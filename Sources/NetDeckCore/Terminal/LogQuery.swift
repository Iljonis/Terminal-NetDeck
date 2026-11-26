import Foundation

/// El periodo de «Buscar en todos los registros»: se mide por la carpeta del día (`AAAA-MM-DD/`) en la que
/// `SessionLogger` deja cada registro.
public enum LogPeriod: String, CaseIterable, Sendable, Identifiable {
    case today, week, month, all

    public var id: String { rawValue }

    /// Cuántos días cuenta, hoy incluido (nil: todos).
    public var days: Int? {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        case .all: nil
        }
    }

    /// El texto del selector.
    public var title: String {
        switch self {
        case .today: L("Hoy")
        case .week: L("Últimos 7 días")
        case .month: L("Últimos 30 días")
        case .all: L("Todo")
        }
    }

    /// El primer día que entra, como AAAAMMDD (nil: todos).
    func firstDay(now: Date, calendar: Calendar) -> Int? {
        guard let days, let from = calendar.date(byAdding: .day, value: -(days - 1), to: now) else { return nil }
        return LogSearch.dayKey(from, calendar: calendar)
    }
}

/// Un regex que no compila: el texto es legible (no el de ICU).
public struct LogSearchError: LocalizedError, Equatable, Sendable {
    public var errorDescription: String? { L("Expresión regular no válida") }
}

/// Qué buscar y dónde: el texto (tal cual o regex), cómo comparar, el equipo, el periodo y el tope de aciertos.
public struct LogQuery: Sendable, Equatable {
    /// Los aciertos que se enseñan como mucho y el largo (en bytes) de cada línea.
    public static let defaultMaxHits = 500
    public static let maxLine = 4096

    public var text: String
    public var isRegex: Bool
    public var caseSensitive: Bool
    public var wholeWord: Bool
    /// El nombre del equipo tal como sale en el archivo del registro (nil: todos).
    public var host: String?
    public var period: LogPeriod
    public var maxHits: Int

    public init(text: String, isRegex: Bool = false, caseSensitive: Bool = false, wholeWord: Bool = false,
                host: String? = nil, period: LogPeriod = .all, maxHits: Int = LogQuery.defaultMaxHits) {
        self.text = text
        self.isRegex = isRegex
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.host = host
        self.period = period
        self.maxHits = max(1, maxHits)
    }

    /// El texto sin espacios de más (con nada que buscar no se busca).
    public var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Una MAC en cualquier formato → la expresión que encaja con todos.
    public static func macPattern(_ q: String) -> String? {
        let hex = q.lowercased().filter { $0.isHexDigit }
        guard hex.count == 12, q.count <= 17, q.allSatisfy({ $0.isHexDigit || ":-. ".contains($0) }) else { return nil }
        let c = Array(hex)
        let pairs = stride(from: 0, to: 12, by: 2).map { String(c[$0...$0 + 1]) }
        let quads = stride(from: 0, to: 12, by: 4).map { String(c[$0..<$0 + 4]) }
        return "(" + [pairs.joined(separator: "[:-]"), quads.joined(separator: "[.-]"), hex].joined(separator: "|") + ")"
    }

    /// Una IPv4 sola → la expresión con bordes: «192.0.2.1» no acierta dentro de «192.0.2.11» ni de «1.192.0.2.1».
    public static func ipv4Pattern(_ q: String) -> String? {
        let parts = q.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ (1...3).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            return nil
        }
        return #"(?<!\d)(?<!\d\.)"# + NSRegularExpression.escapedPattern(for: q) + #"(?!\d)(?!\.\d)"#
    }

    /// La expresión regular que se compila (con la MAC y la IPv4 reconocidas en modo texto).
    public func pattern() -> String {
        let q = trimmed
        var p: String
        if isRegex {
            p = q
        } else if let mac = Self.macPattern(q) {
            p = "(?i:\(mac))"                                       // (una MAC se encuentra en mayúsculas y minúsculas)
        } else {
            p = Self.ipv4Pattern(q) ?? NSRegularExpression.escapedPattern(for: q)
        }
        if wholeWord { p = #"(?<![\p{L}\p{N}_])(?:"# + p + #")(?![\p{L}\p{N}_])"# }
        return p
    }

    /// El comparador, o `LogSearchError` si el regex no compila.
    public func matcher() throws -> LogMatcher {
        do {
            let p = pattern(), options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            let regex = try NSRegularExpression(pattern: p, options: options)
            // (para descartar de golpe un bloque de líneas sin acierto: ^ y $ por línea; con \A, \z, \Z o \G, no vale)
            let anchored = ["\\A", "\\z", "\\Z", "\\G"].contains { p.contains($0) }
            let block = anchored ? nil : try? NSRegularExpression(pattern: p, options: options.union(.anchorsMatchLines))
            return LogMatcher(regex, block: block)
        } catch {
            throw LogSearchError()
        }
    }
}

/// Una consulta ya compilada: dice si una línea acierta y dónde (para resaltar).
public final class LogMatcher: @unchecked Sendable {      // (NSRegularExpression no cambia tras crearse)
    private let regex: NSRegularExpression
    private let block: NSRegularExpression?

    init(_ regex: NSRegularExpression, block: NSRegularExpression? = nil) {
        self.regex = regex
        self.block = block
    }

    /// ¿Puede acertar alguna de estas líneas (unidas con «\n»)? Un «no» es seguro y ahorra mirarlas una a una; un «sí»
    /// no lo es (un `\s` cruza líneas).
    func mayMatch(block lines: String) -> Bool {
        guard let block else { return true }
        return block.firstMatch(in: lines, range: NSRange(location: 0, length: lines.utf16.count)) != nil
    }

    public func matches(_ line: String) -> Bool {
        regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) != nil
    }

    /// Dónde acierta la línea, en posiciones de carácter (`line[i]` con `index(offsetBy:)`); sin vacíos y, como mucho,
    /// `limit` (una línea de 4 KB con un «.» no pinta miles de rangos).
    public func ranges(in line: String, limit: Int = 64) -> [Range<Int>] {
        var out: [Range<Int>] = []
        regex.enumerateMatches(in: line, range: NSRange(location: 0, length: line.utf16.count)) { m, _, stop in
            guard let m, m.range.length > 0, let r = Range(m.range, in: line) else { return }
            let lo = line.distance(from: line.startIndex, to: r.lowerBound)
            out.append(lo..<(lo + line.distance(from: r.lowerBound, to: r.upperBound)))
            if out.count >= limit { stop.pointee = true }
        }
        return out
    }
}
