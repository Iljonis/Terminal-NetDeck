import Foundation

/// Perfil de terminal de una sesión: fuente, colores (tema), historial, teclado y prompt. Va en su bloque del ssh_config
/// de la app, como el resto de anotaciones (nada de un JSON aparte):
///   # @fuente Menlo 13          familia y/o tamaño («# @fuente 14», «# @fuente JetBrains Mono»)
///   # @tema neo-tokyo           id del tema
///   # @scrollback 10000         líneas de historial (dentro de `TerminalHistory.range`)
///   # @teclado meta retroceso-h ⌥ como Meta (o «sin-meta») y Retroceso con ^H (o «retroceso-del»)
///   # @prompt ^core-\d+[#>]$    regex del prompt del equipo (en vez del genérico)
/// Lo que no se indica hereda de Ajustes; un valor que no vale se ignora (también hereda) con aviso en ErrorLog.
public struct TerminalProfile: Hashable, Sendable {
    /// "" = la de Ajustes.
    public var fontFamily = ""
    /// 0 = el de Ajustes.
    public var fontSize: Double = 0
    /// id del tema; "" = el de Ajustes.
    public var theme = ""
    /// nil = el de Ajustes.
    public var scrollback: Int?
    /// ⌥ como Meta (Esc + tecla). nil = como siempre: no (⌥ para «@», «#», «|» en teclado español).
    public var optionAsMeta: Bool?
    /// Retroceso envía ^H (true) o DEL (false). nil = como siempre: DEL.
    public var backspaceSendsCtrlH: Bool?
    /// Regex del prompt del equipo (`PromptRule`); "" = el genérico.
    public var prompt = ""

