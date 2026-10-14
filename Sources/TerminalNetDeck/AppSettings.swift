import AppKit
import NetDeckCore
import Observation

/// Ajustes (UserDefaults). La primera vez se importan los de NetDeck: contraseña por defecto, modo y temática.
@MainActor @Observable
final class AppSettings {
    @ObservationIgnored private let d = UserDefaults.standard

    /// La contraseña de la SESIÓN (su propio login y sus saltos) entra sola al abrirla (askpass).
    var sessionAutoPassword: Bool { didSet { d.set(sessionAutoPassword, forKey: "sessionAutoPassword") } }
    /// Las de los EQUIPOS a los que saltas desde una sesión («ssh equipo»): escribir sola, sugerir o nada.
    var devicePasswordMode: PasswordAutomation.Mode { didSet { d.set(devicePasswordMode.rawValue, forKey: "devicePasswordMode") } }
    var defaultCredentialName: String { didSet { d.set(defaultCredentialName, forKey: "defaultCredentialName") } }
    var defaultCredentialUser: String { didSet { d.set(defaultCredentialUser, forKey: "defaultCredentialUser") } }
    var themeID: String { didSet { d.set(themeID, forKey: "themeID") } }
    /// Como «tema auto» de NetDeck: uno de día y otro de noche, siguiendo al Mac.
    var themeAuto: Bool { didSet { d.set(themeAuto, forKey: "themeAuto") } }
    var themeLight: String { didSet { d.set(themeLight, forKey: "themeLight") } }
    var themeDark: String { didSet { d.set(themeDark, forKey: "themeDark") } }
    /// "" = la oficial del tema.
    var fontFamily: String { didSet { d.set(fontFamily, forKey: "fontFamily") } }
    /// 0 = el del tema.
    var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    var sshConfigPath: String { didSet { d.set(sshConfigPath, forKey: "sshConfigPath") } }
    var sidebarVisible: Bool { didSet { d.set(sidebarVisible, forKey: "sidebarVisible") } }
    /// Rejilla y líneas de barrido en la portada.
    var crtEffect: Bool { didSet { d.set(crtEffect, forKey: "crtEffect") } }
    /// Letra de la interfaz: "" = la del tema, "system" = la monoespaciada del sistema, o una familia.
    var uiFontFamily: String { didSet { d.set(uiFontFamily, forKey: "uiFontFamily") } }

    enum HighlightSource: String, CaseIterable { case auto, netdeck, app, custom }
    /// Resaltado tipo ChromaTerm de la salida.
    var highlightEnabled: Bool { didSet { d.set(highlightEnabled, forKey: "highlightEnabled") } }
    var highlightSource: HighlightSource { didSet { d.set(highlightSource.rawValue, forKey: "highlightSource") } }
    /// Colores del tema (true) o la paleta del propio archivo de reglas.
    var highlightThemeColors: Bool { didSet { d.set(highlightThemeColors, forKey: "highlightThemeColors") } }
    /// Reglas apagadas (por su descripción).
    var highlightDisabled: Set<String> { didSet { d.set(Array(highlightDisabled), forKey: "highlightDisabled") } }
    /// Barra de botones (como barra.conf de NetDeck): arriba, abajo u oculta; con categorías (☰ Grupo) o todos en fila.
    var buttonBar: String { didSet { d.set(buttonBar, forKey: "buttonBar") } }
    var buttonBarGrouped: Bool { didSet { d.set(buttonBarGrouped, forKey: "buttonBarGrouped") } }
    var buttonGroup: String { didSet { d.set(buttonGroup, forKey: "buttonGroup") } }
    /// Registro de cada sesión a un archivo (como NetDeck: activado) y dónde.
    var logEnabled: Bool { didSet { d.set(logEnabled, forKey: "logEnabled") } }
    var logPath: String { didSet { d.set(logPath, forKey: "logPath") } }
    var logURL: URL { URL(fileURLWithPath: AppPaths.expand(logPath), isDirectory: true) }
    /// Registro de depuración (~/Library/Logs/Terminal NetDeck/debug.log).
    var debugLog: Bool {
        didSet {
            d.set(debugLog, forKey: "debugLog")
            DebugLog.enabled = debugLog
        }
    }

    /// Idioma de la interfaz (castellano de España o inglés): se aplica al momento.
    var language: Idioma {
        didSet {
            d.set(language.rawValue, forKey: Idioma.clave)
            Idioma.actual = language
        }
    }

    /// Buscar versiones nuevas en segundo plano (una vez al día, en silencio).
    var autoUpdateCheck: Bool { didSet { d.set(autoUpdateCheck, forKey: "autoUpdateCheck") } }
    /// Sesión que se abre al arrancar (su nombre; "" = ninguna) y terminal local si no queda ninguna pestaña abierta.
    var startupSession: String { didSet { d.set(startupSession, forKey: "startupSession") } }
    var startupLocalTerminal: Bool { didSet { d.set(startupLocalTerminal, forKey: "startupLocalTerminal") } }

    /// Mandar el idioma del Mac (LANG, LC_*) a los servidores por ssh. Desactivado: así no salen avisos de locale en
    /// servidores Linux que no lo tienen.
    static let sendLocaleKey = "sendLocale"
    var sendLocale: Bool { didSet { d.set(sendLocale, forKey: Self.sendLocaleKey) } }

