import Foundation
import Testing
@testable import NetDeckCore

private let kinds = """
    # @grupo Saltos
    Host bastion
        HostName 192.0.2.1
        User tu.usuario

    # @grupo Clientes/Madrid/Core
    Host core-01
        HostName 192.0.2.11
        ProxyJump bastion

    Host olt-01
        # @telnet
        HostName 192.0.2.21
        ProxyJump bastion

    # @grupo Clientes/Madrid
    Host ficheros-01
        # @tipo sftp
        # rack 3, armario B
        # @proyecto despliegue
        HostName 192.0.2.30
        User tu.usuario
        ProxyJump bastion

    Host ftp-01
        # @tipo ftp
        HostName 192.0.2.40
        User tu.usuario
        Port 2121

    # @grupo Consolas
    Host consola-01
        # @tipo serie
        # @serie /dev/cu.usbserial-0001 115200 8N1

    Host mac
        # @tipo local
    """

@Suite struct SessionKindTests {
    let file = SessionFile(text: kinds)
    let manager: SessionManager

    init() async {
        manager = await MainActor.run { SessionManager(profiles: SSHConfigParser().parse(kinds)) }
    }

    @MainActor func route(_ name: String) throws -> ConnectionRoute {
        try manager.route(to: try #require(manager.profile(named: name)))
    }

    @Test func leeElTipoDeCadaSesion() throws {
        let by = Dictionary(uniqueKeysWithValues: file.sessions.map { ($0.name, $0) })
        #expect(by["core-01"]?.kind == .ssh && by["olt-01"]?.kind == .telnet && by["ficheros-01"]?.kind == .sftp)
        #expect(by["ftp-01"]?.kind == .ftp && by["consola-01"]?.kind == .serial && by["mac"]?.kind == .local)
        #expect(by["consola-01"]?.serial == SerialLine(device: "/dev/cu.usbserial-0001", speed: 115200))
        #expect(by["ficheros-01"]?.notes == ["rack 3, armario B", "@proyecto despliegue"])
        // (escribir y leer da lo mismo, con sus anotaciones)
        let again = SessionFile(text: file.render())
        #expect(again.sessions == file.sessions)
        #expect(file.render().contains("    # @tipo serie\n    # @serie /dev/cu.usbserial-0001 115200 8N1\n"))
        #expect(file.render().contains("    # @telnet\n"))
    }

    @Test func sshEntiendeLosBloquesDeOtrosTipos() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ssh_config")
        #expect(file.save(to: url) == nil)
        for n in ["consola-01", "mac", "ftp-01", "ficheros-01"] {
            #expect(SessionFile.sshCheck(url, host: n) == nil, "\(n)")
        }
    }

    @Test @MainActor func ordenDeCadaTipo() throws {
        #expect(try route("core-01").command.executable == "/usr/bin/ssh")
        #expect(try route("core-01").command.arguments == ["--", "core-01"])
        let telnet = try route("olt-01").command
        #expect(telnet.executable == "/usr/bin/ssh" && telnet.arguments == ["-t", "--", "tu.usuario@192.0.2.1", "telnet", "192.0.2.21"])

        // sftp: el mismo alias que ssh (saltos, puerto y usuario del ssh_config), askpass sí, MultiExec no
        let sftp = try route("ficheros-01")
        #expect(sftp.command.executable == "/usr/bin/sftp" && sftp.command.arguments == ["--", "ficheros-01"])
        #expect(sftp.usesPasswords && !sftp.acceptsMultiExec && !sftp.isLocal)
        var direct = ConnectionRoute(title: "x", target: Endpoint(user: "tu.usuario", host: "192.0.2.30", port: 2222),
                                     transport: .sftp)
        #expect(direct.command.arguments == ["-P", "2222", "--", "tu.usuario@192.0.2.30"])
        direct.target = Endpoint(host: "2001:db8::1")
        direct.jumpSpec = ["bastion"]
        #expect(direct.command.arguments == ["-J", "bastion", "--", "[2001:db8::1]"])

        // ftp: al Finder, no a una pestaña
        let ftp = try route("ftp-01")
        #expect(ftp.ftpURL?.absoluteString == "ftp://tu.usuario@192.0.2.40:2121")
        #expect(ftp.command.executable == "/usr/bin/false" && ftp.launchProblem() != nil)
        #expect(!ftp.usesPasswords && !ftp.acceptsMultiExec)
        #expect(ConnectionRoute(title: "f", target: Endpoint(host: "192.0.2.40", port: 21), transport: .ftp).ftpURL?
            .absoluteString == "ftp://192.0.2.40")
        #expect(ConnectionRoute(title: "f", target: Endpoint(host: "a;b"), transport: .ftp).ftpURL == nil)

        // local: la shell de login, sin contraseñas ni MultiExec
        let local = try route("mac")
        #expect(local.isLocal && local.command.arguments == ["-l"] && local.title == "mac" && local.sessionName == "mac")
        #expect(!local.usesPasswords && !local.acceptsMultiExec)

