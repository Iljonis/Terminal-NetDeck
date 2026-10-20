import Foundation
import Testing
@testable import NetDeckCore

/// Sustituir en el destino sólo si consta que no hay nada o que hay un archivo normal: un LIST que falla, un tipo que
/// no se sabe o un SIZE que contesta sin que el listado lo enseñe paran la copia antes de escribir nada.
@Suite struct SustituirSinDudasTests {
    func connect(_ s: MiniFTPServer) async throws -> FTPFileSystem {
        try await FTPFileSystem.connect(label: "prueba", host: "127.0.0.1", port: Int(s.port), user: "tu.usuario", password: "prueba")
    }

    func wrote(_ s: MiniFTPServer) -> Bool {
        s.commands.contains { ["STOR", "RNFR", "RNTO", "DELE"].contains(String($0.prefix(4))) }
    }

    @Test func listFallidoNoEsAusencia() async throws {
        let server = try MiniFTPServer(listing: [])
        server.listFails = true
        defer { server.stop() }
        let fs = try await connect(server)
        await #expect(throws: (any Error).self) { _ = try await AtomicRemoteWriter.open(fs, "/d/a.cfg", verify: false) }
        await fs.close()
        #expect(!wrote(server))
    }

    /// «.a.cfg» no sale en el LIST (los ocultos), pero SIZE contesta: hay algo y no se sabe qué.
    @Test func sizeSinListadoNoEsArchivo() async throws {
        let server = try MiniFTPServer(listing: ["-rw-r--r--    1 u  g   5 Jan  1 12:00 otro.cfg"])
        server.sizes = ["/d/.a.cfg"]
        defer { server.stop() }
        let fs = try await connect(server)
        await #expect(throws: (any Error).self) { _ = try await AtomicRemoteWriter.open(fs, "/d/.a.cfg", verify: false) }
        #expect(!wrote(server))
        // (y lo que el listado enseña como archivo normal, o lo que de verdad no está, sí)
        #expect(try await AtomicRemoteWriter.existingFile(fs, "/d/otro.cfg") == .file)
        #expect(try await AtomicRemoteWriter.existingFile(fs, "/d/nuevo.cfg") == nil)
        await fs.close()
    }

    /// SFTP: un lstat que no contesta «no existe» (permiso denegado, respuesta rara) no es ausencia.
    @Test func lstatDudosoNoEsAusencia() async throws {
        let fs = SFTPLikeFileSystem()
        fs.lookupError = RemoteError("Permiso denegado")
        await #expect(throws: RemoteError.self) { _ = try await AtomicRemoteWriter.open(fs, "/d/a.cfg", verify: false) }
        #expect(fs.files.isEmpty)                                   // (ni el temporal)
    }

    /// Contra el sftp-server de verdad: «no such file» es ausencia; lo que hay se ve con su tipo.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: SFTPServerTests.server)))
    func sftpDistingueAusenciaDeError() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-sftp-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("x".utf8).write(to: dir.appendingPathComponent("a.cfg"))
        let fs = try await SFTPFileSystem.connect(label: "prueba", executable: SFTPServerTests.server, arguments: [], environment: [:])
        defer { Task { await fs.close() } }
        #expect(try await fs.lookup(dir.path + "/a.cfg") == .file)
        #expect(try await fs.lookup(dir.path + "/nada.cfg") == nil)
        #expect(try await fs.lookup(dir.path) == .directory)
    }
}

/// Cancelar con un servidor que ya no contesta (a CLOSE ni a borrar): acaba en el tope, no se queda esperando, y un
/// origen colgado no deja sin abortar el destino. (Lo que se protege es una espera sin fin —el servidor de mentira
/// tarda una hora—: con un tope de 1 s, acabar en menos de 30 lo demuestra también en una máquina lenta.)
@Suite(.serialized) struct CancelarSinColgarseTests {
    /// Un lector que da datos y luego falla; su CLOSE no contesta nunca (sólo acaba si se cancela).
    final class MuteReader: RemoteReader, @unchecked Sendable {
        func read() async throws -> Data? { throw RemoteError("se ha perdido la conexión") }
        func close() async { try? await Task.sleep(for: .seconds(3600)) }
    }

