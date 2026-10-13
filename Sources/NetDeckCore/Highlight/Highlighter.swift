import Foundation

/// Resaltado tipo ChromaTerm de lo que sale del equipo, entre el proceso y el terminal: mete colores (SGR de 24 bits)
/// alrededor de lo que encaja con las reglas. Respeta lo que ya trae el equipo: no toca las secuencias de escape, al
/// acabar cada trozo restaura los colores que hubiera puesto el equipo y no hace nada en pantalla completa (vi, less,
/// top…). Lo que llega partido (un carácter UTF-8 o una secuencia de escape a medias) espera al siguiente trozo.
/// No es seguro entre hilos: se usa siempre desde la misma cola.
public final class Highlighter: @unchecked Sendable {
    public var rules: [HighlightRule]
    public var palette: [String: RGB]
    public var enabled = true
    /// Líneas más largas no se resaltan (salidas enormes de una sola línea).
    public var maxLine = 4096

    private var carry: [UInt8] = []
    private var deviceSGR: [[UInt8]] = []
    private var altScreen = false

    public init(rules: [HighlightRule] = [], palette: [String: RGB] = [:]) {
        self.rules = rules
        self.palette = palette
    }

    // MARK: - flujo

    public func process(_ input: some Collection<UInt8>) -> [UInt8] {
        var data = carry + input
        carry = []
        let keep = Self.incompleteTail(data)
        if keep > 0, keep <= 64 {
            carry = Array(data.suffix(keep))
            data.removeLast(keep)
        }
        guard enabled, !rules.isEmpty else {
            trackOnly(data)
            return data
        }
        var out: [UInt8] = []
        out.reserveCapacity(data.count + 64)
        var start = 0
        while start < data.count {
            var end = start
            while end < data.count, data[end] != 10 { end += 1 }
            if end < data.count { end += 1 }                       // (con su «\n»)
            out += line(data[start..<end])
            start = end
        }
        return out
    }

    /// Estilos de una línea de texto (sin escapes): para la vista previa de Ajustes.
    public func styledRuns(_ text: String) -> [(range: Range<String.Index>, style: HighlightStyle)] {
        let ns = text as NSString
        let styles = match(text, utf16Count: ns.length)
        var out: [(Range<String.Index>, HighlightStyle)] = []
        var i = 0
        while i < styles.count {
            guard let s = styles[i] else { i += 1; continue }
            var j = i
            while j < styles.count, styles[j] == s { j += 1 }
            if let r = Range(NSRange(location: i, length: j - i), in: text) { out.append((r, s)) }
            i = j
        }
        return out
    }

    // MARK: - una línea

    private struct Token {
        var range: Range<Int>
        var isEscape: Bool
    }

    private func line(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        let b = Array(bytes)
        let tokens = Self.tokenize(b)
        // texto (sin escapes) y, por cada unidad UTF-16, su byte
        var scalars = String.UnicodeScalarView()
        var unitByte: [Int] = []                                   // utf16 → índice de byte en `b`
        for t in tokens where !t.isEscape {
            var i = t.range.lowerBound
            while i < t.range.upperBound {
                let (scalar, len) = Self.decode(b, at: i, limit: t.range.upperBound)
                scalars.append(scalar)
                for _ in 0..<scalar.utf16.count { unitByte.append(i) }
                i += len
            }
        }
        let text = String(scalars)
        var styleAtByte: [Int: HighlightStyle] = [:]
        // (si la línea entra o sale de pantalla completa, tampoco se toca)
        let toggles = tokens.contains { $0.isEscape && Self.altToggle(Array(b[$0.range])) != nil }
        if !altScreen, !toggles, b.count <= maxLine, text.contains(where: { $0.isLetter || $0.isNumber }) {
            let styles = match(text, utf16Count: unitByte.count)
            for (u, s) in styles.enumerated() where s != nil { styleAtByte[unitByte[u]] = s }
        }
        // salida: abrir/cerrar nuestros estilos; las secuencias del equipo, tal cual
        var out: [UInt8] = []
        var open: HighlightStyle?
        func close() {
            guard open != nil else { return }
            out += Array("\u{1b}[0m".utf8)
            deviceSGR.forEach { out += $0 }
            open = nil
        }
        for t in tokens {
            if t.isEscape {
                close()
                let seq = Array(b[t.range])
                track(seq)
                out += seq
                continue
            }
            var i = t.range.lowerBound
            while i < t.range.upperBound {
                let (_, len) = Self.decode(b, at: i, limit: t.range.upperBound)
                let s = styleAtByte[i]
                if s != open {
                    close()
                    if let s { out += sgr(s); open = s }
                }
                if b[i] == 10 || b[i] == 13 { close() }
                out += b[i..<(i + len)]
                i += len
            }
        }
        close()
        return out
    }

