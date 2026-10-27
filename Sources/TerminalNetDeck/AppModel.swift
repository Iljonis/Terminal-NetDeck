import AppKit
import NetDeckCore
import Observation

/// Estado de una ventana: sus pestañas, la vista dividida, MultiExec, las hojas y avisos, y lo automático en curso.
/// Lo común a todas (ajustes, temas, sesiones, Llavero, botones, macros, túneles…) está en `AppCore` y se lee con las
/// mismas propiedades de siempre (`settings`, `buttons`…), que lo reenvían.
@MainActor @Observable
final class AppModel {
    enum Sheet: String, Identifiable {
        case connect, paste, list, sessions, fill, logs, macros, tunnels, workspaces
        var id: String { rawValue }
    }

    /// Qué abre el gestor de Sesiones: una sesión, una nueva (en un grupo) o importar.
    enum EditorFocus: Equatable {
        case session(String)
        case new(group: String?, kind: SessionProfile.Transport = .ssh)
        case duplicate(String)
        case importing
    }

    /// Lo común a todas las ventanas.
    let core: AppCore
    /// Esta ventana para SwiftUI (`WindowGroup`) y para pasarle pestañas desde otra (lo pone `AppCore.model(for:)`).
    @ObservationIgnored var token: UUID
    /// La primera ventana (la que carga lo de todas; también la única en la que actúan las capturas de desarrollo).
    @ObservationIgnored private(set) var isLaunchWindow = false

    var settings: AppSettings { core.settings }
    var themes: ThemeStore { core.themes }
    var sessions: SessionManager { core.sessions }
    var store: CredentialStore { core.store }
    var ledger: CredentialLedger { core.ledger }
    var policy: CredentialPolicy { core.policy }
    /// Copias de los exploradores SFTP/FTP (también de servidor a servidor y de una ventana a otra).
    var transfers: TransferCenter { core.transfers }
    /// Visible y ancho del explorador lateral de cada sesión (panel-sftp.json).
    private var panelStore: SFTPPanelStore {
        get { core.panelStore }
        set { core.panelStore = newValue }
    }
    @ObservationIgnored let multiExec = MultiExecGroup()
    /// Lo que afecta a varias pestañas (pegado a todas, listas): Esc en cualquiera lo corta.
    @ObservationIgnored let sharedGate = AutomationGate()

    var tabs: [TerminalSession] = []
    /// Zonas de la ventana (en coordenadas de SwiftUI) donde arrastrar reordena y no mueve la ventana (`keepsWindowStill`).
    @ObservationIgnored var stillZones: [String: CGRect] = [:]
    /// Las zonas de `stillZones` en las que está ahora el puntero.
    @ObservationIgnored private var stillHover: Set<String> = []
    var selection: TerminalSession.ID? {
        didSet { updateVisibility() }
    }
    var sheet: Sheet?
    /// Lo último que ha pasado. No se ve en la barra de estado: sólo lo importante sale un momento como aviso
    /// (`StatusNotice.isImportant`).
    var status = "" {
        didSet {
            guard !status.isEmpty else { return }
            DebugLog.log("estado", status)
            if StatusNotice.isImportant(status) { showToast(status) }
        }
    }
    /// El aviso pasajero (se va solo a los ~4 s).
    var toast: String?
    @ObservationIgnored private var toastGeneration = 0

