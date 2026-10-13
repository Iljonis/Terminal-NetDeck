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
        #expect(r.command.arguments == ["core-01"])
    }

    @Test func accesoDirectoDeSaltoEscribeSshEnElSalto() throws {
        // sin -J: se abre el salto y en su prompt se escribe el ssh (vale aunque no deje reenviar puertos)
        let r = try manager.jumpShortcut(to: "admin@192.0.2.50:2222", via: "bastion")
        #expect(r.command.arguments == ["bastion"])
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
        #expect(h.command.arguments == ["bastion"])
        #expect(h.thenCommand == "ssh -p 2222 tu.usuario@192.0.2.11")
    }

    @Test func telnetATravesDelSalto() throws {
        let r = try manager.route(to: #require(manager.profile(named: "olt-01")))
        #expect(r.command.arguments == ["-t", "tu.usuario@192.0.2.1", "telnet", "192.0.2.21"])
    }

    @Test func bucleDeSaltos() {
        let m = SessionManager(profiles: [SessionProfile(name: "a", proxyJump: ["b"]), SessionProfile(name: "b", proxyJump: ["a"])])
        #expect(throws: RouteError.loop("a")) { try m.route(to: m.profile(named: "a")!) }
    }

    @Test func nadaQueEmpiecepor_GuionLlegaComoOpcion() {
        let m = SessionManager()
        let malo = SSHConfigParser().parse("Host -oProxyCommand=evil\n  HostName 192.0.2.1\nHost x\n  HostName -oProxyCommand=evil\n")
        for p in malo { #expect(throws: RouteError.self) { try m.route(to: p) } }
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