        // serie: screen con velocidad y bits de datos
        let serie = try route("consola-01")
        #expect(serie.command.executable == "/usr/bin/screen")
        #expect(serie.command.arguments == ["/dev/cu.usbserial-0001", "115200,cs8,-ixon,-ixoff"])
        #expect(!serie.usesPasswords && !serie.acceptsMultiExec && !serie.isLoopback)
    }

    @Test func serieComprobadaAlAbrir() {
        let r = ConnectionRoute.serial(SerialLine(device: "/dev/cu.usbserial-0001"), title: "c")
        #expect(r.launchProblem { _ in true } == nil)
        #expect(r.launchProblem { $0 != "/usr/bin/screen" }?.contains("screen") == true)
        #expect(r.launchProblem { $0 != "/dev/cu.usbserial-0001" }?.contains("USB") == true)
        var bad = r
        bad.serial?.device = "/dev/cu.x;rm -rf ~"
        #expect(bad.launchProblem { _ in true } != nil)
        #expect(bad.command.executable == "/usr/bin/false")
    }

    @Test func rutaDelPuertoSerieEstricta() {
        for bad in ["/dev/cu.a;b", "/dev/disk0", "/dev/cu.../x", "-oProxyCommand=x", "/dev/cu.a$(x)", "/dev/tty.a b 9600",
                    "/dev/cu.a 1234 8N1", "/dev/cu.a 9600 9N1", "/dev/cu.a 9600 8X1", "/dev/cu.a 9600 8N3", "/tmp/cu.a"] {
            #expect(SerialLine(annotation: bad) == nil, "\(bad)")
        }
        let ok = SerialLine(annotation: "/dev/tty.usbserial-A9 9600 7E2")
        #expect(ok?.frame == "7E2" && ok?.parity == .even && ok?.screenArguments == ["/dev/tty.usbserial-A9", "9600,cs7,-ixon,-ixoff"])
        #expect(SerialLine(annotation: "/dev/cu.usbmodem1")?.annotation == "/dev/cu.usbmodem1 9600 8N1")
        var f = SessionFile()
        var s = EditableSession(name: "consola")
        s.kind = .serial
        s.serial.device = "/dev/cu.mal nombre"
        f.sessions = [s]
        #expect(f.problems().contains { $0.contains("serie") })
    }

    @Test @MainActor func serieSinPuertoNoAbre() throws {
        let m = SessionManager(profiles: SSHConfigParser().parse("Host c\n  # @tipo serie\n  # @serie /dev/cu.a;b 9600\n"))
        #expect(throws: RouteError.self) { try m.route(to: m.profiles[0]) }
    }

    @Test func pestañasGuardadasDeAntesYDeAhora() throws {
        let old = #"{"title":"core-01","target":{"host":"192.0.2.11"},"jumps":[],"transport":"telnet"}"#
        let r = try JSONDecoder().decode(ConnectionRoute.self, from: Data(old.utf8))
        #expect(r.transport == .telnet && r.serial == nil && r.acceptsMultiExec)
        // (las locales de antes llevaban transport «ssh» y la shell)
        let oldLocal = #"{"title":"t","target":{"host":"localhost"},"jumps":[],"transport":"ssh","localShell":"/bin/zsh"}"#
        let l = try JSONDecoder().decode(ConnectionRoute.self, from: Data(oldLocal.utf8))
        #expect(l.isLocal && !l.acceptsMultiExec && !l.usesPasswords)
        let s = ConnectionRoute.serial(SerialLine(device: "/dev/cu.usbserial-0001", speed: 57600), title: "c", sessionName: "c")
        let back = try JSONDecoder().decode(ConnectionRoute.self, from: JSONEncoder().encode(s))
        #expect(back == s && back.command.arguments.last == "57600,cs8,-ixon,-ixoff")
    }

    @Test func notasQueRomperianElArchivo() {
        var f = SessionFile()
        var s = EditableSession(name: "a")
        s.notes = ["@grupo Otro"]
        f.sessions = [s]
        #expect(!f.problems().isEmpty)
    }
}

@Suite struct SessionOrderTests {
    @Test func subirBajarYArrastrar() {
        var f = SessionFile(text: kinds)
        let id = { (n: String) in f.sessions.first { $0.name == n }!.id }
        let up = f.move(id("olt-01"), by: -1)
        #expect(up)
        #expect(f.sessions.map(\.name).prefix(3) == ["bastion", "olt-01", "core-01"])
        let edge = f.move(id("olt-01"), by: -1)
        #expect(!edge)                                                 // (ya es la primera de su grupo)
        let down = f.move(id("ficheros-01"), by: 1)
        #expect(down)
        #expect(f.sessions.filter { $0.group == "Clientes/Madrid" }.map(\.name) == ["ftp-01", "ficheros-01"])
        f.move(id("mac"), to: id("bastion"))
        #expect(f.sessions.first?.name == "mac" && f.sessions.first?.group == "Saltos")
        f.move(id("mac"), to: id("consola-01"), after: true)
        #expect(f.sessions.last?.name == "mac" && f.sessions.last?.group == "Consolas")
        // (el orden se guarda: es el del archivo)
        #expect(SessionFile(text: f.render()).sessions.map(\.name) == f.sessions.map(\.name))
        #expect(f.uniqueName("core-01") == "core-01-2" && f.uniqueName("nueva") == "nueva")
        let c = f.sessions[0].copy(named: "copia")
        #expect(c.id != f.sessions[0].id && c.host == f.sessions[0].host && c.kind == f.sessions[0].kind)
    }
}

