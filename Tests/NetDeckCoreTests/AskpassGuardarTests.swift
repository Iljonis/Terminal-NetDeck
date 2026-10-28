import Foundation
import Security
import Testing
@testable import NetDeckCore

/// Guardar la contraseña desde el askpass (Intro = sí), las teclas de la pestaña, el Llavero que «sale bien» sin
/// guardar y qué líneas «[NetDeck]» son secretas.
@Suite(.serialized) struct AskpassGuardarTests {
    private func asker(_ ui: AskpassUI, named: String?, store: CredentialStore, state: URL) -> Askpass.Asker {
        Askpass.Asker(tty: ui, account: "tu.usuario@core-01", user: "tu.usuario", host: "core-01", named: named,
                      store: store, ledger: CredentialLedger(), state: state, session: nil, reply: { _ in 0 })
    }

    private func estado() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("askpass-guardar-\(UUID().uuidString)")
    }

    // MARK: - A: Intro = guardar

    @Test func introGuardaEnLasDosPreguntas() throws {
        for named in ["AD", nil] {
            let store = MemoryCredentialStore(), ui = Teclas(["nueva"], respuesta: .intro), state = estado()
            defer { try? FileManager.default.removeItem(at: state) }
            #expect(asker(ui, named: named, store: store, state: state).user(failed: nil) == 0)
            let ref = named.map(CredentialRef.named) ?? .device("tu.usuario", "core-01")
            #expect(try store.password(for: ref) == "nueva")
            #expect(ui.defaults == [true])
            #expect(ui.messages.contains { $0.contains("guardada ✓") })
            #expect(!ui.questions.contains { $0.contains("sustituye") })
        }
    }

    @Test func siYaExisteLaPreguntaLoDiceYNoSiempreDiceNoGuardada() throws {
        let store = MemoryCredentialStore([.named("AD"): "vieja"]), state = estado()
        defer { try? FileManager.default.removeItem(at: state) }
        let ui = Teclas(["nueva"], respuesta: .no)
        #expect(asker(ui, named: "AD", store: store, state: state).user(failed: nil) == 0)
        #expect(ui.questions.first?.hasSuffix("(sustituye la guardada)") == true)
        #expect(try store.password(for: .named("AD")) == "vieja")
        #expect(ui.messages.contains { $0.contains("no guardada") })
    }

    @Test func ctrlCEnLaPreguntaCancelaLaAutenticacion() throws {
        let store = MemoryCredentialStore(), state = estado()
        defer { try? FileManager.default.removeItem(at: state) }
        var replied: [String] = []
        let ui = Teclas(["nueva"], respuesta: .ctrlC)
        let a = Askpass.Asker(tty: ui, account: "tu.usuario@core-01", user: "tu.usuario", host: "core-01", named: "AD",
                              store: store, ledger: CredentialLedger(), state: state, session: nil,
                              reply: { replied.append($0); return 0 })
        #expect(a.user(failed: nil) == 1)
        #expect(replied.isEmpty && !store.contains(.named("AD")))
    }

    @Test func siElLlaveroNoLaAceptaLoDiceSinSuSalida() throws {
        let ui = Teclas(["nueva"], respuesta: .intro), state = estado()
        defer { try? FileManager.default.removeItem(at: state) }
        let store = KeychainStore(run: { _, _ in (0, "", "security> add-generic-password -w \"nueva\": error") },
                                  lookup: { _ in errSecItemNotFound })
        #expect(asker(ui, named: "AD", store: store, state: state).user(failed: nil) == 0)
        #expect(ui.messages.contains { $0.contains("no guardada") })
        #expect(!ui.messages.joined().contains("nueva"))
    }

    // MARK: - B / I: teclas de la pestaña

    private func leer(_ bytes: [UInt8]) -> (TTYLine, [UInt8]) {
        var queue = bytes, back: [UInt8] = []
        let r = TTYLine.read(secret: true, next: { _ in queue.isEmpty ? nil : queue.removeFirst() },
                             unread: { back.append($0) }, echo: { _ in })
        return (r, back + queue)
    }

    @Test func introsEscYCtrlC() {
        #expect(leer(Array("abc".utf8) + [0x1B, 0x4F, 0x4D]).0 == .line("abc"))      // (Intro del teclado numérico)
        #expect(leer(Array("abc".utf8) + [0x1B, 13]).0 == .line("abc"))              // (⌥+Intro)
        #expect(leer(Array("ab".utf8) + [3]).0 == .interrupt)
        #expect(leer([0x1B]).0 == .escape)
        #expect(leer([0x1B, 0x5B, 0x41] + Array("x\r".utf8)).0 == .line("x"))        // (las flechas se ignoran)
        #expect(leer(Array("ab".utf8)).0 == .closed)
    }

    @Test func unCrLfPegadoEsUnSoloIntro() {
        let (r, resto) = leer(Array("clave\r\n".utf8))
        #expect(r == .line("clave") && resto.isEmpty)
        let (r2, resto2) = leer(Array("clave\rs\r".utf8))
        #expect(r2 == .line("clave") && resto2 == Array("s\r".utf8))
    }

    /// Un CR+LF pegado que llega partido: el LF tardío no contesta (y guarda) solo; lo que sigue llegando del pegado
    /// se tira antes de preguntar.
    @Test func elTerminadorQueLlegaTardeNoContesta() {
        var queue = Array("\nn\r".utf8)
        let r = TTYLine.read(secret: false, skipLeadingLF: true, next: { _ in queue.isEmpty ? nil : queue.removeFirst() },
                             unread: { _ in }, echo: { _ in })
        #expect(r == .line("n"))
        var cola = Array("\r\r\n".utf8)
        #expect(TTYLine.drain { _ in cola.isEmpty ? nil : cola.removeFirst() } == 3 && cola.isEmpty)
        // (sin CR antes, un LF es un Intro de verdad)
        var otra = Array("\n".utf8)
        #expect(TTYLine.read(secret: false, next: { _ in otra.isEmpty ? nil : otra.removeFirst() }, unread: { _ in },
                             echo: { _ in }) == .line(""))
    }

    /// Sin pestaña (SFTP) el askpass no puede enseñar si la guardó sin parar a ssh: lo apunta y la app lo dice.
    @Test func sinPestanaElResultadoQuedaApuntadoParaLaApp() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("guardado-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for ventana in [true, false] {
            let session = UUID(), store = MemoryCredentialStore(), state = estado()
            defer { try? FileManager.default.removeItem(at: state) }
            let ui = Teclas(["nueva"], respuesta: .intro)
            ui.ventana = ventana
            let a = Askpass.Asker(tty: ui, account: "tu.usuario@core-01", user: "tu.usuario", host: "core-01", named: "AD",
                                  store: store, ledger: CredentialLedger(), state: state, session: session.uuidString,
                                  directory: dir, reply: { _ in 0 })
            #expect(a.user(failed: nil) == 0)
            let saved = Askpass.takeSaved(session: session, directory: dir)
            #expect(saved.map(\.ref) == (ventana ? [.named("AD")] : []) && saved.allSatisfy(\.ok))
            #expect(Askpass.takeSaved(session: session, directory: dir).isEmpty)      // (se borra al leerlo)
            let texto = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .compactMap { try? String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }.joined()
            #expect(!texto.contains("nueva"))                                         // (nunca la contraseña)
        }
    }

    // MARK: - D: la pregunta del askpass no es otra oferta de guardar

    @Test func laPreguntaDelAskpassNoCreaCandidata() {
        var t = TypedPassword()
        t.feed(Array("buena\r".utf8), cursorLine: "[NetDeck] tu.usuario@core-01's password: ", row: 1, above: [])
        #expect(t.candidate == nil)
        t.feed(Array("buena\r".utf8), cursorLine: "tu.usuario@core-01's password: ", row: 2, above: [])
        #expect(t.candidate?.account == "tu.usuario@core-01")
    }

    // MARK: - F / J: el Llavero

    @Test func unGuardadoQueSaleBienSinGuardarEsUnError() {
        let ref = CredentialRef.named("AD")
        let mudo = KeychainStore(run: { _, _ in (0, "", "") }, lookup: { _ in errSecItemNotFound })
        #expect(throws: KeychainError.self) { try mudo.save("secreto-demo", for: ref) }
        #expect(throws: KeychainError.self) { try mudo.create("secreto-demo", for: ref) }
        let bien = KeychainStore(run: { _, _ in (0, "", "") }, lookup: { _ in errSecSuccess })
        #expect(throws: Never.self) { try bien.save("secreto-demo", for: ref) }
        // (el error nunca lleva lo que dice security: podría repetir la orden con la contraseña)
        let eco = KeychainStore(run: { _, _ in (0, "", "error: \"secreto-demo\"") }, lookup: { _ in errSecSuccess })
        do { try eco.save("secreto-demo", for: ref); Issue.record("debía fallar") } catch {
            #expect(!error.localizedDescription.contains("secreto-demo"))
        }
    }

    @Test func unaContrasenaQueNoCabeSeRechazaSinLlamarASecurity() {
        let llamado = Bandera()
        let store = KeychainStore(run: { _, _ in llamado.marcar(); return (0, "", "") }, lookup: { _ in errSecSuccess })
        let larga = String(repeating: "x", count: CredentialValidation.maxPassword + 1)
        #expect(throws: KeychainError.self) { try store.save(larga, for: .named("AD")) }
        #expect(!llamado.marcada)
        // (escapada cuenta: 600 comillas son 1200 bytes)
        #expect(throws: KeychainError.self) { try CredentialValidation.validate(String(repeating: "\"", count: 600), for: .named("AD")) }
        #expect(throws: Never.self) { try CredentialValidation.validate(String(repeating: "x", count: 1000), for: .named("AD")) }
    }

    // MARK: - G: qué líneas del askpass son secretas

    @Test func soloLasPreguntasSecretasDelAskpass() {
        #expect(SecretPrompt.asks("[NetDeck] tu.usuario@core-01's password: "))
        #expect(SecretPrompt.asks("[NetDeck] Enter passphrase for key '/x':"))
        for aviso in ["[NetDeck] ¿Guardarla como «AD»? [S/n] (Esc = no)", "[NetDeck] guardada ✓", "[NetDeck] Esc = cancelar",
                      "[NetDeck] no guardada", "[NetDeck]"] {
            #expect(!SecretPrompt.asks(aviso), "«\(aviso)»")
            #expect(!PromptRule.isPrompt(aviso, custom: nil), "«\(aviso)»")      // (tampoco es un prompt)
        }
        #expect(SecretPrompt.asks("Enter passphrase for key '/x':") && SecretPrompt.asks("Password:"))
    }

    // MARK: - H

    @Test func losTestsNoEscribenEnTuCarpeta() {
        #expect(AppPaths.underTests)
        #expect(AppPaths.home.path != FileManager.default.homeDirectoryForCurrentUser.path)
    }
}

/// Teclea la contraseña y contesta a «¿guardarla?» con Intro, «n» o Ctrl+C.
private final class Teclas: AskpassUI {
    enum Respuesta { case intro, no, ctrlC }
    private var textos: [String]
    let respuesta: Respuesta
    var ventana = false
    var reportsSaved: Bool { ventana }
    var messages: [String] = [], questions: [String] = [], defaults: [Bool] = []
    init(_ textos: [String], respuesta: Respuesta) { self.textos = textos; self.respuesta = respuesta }
    func say(_ s: String) { messages.append(s) }
    func read(secret: Bool) -> String? { textos.isEmpty ? nil : textos.removeFirst() }
    func yesNo(_ question: String, default d: Bool) -> Bool? {
        questions.append(question); defaults.append(d)
        switch respuesta {
        case .intro: return d
        case .no: return false
        case .ctrlC: return nil
        }
    }
}

private final class Bandera: @unchecked Sendable {
    private let lock = NSLock()
    private var valor = false
    func marcar() { lock.withLock { valor = true } }
    var marcada: Bool { lock.withLock { valor } }
}
