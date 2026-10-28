import AppKit
import Darwin
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

    // Selección rectangular: ⌥ + arrastrar (como SecureCRT o iTerm), sólo las columnas del rectángulo de cada fila.
    // SwiftTerm no la tiene: se dibuja encima y el texto sale de la pantalla (`BlockSelection`). Si el programa del
    // equipo sigue al ratón, ⌥ + arrastrar es suyo.

    /// El rectángulo (filas y columnas de pantalla) y su texto: lo que copia ⌘C mientras esté.
    private(set) var block: BlockSelection?
    private(set) var blockText: String?
    private var blockAnchor: (row: Int, col: Int)?
    private var blockDragged = false
    private var blockDimensions = (cols: 80, rows: 24)
    private lazy var blockOverlay: BlockOverlay = {
        let v = BlockOverlay(frame: .zero)
        addSubview(v, positioned: .above, relativeTo: nil)
        return v
    }()

    private func wantsBlock(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.option) && (!allowMouseReporting || currentMouseMode == .off)
    }

    /// El tamaño de la celda, como lo calcula SwiftTerm (alto de la letra por el interlineado, ancho de la «W»,
    /// ajustados a los píxeles de la pantalla).
    var cellSize: CGSize {
        let f = font
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let w = f.advancement(forGlyph: f.glyph(withName: "W")).width
        let h = ceil((f.ascender - f.descender + f.leading) * lineSpacing)
        return CGSize(width: max(1, (w * scale).rounded() / scale), height: max(1, ceil(h * scale) / scale))
    }

    /// La celda de pantalla (fila desde arriba, columna) bajo un punto de la vista.
    func cell(at p: CGPoint) -> (row: Int, col: Int) {
        let c = cellSize
        return (min(max(0, Int((bounds.height - p.y) / c.height)), blockDimensions.rows - 1),
                min(max(0, Int(p.x / c.width)), blockDimensions.cols - 1))
    }

    /// El centro de una celda de pantalla, en puntos de la vista (capturas y pruebas).
    func point(ofCell row: Int, _ col: Int) -> CGPoint {
        let c = cellSize
        return CGPoint(x: (CGFloat(col) + 0.5) * c.width, y: bounds.height - (CGFloat(row) + 0.5) * c.height)
    }

    private func showBlock(_ b: BlockSelection) {
        block = b
        let c = cellSize
        blockOverlay.color = selectedTextBackgroundColor
        blockOverlay.frame = NSRect(x: CGFloat(b.cols.lowerBound) * c.width,
                                    y: bounds.height - CGFloat(b.rows.upperBound + 1) * c.height,
                                    width: CGFloat(b.cols.count) * c.width, height: CGFloat(b.rows.count) * c.height)
        blockOverlay.isHidden = false
    }

    /// Quita el rectángulo (al hacer clic, teclear o moverse la pantalla: deja de corresponder a lo que se ve).
    func clearBlock() {
        guard block != nil || blockAnchor != nil else { return }
        block = nil
        blockText = nil
        blockAnchor = nil
        blockOverlay.isHidden = true
    }

    /// El texto del rectángulo con lo que hay ahora en pantalla.
    func blockContents(_ b: BlockSelection) -> String {
        let snap = terminalStateSnapshot()
        var screen = Array(repeating: (text: "", cellWidths: [Int]()), count: snap.dimensions.rows)
        for r in snap.visibleRows where screen.indices.contains(r.row) { screen[r.row] = (r.text, r.cellWidths) }
        return b.text(of: screen)
    }

    override func mouseDown(with event: NSEvent) {
        guard wantsBlock(event) else {
            clearBlock()
            super.mouseDown(with: event)
            return
        }
        clearBlock()
        selectNone()
        window?.makeFirstResponder(self)
        let d = terminalStateSnapshot().dimensions
        blockDimensions = (max(1, d.cols), max(1, d.rows))
        blockAnchor = cell(at: convert(event.locationInWindow, from: nil))
        blockDragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let a = blockAnchor else { super.mouseDragged(with: event); return }
        blockDragged = true
        showBlock(BlockSelection(from: a, to: cell(at: convert(event.locationInWindow, from: nil))))
    }

    // Ratón tipo PuTTY/SecureCRT (Ajustes → Terminal → Ratón; los dos apagados de serie).

    /// Copiar al seleccionar: al soltar el botón, lo seleccionado (si hay algo) va al portapapeles.
    override func mouseUp(with event: NSEvent) {
        if let a = blockAnchor {
            blockAnchor = nil
            guard blockDragged else { clearBlock(); return }          // (⌥ + clic sin arrastrar: nada)
            let b = BlockSelection(from: a, to: cell(at: convert(event.locationInWindow, from: nil)))
            showBlock(b)
            blockText = blockContents(b)
            if UserDefaults.standard.bool(forKey: AppSettings.copyOnSelectKey), let t = blockText, !t.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(t, forType: .string)
            }
            return
        }
        super.mouseUp(with: event)
        guard UserDefaults.standard.bool(forKey: AppSettings.copyOnSelectKey), selectionActive,
              let text = getSelection(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// ⌘C: el rectángulo si lo hay; si no, la selección de siempre.
    override func copy(_ sender: Any) {
        guard let t = blockText, !t.isEmpty else { super.copy(sender); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(t, forType: .string)
    }

    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { clearBlock() }
        super.setFrameSize(newSize)
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
        item(L("Copiar"), #selector(copy(_:)), "c", enabled: selectionActive || blockText?.isEmpty == false)
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

/// El rectángulo de la selección con ⌥: el color de la selección, translúcido, encima del texto (no recibe clics).
final class BlockOverlay: NSView {
    var color = NSColor.selectedTextBackgroundColor { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        color.withAlphaComponent(0.45).setFill()
        bounds.fill()
        color.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}

/// Una pestaña: proceso (ssh/telnet o la shell local) + vista + resaltado + automatización de contraseña. Es el `TerminalIO` del núcleo.
@MainActor @Observable
final class TerminalSession: Identifiable, PendingAuthenticationIO, TerminalViewDelegate {
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

    /// Lo que se ve en la pestaña: el nombre que le has puesto o, si no, sólo el equipo de destino (o en el que se
    /// está ahora, si se ha saltado a otro).
    var tabTitle: String { customTitle ?? deviceTitle }
    private var deviceTitle: String { route.tabTitle(device: device, home: homeDevice) }
    /// El nombre puesto a mano («Renombrar la pestaña…»): se queda mientras sigas en el mismo equipo; un prompt de
    /// otro equipo lo quita (`TabRename`).
    var customTitle: String? { renamed.name }
    private var renamed = TabRename()

    func rename(_ name: String?) {
        renamed.set(name, on: device)
        DebugLog.log("pestaña", "«\(title)» renombrada: \(customTitle.map { "«\($0)»" } ?? "nombre del equipo")")
    }
    /// El hostname del propio destino (el primer prompt en él; con salto a mano, el primero tras escribir el ssh).
    @ObservationIgnored private var homeDevice: String?
    /// Ya se ha escrito el ssh en el salto (lo siguiente que se ve es el destino).
    @ObservationIgnored private var hopSent = false

    /// El camino entero, para la ayuda de la pestaña: «core-01 ⟵ bastion · en el salto: ssh … · ahora en pe-mad-02».
    var pathDescription: String {
        var out = title
        if let cmd = route.thenCommand { out += L(" · en el salto: \(cmd)") }
        if deviceTitle != route.tabTitle(device: nil) { out += L(" · ahora en \(deviceTitle)") }
        return out
    }
    var exited: Bool { if case .exited = state { true } else { false } }
    /// Grabando a un archivo (● REC).
    private(set) var logFile: URL?
    @ObservationIgnored private var logger: SessionLogger?
    /// Se ve ahora (pestaña elegida o panel de la vista).
    @ObservationIgnored var isVisible = false
    /// Ha llegado a su primer prompt (estado visual; no confirma ninguna contraseña por sí mismo).
    @ObservationIgnored private(set) var loggedIn = false
    /// El perfil de su sesión (`TerminalProfile`; lo aplica `AppModel.applyProfile`) y lo que ha quedado de él:
    /// el tema (también para los colores del resaltado) y el prompt propio («# @prompt …»; nil = el genérico).
    @ObservationIgnored var profile = TerminalProfile()
    @ObservationIgnored private(set) var theme: Theme?
    @ObservationIgnored var promptRule: PromptRule?
    @ObservationIgnored private var appliedScrollback = TerminalHistory.current
    @ObservationIgnored var onEvent: ((TerminalSession, PasswordAutomation.Event) -> Void)?
    /// La que has escrito tú en un «Password:» y ha entrado (para ofrecer guardarla en el Llavero).
    @ObservationIgnored var onTypedPassword: ((TerminalSession, TypedPassword.Candidate) -> Void)?
    @ObservationIgnored private var typedPassword = TypedPassword()
    /// Ajustes → Contraseñas → «Ofrecer guardar la que escribo yo»: si no, lo que tecleas ni se mira.
    @ObservationIgnored var offerTypedPassword: () -> Bool = { false }
    /// Lo que teclea el usuario (Esc, MultiExec, Intro…): true = ya está atendido, no se envía aquí.
    @ObservationIgnored var onInput: ((TerminalSession, [UInt8]) -> Bool)?
    /// Sesión cerrada: Intro = reconectar, Esc = cerrar la pestaña.
    @ObservationIgnored var onReconnect: ((TerminalSession) -> Void)?
    @ObservationIgnored var onCloseRequest: ((TerminalSession) -> Void)?
    /// «administratively prohibited» con -J: el modelo da otra ruta (ssh escrito en el salto) o nil.
    @ObservationIgnored var onForwardingRefused: ((TerminalSession) -> ConnectionRoute?)?
    /// ¿Entrar en el salto y escribir allí el ssh? (pregunta al usuario: la contraseña del destino pasará por el salto)
    @ObservationIgnored var confirmHop: ((TerminalSession, ConnectionRoute) async -> Bool)?
    /// ssh dice que la clave del equipo ha cambiado: ¿quitar la vieja de known_hosts y reconectar? (pregunta al usuario)
    @ObservationIgnored var onHostKeyChanged: ((TerminalSession, HostKeyMismatch) async -> Bool)?
    /// El registro no se puede crear o ha dejado de escribirse (el aviso, ya escrito).
    @ObservationIgnored var onLogFailed: ((TerminalSession, String) -> Void)?
    /// La consola serie no se abre (ruta, trama o un valor que el puerto no acepta): el aviso «✗ …», ya escrito.
    @ObservationIgnored var onProblem: ((TerminalSession, String) -> Void)?
    /// El contenedor que la muestra ahora (pestaña o panel de la vista dividida).
    @ObservationIgnored weak var host: NSView?
    /// SFTP/FTP: el explorador de archivos (lo que se ve por defecto); la consola sftp, sólo si se pide.
    @ObservationIgnored var browser: RemoteBrowser?
    /// El explorador SFTP al lado del terminal (pestañas ssh); nil hasta que se abre la primera vez.
    var sidePanel: SFTPSidePanel?
    /// Con explorador: se ve la consola en vez de la vista gráfica.
    var showConsole = false
    /// La consola ya ha arrancado (en SFTP espera a que se pida; así no se conecta dos veces).
    @ObservationIgnored private(set) var started = false
    @ObservationIgnored var deferredEnvironment: [String: String] = [:]
    /// El askpass con los Ajustes de ahora (contraseña automática, credencial por defecto, ssh_config), en cada
    /// conexión: al reconectar, tras aceptar una clave nueva o al entrar por el salto a mano, no el de cuando se abrió.
    @ObservationIgnored var askpassEnvironment: (@MainActor () -> [String: String])?

    @ObservationIgnored let pipe = OutputPipe()
    @ObservationIgnored private var process: LocalProcess?
    /// Consola serie: el puerto abierto por la app (sin proceso).
    @ObservationIgnored private var serialPort: SerialPort?
    @ObservationIgnored private var environment: [String: String] = [:]
    /// La última lectura del búfer: sus líneas, el índice del cursor en ellas y la fila absoluta de la primera.
    @ObservationIgnored private var cache: (rev: Int, lines: [String], cursor: Int, base: Int)?
    /// Filas absolutas que no retroceden con el historial lleno (`BufferRows`).
    @ObservationIgnored private var bufferRows = BufferRows()
    /// ¿En la pantalla alternativa? (`BufferRows.alternateEvidence`: sólo cambia con pruebas)
    @ObservationIgnored private var alternate = false
    @ObservationIgnored private var hopTask: Task<Void, Never>?
    @ObservationIgnored private var fellBack = false
    /// ssh ha dicho que el salto rechaza el reenvío; sólo cuenta si además ssh termina con 255 (`processExited`).
    @ObservationIgnored private var refusalSeen = false
    /// ssh ha avisado de que la clave del equipo no es la de known_hosts (se pregunta al terminar ssh).
    @ObservationIgnored private var hostKeyMismatch: HostKeyMismatch?
    /// Tras quitar la clave vieja con tu permiso: la huella que aceptaste. Si al reconectar ssh pregunta por un equipo
    /// nuevo con esa misma huella, se contesta «yes» solo; con otra, se deja la pregunta para ti.
    @ObservationIgnored private var acceptedFingerprint: String?
    /// Fila del búfer al arrancar el proceso: lo de antes (otra conexión de la misma pestaña) no cuenta.
    @ObservationIgnored private var launchRow = 0

    init(route: ConnectionRoute, passwords: PasswordAutomation, ledger: CredentialLedger) {
        self.route = route
        self.passwords = passwords
        self.ledger = ledger
        self.title = route.title
        view = NetDeckTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.optionAsMetaKey = false                   // (⌥ para «@», «#», «|» en teclado español)
        view.changeScrollback(TerminalHistory.current) // (Ajustes → Terminal; SwiftTerm guarda 500)
        view.terminalDelegate = self
        pipe.view = view
        passwords.onRetry = { [weak self] in self?.scheduleOutputCheck() }
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
        cancelPasswordContext()
        passwords.reset()
        if let problem = route.launchProblem() { return fail(problem) }  // (el adaptador serie, su trama o el programa)
        if route.transport == .serial { return openSerial() }
        var (exe, args) = route.command(sharing: AppSettings.jumpSharing, configFile: AppSettings.sshConfigFile)
        // (sftp es ssh por debajo: tampoco le llega el idioma del Mac)
        var env = TerminalEnvironment.prepare(ProcessInfo.processInfo.environment, forSSH: exe == "/usr/bin/ssh" || exe == "/usr/bin/sftp",
                                              sendLocale: UserDefaults.standard.bool(forKey: AppSettings.sendLocaleKey))
        env[Askpass.flag] = nil
        if let fresh = askpassEnvironment { environment = fresh() }
        env.merge(environment) { $1 }
        // (capturas de desarrollo: la terminal local, sin el prompt de este Mac. Una shell de login lee /etc/profile, que
        // pone tu usuario y el nombre del equipo; NETDECK_HOME no cambia el HOME de lo que se lanza. Sin login, sin
        // perfiles, con un prompt de ejemplo y la carpeta de ejemplo)
        if ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] != nil, route.isLocal {
            (exe, args) = ("/bin/sh", [])
            env["HOME"] = AppPaths.home.path
            env["PS1"] = "tu.usuario@mac:~$ "
            for k in ["ENV", "BASH_ENV", "PROMPT_COMMAND", "ZDOTDIR"] { env[k] = nil }
        }
        let d = view.terminalDimensions
        pipe.setSize(cols: d.cols, rows: d.rows)
        let gen = pipe.next()
        let p = LocalProcess(delegate: pipe, dispatchQueue: pipe.queue)
        process = p
        state = .connecting
        loggedIn = false
        homeDevice = nil
        hopSent = false
        hostKeyMismatch = nil
        launchRow = cursorRow
        _ = Askpass.takeGiven(session: id)      // (lo de una conexión anterior no se confirma con ésta)
        p.startProcess(executable: exe, args: args, environment: env.map { "\($0.key)=\($0.value)" },
                       currentDirectory: route.isLocal ? AppPaths.home.path : nil)     // (la local, en tu carpeta)
        DebugLog.log("pestaña", "«\(title)» #\(gen) arranca: \(exe) \(args.joined(separator: " "))"
                     + (route.thenCommand.map { " · luego en el salto: «\($0)»" } ?? "")
                     + (p.running ? "" : " · NO ARRANCA"))
        if !p.running { ErrorLog.error("pestaña", "«\(title)» no arranca: \(exe)") }
        if let cmd = route.thenCommand { typeOnJump(cmd) }
    }

    /// No arranca: el motivo en la pestaña (Intro reintenta) y, si es la consola serie, también como aviso.
    private func fail(_ problem: String) {
        _ = pipe.next()
        state = .exited(nil)
        ErrorLog.error("pestaña", "«\(title)» no arranca: \(problem)")
        pipe.say("\u{1b}[38;5;204m[NetDeck] \(problem)\u{1b}[0m"
                 + L(" · \u{1b}[1mIntro\u{1b}[0m reconectar · \u{1b}[1mEsc\u{1b}[0m cerrar la pestaña\r\n"))
        if route.transport == .serial { onProblem?(self, L("✗ «\(title)»: \(problem)")) }
    }

    /// Consola serie: la app abre el puerto y le aplica la trama, comprobada (`SerialPort`); si el puerto se cierra
    /// solo (adaptador desenchufado), como una sesión cerrada: Intro reabre, Esc cierra la pestaña.
    private func openSerial() {
        let line = route.serial ?? SerialLine()          // (sin puerto, `SerialPort` lo rechaza con su motivo)
        serialPort?.close()
        serialPort = nil
        let pipe = pipe
        let gen = pipe.next()
        do {
            serialPort = try SerialPort(line, queue: pipe.queue, onData: { pipe.receive($0) }, onClose: { why in
                guard gen == pipe.current else { return }
                pipe.say("\r\n\u{1b}[38;5;204m[NetDeck] \(why)\u{1b}[0m")
                pipe.onExit(gen, nil)
            })
        } catch {
            return fail(error.localizedDescription)
        }
        state = .connecting
        loggedIn = false
        homeDevice = nil
        hopSent = false
        hostKeyMismatch = nil
        launchRow = cursorRow
        DebugLog.log("pestaña", "«\(title)» #\(gen) abre el puerto serie \(line.annotation)")
        pipe.say("\u{1b}[38;5;51m[NetDeck] " + L("\(line.device) a \(String(line.speed)) \(line.frame) · para salir, cierra la pestaña")
                 + "\u{1b}[0m\r\n")
    }

    /// Empieza a grabar la salida (texto limpio) en `directory`/AAAA-MM-DD/.
    func startLog(in directory: URL) {
        guard logger == nil else { return }
        let host = route.target.description
        let l: SessionLogger
        do { l = try SessionLogger(directory: directory, name: route.sessionName ?? title, host: host) } catch {
            ErrorLog.error("registro", "«\(title)»: no se puede escribir en \(directory.path): \(error.localizedDescription)")
            onLogFailed?(self, L("✗ No se graba «\(title)»: no se puede escribir en \(AppPaths.tilde(directory.path)) (\(error.localizedDescription))"))
            return
        }
        l.onFailure = { [weak self, weak l] why in
            Task { @MainActor in if let l { self?.logFailed(l, why) } }
        }
        logger = l
        logFile = l.url
        pipe.queue.async { [pipe] in pipe.sink = { l.feed($0) } }
        DebugLog.log("registro", "«\(title)» → \(l.url.path)")
    }

    /// No se ha podido escribir en el registro: se deja de grabar (fuera el ● REC) y se avisa.
    private func logFailed(_ l: SessionLogger, _ why: String) {
        guard logger === l else { return }
        stopLog()
        onLogFailed?(self, L("✗ Se ha dejado de grabar «\(title)»: \(why)"))
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
        gate.abortAll()
        guard started else { return startIfNeeded() }
        hopTask?.cancel()
        retireAuthentication()
        if !exited { process?.terminate() }
        serialPort?.close()
        pipe.say(L("\r\n\u{1b}[38;5;51m[NetDeck] Reconectando…\u{1b}[0m\r\n"))
        refusalSeen = false
        launch()
    }

    func terminate() {
        retireAuthentication()
        gate.abortAll()
        hopTask?.cancel()
        browser?.shutdown()
        sidePanel?.close()
        process?.terminate()
        serialPort?.close()
        stopLog()
    }

    /// No basta con solicitar SIGTERM: una autenticación enviada mantiene su reserva hasta que el proceso muera. Si a
    /// los 3 s sigue vivo, SIGKILL (como los túneles) y, como mucho 2 s después, se suelta igual: la espera no es eterna.
    private func retireAuthentication() {
        commandInput = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
        guard let cleanup = passwords.connectionCleanup() else { return }
        let p = process, pid = p?.shellPid ?? 0, title = title
        guard let p, pid > 0 else { cleanup(); return }
        Task { [weak p] in                                   // (sin la pestaña: al soltarla, SwiftTerm hace lo suyo)
            // (vivo mientras SwiftTerm no lo recoja, que deja su shellPid a 0; si ya no está el proceso, por el PID. La
            // señal, sólo a su hijo sin recoger: nunca a un PID reciclado; sin el proceso, ya lo mata SwiftTerm al soltarlo)
            await ProcessExit.wait(alive: { p.map { $0.shellPid == pid } ?? (kill(pid, 0) == 0 || errno == EPERM) }, kill: {
                guard p?.shellPid == pid else { return }
                DebugLog.log("pestaña", "«\(title)»: el proceso \(pid) no termina con SIGTERM → SIGKILL")
                kill(pid, SIGKILL)
            })
            cleanup()
        }
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
                    self.passwords.beginCommand(cmd, after: self.cursorRow)
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
        commandInput = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
        passwords.connectionEnded()
        typedPassword.forget()
        state = .exited(code)
        gate.abortAll()
        if checksHostKey, !loggedIn, code != 0 {
            // (el aviso de ssh puede no haberse mirado aún: un momento para que llegue y se decide con la pantalla)
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, generation == self.pipe.current else { return }
                if let m = self.hostKeyMismatch ?? HostKeyMismatch.detect(self.lines(from: self.launchRow)) {
                    self.hostKeyChanged(m, generation: generation, code: code)
                } else {
                    self.exitedWithoutHostKey(generation: generation, code: code)
                }
            }
            return
        }
        exitedWithoutHostKey(generation: generation, code: code)
    }

    /// ssh habla con known_hosts de este Mac: ssh y la consola sftp, sin salto «a mano» (ahí el ssh es el del salto).
    private var checksHostKey: Bool {
        onHostKeyChanged != nil && !route.isLocal && (route.transport == .ssh || route.transport == .sftp) && route.thenCommand == nil
    }

    /// La clave del equipo ha cambiado: no se ha conectado. Se pregunta (puede ser alguien en medio); si aceptas, se
    /// quita la vieja de known_hosts (como «ssh-keygen -R») y se reconecta solo.
    private func hostKeyChanged(_ found: HostKeyMismatch, generation: Int, code: Int32?) {
        hostKeyMismatch = nil
        let m = found
        // (sin «Host key for … has changed», el equipo lo dice «ssh -G» al comprobarlo, no la pestaña)
        let host = m.host ?? route.target.host
        guard m.host.map(KnownHosts.isValidHost) ?? true, let ask = onHostKeyChanged else {
            return exitedWithoutHostKey(generation: generation, code: code)
        }
        DebugLog.log("known_hosts", "«\(title)»: la clave de \(host) ha cambiado (\(m.fingerprint ?? "sin huella"))")
        pipe.say(L("\r\n\u{1b}[38;5;204m[NetDeck] La clave del equipo «\(host)» ha cambiado: no se ha conectado\u{1b}[0m\r\n"))
        let route = self.route, configFile = AppSettings.sshConfigFile
        Task { [weak self] in
            // (antes de preguntar: que el aviso sea de esta conexión y su known_hosts, según «ssh -G»)
            let context = await KnownHosts.contextInBackground(for: route, configFile: configFile)
            guard let self, generation == self.pipe.current else { return }
            let checked = context.map { KnownHosts.verify(m, against: $0) }
                ?? .failure(KnownHosts.Refused(message: L("«ssh -G» no ha dicho qué known_hosts usa esta conexión")))
            let target: (host: String, file: URL)
            switch checked {
            case .success(let t): target = t
            case .failure(let why):
                ErrorLog.warning("known_hosts", "«\(self.title)»: no se limpia la clave de \(host): \(why.message)")
                self.pipe.say(L("\u{1b}[38;5;204m[NetDeck] No se toca known_hosts: \(why.message)\u{1b}[0m"))
                self.sayClosed(generation, code)
                return
            }
            var shown = m
            shown.host = target.host
            shown.file = target.file.path
            let ok = await ask(self, shown)
            guard generation == self.pipe.current else { return }       // (mientras preguntaba, se ha reconectado)
            guard ok else {
                DebugLog.log("known_hosts", "«\(self.title)»: clave de \(target.host) no aceptada")
                self.pipe.say(L("\u{1b}[38;5;204m[NetDeck] known_hosts no se ha tocado\u{1b}[0m"))
                self.sayClosed(generation, code)
                return
            }
            if let err = await KnownHosts.removeInBackground(host: target.host, from: target.file) {
                ErrorLog.error("known_hosts", "no se ha podido quitar la clave de \(target.host) de \(AppPaths.tilde(target.file.path)): \(err)")
                self.pipe.say(L("\u{1b}[38;5;204m[NetDeck] No se ha podido quitar la clave vieja: \(err)\u{1b}[0m"))
                self.sayClosed(generation, code)
                return
            }
            guard generation == self.pipe.current else { return }
            self.acceptedFingerprint = m.fingerprint
            self.pipe.say(L("\u{1b}[38;5;51m[NetDeck] Clave vieja de «\(target.host)» quitada de \(AppPaths.tilde(target.file.path))\u{1b}[0m"))
            self.restart()
        }
    }

    private func exitedWithoutHostKey(generation: Int, code: Int32?) {
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
        // (ssh usa 255 para errores de conexión/autenticación: sólo un rechazo con host atribuible permite acusar
        // una credencial reciente. Un banner que parezca prompt no demuestra que el login haya terminado, así que no
        // confirma nada; pero tras llegar al prompt un corte —«Connection reset by …» en los primeros 150 s— no es un
        // rechazo de la contraseña que acaba de entrar: no se la culpa)
        if code == 255, !loggedIn {
            // (sólo lo último de la pantalla, y sólo si hay intentos recientes: un «Permission denied» de una orden o
            // un corte horas después, en un equipo cuyo prompt no se reconoce, no es de la contraseña)
            let rejected = Askpass.settleAfterExit(session: id, ledger: ledger) {
                Askpass.rejection(in: self.lines(from: max(self.launchRow, self.cursorRow - 12))
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(6))
            }
            for r in rejected {
                pipe.say(L("\r\n\u{1b}[38;5;204m[NetDeck] La contraseña guardada «\(r.account)» no ha valido\u{1b}[0m"))
            }
        } else {
            _ = Askpass.takeAttempts(session: id)
        }
        pipe.say(L("\r\n\u{1b}[38;5;204m[NetDeck] Sesión cerrada\(code.map { L(" (código \($0))") } ?? "")\u{1b}[0m")
                 + L(" · \u{1b}[1mIntro\u{1b}[0m reconectar · \u{1b}[1mEsc\u{1b}[0m cerrar la pestaña\r\n"))
    }

    func apply(theme t: Theme, font: NSFont) {
        theme = t
        view.font = font
        view.nativeBackgroundColor = NSColor(t.background)
        view.nativeForegroundColor = NSColor(t.text)
        view.caretColor = NSColor(t.accent)
        view.selectedTextBackgroundColor = NSColor(t.selection)
        view.installColors(t.ansi.map { SwiftTerm.Color($0) })
    }

    /// Historial y teclado del perfil (el historial sólo si cambia: SwiftTerm lo rehace).
    func apply(scrollback: Int, optionAsMeta: Bool, backspaceSendsCtrlH: Bool) {
        if scrollback != appliedScrollback {
            view.changeScrollback(scrollback)
            appliedScrollback = scrollback
        }
        view.optionAsMetaKey = optionAsMeta
        view.backspaceSendsControlH = backspaceSendsCtrlH
    }

    func highlight(rules: [HighlightRule], palette: [String: RGB], enabled: Bool) {
        pipe.configure(rules: rules, palette: palette, enabled: enabled)
    }

    /// Sólo las órdenes que salen hacia una shell remota arman la detección de equipos; un banner no la arma.
    @ObservationIgnored private var commandInput = MacroRecorder(allowScreenFallback: true, soloConexiones: true)

    func cancelPasswordContext() {
        commandInput = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
        passwords.cancelCommand()
    }

    /// El búfer se ha recolocado (`BufferRows.resync`): se suelta todo lo anclado a filas de antes.
    private func noticeRealignment() {
        guard bufferRows.resyncs != seenResyncs else { return }
        seenResyncs = bufferRows.resyncs
        DebugLog.log("autopass", "pestaña \(tabID): búfer recolocado (fila \(bufferRows.resync))")
        passwords.bufferRealigned()
        typedPassword.forget()
        commandInput.bufferRealigned()
    }
    @ObservationIgnored private var seenResyncs = 0

    private func trackCommandInput(_ bytes: [UInt8]) {
        guard route.transport == .ssh || route.transport == .telnet else { return }
        _ = cursorRow
        noticeRealignment()
        // (diagnóstico sin lo tecleado: sólo que un Intro no se ha mirado y por qué)
        guard loggedIn else {
            if bytes.contains(13) || bytes.contains(10) { DebugLog.log("autopass", "pestaña \(tabID): Intro sin seguir (aún sin su primer prompt)") }
            return
        }
        let skipped = commandInput.skipped
        commandInput.feed(bytes, from: self)
        let commands = commandInput.takeLines()
        for command in commands {
            passwords.beginCommand(command, after: cursorRow)
            DebugLog.log("autopass", "pestaña \(tabID): \(passwords.commandTarget == nil ? "otra orden, contexto cerrado" : "orden de conexión armada")")
        }
        if commands.isEmpty, commandInput.skipped > skipped {
            DebugLog.log("autopass", "pestaña \(tabID): orden descartada (\(commandInput.lastDrop ?? "?"), fila \(cursorRow), revisión \(revision))")
        }
        // (con un prompt desconocido tampoco se conserva el login anterior al enviar otra orden)
        if commands.isEmpty, commandInput.skipped > skipped, !SecretPrompt.asks(cursorLine),
           !PasswordPrompt.isLoginLine(cursorLine) { passwords.cancelCommand() }
    }

    /// Para el registro de depuración: el principio del id de la pestaña.
    private var tabID: Substring { id.uuidString.prefix(8) }

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

    func sendSerialBreak() {
        guard route.transport == .serial, !exited else { return }
        serialPort?.sendBreak()
    }

    private func outputChanged() async {
        if !isVisible { activity = true }
        let line = cursorLine.trimmingCharacters(in: .whitespaces)
        noticeRealignment()
        if !loggedIn {
            if !route.jumps.isEmpty, route.thenCommand == nil, !fellBack, !refusalSeen, ConnectionRoute.forwardingRefused(lines(from: max(0, cursorRow - 6))) {
                refusalSeen = true                 // (se decide al terminar ssh: el texto solo lo podría poner el salto)
            }
            if checksHostKey, hostKeyMismatch?.host == nil, let m = HostKeyMismatch.detect(lines(from: launchRow)) {
                hostKeyMismatch = m
                // (sin «StrictHostKeyChecking» ssh seguiría, sin contraseñas: se corta y se pregunta al terminar)
                if m.host != nil || m.failed || lines(from: launchRow).contains(where: { $0.contains("to avoid man-in-the-middle attacks") }) {
                    if !exited { process?.terminate() }
                }
            }
            if let fp = acceptedFingerprint, let shown = KnownHosts.newHostPrompt(lines(from: launchRow)) {
                acceptedFingerprint = nil
                if shown == fp {
                    DebugLog.log("known_hosts", "«\(title)»: la clave nueva es la aceptada (\(fp)) → yes")
                    sendLine("yes")
                } else {
                    DebugLog.log("known_hosts", "«\(title)»: la clave al reconectar (\(shown)) no es la aceptada (\(fp))")
                    pipe.say(L("\r\n\u{1b}[38;5;204m[NetDeck] ¡Ojo! La huella no es la que aceptaste: contesta tú\u{1b}[0m\r\n"))
                }
            }
            // (con «# @prompt», el suyo; una petición de contraseña/OTP nunca cuenta, la acepte o no la regex)
            if !exited, PromptRule.isPrompt(line, custom: promptRule) {
                loggedIn = true
                state = .connected
                // (el prompt sólo cambia el estado visual: las credenciales iniciales pertenecen a OpenSSH,
                // no al detector de equipos. Sus rechazos se resuelven por cuenta al terminar o al repreguntar)
            }
        }
        if let d = PromptDevice.name(line, previous: device), d != device {
            if homeDevice == nil, loggedIn, route.thenCommand == nil || hopSent { homeDevice = d }
            device = d
            // (lo que hubiera a medias en la línea, o el último Intro, era del equipo de antes)
            commandInput.resetLine()
            if route.thenCommand != nil || d != route.target.host { DebugLog.log("pestaña", "«\(title)» → equipo «\(d)»") }
            if let c = customTitle, renamed.deviceChanged(to: d) {
                DebugLog.log("pestaña", "«\(title)»: prompt de otro equipo («\(d)»), deja el nombre «\(c)»")
            }
        }
        if let e = await passwords.observe(self, gate: gate) {
            DebugLog.log("contraseña", "«\(title)»: \(e)")
            onEvent?(self, e)
        }
        if let c = typedPassword.resolve(lines: { [unowned self] in lines(from: $0) }, cursorLine: cursorLine, row: cursorRow) {
            onTypedPassword?(self, c)
        }
    }

    /// El salto no deja reenviar (-J) y ssh ha terminado con 255: con tu permiso, se abre el salto y se escribe allí el
    /// ssh. Ahí la contraseña del destino pasa por la shell del salto: sólo se sugiere, no se escribe sola.
    /// true = se encarga (no se dice «Sesión cerrada»).
    private func fallBackToHop() -> Bool {
        guard refusalSeen, !fellBack, !loggedIn, route.thenCommand == nil, !route.jumps.isEmpty else { return false }
        fellBack = true
        let given = Askpass.takeGiven(session: id)
        given.forEach(ledger.confirmDirect)         // (el salto sí ha entrado: el fallo es al abrir el canal)
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

    func registerPendingAuthentication(_ ref: CredentialRef, reservation token: UUID) {
        if exited { ledger.release(ref, reservation: token) }
        else { passwords.registerPendingAuthentication(ref, reservation: token) }
    }

    func retainPendingAuthentication(_ ref: CredentialRef, reservation token: UUID) {
        passwords.retainPendingAuthentication(ref, reservation: token,
                                               ended: exited || PromptRule.endsNestedLogin(cursorLine, custom: promptRule))
    }

    func send(bytes: [UInt8]) {
        guard !exited else { return }
        trackCommandInput(bytes)
        process?.send(data: bytes[...])
        serialPort?.write(bytes[...])
    }

    var revision: Int { pipe.counter.value }
    /// Absoluta: sigue creciendo aunque el historial esté lleno (`BufferRows`).
    var cursorRow: Int { let s = snapshot(); return s.base + s.cursor }

    var cursorLine: String {
        let s = snapshot()
        return s.lines.indices.contains(s.cursor) ? s.lines[s.cursor] : ""
    }

    /// Desde una fila absoluta; las ya expulsadas del historial se omiten.
    func lines(from row: Int) -> [String] {
        let s = snapshot()
        let from = bufferRows.first(from: row)
        guard !s.lines.isEmpty, from <= s.base + s.cursor else { return [] }
        return Array(s.lines[max(0, from - s.base)...s.cursor])
    }

    /// Todo el búfer (historial + pantalla) como texto; la pantalla son las últimas `rows` filas.
    private func snapshot() -> (lines: [String], cursor: Int, base: Int) {
        let rev = pipe.counter.value
        if let c = cache, c.rev == rev { return (c.lines, c.cursor, c.base) }
        var lines = String(decoding: view.getBufferAsData(), as: UTF8.self).components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let st = view.terminalStateSnapshot()
        let cursor = max(0, min(lines.count - 1, lines.count - st.dimensions.rows + st.cursor.row))
        // (la pantalla alternativa, sólo si el búfer activo es del tamaño de la pantalla: entonces leerla es barato;
        // sin pruebas en un sentido u otro, se queda la de antes)
        var alt: [String] = []
        if lines.count == st.dimensions.rows {
            alt = String(decoding: view.getBufferAsData(kind: .alt), as: UTF8.self).components(separatedBy: "\n")
            if alt.last == "" { alt.removeLast() }
        }
        alternate = BufferRows.alternateEvidence(active: lines, alternate: alt, screenRows: st.dimensions.rows) ?? alternate
        bufferRows.update(lines, screenRows: st.dimensions.rows, cursor: cursor,
                          layout: [st.dimensions.cols, st.dimensions.rows, alternate ? 1 : 0])
        cache = (rev, lines, cursor, bufferRows.base)
        return (lines, cursor, bufferRows.base)
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        view.clearBlock()
        if exited {
            if data.contains(13) { onReconnect?(self) } else if Array(data) == [27] { onCloseRequest?(self) }
            return
        }
        // (la línea del cursor de antes de mandarlo: después, el equipo ya puede haber contestado)
        // (la línea del cursor de antes de mandarlo, sólo si se va a mirar lo tecleado)
        let typed = onTypedPassword != nil && offerTypedPassword() && !route.isLocal
        let before = typed ? (line: cursorLine, row: cursorRow) : nil
        if onInput?(self, Array(data)) == true {
            // (lo atiende la app: reserva de una automatización, MultiExec o una tecla F de un botón)
            if data.contains(13) { DebugLog.log("autopass", "pestaña \(tabID): Intro atendido por la app (reserva, MultiExec o tecla F)") }
            return
        }
        // (sólo lo que llega al equipo: lo tecleado durante «⏳ Enviando…» no es la contraseña que ha entrado)
        if let b = before { typedPassword.feed(Array(data), cursorLine: b.line, row: b.row, above: linesAbove(3)) }
        trackCommandInput(Array(data))
        process?.send(data: data)
        serialPort?.write(data)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        pipe.setSize(cols: newCols, rows: newRows)
        var size = pipe.getWindowSize()
        _ = process?.updateWindowSize(&size)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) { view.clearBlock() }
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
