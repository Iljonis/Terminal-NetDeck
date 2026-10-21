import Foundation
import Testing
@testable import NetDeckCore

/// El explorador lateral: la ruta que sale de la del terminal, lo recordado del panel y la edición remota.
@Suite struct SFTPPanelRouteTests {
    /// Mismo alias, usuario, puerto, saltos, «-F» y sesión que el terminal; sólo cambia a «-s … sftp».
    @Test func mismaRutaQueElTerminal() throws {
        var t = ConnectionRoute(title: "core-01", target: Endpoint(user: "tu.usuario", host: "192.0.2.10", port: 2222),
                                jumpSpec: ["admin@bastion:2200"], sessionName: "core-01")
        t.jumps = [Endpoint(user: "admin", host: "bastion", port: 2200)]
        let p = try SFTPPanel.route(for: t)
        #expect(p.transport == .sftp && p.target == t.target && p.jumpSpec == t.jumpSpec && p.sessionName == "core-01")
        let cmd = try #require(p.sftpSubsystemCommand(sharing: nil, configFile: "/etc/netdeck/ssh_config"))
        #expect(cmd.executable == "/usr/bin/ssh")
        let a = cmd.arguments
        #expect(Array(a.prefix(2)) == ["-F", "/etc/netdeck/ssh_config"])
        #expect(a.contains("-J") && a[a.firstIndex(of: "-J")! + 1] == "admin@bastion:2200")
        #expect(a.contains("-p") && a[a.firstIndex(of: "-p")! + 1] == "2222")
        #expect(a.contains("-l") && a[a.firstIndex(of: "-l")! + 1] == "tu.usuario")
        #expect(Array(a.suffix(3)) == ["--", "192.0.2.10", "sftp"])
        // (sin contraseñas ni órdenes locales en los argumentos)
        #expect(a.contains("PermitLocalCommand=no") && a.contains("ClearAllForwardings=yes"))
    }

    /// Con alias del ssh_config: el alias (ssh lo lee todo de ahí) y, compartiendo, el mismo ProxyCommand al salto.
    @Test func aliasYConexionCompartidaAlSalto() throws {
        var t = ConnectionRoute(title: "core-01", target: Endpoint(user: "tu.usuario", host: "192.0.2.10"), alias: "core-01")
        t.configJumps = ["bastion"]
        t.jumps = [Endpoint(host: "bastion")]
        let p = try SFTPPanel.route(for: t)
        let sharing = JumpSharing(directory: "/tmp/nd")
        let term = t.command(sharing: sharing, configFile: "/etc/netdeck/ssh_config").arguments
        let panel = try #require(p.sftpSubsystemCommand(sharing: sharing, configFile: "/etc/netdeck/ssh_config")).arguments
        let proxy = term.first { $0.hasPrefix("ProxyCommand=") }
        #expect(proxy != nil && panel.contains(proxy!))            // (el mismo socket: el ControlMaster del salto)
        #expect(Array(panel.suffix(3)) == ["--", "core-01", "sftp"])
    }

    @Test func soloEnPestañasSSH() {
        #expect(throws: RemoteError.self) { try SFTPPanel.route(for: ConnectionRoute.local(shell: "/bin/zsh", allowed: ["/bin/zsh"])) }
        let telnet = ConnectionRoute(title: "olt-01", target: Endpoint(host: "192.0.2.20"), transport: .telnet)
        #expect(throws: RemoteError.self) { try SFTPPanel.route(for: telnet) }
        #expect(!SFTPPanel.offers(ConnectionRoute(title: "f", target: Endpoint(host: "192.0.2.21"), transport: .sftp)))
        var hop = ConnectionRoute(title: "core-01", target: Endpoint(host: "bastion"))
        hop.thenCommand = "ssh tu.usuario@core-01"
        hop.manualHop = true
        #expect(throws: RemoteError.self) { try SFTPPanel.route(for: hop) }
    }

    @Test func claveDeLaSesion() {
        #expect(SFTPPanel.key(for: ConnectionRoute(title: "x", target: Endpoint(host: "192.0.2.1"), sessionName: "core-01")) == "sesion:core-01")
        #expect(SFTPPanel.key(for: ConnectionRoute(title: "x", target: Endpoint(user: "tu.usuario", host: "192.0.2.1"))) == "equipo:tu.usuario@192.0.2.1:22")
    }
}

