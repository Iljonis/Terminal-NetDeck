import Foundation

/// Un archivo del servidor que se edita en el Mac: la copia local (carpeta propia 0700, archivo 0600) y cómo era el
/// remoto al bajarlo o la última vez que se subió (MD5 y tamaño), para no pisar lo que otro haya cambiado entretanto.
public struct RemoteEditFile: Sendable, Equatable {
    public let remotePath: String
    public let local: URL
    /// El remoto tal como se bajó (o se subió la última vez).
    public var remoteMD5: String
    public var remoteSize: Int64
    /// El MD5 de la copia local cuando coincidía con el remoto: si el de ahora es otro, hay algo guardado sin subir.
    public var syncedMD5: String

    public init(remotePath: String, local: URL, remoteMD5: String, remoteSize: Int64, syncedMD5: String) {
        self.remotePath = remotePath
        self.local = local
        self.remoteMD5 = remoteMD5
        self.remoteSize = remoteSize
        self.syncedMD5 = syncedMD5
    }

    public var name: String { RemotePath.name(remotePath) }
}

/// Editar un archivo del servidor: se baja a la carpeta de edición, se abre en un editor y, al guardarlo, se sube con
/// `AtomicRemoteWriter` (temporal, MD5 comprobado y sustitución sin perder el original), pero sólo si el remoto sigue
/// como se bajó; si no, no se sobrescribe (`UploadResult.conflict`) y la copia local queda como esté.
public enum RemoteEdit {
    /// Lo más grande que se edita (configuraciones, scripts, registros cortos).
    public static let maxSize: Int64 = 5 * 1024 * 1024

    public enum Conflict: Sendable, Equatable {
        /// El remoto ya no es el que se bajó (otro tamaño u otro MD5).
        case changed
        /// Ya no está.
        case removed
        /// El backend no garantiza renombrados sin sobrescritura: hay que confirmar la sobrescritura o conservar lo local.
        case requiresOverwrite
    }

    public enum UploadResult: Sendable, Equatable {
        case uploaded(RemoteEditFile)
        /// La copia local es la que ya está en el servidor: nada que subir.
        case unchanged
        case conflict(Conflict)
    }

    /// ~/Library/Application Support/Terminal NetDeck/edicion
    public static var workspace: URL { AppPaths.support.appendingPathComponent("edicion", isDirectory: true) }

    /// Texto: sin bytes 0 (un binario abierto en un editor de texto se estropearía al guardarlo).
    public static func isText(_ d: Data) -> Bool { !d.contains(0) }

