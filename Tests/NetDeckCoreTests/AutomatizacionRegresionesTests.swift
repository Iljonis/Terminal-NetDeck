import Foundation
import Testing
@testable import NetDeckCore

/// La respuesta llega en otra tarea: enviar no pinta salida ni incrementa revision. Evita que una contestación
/// síncrona o el eco de entrada escondan la ausencia de await entre órdenes.
@MainActor
private final class TerminalDiferido: TerminalIO {
    var pantalla: [String]
    var promptRule: PromptRule?
    var revision = 0
    var enviados: [String] = []
    var responder: @MainActor (TerminalDiferido, String) async -> Void = { _, _ in }
    private var tareas: [Task<Void, Never>] = []

    init(_ linea: String = "core-01#", regla: PromptRule? = nil) {
        pantalla = [linea]
        promptRule = regla
    }

    var cursorRow: Int { pantalla.count - 1 }
    var cursorLine: String { pantalla.last ?? "" }
    func lines(from row: Int) -> [String] { row <= cursorRow ? Array(pantalla[max(0, row)...]) : [] }

    func send(bytes: [UInt8]) {
        let texto = String(decoding: bytes, as: UTF8.self)
        enviados.append(texto)
        guard texto.hasSuffix("\r") else { return }
        let orden = String(texto.dropLast())
        if !SecretPrompt.asks(cursorLine) { pantalla[pantalla.count - 1] += orden }
        tareas.append(Task { @MainActor in
            await Task.yield()
            await self.responder(self, orden)
        })
    }

    func recibir(_ lineas: [String]) { pantalla += lineas; revision += 1 }
    func sustituir(_ linea: String) { pantalla[pantalla.count - 1] = linea; revision += 1 }
    func fragmento(_ texto: String) { pantalla[pantalla.count - 1] += texto; revision += 1 }
    func terminar() async { for tarea in tareas { await tarea.value } }
}

/// Reloj de las pruebas: las esperas del pegador o de la macro avanzan el tiempo lo pedido y ceden el turno; el equipo
/// de mentira «tarda» cediendo el turno hasta que ese tiempo ha pasado. Así un tope de 1 s son 200 sondeos de 5 ms pase
/// lo que pase en el resto de la suite (con el reloj real, el pool ocupado por otras pruebas retrasaba el despertar de
/// un sleep de 5 ms más de un segundo y el tope vencía sin que el equipo hubiera podido contestar).
final class RelojVirtual: PollClock, @unchecked Sendable {
    private let lock = NSLock()
    private var t = Duration.zero
    func now() -> Duration { lock.withLock { t } }
    func sleep(for duration: Duration) async throws {
        lock.withLock { t += duration }
        await Task.yield()
    }
    /// Lo que tarda el equipo: hasta que las esperas del otro lado lo hayan hecho pasar (con tope de vueltas, por si
    /// el otro lado ya ha terminado). En el hilo principal, como el pegador y la macro: así se turnan de uno en uno (en
    /// otro ejecutor, el pegador agotaba sus sondeos mientras esto saltaba de un lado a otro).
    @MainActor
    func pasar(_ d: Duration) async {
        let fin = now() + d
        for _ in 0..<100_000 where now() < fin { await Task.yield() }
    }
}

@Suite struct PromptRegexRegresionesTests {
    @Test(arguments: ["", " \t ", "Permission den", "Permission denied, please try again.", "Access denied",
                      "Authentication failed", "Login incorrect", "Username:", "login: tu.usuario",
                      "Password", "Verification co", "Verification code:", "% Invalid input detected", "--More--"])
    func reglaQueAceptaVacioNoAutorizaAutenticacion(_ linea: String) throws {
        let regla = try #require(PromptRule(".*"))
        #expect(!PromptRule.isPrompt(linea, custom: regla))
        #expect(!DevicePrompt(sample: "core-01#", custom: regla).matches(linea))
        #expect(PromptRule.isPrompt("core-01#", custom: regla))
        #expect(PromptRule.isPrompt("READY:", custom: PromptRule("^READY:$")))
    }