    /// Un servidor cuyo CLOSE de escritura y cuyo borrar no contestan; apunta lo que se intenta.
    final class MuteFileSystem: RemoteFileSystem, @unchecked Sendable {
        let label = "mudo"
        let removes = Counter()
        let hang: Bool
        init(hang: Bool) { self.hang = hang }
        final class W: RemoteWriter, @unchecked Sendable {
            let hang: Bool
            init(hang: Bool) { self.hang = hang }
            func write(_ data: Data) async throws {}
            func finish() async throws {}
            func abort() async { if hang { try? await Task.sleep(for: .seconds(3600)) } }
        }
        func home() async throws -> String { "/" }
        func list(_ path: String) async throws -> [RemoteEntry] { [] }
        func makeDirectory(_ path: String) async throws {}
        func remove(_ path: String, directory: Bool) async throws {
            removes.add()
            if hang { try await Task.sleep(for: .seconds(3600)) }
        }
        func rename(_ from: String, to: String) async throws {}
        func size(of path: String) async -> Int64? { nil }
        func lookup(_ path: String) async throws -> RemoteEntry.Kind? { nil }
        func openRead(_ path: String) async throws -> any RemoteReader { MuteReader() }
        func openWrite(_ path: String) async throws -> any RemoteWriter { W(hang: hang) }
        func close() async {}
    }

    @Test func origenMudoNoBloqueaElDestino() async throws {
        let old = AtomicRemoteWriter.cleanupSeconds
        AtomicRemoteWriter.cleanupSeconds = 1
        defer { AtomicRemoteWriter.cleanupSeconds = old }
        let fs = MuteFileSystem(hang: false)
        let w = try await AtomicRemoteWriter.open(fs, "/d/a.cfg", verify: false)
        let t0 = ContinuousClock.now
        await #expect(throws: (any Error).self) { try await Transfer.copy(from: MuteReader(), to: w) }
        #expect(ContinuousClock.now - t0 < .seconds(30))
        #expect(fs.removes.count == 1)                          // (el temporal del destino, borrado igualmente)
    }

    @Test func destinoMudoAcabaEnElTope() async throws {
        let old = AtomicRemoteWriter.cleanupSeconds
        AtomicRemoteWriter.cleanupSeconds = 1
        defer { AtomicRemoteWriter.cleanupSeconds = old }
        let fs = MuteFileSystem(hang: true)
        let w = try await AtomicRemoteWriter.open(fs, "/d/a.cfg", verify: false)
        try await w.write(Data("x".utf8))
        let t0 = ContinuousClock.now
        await w.abort()
        #expect(ContinuousClock.now - t0 < .seconds(30))
        // (cancelar la copia entera tampoco se queda esperando)
        let w2 = try await AtomicRemoteWriter.open(fs, "/d/b.cfg", verify: false)
        let copy = Task { try await Transfer.copy(from: EndlessReader(), to: w2) }
        try await Task.sleep(for: .milliseconds(100))
        let t1 = ContinuousClock.now
        copy.cancel()
        _ = await copy.result
        #expect(ContinuousClock.now - t1 < .seconds(30))
    }
}

/// El registro se libera al cerrarlo aunque su aviso de fallo lo tenga a él (como en la app), y los fallos de antes de
/// cerrar siguen llegando.
@Suite struct RegistroSinCicloTests {
    @Test func seLiberaAlCerrar() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let told = Counter()
        weak var gone: SessionLogger?
        do {
            let log = try SessionLogger(directory: dir, name: "core-01", host: "192.0.2.1")
            log.onFailure = { _ in _ = log; told.add() }            // (lo retiene, como el aviso de la pestaña)
            log.writeData = { _, _ in throw POSIXError(.ENOSPC) }
            log.feed(Array("uno\n".utf8)[...])
            log.close()
            gone = log
        }
        #expect(told.count == 1)
        #expect(gone == nil)
    }
}

/// Editor de sesiones: A → editar B → Guardar → volver a A → Conectar antes de que acabe de guardar. Ni conectar, ni
/// cerrar, ni volver a guardar hasta que termine; después, sí.
@Suite @MainActor struct EditorMientrasGuardaTests {
    @Test func conectarAntesDeTerminarDeGuardar() async {
        let gate = EditorSaveGate()
        var selected = "A"
        selected = "B"                                              // (editar B)
        #expect(gate.begin())                                       // Guardar
        let (stream, release) = AsyncStream.makeStream(of: Void.self)
        let save = Task { @MainActor in
            for await _ in stream { break }                         // (el guardado tarda: espera a que lo soltemos)
            gate.end()
        }
        selected = "A"                                              // volver a A
        #expect(selected == "A")
        #expect(gate.blocks(.connect) != nil)                       // Conectar: no
        #expect(gate.blocks(.close) != nil && gate.blocks(.finish) != nil && gate.blocks(.save) != nil)
        #expect(!gate.begin())                                      // (ni un segundo guardado encima)
        release.yield()
        await save.value
        #expect(gate.blocks(.connect) == nil && gate.blocks(.close) == nil && !gate.saving)
    }
}