    /// Baja `path` a una carpeta nueva (0700) dentro de `folder`, con el mismo nombre (0600). Sólo archivos normales, de
    /// texto y de hasta `maxSize`.
    public static func download(_ fs: any RemoteFileSystem, _ path: String, into folder: URL,
                                maxSize: Int64 = RemoteEdit.maxSize) async throws -> RemoteEditFile {
        try Task.checkCancellation()
        let name = RemotePath.name(path)
        guard RemotePath.isValidName(name) else { throw RemoteError(L("✗ Nombre no válido")) }
        guard try await fs.lookup(path) == .file else {
            throw RemoteError(L("«\(name)» no es un archivo normal: no se edita"))
        }
        if let n = await fs.size(of: path), n > maxSize { throw tooBig(name, maxSize) }
        let data = try await read(fs, path, maxSize: maxSize)
        try Task.checkCancellation()
        guard isText(data) else { throw RemoteError(L("«\(name)» no es un archivo de texto: no se edita")) }
        let dir = folder.appendingPathComponent(UUID().uuidString.prefix(8).lowercased(), isDirectory: true)
        AppPaths.ensure(folder)
        AppPaths.ensure(dir)
        let url = dir.appendingPathComponent(name)
        let w = try LocalFileWriter(url: url, verify: true)            // (0600, O_EXCL, sin seguir enlaces)
        do {
            try await w.write(data)
            try await w.finish()
            try Task.checkCancellation()
        } catch {
            await w.abort()
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
        let md5 = TransferDigest.hexOf(data)
        return RemoteEditFile(remotePath: path, local: url, remoteMD5: md5, remoteSize: Int64(data.count), syncedMD5: md5)
    }

    /// El MD5 de la copia local ahora mismo.
    public static func localDigest(_ file: RemoteEditFile) throws -> String {
        TransferDigest.hexOf(try readLocal(file))
    }

    /// Sube con temporal y MD5 comprobado. Sin `force`, comprueba la versión antes del envío y en el archivo apartado
    /// al reemplazar en backends con rename sin sobrescritura. FTP/RNTO exige confirmar `force`:
    /// comprobar el MD5 y luego renombrar no equivale a un reemplazo condicional atómico.
    public static func upload(_ fs: any RemoteFileSystem, _ file: RemoteEditFile, force: Bool = false) async throws -> UploadResult {
        let data = try readLocal(file)
        let md5 = TransferDigest.hexOf(data)
        if !force {
            if md5 == file.syncedMD5, md5 == file.remoteMD5 { return .unchanged }
            if let c = try await conflict(fs, file) { return .conflict(c) }
            guard fs.renameDoesNotOverwrite else { return .conflict(.requiresOverwrite) }
        }
        let expected = force ? nil : RemoteFileVersion(md5: file.remoteMD5, size: file.remoteSize)
        do { try await send(data, to: fs, file.remotePath, expected: expected) } catch let c as RemoteVersionConflict {
            switch c {
            case .changed: return .conflict(.changed)
            case .removed: return .conflict(.removed)
            case .unsupported: return .conflict(.requiresOverwrite)
            }
        }
        var f = file
        f.remoteMD5 = md5
        f.remoteSize = Int64(data.count)
        f.syncedMD5 = md5
        return .uploaded(f)
    }

    /// Copia con UUID y publicación exclusiva: una aparición concurrente nunca se reemplaza, ni se aparta.
    /// FTP/RNTO no lo garantiza: se rechaza antes de escribir y se conserva la copia local.
    public static func uploadCopy(_ fs: any RemoteFileSystem, _ file: RemoteEditFile, date: Date = Date()) async throws -> (path: String, file: RemoteEditFile) {
        guard fs.renameDoesNotOverwrite else {
            throw RemoteError(L("Este servidor no permite guardar una copia sin riesgo de sobrescribir otro archivo. Tu copia local se conserva."))
        }
        let data = try readLocal(file)
        let path = copyPath(for: file.remotePath, date: date)
        let writer = try await AtomicRemoteWriter.open(fs, path, verify: true, createOnly: true)
        try await Transfer.copy(from: DataReader(data), to: writer)
        var f = file
        f.syncedMD5 = TransferDigest.hexOf(data)
        return (path, f)
    }

    /// ¿Ha cambiado el remoto desde que se bajó? nil = sigue igual.
    public static func conflict(_ fs: any RemoteFileSystem, _ file: RemoteEditFile) async throws -> Conflict? {
        guard let kind = try await fs.lookup(file.remotePath) else { return .removed }
        guard kind == .file else {
            throw RemoteError(L("«\(file.name)» es una carpeta o un enlace en el destino: no se sustituye ni se toca"))
        }
        if let n = await fs.size(of: file.remotePath), n != file.remoteSize { return .changed }
        let now = try await read(fs, file.remotePath, maxSize: max(maxSize, file.remoteSize))
        return TransferDigest.hexOf(now) == file.remoteMD5 ? nil : .changed
    }

    /// Nombre propio de esta copia; la exclusividad la garantiza el rename al publicar, nunca un lookup.
    public static func copyPath(for path: String, date: Date = Date(), id: UUID = UUID()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let name = RemotePath.name(path), dir = RemotePath.parent(path)
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty || name.hasPrefix(".") && !name.dropFirst().contains(".") ? name : (name as NSString).deletingPathExtension
        let suffix = base == name ? "" : "." + ext
        return RemotePath.join(dir, "\(base).local-\(f.string(from: date))-\(id.uuidString.lowercased())\(suffix)")
    }

    /// Quita una descarga que no llegó al editor si está sincronizada. Una copia abierta se conserva siempre:
    /// el editor puede guardarla atómicamente después de leer el MD5 y antes de borrar la carpeta.
    @discardableResult
    public static func discard(_ file: RemoteEditFile, openedInEditor: Bool = false) -> Bool {
        guard !openedInEditor else { return false }
        if FileManager.default.fileExists(atPath: file.local.path) {
            guard let now = try? localDigest(file), now == file.syncedMD5 else { return false }
        }
        try? FileManager.default.removeItem(at: file.local.deletingLastPathComponent())
        return true
    }

    // MARK: por dentro

    private static func tooBig(_ name: String, _ max: Int64) -> RemoteError {
        RemoteError(L("«\(name)» es demasiado grande para editarlo (máximo \(ByteCountFormatter.string(fromByteCount: max, countStyle: .file)))"))
    }

    private static func readLocal(_ file: RemoteEditFile) throws -> Data {
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: file.local.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size <= maxSize else { throw tooBig(file.name, maxSize) }
        do { return try Data(contentsOf: file.local) } catch {
            throw RemoteError(L("No se puede leer la copia local de «\(file.name)»"))
        }
    }

    /// Todo el archivo remoto, cortando si pasa de `maxSize` (un servidor que no da el tamaño tampoco lo salta).
    private static func read(_ fs: any RemoteFileSystem, _ path: String, maxSize: Int64) async throws -> Data {
        try Task.checkCancellation()
        let r = try await fs.openRead(path)
        var out = Data()
        do {
            while let d = try await r.read() {
                try Task.checkCancellation()
                out.append(d)
                if Int64(out.count) > maxSize { throw tooBig(RemotePath.name(path), maxSize) }
            }
        } catch {
            await Task { await Transfer.closeSource(r) }.value
            throw error is CancellationError ? RemoteError(L("Cancelada")) : error
        }
        await Task { await Transfer.closeSource(r) }.value
        return out
    }

    private static func send(_ data: Data, to fs: any RemoteFileSystem, _ path: String,
                             expected: RemoteFileVersion? = nil) async throws {
        let w = try await AtomicRemoteWriter.open(fs, path, verify: true, expected: expected)
        try await Transfer.copy(from: DataReader(data), to: w)
    }
}

/// Un guardado fallido sigue pendiente aunque no cambien fecha ni tamaño. Sólo se reintenta con conexión,
/// esperando 2, 4, 8… hasta 60 s; una copia pendiente nunca se convierte en sobrescritura del original.
public struct RemoteEditRetry: Sendable {
    public enum Operation: Equatable, Sendable { case upload, copy }
    public private(set) var operation: Operation?
    private var deadline = ContinuousClock.now
    private var delay = Duration.seconds(2)

