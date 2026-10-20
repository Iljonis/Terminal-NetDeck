import Foundation
import Testing
@testable import NetDeckCore

@Suite struct MacroFormatTests {
    func tempURL() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("macros-\(UUID().uuidString)", isDirectory: true)
        AppPaths.ensure(d)
        return d.appendingPathComponent("macros.json")
    }

    let sample = Macro(name: "Ver interfaces", confirm: true, steps: [
        .send("terminal length 0"), .prompt(timeout: 10), .send("show ip interface brief"),
        .text(#"core-01[#>]"#, timeout: 30), .pause(1.5),
    ])

    @Test func idaYVuelta() throws {
        let url = tempURL()
        try MacroLibrary(macros: [sample]).save(to: url)
        let r = MacroLibrary.load(from: url)
        #expect(r.error == nil && r.warnings.isEmpty)
        #expect(r.library.macros == [sample])
        #expect(r.library.macros.first?.id == sample.id)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        // (con copia antes de sustituirlo)
        try MacroLibrary(macros: []).save(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path + ".anterior"))
    }

    @Test func sinArchivoVacia() {
        let r = MacroLibrary.load(from: tempURL())
        #expect(r.error == nil && r.library.macros.isEmpty)
    }

    @Test func corruptoNoSePierde() throws {
        let url = tempURL()
        try SafeFile.write("{ esto no es json", to: url)
        let r = MacroLibrary.load(from: url)
        #expect(r.error != nil)
        #expect(r.library.macros.isEmpty)
        #expect(try SafeFile.read(url) == "{ esto no es json")                 // (leer no toca nada)
        try MacroLibrary(macros: [sample]).save(to: url, setAsideUnusable: true)
        #expect(try SafeFile.read(url.appendingPathExtension("ilegible")) == "{ esto no es json")
        #expect(MacroLibrary.load(from: url).library.macros == [sample])
    }

    @Test func versionDesconocida() throws {
        let url = tempURL()
        let text = #"{"version": 7, "macros": [{"nombre": "x", "pasos": [{"tipo": "enviar", "texto": "show clock"}]}]}"#
        try SafeFile.write(text, to: url)
        let r = MacroLibrary.load(from: url)
        #expect(r.error?.contains("7") == true)
        #expect(r.library.macros.isEmpty)
        #expect(try SafeFile.read(url) == text)
    }

    @Test func noUTF8EsError() throws {
        let url = tempURL()
        try Data([0xFF, 0xFE, 0x00, 0x41]).write(to: url)
        #expect(MacroLibrary.load(from: url).error != nil)
    }

    @Test func invalidasSeIgnoranConAviso() throws {
        let url = tempURL()
        let text = """
        {"version": 1, "macros": [
          {"nombre": "buena", "pasos": [{"tipo": "enviar", "texto": "show clock"}, {"tipo": "prompt", "segundos": 5}]},
          {"nombre": "tipo raro", "pasos": [{"tipo": "borrar-todo", "texto": "x"}]},
          {"nombre": "", "pasos": [{"tipo": "enviar", "texto": "show clock"}]},
          {"nombre": "regex", "pasos": [{"tipo": "enviar", "texto": "show run"}, {"tipo": "texto", "texto": "(a+)+$"}]},
          {"nombre": "pausa larga", "pasos": [{"tipo": "enviar", "texto": "show run"}, {"tipo": "pausa", "segundos": 3600}]},
          {"nombre": "control", "pasos": [{"tipo": "enviar", "texto": "show run\\nreload"}]},
          {"nombre": "BUENA", "pasos": [{"tipo": "enviar", "texto": "show version"}]},
          42
        ]}
        """
        try SafeFile.write(text, to: url)
        let r = MacroLibrary.load(from: url)
        #expect(r.error == nil)
        #expect(r.library.macros.map(\.name) == ["buena"])
        #expect(r.warnings.count == 7)
    }

    @Test func noSeGuardaUnaInvalida() {
        let url = tempURL()
        #expect(throws: MacroLibrary.SaveError.self) { try MacroLibrary(macros: [Macro(name: "x", steps: [.send("")])]).save(to: url) }
        let dos = [Macro(name: "a", steps: [.send("show clock")]), Macro(name: " A ", steps: [.send("show clock")])]
        #expect(MacroLibrary(macros: dos).problem == .duplicate("A"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(MacroLibrary(macros: dos).uniqueName("a") == "a 2")
    }

    @Test func grabadasConEsperaEntreLineas() {
        #expect(Macro.recorded(["a", "b"]) == [.send("a"), .prompt(), .send("b"), .prompt()])
        #expect(sample.dangerousLines.isEmpty)
        #expect(Macro(name: "r", steps: [.send("reload")]).dangerousLines == ["reload"])
    }
}

