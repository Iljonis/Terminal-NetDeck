import Foundation
import Testing
@testable import NetDeckCore

private let netdeckFile = """
    # cabecera vieja
    Include ~/.ssh/otros

    # @grupo Saltos
    # @clave-grupo AD

    Host bastion
        # @desc Salto principal
        HostName 192.0.2.1
        User tu.usuario

    # @grupo Core

    Host core-01
        # @clave admin-core
        HostName=192.0.2.11
        Port 2222
        ProxyJump bastion
        IdentityFile "~/.ssh/mi clave"
        IdentitiesOnly yes
        # @antiguo
        KexAlgorithms +diffie-hellman-group-exchange-sha1,diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
        HostKeyAlgorithms +ssh-rsa
        LocalForward 8080 192.0.2.12:80

    Host olt-01
        # @telnet
        HostName 192.0.2.21

    # ── Para varias sesiones (Host *, Match…): el editor de Sesiones no los toca ──

    Host *
        ServerAliveInterval 30
    """

@Suite struct SessionFileTests {
    @Test func leeComoNetDeck() throws {
        let f = SessionFile(text: netdeckFile)
        #expect(f.sessions.map(\.name) == ["bastion", "core-01", "olt-01"])
        #expect(f.groups == ["Saltos", "Core"])
        #expect(f.groupCredentials == ["Saltos": "AD"])
        let c = try #require(f.sessions.first { $0.name == "core-01" })
        #expect(c.port == "2222" && c.jump == "bastion" && c.credential == "admin-core")
        #expect(c.keyFile == "~/.ssh/mi clave")
        #expect(c.legacy)
        #expect(c.extra == ["LocalForward 8080 192.0.2.12:80"])
        #expect(f.sessions[2].telnet)
        #expect(f.head == [["Include ~/.ssh/otros"]])
        #expect(f.tail.first?.first == "Host *")
    }

    @Test func quienUsaCadaContraseña() throws {
        let f = SessionFile(text: netdeckFile)
        #expect(f.usage(ofNamed: "AD").groups == ["Saltos"])
        #expect(f.usage(ofNamed: "admin-core").sessions == ["core-01"])
        let bastion = try #require(f.sessions.first { $0.name == "bastion" })
        #expect(f.namedCredential(of: bastion)?.name == "AD" && f.namedCredential(of: bastion)?.fromGroup == true)
        var own = bastion
        own.credential = "-"
        #expect(f.namedCredential(of: own) == nil)
    }

    @Test func escribirYLeerEsLoMismo() {
        let f = SessionFile(text: netdeckFile)
        let again = SessionFile(text: f.render())
        #expect(again.sessions == f.sessions)
        #expect(again.groupCredentials == f.groupCredentials)
        #expect(again.tail.map { $0.filter { !$0.trimmed.isEmpty } } == f.tail.map { $0.filter { !$0.trimmed.isEmpty } })
        let text = f.render()
        #expect(text.contains("    IdentityFile \"~/.ssh/mi clave\"\n    IdentitiesOnly yes\n"))
        #expect(text.contains("# @grupo Saltos\n# @clave-grupo AD\n"))
        #expect(!text.contains("Port 22\n"))
    }

    @Test func problemasAntesDeGuardar() {
        var f = SessionFile()
        var a = EditableSession(name: "core 01")
        a.port = "70000"
        f.sessions = [a, EditableSession(name: "x"), EditableSession(name: "X")]
        let p = f.problems()
        #expect(p.contains { $0.contains("espacios") })
        #expect(p.contains { $0.contains("puerto") })
        #expect(p.contains { $0.contains("repetida") })
    }

    @Test func guardaComprobandoConSsh() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ssh_config")
        var f = SessionFile(text: netdeckFile)
        #expect(f.save(to: url) == nil)
        f.sessions[0].extra = ["NoExisteEstaOpcion si"]
        #expect(f.save(to: url) != nil)                          // ssh no lo entiende: no se guarda
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("rechazado").path))
        #expect(SessionFile(text: try String(contentsOf: url, encoding: .utf8)).sessions[0].extra.isEmpty)
    }
}