    private func showToast(_ text: String) {
        toast = text
        toastGeneration += 1
        let g = toastGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.toastGeneration == g { self?.toast = nil }
        }
    }
    var multiExecOn = false {
        didSet {
            syncMultiExec()
            DebugLog.log("multiexec", multiExecOn ? "activado: \(multiExecTargets.map(\.title))" : "desactivado")
        }
    }
    /// Pantalla dividida (como ⊞ Split de NetDeck): qué pestañas y cómo.
    var split: Split? {
        didSet { syncMultiExec(); updateVisibility() }
    }
    var showSplit = false {
        didSet { syncMultiExec(); updateVisibility() }
    }
    /// Fuera de MultiExec (clic derecho en su cabecera).
    var excluded: Set<TerminalSession.ID> = [] {
        didSet { syncMultiExec() }
    }
    /// Ventana: pantalla completa. El sistema gestiona el espacio de la barra de título al mostrarla y ocultarla.
    var fullScreen = false
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var focusWatch: NSKeyValueObservation?
    @ObservationIgnored private var stillWatch: Any?
    @ObservationIgnored private var windowWatches: [NSObjectProtocol] = []
    @ObservationIgnored private var closeGuard: WindowCloseGuard?
    @ObservationIgnored private var frameBeforeFill: NSRect?
    /// Pestañas abiertas la última vez, de todas las ventanas (para reabrirlas).
    var lastOpen: [ConnectionRoute] { core.lastOpen.tabs }
    /// En cuántas ventanas estaban.
    var lastOpenWindows: Int { core.lastOpen.windows.count }
    var editorFocus: EditorFocus?
    /// Ajustes dentro de la ventana (en pantalla completa no se van a otro escritorio) y con el tema.
    var showSettings = false
    /// Hay una hoja, Ajustes o el asistente abiertos: los atajos que cambian de hoja o actúan sobre las pestañas se
    /// apagan (⌘K sustituiría el gestor con sus cambios; ⌘W cerraría la pestaña a la que va el botón que rellenas).
    var modalOpen: Bool { sheet != nil || showSettings || showSetup || core.renamingCredential }
    var settingsTab = "contraseñas"
    /// La sección de Ajustes abierta con cambios sin guardar (Sesiones, Listas) pregunta antes de cambiar de sección o
    /// cerrar (`true`: se puede salir). `owner`: la vista que lo puso (sólo ella lo quita).
    @ObservationIgnored var settingsLeave: (owner: UUID, check: @MainActor () async -> Bool)?
    /// ★ favoritas y ↻ recientes: los mismos archivos que NetDeck (~/.config/netdeck/favoritas, recientes).
    var favorites: [String] {
        get { core.favorites }
        set { core.favorites = newValue }
    }
    var recents: [String] {
        get { core.recents }
        set { core.recents = newValue }
    }
    /// Botones de la barra (botones.txt de NetDeck, o el de la app).
    var buttons: ButtonFile {
        get { core.buttons }
        set { core.buttons = newValue }
    }
    private var buttonsMoved: Bool {
        get { core.buttonsMoved }
        set { core.buttonsMoved = newValue }
    }
    /// Botón con huecos esperando a que los rellenes.
    var pendingButton: CommandButton?
    /// Sugerencia o elección manual pendiente en cada pestaña.
    var notices: [TerminalSession.ID: PasswordAutomation.Event] = [:]
    var passwordOffers: [TerminalSession.ID: PasswordAutomation.Offer] = [:]
    /// Para refrescar lo que depende del Llavero.
    var keychainRevision: Int {
        get { core.keychainRevision }
        set { core.keychainRevision = newValue }
    }
    /// El asistente de instalación ocupa la ventana: al abrirla desde fuera de Aplicaciones (DMG…), la primera vez que
    /// se abre (también si se arrastró a Aplicaciones desde el DMG) o desde el menú. Sólo en la primera ventana.
    var showSetup = false
    /// Las reglas de resaltado leídas (todas, también las apagadas) y de dónde.
    private(set) var highlightConfig: HighlightConfig {
        get { core.highlightConfig }
        set { core.highlightConfig = newValue }
    }
    private(set) var highlightFile: URL? {
        get { core.highlightFile }
        set { core.highlightFile = newValue }
    }

    /// Versión nueva encontrada en segundo plano (aviso discreto en la barra de estado).
    var availableUpdate: UpdateCheck.Release? {
        get { core.availableUpdate }
        set { core.availableUpdate = newValue }
    }

    /// La ventana `token`. La primera que se crea carga lo de todas (sesiones, resaltado, botones, macros, túneles…),
    /// abre la sesión de inicio y, con `--reabrir`, las pestañas de la última vez.
    init(core: AppCore, token: UUID) {
        self.core = core
        self.token = token
        // MultiExec: pide un secreto o aún no ha llegado a su primer prompt (lo tecleado iría al askpass como contraseña)
        multiExec.awaitingAuth = { io in
            SecretPrompt.asks(io.cursorLine) || (io as? TerminalSession).map { !$0.loggedIn && !$0.exited } == true
        }
        multiExec.canReceiveKeystrokes = { [weak self] io in
            guard let self, let s = io as? TerminalSession else { return false }
            return !self.automationReservation.contains(s.id)
        }
        guard !core.started else { return }
        core.started = true
        isLaunchWindow = true
        showSetup = SetupWizard.needsInstall || SetupWizard.firstLaunch
            || ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT_ACTION"]?.hasPrefix("setup:") == true
        if ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] == nil { protectUserData() }
        reloadSessions()
        reloadHighlight()
        core.lastOpen = AppCore.readOpenTabs()
        Askpass.purgeStale()                        // (lo que dejaron pestañas de otros días: cuentas y equipos)
        loadFavorites()
        reloadButtons()
        reloadMacros()                              // (sólo las lee: ninguna se ejecuta al arrancar)
        reloadTunnels()                             // (ídem: ningún túnel arranca solo)
        reloadWorkspaces()
        if CommandLine.arguments.contains("--reabrir") { DispatchQueue.main.async { self.reopenLast() } }
        if ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] == nil {
            DispatchQueue.main.async { self.openStartupTabs() }                   // (después de reabrir, si toca)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { core.updates.start() }   // (sin estorbar al arrancar)
            // (desarrollo: NETDECK_PRUEBA_ACTUALIZAR=1 con NETDECK_HOME instala la última release sin preguntar)
            if ProcessInfo.processInfo.environment["NETDECK_PRUEBA_ACTUALIZAR"] == "1",
               ProcessInfo.processInfo.environment["NETDECK_HOME"] != nil, let repo = UpdateCheck.repo {
                Task { if let r = try? await UpdateCheck.check(repo: repo) { Updater.install(r, model: self) } }
            }
        }
    }

    /// El tema para la interfaz, con la letra elegida en Ajustes → Fuentes (si no, la del tema).
    var uiTheme: Theme { core.uiTheme }

    /// El archivo de reglas que toca: el personalizado, el de NetDeck (~/.config/netdeck/chromaterm.yml) o el de la app.
    func highlightURL(_ source: AppSettings.HighlightSource) -> URL? {
        let fm = FileManager.default
        let custom = AppPaths.support.appendingPathComponent("resaltado.yml")
        let netdeck = AppPaths.netdeck.appendingPathComponent("chromaterm.yml")
        let app = AppResources.directory("Resaltado")?.appendingPathComponent("netdeck.yml")
        switch source {
        case .custom: return custom
        case .netdeck: return netdeck
        case .app: return app
        case .auto: return [custom, netdeck].first { fm.fileExists(atPath: $0.path) } ?? app
        }
    }

    func reloadHighlight() {
        highlightFile = highlightURL(settings.highlightSource)
        do {
            highlightConfig = try highlightFile.map(HighlightConfig.init(contentsOf:)) ?? HighlightConfig()
        } catch {
            if let f = highlightFile, FileManager.default.fileExists(atPath: f.path) {
                ErrorLog.warning("resaltado", "no se puede leer \(f.lastPathComponent): \(error.localizedDescription)")
            }
            highlightConfig = HighlightConfig()
        }
        applyHighlight()
    }

    /// Reglas activas y colores (los del tema, o la paleta del archivo) a todas las pestañas (de todas las ventanas).
    func applyHighlight() {
        core.allTabs.forEach(applyHighlight)
    }

    private func applyHighlight(to s: TerminalSession) {
        let rules = highlightConfig.rules.filter { !settings.highlightDisabled.contains($0.description) }
        s.highlight(rules: rules, palette: highlightPalette(for: s.theme ?? themes.current), enabled: settings.highlightEnabled)
    }

    /// Los colores con nombre del resaltado («green», «red»…) con el tema `th`: los del tema (o la paleta del archivo
    /// de reglas, sin «Con los colores del tema») y encima los elegidos a mano para ese tema. Sólo para el texto
    /// resaltado: la interfaz no los usa.
    func highlightPalette(for th: Theme) -> [String: RGB] {
        let base = settings.highlightThemeColors ? th.highlightPalette : th.highlightPalette.merging(highlightConfig.palette) { $1 }
        let mine = (settings.highlightColors[th.id] ?? [:]).compactMapValues(RGB.init(hex:))
        return base.merging(mine) { $1 }
    }

    /// Un color del resaltado para el tema actual (nil = el que trae).
    func setHighlightColor(_ name: String, _ c: RGB?) {
        let id = themes.current.id
        var mine = settings.highlightColors[id] ?? [:]
        mine[name] = c?.description
        settings.highlightColors[id] = mine.isEmpty ? nil : mine
        applyHighlight()
    }

    static var customHighlightURL: URL { AppPaths.support.appendingPathComponent("resaltado.yml") }

    /// Lo que se cambia en Ajustes → Resaltado (añadir, editar, ordenar, borrar): al archivo personalizado (con
    /// copia `.anterior`) y a partir de ahí se usan esas. `renamed`: descripción vieja → nueva (para que una regla
    /// apagada siga apagada). nil = bien; si no, el error.
    func saveHighlightRules(_ rules: [HighlightRule], renamed: [String: String] = [:]) -> String? {
        // (las que no se han podido leer no están en `rules`: guardar las borraría; primero, que se arreglen)
        guard highlightConfig.problems.isEmpty else {
            return L("Hay reglas que no se pueden leer (\(highlightConfig.problems.joined(separator: " · "))): arréglalas en el editor y pulsa Recargar; así no se pierden")
        }
        // (las de serie que se quitan o renombran no se vuelven a ofrecer como «nuevas»)
        if let bundled = bundledHighlightRules {
            let kept = Set(rules.map(\.description)), serie = Set(bundled.map(\.description))
            settings.highlightDismissed.formUnion(highlightConfig.rules.map(\.description).filter { !kept.contains($0) && serie.contains($0) })
        }
        var cfg = highlightConfig
        cfg.rules = rules
        cfg.problems = []
        let url = Self.customHighlightURL
        do {
            AppPaths.ensure(AppPaths.support)
            try SafeFile.backup(url)
            try SafeFile.write(cfg.yaml(), to: url)
        } catch {
            ErrorLog.error("resaltado", "no se han podido guardar las reglas: \(error.localizedDescription)")
            return error.localizedDescription
        }
        for (old, new) in renamed where settings.highlightDisabled.remove(old) != nil { settings.highlightDisabled.insert(new) }
        let names = Set(rules.map(\.description))
        settings.highlightDisabled = settings.highlightDisabled.filter(names.contains)
        settings.highlightSource = .custom
        reloadHighlight()
        return nil
    }

    /// Las reglas de serie que no están en las que se usan (las que ha traído una versión nueva y no llegan a quien
    /// tiene las suyas). Vacío si se usan las de la app.
    var missingBundledRules: [HighlightRule] {
        guard let app = highlightURL(.app), highlightFile?.standardizedFileURL != app.standardizedFileURL,
              highlightConfig.problems.isEmpty, let bundled = bundledHighlightRules else { return [] }
        return HighlightConfig.missing(from: bundled, in: highlightConfig.rules).filter { !settings.highlightDismissed.contains($0.description) }
    }

    /// Las de serie, leídas una vez (no cambian con la app abierta; nil si no se pueden leer).
    @ObservationIgnored private lazy var bundledHighlightRules: [HighlightRule]? =
        highlightURL(.app).flatMap { try? HighlightConfig(contentsOf: $0) }?.rules

    /// Añade a las reglas propias las de serie que les faltan, cada una en su sitio; las demás no se tocan.
    func addMissingBundledRules() -> String? {
        guard let bundled = bundledHighlightRules else { return L("No encuentro las reglas de la app") }
        let offered = bundled.filter { !settings.highlightDismissed.contains($0.description) }
        return saveHighlightRules(HighlightConfig.addingMissing(from: offered, to: highlightConfig.rules))
    }

    /// «Restaurar las de serie»: el archivo personalizado vuelve a ser el de la app (queda copia `.anterior`) y todas
    /// las reglas, encendidas.
    func restoreBundledHighlight() -> String? {
        guard let src = highlightURL(.app), let text = try? SafeFile.read(src) else {
            ErrorLog.error("resaltado", "no encuentro las reglas de la app (Resaltado/netdeck.yml)")
            return L("No encuentro las reglas de la app")
        }
        do {
            AppPaths.ensure(AppPaths.support)
            try SafeFile.backup(Self.customHighlightURL)
            try SafeFile.write(text, to: Self.customHighlightURL)
        } catch {
            ErrorLog.error("resaltado", "no se han podido restaurar las reglas: \(error.localizedDescription)")
            return error.localizedDescription
        }
        settings.highlightDisabled = []
        settings.highlightDismissed = []
        settings.highlightSource = .custom
        reloadHighlight()
        return nil
    }

    /// Copia editable de las reglas (para cambiarlas sin tocar las de NetDeck).
    func customizeHighlight() -> URL? {
        let dest = AppPaths.ensure(AppPaths.support).appendingPathComponent("resaltado.yml")
        if !FileManager.default.fileExists(atPath: dest.path), let src = highlightFile {
            try? FileManager.default.copyItem(at: src, to: dest)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)   // (sólo tú)
        }
        settings.highlightSource = .custom
        reloadHighlight()
        return dest
    }

    var current: TerminalSession? { tabs.first { $0.id == selection } }

    func reloadSessions() {
        if FileManager.default.fileExists(atPath: settings.sshConfigURL.path) {
            sessions.load(from: settings.sshConfigURL)
        }
        // Instalación limpia: sin ssh_config no hay sesiones (los ejemplos, sólo para capturas: NETDECK_SAMPLES=1).
        if sessions.profiles.isEmpty, ProcessInfo.processInfo.environment["NETDECK_SAMPLES"] != nil { sessions.loadSamples() }
        core.allTabs.forEach(refreshProfile)        // (el perfil recién guardado, también a las abiertas de cada ventana)
    }

    // MARK: - ajustes en vivo

    func selectTheme(_ id: String) {
        settings.themeID = id
        themes.select(id)
        applyAppearance()
    }

    /// El historial (scrollback) de Ajustes → Terminal, a todas las pestañas abiertas.
    func applyScrollback() {
        core.allTabs.forEach(applyProfile)        // (las que heredan; las de «# @scrollback» se quedan con el suyo)
    }

    /// Tema automático: el claro o el oscuro según el Mac (se llama al cambiar la apariencia).
    func followAppearance() {
        guard settings.themeAuto else { return }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let id = dark ? settings.themeDark : settings.themeLight
        if themes.current.id != id, themes.theme(id: id) != nil { selectTheme(id) }
    }

    /// Tema, fuente y colores del resaltado a todas las pestañas abiertas (de todas las ventanas).
    func applyAppearance() {
        core.allTabs.forEach(applyProfile)
        styleWindows()
        applyHighlight()
    }

    /// Las ventanas (y menús, avisos, hojas) con el tema: claro/oscuro, su color y, en los de cristal, transparentes.
    func styleWindows() { core.styleWindows() }

    func applyPasswordModes() {
        for t in core.allTabs where t.route.usesPasswords {
            if t.passwords.mode != settings.devicePasswordMode { t.cancelPasswordContext() }
            t.passwords.mode = settings.devicePasswordMode
        }
    }

    var terminalFont: NSFont { terminalFont(theme: themes.current, family: settings.fontFamily, size: settings.fontSize) }

    /// `family` "" = la del tema; `size` 0 = el del tema.
    func terminalFont(theme t: Theme, family: String, size: Double) -> NSFont {
        Fonts.terminal(family: family.isEmpty ? Fonts.firstInstalled(t.fonts) : family, size: size > 0 ? size : CGFloat(t.size - 1))
    }

    /// El perfil de la sesión de la pestaña (`TerminalProfile`; lo que no dice, de Ajustes): tema, fuente, historial,
    /// teclado y prompt. Al abrir, al reconectar, al guardar las sesiones y al cambiar Ajustes.
    func applyProfile(to s: TerminalSession) {
        let e = s.profile.resolved(theme: themes.current.id, fontFamily: settings.fontFamily, fontSize: settings.fontSize,
                                   scrollback: settings.scrollback, session: s.route.sessionName ?? s.title,
                                   themeExists: { [themes] in themes.theme(id: $0) != nil }, fontInstalled: Fonts.isInstalled)
        let th = themes.theme(id: e.theme) ?? themes.current
        s.apply(theme: th, font: terminalFont(theme: th, family: e.fontFamily, size: e.fontSize))
        s.apply(scrollback: e.scrollback, optionAsMeta: e.optionAsMeta, backspaceSendsCtrlH: e.backspaceSendsCtrlH)
        s.promptRule = e.prompt
    }

    /// El perfil guardado de la sesión de `s` (sin sesión guardada, todo de Ajustes).
    private func refreshProfile(_ s: TerminalSession) {
        s.profile = s.route.transientProfile ?? s.route.sessionName.flatMap(sessions.profile(named:))?.terminal ?? TerminalProfile()
        applyProfile(to: s)
        applyHighlight(to: s)
    }

    // MARK: - pestañas

    func open(_ profile: SessionProfile) {
        do {
            let r = try sessions.route(to: profile)
            open(r)
            noteRecent(profile.name)
        } catch {
            status = "✗ \(error.localizedDescription)"
        }
    }

    // MARK: - gestor de sesiones (el ssh_config de NetDeck)

    func openSettings(_ tab: String? = nil) {
        guard !sharedEditorBusy() else { return }
        core.refreshKeychain()
        if let tab { settingsTab = tab }
        showSettings = true
    }

    func editSessions(_ focus: EditorFocus? = nil) {
        guard !sharedEditorBusy() else { return }
        core.refreshKeychain()
        editorFocus = focus
        sheet = .sessions
    }

    /// Una hoja. Las que editan datos de todas las ventanas (sesiones, listas, macros, túneles), sólo si no están ya
    /// abiertas en otra (`sharedEditorBusy`).
    func present(_ s: Sheet) {
        if Self.sharedSheets.contains(s), sharedEditorBusy() { return }
        sheet = s
    }

    /// Las hojas que editan datos de todas las ventanas sobre una copia que se guarda entera (ssh_config, listas.json,
    /// macros.json, tuneles.json).
    private static let sharedSheets: Set<Sheet> = [.sessions, .list, .macros, .tunnels]

    /// Ajustes (con sus Sesiones, Listas, Botones, Resaltado…) o una de esas hojas: abiertos en dos ventanas, el último
    /// en guardar pisaría lo del otro. Sólo en una a la vez.
    var editsSharedData: Bool { showSettings || sheet.map(Self.sharedSheets.contains) == true }

    /// Otra ventana los tiene abiertos (y no se cambia nada debajo de ellos: borrar una sesión, ordenar botones…).
    var sharedEditorElsewhere: AppModel? { core.attachedWindows.first { $0 !== self && $0.editsSharedData } }

    /// Si otra ventana ya los tiene abiertos: la trae delante, lo dice allí y devuelve true (aquí no se abre nada).
    private func sharedEditorBusy() -> Bool {
        guard let other = sharedEditorElsewhere else { return false }
        other.window?.makeKeyAndOrderFront(nil)
        other.status = L("✗ Esto ya se está editando aquí: guárdalo o ciérralo antes de abrirlo en otra ventana")
        return true
    }

    /// Más que estas de golpe se preguntan antes de abrirlas.
    static let groupConfirmAbove = 8
    /// Abriendo un grupo (o preguntando si se abre): un segundo clic no lo repite.
    @ObservationIgnored private var openingGroup = false

    /// Las sesiones de una carpeta («# @grupo», con «/» = subcarpetas) y de sus subcarpetas, en el orden del árbol.
    func profiles(inGroup path: String) -> [SessionProfile] {
        GroupTree.items(under: path, in: sessions.groups.map { (name: $0.name, items: $0.profiles) })
    }

    /// «Abrir las N» (barra lateral y menú «+»): todas las de la carpeta y sus subcarpetas, cada una en su pestaña; con
    /// `split`, si son varias, en la vista dividida. Más de `groupConfirmAbove` se preguntan antes.
    func openGroup(_ path: String, split: Bool = true) async {
        let ps = profiles(inGroup: path)
        guard !ps.isEmpty, !openingGroup else { return }
        openingGroup = true
        defer { openingGroup = false }
        if ps.count > Self.groupConfirmAbove {
            guard await ThemedAlert.confirm(L("¿Abrir las \(ps.count) sesiones de «\(L(nombre: path))»?"),
                                            message: L("Cada una en su pestaña (también las de sus subcarpetas)."),
                                            ok: L("Abrir las \(ps.count)")) else { return }
        }
        let before = Set(tabs.map(\.id))
        for p in ps { open(p) }
        let new = tabs.filter { !before.contains($0.id) }.map(\.id)
        DebugLog.log("sesiones", "grupo «\(path)»: \(new.count) de \(ps.count) abiertas\(split ? " (vista dividida)" : "")")
        guard split, new.count > 1 else { return }
        self.split = Split(layout: new.count <= 4 ? .grid4 : .grid, panes: new)
        showSplit = true
    }

    /// Guarda el ssh_config de NetDeck fuera del hilo principal («ssh -G» puede tardar: la ventana no se congela). Antes,
    /// copia de las de ahora (sin ella no se guarda nada) y que el ssh_config de Ajustes (~/.ssh/config u otro elegido)
    /// lo incluya; si falla algún paso, no se sigue y el error sale también como aviso (✗ en `status`).
    func saveSessions(_ file: SessionFile) async -> String? {
        guard !savingSessions else { return L("Ya se están guardando las sesiones") }    // (dos clics seguidos)
        savingSessions = true
        defer { savingSessions = false }
        if let err = await file.saveInBackground(including: settings.sshConfigURL, backup: .standard) {
            ErrorLog.error("sesiones", "no se han podido guardar: \(err)")
            status = "✗ \(err)"
            return err
        }
        reloadSessions()
        if !file.sessions.isEmpty { UserDefaults.standard.set(true, forKey: Self.hadSessionsKey) }
        status = L("Sesiones guardadas (\(file.sessions.count))")
        return nil
    }
    /// (una sola vez a la vez, aunque se guarde desde dos ventanas)
    private var savingSessions: Bool {
        get { core.savingSessions }
        set { core.savingSessions = newValue }
    }

    var sessionFile: SessionFile { (try? SessionFile(contentsOf: SessionFile.defaultURL)) ?? SessionFile() }

    /// Hubo sesiones guardadas en este Mac: sólo entonces, si falta el archivo, se recupera (quien usa sólo su
    /// ~/.ssh/config no lo tiene nunca, y no se le crea ni se mira su carpeta Documentos).
    private static let hadSessionsKey = "sesionesGuardadas"

    /// Antes de leer nada: si falta el archivo de sesiones y consta que las había (p. ej. el desinstalador de NetDeck
    /// borra ~/.config/netdeck entera y el Include de ~/.ssh/config), se recupera de la mejor copia y se vuelve a
    /// incluir; si está pero falta sólo el Include, se vuelve a poner; y al estrenar versión, copia de todo (actualizar
    /// arrastrando el .dmg no pasa por el Updater).
    private func protectUserData() {
        let backup = DataBackup.standard
        let d = UserDefaults.standard
        if !sessionFile.sessions.isEmpty { d.set(true, forKey: Self.hadSessionsKey) }
        // (el ssh_config elegido en Ajustes, o ~/.ssh/config: el que tiene que incluir las sesiones)
        let config = settings.sshConfigURL
        if d.bool(forKey: Self.hadSessionsKey), let (source, n) = backup.recoverSessionsIfMissing() {
            SessionFile.ensureInclude(sshConfig: config)
            status = L("✗ Faltaba el archivo de sesiones: recuperadas \(n) sesiones de \(AppPaths.tilde(source.path))")
        } else {
            do {
                // (el archivo estaba, pero el ssh_config ya no lo incluía o no existía: la lista salía vacía)
                if try backup.restoreIncludeIfMissing(sshConfig: config) {
                    status = L("✗ \(AppPaths.tilde(config.path)) no incluía tus sesiones: vuelto a incluir (copia del anterior junto a él)")
                }
            } catch {
                ErrorLog.error("sesiones", "no se ha podido comprobar el Include en \(AppPaths.tilde(config.path)): \(error.localizedDescription)")
                status = L("✗ No se ha podido comprobar que \(AppPaths.tilde(config.path)) incluya tus sesiones: \(error.localizedDescription)")
            }
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        if d.string(forKey: "ultimaVersion") != version {
            backup.snapshot(reason: "version-\(version)")
            d.set(version, forKey: "ultimaVersion")
        }
    }

    private static var favoritesFile: URL { AppPaths.netdeck.appendingPathComponent("favoritas") }
    private static var recentsFile: URL { AppPaths.netdeck.appendingPathComponent("recientes") }

    func loadFavorites() {
        favorites = ((try? String(contentsOf: Self.favoritesFile, encoding: .utf8)) ?? "")
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var seen = Set<String>()
        recents = ((try? String(contentsOf: Self.recentsFile, encoding: .utf8)) ?? "")
            .components(separatedBy: .newlines).reversed()
            .compactMap { $0.split(separator: "\t").last.map(String.init) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(10).map { $0 }
    }

    func toggleFavorite(_ name: String) {
        if favorites.contains(name) { favorites.removeAll { $0 == name } } else { favorites.append(name) }
        AppPaths.ensure(AppPaths.netdeck)
        do {
            try SafeFile.write(favorites.joined(separator: "\n") + (favorites.isEmpty ? "" : "\n"), to: Self.favoritesFile)
        } catch {
            ErrorLog.error("favoritas", "no se han podido guardar: \(error.localizedDescription)")
        }
    }

    private func noteRecent(_ name: String) {
        recents.removeAll { $0 == name }
        recents.insert(name, at: 0)
        if recents.count > 10 { recents.removeLast() }
        // (las capturas de desarrollo no tocan tus recientes, como tampoco tus pestañas)
        guard ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] == nil else { return }
        AppPaths.ensure(AppPaths.netdeck)
        let line = "\(Int(Date().timeIntervalSince1970))\t\(name)\n"
        if let h = try? FileHandle(forWritingTo: Self.recentsFile) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: Self.recentsFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - al arrancar: sesión de inicio y terminal local

    /// La sesión marcada «Abrir al arrancar» (si sigue existiendo).
    var startupProfile: SessionProfile? {
        settings.startupSession.isEmpty ? nil : sessions.profile(named: settings.startupSession)
    }

    /// Marcar (o desmarcar, si ya lo era) la sesión que se abre al arrancar.
    func toggleStartup(_ name: String) {
        settings.startupSession = settings.startupSession == name ? "" : name
    }

    func openStartupSession() {
        if let p = startupProfile { open(p) } else { status = L("✗ No hay sesión de inicio: márcala con clic derecho en una sesión") }
    }

    /// La sesión de inicio (si no la ha abierto ya «reabrir») y, si no hay ninguna pestaña, la terminal local.
    private func openStartupTabs() {
        if let p = startupProfile, !core.isOpenAnywhere(p.name) {
            DebugLog.log("app", "sesión de inicio «\(p.name)»")
            open(p)
        }
        if settings.startupLocalTerminal, tabs.isEmpty { openLocal() }
    }

    /// Pestaña SFTP/FTP: vista gráfica (explorador) o la consola sftp. La consola arranca la primera vez que se pide.
    func setConsole(_ on: Bool, in s: TerminalSession) {
        guard s.browser != nil, !on || s.route.transport == .sftp else { return }
        s.showConsole = on
        if on {
            s.startIfNeeded()
            DispatchQueue.main.async { s.view.window?.makeFirstResponder(s.view) }
        } else {
            s.browser?.connect()
        }
    }

    /// «Enviar a…»: de un explorador a la carpeta en la que está otro, de servidor a servidor (en memoria).
    func send(_ entries: [RemoteEntry], from: RemoteBrowser, to: RemoteBrowser) {
        guard let src = from.fs, let dst = to.fs, !entries.isEmpty else { return }
        // (mismo servidor y misma carpeta: «sustituir» apartaría y borraría el original. Aviso rápido aquí; si se llega
        //  a la misma carpeta por otro camino —otro nombre del equipo, otro usuario, un enlace—, `SourceGuard` la para)
        if from.route.target.host == to.route.target.host, from.route.target.port == to.route.target.port,
           from.route.transport == to.route.transport, entries.contains(where: { RemotePath.parent($0.path) == to.path }) {
            status = L("✗ Es la misma carpeta del mismo servidor: elige otra de destino")
            return
        }
        let names = Set(to.entries.map(\.name))
        let clash = entries.map(\.name).filter(names.contains)
        let dir = to.path
        Task {
            if !clash.isEmpty, !(await ThemedAlert.confirm(L("Ya existe en \(dir): \(clash.prefix(3).joined(separator: ", "))"),
                                                           message: L("Se sustituirá lo que haya en el servidor de destino."),
                                                           ok: L("Sustituir"), destructive: true)) {
                return
            }
            // (mientras se preguntaba, alguno pudo desconectarse o cambiar de carpeta)
            guard from.fs === src, to.fs === dst, to.path == dir else { return }
            transfers.bridge(entries, from: src, to: dst, dir: dir)
            status = L("Copiando de «\(from.route.title)» a «\(to.route.title)»…")
        }
    }

    /// Refresca (una vez cada uno) los exploradores de ese servidor que enseñan alguna de esas carpetas, en cualquier ventana.
    func refreshBrowsers(showing dirs: Set<String>, of fs: any RemoteFileSystem, except: RemoteBrowser? = nil) {
        core.refreshBrowsers(showing: dirs, of: fs, except: except)
    }

    /// Todos los exploradores: los de las pestañas SFTP/FTP y los laterales de las ssh, de todas las ventanas («Enviar a…»
    /// llega también a los de otra ventana).
    var allBrowsers: [(TerminalSession, RemoteBrowser)] { core.allBrowsers }

    // MARK: - explorador lateral

    /// Mostrar u ocultar el explorador SFTP al lado del terminal ssh (⇧⌘B). Ocultarlo no corta su conexión.
    func toggleSidePanel(_ s: TerminalSession) {
        guard SFTPPanel.offers(s.route) || s.sidePanel != nil else { return }
        let key = SFTPPanel.key(for: s.route)
        let p = s.sidePanel ?? SFTPSidePanel(key: key, layout: panelStore.layout(for: key), model: self)
        s.sidePanel = p
        if p.visible {
            p.visible = false
            p.waitingForLogin = false
            DispatchQueue.main.async { s.view.window?.makeFirstResponder(s.view) }
        } else {
            p.show(in: s)
        }
        rememberPanel(p)
    }

    func rememberPanel(_ p: SFTPSidePanel) {
        guard ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] == nil else { return }   // (las capturas no cuentan)
        do { try panelStore.set(p.layout, for: p.key) } catch {
            ErrorLog.warning("panel-sftp", "no se ha podido guardar: \(error.localizedDescription)")
        }
    }

    /// Borrar una sesión desde la lista (pregunta antes; queda copia en ssh_config.anterior).
    func deleteSession(_ name: String) {
        guard !askingDelete, !sharedEditorBusy() else { return }    // (dos clics seguidos: un solo aviso)
        askingDelete = true
        Task {
            defer { askingDelete = false }
            guard await ThemedAlert.confirm(L("¿Borrar la sesión «\(name)»?"), message: L("Queda una copia en ssh_config.anterior. Su contraseña del Llavero no se toca."), ok: L("Borrar"), destructive: true) else { return }
            // (el archivo, leído después de preguntar: no se pierde lo que cambiara mientras tanto)
            var f = sessionFile
            guard let i = f.sessions.firstIndex(where: { $0.name == name }) else { return }
            f.sessions.remove(at: i)
            if await saveSessions(f) != nil { return }
            if favorites.contains(name) { toggleFavorite(name) }
        }
    }

    /// El salto de «s» no deja reenviar (-J): ¿entrar en él y escribir allí «ssh destino»? Se pregunta siempre (un
    /// salto hostil podría provocarlo para ver la contraseña del destino), fuera del gesto y con la pestaña aún abierta.
    func confirmHop(_ s: TerminalSession, _ r: ConnectionRoute) async -> Bool {
        let jump = r.target.description, cmd = r.thenCommand ?? ""
        guard tabs.contains(where: { $0.id == s.id }) else { return false }
        let ok = await ThemedAlert.confirm(
            L("«\(s.title)»: el salto no deja reenviar (-J)"),
            message: L("Para llegar, la app entraría en «\(jump)» y escribiría allí «\(cmd)». Lo que escribas después (también la contraseña del destino) pasará por la shell de ese salto: hazlo sólo si confías en él. La contraseña del destino no se escribirá sola."),
            ok: L("Entrar por el salto"), over: s.view.window)
        return ok && tabs.contains(where: { $0.id == s.id })
    }

    /// La clave del equipo de «s» no es la de known_hosts: ¿quitar la vieja y reconectar? Como MobaXterm o SecureCRT,
    /// pero «Cancelar» es lo de por defecto: puede ser alguien interceptando la conexión.
    func confirmHostKey(_ s: TerminalSession, _ m: HostKeyMismatch) async -> Bool {
        guard tabs.contains(where: { $0.id == s.id }) else { return false }
        let host = m.host ?? s.route.target.host
        var message = L("La clave que presenta el equipo no es la guardada en known_hosts. Puede que se haya reinstalado o cambiado, o que alguien esté interceptando la conexión (ataque «man in the middle»). Acepta sólo si sabes por qué ha cambiado.")
        if let fp = m.fingerprint { message += "\n\n" + L("Huella de la clave nueva (\(m.keyType ?? "?")): \(fp)") }
        if let f = m.file {
            let place = m.line.map { "\(AppPaths.tilde(f)):\($0)" } ?? AppPaths.tilde(f)
            message += "\n" + L("Clave antigua en \(place)")
        }
        let r = await ThemedAlert.run(L("⚠️ La clave del equipo «\(host)» ha cambiado"), message: message,
                                      buttons: [L("Cancelar"), L("Aceptar y Actualizar Clave")], destructive: 1, over: s.view.window)
        return r.button == 1 && tabs.contains(where: { $0.id == s.id })
    }

    /// Terminal local: tu shell de inicio, como shell de login, en tu carpeta.
    func openLocal() { open(ConnectionRoute.local()) }

    @discardableResult
    func open(_ route: ConnectionRoute) -> TerminalSession {
        let route = sessions.refreshConfigJumps(route)          // (una pestaña guardada: el salto del ssh_config de ahora)
        // (la local y la consola serie no son un equipo por red: ni askpass ni contraseñas automáticas)
        let pw = PasswordAutomation(mode: route.usesPasswords ? settings.devicePasswordMode : .off, store: store, policy: policy, ledger: ledger)
        pw.onlySuggestDevices = route.manualHop == true
        let s = TerminalSession(route: route, passwords: pw, ledger: ledger)
        // (sesiones y ajustes son de todas las ventanas: sigue valiendo si la pestaña pasa a otra)
        pw.candidates = { [weak core = self.core, weak pw] req in
            guard let core, let pw, let target = pw.commandTarget else { return [] }
            // («Password:» escueto: el equipo sólo se sabe por la orden enviada, el usuario por ella o por el login)
            var request = req
            if request.account == nil, let user = request.user ?? pw.commandUser {
                request.account = "\(user)@\(target.host)"
            }
            if let account = request.account, let at = account.lastIndex(of: "@"),
               !core.sessions.expectedHosts(route: nil, typed: pw.commandHosts).contains(String(account[account.index(after: at)...]).lowercased()) {
                return []
            }
            return core.sessions.credentialCandidates(for: request, route: nil, defaultCredential: core.settings.defaultCredential,
                                                       typedHosts: pw.commandHosts, typedTarget: target)
        }
        wire(s)
        refreshProfile(s)
        if route.transport == .sftp || route.transport == .ftp { s.browser = RemoteBrowser(route: route, model: self) }
        // (el explorador lateral recordado como visible: se ve, y conecta cuando entre el terminal)
        let panelKey = SFTPPanel.key(for: route)
        if SFTPPanel.offers(route), panelStore.layout(for: panelKey).visible {
            let p = SFTPSidePanel(key: panelKey, layout: panelStore.layout(for: panelKey), model: self)
            s.sidePanel = p
            p.show(in: s)
        }
        tabs.append(s)
        selection = s.id
        syncMultiExec()
        saveOpenTabs()
        let askpass = askpassEnvironment(for: s)
        if settings.logEnabled { s.startLog(in: settings.logURL) }
        if s.browser != nil {
            s.deferredEnvironment = askpass           // (la consola sftp, cuando se pida; el explorador conecta solo)
            s.browser?.connect()
        } else {
            s.start(extraEnvironment: askpass)
        }
        status = route.usesPasswords ? L("Conectando a \(route.title)…") : ""
        return s
    }

    /// Lo que la pestaña le pide a su ventana (avisos, teclado, reconectar, cerrar y las preguntas): a ésta. Se vuelve a
    /// hacer al pasarla de una ventana a otra.
    private func wire(_ s: TerminalSession) {
        passwordOffers[s.id] = s.passwords.offer
        s.passwords.onOfferChange = { [weak self, weak s] offer in
            guard let self, let s else { return }
            self.passwordOffers[s.id] = offer
            if offer == nil, let notice = self.notices[s.id] {
                switch notice {
                case .suggested, .manual: self.notices[s.id] = nil
                default: break
                }
            }
        }
        s.onEvent = { [weak self] s, e in self?.handle(e, in: s) }
        s.onInput = { [weak self] s, bytes in self?.userInput(bytes, in: s) ?? false }
        s.onReconnect = { [weak self] s in self?.reconnect(s) }
        s.onCloseRequest = { [weak self] s in self?.close(s) }
        s.confirmHop = { [weak self] s, r in await self?.confirmHop(s, r) ?? false }
        s.onHostKeyChanged = { [weak self] s, m in await self?.confirmHostKey(s, m) ?? false }
        s.onLogFailed = { [weak self] _, message in self?.status = message }
        s.onProblem = { [weak self] _, message in self?.status = message }
        s.onForwardingRefused = { [weak self] s in
            do { return try self?.sessions.typedHop(for: s.route) } catch {
                DebugLog.log("salto", "«\(s.title)»: \(error.localizedDescription)")
                return nil
            }
        }
        s.askpassEnvironment = { [weak self, weak s] in
            guard let self, let s else { return [:] }
            return self.askpassEnvironment(for: s)
        }
        s.browser?.retarget(self)
        s.sidePanel?.retarget(self)
    }

    func close(_ s: TerminalSession) {
        DebugLog.log("pestaña", "«\(s.title)» cerrada")
        s.gate.abortAll()
        s.terminate()
        _ = Askpass.takeGiven(session: s.id)             // (lo que dejó el askpass si se cierra antes de entrar)
        if recording == s.id { stopRecording() }
        notices[s.id] = nil
        detach(s)
        saveOpenTabs()
    }

    /// Quita `s` de esta ventana (de la fila, de la vista dividida y de MultiExec) sin tocar su conexión: al cerrarla y
    /// al pasarla a otra ventana.
    private func detach(_ s: TerminalSession) {
        multiExec.leave(s)
        excluded.remove(s.id)
        let i = tabs.firstIndex { $0 === s } ?? 0
        tabs.removeAll { $0 === s }
        tabFrames[s.id] = nil
        if var sp = split, sp.panes.contains(s.id) {
            sp.panes.removeAll { $0 == s.id }
            split = sp.panes.isEmpty ? nil : sp
            if split == nil { showSplit = false }
        }
        if selection == s.id {
            selection = split.flatMap { sp in showSplit ? sp.panes.first : nil }
                ?? (tabs.indices.contains(i) ? tabs[i].id : tabs.last?.id)
        }
        syncMultiExec()
    }

    // MARK: - pasar una pestaña a otra ventana (sin cortar la conexión)

    /// Por qué no se puede sacar `s` de esta ventana ahora (nil: se puede). Grabando una macro en ella o con una
    /// secuencia en marcha (pegado, macro, lista), no: lo que se le está escribiendo es de esta ventana.
    func moveBlocker(_ s: TerminalSession) -> String? {
        // (una hoja abierta —pegado, rellenar un botón, macros— escribe en la pestaña elegida: no se le cambia debajo)
        if modalOpen { return L("✗ Cierra antes lo que tienes abierto en esta ventana para mover la pestaña") }
        if recording == s.id { return L("✗ Para la grabación de la macro antes de mover la pestaña") }
        if automationReservation.contains(s.id) || s.gate.isBusy || sharedGate.isBusy {
            return L("⏳ Hay una secuencia en marcha: Esc para cortarla antes de mover la pestaña")
        }
        return nil
    }

    /// Pasa `s` a la ventana de `target` (con su terminal, su conexión, su explorador y su aviso de contraseña), en
    /// `index` (nil: al final). Si ésta se queda sin pestañas, se cierra. false si ahora no se puede (y lo dice).
    @discardableResult
    func moveTab(_ s: TerminalSession, to target: AppModel, at index: Int? = nil) -> Bool {
        guard target !== self, tabs.contains(where: { $0 === s }) else { return false }
        if let why = moveBlocker(s) { status = why; return false }
        // (allí, una hoja abierta escribiría en la pestaña que llega, que pasaría a ser la elegida)
        guard !target.modalOpen else {
            status = L("✗ La otra ventana tiene algo abierto (pegado, Ajustes…): ciérralo antes de llevarle la pestaña")
            return false
        }
        let notice = notices.removeValue(forKey: s.id)
        passwordOffers[s.id] = nil
        let confirmed = anywayConfirmed.remove(s.id) != nil
        let wasExcluded = excluded.contains(s.id)
        detach(s)
        target.adopt(s, notice: notice, anywayConfirmed: confirmed, excluded: wasExcluded, at: index)
        DebugLog.log("ventana", "«\(s.title)» pasa a otra ventana (\(tabs.count) quedan aquí, \(target.tabs.count) allí)")
        if tabs.isEmpty, core.attachedWindows.count > 1 { window?.close() }      // (vacía: sobra, como en Safari)
        saveOpenTabs()
        return true
    }

    /// Recibe una pestaña de otra ventana: la engancha a ésta, la deja elegida y trae la ventana delante. Si venía
    /// fuera de MultiExec sigue fuera; y si aquí está encendido, entra fuera (lo que escribas no le llega sin decidirlo).
    private func adopt(_ s: TerminalSession, notice: PasswordAutomation.Event?, anywayConfirmed confirmed: Bool,
                       excluded wasExcluded: Bool, at index: Int?) {
        wire(s)
        if let i = index, i <= tabs.count { tabs.insert(s, at: i) } else { tabs.append(s) }
        if let notice { notices[s.id] = notice }
        if confirmed { anywayConfirmed.insert(s.id) }
        if wasExcluded || multiExecOn { excluded.insert(s.id) }
        show(s)
        syncMultiExec()
        if multiExecOn, s.route.acceptsMultiExec {
            status = L("«\(s.title)» queda fuera de MultiExec en esta ventana: inclúyela con clic derecho si quieres")
        }
        window?.makeKeyAndOrderFront(nil)
    }

    /// «Mover a una ventana nueva»: una ventana con ella, en `frame` (nil: donde la ponga macOS). La conexión sigue.
    func moveTabToNewWindow(_ s: TerminalSession, frame: CGRect? = nil) {
        guard tabs.contains(where: { $0 === s }) else { return }
        if let why = moveBlocker(s) { status = why; return }
        core.openWindow(moving: (self, s.id), frame: frame)
    }

    /// Una pestaña arrastrada y soltada fuera de esta ventana, en `point` (pantalla): a la ventana de la app que haya
    /// ahí (en su barra, en el sitio en que cae) o a una nueva con su barra bajo el puntero (`grab`: dónde se cogió,
    /// desde arriba a la izquierda de esta ventana). Con una sola pestaña, se mueve la ventana entera. false: no ha
    /// salido de esta ventana (es reordenar) o no se puede.
    @discardableResult
    func dropTab(_ s: TerminalSession, at point: CGPoint, grab: CGPoint) -> Bool {
        guard let w = window, !w.frame.contains(point) else { return false }
        let other = core.window(at: point)
        DebugLog.log("ventana", "«\(s.title)» soltada en \(point): \(other == nil ? "fuera de las ventanas" : other === self ? "esta" : "otra ventana")")
        if let other {
            guard other !== self else { return false }
            return moveTab(s, to: other, at: other.tabIndex(at: point))
        }
        let frame = WindowPlacement.frame(droppingAt: point, size: w.frame.size, grab: grab,
                                          screens: NSScreen.screens.map(\.visibleFrame))
        if tabs.count == 1 {
            guard !fullScreen else { return false }
            w.setFrame(frame, display: true, animate: true)
            return true
        }
        moveTabToNewWindow(s, frame: frame)
        return true
    }

    /// Marcos de las pestañas en la ventana (de arriba a la izquierda, como `.global`): dónde cae una que llega de otra.
    @ObservationIgnored var tabFrames: [TerminalSession.ID: CGRect] = [:]

    /// En qué sitio de la barra de pestañas cae `point` (pantalla); nil si no cae en la barra (entonces, al final).
    func tabIndex(at point: CGPoint) -> Int? {
        guard let w = window, let content = w.contentView else { return nil }
        let p = w.convertPoint(fromScreen: point)
        let q = CGPoint(x: p.x, y: content.bounds.height - p.y)
        guard stillZones["pestañas"]?.insetBy(dx: -8, dy: -8).contains(q) == true else { return nil }
        return tabs.firstIndex { (tabFrames[$0.id]?.midX ?? .infinity) > q.x } ?? tabs.count
    }

    /// Arrastrar en la barra: `id` ocupa el sitio de `target` (como en Safari: si venía de la izquierda queda detrás,
    /// si de la derecha, delante). Sólo cambia el orden: la terminal y su proceso siguen igual. Se guarda al momento.
    func moveTab(_ id: TerminalSession.ID, to target: TerminalSession.ID) {
        guard id != target, let i = tabs.firstIndex(where: { $0.id == id }),
              let j = tabs.firstIndex(where: { $0.id == target }) else { return }
        tabs.move(fromOffsets: IndexSet(integer: i), toOffset: j > i ? j + 1 : j)
        saveOpenTabs()
    }

    func toggleLog(_ s: TerminalSession) {
        if s.logFile != nil { s.stopLog() } else { s.startLog(in: settings.logURL) }
    }

    func reconnect(_ s: TerminalSession) {
        // (una secuencia compartida tampoco puede saltar a una conexión nueva)
        sharedGate.abortAll(); s.gate.abortAll()
        DebugLog.log("pestaña", "«\(s.title)» reconectar")
        notices[s.id] = nil
        refreshProfile(s)
        if let b = s.browser, !s.showConsole { b.reconnect() } else { s.restart() }
    }

    /// El askpass de la pestaña (la contraseña de la sesión, sola) con los Ajustes de ahora: en cada conexión
    /// (`TerminalSession.askpassEnvironment`). Sin contraseña automática, o sin contraseñas (local, serie), nada.
    private func askpassEnvironment(for s: TerminalSession) -> [String: String] {
        guard settings.sessionAutoPassword, s.route.usesPasswords else { return [:] }
        return Askpass.environment(executable: Bundle.main.executablePath ?? CommandLine.arguments[0],
                                   configPath: settings.sshConfigURL.path,
                                   session: s.id, profile: s.route.sessionName, route: s.route)
    }

    /// Otra pestaña con la misma sesión (clonar).
    func duplicate(_ s: TerminalSession) { open(s.route) }

    /// ⌘W: la pestaña elegida; en una ventana que ya no tiene ninguna (y no es la única), la ventana.
    func closeCurrent() {
        if let s = current { close(s) } else if tabs.isEmpty, core.attachedWindows.count > 1 { askToCloseWindow() }
    }

    func selectNext(_ step: Int) {
        let ids = showSplit ? (split?.panes ?? []) : tabs.map(\.id)
        guard !ids.isEmpty else { return }
        let i = ids.firstIndex { $0 == selection } ?? 0
        selection = ids[(i + step + ids.count) % ids.count]
        current?.view.window?.makeFirstResponder(current?.view)
    }

    /// Elegir una pestaña desde la barra: si está en la vista dividida se ve allí; si no, sola.
    func show(_ s: TerminalSession) {
        if showSplit, split?.panes.contains(s.id) != true { showSplit = false }
        selection = s.id
    }

    private func updateVisibility() {
        let visible: Set<TerminalSession.ID> = showSplit ? Set(split?.panes ?? []) : (selection.map { [$0] } ?? [])
        for t in tabs {
            t.isVisible = visible.contains(t.id)
            if t.isVisible { t.activity = false }
        }
    }

    func jump(to device: String, via jump: String, user: String?, transport: SessionProfile.Transport) {
        do {
            let r = try sessions.jumpShortcut(to: device, via: jump, user: user, transport: transport)
            DebugLog.log("salto", "«\(device)» por «\(jump)»: abro \(r.command.arguments.joined(separator: " ")) y luego «\(r.thenCommand ?? "")»")
            open(r)
        } catch {
            status = "✗ \(error.localizedDescription)"
        }
    }

    /// Conexión rápida (portada / ⌘K): alias del ssh_config o usuario@equipo[:puerto], directo o por un salto.
    func quickConnect(_ text: String, via jump: String = "", user: String? = nil, transport: SessionProfile.Transport = .ssh) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if !jump.isEmpty {
            self.jump(to: t, via: jump, user: user, transport: transport)
        } else if let p = sessions.profile(named: t) {
            open(p)
        } else if var e = Endpoint(parsing: t) {
            if e.user == nil { e.user = user }
            open(ConnectionRoute(title: e.host, target: e, transport: transport))
        } else {
            status = L("✗ «\(t)» no es una sesión ni usuario@equipo")
        }
    }

    // MARK: - contraseñas

    private func handle(_ e: PasswordAutomation.Event, in s: TerminalSession) {
        switch e {
        case .typed(let r): status = L("🔑 «\(r)» escrita en \(s.title)"); notices[s.id] = nil
        case .confirmed: notices[s.id] = nil
        case .cancelled: status = L("⎋ Contraseña cancelada"); notices[s.id] = nil
        case .failed(let r): status = L("🔑 «\(r)» no ha valido: bloqueada 15 min en todas las pestañas"); notices[s.id] = e
        case .suggested, .manual: notices[s.id] = e
        }
    }

    func typePassword(_ ref: CredentialRef, in s: TerminalSession) {
        Task {
            switch await s.passwords.typeManually(ref, into: s) {
            case .typed: notices[s.id] = nil
            case .blocked: status = L("🔑 «\(ref)» falló hace poco: no la escribo (cuenta AD) · desbloquéala en Ajustes")
            case .notAsked: status = L("🔑 Ahí no piden contraseña ahora")
            case .missing: status = L("🔑 «\(ref)» no está en el Llavero")
            case .busy: status = L("🔑 Ya se está escribiendo una contraseña en «\(s.title)»; espera a que conteste")
            case .pending: break
            }
        }
    }

    func choosePassword(_ ref: CredentialRef, offer: PasswordAutomation.Offer, in s: TerminalSession) {
        Task {
            guard tabs.contains(where: { $0 === s }), !s.exited else { return }
            // (ocupada mientras se lee el Llavero: no se pasa a otra ventana a medias y el aviso sale en la suya)
            let sw = s.gate.begin()
            defer { s.gate.end(sw) }
            switch await s.passwords.choose(ref, offer: offer.id, into: s) {
            case .typed: notices[s.id] = nil
            case .blocked: status = L("🔑 «\(ref)» falló hace poco: no la escribo (cuenta AD) · desbloquéala en Ajustes")
            case .pending:
                status = L("🔑 Otra autenticación con «\(ref.account)» sigue pendiente; escríbela a mano o, si ya terminó, restablécela en Ajustes → Contraseñas → «Restablecer pendiente»")
            case .missing: status = L("🔑 «\(ref)» no está en el Llavero")
            case .notAsked, .busy: break
            }
        }
    }

    func dismissPasswordNotice(in s: TerminalSession) {
        s.cancelPasswordContext()
        notices[s.id] = nil
    }

    /// Pestañas en las que ya se ha confirmado «escribir sin esperar a que la pida» (se pregunta una vez por pestaña).
    @ObservationIgnored private var anywayConfirmed: Set<TerminalSession.ID> = []

    /// La manda al terminal aunque ahí no se reconozca «Password:» (prompts raros). Se confirma la primera vez en cada
    /// pestaña y siempre si está bloqueada por un fallo reciente. Nunca se registra.
    func typePasswordAnyway(_ ref: CredentialRef, in s: TerminalSession, pressReturn: Bool) {
        Task {
            if !anywayConfirmed.contains(s.id) {
                guard await ThemedAlert.confirm(L("¿Escribir «\(ref.account)» en «\(s.title)»?"), message: L("Va como texto al terminal aunque no pidan contraseña: si no es un prompt de contraseña, se verá en pantalla (y puede quedar en el historial del equipo)."), ok: L("Escribir")) else { return }
                anywayConfirmed.insert(s.id)
            }
            var force = false
            if ledger.isBlocked(ref) {
                guard await ThemedAlert.confirm(L("«\(ref.account)» ha fallado hace poco"), message: L("Si es una cuenta AD, otro intento fallido puede bloquearla. ¿Escribirla igualmente?"), ok: L("Escribir igualmente"), destructive: true) else { return }
                force = true
            }
            // (tras el aviso la pestaña puede haberse cerrado: nada se escribe en una que ya no está)
            guard tabs.contains(where: { $0.id == s.id }), !s.exited else { return }
            switch await s.passwords.typeAnyway(ref, into: s, pressReturn: pressReturn, force: force) {
            case .typed: notices[s.id] = nil; status = L("🔑 «\(ref)» escrita en \(s.title)")
            case .blocked: status = L("🔑 «\(ref)» falló hace poco: no la escribo (cuenta AD) · desbloquéala en Ajustes")
            case .notAsked, .busy, .pending: break
            case .missing: status = L("🔑 «\(ref)» no está en el Llavero")
            }
        }
    }

    /// Todas las del Llavero de NetDeck (para elegir a mano).
    var keychainAccounts: [CredentialRef] { core.keychainAccounts }
    func hasCredential(_ ref: CredentialRef) -> Bool { keychainAccounts.contains(ref) }

    // MARK: - pegado seguro y listas

    func paste(_ text: String, allowDangerous: Bool, toAll: Bool) async {
        let paster = SafePaster(allowDangerous: allowDangerous)
        if toAll {
            let sw = sharedGate.begin()
            let ids = Set(multiExec.terminals.filter(multiExec.accepts).compactMap { ($0 as? TerminalSession)?.id })
            guard let ticket = automationReservation.reserve(ids) else { sharedGate.end(sw); status = L("⏳ La pestaña ya tiene una secuencia en marcha; pulsa Esc para cortarla"); return }
            defer { sharedGate.end(sw); automationReservation.release(ticket) }
            let reports = await multiExec.paste(text, paster: paster, abort: sw)
            let failed = reports.contains { if case .completed = $0.outcome { false } else { true } }
            status = (failed ? "✗ " : "") + L("Pegado en \(reports.count): ") + reports.map { describe($0) }.joined(separator: " · ")
        } else if let s = current {
            guard s.route.acceptsMultiExec, macroAccepts(s) else { status = L("✗ El pegado seguro requiere una pestaña SSH/Telnet autenticada"); return }
            guard let ticket = automationReservation.reserve([s.id]) else { status = L("⏳ La pestaña ya tiene una secuencia en marcha; pulsa Esc para cortarla"); return }
            let sw = s.gate.begin()
            defer { s.gate.end(sw); automationReservation.release(ticket) }
            status = describe(await paster.paste(text, into: s, abort: sw))
        }
    }

    func run(_ list: JumpList) async {
        let sw = sharedGate.begin()
        defer { sharedGate.end(sw) }
        var byDevice: [Endpoint: TerminalSession] = [:]
        let runner = JumpBatchRunner(list: list, store: store, policy: policy, ledger: ledger, abort: sw) { [weak self] d in
            guard let self else { return nil }
            do {
                var r = try self.sessions.route(to: self.sessions.profile(named: list.jump) ?? SessionProfile(name: list.jump))
                r.title = d.host
                let s = self.open(r)
                byDevice[d] = s
                return s
            } catch {
                return nil
            }
        }
        runner.onChange = { [weak self] d, st in
            // ya en el salto: la del equipo la escribe la lista (un solo intento, nunca dos)
            if st == .connecting { byDevice[d]?.passwords.mode = .off }
            self?.status = "\(list.name) · \(d.host): \(st.texto)"
        }
        await runner.run()
        let ok = runner.status.values.filter { $0 == .connected }.count
        status = L("\(list.name): \(ok)/\(list.devices.count) dentro")
        // juntas en una vista; las que se han quedado en el salto, fuera de MultiExec (nada se ejecuta en el salto)
        let opened = list.devices.compactMap { byDevice[$0] }
        if opened.count > 1 {
            excluded.formUnion(list.devices.filter { runner.status[$0] != .connected }.compactMap { byDevice[$0]?.id })
            split = Split(layout: .grid, panes: opened.map(\.id))
            showSplit = true
        }
    }

    /// Las pestañas en las que está pegando el pegado a todas.
    @ObservationIgnored private let automationReservation = AutomationReservation()

    func abortAll() {
        sharedGate.abortAll()
        tabs.forEach { $0.gate.abortAll(); $0.cancelPasswordContext() }
    }

    private func describe(_ r: PasteReport) -> String {
        switch r.outcome {
        case .completed: L("✓ \(r.sent)/\(r.total) líneas")
        case .aborted: L("⎋ parado en \(r.sent)/\(r.total)")
        case .deviceError(let l, let out): L("✗ error en la línea \(l): \(out)")
        case .pager(let l): L("✗ paginador en la línea \(l) (falta «terminal length 0»)")
        case .timeout(let l): L("✗ sin prompt tras la línea \(l)")
        case .dangerousNotConfirmed(let l, let c): L("✗ línea \(l) peligrosa sin confirmar: \(c)")
        case .passwordPrompt(0): L("🔑 piden contraseña: no pego nada ahí")
        case .passwordPrompt(let l): L("🔑 piden contraseña tras la línea \(l): paro (la siguiente iría como contraseña)")
        }
    }

    // MARK: - teclado: Esc/Ctrl+C cortan lo automático; MultiExec reparte lo que escribes

    /// Lo que teclea (o pega) el usuario en una pestaña. true = ya atendido.
    private func userInput(_ bytes: [UInt8], in s: TerminalSession) -> Bool {
        if AbortKey.isAbort(bytes) { s.cancelPasswordContext() }
        if s.passwords.offer != nil, SecretPrompt.asks(s.cursorLine) { s.cancelPasswordContext() }
        // (si el usuario empieza a contestar durante la lectura automática, ésta ya no puede mezclar su secreto)
        if s.gate.isBusy, SecretPrompt.asks(s.cursorLine) { s.cancelPasswordContext() }
        if AbortKey.isAbort(bytes), s.gate.isBusy || sharedGate.isBusy {
            s.gate.abortAll()
            sharedGate.abortAll()
            status = L("⎋ Cancelado: no se envía nada más")
            if !bytes.contains(AbortKey.ctrlC) { return true }        // (Ctrl+C sí llega al equipo)
        }
        // Mientras se pega, lo tecleado no se mezcla con las líneas que se envían (sólo en el pegado: esperando un
        // salto puede tocar escribir una contraseña a mano).
        if automationReservation.contains(s.id) {
            status = L("⏳ Enviando… Esc para cortar (lo que tecleas no se envía)")
            return true
        }
        if let k = FunctionKey.name(bytes), let b = buttons.button(forKey: k) {      // F5, Mayús+F6…
            DebugLog.log("botones", "\(k) → «\(b.name)»")
            if selection != s.id, tabs.contains(where: { $0 === s }) { selection = s.id }   // (el panel donde se pulsa)
            runButton(b)
            return true
        }
        if recording == s.id { recorder?.feed(bytes, from: s) }      // (sólo lo tecleado; nunca lo que escribe la app)
        guard multiExecOn else { return false }
        let sent = multiExec.broadcast(bytes, from: s)
        if sent, bytes.contains(13) {
            DebugLog.log("multiexec", "Intro desde «\(s.title)» → \(multiExecTargets.map(\.title).joined(separator: ", "))")
        }
        return sent
    }

    // MARK: - túneles

    /// Los túneles guardados (tuneles.json) y sus procesos ssh (`Tunnels.swift`): de la app, no de una ventana.
    var tunnels: TunnelLibrary {
        get { core.tunnels }
        set { core.tunnels = newValue }
    }
    var tunnelsError: String? {
        get { core.tunnelsError }
        set { core.tunnelsError = newValue }
    }
    var tunnelWarnings: [String] {
        get { core.tunnelWarnings }
        set { core.tunnelWarnings = newValue }
    }
    var tunnelRunner: TunnelManager { core.tunnelRunner }
    /// La «sesión» del askpass de cada túnel en marcha (para confirmar la contraseña que ha valido).
    var tunnelAskpass: [Tunnel.ID: UUID] {
        get { core.tunnelAskpass }
        set { core.tunnelAskpass = newValue }
    }

    var workspaces: WorkspaceLibrary {
        get { core.workspaces }
        set { core.workspaces = newValue }
    }
    var workspacesError: String? {
        get { core.workspacesError }
        set { core.workspacesError = newValue }
    }

    // MARK: - macros

    /// Las macros guardadas (macros.json). Cargarlas no ejecuta nada: sólo `runMacro`, desde un clic del usuario.
    var macros: MacroLibrary {
        get { core.macros }
        set { core.macros = newValue }
    }
    /// macros.json no se ha podido usar (ilegible, roto o de otra versión): no se toca; al guardar se aparta.
    var macrosError: String? {
        get { core.macrosError }
        set { core.macrosError = newValue }
    }
    var macroWarnings: [String] {
        get { core.macroWarnings }
        set { core.macroWarnings = newValue }
    }
    /// Pestaña en la que se graba.
    var recording: TerminalSession.ID?
    @ObservationIgnored private var recorder: MacroRecorder?
    /// Lo recién grabado, para el editor.
    var macroDraft: Macro?
    /// Hay una macro reproduciéndose (el botón ■ la para).
    var macroRunning = false

    func reloadMacros() {
        let r = MacroLibrary.load()
        macros = r.library
        macrosError = r.error
        macroWarnings = r.warnings
        if let e = r.error {
            ErrorLog.error("macros", e)
            status = "✗ " + e
        }
        r.warnings.forEach { ErrorLog.warning("macros", $0) }
    }

    func saveMacros(_ lib: MacroLibrary) -> String? {
        do {
            try lib.save(setAsideUnusable: macrosError != nil)
            macros = lib
            macrosError = nil
            macroWarnings = []
            status = L("Macros guardadas (\(lib.macros.count)) en \(AppPaths.tilde(MacroLibrary.defaultURL.path))")
            return nil
        } catch {
            ErrorLog.error("macros", "no se han podido guardar: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    /// Grabar en la pestaña activa (o parar y abrir el editor con lo grabado).
    func toggleRecording() {
        if recording != nil { stopRecording(); return }
        guard let s = current, !s.exited, s.browser == nil || s.showConsole else {
            status = L("✗ Para grabar una macro, abre antes una pestaña de terminal")
            return
        }
        let r = MacroRecorder()
        r.awaitingAuth = multiExec.awaitingAuth
        recorder = r
        recording = s.id
        DebugLog.log("macros", "grabando en «\(s.title)»")
        status = L("● Grabando una macro en «\(s.title)»: escribe las órdenes (las contraseñas no se graban)")
        s.view.window?.makeFirstResponder(s.view)
    }

    func stopRecording() {
        guard let r = recorder else { return }
        recorder = nil
        recording = nil
        DebugLog.log("macros", "grabación parada: \(r.lines.count) líneas, \(r.skipped) sin grabar")
        guard !r.lines.isEmpty else {
            status = L("Grabación parada: no hay órdenes que guardar")
            return
        }
        macroDraft = Macro(name: macros.uniqueName(L("macro")), steps: r.steps)
        status = L("■ Grabadas \(r.lines.count) órdenes") + (r.skipped > 0 ? L(" · \(r.skipped) sin grabar (secretos)") : "")
        if !modalOpen { present(.macros) }
    }

    /// Reproduce una macro en la pestaña activa o en las de MultiExec que aceptan lo repartido. Sólo desde un clic.
    func runMacro(_ m: Macro, toAll: Bool) async {
        if let p = m.problem { status = L("✗ Macro «\(m.name)»: \(p)"); return }
        guard !macroRunning else { status = L("⏳ Ya hay una macro en marcha (■ para pararla)"); return }
        let targets: [TerminalSession] = toAll ? multiExecTargets.filter(multiExec.accepts)
                                               : (current.map { [$0] } ?? []).filter(macroAccepts)
        guard !targets.isEmpty else { status = L("✗ No hay ninguna pestaña donde reproducir «\(m.name)»"); return }
        if recording != nil, targets.contains(where: { $0.id == recording }) {
            status = L("✗ Para la grabación antes de reproducir una macro en esa pestaña")
            return
        }
        let names = targets.map(\.title).joined(separator: ", ")
        if m.confirm, !(await ThemedAlert.confirm(L("¿Reproducir «\(m.name)»?"),
                                                 message: L("\(m.lines.count) órdenes en \(names)"), ok: L("Reproducir"))) { return }
        let dangerous = m.dangerousLines
        if !dangerous.isEmpty, !(await ThemedAlert.confirm(L("«\(m.name)» lleva órdenes peligrosas"),
                                                          message: dangerous.prefix(5).joined(separator: "\n") + L("\n\nEn: \(names)"),
                                                          ok: L("Reproducir igualmente"), destructive: true)) {
            status = L("⎋ «\(m.name)» no se ha reproducido")
            return
        }
        // (tras el aviso pueden haberse cerrado o haber empezado a autenticarse: se vuelve a mirar)
        let live = targets.filter { t in tabs.contains { $0 === t } && !t.exited && (toAll ? multiExec.accepts(t) : macroAccepts(t)) }
        guard !live.isEmpty else { return }
        guard let ticket = automationReservation.reserve(Set(live.map(\.id))) else {
            status = L("⏳ La pestaña ya tiene una secuencia en marcha; pulsa Esc para cortarla"); return
        }
        let player = MacroPlayer(allowDangerous: !dangerous.isEmpty)
        macroRunning = true
        DebugLog.log("macros", "«\(m.name)» en \(live.map(\.title))")
        status = L("▶ «\(m.name)»") + (live.count > 1 ? " ×\(live.count)" : "") + L(" · Esc para cortar")
        defer { macroRunning = false; automationReservation.release(ticket) }
        if toAll {
            let sw = sharedGate.begin()
            defer { sharedGate.end(sw) }
            let tasks = live.map { s in Task { @MainActor in await player.run(m, on: s, abort: sw) } }
            var reports: [MacroReport] = []
            for t in tasks { reports.append(await t.value) }
            let failed = reports.contains { $0.outcome != .completed }
            status = (failed ? "✗ " : "") + L("«\(m.name)» en \(reports.count): ") + reports.map(describe).joined(separator: " · ")
        } else if let s = live.first {
            let sw = s.gate.begin()
            defer { s.gate.end(sw) }
            status = "\(describe(await player.run(m, on: s, abort: sw))) · «\(m.name)»"
        }
    }

    private func describe(_ r: MacroReport) -> String {
        switch r.outcome {
        case .completed: L("✓ \(r.sent)/\(r.total) órdenes")
        case .aborted: L("⎋ parada en \(r.sent)/\(r.total)")
        case .deviceError(let n, let out): L("✗ error en el paso \(n): \(out)")
        case .pager(let n): L("✗ paginador en el paso \(n) (falta «terminal length 0»)")
        case .timeout(let n): L("✗ sin respuesta a tiempo en el paso \(n)")
        case .dangerousNotConfirmed(let n, let c): L("✗ paso \(n) peligroso sin confirmar: \(c)")
        case .secretPrompt(let n): L("🔑 piden contraseña en el paso \(n): paro (no escribo nada ahí)")
        case .invalid(let p): L("✗ macro no válida: \(p)")
        }
    }

    // MARK: - botones (como la barra de NetDeck)

    /// Sin botones.txt (instalación nueva) la barra empieza vacía: los de ejemplo, sólo si los pides en Ajustes → Botones.
    func reloadButtons() {
        let samples = ProcessInfo.processInfo.environment["NETDECK_SAMPLES"] != nil        // (capturas)
        buttons = (try? ButtonFile(contentsOf: ButtonFile.defaultURL)) ?? (samples ? ButtonFile.samples : ButtonFile())
        if !buttons.groups.contains(settings.buttonGroup) { settings.buttonGroup = buttons.groups.first ?? "" }
    }

    func saveButtons(_ f: ButtonFile) -> String? {
        do {
            try f.save()
            reloadButtons()
            status = L("Botones guardados (\(f.buttons.count)) en \(AppPaths.tilde(ButtonFile.defaultURL.path))")
            return nil
        } catch {
            ErrorLog.error("botones", "no se han podido guardar: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    /// Arrastrar en la barra de botones: cambia el orden (y la categoría si cae en otra) en memoria; al soltar,
    /// `saveButtonOrder`. Con líneas mal escritas no: al guardar se perderían.
    func moveButton(_ id: CommandButton.ID, onto target: CommandButton.ID) {
        // (con Ajustes abiertos en otra ventana, su editor de botones guardaría encima su copia de antes)
        guard buttons.problems.isEmpty, sharedEditorElsewhere == nil, buttons.moveButton(id, onto: target) else { return }
        buttonsMoved = true
    }

    func saveButtonOrder() {
        guard buttons.problems.isEmpty else {
            status = L("✗ botones.txt tiene líneas mal escritas: arréglalas en Ajustes → Botones para poder ordenar arrastrando")
            return
        }
        guard buttonsMoved else { return }
        buttonsMoved = false
        if let e = saveButtons(buttons) { status = "✗ \(e)"; reloadButtons() }
    }

    /// Clic derecho en un botón de la barra → «Mover a la categoría».
    func moveButton(_ id: CommandButton.ID, toGroup g: String) {
        guard !sharedEditorBusy() else { return }
        if buttons.problems.isEmpty, buttons.moveButton(id, toGroup: g) { buttonsMoved = true }
        saveButtonOrder()
    }

    /// Clic en un botón (o su tecla): en la pestaña activa, o en todas las de MultiExec.
    func runButton(_ b: CommandButton, values: [String: String]? = nil) {
        if values == nil, !b.holes.isEmpty, b.mode == .run || b.mode == .type {
            pendingButton = b
            sheet = .fill
            return
        }
        let cmd = values.map(b.filled) ?? b.command
        // (con MultiExec, no a las que se están autenticando: lo escrito iría como contraseña)
        let targets = multiExecOn ? multiExecTargets.filter(multiExec.accepts) : (current.map { [$0] } ?? []).filter(macroAccepts)
        if b.mode != .session, targets.contains(where: { automationReservation.contains($0.id) }) {
            status = L("⏳ La pestaña ya tiene una secuencia en marcha; pulsa Esc para cortarla"); return
        }
        DebugLog.log("botones", "«\(b.name)» (\(b.mode.rawValue)) en \(targets.map(\.title))")
        // (nunca una orden en una petición de contraseña: iría como contraseña; se dice por qué en vez de «▶»)
        if targets.isEmpty, b.mode == .type || b.mode == .run {
            if let s = current, !multiExecOn, SecretPrompt.asks(s.cursorLine) {
                status = L("✗ Botón «\(b.name)»: «\(s.title)» pide una contraseña; no escribo órdenes ahí (usa un botón de contraseña)")
            } else if let s = current, !multiExecOn, s.route.usesPasswords, !s.loggedIn, !s.exited {
                status = L("✗ Botón «\(b.name)»: «\(s.title)» aún no ha entrado en el equipo")
            } else {
                status = L("✗ Botón «\(b.name)»: ninguna pestaña puede recibirlo ahora")
            }
            return
        }
        switch b.mode {
        case .session:
            quickConnect(cmd)
        case .type:
            targets.forEach { $0.send(cmd) }
        case .run:
            let lines = cmd.components(separatedBy: " ;; ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if lines.count == 1 {
                targets.forEach { $0.sendLine(lines[0]) }
            } else {
                Task { await paste(lines.joined(separator: "\n"), allowDangerous: true, toAll: multiExecOn) }
            }
        case .pass:
            guard let s = current else { return }
            typePassword(.named(cmd), in: s)
        case .login:
            guard let s = current else { return }
            guard let parts = CommandButton.loginParts(cmd), !parts.user.isEmpty, !parts.credential.isEmpty else {
                status = L("✗ Botón «\(b.name)»: el login es «usuario / nombre-de-la-contraseña»")
                return
            }
            Task {
                let sw = s.gate.begin()
                defer { s.gate.end(sw) }
                s.cancelPasswordContext()
                s.passwords.commandUser = parts.user
                s.passwords.commandJumpUsers = []
                let r = await InputScript.login(user: parts.user, credential: .named(parts.credential), cursorLine: s.cursorLine)
                    .run(on: s, store: store, abort: sw)
                status = L("🔑 Login «\(b.name)»: \(r)")
            }
        }
        if b.mode != .session { status = "▶ \(b.name)" + (targets.count > 1 ? " ×\(targets.count)" : "") }
        current?.view.window?.makeFirstResponder(current?.view)
    }

    // MARK: - pantalla dividida y MultiExec

    /// Dónde escribe MultiExec: los paneles de la vista dividida (si se ve) o todas las pestañas; sin las excluidas.
    var multiExecTargets: [TerminalSession] {
        let pool = showSplit && split != nil ? (split?.panes ?? []).compactMap(tab) : tabs
        // (nunca una terminal local, ni sftp ni una consola serie: lo que va a los equipos no se ejecuta en tu Mac)
        return pool.filter { $0.route.acceptsMultiExec && !excluded.contains($0.id) && !$0.exited }
    }

    func tab(_ id: TerminalSession.ID) -> TerminalSession? { tabs.first { $0.id == id } }

    private func syncMultiExec() {
        multiExec.isActive = multiExecOn
        let targets = Set(multiExecTargets.map(\.id))
        for t in tabs {
            if targets.contains(t.id) { multiExec.join(t) } else { multiExec.leave(t) }
        }
    }

    func toggleExcluded(_ s: TerminalSession) {
        if excluded.contains(s.id) { excluded.remove(s.id) } else { excluded.insert(s.id) }
        DebugLog.log("multiexec", "«\(s.title)» \(excluded.contains(s.id) ? "excluida" : "incluida")")
    }

    /// Monta la vista con la pestaña actual y las siguientes (hasta llenarla; los huecos, para elegir).
    func makeSplit(_ layout: Split.Layout) {
        let first = current.map { [$0.id] } ?? []
        let rest = tabs.map(\.id).filter { !first.contains($0) }
        let panes = Array((first + rest).prefix(layout == .grid ? max(2, tabs.count) : layout.capacity))
        split = Split(layout: layout, panes: panes)
        showSplit = true
        DebugLog.log("vista", "\(layout.title): \(panes.compactMap { tab($0)?.title })")
    }

    func unsplit() {
        split = nil
        showSplit = false
        current?.view.window?.makeFirstResponder(current?.view)
    }

    func addToSplit(_ s: TerminalSession, at index: Int? = nil) {
        var sp = split ?? Split(layout: .side2, panes: current.map { [$0.id] } ?? [])
        sp.panes.removeAll { $0 == s.id }
        if let i = index, i <= sp.panes.count { sp.panes.insert(s.id, at: i) } else { sp.panes.append(s.id) }
        if sp.layout != .grid, sp.panes.count > sp.layout.capacity { sp.layout = sp.panes.count <= 4 ? .grid4 : .grid }
        split = sp
        showSplit = true
        selection = s.id
    }

    func removeFromSplit(_ s: TerminalSession) {
        guard var sp = split else { return }
        sp.panes.removeAll { $0 == s.id }
        split = sp.panes.count < 1 ? nil : sp
        if split == nil { showSplit = false }
    }

    /// Un panel vacío de la vista: abre esa sesión ahí.
    func openInSplit(_ route: ConnectionRoute, at index: Int) {
        let s = open(route)
        addToSplit(s, at: index)
    }

    // MARK: - ventana

    func attach(_ w: NSWindow) {
        closeGuard?.install(on: w)                  // (por si macOS rehace los botones de la barra de título)
        // (uno de paso, de una ventana que se está cerrando: nada de vigilantes que nadie quitaría)
        guard window !== w, core.windows.contains(where: { $0 === self }) else { return }
        window = w
        w.isMovableByWindowBackground = false
        w.tabbingMode = .disallowed                 // (las pestañas son las de la app, no las de macOS)
        // pulsar en una zona de reordenar (pestañas en la barra de título, botones): la ventana no se mueve hasta soltar
        if let m = stillWatch { NSEvent.removeMonitor(m) }
        // (sólo cambia si se puede mover la ventana: AppKit entrega SIEMPRE el evento por su recorrido normal.
        // Llamar a NSHostingView.mouseDown a mano pierde gestos y botones con los SDK recientes.)
        stillWatch = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            nonisolated(unsafe) let e = event
            MainActor.assumeIsolated {
                guard let self, let w = self.window else { return }
                // (al soltar, sigue quieta si el puntero está aún sobre las pestañas: el siguiente arrastre de verdad
                // lo decide el WindowServer antes que este monitor)
                if e.type != .leftMouseDown || e.modifierFlags.contains(.control) { w.isMovable = self.stillHover.isEmpty; return }
                guard e.window === w else { return }
                let h = w.contentView?.bounds.height ?? w.frame.height
                let p = CGPoint(x: e.locationInWindow.x, y: h - e.locationInWindow.y)
                w.isMovable = !self.stillZones.values.contains { $0.contains(p) }
            }
            return event
        }
        fullScreen = w.styleMask.contains(.fullScreen)
        followAppearance()
        // clic en un panel de la vista dividida → es la pestaña activa
        focusWatch = w.observe(\.firstResponder, options: [.new]) { [weak self] w, _ in
            MainActor.assumeIsolated {
                guard let self, let v = w.firstResponder as? NetDeckTerminalView,
                      let s = self.tabs.first(where: { $0.view === v }), self.selection != s.id else { return }
                self.selection = s.id
            }
        }
        let nc = NotificationCenter.default
        windowWatches.forEach(nc.removeObserver)
        windowWatches = [
            // (la de delante recibe los menús y los atajos)
            nc.addObserver(forName: NSWindow.didBecomeMainNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { self.core.becameMain(self) } }
            },
            nc.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { self.core.closing(self) } }
            },
            nc.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.fullScreen = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.styleWindows() }
                    DebugLog.log("ventana", "pantalla completa")
                }
            },
            nc.addObserver(forName: NSWindow.willExitFullScreenNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fullScreen = false }
            },
        ]
        closeGuard = WindowCloseGuard(model: self, window: w)
        DebugLog.log("ventana", "marco \(w.frame) · contenido \(w.contentLayoutRect) · pantalla \(w.screen?.visibleFrame ?? .zero)")
        core.attached(self)                         // (y lo que esperaba esta ventana: pestañas, una movida, su sitio)
    }

    /// Se ha cerrado esta ventana (no la última): se cortan sus pestañas y se quitan sus vigilantes.
    func windowClosed() {
        DebugLog.log("ventana", "cerrada con \(tabs.count) pestañas")
        abortAll()
        for s in tabs { close(s) }
        if let m = stillWatch { NSEvent.removeMonitor(m) }
        stillWatch = nil
        windowWatches.forEach(NotificationCenter.default.removeObserver)
        windowWatches = []
        focusWatch = nil
        closeGuard = nil
        window = nil
    }

    /// Cerrar esta ventana (botón rojo o «Cerrar ventana»). Con Ajustes con cambios sin guardar, lo de siempre (se
    /// pregunta); con conexiones abiertas, se pregunta antes de cortarlas. La última cierra la app (y sus pestañas se
    /// guardan para reabrirlas).
    func askToCloseWindow() {
        guard let w = window, !askingClose, sheet == nil else { return }
        askingClose = true
        Task {
            defer { askingClose = false }
            if showSettings, let leave = settingsLeave, !(await leave.check()) { return }
            let live = tabs.filter { !$0.exited }.count
            if live > 0 {
                let last = core.attachedWindows.count <= 1
                guard await ThemedAlert.confirm(
                    last ? L("¿Cerrar la ventana y salir de Terminal NetDeck?") : L("¿Cerrar esta ventana y sus \(live) pestañas?"),
                    message: last ? L("Se cortan sus \(live) conexiones; al volver a abrir la app podrás reabrir sus pestañas.")
                                  : L("Se cortan sus conexiones; las de las otras ventanas siguen abiertas."),
                    ok: L("Cerrar la ventana"), destructive: true, over: w) else { return }
            }
            w.close()
        }
    }
    @ObservationIgnored private var askingClose = false

    /// El puntero entra o sale de una zona de reordenar (`keepsWindowStill`): la ventana deja de ser movible ya antes
    /// del clic. Con un botón pulsado no se toca (un arrastre de la ventana que pasa por encima sigue siendo suyo).
    func pointerInStillZone(_ key: String, _ inside: Bool) {
        if inside { stillHover.insert(key) } else { stillHover.remove(key) }
        guard let w = window, NSEvent.pressedMouseButtons == 0 else { return }
        w.isMovable = stillHover.isEmpty
    }

    /// Doble clic en la barra de arriba: como en la barra de título (llenar la pantalla / volver, o minimizar).
    func toggleFill() {
        guard let w = window, !fullScreen else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": w.miniaturize(nil)
        case "None": break
        default:
            guard let vf = w.screen?.visibleFrame else { return }
            if w.frame.insetBy(dx: -2, dy: -2).contains(vf), let prev = frameBeforeFill {
                w.setFrame(prev, display: true, animate: true)
                frameBeforeFill = nil
            } else {
                frameBeforeFill = w.frame
                w.setFrame(vf, display: true, animate: true)
            }
        }
    }

    // MARK: - reabrir las de la última vez (y tras actualizar)

    /// Se guarda al abrir, cerrar y mover pestañas: las de todas las ventanas, cada una con la suya (`AppCore`).
    func saveOpenTabs() { core.saveOpenTabs() }

    /// Las de la última vez: las de la primera ventana, aquí; las de las demás, en ventanas nuevas donde estaban.
    func reopenLast() { core.reopenLast(into: self) }

    // MARK: - actualizar (de momento, desde el código: ./actualizar.sh)

    /// La carpeta del código, si está en este Mac: la que apunta install.sh al instalar desde ella (`NetDeckSource`,
    /// no en el .dmg) o, con «swift run», la carpeta actual.
    static var sourceFolder: URL? {
        let candidates = [(Bundle.main.object(forInfoDictionaryKey: "NetDeckSource") as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) },
                          Bundle.main.bundleURL.pathExtension == "app" ? nil : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("actualizar.sh").path) }
    }

    /// La última release en GitHub: si hay una más nueva, ofrece abrir su descarga (no instala nada sola).
    func checkForUpdates() {
        guard let repo = UpdateCheck.repo else {
            status = L("✗ Sin repositorio de actualizaciones (NETDECK_REPO al instalar)")
            return
        }
        status = L("⬆ Buscando actualizaciones…")
        Task {
            do {
                if let r = try await UpdateCheck.check(repo: repo) {
                    availableUpdate = r
                    status = L("⬆ Hay una versión nueva: \(r.version)")
                    offerUpdate(r)
                } else {
                    status = L("⬆ Estás al día (\(UpdateCheck.currentVersion))")
                }
            } catch {
                ErrorLog.warning("actualizaciones", "no se ha podido comprobar: \(error.localizedDescription)")
                status = L("✗ No se ha podido comprobar: \(error.localizedDescription)")
            }
        }
    }

    /// «Hay una versión nueva»: actualizar ahora (baja, comprueba y sustituye la app; se vuelve a abrir con tus
    /// pestañas), abrir su página o más tarde. Nada se instala sin este clic.
    func offerUpdate(_ r: UpdateCheck.Release) {
        let auto = r.dmg != nil && r.sha256 != nil && Updater.canSelfInstall
        let message = L("Tienes la \(UpdateCheck.currentVersion). ")
            + (auto ? L("Se descarga de GitHub, se comprueba y se vuelve a abrir con tus pestañas. ")
                    : L("Descarga el .dmg y sustituye la app. "))
            + L("Tus sesiones, ajustes y el Llavero se conservan.")
        let first = auto ? L("Actualizar ahora") : r.dmg == nil ? L("Abrir la página") : L("Descargar")
        let buttons = auto ? [first, L("Ver qué cambia"), L("Más tarde")] : [first, L("Más tarde")]
        guard !offeringUpdate else { return }               // (dos «Buscar ahora» seguidos: un solo aviso)
        offeringUpdate = true
        Task {
            defer { offeringUpdate = false }
            switch await ThemedAlert.run(L("Terminal NetDeck \(r.version) disponible"), message: message, buttons: buttons).button {
            case 0:
                if auto { Updater.install(r, model: self) } else { NSWorkspace.shared.open(r.dmg ?? r.page) }
            case 1 where auto: NSWorkspace.shared.open(r.page)
            default: break
            }
        }
    }
    /// (un solo aviso de versión nueva aunque haya varias ventanas)
    private var offeringUpdate: Bool {
        get { core.offeringUpdate }
        set { core.offeringUpdate = newValue }
    }
    @ObservationIgnored private var askingDelete = false

    /// Compila, sustituye la app instalada y la vuelve a abrir con las mismas pestañas.
    func updateFromSource() {
        guard let dir = Self.sourceFolder else {
            status = L("✗ No encuentro el código (actualizar.sh) en este Mac")
            return
        }
        saveOpenTabs()
        let log = DebugLog.directory.appendingPathComponent("actualizar.log")
        AppPaths.ensure(DebugLog.directory)
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [dir.appendingPathComponent("actualizar.sh").path]
        p.currentDirectoryURL = dir
        if let h = try? FileHandle(forWritingTo: log) {
            p.standardOutput = h
            p.standardError = h
        }
        do {
            try p.run()
            status = L("⬆ Actualizando: compilando… (se cerrará y se abrirá sola con tus pestañas)")
            DebugLog.log("app", "actualizar: \(dir.path)/actualizar.sh (pid \(p.processIdentifier))")
        } catch {
            ErrorLog.error("actualizar", "no arranca actualizar.sh: \(error.localizedDescription)")
            status = L("✗ No se ha podido actualizar: \(error.localizedDescription)")
        }
    }
}

