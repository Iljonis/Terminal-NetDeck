import AppKit
import NetDeckCore
import Observation
import SwiftUI

/// Lo común a todas las ventanas: ajustes, temas, sesiones, Llavero, botones, macros, túneles, espacios, resaltado,
/// actualizaciones y las pestañas que se reabren. Cada ventana tiene su `AppModel` (pestañas, vista dividida, MultiExec,
/// hojas y avisos), que lee y cambia todo esto con sus propiedades de siempre (`model.settings`, `model.buttons`…).
@MainActor @Observable
final class AppCore {
    static let shared = AppCore()

    let settings = AppSettings()
    let themes: ThemeStore
    let sessions = SessionManager()
    let store: CredentialStore = KeychainStore()
    let ledger = CredentialLedger.shared()
    let policy = CredentialPolicy()
    /// Copias de los exploradores SFTP/FTP (también de servidor a servidor y de una ventana a otra).
    let transfers = TransferCenter()
    /// Visible y ancho del explorador lateral de cada sesión (panel-sftp.json).
    @ObservationIgnored var panelStore = SFTPPanelStore()
    /// ★ favoritas y ↻ recientes: los mismos archivos que NetDeck (~/.config/netdeck/favoritas, recientes).
    var favorites: [String] = []
    var recents: [String] = []
    /// Botones de la barra (botones.txt de NetDeck, o el de la app).
    var buttons = ButtonFile()
    @ObservationIgnored var buttonsMoved = false
    /// Para refrescar lo que depende del Llavero.
    var keychainRevision = 0
    @ObservationIgnored var keychainCache: (rev: Int, list: [CredentialRef])?
    /// Las reglas de resaltado leídas (todas, también las apagadas) y de dónde.
    var highlightConfig = HighlightConfig()
    var highlightFile: URL?
    /// Versión nueva encontrada en segundo plano (aviso discreto en la barra de estado).
    var availableUpdate: UpdateCheck.Release?
    @ObservationIgnored lazy var updates = UpdateChecker(core: self)
    @ObservationIgnored var offeringUpdate = false
    @ObservationIgnored var savingSessions = false
    /// Los túneles guardados (tuneles.json) y sus procesos ssh (`Tunnels.swift`).
    var tunnels = TunnelLibrary()
    var tunnelsError: String?
    var tunnelWarnings: [String] = []
    let tunnelRunner = TunnelManager()
    /// La «sesión» del askpass de cada túnel en marcha (para confirmar la contraseña que ha valido).
    @ObservationIgnored var tunnelAskpass: [Tunnel.ID: UUID] = [:]
    var workspaces = WorkspaceLibrary()
    var workspacesError: String?
    /// Las macros guardadas (macros.json). Cargarlas no ejecuta nada: sólo `runMacro`, desde un clic del usuario.
    var macros = MacroLibrary()
    /// macros.json no se ha podido usar (ilegible, roto o de otra versión): no se toca; al guardar se aparta.
    var macrosError: String?
    var macroWarnings: [String] = []
    /// Pestañas abiertas la última vez, por ventana (para reabrirlas).
    var lastOpen = OpenWindows()
    /// La primera ventana ya ha cargado lo de todas (sesiones, botones, macros…: `AppModel.init`).
    @ObservationIgnored var started = false

    // MARK: - ventanas

    /// Las ventanas abiertas, en el orden en que se abrieron (al reabrir, la primera es la de siempre). Sin observar: se
    /// añade una al pintarse su ventana, y eso no puede invalidar otras vistas a mitad de pintar.
    @ObservationIgnored private(set) var windows: [AppModel] = []
    /// La de la primera ventana, creada antes de pintar nada (carga lo de todas: `AppModel.init`); se la queda la
    /// primera ventana que se pinta.
    @ObservationIgnored private var launch: AppModel?
    /// La de delante: a ella van los menús, ⌘T, ⌘K… y los avisos que no son de una pestaña.
    private(set) var active: AppModel?
    /// Abre una ventana de la escena (lo deja aquí cada una al pintarse: `WindowRoot`). Las pedidas antes de que haya
    /// ninguna (al reabrir con `--reabrir` tras actualizar) esperan en `queuedWindows` y se abren entonces.
    @ObservationIgnored var openWindowAction: OpenWindowAction? {
        didSet {
            guard let open = openWindowAction, !queuedWindows.isEmpty else { return }
            let tokens = queuedWindows
            queuedWindows = []
            // (fuera del `onAppear` que lo ha dejado aquí: abrir otra ventana mientras se monta la primera la bloquea)
            DispatchQueue.main.async { for t in tokens { open(id: "main", value: t) } }
        }
    }
    @ObservationIgnored private var queuedWindows: [UUID] = []
    /// Lo que espera una ventana recién pedida: pestañas que abrir, una que pasarle desde otra y dónde ponerse.
    @ObservationIgnored private var arrivals: [UUID: Arrival] = [:]
    @ObservationIgnored private var closedTokens: Set<UUID> = []
    /// La app se está cerrando: las ventanas que se cierran no cortan sus pestañas (se guardan para reabrirlas).
    @ObservationIgnored private(set) var terminating = false
    @ObservationIgnored private var appearanceWatch: NSKeyValueObservation?

