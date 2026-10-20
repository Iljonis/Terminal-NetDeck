import Foundation

/// Expresión regular inmutable (NSRegularExpression): la sintaxis de los `re` de NetDeck se copia tal cual.
public struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression
    private let acotada: Bool

    public init(_ pattern: String, ignoreCase: Bool = true) {
        regex = try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
        acotada = false
    }

    /// La de un usuario (p. ej. «# @prompt …»): nil si no compila, en vez de parar la app.
    public init?(compiling pattern: String, ignoreCase: Bool = false) {
        guard let r = try? NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : []) else { return nil }
        regex = r
        acotada = true
    }

    public func matches(_ s: String) -> Bool { first(s) != nil }

    /// Rango del primer acierto, o nil.
    public func range(in s: String) -> Range<String.Index>? {
        first(s).flatMap { Range($0.range, in: s) }
    }

    /// Grupo `n` del primer acierto, o nil.
    public func group(_ n: Int, in s: String) -> String? {
        guard let m = first(s), let r = Range(m.range(at: n), in: s) else { return nil }
        return String(s[r])
    }

    public static func escape(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }

    /// Conservador con los grupos repetidos: ni alternativas ni cuantificadores dentro, a cualquier profundidad.
    /// Escapes y clases no cuentan como sintaxis de grupo («[()+|]», «\\(»).
    static func repeticionPeligrosa(en source: String) -> Bool {
        struct Grupo { var cuantificada = false; var alternativa = false }
        let texto = Array(source)
        var grupos = [Grupo()], escape = false, clase = false
        for (i, c) in texto.enumerated() {
            if escape { escape = false; continue }
            if c == "\\" { escape = true; continue }
            if clase { if c == "]" { clase = false }; continue }
            if c == "[" { clase = true; continue }
            switch c {
            case "(": grupos.append(Grupo())
            case ")":
                guard grupos.count > 1 else { return true }
                let g = grupos.removeLast()
                let repetida = i + 1 < texto.count && "*+{".contains(texto[i + 1])
                if repetida && (g.cuantificada || g.alternativa) { return true }
                grupos[grupos.count - 1].cuantificada = grupos.last!.cuantificada || g.cuantificada || repetida
                grupos[grupos.count - 1].alternativa = grupos.last!.alternativa || g.alternativa
            case "|": grupos[grupos.count - 1].alternativa = true
            case "*", "+", "{": grupos[grupos.count - 1].cuantificada = true
            case "?" where i == 0 || texto[i - 1] != "(":
                grupos[grupos.count - 1].cuantificada = true
            default: break
            }
        }
        return false
    }

    private func first(_ s: String) -> NSTextCheckingResult? {
        let range = NSRange(s.startIndex..., in: s)
        guard acotada else { return regex.firstMatch(in: s, range: range) }
        // (ICU llama periódicamente durante el backtracking; el límite también cubre regex no detectadas arriba)
        let fin = ContinuousClock.now + .milliseconds(5)
        var resultado: NSTextCheckingResult?
        regex.enumerateMatches(in: s, options: [.reportProgress], range: range) { match, _, stop in
            if ContinuousClock.now >= fin { stop.pointee = true; return }
            if let match { resultado = match; stop.pointee = true }
        }
        return resultado
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
