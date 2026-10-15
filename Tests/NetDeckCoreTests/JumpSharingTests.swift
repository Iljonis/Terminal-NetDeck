import Foundation
import Testing
@testable import NetDeckCore

private let config = """
    Host bastion
      HostName 192.0.2.1
      User tu.usuario
    Host core-01
      HostName 192.0.2.11
      ProxyJump bastion
    Host core-02
      HostName 192.0.2.12
      ProxyJump admin@198.51.100.5:2222,bastion
    Host core-03
      HostName 192.0.2.13
      ProxyCommand ssh -q -W %h:%p bastion
    Host olt-01
      HostName 192.0.2.21
      ProxyJump bastion
      # @telnet
    Host ficheros-01
      HostName 192.0.2.30
      ProxyJump bastion
      # @tipo sftp
    """

/// Varias pestañas por el mismo bastión: la conexión al último salto compartida (ControlMaster) y la contraseña del
/// salto confirmada en cuanto ssh pasa al destino.
@Suite @MainActor struct JumpSharingTests {
    let manager = SessionManager(profiles: SSHConfigParser().parse(config))
    let sharing = JumpSharing(directory: "/private/var/folders/xx/abc/T/nd")

    private func socket(_ chain: String) throws -> String { try #require(sharing.socket(for: [chain])) }

    @Test func sshConAliasCambiaElProxyJumpPorUnProxyCommandMultiplexado() throws {
        let r = try manager.route(to: #require(manager.profile(named: "core-01")))
        #expect(r.configJumps == ["bastion"])
        let s = try socket("tu.usuario@192.0.2.1")
        #expect(r.command(sharing: sharing).arguments == [
            "-o", "ProxyCommand=/usr/bin/ssh -o ControlMaster=auto -o ControlPath=\(s) -o ControlPersist=120 -W '[%h]:%p' -- bastion",
            "--", "core-01"])
        // (desactivado: igual que siempre, ssh lee el ProxyJump del ssh_config)
        #expect(r.command(sharing: nil).arguments == ["--", "core-01"])
        #expect(r.command.arguments == ["--", "core-01"])
    }

