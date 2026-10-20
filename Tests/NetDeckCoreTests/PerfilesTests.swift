import Foundation
import Testing
@testable import NetDeckCore

/// Perfiles por sesión («# @fuente», «# @tema», «# @scrollback», «# @teclado», «# @prompt»): en el ssh_config de la
/// app, lo que no dicen (o no vale) hereda de Ajustes, y un prompt propio nunca debilita la protección de MultiExec.
@Suite struct PerfilesTests {
    static let texto = """
        # @grupo Core
        Host core-01
            # @desc Núcleo
            # @fuente JetBrains Mono 14
            # @tema neo-tokyo
            # @scrollback 10000
            # @teclado meta retroceso-h
            # @prompt ^core-\\d+(\\([a-z-]+\\))?[#>]$
            # @proyecto despliegue
            HostName 192.0.2.11
            User tu.usuario

        Host core-02
            HostName 192.0.2.12
        """

    @Test @MainActor func conectarSinGuardarAplicaPerfilSinPersistirlo() throws {
        var editable = EditableSession(name: "core-01")
        editable.host = "192.0.2.11"
        editable.terminal.fontSize = 17
        editable.terminal.theme = "papel"
        let route = try SessionManager().route(unsaved: editable)
        #expect(route.sessionName == nil && route.alias == nil)
        #expect(route.transientProfile == editable.terminal)
        let restored = try JSONDecoder().decode(ConnectionRoute.self, from: JSONEncoder().encode(route))
        #expect(restored.transientProfile == nil)
    }

    @Test func idaYVueltaSinPerderNada() {
        let f = SessionFile(text: Self.texto)
        let p = f.sessions[0].terminal
        #expect(p.fontFamily == "JetBrains Mono" && p.fontSize == 14)
        #expect(p.theme == "neo-tokyo" && p.scrollback == 10_000)
        #expect(p.optionAsMeta == true && p.backspaceSendsCtrlH == true)
        #expect(p.prompt == #"^core-\d+(\([a-z-]+\))?[#>]$"#)
        #expect(f.sessions[0].notes == ["@proyecto despliegue"])          // (las notas libres, aparte)
        #expect(f.sessions[1].terminal.isEmpty)
        // (se escribe y se vuelve a leer igual; la sesión sin perfil no gana ninguna anotación)
        let otra = SessionFile(text: f.render())
        #expect(otra.sessions == f.sessions)
        #expect(otra.render() == f.render())
        #expect(!f.render().components(separatedBy: "Host core-02")[1].contains("# @"))
        #expect(f.problems().isEmpty)
        // (y al conectar, el lector de ssh_config ve lo mismo)
        let perfiles = SSHConfigParser().parse(f.render())
        #expect(perfiles.first { $0.name == "core-01" }?.terminal == p)
        #expect(perfiles.first { $0.name == "core-02" }?.terminal.isEmpty == true)
    }

    @Test func soloTamañoOSoloFamilia() {
        var p = TerminalProfile()
        let leida = p.read("fuente", "13", session: "x")
        #expect(leida)
        #expect(p.fontFamily.isEmpty && p.fontSize == 13 && p.annotations.map(\.value) == ["13"])
        p = TerminalProfile()
        p.read("fuente", "Menlo", session: "x")
        #expect(p.fontFamily == "Menlo" && p.fontSize == 0)
        p.read("teclado", "sin-meta", session: "x")
        #expect(p.optionAsMeta == false && p.backspaceSendsCtrlH == nil)
        let ajena = p.read("grupo", "Core", session: "x")
        #expect(!ajena)                                                   // (no es del perfil)
    }

