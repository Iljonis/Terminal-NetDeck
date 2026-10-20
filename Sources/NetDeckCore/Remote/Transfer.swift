import CryptoKit
import Foundation

/// MD5 de lo que pasa por una copia (para comprobar que el destino tiene exactamente lo mismo).
public struct TransferDigest: Sendable {
    private var md5 = Insecure.MD5()
    public init() {}
    public mutating func update(_ d: Data) { md5.update(data: d) }
    public func hex() -> String { md5.finalize().map { String(format: "%02x", $0) }.joined() }

    public static func hexOf(_ d: Data) -> String {
        var x = TransferDigest()
        x.update(d)
        return x.hex()
    }

    /// El MD5 que haya en un texto pegado («md5sum», «MD5 (x) = …», «verify /md5 … = …» de Cisco, en mayúsculas…):
    /// el primer bloque de exactamente 32 hexadecimales, en minúsculas. nil si no hay ninguno.
    public static func extract(_ text: String) -> String? {
        let hex = Set("0123456789abcdefABCDEF")
        var run = ""
        for c in text + " " {
            if hex.contains(c) { run.append(c); continue }
            if run.count == 32 { return run.lowercased() }
            run = ""
        }
        return nil
    }

    /// Cada cuánto se avisa del progreso (y siempre al acabar): no un aviso por cada trozo de 32 KiB.
    public static let progressStep: Int64 = 1 << 20

    /// El MD5 de todo lo que dé `reader` (y lo cierra). `progress`: los bytes leídos hasta ahora (cada `progressStep`
    /// y al final). Cancelado, para en el siguiente trozo y cierra el lector.
    public static func of(_ reader: any RemoteReader, progress: @Sendable (Int64) -> Void = { _ in }) async throws -> String {
        var d = TransferDigest()
        var read: Int64 = 0, told: Int64 = 0
        do {
            try Task.checkCancellation()
            while let chunk = try await reader.read() {
                try Task.checkCancellation()
                d.update(chunk)
                read += Int64(chunk.count)
                if read - told >= progressStep { told = read; progress(read) }
            }
            if read != told || read == 0 { progress(read) }
        } catch {
            await reader.close()
            throw error
        }
        await reader.close()
        return d.hex()
    }
}

/// No se sabe si un renombrado llegó a aplicarse: no se borra ninguna de las rutas recuperables.
public struct ReplaceStuckError: LocalizedError, Equatable, Sendable {
    public let path: String
    public let previous: String
    public let new: String
    public var errorDescription: String? {
        L("No se ha podido confirmar la sustitución de «\(AppPaths.tilde(path))». Revisa el destino y las copias conservadas: anterior «\(AppPaths.tilde(previous))»; nueva «\(AppPaths.tilde(new))».")
    }
}

/// La versión que debe tener el archivo apartado antes de publicar una edición (nil permite sobrescribir).
public struct RemoteFileVersion: Sendable, Equatable {
    public let md5: String
    public let size: Int64
    public init(md5: String, size: Int64) { self.md5 = md5; self.size = size }
}

public enum RemoteVersionConflict: Error, Sendable, Equatable { case changed, removed, unsupported }

/// El destino no tiene lo mismo que el origen (MD5 distinto): no se ha dejado con el nombre bueno.
public struct IntegrityError: LocalizedError, Equatable {
    public let name: String
    public let source: String
    public let copied: String
    public var errorDescription: String? {
        L("MD5 distinto en «\(name)» (origen \(String(source.prefix(8))), copia \(String(copied.prefix(8)))): no se ha guardado")
    }
}

