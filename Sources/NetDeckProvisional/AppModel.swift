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
        case new(group: String?)
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
    var status = "" {
        didSet { if !status.isEmpty { DebugLog.log("estado", status) } }
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
    /// Ventana: pantalla completa (la barra de título de macOS tapa la de arriba: se deja su hueco).
    var fullScreen = false
    var titlebarHeight: CGFloat = 28
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
    /// El asistente de instalación ocupa la ventana: al abrirla desde fuera de Aplicaciones (DMG…) o desde el menú.
    var showSetup = SetupWizard.needsInstall
        || ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT_ACTION"]?.hasPrefix("setup:") == true
    /// Las reglas de resaltado leídas (todas, también las apagadas) y de dónde.
    private(set) var highlightConfig = HighlightConfig()
    private(set) var highlightFile: URL?

    /// (para el delegado de la app: guardar las pestañas al salir)
    nonisolated(unsafe) static weak var instance: AppModel?

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
        highlightConfig = (try? highlightFile.map(HighlightConfig.init(contentsOf:))) ?? HighlightConfig()
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

    /// Copia editable de las reglas (para cambiarlas sin tocar las de NetDeck).
    func customizeHighlight() -> URL? {
        let dest = AppPaths.ensure(AppPaths.support).appendingPathComponent("resaltado.yml")
        if !FileManager.default.fileExists(atPath: dest.path), let src = highlightFile {
            try? FileManager.default.copyItem(at: src, to: dest)
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
        if sessions.profiles.isEmpty { sessions.loadSamples() }
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
        for t in tabs {
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
            open(try sessions.route(to: profile))
            noteRecent(profile.name)
        } catch {
            status = error.localizedDescription
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
        if let err = file.save() { return err }
        if settings.sshConfigURL.standardizedFileURL == SessionManager.defaultConfigURL.standardizedFileURL {
            SessionFile.ensureInclude()
        }
        reloadSessions()
        status = "Sesiones guardadas (\(file.sessions.count))"
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
        try? (favorites.joined(separator: "\n") + (favorites.isEmpty ? "" : "\n"))
            .write(to: Self.favoritesFile, atomically: true, encoding: .utf8)
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

    @discardableResult
    func open(_ route: ConnectionRoute) -> TerminalSession {
        let pw = PasswordAutomation(mode: settings.devicePasswordMode, store: store, policy: policy, ledger: ledger)
        pw.sessionMode = settings.sessionAutoPassword ? .autoType : nil
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
        let askpass = settings.sessionAutoPassword
            ? Askpass.environment(executable: Bundle.main.executablePath ?? CommandLine.arguments[0],
                                  configPath: settings.sshConfigURL.path,
                                  defaultCredential: settings.defaultCredential, session: s.id)
            : [:]
        if settings.logEnabled { s.startLog(in: settings.logURL) }
        s.start(extraEnvironment: askpass)
        status = "Conectando a \(route.title)…"
        return s
    }

    func close(_ s: TerminalSession) {
        DebugLog.log("pestaña", "«\(s.title)» cerrada")
        s.gate.abortAll()
        s.terminate()
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
            status = error.localizedDescription
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
            status = "«\(t)» no es una sesión ni usuario@equipo"
        }
    }

    // MARK: - contraseñas

    private func handle(_ e: PasswordAutomation.Event, in s: TerminalSession) {
        switch e {
        case .typed(let r): status = "🔑 «\(r)» escrita en \(s.title)"; notices[s.id] = nil
        case .confirmed: notices[s.id] = nil
        case .cancelled: status = "⎋ Contraseña cancelada"; notices[s.id] = nil
        case .failed(let r): status = "🔑 «\(r)» no ha valido: bloqueada 15 min en todas las pestañas"; notices[s.id] = e
        case .suggested, .manual: notices[s.id] = e
        }
    }

    func typePassword(_ ref: CredentialRef, in s: TerminalSession) {
        switch s.passwords.typeManually(ref, into: s) {
        case .typed: notices[s.id] = nil
        case .blocked: status = "🔑 «\(ref)» falló hace poco: no la escribo (cuenta AD) · desbloquéala en Ajustes"
        case .notAsked: status = "🔑 Ahí no piden contraseña ahora"
        case .missing: status = "🔑 «\(ref)» no está en el Llavero"
        }
    }

    /// Todas las del Llavero de NetDeck (para elegir a mano).
    var keychainAccounts: [CredentialRef] {
        _ = keychainRevision
        let named = (try? store.accounts(in: .named)) ?? []
        let device = (try? store.accounts(in: .device)) ?? []
        return named.map(CredentialRef.named) + device.map { .init(service: .device, account: $0) }
    }

    // MARK: - pegado seguro y listas

    func paste(_ text: String, allowDangerous: Bool, toAll: Bool) async {
        let paster = SafePaster(allowDangerous: allowDangerous)
        if toAll {
            let sw = sharedGate.begin()
            defer { sharedGate.end(sw) }
            let reports = await multiExec.paste(text, paster: paster, abort: sw)
            status = "Pegado en \(reports.count): " + reports.map { describe($0) }.joined(separator: " · ")
        } else if let s = current {
            let sw = s.gate.begin()
            defer { s.gate.end(sw) }
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
            self?.status = "\(list.name) · \(d.host): \(st)"
        }
        await runner.run()
        let ok = runner.status.values.filter { $0 == .connected }.count
        status = "\(list.name): \(ok)/\(list.devices.count) dentro"
        // juntas en una vista; las que se han quedado en el salto, fuera de MultiExec (nada se ejecuta en el salto)
        let opened = list.devices.compactMap { byDevice[$0] }
        if opened.count > 1 {
            excluded.formUnion(list.devices.filter { runner.status[$0] != .connected }.compactMap { byDevice[$0]?.id })
            split = Split(layout: .grid, panes: opened.map(\.id))
            showSplit = true
        }
    }

    func abortAll() {
        sharedGate.abortAll()
        tabs.forEach { $0.gate.abortAll() }
    }

    private func describe(_ r: PasteReport) -> String {
        switch r.outcome {
        case .completed: "✓ \(r.sent)/\(r.total) líneas"
        case .aborted: "⎋ parado en \(r.sent)/\(r.total)"
        case .deviceError(let l, let out): "✗ error en la línea \(l): \(out)"
        case .pager(let l): "✗ paginador en la línea \(l) (falta «terminal length 0»)"
        case .timeout(let l): "✗ sin prompt tras la línea \(l)"
        case .dangerousNotConfirmed(let l, let c): "✗ línea \(l) peligrosa sin confirmar: \(c)"
        }
    }

    // MARK: - teclado: Esc/Ctrl+C cortan lo automático; MultiExec reparte lo que escribes

    /// Lo que teclea (o pega) el usuario en una pestaña. true = ya atendido.
    private func userInput(_ bytes: [UInt8], in s: TerminalSession) -> Bool {
        if AbortKey.isAbort(bytes), s.gate.isBusy || sharedGate.isBusy {
            s.gate.abortAll()
            sharedGate.abortAll()
            status = "⎋ Cancelado: no se envía nada más"
            if !bytes.contains(AbortKey.ctrlC) { return true }        // (Ctrl+C sí llega al equipo)
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
            status = "Botones guardados (\(f.buttons.count)) en \(ButtonFile.defaultURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
            return nil
        } catch {
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
                status = "Botón «\(b.name)»: el login es «usuario / nombre-de-la-contraseña»"
                return
            }
            Task {
                let sw = s.gate.begin()
                defer { s.gate.end(sw) }
                s.passwords.commandUser = parts[0]
                s.passwords.commandJumpUsers = []
                let r = await InputScript.login(user: parts[0], credential: .named(parts[1])).run(on: s, store: store, abort: sw)
                status = "🔑 Login «\(b.name)»: \(r)"
            }
        }
        if b.mode != .session { status = "▶ \(b.name)" + (targets.count > 1 ? " ×\(targets.count)" : "") }
        current?.view.window?.makeFirstResponder(current?.view)
    }

    // MARK: - pantalla dividida y MultiExec

    /// Dónde escribe MultiExec: los paneles de la vista dividida (si se ve) o todas las pestañas; sin las excluidas.
    var multiExecTargets: [TerminalSession] {
        let pool = showSplit && split != nil ? (split?.panes ?? []).compactMap(tab) : tabs
        return pool.filter { !excluded.contains($0.id) && !$0.exited }
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
        if !fullScreen { titlebarHeight = max(24, w.frame.height - w.contentLayoutRect.height) }
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
                self.titlebarHeight = max(24, w.frame.height - w.contentLayoutRect.height)
                self.fullScreen = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.styleWindows() }
                DebugLog.log("ventana", "pantalla completa (barra de título \(self.titlebarHeight))")
            }
        }
        nc.addObserver(forName: NSWindow.willExitFullScreenNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fullScreen = false }
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
        let routes = tabs.map(\.route)
        guard !routes.isEmpty else {
            if lastOpen.isEmpty { try? FileManager.default.removeItem(at: Self.openTabsFile) }
            return
        }
        AppPaths.ensure(AppPaths.support)
        try? JSONEncoder().encode(routes).write(to: Self.openTabsFile)
    }

    private static func readOpenTabs() -> [ConnectionRoute] {
        (try? Data(contentsOf: openTabsFile)).flatMap { try? JSONDecoder().decode([ConnectionRoute].self, from: $0) } ?? []
    }

    func reopenLast() {
        let routes = lastOpen
        lastOpen = []
        DebugLog.log("app", "reabro \(routes.count): \(routes.map(\.title))")
        for r in routes { open(r) }
    }

    // MARK: - actualizar (de momento, desde el código: ./actualizar.sh)

    /// La carpeta del proyecto, si está en este Mac (con «swift run» o la app compilada aquí).
    static var sourceFolder: URL? {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { u.deleteLastPathComponent() }
        return FileManager.default.fileExists(atPath: u.appendingPathComponent("actualizar.sh").path) ? u : nil
    }

    /// Compila, sustituye la app instalada y la vuelve a abrir con las mismas pestañas.
    func updateFromSource() {
        guard let dir = Self.sourceFolder else {
            status = "No encuentro el código (actualizar.sh) en este Mac"
            return
        }
        saveOpenTabs()
        let log = DebugLog.directory.appendingPathComponent("actualizar.log")
        AppPaths.ensure(DebugLog.directory)
        FileManager.default.createFile(atPath: log.path, contents: nil)
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
            status = "Actualizando: compilando… (se cerrará y se abrirá sola con tus pestañas)"
            DebugLog.log("app", "actualizar: \(dir.path)/actualizar.sh (pid \(p.processIdentifier))")
        } catch {
            status = "No se ha podido actualizar: \(error.localizedDescription)"
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
            case .side2: "2 lado a lado"
            case .stack2: "2 arriba y abajo"
            case .cols3: "3 columnas"
            case .onePlusTwo: "1 + 2"
            case .grid4: "4 (2 × 2)"
            case .grid: "Todas (cuadrícula)"
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