@Suite struct ImporterTests {
    @Test func secureCRT() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let core = dir.appendingPathComponent("Config/Sessions/Madrid/Core")
        try FileManager.default.createDirectory(at: core, withIntermediateDirectories: true)
        try "S:\"Hostname\"=192.0.2.11\r\nS:\"Username\"=admin\r\nD:\"[SSH2] Port\"=00000016\r\nS:\"Firewall Name\"=Session:Saltos/bastion\r\n"
            .write(to: core.appendingPathComponent("core-01.ini"), atomically: true, encoding: .utf8)
        let saltos = dir.appendingPathComponent("Config/Sessions/Saltos")
        try FileManager.default.createDirectory(at: saltos, withIntermediateDirectories: true)
        try "S:\"Hostname\"=192.0.2.1\r\nS:\"Protocol Name\"=SSH2\r\n"
            .write(to: saltos.appendingPathComponent("bastion.ini"), atomically: true, encoding: .utf8)
        try "S:\"Hostname\"=192.0.2.9\r\nS:\"Protocol Name\"=RDP\r\n"
            .write(to: saltos.appendingPathComponent("escritorio.ini"), atomically: true, encoding: .utf8)
        let r = SessionImporter.read(dir, existing: [])
        #expect(r.format == "SecureCRT")
        let c = try #require(r.sessions.first { $0.name == "core-01" })
        #expect(c.group == "Madrid/Core" && c.host == "192.0.2.11" && c.user == "admin" && c.port == "22")
        #expect(c.jump == "bastion")
        #expect(r.skipped.contains { $0.1 == "RDP" })
    }

    @Test func mobaXtermConTelnetYRepetidos() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mxtsessions")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
            [Bookmarks]
            SubRep=
            [Bookmarks_1]
            SubRep=Red\\Core
            core 01 (admin)=#109#0%192.0.2.11%22%admin%%-1%-1%%%%%0%0%0%%%-1%0%0%0%%1080%%0%0%1#MobaFont%10#0# #-1
            olt=#98#1%192.0.2.21%23%%%2%%%%%0%0%%1080%#MobaFont%10#0# #-1
            pc=#91#4%192.0.2.30%3389%%-1%0%0%0%%0%%%0%0%0%0%%#MobaFont%10#0# #-1
            """.write(to: url, atomically: true, encoding: .utf8)
        var mine = EditableSession(name: "core-01")
        mine.host = "192.0.2.99"
        let r = SessionImporter.read(url, existing: [mine])
        #expect(r.sessions.map(\.name) == ["core-01-2", "olt"])
        #expect(r.sessions[0].group == "Red/Core" && r.sessions[0].user == "admin")
        #expect(r.sessions[0].summary == "core 01")
        #expect(r.sessions[1].telnet && r.sessions[1].port == "23")
        #expect(r.skipped.contains { $0.1 == "RDP" })
    }

    @Test func csvConCabeceraYValidacion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try "Name;IP;User;Group\ncore-01;192.0.2.11;admin;Core\nmal;192.0.2.1 -oProxyCommand=x;admin;Core\n"
            .write(to: url, atomically: true, encoding: .utf8)
        let r = SessionImporter.read(url, existing: [])
        #expect(r.sessions.map(\.name) == ["core-01"])
        #expect(r.skipped.count == 1)
        #expect(SessionImporter.validName("Almería Core 1") == "Almeria-Core-1")
    }
}

@Suite struct SafeFileTests {
    func carpeta() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("safefile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func noPisaUnArchivoQueNoSePuedeLeer() throws {
        let f = try carpeta().appendingPathComponent("ssh_config")
        try Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: f)                 // no es UTF-8
        #expect(throws: SafeFile.Unreadable.self) { try SafeFile.backup(f) }
        let err = SessionFile(text: "Host a\n  HostName 192.0.2.1\n").save(to: f, validate: false)
        #expect(err != nil)
        #expect(FileManager.default.contents(atPath: f.path) == Data([0xFF, 0xFE, 0x00, 0xD8]))
    }

    @Test func guardaElOriginalYElAnterior() throws {
        let f = try carpeta().appendingPathComponent("botones.txt")
        try SafeFile.write("uno", to: f)
        try SafeFile.backup(f); try SafeFile.write("dos", to: f)
        try SafeFile.backup(f); try SafeFile.write("tres", to: f)
        #expect(try SafeFile.read(f.appendingPathExtension("original")) == "uno")
        #expect(try SafeFile.read(f.appendingPathExtension("anterior")) == "dos")
        #expect(try SafeFile.read(f) == "tres")
        let modo = try FileManager.default.attributesOfItem(atPath: f.path)[.posixPermissions] as? Int
        #expect(modo == 0o600)
    }

    @Test func alImportarSeQuitanLasOpcionesQueEjecutan() {
        let extra = ["ProxyCommand nc %h %p", "LocalCommand touch /tmp/x", "ServerAliveInterval 30", "forwardagent yes"]
        #expect(SessionImporter.safeExtra(extra, session: "x") == ["ServerAliveInterval 30"])
    }
}