@Suite struct SFTPPanelStoreTests {
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-panel-\(UUID().uuidString)/panel-sftp.json")
    }

    @Test func idaYVuelta() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var s = SFTPPanelStore(url: url)
        #expect(s.layout(for: "sesion:core-01") == SFTPPanelLayout())
        try s.set(SFTPPanelLayout(visible: true, width: 520), for: "sesion:core-01")
        let back = SFTPPanelStore(url: url)
        #expect(back.layout(for: "sesion:core-01") == SFTPPanelLayout(visible: true, width: 520))
        #expect(back.layout(for: "sesion:otra").visible == false)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("\"version\" : 1"))
    }

    @Test func anchoEntreMinimoYMaximo() {
        #expect(SFTPPanelLayout(width: 10).width == SFTPPanelLayout.minWidth)
        #expect(SFTPPanelLayout(width: 5000).width == SFTPPanelLayout.maxWidth)
        #expect(SFTPPanelLayout.clamp(800, available: 900) == 900 - SFTPPanelLayout.minTerminal)
        #expect(SFTPPanelLayout.clamp(.nan) == SFTPPanelLayout.defaultWidth)
    }

    /// Roto: lo de por defecto sin fallar; al guardar, copia del roto antes de sustituirlo.
    @Test func archivoRotoValoresPorDefecto() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ esto no es json".write(to: url, atomically: true, encoding: .utf8)
        var s = SFTPPanelStore(url: url)
        #expect(s.layouts.isEmpty && s.writable)
        try s.set(SFTPPanelLayout(visible: true), for: "k")
        #expect(SFTPPanelStore(url: url).layout(for: "k").visible)
        #expect(try String(contentsOf: url.appendingPathExtension("original"), encoding: .utf8) == "{ esto no es json")

        // (valores raros dentro: los de por defecto o recortados)
        try #"{"version":1,"paneles":{"a":{"visible":"sí","ancho":99999}}}"#.write(to: url, atomically: true, encoding: .utf8)
        #expect(SFTPPanelStore(url: url).layout(for: "a") == SFTPPanelLayout(visible: false, width: SFTPPanelLayout.maxWidth))
    }

    /// De una versión que no se conoce (una app más nueva): por defecto y sin sobrescribirlo.
    @Test func versionDesconocidaNoSeSobrescribe() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let future = #"{"version":7,"paneles":{"k":{"visible":true,"ancho":500}},"otra":1}"#
        try future.write(to: url, atomically: true, encoding: .utf8)
        var s = SFTPPanelStore(url: url)
        #expect(!s.writable && s.layout(for: "k") == SFTPPanelLayout())
        try s.set(SFTPPanelLayout(visible: true, width: 360), for: "k")
        #expect(s.layout(for: "k").width == 360)                    // (en memoria sí, mientras dure)
        #expect(try String(contentsOf: url, encoding: .utf8) == future)
    }
}

/// Contra el sftp-server de verdad del Mac (como `SFTPServerTests`).
@Suite(.serialized) struct RemoteEditTests {
    static let server = "/usr/libexec/sftp-server"

