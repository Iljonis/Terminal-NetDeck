import Foundation

/// Color #rrggbb (o #rrggbbaa: con transparencia, para los temas de cristal).
public struct RGB: Hashable, Sendable, CustomStringConvertible {
    public var r, g, b: Double                                   // 0…255
    /// 0…1 (1 = opaco).
    public var a: Double = 1

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init?(hex: String) {
        let h = hex.trimmed.hasPrefix("#") ? String(hex.trimmed.dropFirst()) : hex.trimmed
        guard h.count == 6 || h.count == 8, let v = UInt32(h, radix: 16) else { return nil }
        let rgb = h.count == 8 ? v >> 8 : v
        self.init(Double(rgb >> 16 & 0xFF), Double(rgb >> 8 & 0xFF), Double(rgb & 0xFF), h.count == 8 ? Double(v & 0xFF) / 255 : 1)
    }

    public var description: String { String(format: "#%02x%02x%02x", Int(r.rounded()), Int(g.rounded()), Int(b.rounded())) }

    public var opaque: RGB { RGB(r, g, b) }
    public func alpha(_ v: Double) -> RGB { RGB(r, g, b, v) }

    /// Mezcla con `o` (t = 0 → éste, 1 → o).
    public func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t, a + (o.a - a) * t) }

    /// Luminancia relativa (WCAG).
    public var luminance: Double {
        func c(_ v: Double) -> Double { let v = v / 255; return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * c(r) + 0.7152 * c(g) + 0.0722 * c(b)
    }

    /// Texto legible encima de este color.
    public var readable: RGB { luminance > 0.35 ? RGB(11, 11, 12) : RGB(255, 255, 255) }

    public static let white = RGB(255, 255, 255)
    public static let black = RGB(0, 0, 0)
}

/// Una temática de NetDeck: el mismo formato .tema («clave = valor  # comentario»), así que las de NetDeck valen tal cual.
public struct Theme: Identifiable, Hashable, Sendable {
    public static let groups = ["Cyberpunk", "Sistemas", "Anime y cine", "Kawaii", "Retro", "Sobrias", "Prácticas", "Corporativas"]
    static let colorKeys = ["fondo", "texto", "barra", "panel", "pestaña", "sobre_pestaña", "acento", "acento2", "bien",
                            "mal", "especial", "apagado"]

    public var id: String
    public var name: String
    public var group: String
    public var order: String
    public var summary: String
    /// La 1ª es la oficial; las otras, recomendadas.
    public var fonts: [String]
    public var size: Int
    public var menu: String
    public var clock: String

    public var background: RGB      // fondo
    public var text: RGB            // texto
    public var bar: RGB             // barra
    public var panel: RGB           // panel
    public var tab: RGB             // pestaña
    public var onTab: RGB           // sobre_pestaña
    public var accent: RGB          // acento
    public var accent2: RGB         // acento2
    public var good: RGB            // bien
    public var bad: RGB             // mal
    public var special: RGB         // especial
    public var dim: RGB             // apagado

    /// Cómo se dibuja la interfaz: «neon» (NetDeck), «cristal» (macOS Liquid Glass) o «fluent» (Windows 11).
    public enum Style: String, Sendable { case neon, glass = "cristal", fluent }
    public var style = Style.neon
    /// Fondo detrás de la ventana: «cristal» (desenfoque transparente) o «mica» (Windows 11); nil = opaco.
    public var material: String?
    /// Letra de la interfaz (si no, la del terminal): «sistema» = la del Mac (SF Pro).
    public var uiFonts: [String] = []
    /// Los 16 colores ANSI tal cual (si no, salen de los del tema).
    public var explicitANSI: [RGB]?

    public var isTranslucent: Bool { background.a < 1 || material != nil }
    /// Fondo de lo que va encima del de la ventana: transparente en los temas de cristal (que no se acumule).
    public var layer: RGB { isTranslucent ? background.alpha(0) : background }

    public var isLight: Bool { background.opaque.luminance > 0.5 }
    public var warning: RGB { isLight ? bad.mix(RGB(179, 89, 0), 0.5) : bad.mix(accent, 0.5) }
    public var blue: RGB { accent2.mix(special, 0.45) }
    public var line: RGB { panel.mix(text, 0.18) }
    public var selection: RGB { background.opaque.mix(special, 0.45) }

    /// Los 16 colores ANSI del terminal, sacados de la temática.
    public var ansi: [RGB] {
        if let e = explicitANSI, e.count == 16 { return e.map(\.opaque) }
        let base = [background.mix(text, 0.12), bad, good, accent, blue, special, accent2, text.mix(background, 0.15)]
        let towards = isLight ? RGB.black : RGB.white
        return (base + [dim] + base[1...6].map { $0.mix(towards, 0.25) } + [text]).map(\.opaque)
    }

