import Darwin
import Foundation
import Testing
@testable import NetDeckCore

@Suite struct TunelValidacionTests {
    @Test func escuchaPorDefectoEnLoopback() {
        let l = Tunnel(name: "web", session: "core-01", kind: .local, listenPort: 8080, targetHost: "192.0.2.10", targetPort: 80)
        #expect(l.listen == "127.0.0.1" && l.problem == nil && l.warnings.isEmpty)
        #expect(l.forwardSpec == "127.0.0.1:8080:192.0.2.10:80")
        let r = Tunnel(name: "vuelta", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1", targetPort: 22)
        #expect(r.listen == "localhost" && r.forwardSpec == "localhost:9000:127.0.0.1:22")
        let d = Tunnel(name: "socks", session: "core-01", kind: .dynamic, listenPort: 1080, targetHost: "")
        #expect(d.problem == nil && d.forwardSpec == "127.0.0.1:1080")
    }

    @Test func puertos() {
        for p in [0, -1, 65536, 100_000] {
            #expect(Tunnel(name: "x", session: "core-01", listenPort: p, targetHost: "192.0.2.10").problem != nil)
            #expect(Tunnel(name: "x", session: "core-01", listenPort: 8080, targetHost: "192.0.2.10", targetPort: p).problem != nil)
        }
        #expect(Tunnel(name: "x", session: "core-01", listenPort: 65535, targetHost: "192.0.2.10", targetPort: 1).problem == nil)
        // (menor que 1024: vale, con aviso)
        let bajo = Tunnel(name: "x", session: "core-01", listenPort: 443, targetHost: "192.0.2.10", targetPort: 443)
        #expect(bajo.problem == nil && bajo.warnings.count == 1)
    }

    @Test func equiposYOpciones() {
        for h in ["-oProxyCommand=x", "a b", "a\u{7}b", "", "a;b", "$(id)", "x\ny"] {
            #expect(Tunnel(name: "x", session: "core-01", targetHost: h).problem != nil, "«\(h)»")
            #expect(Tunnel(name: "x", session: "core-01", listenAddress: h.isEmpty ? " -x" : h, targetHost: "192.0.2.10").problem != nil, "«\(h)»")
        }
        for h in ["192.0.2.10", "core-01", "2001:db8::1", "[2001:db8::1]", "srv_web.example.net"] {
            #expect(Tunnel(name: "x", session: "core-01", targetHost: h).problem == nil, "«\(h)»")
        }
        #expect(Tunnel(name: "x", session: "-oProxyCommand=x", targetHost: "192.0.2.10").problem != nil)
        #expect(Tunnel(name: "x", session: "core 01", targetHost: "192.0.2.10").problem != nil)
        #expect(Tunnel(name: "x", server: "-oProxyCommand=x", targetHost: "192.0.2.10").problem != nil)
        #expect(Tunnel(name: "x", server: "tu.usuario@-x", targetHost: "192.0.2.10").problem != nil)
        #expect(Tunnel(name: "x", server: "tu.usuario@192.0.2.20:2222", jump: "bastion;id", targetHost: "192.0.2.10").problem != nil)
        #expect(Tunnel(name: "x", server: "tu.usuario@192.0.2.20:2222", jump: "-oX", targetHost: "192.0.2.10").problem != nil)
        #expect(Tunnel(name: "x", targetHost: "192.0.2.10").problem != nil)            // (ni sesión ni equipo)
        #expect(Tunnel(name: " ", session: "core-01", targetHost: "192.0.2.10").problem != nil)
        #expect(Tunnel(name: "a\u{1b}b", session: "core-01", targetHost: "192.0.2.10").problem != nil)
    }

    @Test func todasLasDireccionesSoloSiSeMarca() {
        for a in ["0.0.0.0", "*", "::", "192.0.2.5"] {
            var t = Tunnel(name: "x", session: "core-01", listenAddress: a, targetHost: "192.0.2.10")
            #expect(t.problem != nil, "«\(a)» sin marcar")
            t.exposed = true
            #expect(t.problem == nil, "«\(a)» marcado")
            #expect(t.warnings.contains { $0.hasPrefix("⚠") })
        }
        #expect(Tunnel(name: "x", session: "core-01", listenAddress: "*", targetHost: "192.0.2.10", exposed: true)
            .forwardSpec == "*:8080:192.0.2.10:80")
        for a in ["127.0.0.1", "127.0.0.2", "::1", "[::1]", "localhost"] {
            #expect(Tunnel(name: "x", session: "core-01", listenAddress: a, targetHost: "192.0.2.10").problem == nil, "«\(a)»")
        }
        #expect(Tunnel(name: "x", session: "core-01", listenAddress: "::1", targetHost: "2001:db8::1")
            .forwardSpec == "[::1]:8080:[2001:db8::1]:80")
    }
}

@MainActor @Suite struct TunelOrdenTests {
    let manager = SessionManager(profiles: SSHConfigParser().parse("""
        Host bastion
          HostName 192.0.2.1
          User tu.usuario
        Host core-01
          HostName 192.0.2.11
          User tu.usuario
          ProxyJump bastion
        Host ficheros
          HostName 192.0.2.30
          # @tipo sftp
        Host olt-01
          HostName 192.0.2.21
          # @telnet
        Host -oProxyCommand=x
          HostName 192.0.2.99
        """))

    func args(_ t: Tunnel, sharing: JumpSharing? = nil, config: String? = nil) throws -> [String] {
        try t.arguments(route: t.route(using: manager), sharing: sharing, configFile: config)
    }

