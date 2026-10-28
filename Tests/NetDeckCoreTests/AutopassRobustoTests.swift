import Foundation
import Testing
@testable import NetDeckCore

/// La contraseña dentro de la sesión no se pierde en silencio: historial lleno (la fila del cursor deja de crecer), un
/// Esc suelto, el cambio de equipo, un Llavero que no contesta, un corte antes del prompt y un ssh que repregunta tarde.
@MainActor @Suite(.serialized) struct AutopassRobustoTests {
    private let ref = CredentialRef.named("AD")

    private func automation(_ store: CredentialStore, ledger: CredentialLedger = CredentialLedger()) -> PasswordAutomation {
        let a = PasswordAutomation(mode: .autoType, store: store, ledger: ledger) { _ in
            [.init(ref: .named("AD"), owners: ["tu.usuario"], origin: .defaultCredential)]
        }
        a.settle = .milliseconds(1)
        a.beginCommand("ssh tu.usuario@core-01")
        return a
    }

    // MARK: - filas absolutas

    @Test func elSolapeEsElDesplazamientoMasPequeno() {
        #expect(BufferRows.overlap(suffixOf: [1, 2, 3, 4], prefixOf: [3, 4, 5]) == 2)
        #expect(BufferRows.overlap(suffixOf: [1, 2, 3], prefixOf: [1, 2, 3, 4]) == 3)
        #expect(BufferRows.overlap(suffixOf: [1, 2], prefixOf: [7, 8]) == 0)
        #expect(BufferRows.overlap(suffixOf: [5, 5, 5], prefixOf: [5, 5, 5, 6]) == 3)
    }

    @Test func conElHistorialLlenoLaFilaSigueCreciendo() {
        let t = TerminalAcotado(capacidad: 50, pantalla: 5)
        for i in 0..<60 { t.escribir("línea \(i)") }
        var filas = [t.cursorRow]
        for i in 60..<70 { t.escribir("línea \(i)"); filas.append(t.cursorRow) }
        #expect(t.lineas.count == 50)                                   // (lleno: no crece)
        #expect(filas == Array(filas[0]...(filas[0] + 10)))            // (una fila más por línea)
        #expect(t.lines(from: t.cursorRow - 1) == ["línea 68", "línea 69"])
        #expect(t.lines(from: 0).first == "línea 20")                   // (las expulsadas se omiten)
        // (sin poder casar —historial borrado—: salta hacia delante, nunca atrás)
        let antes = t.cursorRow
        t.borrarHistorial()
        #expect(t.cursorRow > antes)
    }

    // MARK: - recolector de órdenes

    @Test func conLaFilaFijaYLaRevisionCreciendoNoSeQuedaEnmascarado() {
        let io = FilaFija("tu.usuario@bastion:~$ "), r = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
        r.feed(Array("ssh core-01\r".utf8), from: io)
        #expect(r.takeLines() == ["ssh core-01"])
        // (el equipo corta y vuelve el prompt del salto en la misma fila: ha salido algo)
        io.revision += 3
        r.feed(Array("ssh core-02\r".utf8), from: io)
        #expect(r.takeLines() == ["ssh core-02"] && r.lastDrop == nil)
        // (sin salida entre medias —un pegado de dos líneas— la segunda sí se enmascara)
        io.revision += 1
        r.feed(Array("ssh core-03\rssh core-04\r".utf8), from: io)
        #expect(r.takeLines() == ["ssh core-03"] && r.lastDrop == "misma-fila")
    }

    @Test func unEscSueltoNoSeComeLaSiguienteTecla() {
        let io = FilaFija("tu.usuario@bastion:~$ "), r = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
        r.feed([0x1B], from: io)
        r.feed(Array("s".utf8), from: io)
        io.line = "tu.usuario@bastion:~$ ssh core-04"                  // (el eco de lo tecleado)
        r.feed(Array("sh core-04\r".utf8), from: io)
        #expect(r.takeLines() == ["ssh core-04"])
        // (Alt+tecla en el mismo trozo: tampoco se pierde)
        io.line = "tu.usuario@bastion:~$ "
        io.row += 1
        r.feed([0x1B] + Array("s".utf8), from: io)
        io.line = "tu.usuario@bastion:~$ ssh core-05"
        r.feed(Array("sh core-05\r".utf8), from: io)
        #expect(r.takeLines() == ["ssh core-05"])
    }

