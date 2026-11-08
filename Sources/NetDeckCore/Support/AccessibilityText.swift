import Foundation

/// Textos para VoiceOver sacados de los que ya se ven.
public enum AccessibilityText {
    /// El nombre corto de un botón de icono a partir de su ayuda: hasta los «:», « (», « · » o el salto de línea
    /// («Pegado seguro: revisa…» → «Pegado seguro», «Ajustes (⌘,)» → «Ajustes»). La ayuda entera queda de pista.
    public static func label(fromHelp help: String) -> String {
        var s = Substring(help)
        for cut in [":", " (", " · ", "\n"] {
            if let r = s.range(of: cut), r.lowerBound > s.startIndex { s = s[..<r.lowerBound] }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