    @Test func porLaSesionConF() throws {
        let t = Tunnel(name: "web", session: "core-01", listenPort: 8080, targetHost: "192.0.2.10", targetPort: 80)
        let a = try args(t, config: "/ruta/de/prueba/ssh_config")
        #expect(Array(a.prefix(2)) == ["-F", "/ruta/de/prueba/ssh_config"])
        #expect(Array(a.suffix(2)) == ["--", "core-01"])
        let dash = try #require(a.lastIndex(of: "--"))
        for o in ["-N", "-T", "-L", "ExitOnForwardFailure=yes", "ServerAliveInterval=30", "ControlPath=none",
                  "ControlPersist=no", "ForkAfterAuthentication=no", "ClearAllForwardings=no", "GatewayPorts=no"] {
            let i = try #require(a.firstIndex(of: o), "falta \(o)")
            #expect(i < dash)
        }
        #expect(a[try #require(a.firstIndex(of: "-L")) + 1] == "127.0.0.1:8080:192.0.2.10:80")
        // (ni shell ni contraseñas: sólo opciones de ssh)
        #expect(!a.contains { $0.lowercased().contains("password") || $0.contains("ASKPASS") || $0 == "-c" })
        // (sin -F: el ssh_config de siempre)
        #expect(try !args(t).contains("-F"))
    }

    @Test func saltosComoLaSesion() throws {
        let t = Tunnel(name: "web", session: "core-01", targetHost: "192.0.2.10")
        // (compartiendo el salto: el mismo ProxyCommand que la pestaña, con -F también dentro)
        let a = try args(t, sharing: JumpSharing(directory: "/tmp/nd"), config: "/ruta/cfg")
        let proxy = try #require(a.first { $0.hasPrefix("ProxyCommand=") })
        #expect(proxy.contains("-F /ruta/cfg") && proxy.contains("bastion"))
        // (sin compartir: ssh lee el ProxyJump del ssh_config por el alias)
        #expect(try !args(t).contains { $0.hasPrefix("ProxyCommand=") })
        // (equipo escrito con salto: -J)
        let e = Tunnel(name: "e", server: "tu.usuario@192.0.2.20:2222", jump: "bastion, tu.usuario@192.0.2.2", kind: .dynamic, listenPort: 1080)
        let b = try args(e)
        #expect(b[try #require(b.firstIndex(of: "-J")) + 1] == "bastion,tu.usuario@192.0.2.2")
        #expect(Array(b.suffix(2)) == ["--", "192.0.2.20"])
        let ip = try #require(b.firstIndex(of: "-p")), il = try #require(b.firstIndex(of: "-l"))
        #expect(b[ip + 1] == "2222" && b[il + 1] == "tu.usuario")
        #expect(b[try #require(b.firstIndex(of: "-D")) + 1] == "127.0.0.1:1080")
    }

    @Test func preflightConservaRutaSinElForwardPedido() throws {
        for kind in Tunnel.Kind.allCases {
            let t = Tunnel(name: "web", session: "core-01", kind: kind, targetHost: "192.0.2.10")
            let a = try args(t, sharing: JumpSharing(directory: "/tmp/nd"), config: "/ruta/cfg")
            let check = try t.configurationArguments(arguments: a)
            #expect(check.first == "-G")
            #expect(!check.contains(kind.flag) && !check.contains(t.forwardSpec))
            #expect(Array(check.dropFirst()) == Array(a.dropLast(4)) + Array(a.suffix(2)))
            #expect(!check.contains("ClearAllForwardings=yes"))
            #expect(throws: (any Error).self) { try t.configurationArguments(arguments: ["-N", "--", "core-01"]) }
        }
        #expect(Tunnel.configurationProblem("host core-01\nclearallforwardings no\n") == nil)
        for text in ["", "host core-01\n", "host core-01\nclearallforwardings yes\n"] {
            #expect(Tunnel.configurationProblem(text) != nil)
        }
        for key in ["localforward", "remoteforward", "dynamicforward", "LocalForward"] {
            #expect(Tunnel.configurationProblem("host core-01\nclearallforwardings no\n\(key) 0.0.0.0:8080 192.0.2.10:80") != nil)
        }
    }

    @Test func remotoYSesionesQueNoSonSSH() throws {
        let r = Tunnel(name: "r", session: "ficheros", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1", targetPort: 22)
        let a = try args(r)                                    // (sftp es ssh: vale)
        #expect(a[try #require(a.firstIndex(of: "-R")) + 1] == "localhost:9000:127.0.0.1:22")
        #expect(Array(a.suffix(2)) == ["--", "ficheros"])
        #expect(throws: TunnelError.notSSH("olt-01")) { try args(Tunnel(name: "t", session: "olt-01", targetHost: "192.0.2.10")) }
        #expect(throws: TunnelError.noSession("no-existe")) { try args(Tunnel(name: "t", session: "no-existe", targetHost: "192.0.2.10")) }
        #expect(throws: (any Error).self) { try args(Tunnel(name: "t", session: "-oProxyCommand=x", targetHost: "192.0.2.10")) }
        #expect(throws: (any Error).self) { try args(Tunnel(name: "t", session: "core-01", listenAddress: "0.0.0.0", targetHost: "192.0.2.10")) }
    }
}

@Suite struct TunelArchivoTests {
    func tempURL() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("tuneles-\(UUID().uuidString)", isDirectory: true)
        AppPaths.ensure(d)
        return d.appendingPathComponent("tuneles.json")
    }

    let sample = [Tunnel(name: "web", session: "core-01", listenPort: 8080, targetHost: "192.0.2.10", targetPort: 80),
                  Tunnel(name: "socks", server: "tu.usuario@192.0.2.20", jump: "bastion", kind: .dynamic, listenPort: 1080),
                  Tunnel(name: "vuelta", session: "core-01", kind: .remote, listenAddress: "0.0.0.0", listenPort: 9000,
                         targetHost: "127.0.0.1", targetPort: 22, exposed: true)]

