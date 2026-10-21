import Foundation
import Testing
@testable import NetDeckCore

/// La publicación, no un lookup anterior, decide si el destino sigue libre.
@Suite(.serialized) struct EdicionCopiaExclusivaTests {
    private static let server = "/usr/libexec/sftp-server"

    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-copia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.resolvingSymlinksInPath()
    }

    private func connect() async throws -> SFTPFileSystem {
        try await SFTPFileSystem.connect(label: "prueba", executable: Self.server, arguments: [], environment: [:])
    }

    /// Dos subidas preparadas para el mismo nombre; la segunda publica cuando la primera ya lo ha ocupado.
    /// Con el reemplazo habitual se perdía la primera copia, incluso con rename no sobrescribible de SFTP.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func colisionAlPublicarNuncaApartaNiBorraLaCopiaAjena() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fs = try await connect()
        defer { Task { await fs.close() } }
        let path = dir.appendingPathComponent("core-01.local.cfg")
        let a = try await AtomicRemoteWriter.open(fs, path.path, verify: true, createOnly: true)
        let b = try await AtomicRemoteWriter.open(fs, path.path, verify: true, createOnly: true)
        try await a.write(Data("copia primera".utf8))
        try await b.write(Data("copia segunda".utf8))
        try await a.finish()
        await #expect(throws: (any Error).self) { try await b.finish() }
        await b.abort()
        #expect(try String(contentsOf: path, encoding: .utf8) == "copia primera")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["core-01.local.cfg"])
    }

    /// Dos editores del mismo archivo y el mismo segundo conservan ambas versiones y el original.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func dosCopiasSimultaneasDelMismoSegundoSeConservan() async throws {
        let dir = try folder(), local = try folder()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: local) }
        let fs = try await connect()
        defer { Task { await fs.close() } }
        let target = dir.appendingPathComponent("core-01.cfg")
        try Data("original".utf8).write(to: target)
        let one = local.appendingPathComponent("uno.cfg"), two = local.appendingPathComponent("dos.cfg")
        try Data("primero".utf8).write(to: one)
        try Data("segundo".utf8).write(to: two)
        let a = RemoteEditFile(remotePath: target.path, local: one, remoteMD5: "base", remoteSize: 8, syncedMD5: "base")
        let b = RemoteEditFile(remotePath: target.path, local: two, remoteMD5: "base", remoteSize: 8, syncedMD5: "base")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        async let first = RemoteEdit.uploadCopy(fs, a, date: date)
        async let second = RemoteEdit.uploadCopy(fs, b, date: date)
        let (x, y) = try await (first, second)
        #expect(x.path != y.path)
        #expect(try String(contentsOfFile: x.path, encoding: .utf8) == "primero")
        #expect(try String(contentsOfFile: y.path, encoding: .utf8) == "segundo")
        #expect(try String(contentsOf: target, encoding: .utf8) == "original")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 3)
    }

    @Test func sinGarantiaNoSeEscribeNiTemporal() async throws {
        let fs = MemoryFileSystem()
        fs.files["/d/copia.cfg"] = Data("ajeno".utf8)
        await #expect(throws: RemoteVersionConflict.unsupported) {
            _ = try await AtomicRemoteWriter.open(fs, "/d/copia.cfg", verify: true, createOnly: true)
        }
        #expect(fs.files == ["/d/copia.cfg": Data("ajeno".utf8)])
    }

    /// Tras un corte no hace falta otro guardado del editor: misma copia y misma fecha, con una conexión nueva.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: server)))
    func reintentoTrasReconectarSinOtroGuardadoLocal() async throws {
        let dir = try folder(), local = try folder()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: local) }
        let target = dir.appendingPathComponent("core-01.cfg")
        try Data("original".utf8).write(to: target)
        let fs = try await connect()
        defer { Task { await fs.close() } }
        let file = try await RemoteEdit.download(fs, target.path, into: local)
        try Data("editado".utf8).write(to: file.local)
        let stamp = try FileManager.default.attributesOfItem(atPath: file.local.path)[.modificationDate] as? Date
        let broken = BreakingFileSystem(fs, mode: .disconnect)
        await #expect(throws: (any Error).self) { _ = try await RemoteEdit.upload(broken, file) }
        #expect(broken.writing)
        #expect(try String(contentsOf: target, encoding: .utf8) == "original")
        var retry = RemoteEditRetry()
        let now = ContinuousClock.now
        retry.failed(.upload, now: now)
        #expect(!retry.ready(connected: false, now: now.advanced(by: .seconds(60))))
        let reconnected = try await connect()
        defer { Task { await reconnected.close() } }
        #expect(retry.ready(connected: true, now: now.advanced(by: .seconds(2))))
        guard case .uploaded = try await RemoteEdit.upload(reconnected, file) else {
            Issue.record("El guardado pendiente no se ha subido al reconectar"); return
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "editado")
        #expect(try FileManager.default.attributesOfItem(atPath: file.local.path)[.modificationDate] as? Date == stamp)
    }
}

@Suite struct EdicionReintentoTests {
    @Test func pendienteSinConexionEsperaYSinFalloNoReintenta() {
        let now = ContinuousClock.now
        var retry = RemoteEditRetry()
        #expect(!retry.ready(connected: true, now: now))
        retry.failed(.upload, now: now)
        #expect(!retry.ready(connected: false, now: now.advanced(by: .seconds(100))))
        #expect(!retry.ready(connected: true, now: now.advanced(by: .seconds(1))))
        #expect(retry.ready(connected: true, now: now.advanced(by: .seconds(2))))
    }

    @Test func fallosRepetidosEsperanCadaVezMasHastaUnMinuto() {
        var retry = RemoteEditRetry()
        let now = ContinuousClock.now
        for seconds in [2, 4, 8, 16, 32, 60, 60] {
            retry.failed(.copy, now: now)
            #expect(retry.operation == .copy)                      // (no convierte la copia en sobrescritura)
            #expect(!retry.ready(connected: true, now: now.advanced(by: .seconds(seconds - 1))))
            #expect(retry.ready(connected: true, now: now.advanced(by: .seconds(seconds))))
        }
    }

    @Test func exitoOCancelacionRetiranElPendienteYReinicianLaEspera() {
        var retry = RemoteEditRetry()
        let now = ContinuousClock.now
        retry.failed(.copy, now: now)
        retry.failed(.copy, now: now)
        retry.reset()
        #expect(retry.operation == nil)
        #expect(!retry.ready(connected: true, now: now.advanced(by: .seconds(100))))
        retry.failed(.upload, now: now)
        #expect(retry.operation == .upload)
        #expect(retry.ready(connected: true, now: now.advanced(by: .seconds(2))))
    }
}
