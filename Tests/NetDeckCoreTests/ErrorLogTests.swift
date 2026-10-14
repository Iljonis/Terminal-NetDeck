import Foundation
import Testing
@testable import NetDeckCore

@Suite struct ErrorLogTests {
    @Test func formatoDeLinea() {
        let d = ISO8601DateFormatter().date(from: "2026-10-14T10:00:00Z")!
        #expect(ErrorLog.line(.error, "sesiones", "no se han podido guardar", date: d)
                == "2026-10-14T10:00:00Z [ERROR] sesiones: no se han podido guardar\n")
        #expect(ErrorLog.line(.warning, "actualizaciones", "sin red\ny otra", date: d)
                == "2026-10-14T10:00:00Z [WARNING] actualizaciones: sin red y otra\n")
    }

    @Test func anadeYRotaConUnaCopia() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("errorlog-\(UUID().uuidString)/logs")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let f = dir.appendingPathComponent("error.log")
        ErrorLog.append("uno\n", to: f, limit: 10)
        ErrorLog.append("dos\n", to: f, limit: 10)
        #expect(try String(contentsOf: f, encoding: .utf8) == "uno\ndos\n")
        let perms = try FileManager.default.attributesOfItem(atPath: f.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        #expect(try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int == 0o700)
        ErrorLog.append("tres\n", to: f, limit: 5)                   // (pasa del límite: rota)
        let old = URL(fileURLWithPath: f.path + ".1")
        #expect(try String(contentsOf: old, encoding: .utf8) == "uno\ndos\n")
        #expect(try String(contentsOf: f, encoding: .utf8) == "tres\n")
        ErrorLog.append("cuatro\n", to: f, limit: 5)                 // (sólo una copia: la .1 se sustituye)
        #expect(try String(contentsOf: old, encoding: .utf8) == "tres\n")
        #expect(!FileManager.default.fileExists(atPath: f.path + ".2"))
    }

    @Test func avisosImportantes() {
        #expect(StatusNotice.isImportant("✗ error en la línea 3"))
        #expect(StatusNotice.isImportant("🔑 «AD» no ha valido"))
        #expect(StatusNotice.isImportant("⎋ Cancelado"))
        #expect(StatusNotice.isImportant("⬆ Estás al día (1.0)"))
        #expect(!StatusNotice.isImportant("Sesiones guardadas (3)"))
        #expect(!StatusNotice.isImportant("▶ show version"))
    }
}