    @Test func idaYVuelta() throws {
        let url = tempURL()
        try TunnelLibrary(tunnels: sample).save(to: url)
        let r = TunnelLibrary.load(from: url)
        #expect(r.error == nil && r.warnings.isEmpty)
        #expect(r.library.tunnels == sample)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        try TunnelLibrary(tunnels: []).save(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path + ".anterior"))
        #expect(throws: (any Error).self) { try TunnelLibrary(tunnels: [sample[0], sample[0]]).save(to: url) }
    }

    @Test func uuidDuplicadoConDistintoNombreNoTocaNada() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try TunnelLibrary(tunnels: sample).save(to: url)
        try TunnelLibrary(tunnels: [sample[0]]).save(to: url)
        try SafeFile.write("copia anterior ilegible", to: url.appendingPathExtension("ilegible"))
        let files = [url] + ["anterior", "original", "ilegible"].map { url.appendingPathExtension($0) }
        let before = try files.map { try Data(contentsOf: $0) }
        var duplicate = sample[0]
        duplicate.name = "otro nombre"
        let lib = TunnelLibrary(tunnels: [sample[0], duplicate])
        #expect(lib.problem == L("Hay dos túneles con el mismo identificador"))
        for aside in [false, true] {
            #expect(throws: (any Error).self) { try lib.save(to: url, setAsideUnusable: aside) }
            #expect(try files.map { try Data(contentsOf: $0) } == before)
        }
        let missing = url.deletingLastPathComponent().appendingPathComponent("sin-crear/tuneles.json")
        #expect(throws: (any Error).self) { try lib.save(to: missing, setAsideUnusable: true) }
        #expect(!FileManager.default.fileExists(atPath: missing.deletingLastPathComponent().path))
    }

    @Test func cargaUuidDuplicadoConAvisoSinModificarElArchivo() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var duplicate = sample[0]
        duplicate.name = "otro nombre"
        struct File: Encodable { let version = 1; let tuneles: [Tunnel] }
        let data = try JSONEncoder().encode(File(tuneles: [sample[0], duplicate]))
        try SafeFile.write(String(decoding: data, as: UTF8.self), to: url)
        let loaded = TunnelLibrary.load(from: url)
        #expect(loaded.error == nil && loaded.warnings.count == 1)
        #expect(loaded.library.tunnels == [sample[0]])
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func corruptoOVersionDesconocidaNoSePierde() throws {
        for text in ["{ esto no es json", #"{"version": 7, "tuneles": []}"#] {
            let url = tempURL()
            try SafeFile.write(text, to: url)
            let r = TunnelLibrary.load(from: url)
            #expect(r.error != nil && r.library.tunnels.isEmpty)
            #expect(try SafeFile.read(url) == text)                    // (leerlo no lo toca)
            try TunnelLibrary(tunnels: [sample[0]]).save(to: url, setAsideUnusable: true)
            #expect(try SafeFile.read(url.appendingPathExtension("ilegible")) == text)
            #expect(TunnelLibrary.load(from: url).library.tunnels == [sample[0]])
        }
    }

    @Test func falloAlRecuperarIlegibleRestauraArchivoYCopia() throws {
        for partial in [false, true] {
            for existingAside in [false, true] {
                let url = tempURL(), aside = url.appendingPathExtension("ilegible")
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                let before = Data([0xff, 0x00, 0x01])             // (también si ni siquiera es UTF-8)
                try before.write(to: url)
                let previous = "copia ilegible anterior"
                if existingAside { try SafeFile.write(previous, to: aside) }
                #expect(throws: (any Error).self) {
                    try TunnelLibrary(tunnels: [sample[0]]).save(to: url, setAsideUnusable: true, write: { text, destination in
                        if partial { try SafeFile.write(text, to: destination) }
                        throw CocoaError(.fileWriteNoPermission)
                    })
                }
                #expect(try Data(contentsOf: url) == before)
                #expect(try SafeFile.read(aside) == (existingAside ? previous : nil))
                let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
                #expect(Set(files) == Set(existingAside ? ["tuneles.json", "tuneles.json.ilegible"] : ["tuneles.json"]))
            }
        }
    }

    @Test func entradasInvalidasSeIgnoranConAviso() throws {
        let url = tempURL()
        try SafeFile.write("""
            {"version": 1, "tuneles": [
              {"nombre": "bueno", "sesion": "core-01", "tipo": "local", "puerto": 8080, "destino": "192.0.2.10", "puerto-destino": 80},
              {"nombre": "puerto", "sesion": "core-01", "tipo": "local", "puerto": 0, "destino": "192.0.2.10", "puerto-destino": 80},
              {"nombre": "abierto", "sesion": "core-01", "tipo": "socks", "escucha": "0.0.0.0", "puerto": 1080},
              {"nombre": "raro", "tipo": "otro", "puerto": 1},
              {"nombre": "bueno", "sesion": "core-01", "tipo": "socks", "puerto": 1081}
            ]}
            """, to: url)
        let r = TunnelLibrary.load(from: url)
        #expect(r.error == nil)
        #expect(r.library.tunnels.map(\.name) == ["bueno"])
        #expect(r.warnings.count == 4)
    }
}

