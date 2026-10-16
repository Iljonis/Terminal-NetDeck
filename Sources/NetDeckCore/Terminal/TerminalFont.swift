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
}