    @Test func vacioHeredaDeAjustes() {
        let e = TerminalProfile().resolved(theme: "papel", fontFamily: "", fontSize: 0, scrollback: 2_500, session: "x",
                                           themeExists: { _ in true }, fontInstalled: { _ in true })
        #expect(e == TerminalProfile.Effective(theme: "papel", fontFamily: "", fontSize: 0, scrollback: 2_500,
                                               optionAsMeta: false, backspaceSendsCtrlH: false, prompt: nil))
        var p = TerminalProfile()
        p.theme = "neo-tokyo"
        p.scrollback = 10_000
        p.prompt = "^core-01#$"
        let s = p.resolved(theme: "papel", fontFamily: "Menlo", fontSize: 12, scrollback: 2_500, session: "x",
                           themeExists: { _ in true }, fontInstalled: { _ in true })
        // (lo que dice la sesión manda; la fuente y el tamaño, que no dice, siguen a Ajustes)
        #expect(s.theme == "neo-tokyo" && s.scrollback == 10_000 && s.prompt?.source == "^core-01#$")
        #expect(s.fontFamily == "Menlo" && s.fontSize == 12)
    }

    /// Un tema que ya no está o una fuente sin instalar: hereda y se apunta en ErrorLog.
    @Test func temaOFuenteQueNoEstan() {
        var p = TerminalProfile()
        p.theme = "tema-borrado"
        p.fontFamily = "Fuente Inexistente"
        let e = p.resolved(theme: "papel", fontFamily: "", fontSize: 0, scrollback: 2_500, session: "perfil-sin-tema",
                           themeExists: { $0 == "papel" }, fontInstalled: { _ in false })
        #expect(e.theme == "papel" && e.fontFamily.isEmpty)
        ErrorLog.flush()
        let log = (try? String(contentsOf: ErrorLog.file, encoding: .utf8)) ?? ""
        #expect(log.contains("«perfil-sin-tema»: el tema «tema-borrado» no existe"))
    }

    /// Valores corruptos a mano: la carga no falla, cada uno se ignora (hereda) con aviso y el resto vale.
    @Test func valoresInvalidosSeIgnoran() {
        let f = SessionFile(text: """
            Host perfil-roto
                # @fuente Menlo 400
                # @tema con espacios
                # @scrollback 99999999
                # @teclado meta turbo
                # @prompt ([
                # @tema papel
                HostName 192.0.2.30
            Host siguiente
                HostName 192.0.2.31
            """)
        #expect(f.sessions.map(\.name) == ["perfil-roto", "siguiente"])
        let s = f.sessions[0]
        #expect(s.host == "192.0.2.30")
        #expect(s.terminal.fontFamily.isEmpty && s.terminal.fontSize == 0 && s.terminal.scrollback == nil)
        #expect(s.terminal.optionAsMeta == nil && s.terminal.prompt.isEmpty)
        #expect(s.terminal.theme == "papel")                    // (la mala se ignora; la siguiente que vale, sí)
        #expect(s.notes.isEmpty)                               // (ni se cuelan como notas)
        #expect(f.problems().isEmpty)
        let p = SSHConfigParser().parse("Host x\n  # @scrollback cien\n  # @prompt (a+)+$\n  HostName 192.0.2.32\n")
        #expect(p.count == 1 && p[0].terminal.isEmpty && p[0].hostName == "192.0.2.32")
        ErrorLog.flush()
        let log = (try? String(contentsOf: ErrorLog.file, encoding: .utf8)) ?? ""
        #expect(log.contains("«perfil-roto»: «# @scrollback 99999999» no vale"))
    }

    /// Lo escrito en el editor que no vale no se guarda.
    @Test func elEditorNoGuardaValoresMalos() {
        var f = SessionFile()
        var s = EditableSession(name: "core-01")
        s.host = "192.0.2.11"
        s.terminal.prompt = "core-01#\n"
        s.terminal.scrollback = 5
        s.terminal.fontSize = 200
        s.terminal.theme = "con espacio"
        f.sessions = [s]
        #expect(f.problems().count == 4)
        f.sessions[0].terminal = TerminalProfile()
        f.sessions[0].notes = ["@prompt .*"]                     // (por las notas tampoco)
        #expect(f.problems().count == 1)
    }

    @Test func reglaDelPrompt() {
        #expect(PromptRule(#"^core-\d+[#>]$"#) != nil)
        #expect(PromptRule.problem(#"^\[~?[A-Z0-9-]+\]$"#) == nil)
        #expect(PromptRule.problem(#"^[\w-]+(\(config[^)]*\))?#$"#) == nil)
        #expect(PromptRule.problem("([") != nil && PromptRule("([") == nil)              // no compila
        #expect(PromptRule.problem("") != nil)
        #expect(PromptRule.problem("^" + String(repeating: "a", count: PromptRule.maxLength) + "$") != nil)   // larga
        #expect(PromptRule.problem("^core\u{7}#$") != nil)                               // control
        for nested in ["(a+)+$", #"^(\d*)*#"#, "(?:x{1,3}){2,}"] { #expect(PromptRule.problem(nested) != nil, "\(nested)") }
        let r = PromptRule(#"^core-\d+[#>]$"#)!
        #expect(PromptRule.isPrompt("core-07# ", custom: r))
        #expect(!PromptRule.isPrompt("tu.usuario@bastion:~$", custom: r))    // (con regex propia, manda ella)
        #expect(PromptRule.isPrompt("tu.usuario@bastion:~$", custom: nil))   // (sin ella, el genérico)
        #expect(DevicePrompt(sample: "core-07#", custom: r).matches("core-08>"))
    }

    /// Un prompt que «acepta» cualquier cosa: una petición de contraseña, passphrase u OTP sigue sin ser prompt.
    @Test func unPromptPropioNoAceptaPeticionesDeSecretos() {
        let todo = PromptRule(".*")!
        for l in ["tu.usuario@192.0.2.1's password: ", "Password:", "Enter passphrase for key '/k': ", "Verification code: ",
                  "[NetDeck] tu.usuario@192.0.2.1's password: ",
                  "Are you sure you want to continue connecting (yes/no/[fingerprint])? "] {
            #expect(!PromptRule.isPrompt(l, custom: todo), "\(l)")
            #expect(!DevicePrompt(sample: nil, custom: todo).matches(l), "\(l)")
        }
        #expect(PromptRule.isPrompt("core-01#", custom: todo))
    }

    /// Importar (ssh_config o el JSON de la app) trae el perfil y sigue quitando las opciones peligrosas.
    @Test func importarYExportarConservanElPerfil() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perfiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = dir.appendingPathComponent("config")
        try (Self.texto.replacingOccurrences(of: "User tu.usuario", with: "User tu.usuario\n    ProxyCommand nc %h %p"))
            .write(to: cfg, atomically: true, encoding: .utf8)
        let r = SessionImporter.read(cfg, existing: [])
        let core = try #require(r.sessions.first { $0.name == "core-01" })
        #expect(core.terminal == SessionFile(text: Self.texto).sessions[0].terminal)
        #expect(!core.extra.contains { $0.lowercased().contains("proxycommand") })
        let json = dir.appendingPathComponent("sesiones.json")
        try SessionExport.json(r.sessions).write(to: json)
        let again = SessionImporter.read(json, existing: [])
        #expect(again.sessions.first { $0.name == "core-01" }?.terminal == core.terminal)
        #expect(again.sessions.first { $0.name == "core-02" }?.terminal.isEmpty == true)
    }
}