    @Test func alCambiarDeEquipoSeOlvidaLaLineaDeAntes() {
        let io = FilaFija("tu.usuario@bastion:~$ "), r = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
        r.feed(Array("ssh core-01\r".utf8), from: io)
        #expect(r.takeLines() == ["ssh core-01"])
        r.feed(Array("ssh co".utf8), from: io)                         // (a medias, en el mismo instante)
        r.resetLine()
        r.feed(Array("ssh core-05\r".utf8), from: io)
        #expect(r.takeLines() == ["ssh core-05"])
    }

    @Test func cadaDescarteDiceSuMotivo() {
        let io = FilaFija("tu.usuario@bastion:~$ "), r = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
        r.feed(Array("show version\r".utf8), from: io)
        #expect(r.takeLines() == ["show version"] && r.lastDrop == nil)  // (otra orden: cierra el contexto)
        io.revision += 1
        r.feed(Array("ls\t\r".utf8), from: io)
        #expect(r.lastDrop == "no-conexion")
        io.revision += 1
        io.line = "Password:"
        r.feed(Array("secreto\r".utf8), from: io)
        #expect(r.lastDrop == "enmascarada-secreto")
        io.revision += 1
        io.line = "Last login: ayer"
        r.feed(Array("ssh core-01\r".utf8), from: io)
        #expect(r.lastDrop == "sin-prompt")
    }

    // MARK: - repregunta con el historial lleno

    @Test func conLaFilaFijaDetectaLaRepregunta() async {
        let ledger = CredentialLedger(), a = automation(MemoryCredentialStore([ref: "secreto-demo"]), ledger: ledger)
        defer { a.cancelCommand() }
        let io = FilaFija("tu.usuario@core-01's password:"), gate = AutomationGate()
        #expect(await a.observe(io, gate: gate) == .typed(ref))
        io.line = ""; io.revision += 1                                  // (el salto de línea tras la contraseña)
        #expect(await a.observe(io, gate: gate) == nil)
        io.line = "tu.usuario@core-01's password:"; io.revision += 1    // (otra vez, en la misma fila)
        #expect(await a.observe(io, gate: gate) == .failed(ref))
        #expect(io.sent == ["secreto-demo\r"] && ledger.isBlocked(ref))
    }

    @Test func sinSalirDeLaPeticionNoEsUnaRepregunta() async {
        let ledger = CredentialLedger(), a = automation(MemoryCredentialStore([ref: "secreto-demo"]), ledger: ledger)
        defer { a.cancelCommand() }
        let io = FilaFija("tu.usuario@core-01's password:"), gate = AutomationGate()
        #expect(await a.observe(io, gate: gate) == .typed(ref))
        io.revision += 1                                                // (un trozo de salida que no mueve nada)
        #expect(await a.observe(io, gate: gate) == nil)
        #expect(io.sent.count == 1 && !ledger.isBlocked(ref))
    }

    @Test func conElHistorialLlenoDeVerdadTambien() async {
        let ledger = CredentialLedger(), a = automation(MemoryCredentialStore([ref: "secreto-demo"]), ledger: ledger)
        defer { a.cancelCommand() }
        let io = TerminalAcotado(capacidad: 30, pantalla: 5), gate = AutomationGate()
        for i in 0..<40 { io.escribir("línea \(i)") }
        io.escribir("tu.usuario@core-01's password:")
        #expect(await a.observe(io, gate: gate) == .typed(ref))
        io.escribir("Permission denied, please try again.")
        io.escribir("tu.usuario@core-01's password:")
        #expect(await a.observe(io, gate: gate) == .failed(ref))
        #expect(io.sent == ["secreto-demo\r"])
    }

    // MARK: - Llavero

    @Test func unErrorDelLlaveroNoEsUnaAusencia() async {
        let roto = LlaveroRoto()
        #expect(await roto.readInBackground(ref) == .failed)
        #expect(await MemoryCredentialStore().readInBackground(ref) == .missing)
        #expect(await MemoryCredentialStore([ref: "x"]).readInBackground(ref) == .found("x"))
        let c = CredentialCandidate(ref: ref, owners: ["tu.usuario"], origin: .defaultCredential)
        let r = await roto.availabilityInBackground([c])
        #expect(r.available.isEmpty && r.failed)
        let ok = await MemoryCredentialStore().availabilityInBackground([c])
        #expect(ok.available.isEmpty && !ok.failed)
        #expect(await roto.passwordInBackground(for: ref) == nil)       // (los de siempre, igual)
    }

    @Test func siNoSePuedeMirarElLlaveroSeAvisaYSeReintenta() async {
        let roto = LlaveroRoto(), a = automation(roto), gate = AutomationGate()
        defer { a.cancelCommand() }
        let io = FilaFija("tu.usuario@core-01's password:")
        #expect(await a.observe(io, gate: gate) == .manual(.keychainUnavailable))
        #expect(await a.observe(io, gate: gate) == .manual(.keychainUnavailable))   // (no queda como atendida)
        #expect(roto.consultas == 2 && io.sent.isEmpty)
    }