@Suite struct GroupTreeTests {
    @Test func carpetasDentroDeCarpetas() {
        let groups: [(name: String, items: [String])] = [("Saltos", ["bastion"]), ("Clientes/Madrid/Core", ["core-01", "olt-01"]),
                                                          ("Clientes/Madrid", ["ficheros-01"]), ("Clientes / Sevilla", ["sw-01"])]
        func show(_ rows: [GroupTree.Row<String>]) -> [String] {
            rows.map {
                switch $0 {
                case .folder(let p, _, let d, let n): String(repeating: " ", count: d) + "[\(p)] \(n)"
                case .item(let s, let d): String(repeating: " ", count: d) + s
                }
            }
        }
        #expect(show(GroupTree.rows(groups)) == [
            "[Saltos] 1", " bastion",
            "[Clientes] 4", " [Clientes/Madrid] 3", "  ficheros-01", "  [Clientes/Madrid/Core] 2", "   core-01", "   olt-01",
            " [Clientes/Sevilla] 1", "  sw-01",
        ])
        #expect(show(GroupTree.rows(groups, collapsed: ["Clientes/Madrid"])) == [
            "[Saltos] 1", " bastion", "[Clientes] 4", " [Clientes/Madrid] 3", " [Clientes/Sevilla] 1", "  sw-01",
        ])
        #expect(GroupTree.contains("Clientes", "Clientes/Madrid/Core") && GroupTree.contains("Clientes/Madrid", "Clientes/Madrid"))
        #expect(!GroupTree.contains("Clientes/Mad", "Clientes/Madrid") && !GroupTree.contains("", "Saltos"))
    }
}

@Suite struct SessionExportTests {
    @Test func jsonDeIdaYVuelta() throws {
        var f = SessionFile(text: kinds)
        f.sessions[1].credential = "AD"
        f.sessions[1].extra = ["ProxyCommand nc %h %p", "ServerAliveInterval 30"]
        f.sessions[1].notes = ["@clave otra", "nota buena"]
        let only = SessionExport.select(f.sessions, groups: ["Clientes"])
        #expect(only.map(\.name) == ["core-01", "olt-01", "ficheros-01", "ftp-01"])
        let data = SessionExport.json(only)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(SessionExport.format) && !text.lowercased().contains("password"))

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("sesiones.json")
        try data.write(to: url)
        // (en otro Mac sin ninguna: vuelven todas; el salto, a la que ya tienes o como estaba)
        let r = SessionImporter.read(url, existing: [])
        #expect(r.format == "Terminal NetDeck")
        #expect(r.sessions.map(\.name) == ["core-01", "olt-01", "ficheros-01", "ftp-01"])
        let c = try #require(r.sessions.first)
        #expect(c.group == "Clientes/Madrid/Core" && c.jump == "bastion")
        #expect(c.extra == ["ServerAliveInterval 30"])                 // (lo que ejecuta órdenes, fuera)
        #expect(c.credential.isEmpty && c.notes == ["nota buena"])      // (la contraseña con nombre se elige aquí)
        #expect(r.sessions[1].kind == .telnet && r.sessions[2].kind == .sftp && r.sessions[3].kind == .ftp)
        #expect(r.sessions[3].port == "2121")
        // (en el mismo: nada nuevo, todas repetidas)
        let again = SessionImporter.read(url, existing: f.sessions)
        #expect(again.sessions.isEmpty && again.skipped.count == 4)

        // serie y local también
        try SessionExport.json(f.sessions.filter { $0.group == "Consolas" }).write(to: url)
        let con = SessionImporter.read(url, existing: [])
        #expect(con.sessions.map(\.kind) == [.serial, .local])
        #expect(con.sessions[0].serial.device == "/dev/cu.usbserial-0001" && con.sessions[0].serial.speed == 115200)
    }

    @Test func csvConLasColumnasDelImportador() throws {
        var f = SessionFile(text: kinds)
        f.sessions[1].summary = "core; planta 2"
        let csv = SessionExport.csv(SessionExport.select(f.sessions, groups: ["Clientes/Madrid/Core"]))
        #expect(csv.hasPrefix("grupo;nombre;host;usuario;puerto;salto;descripcion;tipo\n"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try csv.write(to: url, atomically: true, encoding: .utf8)
        let r = SessionImporter.read(url, existing: [])
        #expect(r.sessions.map(\.name) == ["core-01", "olt-01"])
        #expect(r.sessions[0].summary == "core; planta 2" && r.sessions[0].jump == "bastion")
        #expect(r.sessions[1].kind == .telnet)
    }
}
