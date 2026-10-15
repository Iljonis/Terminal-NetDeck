import AppKit
import NetDeckCore
import Observation
import SwiftTerm

/// Salidas del equipo: lo sube la cola de salida, lo lee el principal.
final class OutputCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    private var scheduled = false

    var value: Int { lock.withLock { n } }

    /// true si hay que avisar al hilo principal (uno por tanda).
    func bump() -> Bool {
        lock.withLock {
            n += 1
            defer { scheduled = true }
            return !scheduled
        }
    }

    func delivered() { lock.withLock { scheduled = false } }
}

/// Proceso (o canal SSH) → registro → resaltado (tipo ChromaTerm) → terminal, en su propia cola: una salida enorme no
/// frena la interfaz.
final class OutputPipe: LocalProcessDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "netdeck.salida", qos: .userInteractive)
    let highlighter = Highlighter()
    let counter = OutputCounter()
    nonisolated(unsafe) weak var view: TerminalView?
    var onOutput: @Sendable () -> Void = {}
    /// (generación del proceso, código de salida)
    var onExit: @Sendable (Int, Int32?) -> Void = { _, _ in }
    /// Lo que sale, tal cual (para el registro de la sesión); en la cola de salida.
    var sink: (@Sendable (ArraySlice<UInt8>) -> Void)?
    /// Cada arranque (reconectar) es una generación: lo que llegue de un proceso anterior se ignora.
    private let lock = NSLock()
    private var generation = 0
    private var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)

    func next() -> Int { lock.withLock { generation += 1; return generation } }
    var current: Int { lock.withLock { generation } }

    func receive(_ slice: ArraySlice<UInt8>) {
        sink?(slice)
        let out = highlighter.process(slice)
        view?.feed(byteArray: out[...])
        if counter.bump() { onOutput() }
    }

    /// Texto propio de la app (avisos «[NetDeck] …»): sin resaltar ni registrar.
    func say(_ text: String) {
        queue.async { [weak self] in
            self?.view?.feed(text: text)
            if self?.counter.bump() == true { self?.onOutput() }
        }
    }

    func dataReceived(slice: ArraySlice<UInt8>) { receive(slice) }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) { onExit(current, exitCode) }

    func getWindowSize() -> winsize { lock.withLock { size } }

    func setSize(cols: Int, rows: Int) {
        lock.withLock { size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0) }
    }

    /// Reglas, colores y si está activo (se aplican en la cola de salida, entre trozo y trozo).
    func configure(rules: [HighlightRule], palette: [String: RGB], enabled: Bool) {
        queue.async { [highlighter] in
            highlighter.rules = rules
            highlighter.palette = palette
            highlighter.enabled = enabled
        }
    }
}

/// La vista de SwiftTerm de una pestaña.
final class NetDeckTerminalView: TerminalView {
    /// ⌘F: la barra de búsqueda de SwiftTerm.
    func showFind() {
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        performFindPanelAction(item)
    }

    // Ratón tipo PuTTY/SecureCRT (Ajustes → General → Ratón; los dos apagados de serie).

    /// Copiar al seleccionar: al soltar el botón, lo seleccionado (si hay algo) va al portapapeles.
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard UserDefaults.standard.bool(forKey: AppSettings.copyOnSelectKey), selectionActive,
              let text = getSelection(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Pegar con clic derecho: por `paste(_:)`, el mismo camino que ⌘V (pegado entre corchetes y lo que haga la app
    /// con lo tecleado: MultiExec, Esc…). Con ⌃/⌥, o si el programa del equipo sigue al ratón, como siempre.
    override func rightMouseDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.control, .option])
        guard UserDefaults.standard.bool(forKey: AppSettings.pasteOnRightClickKey), mods.isEmpty,
              !allowMouseReporting || currentMouseMode == .off else {
            super.rightMouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        paste(self)
    }

