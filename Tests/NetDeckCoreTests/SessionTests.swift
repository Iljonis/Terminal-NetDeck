import Foundation
import Testing
@testable import NetDeckCore

private let config = """
    # @grupo Saltos
    Host bastion
      HostName 10.0.0.1
      # @desc Salto principal
    # @grupo Core
    # @clave-grupo AD
    Host core-01 core-01b
      HostName=10.0.0.11
      Port = 2222
      ProxyJump bastion
    Host core-02
      HostName 10.0.0.12
      User admin
      ProxyCommand ssh -q -W %h:%p bastion
      # @clave admin-core
    Host olt-01
      HostName 10.0.0.21
      ProxyJump bastion
      # @telnet
    Host 10.0.0.*
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
        #expect(c.hostName == "10.0.0.11")
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
        #expect(Endpoint(parsing: "admin@10.0.0.1:2222") == Endpoint(user: "admin", host: "10.0.0.1", port: 2222))
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
        #expect(r.jumps == [Endpoint(user: "tu.usuario", host: "10.0.0.1")])
        #expect(r.command.arguments == ["core-01"])
    }

    @Test func accesoDirectoDeSaltoEscribeSshEnElSalto() throws {
        // sin -J: se abre el salto y en su prompt se escribe el ssh (vale aunque no deje reenviar puertos)
        let r = try manager.jumpShortcut(to: "admin@10.0.0.50:2222", via: "bastion")
        #expect(r.command.arguments == ["bastion"])
        #expect(r.thenCommand == "ssh -p 2222 admin@10.0.0.50")
        #expect(r.thenUser == "admin")
        #expect(r.title == "10.0.0.50 ⟵ bastion")
        let t = try manager.jumpShortcut(to: "10.0.0.21", via: "bastion", transport: .telnet)
        #expect(t.thenCommand == "telnet 10.0.0.21")
        #expect(throws: RouteError.badDevice("x;reboot")) { try manager.jumpShortcut(to: "x;reboot", via: "bastion") }
    }

    @Test func sesionConProxyJumpEscritaEnElSalto() throws {
        let r = try manager.route(to: #require(manager.profile(named: "core-01")))
        let h = try #require(try manager.typedHop(for: r))
        #expect(h.command.arguments == ["bastion"])
        #expect(h.thenCommand == "ssh -p 2222 tu.usuario@10.0.0.11")
    }

    @Test func telnetATravesDelSalto() throws {
        let r = try manager.route(to: #require(manager.profile(named: "olt-01")))
        #expect(r.command.arguments == ["-t", "tu.usuario@10.0.0.1", "telnet", "10.0.0.21"])
    }

    @Test func bucleDeSaltos() {
        let m = SessionManager(profiles: [SessionProfile(name: "a", proxyJump: ["b"]), SessionProfile(name: "b", proxyJump: ["a"])])
        #expect(throws: RouteError.loop("a")) { try m.route(to: m.profile(named: "a")!) }
    }

    @Test func candidatasConSusDuenos() throws {
        let r = try manager.route(to: #require(manager.profile(named: "core-02")))
        let req = PasswordRequest(line: "admin@10.0.0.12's password:", account: "admin@10.0.0.12")
        let c = manager.credentialCandidates(for: req, route: r, defaultCredential: .init(name: "AD", user: "tu.usuario"))
        #expect(c.first?.ref == .named("admin-core"))              // la con nombre de la sesión, como NetDeck
        #expect(c.first?.owners == ["admin"])
        #expect(c[1].ref == .device("admin", "10.0.0.12"))
        #expect(c.last?.ref == .named("AD"))
    }
}