    struct Arrival {
        var routes: [ConnectionRoute] = []
        /// Una pestaña que viene de otra ventana (se suelta allí sólo cuando ésta ya está: si no llega, no se pierde).
        var moving: (from: AppModel, tab: TerminalSession.ID)?
        var frame: CGRect?
    }

    private init() {
        themes = ThemeStore(selected: settings.themeID)
        DebugLog.enabled = settings.debugLog
        DebugLog.log("app", "arranca \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")"
                     + " (\(Bundle.main.bundlePath)) · ssh_config \(settings.sshConfigURL.path)")
        let settings = settings
        transfers.verify = { settings.verifyTransfers }
        transfers.showCopied = { [weak self] fs, dir in self?.refreshBrowsers(showing: [dir], of: fs) }
        tunnelRunner.onChange = { [weak self] id, state in self?.front?.tunnelChanged(id, state) }
        watchMenus()
    }

    /// Los menús: lo que decide si se ven activos (la ventana de delante, sus hojas, su pestaña…). SwiftUI no los vuelve
    /// a mirar por un cambio `@Observable`; `menus` (ObservableObject) sí.
    @ObservationIgnored let menus = MenuRefresh()

    private func watchMenus() {
        withObservationTracking {
            let m = front
            _ = (m?.modalOpen, m?.selection, m?.tabs.count, m?.recording, m?.multiExecOn, m?.current?.exited)
            _ = (m?.startupProfile?.name, settings.highlightEnabled)
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.menus.bump()
                self.watchMenus()
            }
        }
    }

    /// La ventana de delante, o la primera si ninguna lo es (p. ej. con la app en segundo plano).
    var front: AppModel? { active ?? windows.first }

    /// Al arrancar, antes de la primera ventana: su modelo, que carga sesiones, resaltado, botones, macros, túneles… y
    /// decide si sale el asistente (así no cambia nada a mitad de pintarla).
    func prepareLaunch() {
        guard launch == nil, windows.isEmpty else { return }
        let m = AppModel(core: self, token: UUID())
        windows.append(m)                           // (ya cuenta: lo que reabra antes de pintarse se guarda con ella)
        launch = m
    }

    /// El modelo de la ventana `token` (se crea la primera vez que SwiftUI la pinta y vive hasta que se cierra).
    func model(for token: UUID) -> AppModel {
        if let m = windows.first(where: { $0.token == token }) { return m }
        // (SwiftUI aún puede pintar una que se está cerrando: uno de paso, que no cuenta como ventana)
        if closedTokens.contains(token) { return AppModel(core: self, token: token) }
        if let m = launch {
            launch = nil
            // (con --reabrir, su marco puede esperar desde antes de que la escena le dé el token definitivo)
            if let frame = arrivals.removeValue(forKey: m.token)?.frame, arrivals[token]?.frame == nil {
                arrivals[token, default: Arrival()].frame = frame
            }
            m.token = token
            return m
        }
        let m = AppModel(core: self, token: token)
        windows.append(m)
        return m
    }

    /// La ventana ya tiene su NSWindow: si es la de delante, pasa a ser la activa; y recoge lo que la esperaba.
    func attached(_ m: AppModel) {
        if active == nil || m.window?.isMainWindow == true { active = m }
        if appearanceWatch == nil {
            appearanceWatch = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.front?.followAppearance() }
            }
        }
        styleWindows()
        guard let a = arrivals.removeValue(forKey: m.token) else { return }
        if let f = a.frame { restoreFrame(f, into: m) }
        for r in a.routes { m.open(r) }
        if let (from, id) = a.moving {
            // (si la de origen ya no puede soltarla —cerrada, o la pestaña está en una secuencia—, la nueva sobra)
            guard let s = from.tab(id), from.moveTab(s, to: m) else {
                if m.tabs.isEmpty { m.window?.close() }
                return
            }
        }
    }

    /// El marco guardado: respeta el mínimo y su pantalla, y espera a la NSWindow si aún no se ha pintado.
    private func restoreFrame(_ f: CGRect, into m: AppModel) {
        guard let w = m.window else {
            arrivals[m.token, default: Arrival()].frame = f
            return
        }
        guard !w.styleMask.contains(.fullScreen) else { return }
        // (el borde de arriba queda donde estaba; si su pantalla ya no está, donde la ponga macOS)
        let size = CGSize(width: max(f.width, w.minSize.width), height: max(f.height, w.minSize.height))
        let want = CGRect(x: f.minX, y: f.maxY - size.height, width: size.width, height: size.height)
        if let fit = WindowPlacement.restored(want, screens: NSScreen.screens.map(\.visibleFrame)) {
            w.setFrame(fit, display: true)
        }
    }

    func becameMain(_ m: AppModel) {
        if active !== m { active = m }
    }

    /// Las que tienen ya su NSWindow (las de la pantalla).
    var attachedWindows: [AppModel] { windows.filter { $0.window != nil } }

    /// La ventana de la app que está bajo `point` (pantalla): la de más arriba si se tapan; nil si no hay ninguna
    /// (ni minimizada ni en otro escritorio).
    func window(at point: CGPoint) -> AppModel? {
        for w in NSApp.orderedWindows where w.isVisible && !w.isMiniaturized && w.isOnActiveSpace && w.frame.contains(point) {
            if let m = attachedWindows.first(where: { $0.window === w }) { return m }
        }
        return nil
    }

    /// Una ventana nueva: vacía (la portada), con esas pestañas, o con una que se le pasa desde otra; `frame`, dónde.
    func openWindow(routes: [ConnectionRoute] = [], moving: (from: AppModel, tab: TerminalSession.ID)? = nil,
                    frame: CGRect? = nil) {
        let token = UUID()
        arrivals[token] = Arrival(routes: routes, moving: moving, frame: frame)
        if let open = openWindowAction { open(id: "main", value: token) } else { queuedWindows.append(token) }
        DebugLog.log("ventana", "nueva (\(routes.count) pestañas\(moving == nil ? "" : ", una movida")) · marco \(frame.map { "\($0)" } ?? "el de macOS")")
    }

    /// Se cierra la ventana de `m`. La última no corta nada: cierra la app y sus pestañas se guardan para reabrirlas.
    func closing(_ m: AppModel) {
        guard !terminating, windows.contains(where: { $0 === m }) else { return }
        guard attachedWindows.contains(where: { $0 !== m }) else { return }
        windows.removeAll { $0 === m }
        closedTokens.insert(m.token)
        if active === m { active = attachedWindows.first { $0.window?.isMainWindow == true } ?? attachedWindows.last }
        m.windowClosed()
        saveOpenTabs()
    }

    /// Al salir (antes de que se cierre ninguna ventana): se guardan las pestañas de todas, cada una en su ventana.
    func willTerminate() {
        guard !terminating else { return }
        terminating = true
        saveOpenTabs()
    }

    /// ■ y ⌘.: corta lo automático en todas las ventanas (un pegado o una macro en otra pantalla también).
    func abortEverywhere() {
        windows.forEach { $0.abortAll() }
    }

    // MARK: - lo que afecta a las pestañas de todas las ventanas

    var allTabs: [TerminalSession] { windows.flatMap(\.tabs) }

    /// Todos los exploradores: los de las pestañas SFTP/FTP y los laterales de las ssh, de todas las ventanas.
    var allBrowsers: [(TerminalSession, RemoteBrowser)] {
        allTabs.compactMap { s in (s.browser ?? s.sidePanel?.browser).map { (s, $0) } }
    }

    /// Refresca (una vez cada uno) los exploradores de ese servidor que enseñan alguna de esas carpetas.
    func refreshBrowsers(showing dirs: Set<String>, of fs: any RemoteFileSystem, except: RemoteBrowser? = nil) {
        for (_, b) in allBrowsers where b !== except && dirs.contains(where: { b.shows($0, of: fs) }) { b.refresh() }
    }

    /// El tema para la interfaz, con la letra elegida en Ajustes → Fuentes (si no, la del tema).
    var uiTheme: Theme {
        var t = themes.current
        switch settings.uiFontFamily {
        case "": break
        case "system": t.fonts = []
        default: t.fonts = [settings.uiFontFamily]
        }
        return t
    }

    /// Las ventanas (y menús, avisos, hojas) con el tema: claro/oscuro, su color y, en los de cristal, transparentes.
    func styleWindows() {
        let th = themes.current
        NSApp.appearance = NSAppearance(named: th.isLight ? .aqua : .darkAqua)
        let ours = Set(windows.compactMap { $0.window.map(ObjectIdentifier.init) })
        for w in NSApp.windows {
            let mine = ours.contains(ObjectIdentifier(w))
            if mine || w.className.contains("FullScreen") || w.className.contains("Titlebar") {
                w.isOpaque = !th.isTranslucent
                w.backgroundColor = mine ? (th.isTranslucent ? .clear : NSColor(th.background)) : NSColor(th.bar.opaque)
            }
            if mine { w.titlebarAppearsTransparent = true }
        }
    }

    // MARK: - reabrir las de la última vez (y tras actualizar)

    static var openTabsFile: URL { AppPaths.support.appendingPathComponent("abiertas.json") }

    /// Se guarda al abrir, cerrar y mover pestañas (así una actualización o un cierre brusco no las pierde), con la
    /// ventana de cada una y dónde estaba.
    func saveOpenTabs() {
        // (las capturas de desarrollo no tocan tus pestañas; y nunca las de este mismo Mac)
        guard ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] == nil else { return }
        let now = currentOpenWindows()
        guard !now.isEmpty else {
            if lastOpen.isEmpty { try? FileManager.default.removeItem(at: Self.openTabsFile) }
            return
        }
        AppPaths.ensure(AppPaths.support)
        do {
            try now.encoded().write(to: Self.openTabsFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.openTabsFile.path)
        } catch {
            ErrorLog.error("pestañas", "no se han podido guardar las pestañas abiertas: \(error.localizedDescription)")
        }
    }

    /// Lo que se guardaría ahora: las pestañas de cada ventana (sin las de este Mac) y dónde está cada una (en pantalla
    /// completa, sin marco: al reabrir sale donde toque).
    func currentOpenWindows() -> OpenWindows {
        let open = windows.map { m in
            OpenWindows.Window(tabs: m.tabs.map(\.route), frame: m.fullScreen ? nil : m.window?.frame)
        }
        // (y las pedidas que aún no se han pintado, con lo que van a abrir: al reabrir, las demás tardan un momento)
        let coming = arrivals.values.map { OpenWindows.Window(tabs: $0.routes, frame: $0.frame) }
        return OpenWindows(windows: open + coming).withoutLoopback()
    }

    /// La sesión `name` ya está abierta en alguna ventana (o va a abrirse en una que aún no se ha pintado).
    func isOpenAnywhere(_ name: String) -> Bool {
        allTabs.contains { $0.route.sessionName == name } || arrivals.values.contains { $0.routes.contains { $0.sessionName == name } }
    }

    static func readOpenTabs() -> OpenWindows {
        guard let data = try? Data(contentsOf: openTabsFile) else { return OpenWindows() }
        guard let all = OpenWindows.decode(data) else {
            ErrorLog.warning("pestañas", "abiertas.json no se puede leer: no se reabre nada")
            return OpenWindows()
        }
        let kept = all.withoutLoopback()
        if kept.tabs.count != all.tabs.count { DebugLog.log("app", "no reabro \(all.tabs.count - kept.tabs.count) a este mismo Mac (127.x/localhost)") }
        return kept
    }

    /// Reabre las de la última vez: las de la primera ventana en `m`; las de las demás, cada una en una ventana nueva.
    /// Todas recuperan su sitio si su pantalla sigue conectada y no están ya en pantalla completa.
    func reopenLast(into m: AppModel) {
        let saved = lastOpen
        lastOpen = OpenWindows()
        DebugLog.log("app", "reabro \(saved.tabs.count) en \(saved.windows.count) ventanas: \(saved.tabs.map(\.title))")
        guard let first = saved.windows.first else { return }
        if let frame = first.frame { restoreFrame(frame, into: m) }
        for r in first.tabs { m.open(r) }
        for w in saved.windows.dropFirst() { openWindow(routes: w.tabs, frame: w.frame) }
    }
}

/// Lo que SwiftUI sí vigila en los menús (`NetDeckCommands`): se avisa cuando cambia algo que los enciende o apaga.
@MainActor
final class MenuRefresh: ObservableObject {
    @Published private(set) var tick = 0
    func bump() { tick &+= 1 }
}

/// El botón rojo de una ventana: en vez de cerrarla sin más, `AppModel.askToCloseWindow` (pregunta si hay más ventanas
/// y ésta tiene conexiones). El delegado de la ventana es de SwiftUI y no se toca.
@MainActor
final class WindowCloseGuard: NSObject {
    private weak var model: AppModel?

    init(model: AppModel, window: NSWindow) {
        self.model = model
        super.init()
        install(on: window)
    }

    func install(on window: NSWindow) {
        guard let b = window.standardWindowButton(.closeButton), b.target !== self else { return }
        b.target = self
        b.action = #selector(closeClicked(_:))
    }

    @objc private func closeClicked(_ sender: Any?) { model?.askToCloseWindow() }
}