    public static let keys = ["fuente", "tema", "scrollback", "teclado", "prompt"]
    public static let fontSizes = 8.0...36.0
    static let maxFamilyLength = 100
    static let themeID = Pattern(#"^[^\s"'`$\\]{1,80}$"#, ignoreCase: false)

    public init() {}

    /// Todo hereda.
    public var isEmpty: Bool { self == TerminalProfile() }

    // MARK: - anotaciones

    /// Las anotaciones de la sesión en orden («fuente», «Menlo 13»…), sólo las que no heredan.
    public var annotations: [(key: String, value: String)] {
        var out: [(String, String)] = []
        let size = fontSize > 0 ? String(Int(fontSize)) : ""
        let font = [fontFamily, size].filter { !$0.isEmpty }.joined(separator: " ")
        if !font.isEmpty { out.append(("fuente", font)) }
        if !theme.isEmpty { out.append(("tema", theme)) }
        if let scrollback { out.append(("scrollback", String(scrollback))) }
        let keys = [optionAsMeta.map { $0 ? "meta" : "sin-meta" }, backspaceSendsCtrlH.map { $0 ? "retroceso-h" : "retroceso-del" }]
            .compactMap { $0 }
        if !keys.isEmpty { out.append(("teclado", keys.joined(separator: " "))) }
        if !prompt.isEmpty { out.append(("prompt", prompt)) }
        return out
    }

    /// ¿Lo dice ya? (en el archivo, la primera anotación de cada clave gana: como `SSHConfigParser`)
    public func has(_ key: String) -> Bool { annotations.contains { $0.key == key } }

    /// Lee una anotación («fuente», «Menlo 13»). false si la clave no es del perfil; si el valor no vale, se ignora
    /// (hereda) con aviso en ErrorLog: un archivo editado a mano no rompe la carga.
    @discardableResult
    public mutating func read(_ key: String, _ value: String, session: String) -> Bool {
        guard Self.keys.contains(key) else { return false }
        let v = value.trimmed
        var next = self
        if let why = next.parse(key, v) {
            Self.warn("«\(session)»: «# @\(key) \(v.prefix(80))» no vale (\(why)): se usa el de Ajustes")
        } else {
            self = next
        }
        return true
    }

    /// nil si vale (y lo deja puesto); si no, por qué (para el registro: sin traducir).
    private mutating func parse(_ key: String, _ v: String) -> String? {
        guard !SessionFile.hasControl(v) else { return "caracteres de control" }
        switch key {
        case "fuente":
            var words = v.split(whereSeparator: \.isWhitespace).map(String.init)
            var size: Double = 0
            if let last = words.last, let n = Double(last) {
                guard Self.fontSizes.contains(n) else { return "tamaño fuera de \(Int(Self.fontSizes.lowerBound))…\(Int(Self.fontSizes.upperBound))" }
                size = n.rounded()
                words.removeLast()
            }
            let family = words.joined(separator: " ")
            guard !family.isEmpty || size > 0 else { return "vacío" }
            guard family.count <= Self.maxFamilyLength, !family.contains("\"") else { return "familia no válida" }
            fontFamily = family
            fontSize = size
        case "tema":
            guard Self.themeID.matches(v) else { return "id no válido" }
            theme = v
        case "scrollback":
            guard let n = Int(v), TerminalHistory.range.contains(n) else {
                return "fuera de \(TerminalHistory.range.lowerBound)…\(TerminalHistory.range.upperBound)"
            }
            scrollback = n
        case "teclado":
            var meta: Bool?, ctrlH: Bool?
            for w in v.lowercased().split(whereSeparator: \.isWhitespace) {
                switch w {
                case "meta": meta = true
                case "sin-meta": meta = false
                case "retroceso-h": ctrlH = true
                case "retroceso-del": ctrlH = false
                default: return "«\(w)» no es meta, sin-meta, retroceso-h ni retroceso-del"
                }
            }
            guard meta != nil || ctrlH != nil else { return "vacío" }
            optionAsMeta = meta
            backspaceSendsCtrlH = ctrlH
        case "prompt":
            if let why = PromptRule.problem(v) { return why }
            prompt = v
        default:
            return "clave desconocida"
        }
        return nil
    }

    /// Qué está mal antes de guardar (lo escrito en el editor): mensajes para el usuario.
    public func problems() -> [String] {
        var out: [String] = []
        if SessionFile.hasControl(fontFamily) || fontFamily.contains("\"") || fontFamily.count > Self.maxFamilyLength {
            out.append(L("fuente «\(fontFamily)» no válida"))
        }
        if fontSize != 0, !Self.fontSizes.contains(fontSize) { out.append(L("tamaño de letra «\(Int(fontSize))»")) }
        if !theme.isEmpty, !Self.themeID.matches(theme) || SessionFile.hasControl(theme) { out.append(L("tema «\(theme)» no válido")) }
        if let n = scrollback, !TerminalHistory.range.contains(n) { out.append(L("historial «\(String(n))» fuera de lo admitido")) }
        if !prompt.isEmpty, let why = PromptRule.problem(prompt) { out.append(L("prompt: \(why)")) }
        return out
    }

    // MARK: - herencia

    /// Lo que vale de verdad en la pestaña: lo de la sesión y, lo que no dice (o ya no existe), de Ajustes.
    public struct Effective: Equatable, Sendable {
        public var theme: String
        /// "" = la del tema.
        public var fontFamily: String
        /// 0 = el del tema.
        public var fontSize: Double
        public var scrollback: Int
        public var optionAsMeta: Bool
        public var backspaceSendsCtrlH: Bool
        /// nil = el prompt genérico.
        public var prompt: PromptRule?
    }

    /// Con los valores de Ajustes. Un tema que ya no está o una fuente que no está instalada heredan (aviso en
    /// ErrorLog, una vez).
    public func resolved(theme globalTheme: String, fontFamily globalFamily: String, fontSize globalSize: Double,
                         scrollback globalScrollback: Int, session: String,
                         themeExists: (String) -> Bool, fontInstalled: (String) -> Bool) -> Effective {
        var e = Effective(theme: globalTheme, fontFamily: globalFamily, fontSize: globalSize, scrollback: globalScrollback,
                          optionAsMeta: optionAsMeta ?? false, backspaceSendsCtrlH: backspaceSendsCtrlH ?? false,
                          prompt: prompt.isEmpty ? nil : PromptRule(prompt))
        if !theme.isEmpty {
            if themeExists(theme) { e.theme = theme } else { Self.warn("«\(session)»: el tema «\(theme)» no existe: se usa el de Ajustes") }
        }
        if !fontFamily.isEmpty {
            if fontInstalled(fontFamily) { e.fontFamily = fontFamily }
            else { Self.warn("«\(session)»: la fuente «\(fontFamily)» no está instalada: se usa la de Ajustes") }
        }
        if fontSize > 0 { e.fontSize = fontSize }
        if let scrollback { e.scrollback = scrollback }
        return e
    }

    // MARK: - avisos

    private static let warnedLock = NSLock()
    nonisolated(unsafe) private static var warned = Set<String>()

    /// Al ErrorLog, una vez por mensaje (las sesiones se vuelven a leer a menudo).
    static func warn(_ message: String) {
        let first = warnedLock.withLock { warned.insert(message).inserted }
        if first { ErrorLog.warning("perfil", message) }
    }
}
