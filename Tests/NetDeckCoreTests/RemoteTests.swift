import Foundation
import Testing
@testable import NetDeckCore

@Suite struct SFTPPacketTests {
    @Test func paqueteYLectura() throws {
        let p = SFTP.packet(.open, id: 7) {
            $0.string("/srv/archivo.txt")
            $0.u32(SFTP.OpenFlags.read.rawValue)
            $0.attributes(SFTP.Attributes(size: 10, permissions: 0o100644, mtime: 1_700_000_000))
        }
        var buf = p + Data([0, 0])                         // (lo que sobra es del siguiente paquete)
        let out = try SFTP.split(&buf)
        #expect(out.count == 1 && out[0].kind == SFTP.Kind.open.rawValue && buf == Data([0, 0]))
        var r = SFTP.Reader(out[0].body)
        #expect(try r.u32() == 7)
        #expect(try r.string() == "/srv/archivo.txt")
        #expect(try r.u32() == 1)
        let a = try r.attributes()
        #expect(a.size == 10 && a.permissions == 0o100644 && a.mtime == 1_700_000_000 && a.kind == .file)
    }

    @Test func paqueteIncompletoEspera() throws {
        let p = SFTP.packet(.realpath, id: 1) { $0.string(".") }
        var buf = Data(p.prefix(6))
        #expect(try SFTP.split(&buf).isEmpty && buf.count == 6)
        buf.append(p.dropFirst(6))
        #expect(try SFTP.split(&buf).count == 1 && buf.isEmpty)
    }

    @Test func longitudAbsurdaEsError() {
        var buf = Data([0x7F, 0xFF, 0xFF, 0xFF, 1])
        #expect(throws: RemoteError.self) { try SFTP.split(&buf) }
    }

    @Test func dueñoDelLongname() {
        let o = SFTP.owner(fromLongname: "-rw-r--r--    1 tu.usuario staff      1234 Jan  1 12:00 a.txt")
        #expect(o?.owner == "tu.usuario" && o?.group == "staff")
        #expect(SFTP.owner(fromLongname: "a.txt") == nil)
    }
}

@Suite struct RemotePathTests {
    @Test func rutas() {
        #expect(RemotePath.join("/", "etc") == "/etc")
        #expect(RemotePath.join("/var", "log") == "/var/log")
        #expect(RemotePath.parent("/var/log") == "/var")
        #expect(RemotePath.parent("/var") == "/")
        #expect(RemotePath.parent("/") == "/")
        #expect(RemotePath.parent("/var/log/") == "/var")
        #expect(RemotePath.name("/var/log") == "log")
        #expect(RemotePath.breadcrumbs("/var/log").map(\.path) == ["/", "/var", "/var/log"])
    }

    @Test func nombresVálidos() {
        #expect(RemotePath.isValidName("informe 2024.txt"))
        #expect(!RemotePath.isValidName(""))
        #expect(!RemotePath.isValidName(".."))
        #expect(!RemotePath.isValidName("a/b"))
        #expect(!RemotePath.isValidName("a\r\nDELE b"))       // (en FTP sería otra orden)
    }

    @Test func permisosYOrden() {
        let d = RemoteEntry(name: "b", path: "/b", kind: .directory, permissions: 0o755)
        let f = RemoteEntry(name: "a", path: "/a", kind: .file, permissions: 0o640)
        #expect(d.permissionString == "drwxr-xr-x" && f.permissionString == "-rw-r-----")
        #expect(RemoteEntry.sorted([f, d]).map(\.name) == ["b", "a"])
        #expect(RemoteEntry(name: "x", path: "/x", kind: .file).permissionString == "—")
    }
}