/// Una pestaña de mentira con su prompt propio (la de verdad lo pone `AppModel.applyProfile`).
@MainActor
final class PromptTerminal: TerminalIO {
    var screen: [String]
    var revision = 0
    var sent: [String] = []
    var promptRule: PromptRule?

    init(_ screen: [String], prompt: PromptRule?) {
        self.screen = screen
        promptRule = prompt
    }

    func send(bytes: [UInt8]) { sent.append(String(decoding: bytes, as: UTF8.self)) }
    var cursorRow: Int { screen.count - 1 }
    var cursorLine: String { screen.last ?? "" }
    func lines(from row: Int) -> [String] { row <= cursorRow ? Array(screen[max(0, row)...]) : [] }
}

/// MultiExec con un prompt propio que «acepta» la línea de la contraseña: la pestaña sigue «autenticándose».
@Suite @MainActor struct PerfilesMultiExecTests {
    @Test func laContraseñaNoSaleDeSuPestaña() async {
        let todo = PromptRule(".*")!
        let pw = PromptTerminal(["tu.usuario@192.0.2.1's password: "], prompt: todo)
        let otp = PromptTerminal(["Verification code: "], prompt: todo)
        let core = PromptTerminal(["core-02#"], prompt: nil)
        // (como la app: pide un secreto o no ha llegado a su primer prompt, con el prompt de su sesión)
        var loggedIn: [ObjectIdentifier: Bool] = [:]
        func observe(_ io: PromptTerminal) {
            if PromptRule.isPrompt(io.cursorLine, custom: io.promptRule) { loggedIn[ObjectIdentifier(io)] = true }
        }
        [pw, otp, core].forEach(observe)
        #expect(loggedIn[ObjectIdentifier(pw)] == nil && loggedIn[ObjectIdentifier(otp)] == nil)
        #expect(loggedIn[ObjectIdentifier(core)] == true)
        let g = MultiExecGroup()
        g.isActive = true
        g.awaitingAuth = { io in SecretPrompt.asks(io.cursorLine) || loggedIn[ObjectIdentifier(io)] != true }
        [pw, otp, core].forEach(g.join)
        #expect(!g.accepts(pw) && !g.accepts(otp) && g.accepts(core))
        #expect(!g.broadcast(Array("s3cr3t".utf8), from: pw))        // (sólo a la suya)
        #expect(core.sent.isEmpty && otp.sent.isEmpty)
        #expect(g.broadcast(Array("show clock\r".utf8), from: core))
        #expect(pw.sent.isEmpty && otp.sent.isEmpty)

        // (la automatización de contraseñas tampoco da por entrada la pestaña)
        let a = PasswordAutomation(mode: .off, store: MemoryCredentialStore([:]), ledger: CredentialLedger())
        _ = await a.observe(pw, gate: AutomationGate())
        #expect(!a.loggedIn)
        pw.screen.append("core-01#")
        _ = await a.observe(pw, gate: AutomationGate())
        #expect(a.loggedIn)
    }
}
