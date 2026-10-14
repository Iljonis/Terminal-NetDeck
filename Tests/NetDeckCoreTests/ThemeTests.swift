import Foundation
import Testing
@testable import NetDeckCore

@Suite struct ThemeTests {
    static let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Temas")

    @Test func todoElCatalogoSeLee() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.catalog, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "tema" }
        #expect(files.count >= 30)
        for f in files { _ = try Theme(contentsOf: f) }
    }

    /// Contraste WCAG entre dos colores (1…21).
    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (l1, l2) = (a.opaque.luminance, b.opaque.luminance)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Todo el catálogo se lee bien: texto ≥ 4,5:1, apagado ≥ 3:1, texto de la pestaña activa ≥ 4,5:1 y los colores
    /// ANSI de primer plano (1–6 y 9–14) ≥ 3:1 sobre el fondo (el de cristal, como si fuera opaco).
    @Test func contrasteDelCatalogo() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.catalog, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "tema" }
        for f in files {
            let t = try Theme(contentsOf: f)
            let bg = t.background.opaque
            #expect(Self.contrast(t.text, bg) >= 4.5, "\(t.id): texto")
            #expect(Self.contrast(t.dim, bg) >= 3, "\(t.id): apagado")
            #expect(Self.contrast(t.onTab, t.tab) >= 4.5, "\(t.id): pestaña activa")
            for i in Array(1...6) + Array(9...14) {
                #expect(Self.contrast(t.ansi[i], bg) >= 3, "\(t.id): ANSI \(i)")
            }
        }
        #expect(Self.contrast(Theme.builtIn.text, Theme.builtIn.background) >= 4.5)
    }

    @Test func formatoDeNetDeck() throws {
        let t = try Theme(id: "x", text: """
            # Prueba — Una de prueba.
            nombre    = Prueba
            grupo     = Cyberpunk
            fuentes   = Kode Mono, Space Mono      # la 1ª es la oficial
            tamaño    = 15
            fondo = #000000
            texto = #ffffff
            barra = #111111
            panel = #222222
            pestaña = #ff0000
            sobre_pestaña = #000000
            acento = #00ffff                  # interfaces
            acento2 = #ff00ff
            bien = #00ff00
            mal = #ff0000
            especial = #8800ff
            apagado = #666666
            reloj = %H:%M 東京
            """)
        #expect(t.name == "Prueba")
        #expect(t.summary == "Una de prueba.")
        #expect(t.fonts == ["Kode Mono", "Space Mono"])
        #expect(t.size == 15)
        #expect(t.accent == RGB(hex: "#00ffff"))
        #expect(t.ansi.count == 16)
        #expect(t.ansi[1] == t.bad && t.ansi[15] == t.text)
        #expect(t.clockText().hasSuffix("東京"))
    }

    @Test func colorMalEsUnError() {
        #expect(throws: Theme.ParseError.badColor("fondo")) { try Theme(id: "x", text: "fondo = rojo") }
    }

    @Test func todosDisponiblesSinInstalarEImportados() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = ThemeLibrary(appDirectory: Self.catalog, importDirectory: dir, netdeckDirectory: nil)
        let all = lib.all()
        #expect(all.count >= 31)
        #expect(lib.theme(id: "neo-tokyo") != nil)
        #expect(all.first { $0.theme.id == Theme.builtIn.id }?.source == .builtIn)
        // uno propio, importado de un archivo: se puede quitar
        let file = dir.appendingPathExtension("mio.tema")
        try Self.sample.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let t = try lib.importTheme(file: file)
        #expect(lib.all().first { $0.theme.id == t.id }?.source == .imported)
        try lib.remove(t.id)
        #expect(lib.theme(id: t.id) == nil)
    }

    static let sample = """
        nombre = Mío
        fondo = #000000
        texto = #ffffff
        barra = #111111
        panel = #222222
        pestaña = #ff0000
        sobre_pestaña = #000000
        acento = #00ffff
        acento2 = #ff00ff
        bien = #00ff00
        mal = #ff0000
        especial = #8800ff
        apagado = #666666
        """

    @Test func rotulo() {
        let g = Banner.grid("NE")
        #expect(g.count == 5)
        #expect(g[0].count == 11)
        #expect(Banner.rows("I")[0] == "██████████")
    }
}