@Suite struct FTPParseTests {
    /// Respuestas de varias líneas (Pure-FTPd empieza el saludo con «220---------- Welcome…»).
    @Test func respuestasDeVariasLineas() throws {
        let start = try FTPParse.replyStart("220---------- Welcome to Pure-FTPd ----------")
        #expect(start.code == 220 && start.more && start.text == "--------- Welcome to Pure-FTPd ----------")
        var lines = [start.text]
        #expect(!FTPParse.replyEnds("220-You are user number 1 of 50 allowed.", code: 220, into: &lines))
        #expect(!FTPParse.replyEnds(" UTF8", code: 220, into: &lines))                 // (sin código: RFC 959)
        #expect(FTPParse.replyEnds("220 You will be disconnected after 15 minutes.", code: 220, into: &lines))
        #expect(lines == ["--------- Welcome to Pure-FTPd ----------", "You are user number 1 of 50 allowed.", " UTF8",
                          "You will be disconnected after 15 minutes."])
        let one = try FTPParse.replyStart("500 Unknown command")
        #expect(one.code == 500 && !one.more)
        #expect(throws: RemoteError.self) { try FTPParse.replyStart("hola") }
    }

    @Test func pasivo() {
        #expect(FTPParse.epsvPort("Entering Extended Passive Mode (|||6446|)") == 6446)
        #expect(FTPParse.pasvPort("Entering Passive Mode (192,0,2,7,19,77).") == UInt16(19 * 256 + 77))
        #expect(FTPParse.pasvPort("Entering Passive Mode") == nil)
        #expect(FTPParse.quotedPath("\"/home/tu.usuario\" is the current directory") == "/home/tu.usuario")
        #expect(FTPParse.quotedPath("\"/a\"\"b\" ok") == "/a\"b")
    }

    @Test func mlsd() {
        let e = FTPParse.mlsd("type=dir;modify=20240101120000;UNIX.mode=0755; copias de seguridad", in: "/srv")
        #expect(e?.name == "copias de seguridad" && e?.kind == .directory && e?.permissions == 0o755 && e?.path == "/srv/copias de seguridad")
        let f = FTPParse.mlsd("type=file;size=1234;modify=20240101120000; a.txt", in: "/")
        #expect(f?.size == 1234 && f?.kind == .file && f?.modified != nil)
        #expect(FTPParse.mlsd("type=cdir; .", in: "/") == nil)
    }

    @Test func listUnixYWindows() {
        let now = Date(timeIntervalSince1970: 1_717_200_000)                 // (junio de 2024)
        let d = FTPParse.list("drwxr-xr-x    2 tu.usuario staff     4096 Jan  1 12:00 mis copias", in: "/srv", now: now)
        #expect(d?.name == "mis copias" && d?.kind == .directory && d?.permissions == 0o755 && d?.owner == "tu.usuario")
        let f = FTPParse.list("-rw-r--r--    1 0 0  1234 Mar 3  2021 a.txt", in: "/", now: now)
        #expect(f?.size == 1234 && f?.kind == .file && f?.modified != nil)
        let l = FTPParse.list("lrwxrwxrwx    1 0 0  4 Mar 3  2021 www -> html", in: "/", now: now)
        #expect(l?.name == "www" && l?.kind == .link)
        let w = FTPParse.list("01-31-24  09:15AM       <DIR>          Informes", in: "/", now: now)
        #expect(w?.name == "Informes" && w?.kind == .directory)
        let wf = FTPParse.list("01-31-24  09:15AM              2048 datos.csv", in: "/", now: now)
        #expect(wf?.size == 2048 && wf?.kind == .file)
        #expect(FTPParse.list("total 12", in: "/", now: now) == nil)
        // (un servidor hostil no saca rutas fuera de la carpeta)
        #expect(FTPParse.mlsd("type=file;size=1; ../../etc/x", in: "/srv") == nil)
        #expect(FTPParse.list("-rw-r--r-- 1 0 0 1 Mar 3 2021 a/b", in: "/", now: now) == nil)
        #expect(RemoteOps.isSafeRelative("conf/sub/x.txt") && !RemoteOps.isSafeRelative("conf/../../x")
                && !RemoteOps.isSafeRelative("/x"))
    }
}