@Suite @MainActor struct MacroRecorderTests {
    func type(_ r: MacroRecorder, _ text: String, _ io: FakeTerminal) {
        for b in Array(text.utf8) { r.feed([b], from: io) }
    }

    @Test func grabaLineasNoTeclas() {
        let io = FakeTerminal(["core-01#"])
        let r = MacroRecorder()
        type(r, "show vresion", io)
        r.feed([0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F], from: io)               // (borrar)
        type(r, "ersion\r", io)
        io.screen += ["Cisco IOS XE Software", "core-01#"]                    // (el equipo contesta)
        type(r, "\r", io)                                                     // (Intro solo: nada)
        type(r, "conf t", io)
        r.feed([3], from: io)                                                 // (Ctrl+C: no se envía)
        io.screen.append("core-01#")
        // (pegado de varias líneas: sólo la primera; las demás podrían ser la respuesta a un «Password:» aún sin pintar)
        r.feed(Array("\u{1b}[200~show clock\r\nshow users\r\u{1b}[201~".utf8), from: io)
        #expect(r.lines == ["show version", "show clock"])
        #expect(r.skipped == 1)
        #expect(r.steps.count == 4)
    }

    @Test func conFlechasSeLeeDeLaPantalla() {
        let io = FakeTerminal(["core-01#"])
        let r = MacroRecorder()
        r.feed([0x1B, 0x5B, 0x41], from: io)                                  // (flecha arriba: historial)
        io.screen[0] = "core-01#show running-config"
        r.feed([13], from: io)
        #expect(r.lines == ["show running-config"])
    }

    /// Nunca un secreto: ni lo tecleado en una petición de contraseña/passphrase/OTP, ni mientras se autentica, ni lo
    /// que escribe la app desde el Llavero (eso va directo al terminal y no pasa por `feed`).
    @Test func nuncaGrabaSecretos() async {
        let io = FakeTerminal(["core-01>"])
        let r = MacroRecorder()
        io.respond = { cmd in cmd == "enable" ? ["Password:"] : ["core-01#"] }
        type(r, "enable\r", io)
        io.sendLine("enable")                                                 // (la vista lo envía)
        type(r, "S3creta!\r", io)                                             // contraseña a mano: no
        io.screen.append("Verification code:")
        type(r, "123456\r", io)                                               // OTP: no
        io.screen.append("Enter passphrase for key '~/.ssh/id_ed25519':")
        type(r, "frase secreta\r", io)                                        // passphrase: no
        io.screen.append("Password: ")
        type(r, "abc", io)
        io.screen[io.screen.count - 1] = "Password: ***"                      // (el equipo pinta asteriscos)
        type(r, "def\r", io)                                                  // empezada en la petición: no
        // la app escribe una del Llavero (botón o automatización): directo al terminal, no por el teclado
        let ledger = CredentialLedger()
        let pw = PasswordAutomation(mode: .autoType, store: MemoryCredentialStore([.named("AD"): "DelLlavero1"]), ledger: ledger) { _ in [] }
        pw.settle = .milliseconds(1)
        io.screen.append("Password:")
        #expect(await pw.typeManually(.named("AD"), into: io) == .typed)
        #expect(io.sent.contains("DelLlavero1\r"))
        io.screen.append("core-01#")
        type(r, "show clock\r", io)
        // autenticándose (aún sin su primer prompt): nada
        r.awaitingAuth = { _ in true }
        type(r, "tu.usuario\r", io)
        r.awaitingAuth = { SecretPrompt.asks($0.cursorLine) }
        #expect(r.lines == ["enable", "show clock"])
        #expect(r.skipped == 5)
        for s in ["S3creta!", "123456", "frase secreta", "abcdef", "DelLlavero1", "tu.usuario"] {
            #expect(!r.lines.contains { $0.contains(s) })
        }
    }
}

@Suite @MainActor struct MacroPlayerTests {
    var fast: MacroPlayer {
        var p = MacroPlayer()
        p.poll = .milliseconds(5)
        p.quiet = .milliseconds(30)
        return p
    }

    func macro(_ steps: [MacroStep]) -> Macro { Macro(name: "m", steps: steps) }

