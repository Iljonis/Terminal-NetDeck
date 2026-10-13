import Foundation

/// Expresión regular inmutable (NSRegularExpression): la sintaxis de los `re` de NetDeck se copia tal cual.
public struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    public init(_ pattern: String, ignoreCase: Bool = true) {
        regex = try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
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

    private func first(_ s: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