/// Lector y escritor en memoria (para probar el puente sin red).
final class MemoryReader: RemoteReader, @unchecked Sendable {
    private var chunks: [Data]
    private let failAt: Int?
    private var n = 0
    init(_ chunks: [Data], failAt: Int? = nil) { self.chunks = chunks; self.failAt = failAt }
    func read() async throws -> Data? {
        defer { n += 1 }
        if let failAt, n == failAt { throw RemoteError("se cae") }
        return chunks.isEmpty ? nil : chunks.removeFirst()
    }
    func close() async {}
}

final class MemoryWriter: RemoteWriter, @unchecked Sendable {
    var data = Data()
    var finished = false, aborted = false
    func write(_ d: Data) async throws {
        try await Task.sleep(for: .microseconds(50))       // (más lento que el origen: la cola se llena)
        data.append(d)
    }
    func finish() async throws { finished = true }
    func abort() async { aborted = true }
}

@Suite struct TransferTests {
    @Test func copiaEnOrdenYConProgreso() async throws {
        let chunks = (0..<200).map { i in Data(repeating: UInt8(i % 256), count: 1000 + i) }
        let w = MemoryWriter()
        let seen = Counter()
        let n = try await Transfer.copy(from: MemoryReader(chunks), to: w, capacity: 4) { seen.set($0) }
        #expect(w.data == chunks.reduce(Data(), +) && w.finished && !w.aborted)
        #expect(n == Int64(w.data.count) && seen.value == n)
    }

    @Test func errorDelOrigenAbortaElDestino() async {
        let w = MemoryWriter()
        await #expect(throws: RemoteError.self) {
            try await Transfer.copy(from: MemoryReader([Data([1]), Data([2]), Data([3])], failAt: 2), to: w)
        }
        #expect(w.aborted && !w.finished)
    }

    @Test func colaConTope() async throws {
        let pipe = ChunkPipe(capacity: 2)
        try await pipe.put(Data([1]))
        try await pipe.put(Data([2]))
        let third = Task { try await pipe.put(Data([3])) }      // (espera: la cola está llena)
        try await Task.sleep(for: .milliseconds(20))
        #expect(try await pipe.take() == Data([1]))
        try await third.value
        await pipe.finish()
        #expect(try await pipe.take() == Data([2]))
        #expect(try await pipe.take() == Data([3]))
        #expect(try await pipe.take() == nil)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var v: Int64 = 0
    func set(_ n: Int64) { lock.withLock { v = n } }
    var value: Int64 { lock.withLock { v } }
}

/// Contra el sftp-server de verdad del Mac (/usr/libexec/sftp-server, sin ssh ni red), en una carpeta temporal.
@Suite(.serialized) struct SFTPServerTests {
    static let server = "/usr/libexec/sftp-server"

    func connect() async throws -> SFTPFileSystem {
        try await SFTPFileSystem.connect(label: "prueba", executable: Self.server, arguments: [], environment: [:])
    }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-sftp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.resolvingSymlinksInPath()
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func listarEscribirLeerRenombrarBorrar() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fs = try await connect()
        defer { Task { await fs.close() } }
        #expect(try await fs.home().hasPrefix("/"))