    @Test func esperaPromptYPausa() async {
        let io = FakeTerminal(["core-01#"]) { cmd in ["salida de \(cmd)", "core-01#"] }
        let m = macro([.send("show clock"), .prompt(timeout: 2), .pause(0.1), .send("show users"), .prompt(timeout: 2)])
        let clock = ContinuousClock()
        let t0 = clock.now
        let r = await fast.run(m, on: io, abort: AbortSwitch())
        #expect(r == MacroReport(sent: 2, total: 2, outcome: .completed))
        #expect(io.sent == ["show clock\r", "show users\r"])
        #expect(clock.now - t0 >= .milliseconds(100))
    }

    @Test func esperaTexto() async {
        let io = FakeTerminal(["core-01#"]) { _ in ["Building configuration...", "[OK]", "core-01#"] }
        let r = await fast.run(macro([.send("write memory"), .text(#"^\[OK\]"#, timeout: 2), .send("show clock")]), on: io, abort: AbortSwitch())
        #expect(r.outcome == .completed)
        #expect(io.sent.count == 2)
    }

    @Test func timeoutPorPaso() async {
        let io = FakeTerminal(["core-01#"])                                   // (no contesta nunca)
        let r = await fast.run(macro([.send("show tech"), .prompt(timeout: 1), .send("show clock")]), on: io, abort: AbortSwitch())
        #expect(r == MacroReport(sent: 1, total: 2, outcome: .timeout(step: 2)))
        #expect(io.sent == ["show tech\r"])
    }

    @Test func errorDelEquipoPara() async {
        let io = FakeTerminal(["core-01#"]) { cmd in cmd == "shwo run" ? ["% Invalid input detected at '^' marker.", "core-01#"] : ["core-01#"] }
        let m = macro([.send("shwo run"), .prompt(timeout: 2), .send("show clock"), .prompt()])
        let r = await fast.run(m, on: io, abort: AbortSwitch())
        #expect(r.outcome == .deviceError(step: 2, output: "% Invalid input detected at '^' marker."))
        #expect(io.sent == ["shwo run\r"])
        // (también sin espera entre medias: antes de la siguiente orden)
        let io2 = FakeTerminal(["core-01#"]) { _ in ["% Invalid input detected at '^' marker.", "core-01#"] }
        let r2 = await fast.run(macro([.send("shwo run"), .send("show clock")]), on: io2, abort: AbortSwitch())
        #expect(r2.outcome == .deviceError(step: 1, output: "% Invalid input detected at '^' marker."))
        #expect(io2.sent.count == 1)
    }

    @Test func paginadorPara() async {
        let io = FakeTerminal(["core-01#"]) { _ in ["línea", " --More-- "] }
        let r = await fast.run(macro([.send("show run"), .prompt(timeout: 2), .send("show clock")]), on: io, abort: AbortSwitch())
        #expect(r.outcome == .pager(step: 2))
        #expect(io.sent.count == 1)
    }

    /// Una petición de contraseña a mitad: para y la orden siguiente NO se escribe ahí (iría como contraseña).
    @Test func contraseñaAMitadParaSinEscribirla() async {
        let io = FakeTerminal(["core-01>"]) { cmd in cmd == "enable" ? ["Password:"] : ["core-01#"] }
        let m = macro([.send("show clock"), .prompt(timeout: 2), .send("enable"), .prompt(timeout: 2), .send("show run")])
        let r = await fast.run(m, on: io, abort: AbortSwitch())
        #expect(r.outcome == .secretPrompt(step: 4))
        #expect(io.sent == ["show clock\r", "enable\r"])
        // sin espera entre medias, ni un OTP: tampoco
        let io2 = FakeTerminal(["core-01>"]) { _ in ["Verification code:"] }
        let r2 = await fast.run(macro([.send("login"), .send("show run")]), on: io2, abort: AbortSwitch())
        #expect(r2.outcome == .secretPrompt(step: 2))
        #expect(io2.sent == ["login\r"])
        // ya la piden al empezar: nada
        let io3 = FakeTerminal(["Password:"])
        #expect(await fast.run(macro([.send("show run")]), on: io3, abort: AbortSwitch()).outcome == .secretPrompt(step: 1))
        #expect(io3.sent.isEmpty)
    }

    @Test func peligrosaSinConfirmar() async {
        let io = FakeTerminal(["core-01#"]) { _ in ["core-01#"] }
        let m = macro([.send("show clock"), .prompt(timeout: 2), .send("reload"), .prompt()])
        #expect(await fast.run(m, on: io, abort: AbortSwitch()).outcome == .dangerousNotConfirmed(step: 3, command: "reload"))
        #expect(io.sent == ["show clock\r"])
        var ok = fast
        ok.allowDangerous = true
        #expect(await ok.run(m, on: FakeTerminal(["core-01#"]) { _ in ["core-01#"] }, abort: AbortSwitch()).outcome == .completed)
    }

    @Test func cancelarAlMomento() async {
        let io = FakeTerminal(["core-01#"]) { _ in ["core-01#"] }
        let sw = AbortSwitch()
        let m = macro([.send("show clock"), .pause(30), .send("show users")])
        let t = Task { @MainActor in await fast.run(m, on: io, abort: sw) }
        try? await Task.sleep(for: .milliseconds(50))
        let clock = ContinuousClock()
        let t0 = clock.now
        sw.trip()                                                             // (Esc / Ctrl+C / botón)
        let r = await t.value
        #expect(r.outcome == .aborted)
        #expect(clock.now - t0 < .seconds(10))
        #expect(io.sent == ["show clock\r"])
        // ya cortada antes de empezar: ni un byte
        let io2 = FakeTerminal(["core-01#"])
        #expect(await fast.run(m, on: io2, abort: sw).outcome == .aborted)
        #expect(io2.sent.isEmpty)
    }

    @Test func invalidaNoEnviaNada() async {
        let io = FakeTerminal(["core-01#"])
        let r = await fast.run(macro([.send("show clock"), .pause(999)]), on: io, abort: AbortSwitch())
        guard case .invalid = r.outcome else { Issue.record("\(r)"); return }
        #expect(io.sent.isEmpty)
    }

    @Test func multiExecSoloALasQueAceptan() async {
        let a = FakeTerminal(["core-01#"]) { _ in ["core-01#"] }
        let b = FakeTerminal(["core-02#"]) { _ in ["core-02#"] }
        let c = FakeTerminal(["Password:"])                                   // (autenticándose)
        let g = MultiExecGroup()
        [a, b, c].forEach(g.join)
        let reports = await g.run(macro([.send("show clock"), .prompt(timeout: 2)]), player: fast, abort: AbortSwitch())
        #expect(reports.count == 2 && reports.allSatisfy { $0.outcome == .completed })
        #expect(a.sent == ["show clock\r"] && b.sent == ["show clock\r"] && c.sent.isEmpty)
    }

    /// Cargar macros (al arrancar, importar o restaurar) no ejecuta nada: `load` no recibe ningún terminal y sólo se
    /// reproduce con `MacroPlayer.run` (que la app llama sólo desde una acción del usuario).
    @Test func cargarNoEjecuta() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("macros-\(UUID().uuidString)", isDirectory: true)
        AppPaths.ensure(d)
        let url = d.appendingPathComponent("macros.json")
        try MacroLibrary(macros: [macro([.send("reload"), .prompt()])]).save(to: url)
        let io = FakeTerminal(["core-01#"])
        let g = MultiExecGroup()
        g.join(io)
        g.isActive = true
        for _ in 0..<3 { _ = MacroLibrary.load(from: url) }
        #expect(io.sent.isEmpty)
        // (y el archivo sigue igual: leer no escribe)
        #expect(!FileManager.default.fileExists(atPath: url.path + ".anterior"))
    }
}

/// Varias líneas que llegan de golpe (pegado): sólo la primera se puede comprobar contra la pantalla; las demás pueden
/// ser la respuesta a un «Password:» que el equipo aún no ha tenido tiempo de pintar. No se graban.
@Suite @MainActor struct MacroPegadoTests {
    @Test func pegarOrdenYContraseñaNoGrabaLaContraseña() {
        let io = FakeTerminal(["core-01#"])
        let r = MacroRecorder()
        r.feed(Array("enable\rS3cr3t-pegada\r".utf8), from: io)
        #expect(r.lines == ["enable"])
        #expect(!r.lines.contains { $0.contains("S3cr3t") })
        #expect(r.skipped == 1)
        // (tecleado línea a línea, con el equipo contestando entre medias, sí se graba todo)
        io.screen += ["% Invalid input detected", "core-01#"]
        r.feed(Array("show clock\r".utf8), from: io)
        #expect(r.lines == ["enable", "show clock"])
    }
}


/// El pegado «orden⏎contraseña⏎» llegue en los trozos que llegue (separados, partida la contraseña, partidos los
/// marcadores del pegado): la protección sigue de un trozo al siguiente. Y tras una respuesta segura del equipo (su
/// prompt), las órdenes de verdad se graban.
@Suite @MainActor struct MacroPegadoEnTrozosTests {
    func feed(_ r: MacroRecorder, _ io: FakeTerminal, _ parts: [String]) {
        for p in parts { r.feed(Array(p.utf8), from: io) }
    }

    func check(_ parts: [String], _ what: Comment) {
        let io = FakeTerminal(["core-01>"])
        let r = MacroRecorder()
        feed(r, io, parts)
        #expect(r.lines == ["enable"], what)
        #expect(!r.lines.joined().contains("S3c") && !r.lines.joined().contains("r3t"), what)
        #expect(r.skipped == 1, what)
    }

    @Test func enLlamadasSeparadas() { check(["enable\r", "S3cr3t\r"], "orden y contraseña en dos llamadas") }

    @Test func partidaLaContraseña() {
        check(["enable\rS3c", "r3t\r"], "la contraseña partida")
        check(["enable\r", "S3", "cr", "3t", "\r"], "la contraseña en tres trozos y el Intro aparte")
    }

    @Test func partidosLosMarcadoresDelPegado() {
        check(["\u{1b}[20", "0~enable\rS3", "cr3t\r\u{1b}[2", "01~"], "marcadores del pegado partidos")
        check(["\u{1b}", "[200~enable\r", "S3cr3t\r\u{1b}", "[201~"], "ESC suelta entre trozos")
    }

    @Test func byteAByte() {
        check(Array("\u{1b}[200~enable\rS3cr3t\r\u{1b}[201~").map { String($0) }, "byte a byte")
    }

    /// Tras «enable», el equipo pinta su prompt (no pide nada): lo siguiente es una orden de verdad y se graba, aunque
    /// llegue en trozos y aunque lo de antes acabara con el marcador del pegado.
    @Test func ordenesDeVerdadTrasUnaRespuestaSegura() {
        let io = FakeTerminal(["core-01>"])
        let r = MacroRecorder()
        feed(r, io, ["\u{1b}[200~enable\r\u{1b}[201~"])
        io.screen += ["core-01#"]                                             // (sin contraseña: su prompt)
        feed(r, io, ["show ", "clock\r"])
        io.screen += ["*10:00:00 UTC", "core-01#"]
        feed(r, io, ["\u{1b}[200~show users\r", "\u{1b}[201~"])
        #expect(r.lines == ["enable", "show clock", "show users"])
        #expect(r.skipped == 0)
    }

    /// Lo que hay en la fila nueva no es un prompt (sólo el eco del Intro, o un «Password:» pintado entre trozos): no.
    @Test func sinPromptNoSeGraba() {
        let io = FakeTerminal(["core-01>"])
        let r = MacroRecorder()
        feed(r, io, ["enable\r"])
        io.screen += [""]                                                     // (eco: fila nueva vacía)
        feed(r, io, ["S3cr3t\r"])
        io.screen += ["Password: "]
        feed(r, io, ["Otr4\r"])
        #expect(r.lines == ["enable"])
        #expect(r.skipped == 2)
    }
}

/// Guardar encima de un macros.json ilegible: si la escritura falla, el original vuelve a su sitio y la copia
/// .ilegible de antes sigue intacta; si va bien, el ilegible queda aparte en .ilegible.
@Suite struct MacroGuardadoSeguroTests {
    struct Fallo: Error {}

    @Test func apartarElIlegibleNuncaPierdeNada() throws {
        let dir = AppPaths.ensure(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("macros.json"), aside = url.appendingPathExtension("ilegible")
        try SafeFile.write("{roto nuevo", to: url)
        try SafeFile.write("{roto viejo", to: aside)
        let lib = MacroLibrary(macros: [Macro(name: "Prueba", steps: [.send("show clock")])])
        #expect(throws: Fallo.self) { try lib.save(to: url, setAsideUnusable: true, write: { _, _ in throw Fallo() }) }
        #expect(try SafeFile.read(url) == "{roto nuevo")
        #expect(try SafeFile.read(aside) == "{roto viejo")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["macros.json", "macros.json.ilegible"])
        try lib.save(to: url, setAsideUnusable: true)
        #expect(try SafeFile.read(aside) == "{roto nuevo")
        #expect(MacroLibrary.load(from: url).library.macros.map(\.name) == ["Prueba"])
    }
}