/// Pantalla dividida: las formas de NetDeck (⊞ Split) y qué pestaña va en cada panel.
struct Split: Equatable {
    enum Layout: String, CaseIterable, Identifiable {
        case side2, stack2, cols3, onePlusTwo, grid4, grid
        var id: String { rawValue }
        var title: String {
            switch self {
            case .side2: L("2 lado a lado")
            case .stack2: L("2 arriba y abajo")
            case .cols3: L("3 columnas")
            case .onePlusTwo: "1 + 2"
            case .grid4: "4 (2 × 2)"
            case .grid: L("Todas (cuadrícula)")
            }
        }
        var icon: String {
            switch self {
            case .side2: "rectangle.split.2x1"
            case .stack2: "rectangle.split.1x2"
            case .cols3: "rectangle.split.3x1"
            case .onePlusTwo: "rectangle.leadinghalf.inset.filled"
            case .grid4: "rectangle.split.2x2"
            case .grid: "square.grid.3x3"
            }
        }
        var capacity: Int {
            switch self {
            case .side2, .stack2: 2
            case .cols3, .onePlusTwo: 3
            case .grid4: 4
            case .grid: 16
            }
        }
    }

    var layout: Layout
    var panes: [TerminalSession.ID]
    var fractions: [String: [Double]] = [:]
}