    @Test func siNoSePuedeLeerLaContrasenaSeAvisaYSeSueltaLaReserva() async {
        let roto = LlaveroRoto(existe: true), ledger = CredentialLedger(), a = automation(roto, ledger: ledger)
        defer { a.cancelCommand() }
        let io = FilaFija("tu.usuario@core-01's password:"), gate = AutomationGate()
        #expect(await a.observe(io, gate: gate) == .manual(.keychainUnavailable))
        #expect(ledger.state(of: ref) == nil && io.sent.isEmpty)
        #expect(await a.observe(io, gate: gate) == .manual(.keychainUnavailable))
        #expect(roto.lecturas == 2)
    }

    @Test func elAskpassDiceQueElLlaveroNoContestaYTeLaPide() throws {
        for existe in [false, true] {
            let t = try Askpass1(store: LlaveroRoto(existe: existe))
            #expect(t.ask("tu.usuario@192.0.2.11's password:") == 1)  // (te la pide; aquí, Esc)
            #expect(t.ui.messages.contains { $0.contains("no se ha podido leer el Llavero") })
            #expect(!t.ui.messages.contains { $0.contains("no hay ninguna guardada") })
            #expect(t.answers.isEmpty && t.ui.secretReads == [true])
        }
    }

    // MARK: - corte antes del prompt

    @Test func unCorteAntesDelPromptNoConfirmaNiFalla() async {
        let ledger = CredentialLedger(), a = automation(MemoryCredentialStore([ref: "secreto-demo"]), ledger: ledger)
        defer { a.cancelCommand() }
        let io = FakeTerminal(["tu.usuario@bastion:~$ ssh tu.usuario@core-01", "tu.usuario@core-01's password:"]) { _ in
            ["Connection closed by 192.0.2.11 port 22", "tu.usuario@bastion:~$ "]
        }
        let gate = AutomationGate()
        #expect(await a.observe(io, gate: gate) == .typed(ref))
        #expect(await a.observe(io, gate: gate) == nil)
        #expect(ledger.state(of: ref) == nil && !ledger.isBlocked(ref))
        // (sin corte, vuelve a confirmarse como siempre)
        let b = automation(MemoryCredentialStore([ref: "secreto-demo"]), ledger: ledger)
        defer { b.cancelCommand() }
        let ok = FakeTerminal(["tu.usuario@core-01's password:"]) { _ in ["core-01#"] }
        #expect(await b.observe(ok, gate: gate) == .typed(ref))
        #expect(await b.observe(ok, gate: gate) == .confirmed(ref))
    }

    // MARK: - askpass

    @Test func elMismoSshNoRecibeOtraVezLaGuardadaPasadosDosMinutos() throws {
        let t = try Askpass1(store: MemoryCredentialStore([.named("clave-a"): "rechazada"]))
        #expect(t.ask("tu.usuario@192.0.2.11's password:") == 0)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-300)], ofItemAtPath: t.state.path)
        #expect(t.ask("tu.usuario@192.0.2.11's password:") == 1)      // (te la pide; aquí, Esc)
        #expect(t.answers == ["rechazada"] && t.ui.secretReads == [true])
        #expect(t.ui.messages.contains { $0.contains("no ha funcionado") })
    }

    @Test func laPurgaNoBorraElEstadoDeUnSshVivo() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("estados-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let vivo = dir.appendingPathComponent("ndapp-askpass.\(UUID().uuidString).4242")
        let muerto = dir.appendingPathComponent("ndapp-askpass.\(UUID().uuidString).4343")
        let viejo = dir.appendingPathComponent("ndapp-askpass.\(UUID().uuidString).4242.x")
        let reciente = dir.appendingPathComponent("ndapp-askpass.\(UUID().uuidString).4444")
        for f in [vivo, muerto, viejo, reciente] { try Data("@core-01\tnamed\tAD\n".utf8).write(to: f) }
        for f in [vivo, muerto] { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-900)], ofItemAtPath: f.path) }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-2 * 24 * 3600)], ofItemAtPath: viejo.path)
        Askpass.purgeStates(in: dir) { $0 == 4242 }
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: vivo.path) && fm.fileExists(atPath: reciente.path))
        #expect(!fm.fileExists(atPath: muerto.path) && !fm.fileExists(atPath: viejo.path))
    }
}

