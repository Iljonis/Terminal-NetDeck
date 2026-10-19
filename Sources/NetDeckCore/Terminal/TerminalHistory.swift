import Foundation

/// Líneas que guarda cada terminal para volver atrás (scrollback). Ajustes → Terminal; se aplica también a las pestañas
/// abiertas (si se baja, se pierden las más viejas que no quepan).
public enum TerminalHistory {
    /// Clave en UserDefaults (la vista la lee al crearse).
    public static let key = "scrollback"
    public static let defaultLines = 2_500
    public static let options = [1_000, 2_500, 5_000, 10_000]
    /// Lo que se acepta de UserDefaults o de «-scrollback N» (menos no deja ver ni un `show run`; más gasta memoria por
    /// pestaña sin necesidad).
    public static let range = 100...100_000

    /// Lo guardado, dentro de `range`; sin nada (o no es un número), `defaultLines`.
    public static func lines(_ stored: Any?) -> Int {
        guard let n = (stored as? Int) ?? (stored as? String).flatMap({ Int($0) }) else { return defaultLines }
        return min(max(n, range.lowerBound), range.upperBound)
    }

    public static var current: Int { lines(UserDefaults.standard.object(forKey: key)) }

    /// «2.500» / «2,500».
    public static func grouped(_ n: Int, idioma: Idioma = Idioma.actual) -> String {
        let digits = Array(String(n))
        var out = ""
        for (i, d) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out += idioma == .en ? "," : "." }
            out.append(d)
        }
        return out
    }

    /// «2.500 líneas» / «2,500 lines».
    public static func label(_ n: Int) -> String { L("\(grouped(n)) líneas") }
}