    /// Ratón como en PuTTY/SecureCRT (los dos apagados de serie): lo que seleccionas se copia solo, y el clic derecho
    /// pega (por el mismo camino que ⌘V; ⌃/⌥+clic derecho, el menú de siempre). La vista del terminal los lee al vuelo.
    static let copyOnSelectKey = "copyOnSelect"
    static let pasteOnRightClickKey = "pasteOnRightClick"
    var copyOnSelect: Bool { didSet { d.set(copyOnSelect, forKey: Self.copyOnSelectKey) } }
    var pasteOnRightClick: Bool { didSet { d.set(pasteOnRightClick, forKey: Self.pasteOnRightClickKey) } }

    init() {
        sendLocale = d.bool(forKey: Self.sendLocaleKey)
        copyOnSelect = d.bool(forKey: Self.copyOnSelectKey)
        pasteOnRightClick = d.bool(forKey: Self.pasteOnRightClickKey)
        autoUpdateCheck = d.object(forKey: "autoUpdateCheck") as? Bool ?? true
        startupSession = d.string(forKey: "startupSession") ?? ""
        startupLocalTerminal = d.object(forKey: "startupLocalTerminal") as? Bool ?? false
        language = Idioma.actual
        if d.object(forKey: "configured") == nil { Self.importNetDeck(into: d) }
        sessionAutoPassword = d.object(forKey: "sessionAutoPassword") as? Bool ?? true
        devicePasswordMode = PasswordAutomation.Mode(rawValue: d.string(forKey: "devicePasswordMode") ?? "") ?? .suggest
        defaultCredentialName = d.string(forKey: "defaultCredentialName") ?? ""
        defaultCredentialUser = d.string(forKey: "defaultCredentialUser") ?? NSUserName()
        themeID = d.string(forKey: "themeID") ?? Theme.builtIn.id
        themeAuto = d.object(forKey: "themeAuto") as? Bool ?? false
        themeLight = d.string(forKey: "themeLight") ?? "papel"
        themeDark = d.string(forKey: "themeDark") ?? (d.string(forKey: "themeID") ?? Theme.builtIn.id)
        fontFamily = d.string(forKey: "fontFamily") ?? ""
        fontSize = d.object(forKey: "fontSize") as? Double ?? 0
        sshConfigPath = d.string(forKey: "sshConfigPath") ?? SessionManager.defaultConfigURL.path
        sidebarVisible = d.object(forKey: "sidebarVisible") as? Bool ?? true
        crtEffect = d.object(forKey: "crtEffect") as? Bool ?? true
        uiFontFamily = d.string(forKey: "uiFontFamily") ?? ""
        highlightEnabled = d.object(forKey: "highlightEnabled") as? Bool ?? true
        highlightSource = HighlightSource(rawValue: d.string(forKey: "highlightSource") ?? "") ?? .auto
        highlightThemeColors = d.object(forKey: "highlightThemeColors") as? Bool ?? true
        highlightDisabled = Set(d.stringArray(forKey: "highlightDisabled") ?? [])
        debugLog = d.object(forKey: "debugLog") as? Bool ?? true
        logEnabled = d.object(forKey: "logEnabled") as? Bool ?? true
        let barra = AppPaths.readConf(AppPaths.netdeck.appendingPathComponent("barra.conf"))
        buttonBar = d.string(forKey: "buttonBar") ?? (barra["posicion"] ?? "arriba")
        buttonBarGrouped = d.object(forKey: "buttonBarGrouped") as? Bool ?? (barra["estilo"] != "sin-categorias")
        buttonGroup = d.string(forKey: "buttonGroup") ?? ""
        logPath = d.string(forKey: "logPath") ?? SessionLogger.defaultDirectory.path
    }

    var defaultCredential: DefaultCredential? {
        defaultCredentialName.isEmpty ? nil
            : DefaultCredential(name: defaultCredentialName, user: defaultCredentialUser.isEmpty ? NSUserName() : defaultCredentialUser)
    }

    var sshConfigURL: URL { URL(fileURLWithPath: AppPaths.expand(sshConfigPath)) }

    /// clave.conf (defecto, modo) y tema.conf (tema, auto_claro/auto_oscuro) de NetDeck, si está instalado.
    private static func importNetDeck(into d: UserDefaults) {
        d.set(true, forKey: "configured")
        let clave = AppPaths.readConf(AppPaths.netdeck.appendingPathComponent("clave.conf"))
        if let n = clave["defecto"], !n.isEmpty { d.set(n, forKey: "defaultCredentialName") }
        switch clave["modo"] {
        case "escribir": d.set(PasswordAutomation.Mode.autoType.rawValue, forKey: "devicePasswordMode")
        case "sugerir": d.set(PasswordAutomation.Mode.suggest.rawValue, forKey: "devicePasswordMode")
        default: break
        }
        let tema = AppPaths.readConf(AppPaths.netdeck.appendingPathComponent("tema.conf"))
        if let l = tema["auto_claro"], !l.isEmpty { d.set(l, forKey: "themeLight") }
        if let o = tema["auto_oscuro"], !o.isEmpty { d.set(o, forKey: "themeDark") }
        if var t = tema["tema"], !t.isEmpty {
            if t == "auto" {
                d.set(true, forKey: "themeAuto")
                let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
                t = tema[dark ? "auto_oscuro" : "auto_claro"] ?? t
            }
            d.set(t, forKey: "themeID")
        }
    }
}