    /// Estilo de cada unidad UTF-16 del texto (nil = sin resaltar). Por orden de reglas: la primera gana; una
    /// exclusiva reserva su zona para que no la coloree ninguna de después.
    private func match(_ text: String, utf16Count n: Int) -> [HighlightStyle?] {
        var styles = [HighlightStyle?](repeating: nil, count: n)
        var taken = [Bool](repeating: false, count: n)
        for rule in rules {
            for m in rule.regex.allMatches(text) {
                let whole = m.range
                guard whole.length > 0, whole.location + whole.length <= n else { continue }
                if (whole.location..<(whole.location + whole.length)).contains(where: { taken[$0] }) { continue }
                for (g, style) in rule.styles where g < m.numberOfRanges {
                    let r = m.range(at: g)
                    guard r.location != NSNotFound, r.length > 0 else { continue }
                    for u in r.location..<min(n, r.location + r.length) where styles[u] == nil { styles[u] = style }
                }
                if rule.exclusive { for u in whole.location..<(whole.location + whole.length) { taken[u] = true } }
            }
        }
        return styles
    }

    private func sgr(_ s: HighlightStyle) -> [UInt8] {
        var p: [String] = []
        if s.bold { p.append("1") }
        if s.italic { p.append("3") }
        if s.underline { p.append("4") }
        if let c = s.foreground.flatMap(color) { p.append("38;2;\(Int(c.r));\(Int(c.g));\(Int(c.b))") }
        if let c = s.background.flatMap(color) { p.append("48;2;\(Int(c.r));\(Int(c.g));\(Int(c.b))") }
        return p.isEmpty ? [] : Array("\u{1b}[\(p.joined(separator: ";"))m".utf8)
    }

    private func color(_ name: String) -> RGB? { palette[name] ?? RGB(hex: name) }

    // MARK: - lo que pone el equipo

    private func trackOnly(_ data: [UInt8]) {
        for t in Self.tokenize(data) where t.isEscape { track(Array(data[t.range])) }
    }

    /// Colores del equipo (para restaurarlos) y pantalla completa (para no tocarla).
    private func track(_ seq: [UInt8]) {
        guard seq.count >= 3, seq[0] == 0x1B, seq[1] == UInt8(ascii: "[") else { return }
        if let on = Self.altToggle(seq) { altScreen = on; return }
        let body = String(decoding: seq[2...], as: UTF8.self)
        if body.hasPrefix("?") { return }
        guard body.hasSuffix("m") else { return }
        let params = body.dropLast()
        if params.isEmpty || params == "0" || params.hasPrefix("0;") || params == "00" {
            deviceSGR = []
            if params.hasPrefix("0;") { deviceSGR.append(Array("\u{1b}[\(params.dropFirst(2))m".utf8)) }
        } else {
            deviceSGR.append(seq)
            if deviceSGR.count > 8 { deviceSGR.removeFirst() }
        }
    }

    // MARK: - bytes

