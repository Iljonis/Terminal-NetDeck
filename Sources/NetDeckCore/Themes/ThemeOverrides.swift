import Foundation

/// Colores a medida de un tema (Ajustes → Temas → «Personalizar colores»): una capa encima del tema, como
/// `workbench.colorCustomizations` de VS Code o `palette =` de Ghostty. El .tema no se toca; lo que no se cambia sigue
/// saliendo de él (los ANSI que no se fijan, también del fondo y el texto nuevos). Se guarda por id de tema en Ajustes
/// como `[clave: «#rrggbb»]`, con las mismas claves que el .tema.
public struct ThemeOverrides: Hashable, Sendable {
    /// Los colores que se pueden cambiar (los ANSI aparte: «ansi0»…«ansi15»).
    public static let colorKeys = ["fondo", "texto", "acento", "acento2", "pestaña", "selección", "cursor"]
    public static let ansiKeys = (0..<16).map { "ansi\($0)" }
    /// Opacidad del fondo (0,2…1), sólo en los temas de cristal.
    public static let opacityKey = "opacidad"
    public static let opacityRange = 0.2...1.0

    /// Clave → color (opaco: la transparencia del tema se conserva).
    public private(set) var colors: [String: RGB] = [:]
    public private(set) var opacity: Double?

    public init() {}

    /// Desde Ajustes: lo que no es una clave conocida, un #hex válido o una opacidad en su rango se ignora.
    public init(_ dict: [String: String]) {
        for (k, v) in dict {
            if k == Self.opacityKey {
                if let o = Double(v.trimmed), Self.opacityRange.contains(o) { opacity = o }
            } else if Self.colorKeys.contains(k) || Self.ansiKeys.contains(k), let c = RGB(hex: v) {
                colors[k] = c.opaque.rounded
            }
        }
    }

    /// Para Ajustes (ida y vuelta con `init(_:)`).
    public var dictionary: [String: String] {
        var d = colors.mapValues(\.description)
        if let opacity { d[Self.opacityKey] = String(format: "%.2f", opacity) }
        return d
    }

    public var isEmpty: Bool { colors.isEmpty && opacity == nil }

    public subscript(key: String) -> RGB? {
        get { colors[key] }
        set {
            guard Self.colorKeys.contains(key) || Self.ansiKeys.contains(key) else { return }
            colors[key] = newValue?.opaque.rounded
        }
    }

    public mutating func setOpacity(_ v: Double?) {
        opacity = v.map { min(max($0, Self.opacityRange.lowerBound), Self.opacityRange.upperBound) }
    }

    /// El tema con estos cambios (sólo los dados). Cada color guarda la transparencia que tenía en el tema; la
    /// opacidad, sólo en los de cristal, y redondeada a lo que cabe en «#rrggbbaa».
    public func apply(to theme: Theme) -> Theme {
        var t = theme
        let paths: [(String, WritableKeyPath<Theme, RGB>)] = [("fondo", \.background), ("texto", \.text),
            ("acento", \.accent), ("acento2", \.accent2), ("pestaña", \.tab)]
        for (k, p) in paths { if let c = colors[k] { t[keyPath: p] = c.alpha(theme[keyPath: p].a) } }
        if let o = opacity, t.isTranslucent { t.background.a = (o * 255).rounded() / 255 }
        if let c = colors["selección"] { t.selectionColor = c }
        if let c = colors["cursor"] { t.cursorColor = c }
        let ansi = Self.ansiKeys.enumerated().compactMap { i, k in colors[k].map { (i, $0) } }
        if !ansi.isEmpty {
            var a = t.ansi.map(\.rounded)       // (los demás, del tema ya cambiado)
            for (i, c) in ansi { a[i] = c }
            t.explicitANSI = a
        }
        return t
    }

    /// El tema que se ve: con sus colores a medida y, si el Mac pide «Reducir transparencia» o «Aumentar contraste»,
    /// opaco (`Theme.solid`). El único sitio donde se juntan las dos cosas: barra, pestañas, menús y terminal lo
    /// sacan de aquí (`ThemeStore`).
    public static func effective(_ theme: Theme, _ overrides: ThemeOverrides?, solid: Bool) -> Theme {
        let t = overrides.map { $0.apply(to: theme) } ?? theme
        return solid ? t.solid : t
    }

    /// Sin los cambios de los temas que ya no están (se quitó el importado o se borró el archivo).
    public static func pruned(_ all: [String: [String: String]], keeping ids: Set<String>) -> [String: [String: String]] {
        all.filter { ids.contains($0.key) && !ThemeOverrides($0.value).isEmpty }
    }

    /// Lo que se lee mal en el tema (aviso, no impide nada): con el mínimo de los temas de la app (ThemeTests): texto y
    /// pestaña activa ≥ 4,5:1; los ANSI de primer plano (1–6, 9–14) y el cursor ≥ 3:1 sobre el fondo.
    public struct ContrastWarning: Hashable, Sendable {
        public let key: String
        public let ratio: Double
        public let minimum: Double
    }

