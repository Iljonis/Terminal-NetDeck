import Darwin
import Foundation
import Testing
@testable import NetDeckCore

/// MultiExec: lo tecleado donde piden un secreto no sale de esa pestaña, y a las que se autentican no les llega nada.
@Suite @MainActor struct MultiExecSecretosTests {
    var paster: SafePaster {
        var p = SafePaster()
        p.poll = .milliseconds(5)
        p.quiet = .milliseconds(20)
        p.lineTimeout = .seconds(2)
        return p
    }

    @Test func peticionesDeSecretos() {
        for l in ["tu.usuario@192.0.2.1's password: ", "Enter passphrase for key '/Users/x/.ssh/id_ed25519': ",
                  "Verification code: ", "One-time password (OATH) for `tu.usuario': ", "Enter PASSCODE:",
                  "Passcode or option (1-3): ", "Enter PIN for 'PIV Card Holder pin (PIV_II)': ", "Token code:",
                  "[NetDeck] tu.usuario@192.0.2.1's password: ",
                  "Are you sure you want to continue connecting (yes/no/[fingerprint])? ", "Código de verificación:"] {
            #expect(SecretPrompt.asks(l), "\(l)")
        }
        // (el sí/no de guardarla no es un secreto: tampoco es un prompt, y mientras se autentica la pestaña no reparte)
        for l in ["core-01#", "core-01#show run | i password:", "tu.usuario@bastion:~$ ", "Username: ",
                  "[NetDeck] ¿Guardarla como «AD»? [S/n] (Esc = no) ",
                  "core-01(config)#crypto pki token default removal timeout:", "Building configuration..."] {
            #expect(!SecretPrompt.asks(l), "\(l)")
        }
    }

    /// Contraseña, passphrase y OTP tecleados a mano en una: no llegan a ninguna otra, ni siquiera cuando el equipo
    /// pinta asteriscos (hasta el Intro); luego todo vuelve a repartirse, menos a las que siguen autenticándose.
    @Test func elSecretoNoSaleDeSuPestaña() {
        let pw = FakeTerminal(["tu.usuario@192.0.2.1's password: "]), core = FakeTerminal(["core-02#"])
        let key = FakeTerminal(["Enter passphrase for key '/k': "]), otp = FakeTerminal(["Verification code: "])
        let askpass = FakeTerminal(["[NetDeck] tu.usuario@192.0.2.3's password: "])
        let g = MultiExecGroup()
        g.isActive = true
        [pw, core, key, otp, askpass].forEach(g.join)

        #expect(!g.broadcast(Array("s3cr".utf8), from: pw))          // (la vista lo envía sólo a la suya)
        pw.screen[0] += "****"                                       // (equipos que pintan asteriscos)
        #expect(!g.broadcast(Array("3t".utf8), from: pw))
        #expect(!g.broadcast([13], from: pw))
        #expect(!g.broadcast(Array("123456".utf8), from: otp))
        #expect(!g.broadcast(Array("frase".utf8), from: key))
        #expect([core, key, otp, askpass, pw].allSatisfy { $0.sent.isEmpty })

        pw.screen.append("core-01#")                                 // (ha entrado)
        #expect(g.broadcast(Array("show clock\r".utf8), from: core))
        #expect(pw.sent == ["show clock\r"] && core.sent == ["show clock\r"])
        #expect(key.sent.isEmpty && otp.sent.isEmpty && askpass.sent.isEmpty)
        // (y lo empezado en la del OTP sigue siendo suyo aunque la pantalla cambie, hasta su Intro)
        otp.screen.append("core-03#")
        #expect(!g.broadcast(Array("7".utf8), from: otp))
        #expect(!g.broadcast([13], from: otp))
        #expect(g.broadcast(Array("x".utf8), from: otp))
    }

