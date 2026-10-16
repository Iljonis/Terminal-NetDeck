import Foundation

/// Cliente SFTP sobre «ssh -s … sftp» (el ssh del sistema: mismo alias del ssh_config, saltos, claves y askpass que las
/// pestañas). Las peticiones van en paralelo (cada una con su id): lecturas y escrituras de varios trozos a la vez.
public actor SFTPFileSystem: RemoteFileSystem {
    public nonisolated let label: String
    private let process: ChildProcess
    private var buffer = Data()
    private var nextID: UInt32 = 1
    private var waiting: [UInt32: CheckedContinuation<(UInt8, Data), Error>] = [:]
    private var arrived: [UInt32: (UInt8, Data)] = [:]
    private var dropped: Set<UInt32> = []
    private var versionWaiter: CheckedContinuation<Void, Error>?
    private var gotVersion = false
    private var failure: Error?

    /// Trozo de cada petición de lectura/escritura (32 KiB: lo que admite cualquier servidor).
    public static let chunk = 32 * 1024

    private init(label: String, process: ChildProcess) {
        self.label = label
        self.process = process
    }

    /// Arranca ssh y hace el saludo de SFTP (versión 3).
    public static func connect(label: String, executable: String, arguments: [String],
                               environment: [String: String]) async throws -> SFTPFileSystem {
        let p = try ChildProcess(executable: executable, arguments: arguments, environment: environment)
        let fs = SFTPFileSystem(label: label, process: p)
        await fs.start()
        do {
            // (cancelar mientras ssh espera, p. ej. a un equipo mudo o a la contraseña: se termina ssh y hello acaba)
            try await withTaskCancellationHandler { try await fs.hello() } onCancel: { p.terminate() }
        } catch {
            await fs.close()
            throw error
        }
        return fs
    }

    private func start() {
        let stream = process.output
        Task { await self.pump(stream) }
    }

    private func pump(_ stream: AsyncStream<Data>) async {
        for await chunk in stream {
            buffer.append(chunk)
            do {
                for (kind, body) in try SFTP.split(&buffer) { deliver(kind, body) }
            } catch {
                fail(error)
                process.terminate()
                return
            }
        }
        // (ssh ha terminado: lo que diga por su salida de errores es lo que ha pasado)
        try? await Task.sleep(for: .milliseconds(150))
        let why = process.errorSummary
        fail(RemoteError(why.isEmpty ? L("Se ha cerrado la conexión") : why))
    }

    private func deliver(_ kind: UInt8, _ body: Data) {
        if kind == SFTP.Kind.version.rawValue {
            gotVersion = true
            versionWaiter?.resume()
            versionWaiter = nil
            return
        }
        var r = SFTP.Reader(body)
        guard let id = try? r.u32() else { return }
        let rest = Data(body.dropFirst(4))
        if dropped.remove(id) != nil { return }
        if let c = waiting.removeValue(forKey: id) { c.resume(returning: (kind, rest)) } else { arrived[id] = (kind, rest) }
    }

    private func fail(_ e: Error) {
        guard failure == nil else { return }
        failure = e
        versionWaiter?.resume(throwing: e)
        versionWaiter = nil
        for c in waiting.values { c.resume(throwing: e) }
        waiting = [:]
    }

    private func hello() async throws {
        try process.write(SFTP.packet(.initialize, id: nil) { $0.u32(3) })
        if gotVersion { return }
        if let failure { throw failure }
        try await withCheckedThrowingContinuation { versionWaiter = $0 }
    }

    // MARK: peticiones

    func send(_ kind: SFTP.Kind, _ body: (inout SFTP.Writer) -> Void) throws -> UInt32 {
        if let failure { throw failure }
        let id = nextID
        nextID &+= 1
        try process.write(SFTP.packet(kind, id: id, body))
        return id
    }

    /// La respuesta a `id`. Si la tarea se cancela mientras espera (Cancelar en una copia), acaba al momento con
    /// CancellationError y la respuesta, cuando llegue, se descarta.
    func reply(_ id: UInt32) async throws -> (UInt8, Data) {
        if let r = arrived.removeValue(forKey: id) { return r }
        if let failure { throw failure }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in
                if Task.isCancelled {
                    dropped.insert(id)
                    c.resume(throwing: CancellationError())
                } else {
                    waiting[id] = c
                }
            }
        } onCancel: {
            Task { await self.stopWaiting(id) }
        }
    }

    private func stopWaiting(_ id: UInt32) {
        guard let c = waiting.removeValue(forKey: id) else { return }
        dropped.insert(id)
        c.resume(throwing: CancellationError())
    }

    /// Ya no interesa la respuesta (lecturas adelantadas que sobran).
    func drop(_ id: UInt32) {
        if arrived.removeValue(forKey: id) == nil { dropped.insert(id) }
    }

    private func call(_ kind: SFTP.Kind, _ body: (inout SFTP.Writer) -> Void) async throws -> (UInt8, SFTP.Reader) {
        let (k, d) = try await reply(try send(kind, body))
        return (k, SFTP.Reader(d))
    }

    /// STATUS: OK o el error que diga.
    static func check(_ kind: UInt8, _ r: inout SFTP.Reader, allowEOF: Bool = false) throws {
        guard kind == SFTP.Kind.status.rawValue else { throw RemoteError(L("SFTP: respuesta inesperada")) }
        let code = try r.u32()
        let text = (try? r.string()) ?? ""
        if code == SFTP.Status.ok.rawValue || (allowEOF && code == SFTP.Status.eof.rawValue) { return }
        throw RemoteError(SFTP.message(for: code, text))
    }

    private func handle(_ kind: SFTP.Kind, _ body: (inout SFTP.Writer) -> Void) async throws -> Data {
        let (k, r0) = try await call(kind, body)
        var r = r0
        if k == SFTP.Kind.handle.rawValue { return try r.bytes() }
        try Self.check(k, &r)
        throw RemoteError(L("SFTP: respuesta inesperada"))
    }

    private func status(_ kind: SFTP.Kind, _ body: (inout SFTP.Writer) -> Void) async throws {
        let (k, r0) = try await call(kind, body)
        var r = r0
        try Self.check(k, &r)
    }

    func closeHandle(_ h: Data) async throws {
        try await status(.close) { $0.bytes(h) }
    }

    func stat(_ path: String, follow: Bool = true) async throws -> SFTP.Attributes {
        let (k, r0) = try await call(follow ? .stat : .lstat) { $0.string(path) }
        var r = r0
        if k == SFTP.Kind.attrs.rawValue { return try r.attributes() }
        try Self.check(k, &r)
        throw RemoteError(L("SFTP: respuesta inesperada"))
    }

    // MARK: RemoteFileSystem

    public func home() async throws -> String {
        let (k, r0) = try await call(.realpath) { $0.string(".") }
        var r = r0
        if k == SFTP.Kind.name.rawValue, let n = try r.names().first { return n.filename }
        try Self.check(k, &r)
        return "/"
    }

    public func list(_ path: String) async throws -> [RemoteEntry] {
        let h = try await handle(.opendir) { $0.string(path) }
        var out: [RemoteEntry] = []
        do {
            while true {
                let (k, r0) = try await call(.readdir) { $0.bytes(h) }
                var r = r0
                if k == SFTP.Kind.status.rawValue {
                    try Self.check(k, &r, allowEOF: true)
                    break
                }
                guard k == SFTP.Kind.name.rawValue else { throw RemoteError(L("SFTP: respuesta inesperada")) }
                for n in try r.names() where RemotePath.isValidName(n.filename) {      // (ni «.», «..», «/» ni saltos: un servidor hostil no saca rutas de su carpeta)
                    let a = n.attributes
                    var e = RemoteEntry(name: n.filename, path: RemotePath.join(path, n.filename), kind: a.kind,
                                        size: a.size.map { Int64(clamping: $0) }, permissions: a.permissions.map { $0 & 0o7777 },
                                        modified: a.mtime.map { Date(timeIntervalSince1970: TimeInterval($0)) })
                    if let o = SFTP.owner(fromLongname: n.longname) { (e.owner, e.group) = o }
                    out.append(e)
                }
            }
        } catch {
            try? await closeHandle(h)
            throw error
        }
        try? await closeHandle(h)
        // (los enlaces: ¿apuntan a una carpeta?)
        for i in out.indices where out[i].kind == .link {
            if let a = try? await stat(out[i].path) { out[i].linkToDirectory = a.kind == .directory }
        }
        return RemoteEntry.sorted(out)
    }

    public func makeDirectory(_ path: String) async throws {
        try await status(.mkdir) { $0.string(path); $0.attributes(SFTP.Attributes()) }
    }

    public func remove(_ path: String, directory: Bool) async throws {
        try await status(directory ? .rmdir : .remove) { $0.string(path) }
    }

    public func rename(_ from: String, to: String) async throws {
        try await status(.rename) { $0.string(from); $0.string(to) }
    }

    public func permissions(of path: String) async -> UInt32? {
        (try? await stat(path))?.permissions.map { $0 & 0o7777 }
    }

    public func kind(of path: String) async -> RemoteEntry.Kind? {
        (try? await stat(path, follow: false))?.kind
    }

    public func setPermissions(_ mode: UInt32, of path: String) async throws {
        try await status(.setstat) { $0.string(path); $0.attributes(SFTP.Attributes(permissions: mode & 0o7777)) }
    }

    public func size(of path: String) async -> Int64? {
        (try? await stat(path))?.size.map { Int64(clamping: $0) }
    }

    public func openRead(_ path: String) async throws -> any RemoteReader {
        let h = try await handle(.open) {
            $0.string(path)
            $0.u32(SFTP.OpenFlags.read.rawValue)
            $0.attributes(SFTP.Attributes())
        }
        return SFTPFileReader(fs: self, handle: h)
    }

    /// Sólo crea uno nuevo (O_EXCL): nunca abre ni trunca uno que ya exista (el origen de una copia incluido).
    /// Algunos SFTP de equipos de red no admiten O_EXCL: entonces, sin él (sólo se abren nombres nuevos de UUID).
    public func openWrite(_ path: String) async throws -> any RemoteWriter {
        do {
            return try await openWrite(path, [.write, .create, .exclusive])
        } catch let e as RemoteError where e.message == SFTP.message(for: SFTP.Status.unsupported.rawValue, "") {
            return try await openWrite(path, [.write, .create, .truncate])
        }
    }

    private func openWrite(_ path: String, _ flags: SFTP.OpenFlags) async throws -> any RemoteWriter {
        let h = try await handle(.open) {
            $0.string(path)
            $0.u32(flags.rawValue)
            $0.attributes(SFTP.Attributes())
        }
        return SFTPFileWriter(fs: self, handle: h)
    }

    /// Primero se mata ssh (sin esperar al actor: una escritura bloqueada en la tubería acaba así con EPIPE) y luego
    /// se despierta a quien esperase respuesta.
    public nonisolated func close() async {
        process.terminate()
        await fail(RemoteError(L("Conexión cerrada")))
    }
}

