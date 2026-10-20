import Foundation
import Testing
@testable import NetDeckCore

/// Renombrados reales contra sftp-server, con pérdida de respuesta antes/después de aplicar la orden. No basta con
/// que rename lance un error: un servidor puede haber movido el archivo aunque no llegue la confirmación.
@Suite(.serialized) struct EdicionTransaccionesTests {
    static let server = "/usr/libexec/sftp-server"

    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-edicion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.resolvingSymlinksInPath()
    }

    private func connect() async throws -> SFTPFileSystem {
        try await SFTPFileSystem.connect(label: "prueba", executable: Self.server, arguments: [], environment: [:])
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)),
          arguments: [EdicionFallosFS.Failure.publishMute, .publishAppliedMute, .backupAppliedMute,
                      .rollbackMute, .rollbackAppliedMute, .occupy, .publishAppliedError, .backupAppliedError, .rollbackAppliedError])
    func resultadoInciertoConservaRutas(failure: EdicionFallosFS.Failure) async throws {
        let dir = try folder(), target = dir.appendingPathComponent("core-01.cfg")
        defer { try? FileManager.default.removeItem(at: dir) }
        let before = Data("anterior".utf8), after = Data("editado".utf8)
        try before.write(to: target)
        let inner = try await connect()
        defer { Task { await inner.close() } }
        let fs = EdicionFallosFS(inner, path: target.path, failure: failure)
        let w = try await AtomicRemoteWriter.open(fs, target.path, verify: true, replacementSeconds: 1)
        let start = ContinuousClock.now
        var failureResult: ReplaceStuckError?
        do { try await Transfer.copy(from: DataReader(after), to: w) } catch let error as ReplaceStuckError {
            failureResult = error
        }
        let error = try #require(failureResult)
        #expect(ContinuousClock.now - start < .seconds(5))
        #expect(error.path == target.path && error.new == w.part)
        #expect(error.localizedDescription.contains(error.previous) && error.localizedDescription.contains(error.new))
        await w.abort()                                    // (la limpieza de Transfer tampoco borra las copias)
        let previous = FileManager.default.fileExists(atPath: error.previous) ? error.previous : target.path
        let new = FileManager.default.fileExists(atPath: error.new) ? error.new : target.path
        #expect(try Data(contentsOf: URL(fileURLWithPath: previous)) == before)
        #expect(try Data(contentsOf: URL(fileURLWithPath: new)) == after)
        if failure == .occupy { #expect(try Data(contentsOf: target) == Data("tercero".utf8)) }
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func cancelarTrasApartarNoEsperaAlServidor() async throws {
        let dir = try folder(), target = dir.appendingPathComponent("core-01.cfg")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("anterior".utf8).write(to: target)
        let inner = try await connect()
        defer { Task { await inner.close() } }
        let fs = EdicionFallosFS(inner, path: target.path, failure: .publishMute)
        let w = try await AtomicRemoteWriter.open(fs, target.path, verify: true, replacementSeconds: 30)
        let copy = Task { try await Transfer.copy(from: DataReader(Data("nuevo".utf8)), to: w) }
        defer { copy.cancel() }
        for _ in 0..<400 where !fs.hanging { try await Task.sleep(for: .milliseconds(5)) }
        #expect(fs.hanging)
        let start = ContinuousClock.now
        copy.cancel()
        var stuck: ReplaceStuckError?
        do { _ = try await copy.value } catch let error as ReplaceStuckError { stuck = error }
        let error = try #require(stuck)
        #expect(ContinuousClock.now - start < .seconds(3))
        #expect(try Data(contentsOf: URL(fileURLWithPath: error.previous)) == Data("anterior".utf8))
        #expect(try Data(contentsOf: URL(fileURLWithPath: error.new)) == Data("nuevo".utf8))
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func falloConfirmadoRestauraAntesDeLimpiar() async throws {
        let dir = try folder(), target = dir.appendingPathComponent("core-01.cfg")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("anterior".utf8).write(to: target)
        let inner = try await connect()
        defer { Task { await inner.close() } }
        let fs = EdicionFallosFS(inner, path: target.path, failure: .reject)
        let w = try await AtomicRemoteWriter.open(fs, target.path, verify: true, replacementSeconds: 1)
        await #expect(throws: RemoteError.self) { try await Transfer.copy(from: DataReader(Data("nuevo".utf8)), to: w) }
        #expect(try Data(contentsOf: target) == Data("anterior".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["core-01.cfg"])
    }

    /// Ambos editores pasan el MD5 previo antes de terminar el envío. El segundo comprueba la copia apartada,
    /// descubre la edición del primero y la restaura; «Sobrescribir» sigue permitiendo sustituirla expresamente.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func dosEditoresConLaMismaBaseNoSePisan() async throws {
        let dir = try folder(), work = try folder(), target = dir.appendingPathComponent("core-01.cfg")
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: work) }
        try Data("base".utf8).write(to: target)
        let fs1 = try await connect(), fs2 = try await connect()
        defer { Task { await fs1.close(); await fs2.close() } }
        let a = try await RemoteEdit.download(fs1, target.path, into: work)
        let b = try await RemoteEdit.download(fs2, target.path, into: work)
        try Data("uno!".utf8).write(to: a.local, options: .atomic)
        try Data("dos!".utf8).write(to: b.local, options: .atomic)
        let gate1 = EdicionPause(), gate2 = EdicionPause()
        let slow1 = EdicionFallosFS(fs1, path: target.path, failure: .none, writeGate: gate1)
        let slow2 = EdicionFallosFS(fs2, path: target.path, failure: .none, writeGate: gate2)
        let upload1 = Task { try await RemoteEdit.upload(slow1, a) }
        let upload2 = Task { try await RemoteEdit.upload(slow2, b) }
        defer {
            upload1.cancel(); upload2.cancel()
            Task { await gate1.release(); await gate2.release() }
        }
        for _ in 0..<400 {
            if await gate1.waiting, await gate2.waiting { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await gate1.waiting)
        #expect(await gate2.waiting)
        await gate1.release()
        guard case .uploaded = try await upload1.value else { Issue.record("no se ha subido el primero"); await gate2.release(); return }
        await gate2.release()
        #expect(try await upload2.value == .conflict(.changed))
        #expect(try Data(contentsOf: target) == Data("uno!".utf8))
        #expect(try Data(contentsOf: b.local) == Data("dos!".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["core-01.cfg"])
        guard case .uploaded = try await RemoteEdit.upload(fs2, b, force: true) else { Issue.record("no se ha sobrescrito"); return }
        #expect(try Data(contentsOf: target) == Data("dos!".utf8))
    }

    /// RNTO puede pisar una aparición posterior al lookup: sin capacidad declarada, ni siquiera se crea el temporal
    /// de una edición condicional. La copia y la sobrescritura explícitas siguen disponibles.
    @Test func FTPExigeCopiaOSobrescrituraExplicita() async throws {
        let inner = MemoryFileSystem(), path = "/d/core-01.cfg", work = try folder()
        defer { try? FileManager.default.removeItem(at: work) }
        let original = Data("base".utf8), edited = Data("nuevo".utf8)
        inner.files[path] = original
        let base = RemoteFileVersion(md5: TransferDigest.hexOf(original), size: 4)
        #expect(!inner.renameDoesNotOverwrite)
        await #expect(throws: RemoteVersionConflict.unsupported) {
            _ = try await AtomicRemoteWriter.open(inner, path, verify: true, expected: base)
        }
        let local = work.appendingPathComponent("core-01.cfg")
        try edited.write(to: local)
        let file = RemoteEditFile(remotePath: path, local: local, remoteMD5: base.md5, remoteSize: base.size, syncedMD5: base.md5)
        let result = try await RemoteEdit.upload(inner, file)
        #expect(result == .conflict(.requiresOverwrite))
        #expect(inner.files == [path: original])
        let (copy, _) = try await RemoteEdit.uploadCopy(inner, file)
        #expect(copy != path && inner.files[path] == original && inner.files[copy] == edited)
        guard case .uploaded = try await RemoteEdit.upload(inner, file, force: true) else { Issue.record("no se ha sobrescrito"); return }
        #expect(inner.files[path] == edited)
    }

    @Test func conflictoSinRestauracionConservaVersionAjenaYNueva() async throws {
        let inner = SFTPLikeFileSystem(), path = "/d/core-01.cfg"
        inner.files[path] = Data("base".utf8)
        let fs = EdicionFallosFS(inner, path: path, failure: .restoreReject, noReplace: true)
        let base = RemoteFileVersion(md5: TransferDigest.hexOf(Data("base".utf8)), size: 4)
        let w = try await AtomicRemoteWriter.open(fs, path, verify: true, expected: base)
        try await w.write(Data("nuevo".utf8))
        inner.files[path] = Data("ajeno".utf8)
        var stuck: ReplaceStuckError?
        do { try await w.finish() } catch let error as ReplaceStuckError { stuck = error }
        let error = try #require(stuck)
        await w.abort()
        #expect(inner.files == [error.previous: Data("ajeno".utf8), error.new: Data("nuevo".utf8)])
    }

    @Test func desaparecidoDuranteElEnvioEsConflicto() async throws {
        let fs = SFTPLikeFileSystem(), path = "/d/core-01.cfg"
        fs.files[path] = Data("base".utf8)
        let base = RemoteFileVersion(md5: TransferDigest.hexOf(Data("base".utf8)), size: 4)
        let safe = EdicionFallosFS(fs, path: path, failure: .none, noReplace: true)
        let w = try await AtomicRemoteWriter.open(safe, path, verify: true, expected: base)
        try await w.write(Data("nuevo".utf8))
        fs.files[path] = nil
        await #expect(throws: RemoteVersionConflict.removed) { try await w.finish() }
        #expect(fs.files.isEmpty)
    }
}