    /// La app añade «aún no ha llegado a su prompt»: lo tecleado lo leería el askpass como contraseña. Ni las teclas,
    /// ni el pegado ni los botones (que filtran con `accepts`) le llegan.
    @Test func lasQueSeAutenticanQuedanFuera() async {
        let a = FakeTerminal(["core-01#"]) { _ in ["core-01#"] }, b = FakeTerminal(["core-02#"]) { _ in ["core-02#"] }
        let connecting = FakeTerminal([""])
        let g = MultiExecGroup()
        g.isActive = true
        g.awaitingAuth = { SecretPrompt.asks($0.cursorLine) || $0 === connecting }
        [a, b, connecting].forEach(g.join)
        #expect(g.broadcast(Array("terminal length 0\r".utf8), from: a))
        #expect(connecting.sent.isEmpty)
        #expect(!g.accepts(connecting) && g.accepts(a))
        let r = await g.paste("show version\n", paster: paster, abort: AbortSwitch())
        #expect(r.count == 2 && r.allSatisfy { $0.outcome == .completed })
        #expect(connecting.sent.isEmpty)
        #expect(!g.broadcast(Array("tu.usuario".utf8), from: connecting))
    }
}

/// FTP: un nombre con espacios delante es otro archivo; contra un servidor FTP de verdad (en este Mac, por loopback).
@Suite struct FTPEspaciosTests {
    @Test func nombresConEspaciosDelante() {
        let u = FTPParse.list("-rw-r--r--    1 u  g   5 Jan  1 12:00   oculto", in: "/d")
        #expect(u?.name == "  oculto" && u?.path == "/d/  oculto")
        #expect(FTPParse.list("-rw-r--r--    1 u  g   5 Jan  1 12:00 oculto", in: "/d")?.path == "/d/oculto")
        let w = FTPParse.list("01-31-24  09:15AM       <DIR>           oculto", in: "/d")    // (IIS: columna 39)
        #expect(w?.name == " oculto" && w?.kind == .directory)
        let wf = FTPParse.list("01-31-24  09:15AM                 1234  oculto", in: "/d")
        #expect(wf?.name == " oculto" && wf?.size == 1234)
        #expect(FTPParse.list("01-31-24  09:15AM              2048 datos.csv", in: "/")?.name == "datos.csv")
        // (sin las columnas de IIS no se sabe dónde empieza: no se enseña antes que confundirlo con otro)
        #expect(FTPParse.list("01-31-24 09:15AM 12   oculto", in: "/d") == nil)
    }

    /// Listar y borrar « oculto»: se borra ése, no «oculto» (que también existe).
    @Test func borrarElDeEspacioDelanteNoBorraOtro() async throws {
        let server = try MiniFTPServer(listing: ["-rw-r--r--    1 u  g   5 Jan  1 12:00  oculto",
                                                 "-rw-r--r--    1 u  g   7 Jan  1 12:00 oculto"])
        defer { server.stop() }
        let fs = try await FTPFileSystem.connect(label: "prueba", host: "127.0.0.1", port: Int(server.port),
                                                 user: "tu.usuario", password: "prueba")
        let list = try await fs.list("/d")
        #expect(Set(list.map(\.path)) == ["/d/ oculto", "/d/oculto"])
        let spaced = try #require(list.first { $0.name == " oculto" })
        try await RemoteOps.removeRecursively(fs, spaced, timeout: 5)
        await fs.close()
        #expect(server.commands.filter { $0.hasPrefix("DELE") } == ["DELE /d/ oculto"])
    }

    /// Subir encima de un enlace por FTP (que no dice el tipo): se mira el listado y se para antes de escribir nada.
    @Test func ftpNoSustituyeUnEnlace() async throws {
        let server = try MiniFTPServer(listing: ["lrwxrwxrwx    1 u  g   4 Jan  1 12:00 a.cfg -> real",
                                                 "drwxr-xr-x    2 u  g   4 Jan  1 12:00 conf"])
        defer { server.stop() }
        let fs = try await FTPFileSystem.connect(label: "prueba", host: "127.0.0.1", port: Int(server.port),
                                                 user: "tu.usuario", password: "prueba")
        await #expect(throws: RemoteError.self) { _ = try await AtomicRemoteWriter.open(fs, "/d/a.cfg", verify: false) }
        await #expect(throws: RemoteError.self) { _ = try await AtomicRemoteWriter.open(fs, "/d/conf", verify: false) }
        await fs.close()
        #expect(!server.commands.contains { ["STOR", "RNFR", "RNTO", "DELE"].contains(String($0.prefix(4))) })
    }
}

