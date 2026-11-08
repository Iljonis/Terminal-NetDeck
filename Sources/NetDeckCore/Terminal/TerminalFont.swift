import CoreText
import Foundation

/// La letra de las terminales, sin ligaduras ni alternativas contextuales. SwiftTerm pone cada glifo en la celda de su
/// carácter contando glifos: si la fuente junta «fl» o «fi» en uno solo (Share Tech Mono, la cursiva de Space Mono…),
/// ese glifo cae en una celda y todo lo que sigue en la línea se corre una a la izquierda, encima de la letra de al
/// lado. Sin ligaduras sale un glifo por carácter, cada uno en su celda.
public enum TerminalFont {
    private static let featuresOff: [(Int, Int)] = [
        (kLigaturesType, kCommonLigaturesOffSelector),
        (kLigaturesType, kRareLigaturesOffSelector),
        (kLigaturesType, kContextualLigaturesOffSelector),
        (kLigaturesType, kHistoricalLigaturesOffSelector),
        (kContextualAlternatesType, kContextualAlternatesOffSelector),
    ]

    /// La misma fuente y tamaño con esas opciones apagadas (las que la fuente no tenga se ignoran).
    public static func strict(_ font: CTFont) -> CTFont {
        let settings = featuresOff.map { t, s in
            [kCTFontFeatureTypeIdentifierKey: t, kCTFontFeatureSelectorIdentifierKey: s] as [CFString: Int]
        }
        let d = CTFontDescriptorCreateWithAttributes([kCTFontFeatureSettingsAttribute: settings] as CFDictionary)
        return CTFontCreateCopyWithAttributes(font, 0, nil, d)
    }

    /// Glifos que salen al escribir `text` con `font` (uno por carácter = cada letra en su celda).
    public static func glyphCount(_ font: CTFont, _ text: String) -> Int {
        let s = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        return CTLineGetGlyphCount(CTLineCreateWithAttributedString(s))
    }

    /// La celda como la mide SwiftTerm (`computeFontDimensions`): alto de la letra por el interlineado y ancho de la
    /// «W» buscada por carácter (por nombre de glifo, las CJK como Songti o BIZ UDGothic dan .notdef, de un em entero),
    /// ajustados a los píxeles de la pantalla.
    public static func cell(_ font: CTFont, lineSpacing: CGFloat, scale: CGFloat) -> CGSize {
        var chars: [UniChar] = [0x57], glyphs: [CGGlyph] = [0]
        let glyph = CTFontGetGlyphsForCharacters(font, &chars, &glyphs, 1) ? glyphs[0] : CTFontGetGlyphWithName(font, "W" as CFString)
        var g = glyph, advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &advance, 1)
        let h = ceil((CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)) * lineSpacing)
        return CGSize(width: max(1, (advance.width * scale).rounded() / scale), height: max(1, ceil(h * scale) / scale))
    }

    // MARK: - tamaño e interlineado

    /// Tamaños que valen en todas partes: Ajustes, «# @fuente» y ⌘+ / ⌘-.
    public static let sizes = 8.0...36.0
    /// Interlineado (el alto de la celda por esto; 1 = el de la fuente): Ajustes y «# @interlineado».
    public static let lineSpacings = 0.9...1.5

    /// El tamaño guardado en Ajustes: 0 = el del tema; si no, dentro de `sizes` (un 1-7 de cuando el deslizador iba
    /// de 0 a 26, al mínimo).
    public static func setting(_ size: Double) -> Double {
        size.isFinite && size > 0 ? clamp(size) : 0
    }

    /// El que sale de verdad: `size` (0 = el del tema, su «tamaño» − 1) más `zoom` (los puntos de ⌘+ / ⌘- de la
    /// pestaña), siempre dentro de `sizes`.
    public static func size(_ size: Double, themeSize: Int, zoom: Int = 0) -> Double {
        clamp(clamp(size.isFinite && size > 0 ? size : Double(themeSize - 1)) + Double(zoom))
    }

    /// ⌘+ / ⌘-: el aumento de la pestaña tras `steps` puntos más (o menos), sin salirse de `sizes` (así, al tope, ⌘-
    /// baja a la primera).
    public static func zoom(_ zoom: Int, by steps: Int, size: Double, themeSize: Int) -> Int {
        let base = Self.size(size, themeSize: themeSize)
        return Int(clamp(Self.size(size, themeSize: themeSize, zoom: zoom) + Double(steps)) - base)
    }

    /// El interlineado dentro de `lineSpacings`, en centésimas (lo que no es un número, 1).
    public static func lineSpacing(_ v: Double) -> Double {
        guard v.isFinite else { return 1 }
        return (min(max(v, lineSpacings.lowerBound), lineSpacings.upperBound) * 100).rounded() / 100
    }

    private static func clamp(_ v: Double) -> Double { min(max(v.rounded(), sizes.lowerBound), sizes.upperBound) }
}