    func connect() async throws -> SFTPFileSystem {
        try await SFTPFileSystem.connect(label: "prueba", executable: Self.server, arguments: [], environment: [:])
    }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-edit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.resolvingSymlinksInPath()
    }

    func text(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func bajarEditarYSubir() async throws {
        let dir = try tempDir(), work = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: work) }
        let fs = try await connect()
        defer { Task { await fs.close() } }
        let path = dir.path + "/core-01.cfg"
        try "hostname core-01\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: path)

        let f = try await RemoteEdit.download(fs, path, into: work)
        #expect(try text(f.local.path) == "hostname core-01\n")
        #expect(try FileManager.default.attributesOfItem(atPath: f.local.path)[.posixPermissions] as? Int == 0o600)
        #expect(try FileManager.default.attributesOfItem(atPath: f.local.deletingLastPathComponent().path)[.posixPermissions] as? Int == 0o700)
        #expect(try await RemoteEdit.upload(fs, f) == .unchanged)

        let edited = "hostname core-01\ninterface lo0\n ip address 192.0.2.1/32\n"
        try edited.write(to: f.local, atomically: true, encoding: .utf8)
        guard case .uploaded(let g) = try await RemoteEdit.upload(fs, f) else { Issue.record("no se ha subido"); return }
        #expect(try text(path) == edited)
        #expect(g.remoteMD5 == TransferDigest.hexOf(Data(edited.utf8)) && g.syncedMD5 == g.remoteMD5)
        #expect(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int == 0o640)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["core-01.cfg"])     // (sin .part ni .old)

        // (se puede limpiar: no queda nada sin subir)
        #expect(RemoteEdit.discard(g))
        #expect(!FileManager.default.fileExists(atPath: g.local.deletingLastPathComponent().path))
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func soloTextoYConLimite() async throws {
        let dir = try tempDir(), work = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: work) }
        let fs = try await connect()
        defer { Task { await fs.close() } }
        try Data([0x7f, 0x45, 0x4c, 0x46, 0, 1]).write(to: dir.appendingPathComponent("binario"))
        try Data(repeating: 0x61, count: 2000).write(to: dir.appendingPathComponent("grande.txt"))
        await #expect(throws: RemoteError.self) { _ = try await RemoteEdit.download(fs, dir.path + "/binario", into: work) }
        await #expect(throws: RemoteError.self) { _ = try await RemoteEdit.download(fs, dir.path + "/grande.txt", into: work, maxSize: 1000) }
        await #expect(throws: (any Error).self) { _ = try await RemoteEdit.download(fs, dir.path, into: work) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
    }

    /// El remoto cambia mientras se edita: no se sobrescribe; se conservan los dos y se puede guardar como copia o,
    /// si se elige, sobrescribir.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func remotoCambiadoNoSeSobrescribe() async throws {
        let dir = try tempDir(), work = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: work) }
        let fs = try await connect()
        defer { Task { await fs.close() } }
        let path = dir.path + "/acl.txt"
        try "permit 192.0.2.0/24\n".write(toFile: path, atomically: true, encoding: .utf8)
        let f = try await RemoteEdit.download(fs, path, into: work)
        try "permit 198.51.100.0/24\n".write(to: f.local, atomically: true, encoding: .utf8)

        // (mismo tamaño, otro contenido: lo ve el MD5)
        try "permit 203.0.113.0/24\n".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(try await RemoteEdit.upload(fs, f) == .conflict(.changed))
        #expect(try text(path) == "permit 203.0.113.0/24\n")
        #expect(try text(f.local.path) == "permit 198.51.100.0/24\n")
        // (otro tamaño)
        try "deny any\n".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(try await RemoteEdit.upload(fs, f) == .conflict(.changed))
        #expect(try text(path) == "deny any\n")

        // (guardar como copia junto al remoto: el remoto sigue igual)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let (copy, g) = try await RemoteEdit.uploadCopy(fs, f, date: date)
        #expect(RemotePath.parent(copy) == dir.path && RemotePath.name(copy).hasPrefix("acl.local-") && copy.hasSuffix(".txt"))
        #expect(try text(copy) == "permit 198.51.100.0/24\n")
        #expect(try text(path) == "deny any\n")
        let (copy2, _) = try await RemoteEdit.uploadCopy(fs, f, date: date)         // (mismo segundo, otro UUID)
        #expect(copy2 != copy && copy2.hasSuffix(".txt"))
        // (lo local está a salvo en el servidor: ya se puede limpiar)
        #expect(g.syncedMD5 == TransferDigest.hexOf(Data("permit 198.51.100.0/24\n".utf8)))

        // (sobrescribir, si se elige)
        guard case .uploaded = try await RemoteEdit.upload(fs, f, force: true) else { Issue.record("no se ha subido"); return }
        #expect(try text(path) == "permit 198.51.100.0/24\n")

        // (borrado entretanto: también es un cambio)
        try FileManager.default.removeItem(atPath: path)
        let h = try await RemoteEdit.download(fs, copy, into: work)
        try FileManager.default.removeItem(atPath: copy)
        try "otra\n".write(to: h.local, atomically: true, encoding: .utf8)
        #expect(try await RemoteEdit.upload(fs, h) == .conflict(.removed))
        #expect(!FileManager.default.fileExists(atPath: copy))
        // (con algo sin subir, la carpeta de edición no se borra)
        #expect(!RemoteEdit.discard(h))
        #expect(FileManager.default.fileExists(atPath: h.local.path))
    }

    /// Se corta la conexión o se cancela a mitad de la subida: el remoto queda como estaba.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func cortarOCancelarAMitadNoTocaElRemoto() async throws {
        let dir = try tempDir(), work = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: work) }
        let path = dir.path + "/running-config.txt"
        let original = String(repeating: "interface Gi0/1\n description core-01\n", count: 20_000)    // (~760 KB)
        try original.write(toFile: path, atomically: true, encoding: .utf8)
        let fs = try await connect()
        let f = try await RemoteEdit.download(fs, path, into: work)
        try original.replacingOccurrences(of: "core-01", with: "core-02").write(to: f.local, atomically: true, encoding: .utf8)

        // (desconexión: tras el primer trozo, se cierra la conexión)
        let cut = BreakingFileSystem(fs, mode: .disconnect)
        await #expect(throws: (any Error).self) { _ = try await RemoteEdit.upload(cut, f) }
        #expect(cut.writing)                                   // (el fallo ocurre durante el envío, no en una comprobación previa)
        #expect(try text(path) == original)
        // (con la conexión muerta, el temporal no se puede borrar: queda «.part», nunca con el nombre bueno)
        func parts() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".part") }.sorted() }
        let leftover = try parts()

        // (cancelación: la escritura se queda esperando y se cancela la tarea)
        let fs2 = try await connect()
        defer { Task { await fs2.close() } }
        let slow = BreakingFileSystem(fs2, mode: .hang)
        let task = Task { try await RemoteEdit.upload(slow, f) }
        defer { task.cancel() }
        for _ in 0..<200 where !slow.writing { try await Task.sleep(for: .milliseconds(10)) }
        #expect(slow.writing)                                  // (se cancela una escritura pendiente de verdad)
        task.cancel()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(try text(path) == original)
        // (con la conexión viva, el temporal de la cancelada sí se borra)
        #expect(try parts() == leftover)
        // (y la copia local, intacta para volver a probar)
        #expect(try text(f.local.path).contains("core-02"))
    }
}