    /// «ESC [ ? 1049 h» (entra en pantalla completa) → true; «… l» → false; otra cosa → nil.
    static func altToggle(_ seq: [UInt8]) -> Bool? {
        guard seq.count >= 4, seq[0] == 0x1B, seq[1] == UInt8(ascii: "["), seq[2] == UInt8(ascii: "?"),
              let last = seq.last, last == UInt8(ascii: "h") || last == UInt8(ascii: "l") else { return nil }
        let params = String(decoding: seq[3..<(seq.count - 1)], as: UTF8.self).split(separator: ";")
        return params.contains { ["1049", "1047", "47"].contains($0) } ? last == UInt8(ascii: "h") : nil
    }

    /// Trozos de texto y secuencias de escape (CSI, OSC, DCS y ESC + carácter).
    private static func tokenize(_ b: [UInt8]) -> [Token] {
        var out: [Token] = []
        var i = 0, textStart = 0
        func text(_ end: Int) { if end > textStart { out.append(Token(range: textStart..<end, isEscape: false)) } }
        while i < b.count {
            guard b[i] == 0x1B else { i += 1; continue }
            text(i)
            let end = escapeEnd(b, from: i) ?? b.count
            out.append(Token(range: i..<end, isEscape: true))
            i = end
            textStart = i
        }
        text(b.count)
        return out
    }

    /// Fin (exclusivo) de la secuencia que empieza en `i`, o nil si está a medias.
    static func escapeEnd(_ b: [UInt8], from i: Int) -> Int? {
        guard i + 1 < b.count else { return nil }
        switch b[i + 1] {
        case UInt8(ascii: "["):
            var j = i + 2
            while j < b.count {
                if (0x40...0x7E).contains(b[j]) { return j + 1 }
                j += 1
            }
            return nil
        case UInt8(ascii: "]"), UInt8(ascii: "P"), UInt8(ascii: "_"), UInt8(ascii: "^"):
            var j = i + 2
            while j < b.count {
                if b[j] == 0x07 { return j + 1 }
                if b[j] == 0x1B, j + 1 < b.count, b[j + 1] == UInt8(ascii: "\\") { return j + 2 }
                j += 1
            }
            return nil
        case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "#"), UInt8(ascii: "%"):
            return i + 2 < b.count ? i + 3 : nil
        default:
            return i + 2
        }
    }

    /// Cuántos bytes del final hay que guardar: una secuencia de escape o un carácter UTF-8 a medias.
    static func incompleteTail(_ b: [UInt8]) -> Int {
        if let esc = b.lastIndex(of: 0x1B), b.count - esc <= 64, escapeEnd(b, from: esc) == nil { return b.count - esc }
        var i = b.count - 1, n = 0
        while i >= 0, n < 4, b[i] & 0xC0 == 0x80 { i -= 1; n += 1 }
        guard i >= 0 else { return 0 }
        let need = b[i] >= 0xF0 ? 4 : b[i] >= 0xE0 ? 3 : b[i] >= 0xC0 ? 2 : 1
        return need > n + 1 ? n + 1 : 0
    }

    /// Un escalar UTF-8 (uno inválido cuenta como U+FFFD de un byte).
    static func decode(_ b: [UInt8], at i: Int, limit: Int) -> (Unicode.Scalar, Int) {
        let c = b[i]
        let len = c < 0x80 ? 1 : c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 0
        guard len > 0, i + len <= limit else { return (Unicode.Scalar(0xFFFD)!, 1) }
        if len == 1 { return (Unicode.Scalar(c), 1) }
        var v = UInt32(c) & (len == 2 ? 0x1F : len == 3 ? 0x0F : 0x07)
        for k in 1..<len {
            guard b[i + k] & 0xC0 == 0x80 else { return (Unicode.Scalar(0xFFFD)!, 1) }
            v = v << 6 | UInt32(b[i + k] & 0x3F)
        }
        return (Unicode.Scalar(v) ?? Unicode.Scalar(0xFFFD)!, len)
    }
}

extension Pattern {
    /// Todos los aciertos (rangos en UTF-16).
    func allMatches(_ s: String) -> [NSTextCheckingResult] {
        regex.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
}