/// Cola de trozos con tope (el puente en memoria): quien lee del origen espera si está llena, quien escribe en el
/// destino espera si está vacía. Así la RAM usada no pasa de `capacity` trozos ni de `maxBytes`, sea el archivo del
/// tamaño que sea (y el que lee puede ir por delante: un servidor lento no frena al otro trozo a trozo).
public actor ChunkPipe {
    private var chunks: [Data] = []
    private var bytes = 0
    private var finished = false
    private var failure: Error?
    private var takers: [CheckedContinuation<Data?, Error>] = []
    private var putters: [CheckedContinuation<Void, Error>] = []
    public let capacity: Int
    public let maxBytes: Int

    public init(capacity: Int = 64, maxBytes: Int = 8 * 1024 * 1024) {
        self.capacity = max(1, capacity)
        self.maxBytes = max(1, maxBytes)
    }

    /// Mete un trozo (espera si ya hay `capacity` o `maxBytes`; uno solo, aunque sea grande, siempre cabe).
    public func put(_ d: Data) async throws {
        while !chunks.isEmpty, chunks.count >= capacity || bytes + d.count > maxBytes, failure == nil {
            try await withCheckedThrowingContinuation { putters.append($0) }
        }
        if let failure { throw failure }
        if !takers.isEmpty {
            takers.removeFirst().resume(returning: d)
        } else {
            chunks.append(d)
            bytes += d.count
        }
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
        bytes = 0
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
            bytes -= d.count
            if !putters.isEmpty { putters.removeFirst().resume() }
            return d
        }
        if finished { return nil }
        return try await withCheckedThrowingContinuation { takers.append($0) }
    }
}

public enum Transfer {
    /// Cada cuánto se avisa del progreso (como mucho): sin inundar el hilo principal con un aviso por trozo.
    public static let progressInterval: Duration = .milliseconds(100)