    @Test func variosSaltosElUltimoMultiplexadoYLosDemasPorJ() throws {
        let r = try manager.route(to: #require(manager.profile(named: "core-02")))
        let pc = try #require(r.command(sharing: sharing).arguments.first { $0.hasPrefix("ProxyCommand=") })
        #expect(pc.hasSuffix(" -J admin@198.51.100.5:2222 -W '[%h]:%p' -- bastion"))
        // explícito (conectar sin guardar): «admin@equipo:puerto» del último va con -l y -p
        var d = ConnectionRoute(title: "x", target: Endpoint(host: "192.0.2.40"))
        d.jumpSpec = ["admin@198.51.100.5:2222"]
        let a = d.command(sharing: sharing).arguments
        #expect(a.first == "-o" && a.suffix(2) == ["--", "192.0.2.40"])
        #expect(a[1].hasSuffix(" -l admin -p 2222 -W '[%h]:%p' -- 198.51.100.5"))
        #expect(d.command(sharing: nil).arguments == ["-J", "admin@198.51.100.5:2222", "--", "192.0.2.40"])
    }

    @Test func conProxyCommandPropioNoSeToca() throws {
        let r = try manager.route(to: #require(manager.profile(named: "core-03")))
        #expect(r.configJumps == nil)
        #expect(r.command(sharing: sharing).arguments == ["--", "core-03"])
    }

    @Test func telnetSftpYExploradorPorElMismoSocket() throws {
        let s = try socket("tu.usuario@192.0.2.1")
        let olt = try manager.route(to: #require(manager.profile(named: "olt-01")))
        #expect(olt.command(sharing: sharing).arguments == [
            "-t", "-o", "ControlMaster=auto", "-o", "ControlPath=\(s)", "-o", "ControlPersist=120",
            "--", "tu.usuario@192.0.2.1", "telnet", "192.0.2.21"])
        let f = try manager.route(to: #require(manager.profile(named: "ficheros-01")))
        #expect(f.command(sharing: sharing).executable == "/usr/bin/sftp")
        #expect(f.command(sharing: sharing).arguments.suffix(2) == ["--", "ficheros-01"])
        #expect(f.command(sharing: sharing).arguments[1].contains("ControlPath=\(s) "))
        let sub = try #require(f.sftpSubsystemCommand(sharing: sharing))
        #expect(sub.arguments.suffix(3) == ["--", "ficheros-01", "sftp"])
        #expect(sub.arguments.contains { $0.hasPrefix("ProxyCommand=/usr/bin/ssh ") && $0.contains("ControlPath=\(s) ") })
        #expect(f.sftpSubsystemCommand(sharing: nil)?.arguments == f.sftpSubsystemCommand?.arguments)
        #expect(f.sftpSubsystemCommand?.arguments.contains { $0.hasPrefix("ProxyCommand") } == false)
    }

    @Test func sinSaltoOLocalNadaCambia() throws {
        let b = try manager.route(to: #require(manager.profile(named: "bastion")))
        #expect(b.command(sharing: sharing).arguments == ["--", "bastion"])
        // (el salto a mano entra en el bastión y escribe allí el ssh: tampoco cambia)
        let core = try manager.route(to: #require(manager.profile(named: "core-01")))
        let h = try #require(try manager.typedHop(for: core))
        #expect(h.command(sharing: sharing).arguments == ["--", "bastion"])
        #expect(ConnectionRoute.local(shell: "/bin/zsh", allowed: ["/bin/zsh"]).command(sharing: sharing).arguments == ["-l"])
    }

    /// Lo que va al ProxyCommand pasa por la shell: con cualquier cosa rara, -J como siempre (ssh no usa shell para -J).
    @Test func nadaRaroLlegaALaShell() {
        for bad in ["x;id", "a$(id)", "`id`", "a b", "x'y", "%d", "tu.usuario@x|y", "-oProxyCommand=id", "fe80::1",
                    "~/x", "a\"b", "x&y"] {
            var r = ConnectionRoute(title: "x", target: Endpoint(host: "192.0.2.40"))
            r.jumpSpec = [bad]
            #expect(r.command(sharing: sharing).arguments == ["-J", bad, "--", "192.0.2.40"], "\(bad)")
            #expect(sharing.proxyCommand(hops: ["bastion", bad], socket: "/tmp/nd/x") == nil, "\(bad)")
        }
        // (el destino también: %h se escribe en esa shell)
        var t = ConnectionRoute(title: "x", target: Endpoint(host: "a'b"))
        t.jumpSpec = ["bastion"]
        #expect(t.command(sharing: sharing).arguments == ["-J", "bastion", "--", "a'b"])
        #expect(sharing.proxyCommand(hops: ["bastion"], socket: "/tmp/nd/x y") == nil)
        #expect(sharing.proxyCommand(hops: ["bastion"], socket: "/tmp/%h") == nil)
    }

    /// El socket Unix admite 104 bytes y ssh le añade 17 al crearlo: si no cabe, sin compartir (ssh se cerraría).
    @Test func rutaDelSocketAcotada() throws {
        let s = try socket("tu.usuario@192.0.2.1")
        #expect(s.hasPrefix(sharing.directory + "/") && s.count == sharing.directory.count + 17)
        #expect(sharing.socket(for: ["otro@192.0.2.1"]) != s)
        let largo = JumpSharing(directory: "/" + String(repeating: "c", count: 70))
        #expect(largo.socket(for: ["bastion"]) == nil)
        var r = try manager.route(to: #require(manager.profile(named: "core-01")))
        #expect(r.command(sharing: largo).arguments == ["--", "core-01"])
        r.transport = .telnet
        #expect(!r.command(sharing: largo).arguments.contains("ControlMaster=auto"))
        #expect(JumpSharing(directory: "/tmp/con espacio").socket(for: ["bastion"]) == nil)
    }

    @Test func carpetaPropia0700() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString.prefix(8).description)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let s = try #require(JumpSharing.standard(base: base.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: s.directory)
        #expect((attrs[.posixPermissions] as? Int) == 0o700)
        // (un enlace en su lugar no vale)
        let other = base.appendingPathComponent("otra")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let trap = base.appendingPathComponent("trampa")
        try FileManager.default.createDirectory(at: trap, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: trap.appendingPathComponent("nd").path, withDestinationPath: other.path)
        #expect(JumpSharing.standard(base: trap.path) == nil)
    }

    @Test func avisoDeReenvioRechazadoTambienMultiplexado() {
        #expect(ConnectionRoute.forwardingRefused(["Stdio forwarding request failed: Session open refused by peer"]))
        #expect(!ConnectionRoute.forwardingRefused(["banner: hola stdio forwarding request failed:"]))
    }
}

/// La contraseña del salto se confirma cuando ssh pregunta ya por el destino (en la misma pestaña).
@Suite struct EarlyConfirmTests {
    @Test func laDelSaltoSeConfirmaAlPreguntarPorElDestino() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = MemoryLedgerStorage()
        let tab1 = CredentialLedger(storage: storage), tab2 = CredentialLedger(storage: storage)
        let ad = CredentialRef.named("AD"), core = CredentialRef.device("tu.usuario", "192.0.2.11")
        let session = UUID().uuidString
        #expect(tab1.beginProbe(ad) == .go)
        #expect(tab2.beginProbe(ad) == .wait)                       // la otra pestaña espera
        try SafeFile.write(Askpass.encodeGiven(ad, host: "192.0.2.1") + "\n", to: dir.appendingPathComponent(session))

        // ssh vuelve a preguntar por el salto: no valía; nada se confirma (se marca fallo como siempre)
        #expect(Askpass.confirmEarlier(session: session, host: "192.0.2.1", ledger: tab1, directory: dir).isEmpty)
        #expect(tab2.beginProbe(ad) == .wait)
        // otra pestaña: lo suyo no cuenta
        #expect(Askpass.confirmEarlier(session: UUID().uuidString, host: "192.0.2.11", ledger: tab1, directory: dir).isEmpty)

        // pregunta ya por el destino: la del salto ha entrado
        #expect(Askpass.confirmEarlier(session: session, host: "192.0.2.11", ledger: tab1, directory: dir) == [ad])
        #expect(tab2.state(of: ad).map { if case .confirmed = $0 { true } else { false } } == true)
        #expect(tab2.beginProbe(ad) == .go)                        // la que esperaba sigue ya

        // la del destino queda para cuando salga su prompt
        let url = dir.appendingPathComponent(session)
        try SafeFile.write(Askpass.encodeGiven(core, host: "192.0.2.11") + "\n", to: url)
        #expect(Askpass.confirmEarlier(session: session, host: "192.0.2.11", ledger: tab1, directory: dir).isEmpty)
        #expect(try String(contentsOf: url, encoding: .utf8) == Askpass.encodeGiven(core, host: "192.0.2.11") + "\n")
    }

    @Test func lineasDeAntesSinEquipo() {
        let r = CredentialRef.device("tu.usuario", "192.0.2.1")
        #expect(Askpass.decodeGiven(Askpass.encode(r))?.ref == r && Askpass.decodeGiven(Askpass.encode(r))?.host == nil)
        let g = Askpass.decodeGiven(Askpass.encodeGiven(.named("AD"), host: "bastion"))
        #expect(g?.ref == .named("AD") && g?.host == "bastion")
    }
}