        try await fs.makeDirectory(dir.path + "/sub")
        let body = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })        // (varios trozos de 32 KiB)
        let w = try await fs.openWrite(dir.path + "/datos.bin")
        try await w.write(body)
        try await w.finish()
        #expect(try Data(contentsOf: dir.appendingPathComponent("datos.bin")) == body)
        #expect(await fs.size(of: dir.path + "/datos.bin") == Int64(body.count))

        let list = try await fs.list(dir.path)
        #expect(list.map(\.name) == ["sub", "datos.bin"])
        #expect(list[0].isDirectory && list[1].size == Int64(body.count) && list[1].permissions != nil)

        let r = try await fs.openRead(dir.path + "/datos.bin")
        var back = Data()
        while let d = try await r.read() { back.append(d) }
        await r.close()
        #expect(back == body)

        try await fs.rename(dir.path + "/datos.bin", to: dir.path + "/sub/movido.bin")
        #expect(try await fs.list(dir.path + "/sub").map(\.name) == ["movido.bin"])
        try await RemoteOps.removeRecursively(fs, RemoteEntry(name: "sub", path: dir.path + "/sub", kind: .directory))
        #expect(try await fs.list(dir.path).isEmpty)
        await #expect(throws: RemoteError.self) { try await fs.list(dir.path + "/no-existe") }
    }

    /// El puente: de un servidor a otro (dos conexiones), en memoria.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func puenteEntreServidores() async throws {
        let a = try tempDir(), b = try tempDir()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let body = Data((0..<1_500_000).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })
        try body.write(to: a.appendingPathComponent("imagen.bin"))
        let src = try await connect(), dst = try await connect()
        defer { Task { await src.close(); await dst.close() } }
        let n = try await Transfer.copy(from: try await src.openRead(a.path + "/imagen.bin"),
                                        to: try await dst.openWrite(b.path + "/imagen.bin"))
        #expect(n == Int64(body.count))
        #expect(try Data(contentsOf: b.appendingPathComponent("imagen.bin")) == body)

        // carpeta entera
        try FileManager.default.createDirectory(at: a.appendingPathComponent("conf/sub"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: a.appendingPathComponent("conf/sub/x.txt"))
        let plan = try await RemoteOps.plan(src, RemoteEntry(name: "conf", path: a.path + "/conf", kind: .directory))
        #expect(plan.map(\.relative) == ["conf", "conf/sub", "conf/sub/x.txt"])
    }
}

@Suite struct SessionDefaultsTests {
    @Test func sesiónNuevaConTuUsuarioYPuerto() {
        let s = EditableSession.new(group: "General", name: "nueva", kind: .ssh, user: "tu.usuario")
        #expect(s.user == "tu.usuario" && s.port == "22")
        #expect(EditableSession.new(group: "G", name: "n", kind: .serial, user: "tu.usuario").user.isEmpty)
    }

    @Test func cambiarDeTipoCambiaElPuerto() {
        var s = EditableSession.new(group: "G", name: "n", user: "tu.usuario")
        s.setKind(.telnet); #expect(s.port == "23")
        s.setKind(.ftp); #expect(s.port == "21")
        s.setKind(.sftp); #expect(s.port == "22")
        s.port = "2222"
        s.setKind(.telnet); #expect(s.port == "2222")          // (un puerto propio se respeta)
    }

    @Test func puertoDeTelnetYFTPAlLeerYEscribir() {
        let f = SessionFile(text: """
            Host olt-01
                # @telnet
                HostName 192.0.2.21

            Host ftp-01
                # @tipo ftp
                HostName 192.0.2.40
                Port 2121
            """)
        #expect(f.sessions[0].port == "23" && f.sessions[1].port == "2121")
        #expect(!f.render().contains("Port 23") && f.render().contains("Port 2121"))
    }

    @Test func ordenDelExploradorSFTP() {
        var r = ConnectionRoute(title: "f", target: Endpoint(user: "tu.usuario", host: "192.0.2.30", port: 2222), transport: .sftp)
        let c = r.sftpSubsystemCommand
        #expect(c?.executable == "/usr/bin/ssh")
        #expect(c?.arguments.suffix(8) == ["-s", "-p", "2222", "-l", "tu.usuario", "--", "192.0.2.30", "sftp"])
        #expect(c?.arguments.contains("ClearAllForwardings=yes") == true)
        r.alias = "ficheros-01"
        #expect(r.sftpSubsystemCommand?.arguments.suffix(4) == ["-s", "--", "ficheros-01", "sftp"])
        r.transport = .ssh
        #expect(r.sftpSubsystemCommand == nil)
    }
}