/// El registro de una pestaña: tope de cursor y de memoria, sin regex con los espacios del final, uno por conexión y
/// sin fallos callados.
@Suite struct RegistroRobustoTests {
    func temp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-log-\(UUID().uuidString)") }

    @Test func cursorConTope() {
        var r = LogLineRenderer()
        // (Int.max: antes desbordaba x += n)
        var out = r.feed(Array("\u{1b}[9223372036854775807Cz\n\u{1b}[99999999999999999999Cy\n".utf8))
        out += r.feed(Array("\u{1b}[50000000Gw\n".utf8))
        #expect(out.count >= 3 && out.allSatisfy { $0.count <= LogLineRenderer.maxLine })
        #expect(out.contains { $0.hasSuffix("z") } && out.contains { $0.hasSuffix("w") })
        // (una línea sin fin se corta en trozos del tope)
        var long = LogLineRenderer()
        let lines = long.feed(Array(String(repeating: "a", count: LogLineRenderer.maxLine * 2 + 10).utf8))
        #expect(lines.count == 2 && lines.allSatisfy { $0.count == LogLineRenderer.maxLine })
        #expect(long.finish()?.count == 10)
    }

    @Test(.timeLimit(.minutes(1))) func espaciosFinalesSinCoste() {
        var r = LogLineRenderer()
        let t0 = ContinuousClock.now
        let spaces = String(repeating: " ", count: 20_000)              // (la línea, por debajo del tope)
        let out = r.feed(Array((spaces + "x" + spaces + "y" + spaces + "\n" + "\u{1b}[60000Cz   \n").utf8))
        #expect(ContinuousClock.now - t0 < .seconds(10))               // (antes: 57 s y 116 s)
        #expect(out == [spaces + "x" + spaces + "y", String(repeating: " ", count: 60_000) + "z"])
    }

    /// La misma sesión dos veces en el mismo segundo: dos archivos, cada uno con lo suyo.
    @Test func unArchivoPorConexion() throws {
        let dir = temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let when = Date()
        let a = try SessionLogger(directory: dir, name: "core-01", host: "192.0.2.1", date: when)
        let b = try SessionLogger(directory: dir, name: "core-01", host: "192.0.2.2", date: when)
        #expect(a.url != b.url && b.url.lastPathComponent.hasSuffix("-2.log"))
        a.feed(Array("de a\n".utf8)[...])
        b.feed(Array("de b\n".utf8)[...])
        a.close()
        b.close()
        let ta = try String(contentsOf: a.url, encoding: .utf8), tb = try String(contentsOf: b.url, encoding: .utf8)
        #expect(ta.contains("192.0.2.1") && ta.contains("de a") && !ta.contains("de b"))
        #expect(tb.contains("192.0.2.2") && tb.contains("de b") && !tb.contains("de a"))
        #expect(try FileManager.default.attributesOfItem(atPath: b.url.path)[.posixPermissions] as? Int == 0o600)
    }

    /// Disco lleno: se deja de grabar y se avisa una vez (antes, `try?` se lo tragaba).
    @Test func fallarAlEscribirSeAvisa() throws {
        let dir = temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try SessionLogger(directory: dir, name: "core-01", host: "192.0.2.1")
        let told = Counter()
        log.onFailure = { _ in told.add() }
        log.writeData = { _, _ in throw POSIXError(.ENOSPC) }
        log.feed(Array("uno\n".utf8)[...])
        log.feed(Array("dos\n".utf8)[...])
        log.close()
        #expect(told.count == 1)
        #expect(log.failure?.isEmpty == false)
        // (y sin poder crear el archivo: error, no un registro que no graba)
        let file = dir.appendingPathComponent("archivo")
        try Data().write(to: file)
        #expect(throws: (any Error).self) { _ = try SessionLogger(directory: file, name: "x", host: "192.0.2.1") }
    }
}

