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

    /// Con el historial lleno la fila absoluta sigue avanzando: la orden siguiente no se queda enmascarada.
    @Test func conElHistorialLlenoElRecolectorNoSeQuedaEnmascarado() {
        let io = TerminalAcotado(capacidad: 30, pantalla: 5), r = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
        for i in 0..<40 { io.escribir("línea \(i)") }
        io.escribir("tu.usuario@bastion:~$ ")
        r.feed(Array("ssh core-01\r".utf8), from: io)
        #expect(r.takeLines() == ["ssh core-01"])
        // (el equipo corta y vuelve el prompt del salto)
        io.escribir("Connection to core-01 closed.")
        io.escribir("tu.usuario@bastion:~$ ")
        r.feed(Array("ssh core-02\r".utf8), from: io)
        #expect(r.takeLines() == ["ssh core-02"] && r.lastDrop == nil)
        // (sin respuesta entre medias —un pegado de dos líneas— la segunda sí se enmascara)
        io.escribir("tu.usuario@bastion:~$ ")
        r.feed(Array("ssh core-03\rssh core-04\r".utf8), from: io)
        #expect(r.takeLines() == ["ssh core-03"] && r.lastDrop == "misma-fila")
    }

    /// Un BEL o un color suben la revisión sin que el equipo haya contestado: el secreto de un pegado troceado
    /// «enable⏎secreto⏎» no se graba.
    @Test func unaSalidaSinPromptNoPruebaQueHayaContestado() {
        let io = FakeTerminal(["core-01>"]), r = MacroRecorder()
        r.feed(Array("enable\r".utf8), from: io)
        io.revision += 1                                                // (un BEL, en la misma fila)
        r.feed(Array("S3cr3t\r".utf8), from: io)
        #expect(r.lines == ["enable"] && r.skipped == 1)
    }

    @Test func trasRecolocarElBuferJustoTrasUnIntroSeEnmascara() {
        let io = FilaFija("core-01>"), r = MacroRecorder()
        r.feed(Array("enable\r".utf8), from: io)
        io.row += 1
        r.bufferRealigned()
        r.feed(Array("S3cr3t\r".utf8), from: io)
        #expect(r.lines == ["enable"])
        // (pasado un rato —salir de less y escribir otra orden—, no)
        var reloj = Date()
        let tarde = MacroRecorder()
        tarde.now = { reloj }
        tarde.feed(Array("show clock\r".utf8), from: io)
        io.row += 1
        reloj += 10
        tarde.bufferRealigned()
        tarde.feed(Array("show users\r".utf8), from: io)
        #expect(tarde.lines == ["show clock", "show users"])
    }

    /// «clear⏎» o «tmux attach⏎» recolocan el búfer justo tras el Intro; la orden de un minuto después sí se mira (la
    /// marca caduca): antes se descartaba como «misma-fila», sin aviso.
    @Test func laMarcaDeRecolocadoCaduca() {
        var reloj = Date()
        let io = FilaFija("tu.usuario@bastion:~$ "), r = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
        r.now = { reloj }
        r.feed(Array("clear\r".utf8), from: io)
        io.row += 1
        r.bufferRealigned()                                             // (justo tras el Intro)
        reloj += 60
        r.feed(Array("ssh core-02\r".utf8), from: io)
        #expect(r.takeLines() == ["clear", "ssh core-02"] && r.lastDrop == nil)
    }

    /// Entrar en la pantalla alternativa (tmux, less) y salir cuentan como recolocar, aunque allí no haya historial:
    /// lo anclado dentro de tmux no lee luego el historial normal.
    @Test func entrarYSalirDeLaPantallaAlternativaRecoloca() {
        let normal = (0..<5).map { "n\($0)" }, tmux = (0..<5).map { "t\($0)" }
        #expect(BufferRows.alternateEvidence(active: tmux, alternate: tmux, screenRows: 5) == true)
        #expect(BufferRows.alternateEvidence(active: normal, alternate: tmux, screenRows: 5) == nil)   // (difieren)
        #expect(BufferRows.alternateEvidence(active: ["", ""], alternate: ["", ""], screenRows: 2) == nil)  // (en blanco)
        #expect(BufferRows.alternateEvidence(active: normal + ["x"], alternate: tmux, screenRows: 5) == false) // (historial)
        var f = BufferRows()
        f.update(normal, screenRows: 5, cursor: 4, layout: [80, 5, 0])
        f.update(tmux, screenRows: 5, cursor: 2, layout: [80, 5, 1])
        #expect(f.resyncs == 1)
        let dentro = f.resync
        f.update(normal, screenRows: 5, cursor: 4, layout: [80, 5, 0])
        #expect(f.resyncs == 2 && f.first(from: dentro) > dentro)
    }

    /// Dentro de tmux con salida continua, una lectura a destiempo (activo ≠ alternativo) o un «clear» que deja la
    /// alternativa en blanco no son pruebas de haber salido: no recolocan ni cancelan el autopass armado.
    @Test func laAlternaEsEstableSinPruebas() {
        var estado = false, f = BufferRows()
        func leer(_ activo: [String], _ alt: [String]) {
            estado = BufferRows.alternateEvidence(active: activo, alternate: alt, screenRows: 5) ?? estado
            f.update(activo, screenRows: 5, cursor: activo.count - 1, layout: [80, 5, estado ? 1 : 0])
        }
        let tmux = (0..<5).map { "t\($0)" }, otro = (0..<5).map { "u\($0)" }, blanco = Array(repeating: "", count: 5)
        leer(tmux, tmux)                                                // (entra: un recolocado)
        let entrar = f.resyncs
        leer(otro, tmux)                                                // (a destiempo: ambiguo)
        leer(otro, otro)
        leer(blanco, blanco)                                            // (clear en screen: ambiguo)
        leer(tmux, tmux)
        #expect(f.resyncs == entrar && estado)
        leer((0..<9).map { "n\($0)" }, tmux)                            // (sale: con historial, sí)
        #expect(f.resyncs == entrar + 1 && !estado)
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
        io.row += 1
        r.feed(Array("ls\t\r".utf8), from: io)
        #expect(r.lastDrop == "no-conexion")
        io.row += 1
        io.line = "Password:"
        r.feed(Array("secreto\r".utf8), from: io)
        #expect(r.lastDrop == "enmascarada-secreto")
        io.row += 1
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

    /// Recolocar el búfer (otro tamaño) no hace que un «Permission denied» viejo cuente como el rechazo de ahora.
    @Test func trasRecolocarElBuferNoSeLeeLoViejo() async {
        let ledger = CredentialLedger(), a = automation(MemoryCredentialStore([ref: "secreto-demo"]), ledger: ledger)
        defer { a.cancelCommand() }
        let io = TerminalAcotado(capacidad: 30, pantalla: 5), gate = AutomationGate()
        for i in 0..<10 { io.escribir("línea \(i)") }
        io.escribir("tu.usuario@core-02: Permission denied (password).")     // (de antes)
        for i in 0..<10 { io.escribir("salida \(i)") }
        io.escribir("tu.usuario@core-01's password:")
        #expect(await a.observe(io, gate: gate) == .typed(ref))
        let antes = io.cursorRow
        io.redimensionar()
        #expect(io.cursorRow > antes && io.lines(from: 0).count == 1)       // (sólo desde el cursor de entonces)
        // (la pestaña suelta la enviada sin confirmarla ni marcarla y la orden deja de armar nada)
        a.bufferRealigned()
        #expect(ledger.state(of: ref) == nil && a.commandTarget == nil)
        io.escribir("tu.usuario@core-02: Permission denied (password).")    // (aunque luego salga otro rechazo)
        #expect(await a.observe(io, gate: gate) == nil)
        #expect(!ledger.isBlocked(ref) && io.sent.count == 1)
    }

    @Test func soloUnSolapeSuficienteCuentaComoElMismoHistorial() {
        var f = BufferRows()
        let viejo = (0..<40).map { "l\($0)" }
        f.update(viejo, screenRows: 5, cursor: 39)
        // (sólo coinciden 3 líneas: no demuestra nada; se da por recolocado)
        f.update(Array(viejo.suffix(3)) + (0..<37).map { "n\($0)" }, screenRows: 5, cursor: 39)
        #expect(f.resyncs == 1 && f.resync == f.base + 39)
        // (desplazado una línea: el mismo historial)
        var g = BufferRows()
        g.update(viejo, screenRows: 5, cursor: 39)
        g.update(Array(viejo.dropFirst()) + ["l40"], screenRows: 5, cursor: 39)
        #expect(g.resyncs == 0 && g.base == 1)
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

    /// Otro tamaño: las líneas se recolocan (aquí, cada una cambia) y no casan con el historial de antes.
    func redimensionar() {
        lineas = lineas.map { $0 + " " }
        revision += 1
        ancho += 1
        filas.update(lineas, screenRows: pantalla, cursor: lineas.count - 1, layout: [ancho, pantalla])
    }
    private var ancho = 80

    func borrarHistorial() {
        lineas = Array(lineas.suffix(pantalla))
        revision += 1
        filas.update(lineas, screenRows: pantalla)
    }

    func send(bytes: [UInt8]) { sent.append(String(decoding: bytes, as: UTF8.self)) }
    var cursorRow: Int { filas.absolute(lineas.count - 1) }
    var cursorLine: String { lineas.last ?? "" }
    func lines(from row: Int) -> [String] {
        let from = filas.first(from: row)
        guard from <= cursorRow, !lineas.isEmpty else { return [] }
        return Array(lineas[max(0, filas.local(from))...])
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