    public static func contrastWarnings(_ t: Theme) -> [ContrastWarning] {
        let bg = t.background.opaque
        var checks: [(String, RGB, RGB, Double)] = [("texto", t.text, bg, 4.5), ("pestaña", t.onTab, t.tab, 4.5),
                                                   ("cursor", t.cursor, bg, 3)]
        let ansi = t.ansi
        for i in Array(1...6) + Array(9...14) { checks.append(("ansi\(i)", ansi[i], bg, 3)) }
        return checks.compactMap { k, a, b, m in
            let r = a.opaque.contraste(b.opaque)
            return r < m ? ContrastWarning(key: k, ratio: r, minimum: m) : nil
        }
    }
}

extension RGB {
    /// Con cada componente entero (lo que guarda un «#rrggbb»): así el .tema exportado vuelve igual.
    var rounded: RGB { RGB(r.rounded(), g.rounded(), b.rounded(), a) }

    /// «#rrggbb», o «#rrggbbaa» si es transparente (el formato del .tema).
    public var temaHex: String {
        a < 1 ? description + String(format: "%02x", Int((a * 255).rounded())) : description
    }
}

extension Theme {
    /// El .tema de este tema (para «Exportar .tema…» y «Guardar como tema nuevo…»): vuelve a leerse igual.
    public var temaText: String {
        var lines = ["# \(name) — \(summary)", "", "nombre    = \(name)", "grupo     = \(group)", "orden     = \(order)",
                     "estilo    = \(style.rawValue)"]
        if let material { lines.append("material  = \(material)") }
        if glowing { lines.append("brillo    = sí") }
        if let glassTint { lines.append("tinte     = \(glassTint.temaHex)") }
        lines.append("fuentes   = \(fonts.joined(separator: ", "))")
        if !uiFonts.isEmpty { lines.append("fuente_interfaz = \(uiFonts.joined(separator: ", "))") }
        lines += ["tamaño    = \(size)", ""]
        let colores: [(String, RGB)] = [("fondo", background), ("texto", text), ("barra", bar), ("panel", panel),
            ("pestaña", tab), ("sobre_pestaña", onTab), ("acento", accent), ("acento2", accent2), ("bien", good),
            ("mal", bad), ("especial", special), ("apagado", dim)]
        for (k, c) in colores { lines.append(k.padding(toLength: 14, withPad: " ", startingAt: 0) + "= " + c.temaHex) }
        if let selectionColor { lines.append("selección     = \(selectionColor.temaHex)") }
        if let cursorColor { lines.append("cursor        = \(cursorColor.temaHex)") }
        lines += ["menu          = \(menu)", "reloj         = \(clock)"]
        if let e = explicitANSI, e.count == 16 { lines.append("ansi          = " + e.map(\.temaHex).joined(separator: ", ")) }
        if !highlightColors.isEmpty {
            lines.append("resaltado     = " + highlightColors.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.temaHex)" }
                .joined(separator: ", "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// El id (y nombre del archivo) de un tema nuevo con ese nombre: «Mi Tema Ñ» → «mi-tema-n». nil si el nombre no
    /// vale: vacío, empieza por «-» o lleva «#» o un salto de línea (romperían el .tema).
    public static func fileID(forName name: String) -> String? {
        let n = name.trimmed
        guard !n.isEmpty, !n.hasPrefix("-"), !n.contains("#"), !n.contains(where: \.isNewline) else { return nil }
        let id = n.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return id.isEmpty ? nil : id
    }
}

extension ThemeLibrary {
    public enum SaveError: LocalizedError, Equatable {
        case badName
        case exists(String)

        public var errorDescription: String? {
            switch self {
            case .badName: L("El nombre no vale: no puede estar vacío, empezar por «-» ni llevar «#»")
            case .exists(let n): L("Ya hay un tema «\(n)»: elige otro nombre")
            }
        }
    }

    /// Guarda `theme` (con sus colores a medida ya puestos) como un tema nuevo llamado `name` entre los importados,
    /// con SafeFile. No pisa ninguno que ya exista. Devuelve el tema tal como se ha guardado.
    @discardableResult
    public func saveNew(_ theme: Theme, name: String) throws -> Theme {
        guard let id = Theme.fileID(forName: name) else { throw SaveError.badName }
        if let other = all().first(where: { $0.theme.id == id })?.theme { throw SaveError.exists(other.name) }
        var t = theme
        t.id = id
        t.name = name.trimmed
        t.summary = "A medida, a partir de «\(theme.name)»"     // (se guarda en el archivo: en castellano)
        let url = AppPaths.ensure(importDirectory).appendingPathComponent("\(id).tema")
        try SafeFile.backup(url)
        try SafeFile.write(t.temaText, to: url)
        return try Theme(contentsOf: url)
    }
}