/// Sustituir un archivo del servidor: carpetas y enlaces, fuera antes de escribir nada; y si falla también la vuelta
/// atrás, no se borra ninguno y el error dice dónde está cada uno.
@Suite struct SustituirRemotoTests {
    @Test func dobleFalloConservaLosDos() async throws {
        let fs = SFTPLikeFileSystem()
        fs.files["/d/a.cfg"] = Data("viejo".utf8)
        fs.refuseRenameTo = ["/d/a.cfg"]                           // (ni entra el nuevo ni vuelve el viejo)
        let w = try await AtomicRemoteWriter.open(fs, "/d/a.cfg", verify: true)
        var stuck: ReplaceStuckError?
        do { try await Transfer.copy(from: BlobReader(Data("nuevo".utf8)), to: w) } catch let e as ReplaceStuckError {
            stuck = e
        }
        let e = try #require(stuck)
        #expect(e.path == "/d/a.cfg" && e.new == w.part)
        #expect(fs.files[e.previous] == Data("viejo".utf8) && fs.files[e.new] == Data("nuevo".utf8))
        #expect(e.localizedDescription.contains(e.previous) && e.localizedDescription.contains(e.new))
        await w.abort()                                            // (lo que hace la copia al fallar: no borra nada)
        #expect(fs.files[e.new] == Data("nuevo".utf8))

        // (si la vuelta atrás sí funciona, el de antes vuelve y no queda nada más)
        let ok = SFTPLikeFileSystem()
        ok.files["/d/a.cfg"] = Data("viejo".utf8)
        ok.refuseRenameTo = ["/d/a.cfg"]
        ok.allowAfter = 2                                          // (el tercer rename a a.cfg, el de volver, sí)
        let w2 = try await AtomicRemoteWriter.open(ok, "/d/a.cfg", verify: false)
        await #expect(throws: RemoteError.self) { try await Transfer.copy(from: BlobReader(Data("nuevo".utf8)), to: w2) }
        #expect(ok.files == ["/d/a.cfg": Data("viejo".utf8)])
    }

    /// Contra el sftp-server de verdad: un enlace o una carpeta con ese nombre se rechazan sin crear el temporal.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: SFTPServerTests.server)))
    func enlacesYCarpetasNoSeTocan() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-sftp-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("real".utf8).write(to: dir.appendingPathComponent("real.cfg"))
        try FileManager.default.createSymbolicLink(atPath: dir.path + "/a.cfg", withDestinationPath: "real.cfg")
        try FileManager.default.createDirectory(atPath: dir.path + "/conf", withIntermediateDirectories: false)
        let fs = try await SFTPFileSystem.connect(label: "prueba", executable: SFTPServerTests.server, arguments: [], environment: [:])
        defer { Task { await fs.close() } }
        for target in ["/a.cfg", "/conf"] {
            await #expect(throws: RemoteError.self) { _ = try await AtomicRemoteWriter.open(fs, dir.path + target, verify: true) }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["a.cfg", "conf", "real.cfg"])
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: dir.path + "/a.cfg") == "real.cfg")
        #expect(try String(contentsOf: dir.appendingPathComponent("real.cfg"), encoding: .utf8) == "real")
    }
}

/// Como SFTP v3: rename no pisa lo que haya y el tipo se sabe. `refuseRenameTo`: renames que fallan (salvo los
/// `allowAfter` primeros fallos, a partir de los cuales ya funcionan).
final class SFTPLikeFileSystem: RemoteFileSystem, @unchecked Sendable {
    let label = "sftp de mentira"
    private let lock = NSLock()
    private var store: [String: Data] = [:]
    var refuseRenameTo: Set<String> = []
    var allowAfter = Int.max
    private var refused = 0
    var files: [String: Data] {
        get { lock.withLock { store } }
        set { lock.withLock { store = newValue } }
    }
    func lookup(_ path: String) async throws -> RemoteEntry.Kind? {
        if let e = lookupError { throw e }
        return files[path] != nil ? .file : nil
    }
    /// lstat que no contesta bien (permisos, respuesta rara).
    var lookupError: RemoteError?