/// Un SFTP que falla a mitad de escribir: corta la conexión tras el primer trozo o se queda esperando (para cancelar).
final class BreakingFileSystem: RemoteFileSystem, @unchecked Sendable {
    enum Mode { case disconnect, hang }
    let inner: any RemoteFileSystem
    let mode: Mode
    private let lock = NSLock()
    private var started = false
    var writing: Bool { lock.withLock { started } }

    init(_ inner: any RemoteFileSystem, mode: Mode) { self.inner = inner; self.mode = mode }

    final class Writer: RemoteWriter, @unchecked Sendable {
        let owner: BreakingFileSystem, inner: any RemoteWriter
        init(_ owner: BreakingFileSystem, _ inner: any RemoteWriter) { self.owner = owner; self.inner = inner }
        func write(_ data: Data) async throws {
            try await inner.write(data.prefix(1000))
            owner.lock.withLock { owner.started = true }
            switch owner.mode {
            case .disconnect:
                await owner.inner.close()
                throw RemoteError("Se ha perdido la conexión")
            case .hang:
                try await Task.sleep(for: .seconds(3600))
            }
        }
        func finish() async throws { try await inner.finish() }
        func abort() async { await inner.abort() }
    }

    var label: String { inner.label }
    var renameDoesNotOverwrite: Bool { inner.renameDoesNotOverwrite }
    func home() async throws -> String { try await inner.home() }
    func list(_ path: String) async throws -> [RemoteEntry] { try await inner.list(path) }
    func makeDirectory(_ path: String) async throws { try await inner.makeDirectory(path) }
    func remove(_ path: String, directory: Bool) async throws { try await inner.remove(path, directory: directory) }
    func rename(_ from: String, to: String) async throws { try await inner.rename(from, to: to) }
    func size(of path: String) async -> Int64? { await inner.size(of: path) }
    func openRead(_ path: String) async throws -> any RemoteReader { try await inner.openRead(path) }
    func openWrite(_ path: String) async throws -> any RemoteWriter { Writer(self, try await inner.openWrite(path)) }
    func close() async { await inner.close() }
    func permissions(of path: String) async -> UInt32? { await inner.permissions(of: path) }
    func kind(of path: String) async -> RemoteEntry.Kind? { await inner.kind(of: path) }
    func lookup(_ path: String) async throws -> RemoteEntry.Kind? { try await inner.lookup(path) }
    func setPermissions(_ mode: UInt32, of path: String) async throws { try await inner.setPermissions(mode, of: path) }
}
