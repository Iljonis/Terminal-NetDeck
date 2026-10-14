import Foundation

/// Cola de trozos con tope (el puente en memoria): quien lee del origen espera si está llena, quien escribe en el
/// destino espera si está vacía. Así la RAM usada no pasa de `capacity` trozos, sea el archivo del tamaño que sea.
public actor ChunkPipe {
    private var chunks: [Data] = []
    private var finished = false
    private var failure: Error?
    private var takers: [CheckedContinuation<Data?, Error>] = []
    private var putters: [CheckedContinuation<Void, Error>] = []
    public let capacity: Int

    public init(capacity: Int = 8) { self.capacity = max(1, capacity) }

    /// Mete un trozo (espera si ya hay `capacity`).
    public func put(_ d: Data) async throws {
        while chunks.count >= capacity, failure == nil {
            try await withCheckedThrowingContinuation { putters.append($0) }
        }
        if let failure { throw failure }
        if !takers.isEmpty { takers.removeFirst().resume(returning: d) } else { chunks.append(d) }
    }

    /// El origen se ha acabado: quien lea, cuando vacíe la cola, recibe nil.
    public func finish() {
        finished = true
        for t in takers { t.resume(returning: nil) }
        takers = []
    }

    /// Algo ha fallado (o se ha cancelado): se despierta a todos con el error.
    public func fail(_ e: Error) {
        guard failure == nil else { return }
        failure = e
        chunks = []
        for t in takers { t.resume(throwing: e) }
        for p in putters { p.resume(throwing: e) }
        takers = []
        putters = []
    }

    /// El siguiente trozo; nil = no hay más.
    public func take() async throws -> Data? {
        if let failure { throw failure }
        if !chunks.isEmpty {
            let d = chunks.removeFirst()
            if !putters.isEmpty { putters.removeFirst().resume() }
            return d
        }
        if finished { return nil }
        return try await withCheckedThrowingContinuation { takers.append($0) }
    }
}

public enum Transfer {
    /// Copia `reader` → `writer` con lectura y escritura a la vez (dos tareas y una `ChunkPipe` en medio): de servidor a
    /// servidor sin pasar por el disco del Mac. `progress` recibe los bytes escritos hasta ahora. Si algo falla o se
    /// cancela, el destino queda abortado y se lanza el error.
    @discardableResult
    public static func copy(from reader: any RemoteReader, to writer: any RemoteWriter, capacity: Int = 8,
                            progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws -> Int64 {
        let pipe = ChunkPipe(capacity: capacity)
        do {
            let total = try await withThrowingTaskGroup(of: Int64.self) { group in
                group.addTask {                                         // origen → cola
                    do {
                        while let d = try await reader.read() {
                            try Task.checkCancellation()
                            if !d.isEmpty { try await pipe.put(d) }
                        }
                        await pipe.finish()
                        return 0
                    } catch {
                        await pipe.fail(error)
                        throw error
                    }
                }
                group.addTask {                                         // cola → destino
                    var done: Int64 = 0
                    do {
                        while let d = try await pipe.take() {
                            try Task.checkCancellation()
                            try await writer.write(d)
                            done += Int64(d.count)
                            progress(done)
                        }
                        try await writer.finish()
                        return done
                    } catch {
                        await pipe.fail(error)
                        throw error
                    }
                }
                var total: Int64 = 0
                do {
                    for try await n in group { total += n }
                } catch {
                    group.cancelAll()
                    await pipe.fail(error)
                    throw error
                }
                return total
            }
            await reader.close()
            return total
        } catch {
            await reader.close()
            await writer.abort()
            throw error is CancellationError ? RemoteError(L("Cancelada")) : error
        }
    }
}

// MARK: - el Mac (subir y bajar)

/// Lee un archivo del Mac a trozos.
public final class LocalFileReader: RemoteReader, @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    public static let chunk = 256 * 1024

    public init(url: URL) throws { handle = try FileHandle(forReadingFrom: url) }

    public func read() async throws -> Data? {
        let d = try lock.withLock { try handle.read(upToCount: Self.chunk) }
        return d?.isEmpty == false ? d : nil
    }

    public func close() async { lock.withLock { try? handle.close() } }
}