    final class Writer: RemoteWriter, @unchecked Sendable {
        let fs: SFTPLikeFileSystem, path: String
        private var data = Data()
        init(fs: SFTPLikeFileSystem, path: String) { self.fs = fs; self.path = path }
        func write(_ d: Data) async throws { data += d }
        func finish() async throws { fs.files[path] = data }
        func abort() async {}
    }

    func home() async throws -> String { "/" }
    func list(_ path: String) async throws -> [RemoteEntry] { [] }
    func makeDirectory(_ path: String) async throws {}
    func remove(_ path: String, directory: Bool) async throws { files[path] = nil }
    func rename(_ from: String, to: String) async throws {
        try lock.withLock {
            if refuseRenameTo.contains(to) {
                refused += 1
                if refused <= allowAfter { throw RemoteError("rename refused") }
            }
            guard store[to] == nil else { throw RemoteError("ya existe") }
            guard let d = store[from] else { throw RemoteError("no existe") }
            store[from] = nil
            store[to] = d
        }
    }
    func size(of path: String) async -> Int64? { files[path].map { Int64($0.count) } }
    func kind(of path: String) async -> RemoteEntry.Kind? { files[path] != nil ? .file : nil }
    func openRead(_ path: String) async throws -> any RemoteReader {
        guard let d = files[path] else { throw RemoteError("no existe") }
        return BlobReader(d)
    }
    func openWrite(_ path: String) async throws -> any RemoteWriter { Writer(fs: self, path: path) }
    func close() async {}
}

/// Un servidor FTP mínimo en 127.0.0.1 (sockets de verdad): saludo, USER/PASS, FEAT (sin MLSD), EPSV, CWD, LIST con
/// `listing`, y apunta cada orden. DELE/RNFR/RNTO/STOR contestan bien sin hacer nada.
final class MiniFTPServer: @unchecked Sendable {
    let port: UInt16
    private let listener: Int32
    private let listing: [String]
    /// LIST contesta con error (permisos, carpeta que no se puede leer).
    var listFails = false
    /// Rutas a las que SIZE contesta (archivos que el LIST no enseña, como los «.algo»).
    var sizes: Set<String> = []
    private let lock = NSLock()
    private var log: [String] = []
    var commands: [String] { lock.withLock { log } }

    init(listing: [String]) throws {
        self.listing = listing
        (listener, port) = try Self.listen()
        let fd = listener
        Thread { [self] in
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { return }
                Thread { [self] in session(c) }.start()
            }
        }.start()
    }

    func stop() { Darwin.shutdown(listener, SHUT_RDWR); Darwin.close(listener) }

    static func listen() throws -> (Int32, UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, len) == 0 && Darwin.listen(fd, 8) == 0 && getsockname(fd, $0, &len) == 0
            }
        }
        guard fd >= 0, ok else { throw POSIXError(.EADDRNOTAVAIL) }
        return (fd, UInt16(bigEndian: addr.sin_port))
    }

    private func say(_ c: Int32, _ s: String) {
        let d = Array((s + "\r\n").utf8)
        _ = d.withUnsafeBytes { Darwin.write(c, $0.baseAddress, $0.count) }
    }

    private func session(_ c: Int32) {
        defer { Darwin.close(c) }
        say(c, "220 hola")
        var pending = Data(), data: Int32 = -1
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            guard let nl = pending.firstIndex(of: 10) else {
                let n = Darwin.read(c, &buf, buf.count)
                if n <= 0 { return }
                pending.append(contentsOf: buf[0..<n])
                continue
            }
            let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            pending = Data(pending[(nl + 1)...])
            lock.withLock { log.append(line) }
            let verb = line.split(separator: " ").first.map { $0.uppercased() } ?? ""
            switch verb {
            case "USER": say(c, "331 ok")
            case "PASS": say(c, "230 ok")
            case "FEAT": say(c, "211-Features:\r\n EPSV\r\n211 End")
            case "TYPE", "OPTS": say(c, "200 ok")
            case "CWD": say(c, "250 ok")
            case "PWD": say(c, "257 \"/\"")
            case "SIZE":
                let arg = line.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                say(c, sizes.contains(arg) ? "213 5" : "550 no")
            case "EPSV":
                guard let (fd, p) = try? Self.listen() else { say(c, "425 no"); continue }
                data = fd
                say(c, "229 Entering Extended Passive Mode (|||\(p)|)")
            case "LIST" where listFails:
                if data >= 0 { Darwin.close(data) }
                say(c, "550 Permission denied")
            case "LIST":
                say(c, "150 ok")
                let d = accept(data, nil, nil)
                say(d, listing.joined(separator: "\r\n"))
                Darwin.close(d)
                Darwin.close(data)
                say(c, "226 ok")
            case "DELE", "RMD": say(c, "250 ok")
            case "RNFR": say(c, "350 ok")
            case "RNTO": say(c, "250 ok")
            case "QUIT": say(c, "221 adiós"); return
            default: say(c, "502 no")
            }
        }
    }
}