/// Decorador: conserva las operaciones de SFTP reales y sólo cambia cuándo se recibe su respuesta.
final class EdicionFallosFS: RemoteFileSystem, @unchecked Sendable {
    enum Failure: Sendable, Equatable {
        case none, reject, publishMute, publishAppliedMute, backupAppliedMute, rollbackMute, rollbackAppliedMute, occupy
        case publishAppliedError, backupAppliedError, rollbackAppliedError, restoreReject
    }
    let inner: any RemoteFileSystem
    let path: String
    let failure: Failure
    let writeGate: EdicionPause?
    let renameDoesNotOverwrite: Bool
    private let lock = NSLock()
    private var moved = false
    private var mute = false
    var hanging: Bool { lock.withLock { mute } }
    var label: String { inner.label }

    init(_ inner: any RemoteFileSystem, path: String, failure: Failure, writeGate: EdicionPause? = nil, noReplace: Bool? = nil) {
        self.inner = inner; self.path = path; self.failure = failure; self.writeGate = writeGate
        renameDoesNotOverwrite = noReplace ?? inner.renameDoesNotOverwrite
    }

    private func silence() async throws {
        lock.withLock { mute = true }
        try await Task.sleep(for: .seconds(3600))
    }

    func rename(_ from: String, to: String) async throws {
        if from == path, to.hasSuffix(".old") {
            try await inner.rename(from, to: to)
            lock.withLock { moved = true }
            if failure == .backupAppliedMute { try await silence() }
            if failure == .backupAppliedError { throw RemoteError("conexión perdida después de apartar") }
            return
        }
        if from.hasSuffix(".old"), to == path {
            if failure == .restoreReject { throw RemoteError("restauración rechazada") }
            if failure == .rollbackMute { try await silence() }
            try await inner.rename(from, to: to)
            if failure == .rollbackAppliedMute { try await silence() }
            if failure == .rollbackAppliedError { throw RemoteError("conexión perdida después de restaurar") }
            return
        }
        if from.hasSuffix(".part"), to == path, lock.withLock({ moved }) {
            switch failure {
            case .reject, .rollbackMute, .rollbackAppliedMute, .rollbackAppliedError:
                throw RemoteError("rename rechazado")
            case .occupy:
                let w = try await inner.openWrite(path)
                try await w.write(Data("tercero".utf8))
                try await w.finish()
                throw RemoteError("destino ocupado")
            case .publishMute: try await silence()
            case .publishAppliedMute, .publishAppliedError:
                try await inner.rename(from, to: to)
                if failure == .publishAppliedError { throw RemoteError("conexión perdida después de publicar") }
                try await silence()
                return
            default: break
            }
        }
        try await inner.rename(from, to: to)
    }

