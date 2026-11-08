import Foundation
import Testing
@testable import NetDeckCore

/// Colores a medida por tema (Ajustes → Temas → «Personalizar colores»): una capa encima del tema.
@Suite struct ThemeOverridesTests {
    static let glass = try! Theme(id: "cristal-prueba", text: """
        # Cristal de prueba — vidrio oscuro
        nombre    = Cristal de prueba
        grupo     = Sistemas
        estilo    = cristal
        material  = cristal
        fondo         = #1c1c1eb3
        texto         = #f5f5f7
        barra         = #2c2c2e66
        panel         = #3a3a3c99
        pestaña       = #0a84ff
        sobre_pestaña = #ffffff
        acento        = #0a84ff
        acento2       = #64d2ff
        bien          = #30d158
        mal           = #ff453a
        especial      = #bf5af2
        apagado       = #8e8e93
        """)

    static func temp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("colores-\(UUID().uuidString)", isDirectory: true)
    }

    /// Sólo cambia lo dado: el resto del tema (y los ANSI que no se fijan, que salen del tema ya cambiado) igual.
    @Test func aplicaSoloLoDado() {
        let base = Theme.builtIn
        let o = ThemeOverrides(["acento": "#112233", "ansi3": "#445566"])
        let t = o.apply(to: base)
        #expect(t.accent == RGB(0x11, 0x22, 0x33))
        #expect(t.ansi[3] == RGB(0x44, 0x55, 0x66))
        #expect(t.text == base.text && t.background == base.background && t.tab == base.tab && t.accent2 == base.accent2)
        #expect(t.ansi[1] == base.ansi[1] && t.ansi[15] == base.ansi[15])
        #expect(t.selection == base.selection && t.cursor == t.accent)
        #expect(ThemeOverrides().apply(to: base) == base)
        // (selección y cursor, aparte)
        let sc = ThemeOverrides(["selección": "#203040", "cursor": "#ff00ff"]).apply(to: base)
        #expect(sc.selection == RGB(0x20, 0x30, 0x40) && sc.cursor == RGB(255, 0, 255) && sc.accent == base.accent)
    }

    @Test func hexInvalidoYClavesRarasSeIgnoran() {
        let o = ThemeOverrides(["acento": "azul", "texto": "#12345", "fondo": "#zzzzzz", "barra": "#000000",
                                "opacidad": "7", "pestaña": "#abcdef"])
        #expect(o.colors.keys.sorted() == ["pestaña"])
        #expect(o.opacity == nil)
        #expect(ThemeOverrides(["opacidad": "nada"]).isEmpty)
    }

    @Test func ansiFueraDeRangoSeDescarta() {
        let o = ThemeOverrides(["ansi16": "#ffffff", "ansi-1": "#ffffff", "ansi15": "#010203"])
        #expect(o.colors.keys.sorted() == ["ansi15"])
        var p = ThemeOverrides()
        p["ansi99"] = RGB(1, 2, 3)
        #expect(p.isEmpty)
    }

    /// Ida y vuelta con lo que se guarda en Ajustes.
    @Test func idaYVueltaConAjustes() {
        var o = ThemeOverrides()
        o["texto"] = RGB(10, 20, 30)
        o["ansi0"] = RGB(1, 2, 3)
        o.setOpacity(0.55)
        let d = o.dictionary
        #expect(d["texto"] == "#0a141e" && d["ansi0"] == "#010203" && d["opacidad"] == "0.55")
        #expect(ThemeOverrides(d) == o)
        // (lo de fuera de rango se lleva al rango)
        o.setOpacity(0.01)
        #expect(o.opacity == ThemeOverrides.opacityRange.lowerBound)
    }

    /// Con «Reducir transparencia» el tema efectivo queda opaco (alfa 1) y con el color elegido.
    @Test func efectivoConReducirTransparencia() {
        let o = ThemeOverrides(["fondo": "#102030", "opacidad": "0.5"])
        let normal = ThemeOverrides.effective(Self.glass, o, solid: false)
        #expect(normal.background.opaque == RGB(16, 32, 48))
        #expect(abs(normal.background.a - 0.5) < 0.01)
        let solid = ThemeOverrides.effective(Self.glass, o, solid: true)
        #expect(solid.background == RGB(16, 32, 48, 1))
        #expect(!solid.isTranslucent)
        #expect(ThemeOverrides.effective(Self.glass, nil, solid: true) == Self.glass.solid)
        // (la opacidad no hace nada en uno opaco)
        #expect(ThemeOverrides(["opacidad": "0.5"]).apply(to: Theme.builtIn).background.a == 1)
        // (el fondo nuevo guarda la transparencia del tema)
        #expect(ThemeOverrides(["fondo": "#102030"]).apply(to: Self.glass).background.a == Self.glass.background.a)
    }

    /// Exportar y volver a importar da el mismo tema (con los colores a medida, la opacidad y los ANSI fijados).
    @Test func exportarYVolverAImportar() throws {
        let o = ThemeOverrides(["fondo": "#102030", "opacidad": "0.63", "ansi4": "#3366ff", "cursor": "#ffcc00",
                                "selección": "#334455"])
        for base in [Theme.builtIn, Self.glass] + (try ThemeTests.catalogThemes()) {
            let t = o.apply(to: base)
            #expect(try Theme(id: t.id, text: t.temaText) == t, "\(base.id)")
        }
    }

    /// Guardar como tema nuevo: lo escribe entre los importados (sólo para ti), no pisa ninguno y rechaza nombres raros.
    @Test func guardarComoTemaNuevo() throws {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = ThemeLibrary(appDirectory: nil, importDirectory: dir, netdeckDirectory: nil)
        let t = ThemeOverrides(["acento": "#123456"]).apply(to: Theme.builtIn)
        let saved = try lib.saveNew(t, name: "Mi Cyberpunk Ñ")
        #expect(saved.id == "mi-cyberpunk-n" && saved.name == "Mi Cyberpunk Ñ" && saved.accent == RGB(0x12, 0x34, 0x56))
        #expect(lib.all().contains { $0.theme.id == saved.id && $0.source == .imported })
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("mi-cyberpunk-n.tema").path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        #expect(throws: ThemeLibrary.SaveError.self) { try lib.saveNew(t, name: "mi cyberpunk n") }
        #expect(throws: ThemeLibrary.SaveError.self) { try lib.saveNew(t, name: "NetDeck Cyberpunk") }
        for bad in ["", "  ", "-raro", "con # almohadilla", "¡¡!!"] {
            #expect(throws: ThemeLibrary.SaveError.badName) { try lib.saveNew(t, name: bad) }
        }
    }

    /// Los cambios de un tema que ya no existe (o que no tienen nada válido) se descartan.
    @Test func losDeUnTemaQueYaNoEstaSeDescartan() {
        let all = ["netdeck-cyberpunk": ["acento": "#112233"], "borrado": ["acento": "#445566"],
                   "vacio": ["acento": "nada"]]
        #expect(ThemeOverrides.pruned(all, keeping: ["netdeck-cyberpunk", "vacio"]) == ["netdeck-cyberpunk": ["acento": "#112233"]])
    }

    /// Aviso de contraste: texto sobre el fondo por debajo de 4,5:1 y un ANSI por debajo de 3:1.
    @Test func avisoDeContraste() {
        #expect(ThemeOverrides.contrastWarnings(Theme.builtIn).isEmpty)
        let t = ThemeOverrides(["texto": "#14132a", "ansi2": "#0c0b20"]).apply(to: Theme.builtIn)
        let keys = Set(ThemeOverrides.contrastWarnings(t).map(\.key))
        #expect(keys.contains("texto") && keys.contains("ansi2"))
        #expect(ThemeOverrides.contrastWarnings(t).allSatisfy { $0.ratio < $0.minimum })
    }
}