// MARK: - dobles

/// Un terminal cuya fila del cursor no se mueve (el historial lleno visto con filas locales): sólo cambian la línea
/// del cursor y la revisión.
@MainActor
private final class FilaFija: TerminalIO {
    var line: String
    var row = 99
    var revision = 0
    var sent: [String] = []

    init(_ line: String) { self.line = line }

    func send(bytes: [UInt8]) { sent.append(String(decoding: bytes, as: UTF8.self)) }
    var cursorRow: Int { row }
    var cursorLine: String { line }
    func lines(from r: Int) -> [String] { r <= row ? [line] : [] }
}

/// Como SwiftTerm con el historial lleno: el búfer no pasa de `capacidad` líneas y las de arriba se expulsan; las
/// filas absolutas salen de `BufferRows`, como en la pestaña.
@MainActor
private final class TerminalAcotado: TerminalIO {
    private(set) var lineas: [String] = []
    let capacidad: Int, pantalla: Int
    var revision = 0
    var sent: [String] = []
    private var filas = BufferRows()

    init(capacidad: Int, pantalla: Int) {
        self.capacidad = capacidad
        self.pantalla = pantalla
    }

    /// Una línea nueva del equipo (la del cursor pasa a ser ésta).
    func escribir(_ texto: String) {
        lineas.append(texto)
        if lineas.count > capacidad { lineas.removeFirst(lineas.count - capacidad) }
        revision += 1
        filas.update(lineas, screenRows: pantalla)
    }

    func borrarHistorial() {
        lineas = Array(lineas.suffix(pantalla))
        revision += 1
        filas.update(lineas, screenRows: pantalla)
    }

    func send(bytes: [UInt8]) { sent.append(String(decoding: bytes, as: UTF8.self)) }
    var cursorRow: Int { filas.absolute(lineas.count - 1) }
    var cursorLine: String { lineas.last ?? "" }
    func lines(from row: Int) -> [String] {
        guard row <= cursorRow, !lineas.isEmpty else { return [] }
        return Array(lineas[max(0, filas.local(row))...])
    }
}

/// Un Llavero que no contesta: comprobar falla (o dice que está, con `existe`) y leer, siempre falla.
private final class LlaveroRoto: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private let existe: Bool
    private var consultadas = 0, leidas = 0

    init(existe: Bool = false) { self.existe = existe }

    var consultas: Int { lock.withLock { consultadas } }
    var lecturas: Int { lock.withLock { leidas } }

    func exists(_ ref: CredentialRef) throws -> Bool {
        lock.withLock { consultadas += 1 }
        if existe { return true }
        throw KeychainError(message: "interacción no permitida")
    }
    func contains(_ ref: CredentialRef) -> Bool { (try? exists(ref)) ?? false }
    func password(for ref: CredentialRef) throws -> String? {
        lock.withLock { leidas += 1 }
        throw KeychainError(message: "no contesta")
    }
    func save(_ password: String, for ref: CredentialRef) throws { throw KeychainError(message: "no contesta") }
    func delete(_ ref: CredentialRef) throws {}
    func accounts(in service: CredentialRef.Service) throws -> [String] { [] }
}

/// El askpass de una sesión con su clave propia, con el Llavero que se le dé.
@MainActor
private final class Askpass1 {
    let manager: SessionManager
    let store: CredentialStore
    let ledger = CredentialLedger()
    let directory: URL
    let ui = Pantalla()
    var environment: [String: String]
    var answers: [String] = []
    var state: URL { directory.appendingPathComponent("estado") }

    init(store: CredentialStore) throws {
        let a = SessionProfile(name: "core-01", hostName: "192.0.2.11", user: "tu.usuario", namedCredential: "clave-a")
        manager = SessionManager(profiles: [a])
        let route = try manager.route(to: a)
        self.store = store
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("askpass-robusto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        environment = Askpass.environment(executable: "/x", configPath: nil, session: UUID(), profile: route.sessionName, route: route)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func ask(_ question: String) -> Int32 {
        Askpass.respond(question: question, environment: environment, manager: manager, store: store, ledger: ledger,
                        tty: ui, state: state, directory: directory) {
            self.answers.append($0); return 0
        }
    }
}

private final class Pantalla: AskpassUI {
    var responses: [String?] = []
    var messages: [String] = []
    var secretReads: [Bool] = []
    func say(_ s: String) { messages.append(s) }
    func read(secret: Bool) -> String? { secretReads.append(secret); return responses.isEmpty ? nil : responses.removeFirst() }
    func yesNo(_ question: String, default d: Bool) -> Bool? { false }
}
