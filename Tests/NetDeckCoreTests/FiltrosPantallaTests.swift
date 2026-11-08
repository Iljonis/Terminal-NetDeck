import Foundation
import Testing
@testable import NetDeckCore

/// Filtro de pantalla (1.0.0): «filtro =» de los .tema, qué se pinta en cada pestaña y que nunca tape el texto.
@Suite struct FiltrosPantallaTests {
    private func tema(_ filtro: String?) throws -> Theme {
        var t = """
            nombre = Prueba
            fondo = #0b0a1f
            texto = #33ff66
            barra = #07061a
            panel = #1a1740
            pestaña = #ff2e88
            sobre_pestaña = #0b0a1f
            acento = #00e5ff
            acento2 = #ff2e88
            bien = #5cffb0
            mal = #ff3b5c
            especial = #b18cff
            apagado = #6b66a8
            """
        if let filtro { t += "\nfiltro = \(filtro)" }
        return try Theme(id: "prueba", text: t)
    }

    @Test func seLeeElFiltroDelTema() throws {
        #expect(try tema("crt").screenFilter == .crt)
        #expect(try tema("LCD").screenFilter == .lcd)
        #expect(try tema("fosforo").screenFilter == .phosphor)
        #expect(try tema("Fósforo").screenFilter == .phosphor)              // (con tilde y mayúscula, también)
        #expect(try tema("holograma   # el de Sección 9").screenFilter == .hologram)
        #expect(try tema("ninguno").screenFilter == ScreenFilter.none)
        #expect(try tema("no").screenFilter == ScreenFilter.none)
        #expect(try tema(nil).screenFilter == nil)
        #expect(try tema("").screenFilter == nil)
        #expect(try tema("plasma").screenFilter == nil)                      // (lo que no se entiende: sin filtro)
        #expect(Theme.builtIn.screenFilter == nil)
        // (y los de la app se siguen leyendo, lleven o no la línea)
        for f in try FileManager.default.contentsOfDirectory(at: ThemeTests.catalog, includingPropertiesForKeys: nil)
        where f.pathExtension == "tema" { _ = try Theme(contentsOf: f) }
    }

    @Test func automaticoTemaElegidoYAccesibilidad() {
        let auto = ScreenFilter.automatic
        // «Automático»: el del tema; sin filtro en el tema, ninguno
        #expect(ScreenFilter.resolve(choice: auto, on: true, theme: .lcd, calm: false) == .lcd)
        #expect(ScreenFilter.resolve(choice: auto, on: true, theme: nil, calm: false) == ScreenFilter.none)
        // el elegido manda sobre el del tema, también «Ninguno»
        #expect(ScreenFilter.resolve(choice: "crt", on: true, theme: .lcd, calm: false) == .crt)
        #expect(ScreenFilter.resolve(choice: "ninguno", on: true, theme: .lcd, calm: false) == ScreenFilter.none)
        // un valor guardado que no se entiende, como «Automático»
        #expect(ScreenFilter.resolve(choice: "plasma", on: true, theme: .phosphor, calm: false) == .phosphor)
        // apagado (⌥⌘F) o con «Reducir movimiento / transparencia» o «Aumentar contraste»: nada
        for choice in [auto, "crt", "holograma"] {
            #expect(ScreenFilter.resolve(choice: choice, on: false, theme: .crt, calm: false) == ScreenFilter.none)
            #expect(ScreenFilter.resolve(choice: choice, on: true, theme: .crt, calm: true) == ScreenFilter.none)
        }
        #expect(ScreenFilter.none.look(intensity: 1, text: .white) == nil)
        // (lo que se guarda en Ajustes es el id, sin traducir)
        #expect(ScreenFilter.allCases.map(\.rawValue) == ["ninguno", "crt", "lcd", "fosforo", "holograma"])
    }

    @Test func intensidadFueraDeRango() {
        #expect(ScreenFilter.intensity(0.5) == 0.5)
        #expect(ScreenFilter.intensity(-3) == ScreenFilter.intensityRange.lowerBound)
        #expect(ScreenFilter.intensity(0) == ScreenFilter.intensityRange.lowerBound)
        #expect(ScreenFilter.intensity(7) == 1)
        #expect(ScreenFilter.intensity(.nan) == ScreenFilter.defaultIntensity)
        #expect(ScreenFilter.intensity(.infinity) == ScreenFilter.defaultIntensity)
        // (fuera de rango, se pinta como en el borde)
        #expect(ScreenFilter.crt.look(intensity: 50, text: .white) == ScreenFilter.crt.look(intensity: 1, text: .white))
        #expect(ScreenFilter.lcd.look(intensity: -1, text: .white) == ScreenFilter.lcd.look(intensity: 0.1, text: .white))
    }

    /// Ni con la máxima tapa el texto, y la de serie es moderada (menos que la máxima).
    @Test func nuncaTapaElTexto() throws {
        let text = RGB(51, 255, 102)
        for f in ScreenFilter.allCases where f != .none {
            let max = try #require(f.look(intensity: 1, text: text)), mid = try #require(f.look(intensity: ScreenFilter.defaultIntensity, text: text))
            for l in [max.scan, max.grid].compactMap({ $0 }) {
                #expect(l.color.a <= 0.35 && l.width < l.every, "\(f): líneas")
            }
            for c in [max.tint, max.glow].compactMap({ $0 }) { #expect(c.a <= 0.12, "\(f): velo") }
            #expect(max.vignette <= 0.4 && max.curve <= 12, "\(f): bordes")
            #expect((mid.scan ?? mid.grid)?.color.a ?? 0 < (max.scan ?? max.grid)?.color.a ?? 1, "\(f): moderada")
        }
        // el resplandor del fósforo y el «fantasma» del LCD son del color del texto
        #expect(ScreenFilter.phosphor.look(intensity: 1, text: text)?.glow?.opaque == text)
        #expect(ScreenFilter.lcd.look(intensity: 1, text: text)?.tint?.opaque == text)
    }
}