    final class Writer: RemoteWriter, @unchecked Sendable {
        let inner: any RemoteWriter
        let gate: EdicionPause
        init(_ inner: any RemoteWriter, gate: EdicionPause) { self.inner = inner; self.gate = gate }
        func write(_ data: Data) async throws { try await inner.write(data) }
        func finish() async throws { try await inner.finish(); await gate.pause() }
        func abort() async { await inner.abort() }
    }
    func openWrite(_ path: String) async throws -> any RemoteWriter {
        let w = try await inner.openWrite(path)
        if let writeGate { return Writer(w, gate: writeGate) }
        return w
    }
    func home() async throws -> String { try await inner.home() }
    func list(_ path: String) async throws -> [RemoteEntry] { try await inner.list(path) }
    func makeDirectory(_ path: String) async throws { try await inner.makeDirectory(path) }
    func remove(_ path: String, directory: Bool) async throws { try await inner.remove(path, directory: directory) }
    func size(of path: String) async -> Int64? { await inner.size(of: path) }
    func openRead(_ path: String) async throws -> any RemoteReader { try await inner.openRead(path) }
    func close() async { await inner.close() }
    func permissions(of path: String) async -> UInt32? { await inner.permissions(of: path) }
    func lookup(_ path: String) async throws -> RemoteEntry.Kind? { try await inner.lookup(path) }
    func setPermissions(_ mode: UInt32, of path: String) async throws { try await inner.setPermissions(mode, of: path) }
}