/// Lectura con varias peticiones por delante (hasta 1 MiB en vuelo).
actor SFTPFileReader: RemoteReader {
    private let fs: SFTPFileSystem
    private let handle: Data
    private var queue: [(id: UInt32, offset: UInt64, length: Int)] = []
    private var next: UInt64 = 0
    private var eof = false
    private var closed = false
    /// Peticiones en vuelo: 64 × 32 KiB = 2 MiB (como OpenSSH); con 30 ms de ida y vuelta, ~65 MB/s.
    private let depth = 64

    init(fs: SFTPFileSystem, handle: Data) {
        self.fs = fs
        self.handle = handle
    }

    private func fill() async throws {
        while !eof, queue.count < depth {
            let off = next, len = SFTPFileSystem.chunk, h = handle
            let id = try await fs.send(.read) { $0.bytes(h); $0.u64(off); $0.u32(UInt32(len)) }
            queue.append((id, off, len))
            next += UInt64(len)
        }
    }

    private func dropQueue() async {
        for q in queue { await fs.drop(q.id) }
        queue = []
    }

    func read() async throws -> Data? {
        while true {
            if closed { return nil }
            try await fill()
            guard !queue.isEmpty else { return nil }
            let q = queue.removeFirst()
            let (k, body) = try await fs.reply(q.id)
            var r = SFTP.Reader(body)
            if k == SFTP.Kind.data.rawValue {
                let d = Data(try r.bytes())
                if d.count < q.length {                     // (lectura corta: se sigue justo detrás)
                    await dropQueue()
                    next = q.offset + UInt64(d.count)
                }
                if d.isEmpty { continue }
                return d
            }
            try SFTPFileSystem.check(k, &r, allowEOF: true)
            eof = true
            await dropQueue()
            return nil
        }
    }

    func close() async {
        guard !closed else { return }
        closed = true
        await dropQueue()
        try? await fs.closeHandle(handle)
    }
}