    /// El menú del clic derecho (o ⌃/⌥+clic derecho con «Pegar con clic derecho»).
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.autoenablesItems = false
        func item(_ title: String, _ action: Selector, _ key: String, enabled: Bool = true) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = self
            i.isEnabled = enabled
            m.addItem(i)
        }
        item(L("Copiar"), #selector(copy(_:)), "c", enabled: selectionActive)
        item(L("Pegar"), #selector(paste(_:)), "v", enabled: NSPasteboard.general.string(forType: .string) != nil)
        m.addItem(.separator())
        item(L("Seleccionar todo"), #selector(selectAll(_:)), "a")
        item(L("Buscar en la salida…"), #selector(findFromMenu), "f")
        return m
    }

    @objc private func findFromMenu() { showFind() }

    override func rightMouseUp(with event: NSEvent) {
        if UserDefaults.standard.bool(forKey: AppSettings.pasteOnRightClickKey),
           event.modifierFlags.intersection([.control, .option]).isEmpty,
           !allowMouseReporting || currentMouseMode == .off { return }
        super.rightMouseUp(with: event)
    }
}

/// Una pestaña: proceso (ssh/telnet o la shell local) + vista + resaltado + automatización de contraseña. Es el `TerminalIO` del núcleo.
@MainActor @Observable
final class TerminalSession: Identifiable, TerminalIO, TerminalViewDelegate {
    enum State: Equatable { case connecting, connected, exited(Int32?) }

    @ObservationIgnored let id = UUID()
    /// Cambia si hay que pasar a «ssh en el salto» (el salto no deja reenviar).
    @ObservationIgnored private(set) var route: ConnectionRoute
    @ObservationIgnored let view: NetDeckTerminalView
    @ObservationIgnored let gate = AutomationGate()
    @ObservationIgnored let passwords: PasswordAutomation
    @ObservationIgnored let ledger: CredentialLedger
    var title: String
    var state = State.connecting
    /// Ha salido algo mientras no se veía (•).
    var activity = false
    /// Equipo en el que estás de verdad (sale del prompt): «core-01».
    var device: String?

    /// Lo que se ve en la pestaña: sólo el equipo de destino (o en el que se está ahora, si se ha saltado a otro).
    var tabTitle: String { route.tabTitle(device: device, home: homeDevice) }
    /// El hostname del propio destino (el primer prompt en él; con salto a mano, el primero tras escribir el ssh).
    @ObservationIgnored private var homeDevice: String?
    /// Ya se ha escrito el ssh en el salto (lo siguiente que se ve es el destino).
    @ObservationIgnored private var hopSent = false

    /// El camino entero, para la ayuda de la pestaña: «core-01 ⟵ bastion · en el salto: ssh … · ahora en pe-mad-02».
    var pathDescription: String {
        var out = title
        if let cmd = route.thenCommand { out += L(" · en el salto: \(cmd)") }
        if tabTitle != route.tabTitle(device: nil) { out += L(" · ahora en \(tabTitle)") }
        return out
    }
    var exited: Bool { if case .exited = state { true } else { false } }
    /// Grabando a un archivo (● REC).
    private(set) var logFile: URL?
    @ObservationIgnored private var logger: SessionLogger?
    /// Se ve ahora (pestaña elegida o panel de la vista).
    @ObservationIgnored var isVisible = false
    /// Ha llegado a su primer prompt (la contraseña de la sesión, si la dio el askpass, ha valido).
    @ObservationIgnored private(set) var loggedIn = false
    @ObservationIgnored var onEvent: ((TerminalSession, PasswordAutomation.Event) -> Void)?
    /// Lo que teclea el usuario (Esc, MultiExec, Intro…): true = ya está atendido, no se envía aquí.
    @ObservationIgnored var onInput: ((TerminalSession, [UInt8]) -> Bool)?
    /// Sesión cerrada: Intro = reconectar, Esc = cerrar la pestaña.
    @ObservationIgnored var onReconnect: ((TerminalSession) -> Void)?
    @ObservationIgnored var onCloseRequest: ((TerminalSession) -> Void)?
    /// «administratively prohibited» con -J: el modelo da otra ruta (ssh escrito en el salto) o nil.
    @ObservationIgnored var onForwardingRefused: ((TerminalSession) -> ConnectionRoute?)?
    /// ¿Entrar en el salto y escribir allí el ssh? (pregunta al usuario: la contraseña del destino pasará por el salto)
    @ObservationIgnored var confirmHop: ((TerminalSession, ConnectionRoute) async -> Bool)?
    /// El contenedor que la muestra ahora (pestaña o panel de la vista dividida).
    @ObservationIgnored weak var host: NSView?
    /// SFTP/FTP: el explorador de archivos (lo que se ve por defecto); la consola sftp, sólo si se pide.
    @ObservationIgnored var browser: RemoteBrowser?
    /// Con explorador: se ve la consola en vez de la vista gráfica.
    var showConsole = false
    /// La consola ya ha arrancado (en SFTP espera a que se pida; así no se conecta dos veces).
    @ObservationIgnored private(set) var started = false
    @ObservationIgnored var deferredEnvironment: [String: String] = [:]

    @ObservationIgnored let pipe = OutputPipe()
    @ObservationIgnored private var process: LocalProcess?
    @ObservationIgnored private var environment: [String: String] = [:]
    @ObservationIgnored private var cache: (rev: Int, lines: [String], cursor: Int)?
    @ObservationIgnored private var hopTask: Task<Void, Never>?
    @ObservationIgnored private var fellBack = false
    /// ssh ha dicho que el salto rechaza el reenvío; sólo cuenta si además ssh termina con 255 (`processExited`).
    @ObservationIgnored private var refusalSeen = false

    init(route: ConnectionRoute, passwords: PasswordAutomation, ledger: CredentialLedger) {
        self.route = route
        self.passwords = passwords
        self.ledger = ledger
        self.title = route.title
        view = NetDeckTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.optionAsMetaKey = false                   // (⌥ para «@», «#», «|» en teclado español)
        view.terminalDelegate = self
        pipe.view = view
        let counter = pipe.counter
        pipe.onOutput = { [weak self] in
            Task { @MainActor in
                counter.delivered()
                self?.scheduleOutputCheck()
            }
        }
        pipe.onExit = { [weak self] gen, code in
            Task { @MainActor in self?.processExited(generation: gen, code: code) }
        }
    }

    /// `extraEnvironment`: el askpass (contraseña de sesión automática).
    func start(extraEnvironment: [String: String] = [:]) {
        environment = extraEnvironment
        started = true
        launch()
    }

    /// La consola de una pestaña con explorador, la primera vez que se pide.
    func startIfNeeded() {
        if !started { start(extraEnvironment: deferredEnvironment) }
    }

    private func launch() {
        let (exe, args) = route.command
        if let problem = route.launchProblem() {             // (falta screen, el adaptador serie o el programa)
            _ = pipe.next()
            state = .exited(nil)
            ErrorLog.error("pestaña", "«\(title)» no arranca: \(problem)")
            pipe.say("\u{1b}[38;5;204m[NetDeck] \(problem)\u{1b}[0m"
                     + L(" · \u{1b}[1mIntro\u{1b}[0m reconectar · \u{1b}[1mEsc\u{1b}[0m cerrar la pestaña\r\n"))
            return
        }
        if route.transport == .serial {
            pipe.say("\u{1b}[38;5;51m[NetDeck] " + L("screen: para salir, Ctrl-A y luego k") + "\u{1b}[0m\r\n")
        }
        // (sftp es ssh por debajo: tampoco le llega el idioma del Mac)
        var env = TerminalEnvironment.prepare(ProcessInfo.processInfo.environment, forSSH: exe == "/usr/bin/ssh" || exe == "/usr/bin/sftp",
                                              sendLocale: UserDefaults.standard.bool(forKey: AppSettings.sendLocaleKey))
        env[Askpass.flag] = nil
        env.merge(environment) { $1 }
        let d = view.terminalDimensions
        pipe.setSize(cols: d.cols, rows: d.rows)
        let gen = pipe.next()
        let p = LocalProcess(delegate: pipe, dispatchQueue: pipe.queue)
        process = p
        state = .connecting
        loggedIn = false
        homeDevice = nil
        hopSent = false
        p.startProcess(executable: exe, args: args, environment: env.map { "\($0.key)=\($0.value)" },
                       currentDirectory: route.isLocal ? AppPaths.home.path : nil)     // (la local, en tu carpeta)
        DebugLog.log("pestaña", "«\(title)» #\(gen) arranca: \(exe) \(args.joined(separator: " "))"
                     + (route.thenCommand.map { " · luego en el salto: «\($0)»" } ?? "")
                     + (p.running ? "" : " · NO ARRANCA"))
        if !p.running { ErrorLog.error("pestaña", "«\(title)» no arranca: \(exe)") }
        if let cmd = route.thenCommand { typeOnJump(cmd) }
    }

    /// Empieza a grabar la salida (texto limpio) en `directory`/AAAA-MM-DD/.
    func startLog(in directory: URL) {
        guard logger == nil else { return }
        let host = route.target.description
        guard let l = SessionLogger(directory: directory, name: route.sessionName ?? title, host: host) else {
            ErrorLog.error("registro", "«\(title)»: no se puede escribir en \(directory.path)")
            return
        }
        logger = l
        logFile = l.url
        pipe.queue.async { [pipe] in pipe.sink = { l.feed($0) } }
        DebugLog.log("registro", "«\(title)» → \(l.url.path)")
    }

    func stopLog() {
        guard let l = logger else { return }
        logger = nil
        logFile = nil
        pipe.queue.async { [pipe] in
            pipe.sink = nil
            l.close()
        }
    }

    /// Reconectar en la misma pestaña (el historial se queda).
    func restart() {
        guard started else { return startIfNeeded() }
        hopTask?.cancel()
        if !exited { process?.terminate() }
        pipe.say(L("\r\n\u{1b}[38;5;51m[NetDeck] Reconectando…\u{1b}[0m\r\n"))
        refusalSeen = false
        launch()
    }

    func terminate() {
        hopTask?.cancel()
        browser?.disconnect()
        process?.terminate()
        stopLog()
    }

    /// Salto «a mano»: al salir el prompt del salto, «ssh equipo». Esc lo corta.
    private func typeOnJump(_ cmd: String) {
        hopTask?.cancel()
        hopTask = Task { [weak self] in
            guard let self else { return }
            let sw = self.gate.begin()
            defer { self.gate.end(sw) }
            let clock = ContinuousClock()
            let end = clock.now + .seconds(90)
            while clock.now < end, !Task.isCancelled {
                if sw.isTripped { DebugLog.log("salto", "«\(self.title)»: cancelado con Esc antes de «\(cmd)»"); return }
                if self.exited { DebugLog.log("salto", "«\(self.title)»: el salto se ha cerrado antes de su prompt"); return }
                let line = self.cursorLine.trimmingCharacters(in: .whitespaces)
                if !line.hasPrefix(Askpass.marker), DevicePrompt.generic.matches(line) {
                    self.passwords.commandUser = self.route.thenUser
                    self.passwords.commandJumpUsers = []
                    DebugLog.log("salto", "«\(self.title)»: prompt del salto «\(line)» → «\(cmd)»")
                    self.hopSent = true
                    self.sendLine(cmd)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            if !Task.isCancelled {
                DebugLog.log("salto", "«\(self.title)»: sin prompt del salto en 90 s (última línea «\(self.cursorLine)»)")
                self.pipe.say(L("\r\n\u{1b}[38;5;204m[NetDeck] El salto no ha llegado a su prompt: escribe tú «\(cmd)»\u{1b}[0m\r\n"))
            }
        }
    }

    private func processExited(generation: Int, code: Int32?) {
        guard generation == pipe.current else { return }      // (un proceso anterior a reconectar)
        hopTask?.cancel()
        state = .exited(code)
        gate.abortAll()
        if code == 255, !fellBack, !loggedIn, route.thenCommand == nil, !route.jumps.isEmpty {
            // (ssh sale justo después de escribir «stdio forwarding failed»: esa salida puede no haberse mirado aún;
            // un momento para que llegue y se decide con la pantalla)
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, generation == self.pipe.current else { return }
                if !self.refusalSeen, ConnectionRoute.forwardingRefused(self.lines(from: max(0, self.cursorRow - 8))) {
                    self.refusalSeen = true
                }
                if self.refusalSeen, self.fallBackToHop() { return }
                self.sayClosed(generation, code)
            }
            return
        }
        sayClosed(generation, code)
    }

    private func sayClosed(_ generation: Int, _ code: Int32?) {
        // (sin las últimas líneas de la pantalla: podrían llevar algo tecleado con eco)
        DebugLog.log("pestaña", "«\(title)» #\(generation) termina (código \(code.map(String.init) ?? "?"))")
        pipe.say(L("\r\n\u{1b}[38;5;204m[NetDeck] Sesión cerrada\(code.map { L(" (código \($0))") } ?? "")\u{1b}[0m")
                 + L(" · \u{1b}[1mIntro\u{1b}[0m reconectar · \u{1b}[1mEsc\u{1b}[0m cerrar la pestaña\r\n"))
    }

    func apply(theme t: Theme, font: NSFont) {
        view.font = font
        view.nativeBackgroundColor = NSColor(t.background)
        view.nativeForegroundColor = NSColor(t.text)
        view.caretColor = NSColor(t.accent)
        view.selectedTextBackgroundColor = NSColor(t.selection)
        view.installColors(t.ansi.map { SwiftTerm.Color($0) })
    }

    func highlight(rules: [HighlightRule], palette: [String: RGB], enabled: Bool) {
        pipe.configure(rules: rules, palette: palette, enabled: enabled)
    }

    /// Intro del usuario: si era «ssh …»/«telnet …», su usuario cuenta para la regla de la contraseña.
    func noteCommand() {
        if let e = CommandLineUser.parse(cursorLine) {
            passwords.commandUser = e.user
            passwords.commandJumpUsers = CommandLineUser.jumpUsers(cursorLine)
            passwords.commandHosts = CommandLineUser.hosts(cursorLine)
        }
    }

    /// Mirar la pantalla como mucho cada 60 ms: con mucha salida (show tech, tail -f) no se recorre el búfer entero en
    /// cada trozo que llega.
    private func scheduleOutputCheck() {
        guard !checkScheduled else { return }
        checkScheduled = true
        let wait = Duration.milliseconds(60) - (ContinuousClock.now - lastCheck)
        Task { @MainActor [weak self] in
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard let self else { return }
            checkScheduled = false
            lastCheck = .now
            await outputChanged()
        }
    }
    private var checkScheduled = false
    private var lastCheck = ContinuousClock.now - .seconds(1)

    private func outputChanged() async {
        if !isVisible { activity = true }
        let line = cursorLine.trimmingCharacters(in: .whitespaces)
        if !loggedIn {
            if !route.jumps.isEmpty, route.thenCommand == nil, !fellBack, !refusalSeen, ConnectionRoute.forwardingRefused(lines(from: max(0, cursorRow - 6))) {
                refusalSeen = true                 // (se decide al terminar ssh: el texto solo lo podría poner el salto)
            }
            if !line.hasPrefix(Askpass.marker), DevicePrompt.generic.matches(line) {
                loggedIn = true
                state = .connected
                let given = Askpass.takeGiven(session: id)
                given.forEach(ledger.confirm)      // (la del askpass ha valido)
                DebugLog.log("pestaña", "«\(title)» en su prompt «\(line)»"
                             + (given.isEmpty ? "" : " · confirmadas: \(given.map(\.description).joined(separator: ", "))"))
            }
        }
        if let d = PromptDevice.name(line, previous: device), d != device {
            if homeDevice == nil, loggedIn, route.thenCommand == nil || hopSent { homeDevice = d }
            device = d
            if route.thenCommand != nil || d != route.target.host { DebugLog.log("pestaña", "«\(title)» → equipo «\(d)»") }
        }
        if let e = await passwords.observe(self, gate: gate) {
            DebugLog.log("contraseña", "«\(title)»: \(e)")
            onEvent?(self, e)
        }
    }

    /// El salto no deja reenviar (-J) y ssh ha terminado con 255: con tu permiso, se abre el salto y se escribe allí el
    /// ssh. Ahí la contraseña del destino pasa por la shell del salto: sólo se sugiere, no se escribe sola.
    /// true = se encarga (no se dice «Sesión cerrada»).
    private func fallBackToHop() -> Bool {
        guard refusalSeen, !fellBack, !loggedIn, route.thenCommand == nil, !route.jumps.isEmpty else { return false }
        fellBack = true
        let given = Askpass.takeGiven(session: id)
        given.forEach(ledger.confirm)               // (el salto sí ha entrado: el fallo es al abrir el canal)
        guard let r = onForwardingRefused?(self) else {
            DebugLog.log("salto", "«\(title)»: -J rechazado y no hay forma de escribirlo en el salto")
            return false
        }
        let generation = pipe.current
        Task { [weak self] in
            guard let self else { return }
            let ok = await self.confirmHop?(self, r) == true
            guard generation == self.pipe.current else { return }       // (mientras preguntaba, se ha reconectado)
            guard ok else {
                DebugLog.log("salto", "«\(self.title)»: -J rechazado; el salto a mano no se ha aceptado")
                self.pipe.say(L("\r\n\u{1b}[38;5;204m[NetDeck] El salto no deja reenviar (-J) y no se ha entrado por él\u{1b}[0m")
                              + L(" · \u{1b}[1mIntro\u{1b}[0m reconectar · \u{1b}[1mEsc\u{1b}[0m cerrar la pestaña\r\n"))
                return
            }
            DebugLog.log("salto", "«\(self.title)»: -J rechazado por el salto → abro «\(r.command.arguments.joined(separator: " "))» y escribo «\(r.thenCommand ?? "")»")
            self.pipe.say(L("\r\n\u{1b}[38;5;221m[NetDeck] El salto no deja reenviar (-J): entro en el salto y escribo «\(r.thenCommand ?? "")» (la contraseña del destino sólo se sugiere)\u{1b}[0m\r\n"))
            self.passwords.onlySuggestDevices = true
            self.route = r
            self.launch()
        }
        return true
    }

    // MARK: - TerminalIO (directo al proceso: ni MultiExec ni Esc)

    func send(bytes: [UInt8]) {
        guard !exited else { return }
        process?.send(data: bytes[...])
    }

    var revision: Int { pipe.counter.value }
    var cursorRow: Int { snapshot().cursor }

    var cursorLine: String {
        let s = snapshot()
        return s.lines.indices.contains(s.cursor) ? s.lines[s.cursor] : ""
    }

    func lines(from row: Int) -> [String] {
        let s = snapshot()
        guard !s.lines.isEmpty, row <= s.cursor else { return [] }
        return Array(s.lines[max(0, row)...s.cursor])
    }

    /// Todo el búfer (historial + pantalla) como texto; la pantalla son las últimas `rows` filas.
    private func snapshot() -> (lines: [String], cursor: Int) {
        let rev = pipe.counter.value
        if let c = cache, c.rev == rev { return (c.lines, c.cursor) }
        var lines = String(decoding: view.getBufferAsData(), as: UTF8.self).components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let st = view.terminalStateSnapshot()
        let cursor = max(0, min(lines.count - 1, lines.count - st.dimensions.rows + st.cursor.row))
        cache = (rev, lines, cursor)
        return (lines, cursor)
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if exited {
            if data.contains(13) { onReconnect?(self) } else if Array(data) == [27] { onCloseRequest?(self) }
            return
        }
        if onInput?(self, Array(data)) == true { return }
        process?.send(data: data)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        pipe.setSize(cols: newCols, rows: newRows)
        var size = pipe.getWindowSize()
        _ = process?.updateWindowSize(&size)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func bell(source: TerminalView) { NSSound.beep() }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        // (el enlace lo pone el equipo: nada de «ssh://» a donde él quiera)
        if let u = URL(string: link), ["http", "https"].contains(u.scheme ?? "") { NSWorkspace.shared.open(u) }
    }

    // OSC 52: el equipo remoto no lee ni cambia el portapapeles del Mac (podría llevarse una contraseña copiada o
    // dejar una orden maliciosa para pegarla en otro sitio).
    func clipboardCopy(source: TerminalView, content: Data) {}

    func clipboardRead(source: TerminalView) -> Data? { nil }

    func kittyClipboardCapabilities(source: TerminalView) -> KittyClipboardCapabilities { [] }
    func kittyClipboardAvailableMimeTypes(source: TerminalView, location: KittyClipboardLocation) -> [String]? { nil }
    func kittyClipboardRead(source: TerminalView, location: KittyClipboardLocation, mimeType: String) -> KittyClipboardReadResult? { nil }
    func kittyClipboardWrite(source: TerminalView, location: KittyClipboardLocation,
                             content: KittyClipboardWriteContent) -> KittyClipboardWriteResult { .unsupported }
    func kittyClipboardRequestPermission(source: TerminalView,
                                         request: KittyClipboardPermissionRequest) -> KittyClipboardPermissionResult { .deny }
}