/// Ignora deliberadamente la cancelación, como una descarga que ya terminó justo cuando se cerró la pestaña.
actor EdicionPause {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var waiting = false
    func pause() async {
        waiting = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@Suite @MainActor struct EdicionCicloDeVidaTests {
    private func file() throws -> RemoteEditFile {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-editor-\(UUID().uuidString)")
        AppPaths.ensure(dir)
        let local = dir.appendingPathComponent("core-01.cfg"), data = Data("base".utf8)
        try data.write(to: local)
        let md5 = TransferDigest.hexOf(data)
        return RemoteEditFile(remotePath: "/d/core-01.cfg", local: local, remoteMD5: md5, remoteSize: 4, syncedMD5: md5)
    }

    @Test func dobleAbrirReservaAntesDeDescargar() async throws {
        let f = try file(), gate = EdicionPause(), downloads = RemoteEditDownloads()
        defer { try? FileManager.default.removeItem(at: f.local.deletingLastPathComponent()) }
        var opened = 0, failures = 0
        let first = downloads.start(f.remotePath, download: { await gate.pause(); return f },
                                    opened: { _ in opened += 1 }, failed: { _ in failures += 1 })
        let second = downloads.start(f.remotePath, download: { Issue.record("descarga duplicada"); return f },
                                     opened: { _ in opened += 1 }, failed: { _ in failures += 1 })
        #expect(first && !second)
        await gate.release()
        for _ in 0..<400 where opened == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(opened == 1 && failures == 0)
        downloads.finish()
        #expect(FileManager.default.fileExists(atPath: f.local.path))
    }

    @Test func cerrarDescargaPendienteNoAbreNiDejaCopiaHuerfana() async throws {
        let f = try file(), gate = EdicionPause(), downloads = RemoteEditDownloads()
        defer { try? FileManager.default.removeItem(at: f.local.deletingLastPathComponent()) }
        var opened = 0, failures = 0
        let cancelled = Counter()
        downloads.start(f.remotePath, download: {
            await gate.pause()
            if Task.isCancelled { cancelled.add() }
            return f
        },
                        opened: { _ in opened += 1 }, failed: { _ in failures += 1 })
        for _ in 0..<400 {
            if await gate.waiting { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await gate.waiting)
        downloads.finish()
        await gate.release()
        for _ in 0..<400 where FileManager.default.fileExists(atPath: f.local.path) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(downloads.finished && opened == 0 && failures == 0 && cancelled.count == 1)
        #expect(!FileManager.default.fileExists(atPath: f.local.path))
        let restarted = downloads.start(f.remotePath, download: { f }, opened: { _ in opened += 1 }, failed: { _ in failures += 1 })
        #expect(!restarted)
    }

    @Test func falloDeDescargaPermiteReintentar() async throws {
        let f = try file(), downloads = RemoteEditDownloads()
        defer { try? FileManager.default.removeItem(at: f.local.deletingLastPathComponent()) }
        var failures = 0, opened = 0
        downloads.start(f.remotePath, download: { throw RemoteError("sin conexión") },
                        opened: { _ in opened += 1 }, failed: { _ in failures += 1 })
        for _ in 0..<400 where failures == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(failures == 1 && opened == 0)
        let retried = downloads.start(f.remotePath, download: { f }, opened: { _ in opened += 1 }, failed: { _ in failures += 1 })
        #expect(retried)
        for _ in 0..<400 where opened == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(opened == 1)
        downloads.finish()
    }

    @Test func copiaAbiertaSinCambiosAdmiteGuardadoAtomicoTrasCerrar() throws {
        let f = try file()
        defer { try? FileManager.default.removeItem(at: f.local.deletingLastPathComponent()) }
        #expect(try RemoteEdit.localDigest(f) == f.syncedMD5)
        #expect(!RemoteEdit.discard(f, openedInEditor: true))
        // (un editor guarda creando otro inode: no se puede borrar la carpeta entre el MD5 y este guardado)
        try Data("guardado después del cierre".utf8).write(to: f.local, options: .atomic)
        #expect(try Data(contentsOf: f.local) == Data("guardado después del cierre".utf8))
    }
}

/// La operación activa puede estar esperando otra cosa: cancelar un turno no debe esperar a que la libere ni ejecutar
/// después su cuerpo. La conexión no se abre (se prueba la cola, sin red ni credenciales).
@Suite(.serialized) struct FTPColaCancelableTests {
    private func queued(_ connection: FTPConnection, _ count: Int) async throws -> Bool {
        for _ in 0..<400 {
            if await connection.queuedOperations == count { return true }
            try await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    @Test func cancelarTurnoNoEsperaNiBloqueaAlSiguiente() async throws {
        let connection = FTPConnection(host: "192.0.2.1", port: 21), gate = EdicionPause()
        let active = Task { try await connection.exclusive { _ in await gate.pause(); return 1 } }
        defer { active.cancel(); Task { await gate.release() } }
        for _ in 0..<400 {
            if await gate.waiting { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let executed = Counter()
        let cancelled = Task { try await connection.exclusive { _ in executed.add(); return 2 } }
        let firstQueued = try await queued(connection, 1)
        #expect(firstQueued)
        let next = Task { try await connection.exclusive { _ in 3 } }
        let bothQueued = try await queued(connection, 2)
        #expect(bothQueued)
        defer { cancelled.cancel(); next.cancel() }
        // (si hay regresión, soltar el turno permite fallar la aserción sin colgar toda la suite)
        let watchdog = Task { try await Task.sleep(for: .seconds(3)); await gate.release() }
        defer { watchdog.cancel() }
        let start = ContinuousClock.now
        cancelled.cancel()
        switch await cancelled.result {
        case .success: Issue.record("se ha ejecutado una operación cancelada en cola")
        case .failure(let error): #expect(error is CancellationError)
        }
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(executed.count == 0)
        #expect(await connection.queuedOperations == 1)
        await gate.release()
        #expect(try await active.value == 1)
        #expect(try await next.value == 3)
        #expect(await connection.queuedOperations == 0)
    }

    @Test func timeoutDeTurnoRespetaElTope() async throws {
        let connection = FTPConnection(host: "192.0.2.1", port: 21), gate = EdicionPause(), executed = Counter()
        let active = Task { try await connection.exclusive { _ in await gate.pause(); return 1 } }
        defer { active.cancel(); Task { await gate.release() } }
        for _ in 0..<400 {
            if await gate.waiting { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let start = ContinuousClock.now
        let waiting = Task {
            try await RemoteOps.withTimeout(1) {
                try await connection.exclusive { _ in executed.add(); return 2 }
            }
        }
        let isQueued = try await queued(connection, 1)
        #expect(isQueued)
        defer { waiting.cancel() }
        let watchdog = Task { try await Task.sleep(for: .seconds(3)); await gate.release() }
        defer { watchdog.cancel() }
        switch await waiting.result {
        case .success: Issue.record("el turno ha ignorado su timeout")
        case .failure(let error): #expect(error is RemoteTimeout)
        }
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(executed.count == 0)
        #expect(await connection.queuedOperations == 0)
        await gate.release()
        #expect(try await active.value == 1)
        let reused = try await connection.exclusive { _ in 3 }
        #expect(reused == 3)
    }
}