    public init() {}

    public mutating func failed(_ operation: Operation, now: ContinuousClock.Instant = .now) {
        self.operation = operation
        deadline = now.advanced(by: delay)
        delay = min(delay * 2, .seconds(60))
    }

    public func ready(connected: Bool, now: ContinuousClock.Instant = .now) -> Bool {
        operation != nil && connected && now >= deadline
    }

    public mutating func reset() { self = Self() }
}

/// Lee unos datos ya en memoria, a trozos.
final class DataReader: RemoteReader, @unchecked Sendable {
    private let lock = NSLock()
    private var rest: Data

    init(_ d: Data) { rest = d }

    func read() async throws -> Data? {
        lock.withLock {
            guard !rest.isEmpty else { return nil }
            let d = Data(rest.prefix(256 * 1024))
            rest = Data(rest.dropFirst(d.count))
            return d
        }
    }

    func close() async {}
}

/// Descargas pendientes de edición (reservadas antes de suspenderse). Cerrar invalida también una descarga que
/// termine tarde o ignore la cancelación: nunca abre un editor tras cerrar la pestaña.
@MainActor
public final class RemoteEditDownloads {
    private struct Pending {
        let id: UUID
        let task: Task<Void, Never>
    }
    private var pending: [String: Pending] = [:]
    public private(set) var finished = false

    public init() {}

    @discardableResult
    public func start(_ path: String, download: @escaping @Sendable () async throws -> RemoteEditFile,
                      opened: @escaping @MainActor (RemoteEditFile) -> Void,
                      failed: @escaping @MainActor (Error) -> Void) -> Bool {
        guard !finished, pending[path] == nil else { return false }
        let id = UUID()
        let task = Task { @MainActor in
            do {
                try Task.checkCancellation()
                let file = try await download()
                guard !finished, pending[path]?.id == id, !Task.isCancelled else {
                    RemoteEdit.discard(file)                         // (nunca se abrió en el editor)
                    return
                }
                pending[path] = nil
                opened(file)
            } catch {
                guard !finished, pending[path]?.id == id else { return }
                pending[path] = nil
                failed(error)
            }
        }
        pending[path] = Pending(id: id, task: task)
        return true
    }

    public func finish() {
        finished = true
        let tasks = pending.values.map(\.task)
        pending = [:]
        tasks.forEach { $0.cancel() }
    }
}
