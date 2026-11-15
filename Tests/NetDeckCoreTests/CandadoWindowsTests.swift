#if os(Windows)
import Foundation
import Testing
@testable import NetDeckCore

/// El candado entre procesos de las marcas en Windows (`FileLock`, con LockFileEx). El candado es del HANDLE, así que
/// dos almacenes sobre la misma carpeta se comportan como la app y el askpass: el segundo espera al primero.
@Suite struct CandadoWindowsTests {
    @Test func dosAlmacenesDeLaMismaCarpetaSeExcluyen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let uno = DirectoryLedgerStorage(dir), otro = DirectoryLedgerStorage(dir)
        let dentro = DispatchSemaphore(value: 0)
        let apuntes = Apuntes()

        let primero = Thread {
            uno.locked {
                dentro.signal()
                Thread.sleep(forTimeInterval: 0.4)
                apuntes.añadir("sale el primero")
            }
        }
        primero.start()
        dentro.wait()
        otro.locked { apuntes.añadir("entra el segundo") }
        #expect(apuntes.todos == ["sale el primero", "entra el segundo"])
    }

    @Test func seSueltaYSePuedeVolverACoger() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ruta = dir.appendingPathComponent(".candado").path
        for _ in 0..<3 {
            let candado = try #require(FileLock.acquire(ruta))
            FileLock.release(candado)
        }
        // Anidado en el mismo almacén no se espera a sí mismo.
        let almacen = DirectoryLedgerStorage(dir)
        #expect(almacen.locked { almacen.locked { 7 } } == 7)
    }

    @Test func sinCarpetaNoHayCandado() {
        let ruta = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent(".candado").path
        #expect(FileLock.acquire(ruta) == nil)
    }
}

private final class Apuntes: @unchecked Sendable {
    private let lock = NSLock()
    private var lista: [String] = []
    func añadir(_ s: String) { lock.lock(); lista.append(s); lock.unlock() }
    var todos: [String] { lock.lock(); defer { lock.unlock() }; return lista }
}
#endif