    @Test(arguments: ["^(a|aa)+$", "^((a)+)+$", "^(?:(a+))+$", "^((a)?)+$", "^([a-z]+){2,}$"])
    func rechazaRetrocesoExplosivo(_ regex: String) {
        #expect(PromptRule.problem(regex) != nil)
        #expect(PromptRule(regex) == nil)
        #expect(MacroStep.text(regex).problem != nil)
    }

    @Test(arguments: [#"^(?:core|edge)-[0-9]+(?:\(config[^)]*\))?[#>]$"#,
                      #"^[()+|]+#$"#, #"^\(a\+\)\+#$"#, #"^(ab)+#$"#])
    func conservaRegexSencillas(_ regex: String) {
        #expect(PromptRule.problem(regex) == nil)
    }

    @Test func presupuestoDeICUCortaTambienLoQueNoRechazaElFiltro() throws {
        // (se compilan directamente: el presupuesto funciona sin depender del filtro estático de PromptRule)
        for regex in ["^(a|aa)+$", "^((a)+)+$", "^a+a+a+a+a+a+$"] {
            let patron = try #require(Pattern(compiling: regex))
            let inicio = ContinuousClock.now
            #expect(!patron.matches(String(repeating: "a", count: 400) + "!"))
            #expect(ContinuousClock.now - inicio < .seconds(1))
        }
        let patron = try #require(Pattern(compiling: #"^([a-z]+)-(\d+)#$"#))
        #expect(patron.matches("core-01#"))
        #expect(patron.group(2, in: "core-01#") == "01")
        #expect(patron.range(in: "core-01#") != nil)
    }
}

@Suite struct MacroIdentificadorRegresionesTests {
    @Test func guardarUUIDRepetidoNoTocaElArchivo() throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("macros-id-\(UUID())")
        AppPaths.ensure(carpeta)
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let url = carpeta.appendingPathComponent("macros.json")
        try SafeFile.write("contenido anterior", to: url)
        let id = UUID()
        let biblioteca = MacroLibrary(macros: [
            Macro(id: id, name: "Primera", steps: [.send("show clock")]),
            Macro(id: id, name: "Segunda", steps: [.send("show users")])
        ])
        #expect(biblioteca.problem == .duplicateID("Segunda"))
        #expect(throws: MacroLibrary.SaveError.self) { try biblioteca.save(to: url) }
        #expect(try SafeFile.read(url) == "contenido anterior")
        #expect(!FileManager.default.fileExists(atPath: url.path + ".anterior"))
    }

    @Test func cargarUUIDRepetidoAvisaAunqueElNombreSeaDistinto() throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("macros-id-\(UUID())")
        AppPaths.ensure(carpeta)
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let url = carpeta.appendingPathComponent("macros.json")
        let id = UUID().uuidString
        let texto = """
        {"version":1,"macros":[
          {"id":"\(id)","nombre":"Primera","pasos":[{"tipo":"enviar","texto":"show clock"}]},
          {"id":"\(id)","nombre":"Segunda","pasos":[{"tipo":"enviar","texto":"show users"}]}
        ]}
        """
        try SafeFile.write(texto, to: url)
        let leida = MacroLibrary.load(from: url)
        #expect(leida.error == nil)
        #expect(leida.library.macros.map(\.name) == ["Primera"])
        #expect(leida.warnings.count == 1)
        #expect(try SafeFile.read(url) == texto)
    }
}

@Suite @MainActor struct MacroAsincronaRegresionesTests {
    private let reloj = RelojVirtual()
    private var reproductor: MacroPlayer {
        var p = MacroPlayer()
        p.clock = reloj
        p.poll = .milliseconds(5)
        p.quiet = .milliseconds(20)
        p.lineTimeout = .seconds(1)
        return p
    }

    private func macro(_ pasos: [MacroStep]) -> Macro { Macro(name: "Prueba", steps: pasos) }

