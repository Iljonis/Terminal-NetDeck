import AppKit
import CoreText
import Testing
@testable import NetDeckCore

@Suite struct TerminalFontTests {
    static let text = "flaps filas office ffl -> != =="

    /// Con ligaduras, «fl»/«fi»/«ffl» salen en un glifo (y SwiftTerm correría la línea); sin ellas, uno por carácter,
    /// también en la negrita y la cursiva que saca SwiftTerm de la normal. (Hoefler Text: viene con macOS y las tiene.)
    @Test(.enabled(if: NSFont(name: "Hoefler Text", size: 13) != nil))
    func sinLigaduras() throws {
        let f = try #require(NSFontManager.shared.font(withFamily: "Hoefler Text", traits: [], weight: 5, size: 13))
        #expect(TerminalFont.glyphCount(f, Self.text) < Self.text.utf16.count)
        let strict = TerminalFont.strict(f) as NSFont
        #expect(strict.pointSize == f.pointSize && strict.familyName == f.familyName)
        #expect(TerminalFont.glyphCount(strict, Self.text) == Self.text.utf16.count)
        let bold = NSFontManager.shared.convert(strict, toHaveTrait: .boldFontMask)
        #expect(TerminalFont.glyphCount(bold, Self.text) == Self.text.utf16.count)
    }

    /// La del sistema (la de por defecto) también: un glifo por carácter.
    @Test func laDelSistema() {
        let f = TerminalFont.strict(NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        #expect(TerminalFont.glyphCount(f, Self.text) == Self.text.utf16.count)
    }

    /// Un rango para todo (Ajustes, «# @fuente», ⌘+ / ⌘-) y el «automático» = el del tema − 1, dentro de él.
    @Test func tamañoDentroDelRango() {
        #expect(TerminalFont.sizes == 8...36 && TerminalProfile.fontSizes == TerminalFont.sizes)
        #expect(TerminalFont.size(0, themeSize: 14) == 13)              // (el del tema)
        #expect(TerminalFont.size(17, themeSize: 14) == 17)
        #expect(TerminalFont.size(0, themeSize: 6) == 8 && TerminalFont.size(0, themeSize: 60) == 36)
        #expect(TerminalFont.size(.nan, themeSize: 14) == 13)
        #expect(TerminalFont.size(0, themeSize: 14, zoom: 2) == 15 && TerminalFont.size(35, themeSize: 14, zoom: 5) == 36)
    }

    /// Ajustes guardados con el deslizador de antes (0-26): 0 sigue siendo el del tema y un 1-7, el mínimo.
    @Test func migraElTamañoGuardado() {
        #expect(TerminalFont.setting(0) == 0 && TerminalFont.setting(-3) == 0 && TerminalFont.setting(.infinity) == 0)
        for v in 1...7 { #expect(TerminalFont.setting(Double(v)) == 8) }
        #expect(TerminalFont.setting(14) == 14 && TerminalFont.setting(26) == 26 && TerminalFont.setting(40) == 36)
        #expect(TerminalFont.setting(12.6) == 13)
    }

    /// ⌘+ / ⌘-: un punto cada vez, sin salir del rango, y al tope ⌘- baja enseguida (no hay puntos «escondidos»).
    @Test func zoomDeLaPestaña() {
        var z = 0
        for _ in 0..<40 { z = TerminalFont.zoom(z, by: 1, size: 0, themeSize: 14) }
        #expect(z == 23 && TerminalFont.size(0, themeSize: 14, zoom: z) == 36)
        z = TerminalFont.zoom(z, by: -1, size: 0, themeSize: 14)
        #expect(TerminalFont.size(0, themeSize: 14, zoom: z) == 35)
        for _ in 0..<40 { z = TerminalFont.zoom(z, by: -1, size: 0, themeSize: 14) }
        #expect(z == -5 && TerminalFont.size(0, themeSize: 14, zoom: z) == 8)
    }

    @Test func interlineado() {
        #expect(TerminalFont.lineSpacing(1.2) == 1.2 && TerminalFont.lineSpacing(1.234) == 1.23)
        #expect(TerminalFont.lineSpacing(0.5) == 0.9 && TerminalFont.lineSpacing(3) == 1.5 && TerminalFont.lineSpacing(.nan) == 1)
    }

    /// La celda, como SwiftTerm: la «W» por carácter. Songti no tiene un glifo llamado «W» (por nombre sale .notdef,
    /// de un em entero) y la celda salía más ancha que la de SwiftTerm: la selección en bloque y el ratón, corridos.
    @Test(.enabled(if: NSFontManager.shared.font(withFamily: "Songti SC", traits: [], weight: 5, size: 13) != nil))
    func celdaComoSwiftTermEnCJK() throws {
        let f = try #require(NSFontManager.shared.font(withFamily: "Songti SC", traits: [], weight: 5, size: 13))
        let w = NSAttributedString(string: "W", attributes: [.font: f]).size().width
        let c = TerminalFont.cell(f, lineSpacing: 1, scale: 2)
        #expect(abs(c.width - w) <= 0.5)
        #expect(abs(c.width - f.advancement(forGlyph: f.glyph(withName: "W")).width) > 0.5)
        #expect(TerminalFont.cell(f, lineSpacing: 1.5, scale: 2).height > c.height)
    }

    @Test func celdaDeMenlo() {
        let f = TerminalFont.strict(NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)) as NSFont
        let c = TerminalFont.cell(f, lineSpacing: 1, scale: 2)
        #expect(abs(c.width - f.advancement(forGlyph: f.glyph(withName: "W")).width) <= 0.5)
        #expect(c.height == ceil(ceil(f.ascender - f.descender + f.leading) * 2) / 2)
    }
}
