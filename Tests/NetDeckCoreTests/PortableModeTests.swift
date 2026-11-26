import Foundation
import Testing
@testable import NetDeckCore

@Suite struct PortableModeTests {
    @Test func conMarcadorLosDatosVanAlLadoDelEjecutable() {
        let exe = URL(fileURLWithPath: "/apps/NetDeck", isDirectory: true)
        let datos = PortableMode.dataFolder(executableDirectory: exe, fileExists: { $0 == "/apps/NetDeck/NetDeck.portable" })
        #expect(datos?.path == "/apps/NetDeck/datos")
    }

    @Test func sinMarcadorEsUnaInstalacionNormal() {
        let exe = URL(fileURLWithPath: "/Program Files/Terminal NetDeck", isDirectory: true)
        #expect(PortableMode.dataFolder(executableDirectory: exe, fileExists: { _ in false }) == nil)
    }

    @Test func soloValeElMarcadorJuntoAlEjecutable() {
        let exe = URL(fileURLWithPath: "/apps/NetDeck", isDirectory: true)
        // (uno en la carpeta de arriba o dentro de «datos» no activa el modo portable)
        let otros: Set<String> = ["/apps/NetDeck.portable", "/apps/NetDeck/datos/NetDeck.portable"]
        #expect(PortableMode.dataFolder(executableDirectory: exe, fileExists: { otros.contains($0) }) == nil)
    }

    @Test func conUnMarcadorRealEnDisco() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("portable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raiz) }
        #expect(PortableMode.dataFolder(executableDirectory: raiz) == nil)
        try Data().write(to: raiz.appendingPathComponent(PortableMode.markerName))
        #expect(PortableMode.dataFolder(executableDirectory: raiz)?.lastPathComponent == PortableMode.dataFolderName)
    }
}
