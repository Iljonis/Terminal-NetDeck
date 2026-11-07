import Foundation
import Testing
@testable import NetDeckCore

/// Con `NonisolatedNonsendingByDefault` (Swift 6.2), una función async sin actor corre en el de quien la llama: el MD5
/// y la edición remota llevan `@concurrent` para que, llamados desde la interfaz, no lean ni calculen en el principal.
@MainActor @Suite struct FueraDelPrincipalTests {
    /// Apunta si alguna operación se ha hecho en el hilo principal.
    final class Testigo: @unchecked Sendable {
        private let lock = NSLock()
        private var principal = false
        func mira() { if pthread_main_np() != 0 { lock.withLock { principal = true } } }
        var enPrincipal: Bool { lock.withLock { principal } }
    }

    final class Lector: RemoteReader, @unchecked Sendable {
        let testigo: Testigo
        private var trozos: [Data]
        init(_ trozos: [Data], testigo: Testigo) { self.trozos = trozos; self.testigo = testigo }
        func read() async throws -> Data? {
            testigo.mira()
            return trozos.isEmpty ? nil : trozos.removeFirst()
        }
        func close() async {}
    }

    /// Un servidor con un único archivo de texto, que apunta en qué hilo le preguntan.
    final class Servidor: RemoteFileSystem, @unchecked Sendable {
        let testigo = Testigo()
        var label: String { "SFTP tu.usuario@core-01" }
        func home() async throws -> String { "/" }
        func list(_ path: String) async throws -> [RemoteEntry] { testigo.mira(); return [] }
        func makeDirectory(_ path: String) async throws {}
        func remove(_ path: String, directory: Bool) async throws {}
        func rename(_ from: String, to: String) async throws {}
        func lookup(_ path: String) async throws -> RemoteEntry.Kind? { testigo.mira(); return .file }
        func size(of path: String) async -> Int64? { testigo.mira(); return 12 }
        func openRead(_ path: String) async throws -> any RemoteReader {
            testigo.mira()
            return Lector([Data("hostname r1\n".utf8)], testigo: testigo)
        }
        func openWrite(_ path: String) async throws -> any RemoteWriter { throw RemoteError("sólo lectura") }
        func close() async {}
    }

    @Test func elMD5SeCalculaFueraDelPrincipal() async throws {
        let testigo = Testigo()
        let md5 = try await TransferDigest.of(Lector([Data("hostname r1\n".utf8)], testigo: testigo))
        #expect(md5 == TransferDigest.hexOf(Data("hostname r1\n".utf8)))
        #expect(!testigo.enPrincipal)
    }

    @Test func laEdicionRemotaBajaFueraDelPrincipal() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-hilos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fs = Servidor()
        let file = try await RemoteEdit.download(fs, "/etc/router.conf", into: dir)
        #expect(try String(contentsOf: file.local, encoding: .utf8) == "hostname r1\n")
        #expect(!fs.testigo.enPrincipal)
    }
}