/// Escritura con varias peticiones por delante; `finish` espera a que el servidor las confirme todas.
actor SFTPFileWriter: RemoteWriter {
    private let fs: SFTPFileSystem
    private let handle: Data
    private var pending: [UInt32] = []
    private var offset: UInt64 = 0
    private var closed = false
    /// Peticiones en vuelo: 64 × 32 KiB = 2 MiB (como OpenSSH); con 30 ms de ida y vuelta, ~65 MB/s.
    private let depth = 64

    init(fs: SFTPFileSystem, handle: Data) {
        self.fs = fs
        self.handle = handle
    }

    private func settle(_ id: UInt32) async throws {
        let (k, d) = try await fs.reply(id)
        var r = SFTP.Reader(d)
        try SFTPFileSystem.check(k, &r)
    }

    func write(_ data: Data) async throws {
        var at = data.startIndex
        while at < data.endIndex {
            let end = min(at + SFTPFileSystem.chunk, data.endIndex)
            let piece = Data(data[at..<end]), off = offset, h = handle
            pending.append(try await fs.send(.write) { $0.bytes(h); $0.u64(off); $0.bytes(piece) })
            offset += UInt64(piece.count)
            at = end
            while pending.count > depth { try await settle(pending.removeFirst()) }
        }
    }

    func finish() async throws {
        while !pending.isEmpty { try await settle(pending.removeFirst()) }
        closed = true
        try await fs.closeHandle(handle)
    }

    func abort() async {
        guard !closed else { return }
        closed = true
        for id in pending { await fs.drop(id) }
        pending = []
        try? await fs.closeHandle(handle)
    }
}
