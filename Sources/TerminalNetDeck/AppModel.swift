import AppKit
import NetDeckCore
import Observation

/// Estado de la app: ajustes, temas, sesiones, pestañas, Llavero, MultiExec y lo automático en curso.
@MainActor @Observable
final class AppModel {
    enum Sheet: String, Identifiable {
        case connect, paste, list, sessions, fill, logs
        var id: String { rawValue }
    }

    /// Qué abre el gestor de Sesiones: una sesión, una nueva (en un grupo) o importar.
    enum EditorFocus: Equatable {
        case session(String)
        case new(group: String?, kind: SessionProfile.Transport = .ssh)
        case duplicate(String)
        case importing
    }

    let settings = AppSettings()
    let themes: ThemeStore
    let sessions = SessionManager()
    let store: CredentialStore = KeychainStore()
    let ledger = CredentialLedger.shared()
    let policy = CredentialPolicy()
    @ObservationIgnored let multiExec = MultiExecGroup()
    /// Lo que afecta a varias pestañas (pegado a todas, listas): Esc en cualquiera lo corta.
    @ObservationIgnored let sharedGate = AutomationGate()

    var tabs: [TerminalSession] = []
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
    /// Ventana: pantalla completa. Ahí macOS esconde su barra de título (y la de menús) y la baja al acercar el ratón:
    /// sólo mientras está bajada tapa la de arriba y se deja su hueco (`titlebarReveal`); escondida, nada.
    var fullScreen = false
    var titlebarReveal: CGFloat = 0
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var focusWatch: NSKeyValueObservation?
    @ObservationIgnored private var appearanceWatch: NSKeyValueObservation?
    @ObservationIgnored private var frameBeforeFill: NSRect?
    /// Pestañas abiertas la última vez (para reabrirlas).
    var lastOpen: [ConnectionRoute] = []
    var editorFocus: EditorFocus?
    /// Ajustes dentro de la ventana (en pantalla completa no se van a otro escritorio) y con el tema.
    var showSettings = false
    var settingsTab = "contraseñas"
    /// ★ favoritas y ↻ recientes: los mismos archivos que NetDeck (~/.config/netdeck/favoritas, recientes).
    var favorites: [String] = []
    var recents: [String] = []
    /// Botones de la barra (botones.txt de NetDeck, o el de la app).
    var buttons = ButtonFile()
    /// Botón con huecos esperando a que los rellenes.
    var pendingButton: CommandButton?
    /// Sugerencia o elección manual pendiente en cada pestaña.
    var notices: [TerminalSession.ID: PasswordAutomation.Event] = [:]
    /// Para refrescar lo que depende del Llavero.
    var keychainRevision = 0
    /// El asistente de instalación ocupa la ventana: al abrirla desde fuera de Aplicaciones (DMG…), la primera vez que
    /// se abre (también si se arrastró a Aplicaciones desde el DMG) o desde el menú.
    var showSetup = SetupWizard.needsInstall || SetupWizard.firstLaunch
        || ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT_ACTION"]?.hasPrefix("setup:") == true
    /// Las reglas de resaltado leídas (todas, también las apagadas) y de dónde.
    private(set) var highlightConfig = HighlightConfig()
    private(set) var highlightFile: URL?

    /// (para el delegado de la app: guardar las pestañas al salir)
    nonisolated(unsafe) static weak var instance: AppModel?
    /// Versión nueva encontrada en segundo plano (aviso discreto en la barra de estado).
    var availableUpdate: UpdateCheck.Release?
    @ObservationIgnored private lazy var updates = UpdateChecker(model: self)

