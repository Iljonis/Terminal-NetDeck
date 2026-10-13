import Foundation

/// Estilo de un trozo resaltado: «f.cyan bold», «b.red», «f#ff2e88 underline» (formato de ChromaTerm).
public struct HighlightStyle: Hashable, Sendable {
    public var foreground: String?          // nombre de la paleta o «#rrggbb»
    public var background: String?
    public var bold = false
    public var italic = false
    public var underline = false

    public init(_ spec: String) {
        for tok in spec.split(whereSeparator: \.isWhitespace).map(String.init) {
            switch tok.lowercased() {
            case "bold": bold = true
            case "italic": italic = true
            case "underline": underline = true
            default:
                if tok.hasPrefix("f.") || tok.hasPrefix("f#") { foreground = String(tok.dropFirst(tok.hasPrefix("f.") ? 2 : 1)) }
                if tok.hasPrefix("b.") || tok.hasPrefix("b#") { background = String(tok.dropFirst(tok.hasPrefix("b.") ? 2 : 1)) }
            }
        }
    }
}

/// Una regla: expresión regular y el estilo de todo el acierto o de cada grupo.
public struct HighlightRule: Sendable {
    public var description: String
    public var regex: Pattern
    public var source: String
    /// Grupo → estilo (0 = el acierto entero).
    public var styles: [Int: HighlightStyle]
    /// Lo que colorea ya no lo colorea ninguna regla de después.
    public var exclusive: Bool

    public init(description: String, regex: String, styles: [Int: HighlightStyle], exclusive: Bool = false) throws {
        // (sintaxis de Python → ICU)
        let icu = regex.replacingOccurrences(of: "(?P<", with: "(?<").replacingOccurrences(of: "(?P=", with: "\\k<")
        _ = try NSRegularExpression(pattern: icu)                // (que una regla mala no tumbe la app)
        self.description = description
        self.regex = Pattern(icu, ignoreCase: false)
        self.source = regex
        self.styles = styles
        self.exclusive = exclusive
    }
}

/// Un archivo de ChromaTerm (el chromaterm.yml de NetDeck vale tal cual): `palette:` y `rules:` con description,
/// regex, color (texto o {grupo: texto}) y exclusive. Sólo lo que usa ChromaTerm, sin dependencias.
public struct HighlightConfig: Sendable {
    public var palette: [String: RGB] = [:]
    public var rules: [HighlightRule] = []
    /// Reglas que no se han podido leer (descripción: motivo).
    public var problems: [String] = []

    public init() {}

    public init(contentsOf url: URL) throws {
        try self.init(text: String(contentsOf: url, encoding: .utf8))
    }

    public init(text: String) throws {
        enum Section { case none, palette, rules }
        var section = Section.none
        var current: [String: String]?
        func flush() {
            guard let r = current else { return }
            current = nil
            let desc = r["description"] ?? L("regla \(rules.count + problems.count + 1)")
            guard let regex = r["regex"], let color = r["color"] else { problems.append(L("\(desc): falta regex o color")); return }
            do {
                rules.append(try HighlightRule(description: desc, regex: regex, styles: Self.styles(color),
                                               exclusive: r["exclusive"]?.lowercased() == "true"))
            } catch {
                problems.append(L("\(desc): expresión no válida"))
            }
        }
        for raw in text.components(separatedBy: .newlines) {
            let trimmed = raw.trimmed
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indented = raw.first?.isWhitespace == true
            if !indented, !trimmed.hasPrefix("-") {
                flush()
                let key = Self.unquote(Self.stripComment(trimmed)).partition(":").0.trimmed
                section = key == "palette" ? .palette : key == "rules" ? .rules : .none
                continue
            }
            switch section {
            case .palette:
                let (k, _, v) = Self.stripComment(trimmed).partition(":")
                if let c = RGB(hex: Self.unquote(v.trimmed)) { palette[k.trimmed] = c }
            case .rules:
                var line = trimmed
                if line.hasPrefix("-") {
                    flush()
                    current = [:]
                    line = String(line.dropFirst()).trimmed
                    if line.isEmpty { continue }
                }
                let (k, _, v) = line.partition(":")
                current?[k.trimmed] = Self.unquote(Self.stripComment(v.trimmed))
            case .none:
                continue
            }
        }
        flush()
    }

    /// «f.cyan bold» o «{1: f.cyan bold, 2: f.dim}».
    static func styles(_ color: String) -> [Int: HighlightStyle] {
        let c = color.trimmed
        guard c.hasPrefix("{"), c.hasSuffix("}") else { return [0: HighlightStyle(c)] }
        var out: [Int: HighlightStyle] = [:]
        for part in c.dropFirst().dropLast().split(separator: ",") {
            let (k, _, v) = String(part).partition(":")
            if let n = Int(k.trimmed) { out[n] = HighlightStyle(unquote(v.trimmed)) }
        }
        return out
    }

    /// YAML: « #…» fuera de comillas es comentario.
    static func stripComment(_ s: String) -> String {
        var quote: Character?
        var prev: Character = " "
        for (i, ch) in zip(s.indices, s) {
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "'" || ch == "\"" {
                quote = ch
            } else if ch == "#", prev.isWhitespace {
                return String(s[..<i]).trimmed
            }
            prev = ch
        }
        return s
    }

    static func unquote(_ s: String) -> String {
        if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return s
    }
}

extension Theme {
    /// La paleta del resaltado sacada del tema (el mismo reparto que hace «tema» en NetDeck).
    public var highlightPalette: [String: RGB] {
        ["white": text, "yellow": accent, "cyan": accent2, "red": bad, "green": good, "magenta": special,
         "orange": warning, "blue": blue, "dark": background.opaque, "dim": dim]
    }
}