    /// Copia `reader` → `writer` con lectura y escritura a la vez (dos tareas y una `ChunkPipe` en medio): de servidor a
    /// servidor sin pasar por el disco del Mac. `progress` recibe los bytes escritos hasta ahora (cada
    /// `progressInterval` y al final). Si algo falla o se cancela, el destino queda abortado y se lanza el error;
    /// cancelar despierta al momento a quien espere en la cola (y cada lado corta su conexión).
    @discardableResult
    public static func copy(from reader: any RemoteReader, to writer: any RemoteWriter, capacity: Int = 64,
                            progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws -> Int64 {
        let pipe = ChunkPipe(capacity: capacity)
        do {
            let total = try await withTaskCancellationHandler {
              try await withThrowingTaskGroup(of: Int64.self) { group in
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
                    let clock = ContinuousClock()
                    var told = clock.now
                    do {
                        while let d = try await pipe.take() {
                            try Task.checkCancellation()
                            try await writer.write(d)
                            done += Int64(d.count)
                            if clock.now - told >= progressInterval {
                                told = clock.now
                                progress(done)
                            }
                        }
                        try await writer.finish()
                        progress(done)
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
            } onCancel: {
                Task { await pipe.fail(CancellationError()) }
            }
            await closeSource(reader)
            return total
        } catch {
            // (fuera de la tarea, que puede estar cancelada: así se cierra el origen y se borra el temporal de verdad; a
            // la vez y con tope: un origen que no contesta al CLOSE no deja sin abortar el destino)
            await Task {
                async let source: Void = closeSource(reader)
                async let target: Void = writer.abort()
                _ = await (source, target)
            }.value
            throw error is CancellationError ? RemoteError(L("Cancelada")) : error
        }
    }
}

extension Transfer {
    /// Cerrar el origen, con el mismo tope que la limpieza del destino (un servidor mudo no deja la copia colgada).
    static func closeSource(_ reader: any RemoteReader) async {
        do { try await RemoteOps.withTimeout(AtomicRemoteWriter.cleanupSeconds) { await reader.close() } } catch {
            ErrorLog.warning("transferencia", "el origen no contesta al cerrarlo")
        }
    }
}

// MARK: - el Mac (subir y bajar)

/// Lee un archivo del Mac a trozos.
public final class LocalFileReader: RemoteReader, @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    public static let chunk = 1024 * 1024

    public init(url: URL) throws { handle = try FileHandle(forReadingFrom: url) }

    public func read() async throws -> Data? {
        let d = try lock.withLock { try handle.read(upToCount: Self.chunk) }
        return d?.isEmpty == false ? d : nil
    }

    public func close() async { lock.withLock { try? handle.close() } }
}

/// Escribe en el Mac: primero en «nombre.part» (0600) y, al acabar bien, se renombra (no deja medio archivo con el
/// nombre bueno). Nunca pisa uno que exista. Con `verify`, antes de renombrar se vuelve a leer del disco y su MD5
/// tiene que ser el de lo recibido (`digest`).
public final class LocalFileWriter: RemoteWriter, @unchecked Sendable {
    public let url: URL
    private let part: URL
    private let handle: FileHandle
    private let lock = NSLock()
    private let verify: Bool
    private var running = TransferDigest()
    /// El MD5 de lo escrito (tras `finish`).
    public private(set) var digest: String?

    public init(url: URL, verify: Bool = false) throws {
        self.verify = verify
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

    public func write(_ data: Data) async throws {
        try lock.withLock {
            try handle.write(contentsOf: data)
            running.update(data)
        }
    }

    public func finish() async throws {
        let sent: String = try lock.withLock {
            try handle.close()
            return running.hex()
        }
        do {
            if verify {
                let copied = try await TransferDigest.of(try LocalFileReader(url: part))
                guard copied == sent else { throw IntegrityError(name: url.lastPathComponent, source: sent, copied: copied) }
            }
            try FileManager.default.moveItem(at: part, to: url)        // (moveItem no pisa: si ya existe, error)
            lock.withLock { digest = sent }
        } catch {
            try? FileManager.default.removeItem(at: part)
            throw error
        }
    }

    public func abort() async {
        lock.withLock {
            try? handle.close()
            try? FileManager.default.removeItem(at: part)
        }
    }
}

// MARK: - destino remoto sin medio archivo

/// Escribe en un servidor sin dejar nunca medio archivo con el nombre bueno: primero en «.nombre.xxxxxxxx.part» (en la
/// misma carpeta), al acabar (y con `verify`, tras volver a leerlo y comprobar que su MD5 es el de lo enviado) se
/// renombra encima del destino. Ante un resultado incierto se conservan las rutas recuperables y se indican en el error.
public actor AtomicRemoteWriter: RemoteWriter {
    public nonisolated let path: String
    public nonisolated let part: String
    private let fs: any RemoteFileSystem
    private let inner: any RemoteWriter
    private let verify: Bool
    private let expected: RemoteFileVersion?
    private let replacementSeconds: Int
    private var running = TransferDigest()
    private var done = false
    private var finishing = false
    /// El MD5 de lo enviado (tras `finish`).
    public private(set) var digest: String?

    private init(fs: any RemoteFileSystem, path: String, part: String, inner: any RemoteWriter, verify: Bool,
                 expected: RemoteFileVersion?, replacementSeconds: Int) {
        self.fs = fs
        self.path = path
        self.part = part
        self.inner = inner
        self.verify = verify
        self.expected = expected
        self.replacementSeconds = replacementSeconds
    }

    /// «/datos/copia.bin» → «/datos/.copia.bin.1a2b3c4d.part» (o sin el punto delante: `hidden` false).
    public static func partPath(for path: String, hidden: Bool = true) -> String {
        RemotePath.join(RemotePath.parent(path),
                        (hidden ? "." : "") + "\(RemotePath.name(path)).\(UUID().uuidString.prefix(8).lowercased()).part")
    }

    /// Algunos servidores FTP no dejan crear archivos que empiezan por «.»: entonces el temporal va sin el punto.
    public static func open(_ fs: any RemoteFileSystem, _ path: String, verify: Bool,
                            expected: RemoteFileVersion? = nil, replacementSeconds: Int = 10) async throws -> AtomicRemoteWriter {
        guard expected == nil || fs.renameDoesNotOverwrite else { throw RemoteVersionConflict.unsupported }
        _ = try await existingFile(fs, path)                // (una carpeta o un enlace: ni el temporal se escribe)
        var part = partPath(for: path)
        let inner: any RemoteWriter
        do { inner = try await fs.openWrite(part) } catch {
            try Task.checkCancellation()
            part = partPath(for: path, hidden: false)
            inner = try await fs.openWrite(part)
        }
        return AtomicRemoteWriter(fs: fs, path: path, part: part, inner: inner, verify: verify,
                                  expected: expected, replacementSeconds: replacementSeconds)
    }

    public func write(_ data: Data) async throws {
        running.update(data)
        try await inner.write(data)
    }

    public func finish() async throws {
        guard !done, !finishing else { throw RemoteError(L("Cancelada")) }
        finishing = true
        defer { finishing = false }
        let sent = running.hex()
        do {
            try await inner.finish()
            if verify {
                let copied = try await TransferDigest.of(try await fs.openRead(part))
                guard copied == sent else { throw IntegrityError(name: RemotePath.name(path), source: sent, copied: copied) }
            }
            try await replace()
            done = true
            digest = sent
        } catch let stuck as ReplaceStuckError {
            done = true                                     // (el temporal ES el nuevo: no se borra)
            ErrorLog.error("transferencia", stuck.errorDescription ?? "")
            throw stuck
        } catch {
            done = true
            await cleanUp(abortInner: true)             // (si `inner.finish` falló, su handle sigue abierto)
            throw error
        }
    }

    /// Lo más que se espera a la limpieza (el CLOSE y el borrado del temporal) de un servidor que ya no contesta.
    nonisolated(unsafe) static var cleanupSeconds = 10

    /// Fuera de la tarea (que puede estar cancelada: sus esperas acabarían al momento sin borrar nada), pero con tope:
    /// si el servidor deja de contestar, cancelar acaba igual y el temporal se queda (y se apunta dónde).
    private func cleanUp(abortInner: Bool) async {
        let fs = fs, inner = inner, part = part, seconds = Self.cleanupSeconds
        await Task {
            do {
                try await RemoteOps.withTimeout(seconds) {
                    if abortInner { await inner.abort() }
                    try? await fs.remove(part, directory: false)
                }
            } catch {
                ErrorLog.warning("transferencia", "el servidor no contesta al cancelar: queda el temporal \(part)")
            }
        }.value
    }

    /// Cada espera del reemplazo tiene tope y recibe la cancelación. Si se pierde la respuesta a un rename,
    /// podría haberse aplicado: se conservan todas las rutas, sin otro rename ni borrado a ciegas.
    private func replace() async throws {
        let fs = fs, path = path, part = part, seconds = replacementSeconds
        guard expected == nil || fs.renameDoesNotOverwrite else { throw RemoteVersionConflict.unsupported }
        let old = String(Self.partPath(for: path).dropLast(5)) + ".old"
        let stuck = ReplaceStuckError(path: path, previous: old, new: part)
        let kind = try await RemoteOps.withTimeout(seconds) { try await Self.existingFile(fs, path) }
        if expected != nil, kind == nil { throw RemoteVersionConflict.removed }
        if kind == .file {
            try await RemoteOps.withTimeout(seconds) {
                if let mode = await fs.permissions(of: path) { try? await fs.setPermissions(mode, of: part) }
                try Task.checkCancellation()
            }
        }
        try Task.checkCancellation()
        // (FTP puede pisar directamente; una edición con versión esperada SIEMPRE valida el archivo apartado)
        if expected == nil {
            do {
                try await RemoteOps.withTimeout(seconds) { try await fs.rename(part, to: path) }
                return
            } catch {
                if Self.uncertain(error) {
                    throw ReplaceStuckError(path: path, previous: path, new: part)
                }
                guard kind == .file else { throw error }
                // (una respuesta perdida también puede llegar como error de conexión: comprobar antes de apartar)
                do {
                    let source = try await RemoteOps.withTimeout(seconds) { try await fs.lookup(part) }
                    guard source == .file else { throw ReplaceStuckError(path: path, previous: path, new: part) }
                } catch { throw ReplaceStuckError(path: path, previous: path, new: part) }
            }
        }
        let current = try await RemoteOps.withTimeout(seconds) { try await Self.existingFile(fs, path) }
        if expected != nil, current == nil { throw RemoteVersionConflict.removed }
        try Task.checkCancellation()
        do {
            try await RemoteOps.withTimeout(seconds) { try await fs.rename(path, to: old) }
        } catch {
            // (también al apartar puede perderse la respuesta después de que el servidor haya movido el archivo)
            throw stuck
        }
        do {
            if let expected {
                let matches = try await RemoteOps.withTimeout(seconds) {
                    guard try await Self.existingFile(fs, old) == .file else { return false }
                    if let n = await fs.size(of: old), n != expected.size { return false }
                    return try await TransferDigest.of(try await fs.openRead(old)) == expected.md5
                }
                guard matches else { throw RemoteVersionConflict.changed }
                let occupied = try await RemoteOps.withTimeout(seconds) { try await fs.lookup(path) != nil }
                guard !occupied else { throw stuck }       // (SFTP además rechaza una aparición posterior al lookup)
            }
            try Task.checkCancellation()
        } catch {
            try await restore(old, stuck: stuck)
            throw error
        }
        do {
            try await RemoteOps.withTimeout(seconds) { try await fs.rename(part, to: path) }
        } catch {
            // (cancelar la espera no deshace una orden que el servidor ya ha recibido)
            guard !Self.uncertain(error) else { throw stuck }
            try await restore(old, stuck: stuck)
            throw error
        }
        // (el nuevo ya está confirmado; si no se puede borrar el anterior, sigue siendo recuperable)
        do {
            try await RemoteOps.withTimeout(seconds) { try await fs.remove(old, directory: false) }
        } catch {
            ErrorLog.warning("transferencia", "no se ha podido borrar la copia anterior: \(old)")
        }
    }

    private static func uncertain(_ error: Error) -> Bool {
        error is CancellationError || error is RemoteTimeout || Task.isCancelled
    }

    /// Recuperación independiente de la cancelación del envío, con tope. Con versión esperada, el backend también
    /// rechaza una aparición posterior al lookup; sin esa garantía sólo se admiten escrituras explícitas.
    private func restore(_ old: String, stuck: ReplaceStuckError) async throws {
        let fs = fs, path = path, part = part, seconds = replacementSeconds
        do {
            try await Task {
                try await RemoteOps.withTimeout(seconds) {
                    guard try await fs.lookup(path) == nil,
                          try await Self.existingFile(fs, old) == .file,
                          try await Self.existingFile(fs, part) == .file else { throw stuck }
                    try Task.checkCancellation()
                    try await fs.rename(old, to: path)
                }
            }.value
        } catch { throw stuck }
    }

    /// Qué hay en `path`: un archivo normal (.file) o, confirmado, nada (nil). Una carpeta, un enlace, otra cosa o lo
    /// que no se puede saber (permisos, un LIST que falla, un tipo desconocido): error, sin tocar nada.
    static func existingFile(_ fs: any RemoteFileSystem, _ path: String) async throws -> RemoteEntry.Kind? {
        let kind = try await fs.lookup(path)
        if let kind, kind != .file {
            throw RemoteError(L("«\(RemotePath.name(path))» es una carpeta o un enlace en el destino: no se sustituye ni se toca"))
        }
        return kind
    }

    public func abort() async {
        guard !done, !finishing else { return }
        done = true
        await cleanUp(abortInner: true)
    }
}

// MARK: - el origen, de sólo lectura

/// Una copia sólo lee del origen: nunca lo borra, lo renombra ni lo trunca. El único sitio en el que algo podría
/// tocarlo es `AtomicRemoteWriter.replace`, que aparta y borra el archivo que ya hubiera en el destino: si la carpeta
/// de destino es la del origen vista por otro camino (el mismo servidor con otro nombre o por otra sesión, otro
/// usuario, un enlace, el propio Mac por SFTP), ese «archivo de destino» es el original. Antes de escribir en cada
/// carpeta se comprueba: se deja en ella un testigo vacío con nombre único y, si el origen lo ve en su carpeta, son la
/// misma y la copia se para sin escribir nada. El testigo se borra al momento (es lo único que se borra).
public actor SourceGuard {
    private let destination: any RemoteFileSystem
    /// ¿Existe esa ruta en el origen?
    private let sourceSees: @Sendable (String) async -> Bool
    /// Cómo se enseña una carpeta del destino en el aviso.
    private let show: @Sendable (String) -> String
    /// «carpeta de origen \0 carpeta de destino» → ¿son la misma? (sólo lo comprobado de verdad)
    private var checked: [String: Bool] = [:]

    public init(destination: any RemoteFileSystem, show: @escaping @Sendable (String) -> String = { $0 },
                sourceSees: @escaping @Sendable (String) async -> Bool) {
        self.destination = destination
        self.show = show
        self.sourceSees = sourceSees
    }

    /// De un servidor a otro (o al mismo). FTP no dice el tipo y hay equipos sin SIZE: entonces, en el listado.
    public static func remote(_ source: any RemoteFileSystem, to destination: any RemoteFileSystem) -> SourceGuard {
        SourceGuard(destination: destination) { path in
            if await source.kind(of: path) != nil { return true }
            if await source.size(of: path) != nil { return true }
            let name = RemotePath.name(path)
            return (try? await source.list(RemotePath.parent(path)))?.contains { $0.name == name } ?? false
        }
    }

    /// Del Mac a un servidor (un SFTP que puede ser el propio Mac: en el aviso, la ruta con «~»).
    public static func local(to destination: any RemoteFileSystem) -> SourceGuard {
        SourceGuard(destination: destination, show: { AppPaths.tilde($0) }) { path in
            var st = stat()
            return lstat(path, &st) == 0
        }
    }

    /// Lanza un error (sin haber escrito nada) si `target` puede ser el propio `source`, o si no se ha podido
    /// comprobar (no se sigue a ciegas: se vuelve a probar en la próxima copia).
    public func check(source: String, target: String) async throws {
        guard RemotePath.name(source) == RemotePath.name(target) else { return }   // (otro nombre: otro archivo)
        let srcDir = RemotePath.parent(source), dstDir = RemotePath.parent(target)
        let key = srcDir + "\u{0}" + dstDir
        let same: Bool
        if let known = checked[key] { same = known } else {
            guard let probed = await probe(srcDir: srcDir, dstDir: dstDir) else {
                throw RemoteError(L("No se ha podido comprobar que «\(show(dstDir))» no es la carpeta de origen: no se copia"))
            }
            same = probed
            checked[key] = same
        }
        if same { throw RemoteError(L("✗ «\(show(dstDir))» es la misma carpeta que la de origen: no se copia nada encima del original")) }
    }

    /// nil: no se ha podido dejar el testigo.
    private func probe(srcDir: String, dstDir: String) async -> Bool? {
        let fs = destination, sees = sourceSees
        let tag = UUID().uuidString.prefix(12).lowercased()
        // (fuera de la tarea, que puede estar cancelada: el testigo se borra siempre)
        return await Task {
            // (primero sin el punto: los LIST de FTP suelen esconder los «.algo» y algunos no dejan crearlos)
            for name in ["netdeck-\(tag).testigo", ".netdeck-\(tag).testigo"] {
                let marker = RemotePath.join(dstDir, name)
                guard let w = try? await fs.openWrite(marker) else { continue }
                do { try await w.finish() } catch {
                    await w.abort()
                    await Self.discard(fs, marker)
                    continue
                }
                let same = await sees(RemotePath.join(srcDir, name))
                await Self.discard(fs, marker)
                return same
            }
            return nil
        }.value
    }

    private static func discard(_ fs: any RemoteFileSystem, _ marker: String) async {
        do { try await fs.remove(marker, directory: false) } catch {
            ErrorLog.warning("transferencia", "No se ha podido borrar el testigo \(fs.label):\(marker): \(error.localizedDescription)")
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

/// Lo de la interfaz que bloquea (un aviso modal con `NSApp.runModal`) nunca dentro de la acción de un botón: ahí
/// SwiftUI está a medio actualizar y el aviso no recibe los clics (la app se queda colgada). Se hace en la vuelta
/// siguiente del bucle principal, con la acción ya terminada. Por el run loop (modo normal) y no por la cola
/// principal: así, mientras el aviso está abierto, la cola sigue (las otras pestañas, las contraseñas automáticas, el
/// progreso de las copias), y un segundo aviso espera a que se cierre el primero en vez de abrirse encima.
public enum MainTurn {
    @MainActor
    public static func next<T: Sendable>(_ body: @escaping @MainActor () -> T) async -> T {
        await withCheckedContinuation { c in
            RunLoop.main.perform(inModes: [.default]) { MainActor.assumeIsolated { c.resume(returning: body()) } }
        }
    }
}

/// Una operación remota que no contesta en `seconds` (servidor mudo, red caída).
public struct RemoteTimeout: LocalizedError, Equatable {
    public let seconds: Int
    public var errorDescription: String? { L("El servidor no contesta (\(seconds) s): se ha cancelado") }
}

public enum RemoteOps {
    /// `body` con un tope: si no acaba en `seconds`, se cancela (SFTP y FTP cortan sus esperas al cancelar) y se lanza
    /// `RemoteTimeout`. Así ningún botón de la interfaz queda esperando para siempre a un servidor que no contesta.
    public static func withTimeout<T: Sendable>(_ seconds: Int, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw RemoteTimeout(seconds: seconds)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw RemoteTimeout(seconds: seconds) }
            return first
        }
    }

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

    /// Una carpeta de destino que se puede usar tal cual: absoluta, sin «.»/«..» ni nombres raros (en FTP un salto de
    /// línea metería otra orden). Devuelve la ruta limpia («/a/b», sin «/» al final) o nil.
    public static func cleanDirectory(_ dir: String) -> String? {
        guard dir.hasPrefix("/") else { return nil }
        let parts = dir.split(separator: "/").map(String.init)
        guard parts.allSatisfy(RemotePath.isValidName) else { return nil }
        return "/" + parts.joined(separator: "/")
    }

    /// Por qué no se mueve algo a una carpeta del mismo servidor (nil: se puede).
    public enum MoveProblem: Equatable, Sendable {
        /// Ya está en esa carpeta (no se hace nada).
        case sameFolder
        /// Una carpeta dentro de sí misma o de una suya.
        case intoItself
    }

    /// Lo que se puede saber sin preguntar al servidor (`dir` ya limpia, ver `cleanDirectory`).
    public static func moveProblem(_ entry: RemoteEntry, to dir: String) -> MoveProblem? {
        if RemotePath.parent(entry.path) == dir { return .sameFolder }
        if dir == entry.path || dir.hasPrefix(entry.path == "/" ? "/" : entry.path + "/") { return .intoItself }
        return nil
    }

    /// Mover dentro del mismo servidor: un `rename` por elemento (atómico en el servidor, con los permisos del usuario;
    /// nada se copia ni se borra). Antes se comprueba todo (destino válido, nada dentro de sí mismo, nada que pisar,
    /// con una sola lectura de la carpeta de destino): si algo falla no se mueve nada. Los que ya están allí se saltan.
    /// Devuelve las rutas nuevas de lo movido; al primer `rename` que falle se para y lanza (lo anterior queda movido).
    @discardableResult
    public static func move(_ fs: any RemoteFileSystem, _ entries: [RemoteEntry], to dir: String,
                            timeout: Int = callTimeout) async throws -> [String] {
        guard let dir = cleanDirectory(dir) else { throw RemoteError(L("Carpeta de destino no válida")) }
        var todo: [RemoteEntry] = []
        for e in entries {
            switch moveProblem(e, to: dir) {
            case .sameFolder?: continue
            case .intoItself?: throw RemoteError(L("«\(e.name)» no se puede mover dentro de sí misma"))
            case nil:
                guard RemotePath.isValidName(e.name), !todo.contains(where: { $0.name == e.name }) else {
                    throw RemoteError(L("Ya hay «\(e.name)» en \(dir): no se mueve"))
                }
                todo.append(e)
            }
        }
        guard !todo.isEmpty else { return [] }
        let there = Set(try await withTimeout(timeout) { try await fs.list(dir) }.map(\.name))
        if let clash = todo.first(where: { there.contains($0.name) }) {
            throw RemoteError(L("Ya hay «\(clash.name)» en \(dir): no se mueve"))
        }
        var moved: [String] = []
        for e in todo {
            try Task.checkCancellation()
            let to = RemotePath.join(dir, e.name)
            // (y justo antes, por el nombre: un LIST de FTP puede no enseñar los ocultos, el servidor puede no
            //  distinguir mayúsculas, y RNTO sí sustituye; SFTP no, pero tampoco sobra)
            let kind = await fs.kind(of: to), size = await fs.size(of: to)
            if kind != nil || size != nil {
                throw RemoteError(L("Ya hay «\(e.name)» en \(dir): no se mueve"))
            }
            try await withTimeout(timeout) { try await fs.rename(e.path, to: to) }
            moved.append(to)
        }
        return moved
    }

    /// Lo más que se espera cada petición de la interfaz (borrar, renombrar, crear carpeta) a un servidor que no
    /// contesta.
    public static let callTimeout = 30

    /// Borra un archivo o una carpeta con todo lo que lleva dentro (los enlaces se borran, no se siguen). Cada petición
    /// con `timeout` (si se da): una carpeta enorme tarda lo que tarde, pero un servidor mudo no la deja colgada.
    public static func removeRecursively(_ fs: any RemoteFileSystem, _ entry: RemoteEntry, depth: Int = 0,
                                         timeout: Int? = nil) async throws {
        func call<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async throws -> T {
            if let timeout { return try await withTimeout(timeout, body) }
            return try await body()
        }
        guard entry.kind == .directory else { return try await call { try await fs.remove(entry.path, directory: false) } }
        guard depth < maxDepth else { throw RemoteError(L("Demasiados niveles de carpetas en «\(entry.name)»")) }
        for e in try await call({ try await fs.list(entry.path) }) {
            try Task.checkCancellation()
            try await removeRecursively(fs, e, depth: depth + 1, timeout: timeout)
        }
        try await call { try await fs.remove(entry.path, directory: true) }
    }
}