    init() {
        themes = ThemeStore(selected: settings.themeID)
        DebugLog.enabled = settings.debugLog
        DebugLog.log("app", "arranca \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")"
                     + " (\(Bundle.main.bundlePath)) · ssh_config \(settings.sshConfigURL.path)")
        reloadSessions()
        reloadHighlight()
        lastOpen = Self.readOpenTabs()
        Self.instance = self
        loadFavorites()
        reloadButtons()
        if CommandLine.arguments.contains("--reabrir") { DispatchQueue.main.async { self.reopenLast() } }
        if ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] == nil {
            DispatchQueue.main.async { self.openStartupTabs() }                   // (después de reabrir, si toca)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.updates.start() }   // (sin estorbar al arrancar)
        }
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

    /// Reglas activas y colores (los del tema, o la paleta del archivo) a todas las pestañas.
    func applyHighlight() {
        tabs.forEach(applyHighlight)
    }

    private func applyHighlight(to s: TerminalSession) {
        let rules = highlightConfig.rules.filter { !settings.highlightDisabled.contains($0.description) }
        let palette = settings.highlightThemeColors
            ? themes.current.highlightPalette
            : themes.current.highlightPalette.merging(highlightConfig.palette) { $1 }
        s.highlight(rules: rules, palette: palette, enabled: settings.highlightEnabled)
    }

    static var customHighlightURL: URL { AppPaths.support.appendingPathComponent("resaltado.yml") }

    /// Lo que se cambia en Ajustes → Resaltado (añadir, editar, ordenar, borrar): al archivo personalizado (con
    /// copia `.anterior`) y a partir de ahí se usan esas. `renamed`: descripción vieja → nueva (para que una regla
    /// apagada siga apagada). nil = bien; si no, el error.
    func saveHighlightRules(_ rules: [HighlightRule], renamed: [String: String] = [:]) -> String? {
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
    }

    // MARK: - ajustes en vivo

    func selectTheme(_ id: String) {
        settings.themeID = id
        themes.select(id)
        applyAppearance()
    }

    /// Tema automático: el claro o el oscuro según el Mac (se llama al cambiar la apariencia).
    func followAppearance() {
        guard settings.themeAuto else { return }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let id = dark ? settings.themeDark : settings.themeLight
        if themes.current.id != id, themes.theme(id: id) != nil { selectTheme(id) }
    }

    /// Tema, fuente y colores del resaltado a todas las pestañas abiertas.
    func applyAppearance() {
        tabs.forEach { $0.apply(theme: themes.current, font: terminalFont) }
        styleWindows()
        applyHighlight()
    }

    /// La ventana (y menús, avisos, hojas) con el tema: claro/oscuro, su color y, en los de cristal, transparente.
    func styleWindows() {
        let th = themes.current
        NSApp.appearance = NSAppearance(named: th.isLight ? .aqua : .darkAqua)
        for w in NSApp.windows {
            if w === window || w.className.contains("FullScreen") || w.className.contains("Titlebar") {
                w.isOpaque = !th.isTranslucent
                w.backgroundColor = w === window ? (th.isTranslucent ? .clear : NSColor(th.background)) : NSColor(th.bar.opaque)
            }
        }
        window?.titlebarAppearsTransparent = true
    }

    func applyPasswordModes() {
        for t in tabs where t.route.usesPasswords {
            t.passwords.mode = settings.devicePasswordMode
            t.passwords.sessionMode = settings.sessionAutoPassword ? .autoType : nil
        }
    }

    var terminalFont: NSFont {
        let t = themes.current
        let family = settings.fontFamily.isEmpty ? Fonts.firstInstalled(t.fonts) : settings.fontFamily
        return Fonts.terminal(family: family, size: settings.fontSize > 0 ? settings.fontSize : CGFloat(t.size - 1))
    }

    // MARK: - pestañas

    func open(_ profile: SessionProfile) {
        do {
            let r = try sessions.route(to: profile)
            if r.transport == .ftp { openFTP(r) } else { open(r) }
            noteRecent(profile.name)
        } catch {
            status = "✗ \(error.localizedDescription)"
        }
    }

    // MARK: - gestor de sesiones (el ssh_config de NetDeck)

    func openSettings(_ tab: String? = nil) {
        if let tab { settingsTab = tab }
        showSettings = true
    }

    func editSessions(_ focus: EditorFocus? = nil) {
        editorFocus = focus
        sheet = .sessions
    }

    /// Guarda el ssh_config de NetDeck (comprobado con ssh -G) y que ~/.ssh/config lo incluya.
    func saveSessions(_ file: SessionFile) -> String? {
        if let err = file.save() {
            ErrorLog.error("sesiones", "no se han podido guardar: \(err)")
            return err
        }
        if settings.sshConfigURL.standardizedFileURL == SessionManager.defaultConfigURL.standardizedFileURL {
            SessionFile.ensureInclude()
        }
        reloadSessions()
        status = L("Sesiones guardadas (\(file.sessions.count))")
        return nil
    }

    var sessionFile: SessionFile { (try? SessionFile(contentsOf: SessionFile.defaultURL)) ?? SessionFile() }

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
        AppPaths.ensure(AppPaths.netdeck)
        let line = "\(Int(Date().timeIntervalSince1970))\t\(name)\n"
        if let h = try? FileHandle(forWritingTo: Self.recentsFile) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: Self.recentsFile, atomically: true, encoding: .utf8)
        }
        recents.removeAll { $0 == name }
        recents.insert(name, at: 0)
        if recents.count > 10 { recents.removeLast() }
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
        if let p = startupProfile, !tabs.contains(where: { $0.route.sessionName == p.name }) {
            DebugLog.log("app", "sesión de inicio «\(p.name)»")
            open(p)
        }
        if settings.startupLocalTerminal, tabs.isEmpty { openLocal() }
    }

    /// FTP: macOS no trae cliente; el Finder lo monta (sólo lectura) y pide él la contraseña.
    func openFTP(_ r: ConnectionRoute) {
        guard let url = r.ftpURL else { status = "✗ " + L("Equipo no válido: «\(r.target.host)»"); return }
        DebugLog.log("ftp", "«\(r.title)» → Finder")
        NSWorkspace.shared.open(url)
        status = L("FTP «\(r.title)»: se abre en el Finder (sólo lectura)")
    }

    /// Borrar una sesión desde la lista (pregunta antes; queda copia en ssh_config.anterior).
    func deleteSession(_ name: String) {
        var f = sessionFile
        guard let i = f.sessions.firstIndex(where: { $0.name == name }) else { return }
        let a = NSAlert()
        a.messageText = L("¿Borrar la sesión «\(name)»?")
        a.informativeText = L("Queda una copia en ssh_config.anterior. Su contraseña del Llavero no se toca.")
        a.addButton(withTitle: L("Borrar"))
        a.addButton(withTitle: L("Cancelar"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        f.sessions.remove(at: i)
        if let err = saveSessions(f) { status = "✗ \(err)"; return }
        if favorites.contains(name) { toggleFavorite(name) }
    }

    /// Terminal local: tu shell de inicio, como shell de login, en tu carpeta.
    func openLocal() { open(ConnectionRoute.local()) }

    @discardableResult
    func open(_ route: ConnectionRoute) -> TerminalSession {
        // (la local y la consola serie no son un equipo por red: ni askpass ni contraseñas automáticas)
        let pw = PasswordAutomation(mode: route.usesPasswords ? settings.devicePasswordMode : .off, store: store, policy: policy, ledger: ledger)
        pw.sessionMode = settings.sessionAutoPassword && route.usesPasswords ? .autoType : nil
        let s = TerminalSession(route: route, passwords: pw, ledger: ledger)
        pw.candidates = { [weak self] req in
            self?.sessions.credentialCandidates(for: req, route: route, defaultCredential: self?.settings.defaultCredential) ?? []
        }
        s.onEvent = { [weak self] s, e in self?.handle(e, in: s) }
        s.onInput = { [weak self] s, bytes in self?.userInput(bytes, in: s) ?? false }
        s.onReconnect = { [weak self] s in self?.reconnect(s) }
        s.onCloseRequest = { [weak self] s in self?.close(s) }
        s.onForwardingRefused = { [weak self] s in
            do { return try self?.sessions.typedHop(for: s.route) } catch {
                DebugLog.log("salto", "«\(s.title)»: \(error.localizedDescription)")
                return nil
            }
        }
        s.apply(theme: themes.current, font: terminalFont)
        applyHighlight(to: s)
        tabs.append(s)
        selection = s.id
        syncMultiExec()
        saveOpenTabs()
        let askpass = settings.sessionAutoPassword && route.usesPasswords
            ? Askpass.environment(executable: Bundle.main.executablePath ?? CommandLine.arguments[0],
                                  configPath: settings.sshConfigURL.path,
                                  defaultCredential: settings.defaultCredential, session: s.id)
            : [:]
        if settings.logEnabled { s.startLog(in: settings.logURL) }
        s.start(extraEnvironment: askpass)
        status = route.usesPasswords ? L("Conectando a \(route.title)…") : ""
        return s
    }

    func close(_ s: TerminalSession) {
        DebugLog.log("pestaña", "«\(s.title)» cerrada")
        s.gate.abortAll()
        s.terminate()
        _ = Askpass.takeGiven(session: s.id)             // (lo que dejó el askpass si se cierra antes de entrar)
        multiExec.leave(s)
        notices[s.id] = nil
        excluded.remove(s.id)
        let i = tabs.firstIndex { $0 === s } ?? 0
        tabs.removeAll { $0 === s }
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
        saveOpenTabs()
    }

    func toggleLog(_ s: TerminalSession) {
        if s.logFile != nil { s.stopLog() } else { s.startLog(in: settings.logURL) }
    }

    func reconnect(_ s: TerminalSession) {
        DebugLog.log("pestaña", "«\(s.title)» reconectar")
        notices[s.id] = nil
        s.restart()
    }

    /// Otra pestaña con la misma sesión (clonar).
    func duplicate(_ s: TerminalSession) { open(s.route) }

    func closeCurrent() { current.map(close) }

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
        switch s.passwords.typeManually(ref, into: s) {
        case .typed: notices[s.id] = nil
        case .blocked: status = L("🔑 «\(ref)» falló hace poco: no la escribo (cuenta AD) · desbloquéala en Ajustes")
        case .notAsked: status = L("🔑 Ahí no piden contraseña ahora")
        case .missing: status = L("🔑 «\(ref)» no está en el Llavero")
        }
    }

    /// Pestañas en las que ya se ha confirmado «escribir sin esperar a que la pida» (se pregunta una vez por pestaña).
    @ObservationIgnored private var anywayConfirmed: Set<TerminalSession.ID> = []

    /// La manda al terminal aunque ahí no se reconozca «Password:» (prompts raros). Se confirma la primera vez en cada
    /// pestaña y siempre si está bloqueada por un fallo reciente. Nunca se registra.
    func typePasswordAnyway(_ ref: CredentialRef, in s: TerminalSession, pressReturn: Bool) {
        if !anywayConfirmed.contains(s.id) {
            let a = NSAlert()
            a.messageText = L("¿Escribir «\(ref.account)» en «\(s.title)»?")
            a.informativeText = L("Va como texto al terminal aunque no pidan contraseña: si no es un prompt de contraseña, se verá en pantalla (y puede quedar en el historial del equipo).")
            a.addButton(withTitle: L("Escribir"))
            a.addButton(withTitle: L("Cancelar"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
            anywayConfirmed.insert(s.id)
        }
        var force = false
        if ledger.isBlocked(ref) {
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = L("«\(ref.account)» ha fallado hace poco")
            a.informativeText = L("Si es una cuenta AD, otro intento fallido puede bloquearla. ¿Escribirla igualmente?")
            a.addButton(withTitle: L("Escribir igualmente"))
            a.addButton(withTitle: L("Cancelar"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
            force = true
        }
        switch s.passwords.typeAnyway(ref, into: s, pressReturn: pressReturn, force: force) {
        case .typed: notices[s.id] = nil; status = L("🔑 «\(ref)» escrita en \(s.title)")
        case .blocked: status = L("🔑 «\(ref)» falló hace poco: no la escribo (cuenta AD) · desbloquéala en Ajustes")
        case .notAsked: break
        case .missing: status = L("🔑 «\(ref)» no está en el Llavero")
        }
    }

    /// Todas las del Llavero de NetDeck (para elegir a mano).
    var keychainAccounts: [CredentialRef] {
        let rev = keychainRevision
        if let c = keychainCache, c.rev == rev { return c.list }      // (se pide en varias vistas: una consulta por cambio)
        func accounts(_ service: CredentialRef.Service) -> [String] {
            do { return try store.accounts(in: service) } catch {
                ErrorLog.error("llavero", "no se pueden listar las contraseñas: \(error.localizedDescription)")
                return []
            }
        }
        let named = accounts(.named)
        let device = accounts(.device)
        let list = named.map(CredentialRef.named) + device.map { .init(service: .device, account: $0) }
        keychainCache = (rev, list)
        return list
    }
    @ObservationIgnored private var keychainCache: (rev: Int, list: [CredentialRef])?

    // MARK: - pegado seguro y listas

    func paste(_ text: String, allowDangerous: Bool, toAll: Bool) async {
        let paster = SafePaster(allowDangerous: allowDangerous)
        if toAll {
            let sw = sharedGate.begin()
            pasteTargets = Set(multiExec.terminals.compactMap { ($0 as? TerminalSession)?.id })
            defer { sharedGate.end(sw); pasteTargets = [] }
            let reports = await multiExec.paste(text, paster: paster, abort: sw)
            let failed = reports.contains { if case .completed = $0.outcome { false } else { true } }
            status = (failed ? "✗ " : "") + L("Pegado en \(reports.count): ") + reports.map { describe($0) }.joined(separator: " · ")
        } else if let s = current {
            let sw = s.gate.begin()
            pasteTargets = [s.id]
            defer { s.gate.end(sw); pasteTargets = [] }
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
    @ObservationIgnored private var pasteTargets: Set<TerminalSession.ID> = []

    func abortAll() {
        sharedGate.abortAll()
        tabs.forEach { $0.gate.abortAll() }
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
        if AbortKey.isAbort(bytes), s.gate.isBusy || sharedGate.isBusy {
            s.gate.abortAll()
            sharedGate.abortAll()
            status = L("⎋ Cancelado: no se envía nada más")
            if !bytes.contains(AbortKey.ctrlC) { return true }        // (Ctrl+C sí llega al equipo)
        }
        // Mientras se pega, lo tecleado no se mezcla con las líneas que se envían (sólo en el pegado: esperando un
        // salto puede tocar escribir una contraseña a mano).
        if pasteTargets.contains(s.id) {
            status = L("⏳ Enviando… Esc para cortar (lo que tecleas no se envía)")
            return true
        }
        if let k = FunctionKey.name(bytes), let b = buttons.button(forKey: k) {      // F5, Mayús+F6…
            DebugLog.log("botones", "\(k) → «\(b.name)»")
            runButton(b)
            return true
        }
        if bytes.contains(13) { s.noteCommand() }                     // Intro
        guard multiExecOn else { return false }
        let sent = multiExec.broadcast(bytes, from: s)
        if sent, bytes.contains(13) {
            DebugLog.log("multiexec", "Intro desde «\(s.title)» → \(multiExecTargets.map(\.title).joined(separator: ", "))")
        }
        return sent
    }

    // MARK: - botones (como la barra de NetDeck)

    func reloadButtons() {
        buttons = (try? ButtonFile(contentsOf: ButtonFile.defaultURL)) ?? ButtonFile.samples
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

    /// Clic en un botón (o su tecla): en la pestaña activa, o en todas las de MultiExec.
    func runButton(_ b: CommandButton, values: [String: String]? = nil) {
        if values == nil, !b.holes.isEmpty, b.mode == .run || b.mode == .type {
            pendingButton = b
            sheet = .fill
            return
        }
        let cmd = values.map(b.filled) ?? b.command
        let targets = multiExecOn ? multiExecTargets : (current.map { [$0] } ?? []).filter { !$0.exited }
        DebugLog.log("botones", "«\(b.name)» (\(b.mode.rawValue)) en \(targets.map(\.title))")
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
            let parts = cmd.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                status = L("✗ Botón «\(b.name)»: el login es «usuario / nombre-de-la-contraseña»")
                return
            }
            Task {
                let sw = s.gate.begin()
                defer { s.gate.end(sw) }
                s.passwords.commandUser = parts[0]
                s.passwords.commandJumpUsers = []
                let r = await InputScript.login(user: parts[0], credential: .named(parts[1])).run(on: s, store: store, abort: sw)
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
        guard window !== w else { return }
        window = w
        w.isMovableByWindowBackground = false
        styleWindows()
        fullScreen = w.styleMask.contains(.fullScreen)
        // clic en un panel de la vista dividida → es la pestaña activa
        appearanceWatch = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.followAppearance() }
        }
        followAppearance()
        focusWatch = w.observe(\.firstResponder, options: [.new]) { [weak self] w, _ in
            MainActor.assumeIsolated {
                guard let self, let v = w.firstResponder as? NetDeckTerminalView,
                      let s = self.tabs.first(where: { $0.view === v }), self.selection != s.id else { return }
                self.selection = s.id
            }
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.fullScreen = true
                self.titlebarReveal = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.styleWindows() }
                DebugLog.log("ventana", "pantalla completa")
            }
        }
        nc.addObserver(forName: NSWindow.willExitFullScreenNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fullScreen = false; self?.titlebarReveal = 0 }
        }
        // (la barra de título en pantalla completa es otra ventana que baja y sube: lo que tapa de la nuestra)
        nc.addObserver(forName: NSWindow.didMoveNotification, object: nil, queue: .main) { [weak self] n in
            nonisolated(unsafe) let moved = n.object as? NSWindow     // (cola principal)
            MainActor.assumeIsolated {
                guard let self, self.fullScreen, let bar = moved, bar !== w,
                      bar.className.contains("FullScreen") || bar.className.contains("Titlebar") else { return }
                let covered = max(0, w.frame.maxY - bar.frame.minY)
                let reveal = covered < 4 || covered > 160 ? 0 : covered
                guard abs(reveal - self.titlebarReveal) >= 1 else { return }
                self.titlebarReveal = reveal
                DebugLog.log("ventana", "barra de título de pantalla completa (\(bar.className)): tapa \(Int(covered)) → hueco \(Int(reveal))")
            }
        }
        DebugLog.log("ventana", "marco \(w.frame) · contenido \(w.contentLayoutRect) · pantalla \(w.screen?.visibleFrame ?? .zero)")
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

    private static var openTabsFile: URL { AppPaths.support.appendingPathComponent("abiertas.json") }

    /// Se guarda al abrir y cerrar pestañas (así una actualización o un cierre brusco no las pierde).
    func saveOpenTabs() {
        // (las capturas de desarrollo no tocan tus pestañas; y nunca las de este mismo Mac)
        guard ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] == nil else { return }
        let routes = tabs.map(\.route).filter { !$0.isLoopback }
        guard !routes.isEmpty else {
            if lastOpen.isEmpty { try? FileManager.default.removeItem(at: Self.openTabsFile) }
            return
        }
        AppPaths.ensure(AppPaths.support)
        do {
            try JSONEncoder().encode(routes).write(to: Self.openTabsFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.openTabsFile.path)
        } catch {
            ErrorLog.error("pestañas", "no se han podido guardar las pestañas abiertas: \(error.localizedDescription)")
        }
    }

    private static func readOpenTabs() -> [ConnectionRoute] {
        let all = (try? Data(contentsOf: openTabsFile)).flatMap { try? JSONDecoder().decode([ConnectionRoute].self, from: $0) } ?? []
        let kept = all.filter { !$0.isLoopback }
        if kept.count != all.count { DebugLog.log("app", "no reabro \(all.count - kept.count) a este mismo Mac (127.x/localhost)") }
        return kept
    }

    func reopenLast() {
        let routes = lastOpen
        lastOpen = []
        DebugLog.log("app", "reabro \(routes.count): \(routes.map(\.title))")
        for r in routes { open(r) }
    }

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

    /// «Hay una versión nueva»: descargarla (o abrir su página) o más tarde. No instala nada sola.
    func offerUpdate(_ r: UpdateCheck.Release) {
        let alert = NSAlert()
        alert.messageText = L("Terminal NetDeck \(r.version) disponible")
        alert.informativeText = L("Tienes la \(UpdateCheck.currentVersion). Descarga el .dmg y sustituye la app: ")
            + L("tus sesiones, ajustes y el Llavero se conservan.")
        alert.addButton(withTitle: r.dmg == nil ? L("Abrir la página") : L("Descargar"))
        alert.addButton(withTitle: L("Más tarde"))
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(r.dmg ?? r.page) }
    }

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
}