/// El ciclo de vida con un ejecutable de prueba en lugar de ssh (un script en una carpeta temporal).
@MainActor @Suite(.serialized) struct TunelProcesoTests {
    let dir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("tunel-\(UUID().uuidString)", isDirectory: true)
        AppPaths.ensure(d)
        return d
    }()

    func script(_ body: String, configuration: String = "printf 'host core-01\\nclearallforwardings no\\n'; exit 0") throws -> String {
        let url = dir.appendingPathComponent("ssh-\(UUID().uuidString.prefix(6)).sh")
        let check = "if [ \"$1\" = '-G' ]; then\n" + configuration + "\nfi\n"
        try ("#!/bin/sh\n" + check + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0o755)
        return url.path
    }

    func arguments(_ t: Tunnel, config: String = "/dev/null") throws -> [String] {
        let endpoint = Endpoint(parsing: t.server) ?? Endpoint(host: "192.0.2.11")
        let route = ConnectionRoute(title: t.name, target: endpoint, alias: t.session.isEmpty ? nil : t.session)
        return try t.arguments(route: route, sharing: nil, configFile: config)
    }

    func runner() -> TunnelManager {
        let m = TunnelManager()
        m.pollInterval = 0.05
        m.remoteGrace = 0.3
        m.killAfter = 0.6
        return m
    }

    /// Un puerto libre de 127.0.0.1 (el sistema lo elige).
    func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var a = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: 0,
                            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        return Int(UInt16(bigEndian: a.sin_port))
    }

    /// Escucha en 127.0.0.1:port (como haría ssh con -L); devuelve el descriptor para cerrarlo.
    func listen(_ port: Int) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var a = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET),
                            sin_port: UInt16(port).bigEndian, sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
                            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        Darwin.listen(fd, 4)
        return fd
    }

    func until(_ timeout: Double = 5, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return cond()
    }

    let env = ["PATH": "/usr/bin:/bin"]

    @Test func localActivoCuandoEscuchaYParar() async throws {
        let port = freePort()
        let exe = try script("echo $$ > '\(dir.path)/pid'\nexec sleep 30")
        let t = Tunnel(name: "web", session: "core-01", listenPort: port, targetHost: "192.0.2.10")
        let m = runner()
        var seen: [TunnelState] = []
        m.onChange = { _, s in seen.append(s) }
        m.start(t, executable: exe, arguments: try arguments(t), environment: env)
        #expect(m.state(t.id) == .starting)
        // (primero que la conexión haya arrancado, tras el preflight: si se escucha antes, el gestor ve el puerto ocupado
        // al lanzarla y falla, que es lo correcto; con un sleep fijo eso dependía de lo que tardase el preflight)
        try #require(await until(30) { FileManager.default.fileExists(atPath: dir.appendingPathComponent("pid").path) })
        #expect(m.state(t.id) == .starting)                    // (aún no escucha nadie)
        let fd = listen(port)
        defer { close(fd) }
        #expect(await until { m.state(t.id) == .active })
        #expect(m.activeCount == 1)
        let pid = try #require(Int32(String(contentsOf: dir.appendingPathComponent("pid"), encoding: .utf8).trimmed))
        await m.stop(t.id)
        #expect(m.state(t.id) == .stopped)
        #expect(kill(pid, 0) != 0)                              // (ya no existe)
        #expect(seen == [.starting, .active, .stopped])
    }

    @Test func remotoActivoAlEntrar() async throws {
        let exe = try script(#"echo 'Authenticated to core-01 ([192.0.2.11]:22) using "publickey".' >&2"# + "\nexec sleep 30")
        let t = Tunnel(name: "r", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1", targetPort: 22)
        let m = runner()
        m.start(t, executable: exe, arguments: try arguments(t), environment: env)
        #expect(await until { m.state(t.id) == .active })
        await m.stop(t.id)
        #expect(m.state(t.id) == .stopped)
    }

    @Test func errorLeidoDeStderr() async throws {
        let port = freePort()
        let inUse = try script("""
            echo "bind [127.0.0.1]:\(port): Address already in use" >&2
            echo "channel_setup_fwd_listener_tcpip: cannot listen to port: \(port)" >&2
            echo "Could not request local forwarding." >&2
            exit 255
            """)
        let t = Tunnel(name: "web", session: "core-01", listenPort: port, targetHost: "192.0.2.10")
        let m = runner()
        m.start(t, executable: inUse, arguments: try arguments(t), environment: env)
        #expect(await until { if case .failed = m.state(t.id) { true } else { false } })
        #expect(m.state(t.id) == .failed(TunnelFailure.reason(stderr: "Address already in use", status: nil)))

        let auth = try script("echo 'tu.usuario@192.0.2.11: Permission denied (publickey,password).' >&2\nexit 255")
        let a = Tunnel(name: "a", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1", targetPort: 22)
        m.start(a, executable: auth, arguments: try arguments(a), environment: env)
        #expect(await until { if case .failed(let w) = m.state(a.id) { w.contains("Permission denied") } else { false } })
    }

    /// El resumen para la interfaz pierde el equipo; el registro de contraseñas recibe el rechazo original.
    @Test func rechazoDelDestinoNoBloqueaLaContrasenaDelSalto() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let sid = UUID(), ref = CredentialRef.device("tu.usuario", "bastion"), ledger = CredentialLedger()
        try SafeFile.write(Askpass.encodeGiven(ref, host: "bastion") + "\n", to: dir.appendingPathComponent(sid.uuidString))
        let exe = try script("echo 'tu.usuario@core-01: Permission denied (publickey).' >&2\nexit 255")
        let t = Tunnel(name: "web", session: "core-01", kind: .remote, targetHost: "127.0.0.1")
        let m = runner()
        defer { m.onChange = nil; m.stopAll(wait: 0) }
        var settled = false, failed: [CredentialRef] = []
        m.onChange = { id, state in
            if case .failed = state {
                failed = Askpass.settleAfterExit(session: sid, ledger: ledger, directory: dir) { m.authenticationRejection(for: id) }
                settled = true
            }
        }
        m.start(t, executable: exe, arguments: try arguments(t), environment: env)
        #expect(await until { settled })
        #expect(m.state(t.id) == .failed(TunnelFailure.reason(stderr: "Permission denied", status: nil)))
        #expect(m.authenticationRejection(for: t.id)?.host == "core-01")
        // (ni bloqueada ni confirmada: un rechazo que no nombra ningún equipo de los intentos no demuestra que alguno
        // entrara —con HostKeyAlias o la IP del corte sería el rechazado—; sin marca se usa igual que confirmada)
        #expect(failed.isEmpty && !ledger.isBlocked(ref) && ledger.state(of: ref) == nil)
    }

    /// El túnel no entra con la de su sesión: se dice cuál, pero no se bloquea (es de la sesión, no la por defecto).
    @Test func rechazoPropioSeDiceSinBloquear() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let sid = UUID(), ref = CredentialRef.named("AD"), ledger = CredentialLedger()
        try SafeFile.write(Askpass.encodeGiven(ref, host: "core-01") + "\n", to: dir.appendingPathComponent(sid.uuidString))
        let exe = try script("echo 'tu.usuario@core-01: Permission denied (publickey,password).' >&2\nexit 255")
        let t = Tunnel(name: "web", session: "core-01", kind: .remote, targetHost: "127.0.0.1")
        let m = runner()
        defer { m.onChange = nil; m.stopAll(wait: 0) }
        var failed: [CredentialRef] = []
        m.onChange = { id, state in
            if case .failed = state {
                failed = Askpass.settleAfterExit(session: sid, ledger: ledger, directory: dir) { m.authenticationRejection(for: id) }
            }
        }
        m.start(t, executable: exe, arguments: try arguments(t), environment: env)
        #expect(await until { if case .failed = m.state(t.id) { true } else { false } })
        #expect(failed == [ref] && !ledger.isBlocked(ref))
    }

    @Test func unFalloDeRedNoBloqueaContrasenas() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let sid = UUID(), ref = CredentialRef.named("AD"), ledger = CredentialLedger()
        try SafeFile.write(Askpass.encodeGiven(ref, host: "core-01") + "\n", to: dir.appendingPathComponent(sid.uuidString))
        let exe = try script("echo 'ssh: connect to host core-01 port 22: Connection refused' >&2\nexit 255")
        let t = Tunnel(name: "web", session: "core-01", kind: .remote, targetHost: "127.0.0.1")
        let m = runner()
        defer { m.onChange = nil; m.stopAll(wait: 0) }
        var settled = false
        m.onChange = { id, state in
            if case .failed = state {
                #expect(Askpass.settleAfterExit(session: sid, ledger: ledger, directory: dir) { m.authenticationRejection(for: id) }.isEmpty)
                settled = true
            }
        }
        m.start(t, executable: exe, arguments: try arguments(t), environment: env)
        #expect(await until { settled })
        #expect(m.authenticationRejection(for: t.id) == nil && !ledger.isBlocked(ref))
    }

    @Test func elRechazoNoSobreviveAReinicioParadaOBorrado() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let auth = try script("echo 'tu.usuario@core-01: Permission denied (publickey,password).' >&2\nexit 255")
        let config = try script("exit 255", configuration: "echo 'ssh_config: Permission denied' >&2\nexit 255")
        let t = Tunnel(name: "web", session: "core-01", kind: .remote, targetHost: "127.0.0.1")
        let m = runner(), args = try arguments(t)
        defer { m.onChange = nil; m.stopAll(wait: 0) }
        for action in 0..<4 {
            m.start(t, executable: auth, arguments: args, environment: env)
            #expect(await until { m.authenticationRejection(for: t.id) != nil })
            switch action {
            case 0:
                m.onChange = { id, state in if state == .starting { #expect(m.authenticationRejection(for: id) == nil) } }
                m.start(t, executable: config, arguments: args, environment: env)
                #expect(await until { if case .failed = m.state(t.id) { true } else { false } })
            case 1: await m.stop(t.id)
            case 2: await m.forget(t.id)
            default: m.markFailed(t.id, "Permission denied")
            }
            #expect(m.authenticationRejection(for: t.id) == nil)
        }
    }

    @Test func siSshMuereQuedaEnErrorSinRelanzar() async throws {
        let exe = try script("""
            echo x >> '\(dir.path)/veces'
            echo 'Authenticated to core-01 ([192.0.2.11]:22) using "publickey".' >&2
            while [ ! -f '\(dir.path)/sigue' ]; do sleep 0.05; done
            echo 'Connection to 192.0.2.11 closed by remote host.' >&2
            exit 255
            """)
        let t = Tunnel(name: "r", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1", targetPort: 22)
        let m = runner()
        m.start(t, executable: exe, arguments: try arguments(t), environment: env)
        // (la caída, cuando ya se ha visto activo: sin depender de en qué momento despierte la vigilancia del gestor)
        #expect(await until(30) { m.state(t.id) == .active })
        FileManager.default.createFile(atPath: dir.appendingPathComponent("sigue").path, contents: nil)
        #expect(await until(30) { if case .failed = m.state(t.id) { true } else { false } })
        #expect(m.state(t.id) == .failed("Connection to 192.0.2.11 closed by remote host."))
        try? await Task.sleep(for: .milliseconds(500))
        #expect(try String(contentsOf: dir.appendingPathComponent("veces"), encoding: .utf8) == "x\n")
        #expect(m.state(t.id) != .starting)
    }

    @Test func pararConSigkillSiNoSale() async throws {
        let exe = try script("""
            trap '' TERM
            echo $$ > '\(dir.path)/pid-terco'
            echo 'Authenticated to core-01' >&2
            while :; do sleep 0.1; done
            """)
        let t = Tunnel(name: "terco", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1", targetPort: 22)
        let m = runner()
        m.start(t, executable: exe, arguments: try arguments(t), environment: env)
        #expect(await until { m.state(t.id) == .active })
        let pid = try #require(Int32(String(contentsOf: dir.appendingPathComponent("pid-terco"), encoding: .utf8).trimmed))
        let start = Date()
        await m.stop(t.id)
        #expect(Date().timeIntervalSince(start) >= 0.5)        // (esperó a SIGTERM antes del SIGKILL)
        #expect(m.state(t.id) == .stopped)
        #expect(kill(pid, 0) != 0)
    }

    @Test func pararTodosAlSalir() async throws {
        let exe = try script("trap '' TERM\necho 'Authenticated to core-01' >&2\nwhile :; do sleep 0.1; done")
        let m = runner()
        let ts = (0..<2).map { Tunnel(name: "t\($0)", session: "core-01", kind: .remote, listenPort: 9000 + $0, targetHost: "127.0.0.1", targetPort: 22) }
        for t in ts { m.start(t, executable: exe, arguments: try arguments(t), environment: env) }
        #expect(await until { ts.allSatisfy { m.state($0.id) == .active } })
        m.stopAll(wait: 0.3)
        #expect(ts.allSatisfy { m.state($0.id) == .stopped })
        #expect(m.activeCount == 0)
    }

    @Test func puertoOcupadoAntesDeIniciar() async throws {
        let port = freePort()
        var fd = listen(port)
        defer { if fd >= 0 { close(fd) } }
        #expect(PortCheck.problem(address: "127.0.0.1", port: port) != nil)
        #expect(PortCheck.isListening(address: "127.0.0.1", port: port))
        let marker = dir.appendingPathComponent("lanzado")
        let exe = try script("touch '\(marker.path)'\nexec sleep 30")
        let t = Tunnel(name: "web", session: "core-01", listenPort: port, targetHost: "192.0.2.10")
        let m = runner()
        m.start(t, executable: exe, arguments: try arguments(t), environment: env)
        guard case .failed(let why) = m.state(t.id) else { Issue.record("no se ha detectado: \(m.state(t.id))"); return }
        #expect(why.contains(String(port)))
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: marker.path))      // (ssh ni se ha lanzado)
        close(fd)
        fd = -1
        #expect(PortCheck.problem(address: "127.0.0.1", port: port) == nil)
        #expect(PortCheck.problem(address: "192.0.2.77", port: port) != nil)   // (no es de este Mac)
    }

    /// Con el ssh de verdad (sin ssh_config: -F /dev/null) contra un puerto cerrado de este Mac: sale con su error.
    @Test func sshDeVerdadPuertoCerrado() async throws {
        let closed = freePort(), port = freePort()
        let t = Tunnel(name: "real", server: "tu.usuario@127.0.0.1:\(closed)", listenPort: port, targetHost: "192.0.2.10")
        let route = ConnectionRoute(title: "real", target: try #require(Endpoint(parsing: t.server)))
        let args = try t.arguments(route: route, sharing: nil, configFile: "/dev/null")
        let m = runner()
        m.start(t, executable: "/usr/bin/ssh", arguments: args, environment: env)
        #expect(await until(10) { if case .failed = m.state(t.id) { true } else { false } })
        #expect(m.state(t.id) == .failed(TunnelFailure.reason(stderr: "Connection refused", status: nil)))
    }

    /// Sólo «-G» usa el ssh real: el cuerpo de conexión deja una marca, jamás conecta a estos equipos.
    @Test func rechazaForwardsDeAliasComodinMatchEInclude() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("conexion")
        let exe = try script("touch '\(marker.path)'\nexec sleep 30", configuration: "exec /usr/bin/ssh \"$@\"")
        let forwards = ["LocalForward 0.0.0.0:18080 192.0.2.20:80",
                        "RemoteForward 0.0.0.0:19000 192.0.2.20:22", "DynamicForward 0.0.0.0:11080"]
        for forward in forwards {
            // («Match host» compara con el HostName ya sustituido, no con el alias: «Match host core-01» no aplica, ni
            // en ssh -G ni al conectar; los que sí aplican al alias o al equipo son estos)
            for scope in ["Host core-01", "Host *", "Match originalhost core-01", "Match host 192.0.2.11", "Match final", "Include"] {
                try? FileManager.default.removeItem(at: marker)            // (cada caso por separado)
                let cfg = dir.appendingPathComponent("ssh_config")
                let extra = dir.appendingPathComponent("incluido")
                try SafeFile.write("Host *\n  \(forward)\n", to: extra)
                let block = scope == "Include" ? "Host *\n  Include \(extra.path)" : "\(scope)\n  \(forward)"
                try SafeFile.write("""
                    Host core-01
                      HostName 192.0.2.11
                      User tu.usuario
                      CanonicalizeHostname no
                    Host *
                      ClearAllForwardings yes
                    \(block)
                    """, to: cfg)
                let t = Tunnel(name: "web", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1", exposed: true)
                let m = runner()
                defer { m.stopAll(wait: 0) }
                m.start(t, executable: exe, arguments: try arguments(t, config: cfg.path), environment: env)
                #expect(await until { if case .failed = m.state(t.id) { true } else { false } })
                guard case .failed(let why) = m.state(t.id) else { continue }
                #expect(why.contains("reenvíos heredados"), "\(scope): \(forward): \(why)")
                #expect(!FileManager.default.fileExists(atPath: marker.path))
                #expect(m.activeCount == 0)
            }
        }
    }

    @Test func sshGConservaAutenticacionYSaltosYUnSoloForward() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = dir.appendingPathComponent("ssh_config"), key = dir.appendingPathComponent("llave")
        try SafeFile.write("""
            Host core-01
              HostName 192.0.2.11
              User tu.usuario
              Port 2222
              IdentityFile \(key.path)
              IdentitiesOnly yes
              ProxyJump bastion
            Host bastion
              HostName 192.0.2.1
            Host *
              ClearAllForwardings yes
              ForkAfterAuthentication yes
              GatewayPorts yes
            """, to: cfg)
        for kind in Tunnel.Kind.allCases {
            let t = Tunnel(name: "web", session: "core-01", kind: kind, targetHost: "192.0.2.20")
            let args = try arguments(t, config: cfg.path)
            let check = try TunnelProcess(executable: "/usr/bin/ssh", arguments: t.configurationArguments(arguments: args),
                                          environment: env, captureOutput: true)
            defer { check.signal(SIGKILL) }
            #expect(await until { check.exited })
            #expect(check.exitStatus == 0 && !check.outputTruncated)
            #expect(Tunnel.configurationProblem(check.errorOutput) == nil)
            for value in ["hostname 192.0.2.11", "user tu.usuario", "port 2222", "identityfile \(key.path)",
                          "identitiesonly yes", "proxyjump bastion", "clearallforwardings no", "forkafterauthentication no", "gatewayports no"] {
                #expect(check.errorOutput.contains(value), "falta \(value)")
            }
            // (-G también en la orden final: el ClearAllForwardings del archivo no se lleva el de CLI)
            let final = try TunnelProcess(executable: "/usr/bin/ssh", arguments: ["-G"] + args, environment: env, captureOutput: true)
            defer { final.signal(SIGKILL) }
            #expect(await until { final.exited })
            #expect(final.exitStatus == 0)
            let forwards = final.errorOutput.split(separator: "\n").filter {
                ["localforward", "remoteforward", "dynamicforward"].contains(String($0.split(separator: " ").first ?? ""))
            }
            #expect(forwards.count == 1)
            #expect(forwards.first?.contains(String(t.listenPort)) == true)
        }
    }

    @Test func preflightFallidoIncompletoOTruncadoNoArranca() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("conexion")
        let bad = ["echo 'Bad configuration option: noexiste' >&2; exit 255", "exit 0",
                   "awk 'BEGIN {print \"host core-01\"; print \"clearallforwardings no\"; for (i=0; i<70000; i++) print \"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}'; exit 0"]
        for config in bad {
            let exe = try script("touch '\(marker.path)'\nexec sleep 30", configuration: config)
            let t = Tunnel(name: "web", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1")
            let m = runner()
            defer { m.stopAll(wait: 0) }
            m.start(t, executable: exe, arguments: try arguments(t), environment: env)
            #expect(await until { if case .failed = m.state(t.id) { true } else { false } })
            #expect(!FileManager.default.fileExists(atPath: marker.path))
        }
    }

    @Test func falloDeSpawnTrasPreflightQuedaEnError() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let exe = try script("exec sleep 30", configuration: "rm -- \"$0\"\nprintf 'host core-01\\nclearallforwardings no\\n'\nexit 0")
        let t = Tunnel(name: "web", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1")
        let m = runner()
        defer { m.stopAll(wait: 0) }
        m.start(t, executable: exe, arguments: try arguments(t), environment: env)
        #expect(await until { if case .failed(let why) = m.state(t.id) { why.contains("No arranca") } else { false } })
        #expect(m.activeCount == 0)
        await m.stop(t.id)
        #expect(m.state(t.id) == .stopped)
    }

    @Test func preflightCanceladoYOAgotadoMataTambienHijos() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        for timeout in [false, true] {
            let parent = dir.appendingPathComponent("padre"), child = dir.appendingPathComponent("hijo")
            let marker = dir.appendingPathComponent("conexion")
            try? FileManager.default.removeItem(at: parent)
            try? FileManager.default.removeItem(at: child)
            let config = "trap '' TERM\necho $$ > '\(parent.path)'\nsleep 30 &\necho $! > '\(child.path)'\nwait"
            let exe = try script("touch '\(marker.path)'\nexec sleep 30", configuration: config)
            let t = Tunnel(name: "web", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1")
            let m = runner()
            defer { m.stopAll(wait: 0) }
            m.configurationTimeout = 60
            m.start(t, executable: exe, arguments: try arguments(t), environment: env)
            // (primero que el preflight haya arrancado y tenga su hijo; luego, que se agote: en ese orden siempre, sin
            // competir con lo que tarde en arrancar /bin/sh con el resto de la suite en marcha)
            try #require(await until(30) {
                (try? String(contentsOf: child, encoding: .utf8)).flatMap { Int32($0.trimmed) } != nil
            })
            let p = try #require(Int32(String(contentsOf: parent, encoding: .utf8).trimmed))
            let c = try #require(Int32(String(contentsOf: child, encoding: .utf8).trimmed))
            if timeout {
                m.configurationTimeout = 0
                #expect(await until { if case .failed(let why) = m.state(t.id) { why.contains("ssh -G no ha contestado") } else { false } })
            } else {
                await m.stop(t.id)
                #expect(m.state(t.id) == .stopped)
            }
            #expect(await until { kill(p, 0) != 0 && kill(c, 0) != 0 })
            #expect(!FileManager.default.fileExists(atPath: marker.path))
            #expect(m.activeCount == 0)
        }
    }

    @Test func salirDuranteElPreflightNoLanzaLaConexion() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("conexion"), pid = dir.appendingPathComponent("pid")
        let exe = try script("touch '\(marker.path)'\nexec sleep 30", configuration: "echo $$ > '\(pid.path)'\nexec sleep 30")
        let t = Tunnel(name: "web", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1")
        let m = runner()
        m.start(t, executable: exe, arguments: try arguments(t), environment: env)
        #expect(await until { FileManager.default.fileExists(atPath: pid.path) })
        let p = try #require(Int32(String(contentsOf: pid, encoding: .utf8).trimmed))
        m.stopAll(wait: 0)
        #expect(m.state(t.id) == .stopped && kill(p, 0) != 0)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func cancelarLaTareaDeParadaNoBloqueaNiDejaElProceso() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let pid = dir.appendingPathComponent("pid")
        let exe = try script("trap '' TERM\necho $$ > '\(pid.path)'\necho 'Authenticated to core-01' >&2\nexec sleep 30")
        let t = Tunnel(name: "web", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1")
        let m = runner()
        defer { m.stopAll(wait: 0) }
        m.start(t, executable: exe, arguments: try arguments(t), environment: env)
        #expect(await until { m.state(t.id) == .active })
        let p = try #require(Int32(String(contentsOf: pid, encoding: .utf8).trimmed))
        var finished = false
        let stopping = Task { await m.stop(t.id); finished = true }
        stopping.cancel()
        #expect(await until { finished })
        await stopping.value
        #expect(m.state(t.id) == .stopped && kill(p, 0) != 0)
    }

    @Test func paradaAntiguaNoPisaReinicioConElMismoId() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let exe = try script("echo 'Authenticated to core-01' >&2\nexec sleep 30")
        let t = Tunnel(name: "web", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1")
        let m = runner(), args = try arguments(t)
        defer { m.onChange = nil; m.stopAll(wait: 0) }
        m.start(t, executable: exe, arguments: args, environment: env)
        #expect(await until { m.state(t.id) == .active })
        var restarted = false
        m.onChange = { _, state in
            if state == .stopped, !restarted {
                restarted = true
                m.start(t, executable: exe, arguments: args, environment: env)
            }
        }
        await m.stop(t.id)
        #expect(restarted)
        #expect(await until { m.state(t.id) == .active })
    }

    @Test func liberarElGestorNoRetieneProcesos() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let pid = dir.appendingPathComponent("pid")
        let exe = try script("echo $$ > '\(pid.path)'\necho 'Authenticated to core-01' >&2\nexec sleep 30")
        let t = Tunnel(name: "web", session: "core-01", kind: .remote, listenPort: 9000, targetHost: "127.0.0.1")
        var m: TunnelManager? = runner()
        weak var held = m
        m?.start(t, executable: exe, arguments: try arguments(t), environment: env)
        #expect(await until { m?.state(t.id) == .active })
        let p = try #require(Int32(String(contentsOf: pid, encoding: .utf8).trimmed))
        m = nil
        #expect(await until { held == nil && kill(p, 0) != 0 })
    }

    @Test func salidaInmediataConservaEstadoYUltimoError() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let exe = try script("echo 'fallo final' >&2\nexit 37")
        for _ in 0..<20 {
            let p = try TunnelProcess(executable: exe, arguments: [], environment: env)
            defer { p.signal(SIGKILL) }
            #expect(await until { p.exited })
            #expect(p.exitStatus == 37 << 8)
            #expect(p.errorOutput == "fallo final\n")
        }
    }

    @Test func siMuereElPadreNoQuedaElProxyCommand() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let pid = dir.appendingPathComponent("hijo")
        let exe = try script("sleep 30 &\necho $! > '\(pid.path)'\necho 'fallo final' >&2\nexit 37")
        let p = try TunnelProcess(executable: exe, arguments: [], environment: env)
        defer { p.signal(SIGKILL) }
        #expect(await until { p.exited })
        let child = try #require(Int32(String(contentsOf: pid, encoding: .utf8).trimmed))
        #expect(await until { kill(child, 0) != 0 })
        #expect(p.exitStatus == 37 << 8)
    }

    @Test func motivos() {
        #expect(TunnelFailure.reason(stderr: "Warning: remote port forwarding failed for listen port 80\n", status: 65280)
            .contains("remote port forwarding failed"))
        #expect(TunnelFailure.reason(stderr: "channel 0: open failed: administratively prohibited: open failed", status: nil)
            .contains("administratively prohibited"))
        #expect(TunnelFailure.reason(stderr: "ssh: Could not resolve hostname nada: nodename nor servname provided", status: nil)
            .contains("Could not resolve hostname"))
        #expect(TunnelFailure.reason(stderr: "Authenticated to core-01\n", status: 255 << 8) == "ssh ha terminado (código 255)")
        #expect(TunnelFailure.reason(stderr: "", status: 9) == "ssh ha terminado (señal 9)")
    }
}

/// Sólo cuenta como «este Mac» una IP numérica de 127/8, ::1 (o mapeada) o localhost: un nombre que empieza por
/// «127.» lo resuelve el DNS a donde quiera, y escuchar en él exige marcarlo expresamente.
@Suite struct TunelLoopbackTests {
    @Test func soloIPsDeVerdad() {
        for a in ["127.0.0.1", "127.1.2.3", "127.255.255.254", "::1", "[::1]", "localhost", "LOCALHOST", "::ffff:127.0.0.1"] {
            #expect(Tunnel.isLoopback(a), "\(a)")
        }
        for a in ["127.mac.example.net", "127.0.0.1.example.net", "127.0.0", "127.0.0.256", "127.a.b.c", "1270.0.0.1",
                  "128.0.0.1", "0.0.0.0", "*", "::", "192.0.2.1", "localhost.example.net", "::ffff:192.0.2.1", ""] {
            #expect(!Tunnel.isLoopback(a), "\(a)")
        }
        let t = Tunnel(name: "web", session: "core-01", listenAddress: "127.mac.example.net", listenPort: 8080, targetHost: "192.0.2.10")
        #expect(t.problem != nil)                                           // (sin marcarlo, no)
    }
}