/// MultiExec con peticiones que la app no conoce: lo tecleado ahí no sale de su pestaña, y a una pestaña en esa
/// petición no le llega lo de las demás. Lo normal (desde el prompt, a los que están en el suyo) sigue igual.
@Suite @MainActor struct MultiExecPeticionesDesconocidasTests {
    func grupo(_ ts: [FakeTerminal]) -> MultiExecGroup {
        let g = MultiExecGroup()
        g.isActive = true
        ts.forEach(g.join)
        return g
    }

    @Test(arguments: ["Enter secret:", "Secret:", "Key:", "Community:", "Enter shared key:", "Clave del túnel:"])
    func secretoDesconocidoNoSeReparte(_ peticion: String) {
        let a = FakeTerminal([peticion]), b = FakeTerminal(["core-02#"]), c = FakeTerminal(["core-03#"])
        let g = grupo([a, b, c])
        for k in ["S", "3", "c", "r", "e", "t", "\r"] { #expect(!g.broadcast(Array(k.utf8), from: a)) }
        #expect(b.sent.isEmpty && c.sent.isEmpty)
        // (y la que está en esa petición no recibe lo que se teclea en las otras)
        #expect(g.broadcast(Array("show clock\r".utf8), from: b))
        #expect(a.sent.isEmpty && b.sent == ["show clock\r"] && c.sent == ["show clock\r"])
    }

    /// Una línea empezada en el prompt va entera a los que estaban en el suyo, aunque su eco cambie la línea.
    @Test func laLineaVaEnteraALosDeSuInicio() {
        let a = FakeTerminal(["core-01#"]) { _ in ["core-01#"] }, b = FakeTerminal(["core-02#"]) { _ in ["core-02#"] }
        let c = FakeTerminal(["--More--"])
        let g = grupo([a, b, c])
        #expect(g.broadcast(Array("s".utf8), from: a))
        b.screen[0] = "core-02#s"                                      // (eco: ya no parece un prompt)
        #expect(g.broadcast(Array("h\r".utf8), from: a))
        #expect(a.sent == ["s", "h\r"] && b.sent == ["s", "h\r"])
        #expect(c.sent.isEmpty)                                        // (paginando al empezar: fuera)
        // (en el paginador, la barra espaciadora se queda en su pestaña y no la bloquea para después)
        #expect(!g.broadcast([32], from: c))
        c.screen.append("core-03#")
        #expect(g.broadcast(Array("show users\r".utf8), from: c))
        // (la barra espaciadora la envía la vista sólo ahí: no pasa por el reparto)
        #expect(a.sent.last == "show users\r" && b.sent.last == "show users\r" && c.sent == ["show users\r"])
    }
}
