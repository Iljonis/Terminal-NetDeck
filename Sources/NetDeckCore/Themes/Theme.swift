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
    /// Ya pintado encima de `base` (opaco): lo que se ve de un color con transparencia.
    public func over(_ base: RGB) -> RGB { base.opaque.mix(opaque, a) }

    /// Desde HSL (matiz 0…360, saturación y luz 0…1).
    public init(hue h: Double, saturation s: Double, lightness l: Double) {
        let c = (1 - abs(2 * l - 1)) * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = l - c / 2
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        self.init((r + m) * 255, (g + m) * 255, (b + m) * 255)
    }

    /// Saturación y luz HSL (0…1).
    public var saturationLightness: (s: Double, l: Double) {
        let mx = max(r, g, b) / 255, mn = min(r, g, b) / 255, l = (mx + mn) / 2
        return (mx == mn ? 0 : (mx - mn) / (1 - abs(2 * l - 1)), l)
    }

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
    public static let groups = ["Cyberpunk", "Neon Glass", "Sistemas", "Anime y cine", "Ciencia ficción", "Kawaii", "Retro",
                                "Ordenadores clásicos", "Videojuegos retro", "Naturaleza", "Sobrias", "Prácticas",
                                "Centro de datos", "Corporativas"]
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
    /// «brillo = sí»: el halo de neón también fuera del estilo neón (los Neon Glass, de cristal).
    public var glowing = false
    /// «tinte = #rrggbbaa»: el color del cristal de pestañas y botones (si no, el gris de macOS).
    public var glassTint: RGB?
    /// Los 16 colores ANSI tal cual (si no, salen de los del tema).
    public var explicitANSI: [RGB]?
    /// «resaltado = green #2ecc71, blue #9b59b6…»: los colores con nombre del resaltado que fija el tema (los demás
    /// salen de sus colores, ver `highlightPalette`). Las reglas no cambian: siguen diciendo «f.green», «f.blue»…
    public var highlightColors: [String: RGB] = [:]
    /// «selección» y «cursor» del terminal, si el tema (o sus colores a medida, `ThemeOverrides`) los fija.
    public var selectionColor: RGB?
    public var cursorColor: RGB?
    /// «filtro = crt|lcd|fosforo|holograma»: el filtro de pantalla del tema (`ScreenFilter`); nil = sin filtro.
    public var screenFilter: ScreenFilter?

    public var isTranslucent: Bool { background.a < 1 || material != nil }
    /// Fondo de lo que va encima del de la ventana: transparente en los temas de cristal (que no se acumule).
    public var layer: RGB { isTranslucent ? background.alpha(0) : background }

    /// Sin transparencias ni desenfoque, para «Reducir transparencia» o «Aumentar contraste» (Accesibilidad): cada
    /// color, ya pintado sobre el fondo opaco, como se ve en un tema normal.
    public var solid: Theme {
        guard isTranslucent else { return self }
        var t = self
        let bg = background.opaque
        t.background = bg
        t.material = nil
        t.glassTint = nil                                    // (sin cristal, el relleno de siempre)
        for k in [\Theme.text, \.bar, \.panel, \.tab, \.accent, \.accent2, \.good, \.bad, \.special, \.dim] {
            t[keyPath: k] = self[keyPath: k].over(bg)
        }
        t.onTab = onTab.over(t.tab)
        return t
    }

    public var isLight: Bool { background.opaque.luminance > 0.5 }
    /// Naranja de aviso (y «f.orange» del resaltado). El de siempre (mal + acento, o un ocre en los claros) si ya se ve
    /// naranja y se lee; si no (con un acento azul o verde salía gris malva: Cisco, NOC, Liquid Glass…), un naranja de
    /// verdad: matiz 30°, la saturación de «mal» (al menos 75 %) y la luz que haga falta para ≥ 4,5:1 sobre el fondo.
    /// Con un «mal» que ya es naranja (Grid), más claro, para no confundirse con él.
    public var warning: RGB {
        let bg = background.opaque
        let mixed = (isLight ? bad.mix(RGB(179, 89, 0), 0.5) : bad.mix(accent, 0.5)).over(bg)
        if mixed.tono.tono == .naranja, mixed.contraste(bg) >= 4.5 { return mixed }
        let (s, l) = bad.opaque.saturationLightness
        var luz = min(max(l, 0.40), 0.62) + (bad.opaque.tono.tono == .naranja ? 0.15 : 0)
        var c = RGB(hue: 30, saturation: max(s, 0.75), lightness: luz)
        while c.contraste(bg) < 4.5, luz > 0.05, luz < 0.95 {
            luz += isLight ? -0.01 : 0.01
            c = RGB(hue: 30, saturation: max(s, 0.75), lightness: luz)
        }
        return c
    }
    public var blue: RGB { accent2.mix(special, 0.45) }
    public var line: RGB { panel.mix(text, 0.18) }
    public var selection: RGB { selectionColor ?? background.opaque.mix(special, 0.45) }
    public var cursor: RGB { cursorColor ?? accent }

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
        size = min(max(Int(v["tamaño"] ?? "") ?? 14, 1), 200)   // un valor enorme desbordaría al calcular la fuente
        menu = v["menu"] ?? "☰ Menú"
        clock = v["reloj"] ?? "%H:%M"
        style = Style(rawValue: (v["estilo"] ?? "").lowercased().replacingOccurrences(of: "ó", with: "o")) ?? .neon
        material = v["material"].flatMap { ["cristal", "mica"].contains($0.lowercased()) ? $0.lowercased() : nil }
        glowing = ["sí", "si", "yes", "true", "1"].contains((v["brillo"] ?? "").lowercased())
        glassTint = v["tinte"].flatMap(RGB.init(hex:))
        uiFonts = (v["fuente_interfaz"] ?? "").split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        let ansiList = (v["ansi"] ?? "").split(separator: ",").compactMap { RGB(hex: String($0)) }
        explicitANSI = ansiList.count == 16 ? ansiList : nil
        highlightColors = Self.highlightColors(v["resaltado"] ?? "")
        selectionColor = (v["selección"] ?? v["seleccion"]).flatMap(RGB.init(hex:))
        cursorColor = v["cursor"].flatMap(RGB.init(hex:))
        screenFilter = ScreenFilter(tema: v["filtro"])
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

    /// «green #2ecc71, red #e74c3c»: sólo los nombres que entiende el resaltado y con un #hex válido (lo demás se ignora).
    static func highlightColors(_ text: String) -> [String: RGB] {
        var out: [String: RGB] = [:]
        for item in text.split(separator: ",") {
            let parts = item.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == 2, HighlightStyle.colorNames.contains(parts[0].lowercased()),
                  let c = RGB(hex: parts[1]) else { continue }
            out[parts[0].lowercased()] = c
        }
        return out
    }

    public init(contentsOf url: URL) throws {
        try self.init(id: url.deletingPathExtension().lastPathComponent, text: String(contentsOf: url, encoding: .utf8))
    }

    /// El de serie para quien empieza (desde 1.0.0): Liquid Glass, y su versión clara para el modo automático. Viene
    /// con la app (Temas/); si faltara, se usa `builtIn`, que siempre está.
    public static let defaultID = "liquid-glass"
    public static let defaultLightID = "liquid-glass-claro"

    /// Los temas (fijo, claro y oscuro del automático) de quien aún no ha elegido. Quien ya usaba una 0.9 sigue con los
    /// de entonces aunque nunca los eligiera (NetDeck Cyberpunk y Papel): actualizar no le cambia el aspecto.
    public static func startingIDs(previousUser: Bool) -> (fixed: String, light: String, dark: String) {
        previousUser ? (builtIn.id, "papel", builtIn.id) : (defaultID, defaultLightID, defaultID)
    }

    /// Los de neón de NetDeck que el asistente sugiere aparte: el de siempre (`builtIn`) y los del grupo Cyberpunk con
    /// estilo neón, en su orden.
    public static func neonSuggestions(in themes: [Theme]) -> [Theme] {
        themes.filter { $0.style == .neon && $0.group == "Cyberpunk" }
            .sorted { ($0.id == builtIn.id ? 0 : 1, $0.order, $0.name) < ($1.id == builtIn.id ? 0 : 1, $1.order, $1.name) }
    }

    /// La original (siempre está, aunque no haya ninguna instalada): cyberpunk índigo, magenta y cian.
    public static let builtIn = try! Theme(id: "netdeck-cyberpunk", text: """
        # NetDeck Cyberpunk — La original de NetDeck (y la de reserva si falta un tema): índigo profundo, magenta y cian.
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