    @Test func dosEnviosEsperanElPromptReal() async {
        let io = TerminalDiferido()
        io.responder = { io, orden in
            if orden == "show clock" { #expect(io.enviados == ["show clock\r"]) }
            io.recibir(["salida", "core-01#"])
        }
        let r = await reproductor.run(macro([.send("show clock"), .send("show users")]), on: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r == MacroReport(sent: 2, total: 2, outcome: .completed))
        #expect(io.enviados == ["show clock\r", "show users\r"])
    }

    @Test func errorDiferidoEntreDosEnvios() async {
        let io = TerminalDiferido()
        io.responder = { io, _ in
            io.recibir(["1", "2", "3", "4", "5", "% Invalid input detected", "core-01#"])
        }
        let r = await reproductor.run(macro([.send("shwo run"), .send("show clock")]), on: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == .deviceError(step: 1, output: "% Invalid input detected"))
        #expect(io.enviados == ["shwo run\r"])
    }

    @Test func otpDiferidoEntreDosEnvios() async {
        let io = TerminalDiferido()
        io.responder = { io, _ in io.recibir(["Verification code:"]) }
        let r = await reproductor.run(macro([.send("login"), .send("show clock")]), on: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == .secretPrompt(step: 2))
        #expect(io.enviados == ["login\r"])
    }

    @Test(arguments: ["error", "otp", "otp-con-salto", "paginador"])
    func textoEsperadoNoOcultaRiesgosEnElMismoBloque(_ riesgo: String) async {
        let io = TerminalDiferido()
        let salida: [String]
        let esperado: MacroReport.Outcome
        switch riesgo {
        case "error":
            salida = ["[OK]", "1", "2", "3", "4", "% Invalid input detected", "core-01#"]
            esperado = .deviceError(step: 2, output: "% Invalid input detected")
        case "otp":
            salida = ["[OK]", "Verification code:"]
            esperado = .secretPrompt(step: 2)
        case "otp-con-salto":
            salida = ["[OK]", "Verification code:", ""]
            esperado = .secretPrompt(step: 2)
        default:
            salida = ["[OK]", "--More--"]
            esperado = .pager(step: 2)
        }
        io.responder = { io, _ in io.recibir(salida) }
        let r = await reproductor.run(macro([.send("show clock"), .text(#"\[OK\]"#, timeout: 1), .send("show users")]),
                                      on: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == esperado)
        #expect(io.enviados == ["show clock\r"])
    }

    @Test func regexDeTextoQueCoincideConElOTPNoLoAcepta() async {
        let io = TerminalDiferido()
        io.responder = { io, _ in io.recibir(["Verification code:"]) }
        let r = await reproductor.run(macro([.send("login"), .text(".*", timeout: 1), .send("show clock")]),
                                      on: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == .secretPrompt(step: 2))
        #expect(io.enviados == ["login\r"])
    }

    @Test func textoIntermedioNoAutorizaElSiguienteEnvio() async {
        let io = TerminalDiferido(regla: PromptRule(".*"))
        io.responder = { io, _ in
            io.recibir(["[OK]", ""])
            await reloj.pasar(.milliseconds(60))             // (más que quiet)
            io.sustituir("Verification code:")
        }
        let r = await reproductor.run(macro([.send("login"), .text(#"\[OK\]"#, timeout: 1), .send("show clock")]),
                                      on: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == .secretPrompt(step: 3))
        #expect(io.enviados == ["login\r"])
    }

    @Test func elUltimoEnvioTambienSeComprueba() async {
        let io = TerminalDiferido()
        io.responder = { io, _ in io.recibir(["Token code:"]) }
        let r = await reproductor.run(macro([.send("login")]), on: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == .secretPrompt(step: 1))
        #expect(io.enviados == ["login\r"])
    }

    @Test func promptSinEnvioPrevioNoEsperaSobreUnSecreto() async {
        let io = TerminalDiferido("Verification code:", regla: PromptRule(".*"))
        let r = await reproductor.run(macro([.prompt(timeout: 1), .send("show clock")]), on: io, abort: AbortSwitch())
        #expect(r.outcome == .secretPrompt(step: 1))
        #expect(io.enviados.isEmpty)
    }

    @Test func sinRespuestaNoPasaAlSegundoEnvio() async {
        let io = TerminalDiferido()
        let r = await reproductor.run(macro([.send("show clock"), .send("show users")]), on: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == .timeout(step: 2))
        #expect(io.enviados == ["show clock\r"])
    }

    @Test func cancelacionDuranteLaEsperaImplicita() async {
        let io = TerminalDiferido()
        let abort = AbortSwitch()
        io.responder = { _, _ in abort.trip() }
        let r = await reproductor.run(macro([.send("show clock"), .send("show users")]), on: io, abort: abort)
        await io.terminar()
        #expect(r.outcome == .aborted)
        #expect(io.enviados == ["show clock\r"])
    }
}

@Suite @MainActor struct PegadoSecretosRegresionesTests {
    private let reloj = RelojVirtual()
    private var pegador: SafePaster {
        var p = SafePaster()
        p.clock = reloj
        p.poll = .milliseconds(5)
        p.quiet = .milliseconds(20)
        p.lineTimeout = .seconds(1)
        return p
    }

    @Test(arguments: ["Verification code:", "Enter passphrase for key '/k':", "Token code:", "Enter PIN:"])
    func nuncaEmpiezaEnUnSecreto(_ peticion: String) async {
        let io = TerminalDiferido(peticion)
        let r = await pegador.paste("show clock", into: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == .passwordPrompt(line: 0))
        #expect(io.enviados.isEmpty)
    }

    @Test func otpDiferidoNoSeAceptaPorSilencio() async {
        let io = TerminalDiferido()
        io.responder = { io, _ in io.recibir(["Verification code:"]) }
        let r = await pegador.paste("login\nshow clock", into: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == .passwordPrompt(line: 1))
        #expect(io.enviados == ["login\r"])
    }

    @Test func otpSeguidoDeUnaFilaVaciaTambienPara() async {
        let io = TerminalDiferido()
        io.responder = { io, _ in io.recibir(["Verification code:", ""]) }
        let r = await pegador.paste("login\nshow clock", into: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == .passwordPrompt(line: 1))
        #expect(io.enviados == ["login\r"])
    }

    @Test func otpQueSobrescribeLaMismaFila() async {
        let io = TerminalDiferido()
        io.responder = { io, _ in io.sustituir("Verification code:") }
        let r = await pegador.paste("login\nshow clock", into: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == .passwordPrompt(line: 1))
        #expect(io.enviados == ["login\r"])
    }

    @Test func otpFragmentadoConReglaQueAceptaTodo() async {
        let io = TerminalDiferido(regla: PromptRule(".*"))
        io.responder = { io, _ in
            io.recibir([""])
            await reloj.pasar(.milliseconds(40))
            io.fragmento("Verification co")
            await reloj.pasar(.milliseconds(40))             // (cada fragmento supera quiet)
            io.fragmento("de:")
        }
        let r = await pegador.paste("login\nshow clock", into: io, abort: AbortSwitch())
        await io.terminar()
        #expect(r.outcome == .passwordPrompt(line: 1))
        #expect(io.enviados == ["login\r"])
    }
}

@Suite @MainActor struct GrabacionSecretosRegresionesTests {
    @Test(arguments: ["", "Permission den", "Permission denied", "Username:", "Verification co", "Password:"])
    func filaNuevaConReglaAmpliaNoPermiteGrabarSecretos(_ salida: String) {
        let io = TerminalDiferido("core-01>", regla: PromptRule(".*"))
        let r = MacroRecorder()
        r.feed(Array("\u{1b}[20".utf8), from: io)
        r.feed(Array("0~enable\r".utf8), from: io)
        io.recibir([salida])
        r.feed(Array("S3".utf8), from: io)
        io.recibir(["core-01#"])                            // (la línea empezó siendo insegura: sigue excluida)
        r.feed(Array("cr3t\r\u{1b}[201~".utf8), from: io)
        io.recibir(["core-01#"])
        r.feed(Array("show clock\r".utf8), from: io)
        #expect(r.lines == ["enable", "show clock"])
        #expect(r.skipped == 1)
        #expect(!r.lines.joined().contains("S3cr3t"))
    }

    @Test func tampocoGrabaSiEmpiezaEnUnaFilaVacia() {
        let io = TerminalDiferido("", regla: PromptRule(".*"))
        let r = MacroRecorder()
        r.feed(Array("S3cr3t\r".utf8), from: io)
        #expect(r.lines.isEmpty)
        #expect(r.skipped == 1)
    }
}

@Suite @MainActor struct CredencialesPromptRegresionesTests {
    private func automatismo(_ ledger: CredentialLedger) -> PasswordAutomation {
        let a = PasswordAutomation(mode: .autoType, store: MemoryCredentialStore([.named("AD"): "secreto-demo"]),
                                   ledger: ledger) { _ in
            [CredentialCandidate(ref: .named("AD"), owners: ["tu.usuario"], origin: .sessionNamed)]
        }
        a.settle = .milliseconds(1)
        a.beginCommand("ssh tu.usuario@192.0.2.1")
        return a
    }

    @Test func vacioYRechazoFragmentadoNoConfirmanCredenciales() async {
        let io = TerminalDiferido("tu.usuario@192.0.2.1's password:", regla: PromptRule(".*"))
        let ledger = CredentialLedger()
        let a = automatismo(ledger)
        let gate = AutomationGate()
        #expect(await a.observe(io, gate: gate) == .typed(.named("AD")))
        io.recibir([""])
        #expect(await a.observe(io, gate: gate) == nil)
        #expect(!a.loggedIn)
        if case .probing = ledger.state(of: .named("AD")) {} else { Issue.record("Se confirmó una fila vacía") }
        io.fragmento("Permission den")
        #expect(await a.observe(io, gate: gate) == nil)
        #expect(!a.loggedIn)
        io.fragmento("ied, please try again.")
        #expect(await a.observe(io, gate: gate) == .failed(.named("AD")))
        #expect(ledger.isBlocked(.named("AD")))
        #expect(!a.loggedIn)
        io.recibir(["tu.usuario@192.0.2.1's password:"])
        #expect(await a.observe(io, gate: gate) == nil)             // (el rechazo terminó aquel contexto)
        a.beginCommand("ssh tu.usuario@192.0.2.1")
        #expect(await a.observe(io, gate: gate) == .manual(.recentlyFailed(.named("AD"))))
        await io.terminar()
        #expect(io.enviados == ["secreto-demo\r"])
    }

    @Test func rechazoEncimaDelPromptTienePrioridad() async {
        let io = TerminalDiferido("tu.usuario@192.0.2.1's password:", regla: PromptRule(".*"))
        let ledger = CredentialLedger()
        let a = automatismo(ledger)
        #expect(await a.observe(io, gate: AutomationGate()) == .typed(.named("AD")))
        io.recibir(["Permission denied", "core-01#"])
        #expect(await a.observe(io, gate: AutomationGate()) == .failed(.named("AD")))
        #expect(ledger.isBlocked(.named("AD")))
        #expect(!a.loggedIn)
        await io.terminar()
    }

    @Test func soloElPromptRealConfirmaTrasUnaFilaVacia() async {
        let io = TerminalDiferido("tu.usuario@192.0.2.1's password:", regla: PromptRule(".*"))
        let ledger = CredentialLedger()
        let a = automatismo(ledger)
        #expect(await a.observe(io, gate: AutomationGate()) == .typed(.named("AD")))
        io.recibir([""])
        #expect(await a.observe(io, gate: AutomationGate()) == nil)
        io.recibir(["core-01#"])
        #expect(await a.observe(io, gate: AutomationGate()) == .confirmed(.named("AD")))
        #expect(a.loggedIn)
        if case .confirmed = ledger.state(of: .named("AD")) {} else { Issue.record("No se confirmó el prompt real") }
        await io.terminar()
    }
}