/// Escribe en el Mac: primero en «nombre.part» (0600) y, al acabar bien, se renombra (no deja medio archivo con el
/// nombre bueno). Nunca pisa uno que exista.
public final class LocalFileWriter: RemoteWriter, @unchecked Sendable {
    public let url: URL
    private let part: URL
    private let handle: FileHandle
    private let lock = NSLock()

    public init(url: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { throw RemoteError(L("Ya existe «\(url.lastPathComponent)»")) }
        self.url = url
        // (temporal con nombre único y O_EXCL: nunca abre ni pisa uno que ya esté, ni sigue un enlace)
        part = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.prefix(8)).part")
        let fd = open(part.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else {
            throw RemoteError(L("No se puede escribir en «\(url.deletingLastPathComponent().lastPathComponent)»"))
        }
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    public func write(_ data: Data) async throws { try lock.withLock { try handle.write(contentsOf: data) } }

    public func finish() async throws {
        try lock.withLock {
            try handle.close()
            do { try FileManager.default.moveItem(at: part, to: url) } catch {   // (moveItem no pisa: si ya existe, error)
                try? FileManager.default.removeItem(at: part)
                throw error
            }
        }
    }

    public func abort() async {
        lock.withLock {
            try? handle.close()
            try? FileManager.default.removeItem(at: part)
        }
    }
}

// MARK: - carpetas enteras

/// Lo que hay que copiar de una carpeta (o un archivo): rutas relativas, carpetas antes que su contenido.
public struct TransferItem: Hashable, Sendable {
    public var source: String
    /// «carpeta/sub/archivo» (respecto a donde se copia).
    public var relative: String
    public var isDirectory: Bool
    public var size: Int64?

    public init(source: String, relative: String, isDirectory: Bool, size: Int64? = nil) {
        self.source = source
        self.relative = relative
        self.isDirectory = isDirectory
        self.size = size
    }
}

public enum RemoteOps {
    /// Una ruta relativa sin «..», «/» de más ni nombres raros (antes de escribir en el destino).
    public static func isSafeRelative(_ rel: String) -> Bool {
        let parts = rel.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return !parts.isEmpty && parts.allSatisfy(RemotePath.isValidName)
    }

    /// Tope de lo que se recorre de una vez (que una carpeta enorme o un bucle no deje la app colgada).
    public static let maxItems = 50_000
    public static let maxDepth = 32

    /// Todo lo que cuelga de `entry` (sin seguir enlaces a carpetas: podrían dar vueltas).
    public static func plan(_ fs: any RemoteFileSystem, _ entry: RemoteEntry) async throws -> [TransferItem] {
        guard entry.kind == .directory else {
            return [TransferItem(source: entry.path, relative: entry.name, isDirectory: false, size: entry.size)]
        }
        var out = [TransferItem(source: entry.path, relative: entry.name, isDirectory: true)]
        func walk(_ dir: String, _ rel: String, _ depth: Int) async throws {
            guard depth < maxDepth else { throw RemoteError(L("Demasiados niveles de carpetas en «\(rel)»")) }
            for e in try await fs.list(dir) {
                try Task.checkCancellation()
                guard RemotePath.isValidName(e.name) else { continue }
                let r = rel + "/" + e.name
                if e.kind == .directory {
                    out.append(TransferItem(source: e.path, relative: r, isDirectory: true))
                    try await walk(e.path, r, depth + 1)
                } else {
                    out.append(TransferItem(source: e.path, relative: r, isDirectory: false, size: e.size))
                }
                if out.count > maxItems { throw RemoteError(L("Más de \(maxItems) archivos: cópialos por partes")) }
            }
        }
        try await walk(entry.path, entry.name, 0)
        return out
    }

    /// Borra un archivo o una carpeta con todo lo que lleva dentro (los enlaces se borran, no se siguen).
    public static func removeRecursively(_ fs: any RemoteFileSystem, _ entry: RemoteEntry, depth: Int = 0) async throws {
        guard entry.kind == .directory else { return try await fs.remove(entry.path, directory: false) }
        guard depth < maxDepth else { throw RemoteError(L("Demasiados niveles de carpetas en «\(entry.name)»")) }
        for e in try await fs.list(entry.path) {
            try Task.checkCancellation()
            try await removeRecursively(fs, e, depth: depth + 1)
        }
        try await fs.remove(entry.path, directory: true)
    }
}