    // MARK: - leer

    public enum ParseError: LocalizedError, Equatable {
        case badColor(String)

        public var errorDescription: String? {
            switch self { case .badColor(let k): L("falta o está mal el color «\(k)» (formato #rrggbb)") }
        }
    }

    public init(id: String, text source: String) throws {
        var v: [String: String] = [:]
        var desc = ""
        let comment = Pattern(#"\s{2,}#\s.*$"#, ignoreCase: false)
        for (n, line) in source.components(separatedBy: .newlines).enumerated() {
            if n == 0, line.hasPrefix("#") { desc = line.components(separatedBy: "—").last?.trimmed ?? "" }
            let t = line.trimmed
            guard !t.isEmpty, !t.hasPrefix("#"), t.contains("=") else { continue }
            let (k, _, raw) = t.partition("=")
            var value = raw.trimmed
            if let r = comment.range(in: value) { value = String(value[..<r.lowerBound]).trimmed }
            v[k.trimmed] = value
        }
        var colors: [String: RGB] = [:]
        for k in Self.colorKeys {
            guard let c = v[k].flatMap(RGB.init(hex:)) else { throw ParseError.badColor(k) }
            colors[k] = c
        }
        self.id = id
        name = v["nombre"] ?? id
        group = v["grupo"] ?? ""
        order = v["orden"] ?? "99"
        summary = desc
        fonts = (v["fuentes"] ?? "Space Mono").split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        size = Int(v["tamaño"] ?? "") ?? 14
        menu = v["menu"] ?? "☰ Menú"
        clock = v["reloj"] ?? "%H:%M"
        style = Style(rawValue: (v["estilo"] ?? "").lowercased().replacingOccurrences(of: "ó", with: "o")) ?? .neon
        material = v["material"].flatMap { ["cristal", "mica"].contains($0.lowercased()) ? $0.lowercased() : nil }
        uiFonts = (v["fuente_interfaz"] ?? "").split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        let ansiList = (v["ansi"] ?? "").split(separator: ",").compactMap { RGB(hex: String($0)) }
        explicitANSI = ansiList.count == 16 ? ansiList : nil
        background = colors["fondo"]!
        text = colors["texto"]!
        bar = colors["barra"]!
        panel = colors["panel"]!
        tab = colors["pestaña"]!
        onTab = colors["sobre_pestaña"]!
        accent = colors["acento"]!
        accent2 = colors["acento2"]!
        good = colors["bien"]!
        bad = colors["mal"]!
        special = colors["especial"]!
        dim = colors["apagado"]!
    }

    public init(contentsOf url: URL) throws {
        try self.init(id: url.deletingPathExtension().lastPathComponent, text: String(contentsOf: url, encoding: .utf8))
    }

    /// La de serie (siempre está, aunque no haya ninguna instalada): cyberpunk índigo, magenta y cian.
    public static let builtIn = try! Theme(id: "netdeck-cyberpunk", text: """
        # NetDeck Cyberpunk — La de serie: índigo profundo, magenta y cian.
        nombre    = NetDeck Cyberpunk
        grupo     = Cyberpunk
        orden     = 00
        fuentes   = JetBrains Mono, Kode Mono, Space Mono
        tamaño    = 13
        fondo         = #0b0a1f
        texto         = #e6e3ff
        barra         = #07061a
        panel         = #1a1740
        pestaña       = #ff2e88
        sobre_pestaña = #0b0a1f
        acento        = #00e5ff
        acento2       = #ff2e88
        bien          = #5cffb0
        mal           = #ff3b5c
        especial      = #b18cff
        apagado       = #6b66a8
        menu          = ☰ NETDECK
        reloj         = %H:%M
        """)

    /// Orden de NetDeck: por grupo, luego «orden», luego nombre.
    public static func sorted(_ themes: [Theme]) -> [Theme] {
        themes.sorted {
            let g0 = groups.firstIndex(of: $0.group) ?? 99, g1 = groups.firstIndex(of: $1.group) ?? 99
            return (g0, $0.order, $0.name) < (g1, $1.order, $1.name)
        }
    }

    /// «%H:%M 東京» → la hora con ese formato (strftime, como el reloj de NetDeck).
    public func clockText(_ date: Date = Date()) -> String {
        var t = time_t(date.timeIntervalSince1970)
        var tmv = tm()
        localtime_r(&t, &tmv)
        var buf = [CChar](repeating: 0, count: 128)
        let n = strftime(&buf, buf.count, clock, &tmv)
        return n > 0 ? String(decoding: buf[..<n].map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
    }
}
