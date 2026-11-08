import Foundation
import Testing
@testable import NetDeckCore

@Suite struct ThemeTests {
    static let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Temas")

    @Test func todoElCatalogoSeLee() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.catalog, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "tema" }
        #expect(files.count >= 85)
        for f in files { _ = try Theme(contentsOf: f) }
    }

    /// De serie (1.0.0) va Liquid Glass, con su versión clara para el modo automático: los dos vienen en el catálogo y
    /// son de estilo cristal. Los de neón que sugiere el asistente empiezan por el de siempre y son todos de neón.
    @Test func liquidGlassDeSerieYNeonSugeridos() throws {
        let none = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let lib = ThemeLibrary(appDirectory: Self.catalog, importDirectory: none, netdeckDirectory: nil)
        let all = lib.all().map(\.theme)
        let dark = try #require(all.first { $0.id == Theme.defaultID })
        let light = try #require(all.first { $0.id == Theme.defaultLightID })
        #expect(dark.style == .glass && light.style == .glass)
        let neon = Theme.neonSuggestions(in: all)
        #expect(neon.first?.id == Theme.builtIn.id)
        #expect(neon.count >= 4 && neon.allSatisfy { $0.style == .neon && $0.group == "Cyberpunk" })
        #expect(!neon.contains { $0.id == Theme.defaultID })
    }

    /// Al pasar de la 0.9 a la 1.0.0, quien nunca eligió tema sigue con los de entonces; quien empieza, Liquid Glass.
    @Test func actualizarNoCambiaElTemaDeQuienYaLaUsaba() throws {
        let antes = Theme.startingIDs(previousUser: true), nuevo = Theme.startingIDs(previousUser: false)
        #expect(antes.fixed == Theme.builtIn.id && antes.dark == Theme.builtIn.id && antes.light == "papel")
        #expect(nuevo.fixed == Theme.defaultID && nuevo.dark == Theme.defaultID && nuevo.light == Theme.defaultLightID)
        let ids = Set(ThemeLibrary(appDirectory: Self.catalog, importDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString), netdeckDirectory: nil).all().map(\.theme.id))
        #expect(ids.contains("papel"))
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

    /// El icono de un botón activo (túneles, vista dividida…) va con el fondo opaco sobre el acento: con el fondo tal
    /// cual, en los de cristal se transparentaba y quedaba en 2,4:1. Al menos 3:1 en todo el catálogo, también sólido.
    @Test func iconoActivoSobreElAcento() throws {
        for t in try Self.catalogThemes() {
            for s in [t, t.solid] {
                let bg = s.background.opaque
                #expect(Self.contrast(bg, s.accent.over(s.bar.over(bg))) >= 3, "\(t.id): icono activo")
            }
        }
    }

    static func catalogThemes() throws -> [Theme] {
        try FileManager.default.contentsOfDirectory(at: catalog, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "tema" }.map(Theme.init(contentsOf:))
    }

    /// Los de cristal y mica, con «Reducir transparencia» o «Aumentar contraste»: todo opaco (ventana, desenfoque y
    /// fondo del terminal) y legible: texto ≥ 4,5:1 sobre el fondo, la barra y el panel; apagado ≥ 3:1; pestaña ≥ 4,5:1.
    @Test func temasConAlfaSinTransparencia() throws {
        let translucent = try Self.catalogThemes().filter(\.isTranslucent)
        #expect(Set(translucent.map(\.id)).isSuperset(of: ["liquid-glass", "liquid-glass-claro", "windows-11", "windows-11-claro"]))
        for t in translucent {
            let s = t.solid
            #expect(!s.isTranslucent && s.material == nil, "\(t.id)")
            #expect(s.layer == s.background, "\(t.id): capas")
            for c in [s.background, s.text, s.bar, s.panel, s.tab, s.onTab, s.accent, s.dim] { #expect(c.a == 1, "\(t.id)") }
            for (fondo, nombre) in [(s.background, "fondo"), (s.bar, "barra"), (s.panel, "panel")] {
                #expect(Self.contrast(s.text, fondo) >= 4.5, "\(t.id): texto sobre \(nombre)")
                #expect(Self.contrast(s.dim, fondo) >= 3, "\(t.id): apagado sobre \(nombre)")
            }
            #expect(Self.contrast(s.onTab, s.tab) >= 4.5, "\(t.id): pestaña activa")
            #expect(Self.contrast(s.accent, s.bar) >= 3, "\(t.id): acento sobre la barra")
            // (la barra opaca, ya mezclada con el fondo: no el color de la barra tal cual)
            #expect(s.bar == t.bar.over(t.background.opaque))
        }
        let opaco = Theme.builtIn
        #expect(opaco.solid == opaco)
    }

    /// «f.orange» y los avisos: un naranja de verdad en todo el catálogo (antes, gris malva en 11 temas) y legible.
    @Test func naranjaDeVerdad() throws {
        for t in try Self.catalogThemes() {
            let w = t.warning
            #expect(w.tono.tono == .naranja, "\(t.id): \(w) es \(w.tono.tono)")
            #expect(Self.contrast(w, t.background.opaque) >= 4.5, "\(t.id): naranja \(w)")
            #expect(Self.contrast(w, t.bad) >= 1.15 || w.tono.tono != t.bad.tono.tono, "\(t.id): se confunde con «mal»")
        }
        // (el que ya era naranja y se lee no cambia)
        let ambar = try Self.catalogThemes().first { $0.id == "accesible" }!
        #expect(ambar.warning == ambar.bad.mix(ambar.accent, 0.5))
        #expect(RGB(hue: 30, saturation: 1, lightness: 0.5).description == "#ff8000")
        #expect(RGB(hue: 210, saturation: 1, lightness: 0.5).description == "#0080ff")
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

    /// «brillo = sí» y «tinte = #rrggbbaa» (los Neon Glass) se leen; sin ellos, ni halo ni tinte. Con «Reducir
    /// transparencia» (`solid`) el tinte se quita, como el resto del cristal.
    @Test func brilloYTinteSeLeen() throws {
        let t = try Theme(id: "x", text: Self.sample + "\nestilo = cristal\nbrillo    = sí      # halo\ntinte = #ff2e8826\n")
        #expect(t.glowing && t.style == .glass)
        #expect(t.glassTint == RGB(255, 46, 136, Double(0x26) / 255))
        let sinNada = try Theme(id: "y", text: Self.sample + "\nbrillo = no\ntinte = rosa\n")
        #expect(!sinNada.glowing && sinNada.glassTint == nil)
        var cristal = t
        cristal.background = cristal.background.alpha(0.8)
        #expect(cristal.solid.glassTint == nil && cristal.solid.glowing)
        let neonGlass = try Self.catalogThemes().filter { $0.group == "Neon Glass" }
        #expect(neonGlass.count == 10)
        #expect(neonGlass.allSatisfy { $0.style == .glass && $0.glowing && $0.glassTint != nil })
    }

    /// Cada tema del catálogo va en un grupo conocido (con su inglés) y los de Naturaleza, en parejas oscuro/claro
    /// seguidas para el modo automático.
    @Test func gruposYParejasDeNaturaleza() throws {
        let all = try Self.catalogThemes()
        for t in all { #expect(Theme.groups.contains(t.group), "\(t.id): grupo «\(t.group)»") }
        for g in ["Ordenadores clásicos", "Ciencia ficción", "Centro de datos", "Videojuegos retro"] {
            #expect(all.count { $0.group == g } >= 3, "\(g)")
        }
        let naturaleza = Theme.sorted(all.filter { $0.group == "Naturaleza" })
        #expect(naturaleza.count == 8)
        for par in stride(from: 0, to: naturaleza.count - 1, by: 2) {
            let (oscuro, claro) = (naturaleza[par], naturaleza[par + 1])
            #expect(!oscuro.isLight && claro.isLight, "\(oscuro.id) / \(claro.id)")
            #expect(claro.id.hasSuffix("-clara") || claro.id.hasSuffix("-claro"), "\(claro.id)")
        }
    }

    @Test func colorMalEsUnError() {
        #expect(throws: Theme.ParseError.badColor("fondo")) { try Theme(id: "x", text: "fondo = rojo") }
    }

    @Test func todosDisponiblesSinInstalarEImportados() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = ThemeLibrary(appDirectory: Self.catalog, importDirectory: dir, netdeckDirectory: nil)
        let all = lib.all()
        #expect(all.count >= 86)
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
