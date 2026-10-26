import AppKit
import NetDeckCore
import SwiftUI

/// Ventana principal: barra superior (en la de título), sesiones a la izquierda, pestañas y terminal, barra de estado.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        if model.showSetup {
            SetupView()
        } else {
            main
        }
    }

    private var main: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                TopBar()
                if model.settings.buttonBar == "arriba" { ButtonBarView() }
            }
            .snapshotFrame("barra-superior")
            HStack(spacing: 0) {
                if model.settings.sidebarVisible {
                    Sidebar().frame(width: 268).snapshotFrame("sesiones")
                    NeonLine(vertical: true, color: t.panel)
                }
                VStack(spacing: 0) {
                    MainArea()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.settings.buttonBar == "abajo" { ButtonBarView() }
            StatusBar()
        }
        .background(SwiftUI.Color(t.background))
        .background { if t.isTranslucent { BehindWindowBlur(material: t.blurMaterial) } }
        .tint(SwiftUI.Color(t.accent))
        .themedControls()
        .overlay(alignment: .bottomTrailing) {
            StatusToast().padding(.trailing, 14).padding(.bottom, 34)
                .animation(.easeInOut(duration: 0.3), value: model.toast)
        }
        .overlay { if model.showSettings { SettingsOverlay().themedControls() } }
        .onAppear(perform: snapshotAction)
        .sheet(item: $model.sheet) { sheet in
            Group {
                switch sheet {
                case .connect: ConnectSheet()
                case .paste: PasteSheet()
                case .list: ListSheet()
                case .sessions: SessionEditor()
                case .fill: ButtonFillSheet()
                case .logs: LogSearchSheet()
                case .macros: MacroSheet()
                case .tunnels: TunnelSheet()
                case .workspaces: WorkspaceSheet()
                }
            }
            .environment(model)
            .environment(\.theme, t)
            .tint(SwiftUI.Color(t.accent))
            .themedControls()
        }
    }
}

extension ContentView {
    /// Desarrollo (con NETDECK_SNAPSHOT): «tab:usuario@equipo» abre esa pestaña; «settings» abre Ajustes.
    private func snapshotAction() {
        // (sólo en una captura: si no, lo que abren se guardaría en tus pestañas)
        let env = ProcessInfo.processInfo.environment
        // (sólo en la primera ventana: las que se abren durante la prueba no repiten la acción)
        guard env["NETDECK_SNAPSHOT"] != nil, model.isLaunchWindow, let a = env["NETDECK_SNAPSHOT_ACTION"] else { return }
        if a == "password-selector", env["NETDECK_SAMPLES"] == "1" {
            // (demostración sin procesos, red ni Llavero: el mismo contexto y selector que usa un login real)
            let ref = CredentialRef.named("AD"), ledger = CredentialLedger()
            let passwords = PasswordAutomation(mode: .suggest, store: MemoryCredentialStore([ref: "ejemplo"]), ledger: ledger) { _ in
                [.init(ref: ref, owners: ["tu.usuario"], origin: .defaultCredential)]
            }
            let s = TerminalSession(route: .init(title: "bastion", target: .init(user: "tu.usuario", host: "192.0.2.10")),
                                    passwords: passwords, ledger: ledger)
            model.tabs.append(s)
            model.selection = s.id
            model.applyProfile(to: s)
            passwords.onOfferChange = { [weak model, weak s] offer in
                guard let s else { return }
                model?.passwordOffers[s.id] = offer
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                s.view.feed(byteArray: Array("bastion# ssh tu.usuario@192.0.2.11\r\n".utf8)[...])
                _ = s.pipe.counter.bump(); s.pipe.counter.delivered()
                passwords.beginCommand("ssh tu.usuario@192.0.2.11", after: s.cursorRow)
                s.view.feed(byteArray: Array("tu.usuario@192.0.2.11's password: ".utf8)[...])
                _ = s.pipe.counter.bump(); s.pipe.counter.delivered()
                if let event = await passwords.observe(s, gate: s.gate) { model.notices[s.id] = event }
            }
        }
        if a.hasPrefix("tab:") { model.quickConnect(String(a.dropFirst(4))) }
        if a.hasPrefix("tab:") || a == "terminal" {
            // (y el texto de la pestaña, para comprobar que la salida llega al terminal)
            if let path = ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + AppDelegate.snapshotWait) {
                    let text = model.current.map { $0.lines(from: 0).joined(separator: "\n") } ?? ""
                    try? text.write(toFile: path + ".txt", atomically: true, encoding: .utf8)
                }
            }
        }
        if a.hasPrefix("explorador") {               // «explorador»: dos SFTP (con NETDECK_SFTP_SERVER) en una vista partida
            for (n, h) in [("ficheros-01", "192.0.2.30"), ("copias-02", "198.51.100.40")] {
                model.open(ConnectionRoute(title: n, target: Endpoint(user: "tu.usuario", host: h), transport: .sftp))
            }
            if a == "explorador:vista" { model.makeSplit(.side2) }
            if a == "explorador:md5" {               // la ventana del MD5 de un archivo, comparado (en verde)
                Task { @MainActor in
                    for _ in 0..<40 {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard let b = model.current?.browser, let f = b.entries.first(where: { !$0.isDirectory }) else { continue }
                        b.computeMD5(f)
                        for _ in 0..<40 {
                            try? await Task.sleep(for: .milliseconds(50))
                            if let h = b.md5?.hash { b.md5?.expected = "MD5 (\(f.name)) = \(h)"; break }
                        }
                        return
                    }
                }
            }
        }
        if a.hasPrefix("pestañas:"), let n = Int(a.dropFirst(9)) {   // «pestañas:12»: muchas, cortas, largas y con salto
            let names = ["core-01", "bastion", "pe-madrid-agregacion-02 ⟵ bastion", "olt-01", "sw-acceso-planta-3-rack-B",
                         "fw-01", "core-02 ⟵ bastion", "rr-01"]
            for i in 0..<max(0, min(n, 40)) {
                model.open(ConnectionRoute(title: names[i % names.count] + (i < names.count ? "" : "-\(i)"),
                                           target: Endpoint(user: "tu.usuario", host: "192.0.2.\(i + 1)")))
            }
            // (NETDECK_SNAPSHOT_DRAGS=/ruta.txt: arrastres y clics de prueba en la barra; ver `SnapshotDrags`)
            if SnapshotDrags.enabled, let path = env["NETDECK_SNAPSHOT_DRAGS"] {
                Task { @MainActor in await SnapshotDrags.run(model, report: path) }
            }
        }
        if a == "terminal" {                         // «terminal»: una local con la salida de ejemplo ($NETDECK_HOME/salida.txt), resaltada
            let s = model.open(ConnectionRoute.local(shell: "/bin/sh"))   // (sh: sin el rc de zsh, que puede limpiar la pantalla)
            let sample = (try? Data(contentsOf: AppPaths.home.appendingPathComponent("salida.txt"))) ?? Data()
            let path = env["NETDECK_SNAPSHOT"]
            Task { @MainActor in                         // (cuando la shell ya ha arrancado: al arrancar se limpia el terminal)
                for _ in 0..<40 where s.revision == 0 { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .milliseconds(300))
                s.pipe.queue.async {                    // (como `receive`; y lo que sale del resaltado, para comprobarlo)
                    let out = s.pipe.highlighter.process(Array(sample)[...])
                    s.pipe.view?.feed(byteArray: Array("\u{1b}[2J\u{1b}[H".utf8)[...] + out[...])
                    if s.pipe.counter.bump() { s.pipe.onOutput() }
                    if let path { try? Data(out).write(to: URL(fileURLWithPath: path + ".resaltado.txt")) }
                }
                // (NETDECK_SNAPSHOT_BLOCK=«f1,c1,f2,c2»: arrastre normal por la 1.ª fila (lo selecciona SwiftTerm, en
                // «.linea.txt») y ⌥ + arrastre por el rectángulo («.bloque.txt»), por las mismas celdas: si la celda que
                // calcula la app no fuera la de SwiftTerm, no coincidirían. El rectángulo se queda en la captura.)
                guard let spec = env["NETDECK_SNAPSHOT_BLOCK"], let path else { return }
                let n = spec.split(separator: ",").compactMap { Int($0) }
                guard n.count == 4 else { return }
                try? await Task.sleep(for: .milliseconds(800))
                let v = s.view
                func drag(_ a: (Int, Int), _ b: (Int, Int), option: Bool) {
                    let flags: NSEvent.ModifierFlags = option ? .option : []
                    func ev(_ type: NSEvent.EventType, _ c: (Int, Int)) -> NSEvent? {
                        NSEvent.mouseEvent(with: type, location: v.convert(v.point(ofCell: c.0, c.1), to: nil), modifierFlags: flags,
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: v.window?.windowNumber ?? 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                    }
                    if let e = ev(.leftMouseDown, a) { v.mouseDown(with: e) }
                    if let e = ev(.leftMouseDragged, b) { v.mouseDragged(with: e) }
                    if let e = ev(.leftMouseUp, b) { v.mouseUp(with: e) }
                }
                drag((n[0], n[1]), (n[0], n[3]), option: false)
                try? (v.getSelection() ?? "").write(toFile: path + ".linea.txt", atomically: true, encoding: .utf8)
                drag((n[0], n[1]), (n[2], n[3]), option: true)
                try? (v.blockText ?? "").write(toFile: path + ".bloque.txt", atomically: true, encoding: .utf8)
            }
        }
        // (NETDECK_SNAPSHOT_MD5: el MD5 del archivo más pequeño del explorador, entrando en la primera carpeta si no hay
        // ninguno; NETDECK_SNAPSHOT_DOWNLOAD=carpeta: lo baja ahí)
        if env["NETDECK_SNAPSHOT_MD5"] != nil || env["NETDECK_SNAPSHOT_DOWNLOAD"] != nil {
            Task { @MainActor in
                var entered = 0
                for _ in 0..<300 {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let b = model.current?.browser, !b.entries.isEmpty else { continue }
                    let files = b.entries.filter { !$0.isDirectory }
                    if files.isEmpty, entered < 3, let d = b.entries.first(where: \.isDirectory) {
                        entered += 1
                        b.open(d.path)
                        try? await Task.sleep(for: .milliseconds(800))
                        continue
                    }
                    guard let f = files.min(by: { ($0.size ?? .max) < ($1.size ?? .max) }) else { continue }
                    if env["NETDECK_SNAPSHOT_MD5"] != nil { b.computeMD5(f) }
                    if let d = env["NETDECK_SNAPSHOT_DOWNLOAD"], let fs = b.fs {
                        model.transfers.download([f], from: fs, to: URL(fileURLWithPath: d, isDirectory: true))
                    }
                    return
                }
            }
        }
        if a == "panel-sftp" {                       // «panel-sftp»: terminal con la salida de ejemplo y el explorador lateral (NETDECK_SFTP_SERVER)
            let s = model.open(ConnectionRoute.local(shell: "/bin/sh"))
            let r = ConnectionRoute(title: "core-01", target: Endpoint(user: "tu.usuario", host: "192.0.2.10"), transport: .sftp)
            let p = SFTPSidePanel(key: "captura", layout: SFTPPanelLayout(visible: true, width: 470), model: model, route: r)
            s.sidePanel = p
            p.show(in: s)
            let sample = (try? Data(contentsOf: AppPaths.home.appendingPathComponent("salida.txt"))) ?? Data()
            Task { @MainActor in
                for _ in 0..<40 where s.revision == 0 { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .milliseconds(300))
                s.pipe.queue.async {
                    let out = s.pipe.highlighter.process(Array(sample)[...])
                    s.pipe.view?.feed(byteArray: Array("\u{1b}[2J\u{1b}[H".utf8)[...] + out[...])
                    if s.pipe.counter.bump() { s.pipe.onOutput() }
                }
            }
        }
        if a == "espacios" || a == "espacios:verificar" {
            let first = model.open(ConnectionRoute.local(shell: "/bin/sh"))
            let second = model.open(ConnectionRoute.local(shell: "/bin/sh"))
            model.makeSplit(.side2)
            model.setSplitWeights([0.3, 0.7], key: "root")
            model.selection = first.id
            if a == "espacios:verificar", let path = env["NETDECK_SNAPSHOT"] {
                Task { @MainActor in
                    let w = model.captureWorkspace(name: "Guardia")
                    var errors: [String] = []
                    do {
                        try WorkspaceLibrary(workspaces: [w]).save()
                        for s in model.tabs { model.close(s) }
                        let lib = try WorkspaceLibrary.load()
                        model.multiExecOn = true
                        if !(await model.restoreWorkspace(lib.workspaces[0], replacing: true)) { errors.append("restauración") }
                        if model.tabs.count != 2 || model.tabs.map(\.route.localShell) != ["/bin/sh", "/bin/sh"] { errors.append("pestañas") }
                        if model.selection != model.tabs.first?.id { errors.append("selección") }
                        if model.split?.fractions["root"] != [0.3, 0.7] || !model.showSplit { errors.append("disposición") }
                        if model.multiExecOn { errors.append("MultiExec") }
                        // (las capturas no enseñan este Mac: ni tu usuario ni su nombre en el prompt de la local)
                        for _ in 0..<30 where model.tabs.contains(where: { $0.revision == 0 }) { try? await Task.sleep(for: .milliseconds(100)) }
                        let text = model.tabs.flatMap { $0.lines(from: 0) }.joined(separator: "\n").lowercased()
                        let mine = [NSUserName(), Host.current().localizedName ?? "", ProcessInfo.processInfo.hostName]
                            .map { $0.lowercased().components(separatedBy: ".").first ?? "" }.filter { $0.count >= 3 }
                        if mine.contains(where: text.contains) { errors.append("privacidad: el prompt enseña este Mac") }
                    } catch { errors.append(error.localizedDescription) }
                    try? (errors.isEmpty ? "OK espacios: guardar, cerrar, cargar y restaurar" : "ERROR " + errors.joined(separator: ", "))
                        .write(toFile: path + ".espacios.txt", atomically: true, encoding: .utf8)
                    model.sheet = .workspaces
                }
            } else {
                _ = second
                model.sheet = .workspaces
            }
        }
        if a == "macros" {                           // «macros»: el editor con una recién grabada (sin guardar)
            model.macroDraft = Macro(name: "Revisar interfaces", confirm: true, steps: Macro.recorded(
                ["terminal length 0", "show ip interface brief", "show interfaces GigabitEthernet0/0/1"]) + [.text(#"core-01#"#, timeout: 30), .pause(1)])
            model.sheet = .macros
        }
        if a.hasPrefix("tuneles") {                  // «tuneles»: el gestor (los de $NETDECK_HOME); «tuneles:iniciar», todos en marcha
            if a == "tuneles:iniciar" { model.tunnels.tunnels.forEach(model.startTunnel) }
            model.sheet = .tunnels
        }
        if a == "sesion-nueva" { model.editSessions(.new(group: nil, kind: .telnet)) }
        if a.hasPrefix("settings") { model.openSettings(a.split(separator: ":").dropFirst().first.map(String.init) ?? "contraseñas") }
        if a.hasPrefix("split") {                    // «split»: 3 pestañas en 1 + 2 con MultiExec
            for h in ["admin@192.0.2.11", "admin@192.0.2.12", "admin@192.0.2.21"] { model.quickConnect(h) }
            model.makeSplit(.onePlusTwo)
            model.multiExecOn = true
            if let s = model.tabs.last { model.toggleExcluded(s) }
        }
    }
}

// MARK: - barra superior

/// Una sola fila en la barra de título: pestañas y, a la derecha, los accesos directos (pegado, dividir, Llavero,
/// MultiExec, cortar, sesiones, ajustes). El menú de la app solo guarda las órdenes con atajo.
struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Stored private var drag = RowDrag<TerminalSession.ID>()
    /// Anchos medidos: los botones de los lados (fijos) y la «VISTA ×n».
    @Stored private var leftWidth: CGFloat = 0
    @Stored private var rightWidth: CGFloat = 0
    @Stored private var splitWidth: CGFloat = 0

    /// Ancho de cada pestaña: entre `tabMin` y `tabMax`, el que toque para que quepan todas; si ni al mínimo caben,
    /// la tira se desplaza (y la activa siempre se ve).
    static let tabMax: CGFloat = 200
    static let tabMin: CGFloat = 96
    static let tabGap: CGFloat = 4
    private static let spacing: CGFloat = 6
    private static let spacerMin: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            row(width: geometry.size.width)
        }
        .frame(height: 38)
    }

    private func row(width: CGFloat) -> some View {
        // El ancho viene del contenedor, no de la fila ya encogida (evita realimentar el mínimo de 96).
        let rowWidth = width - (model.fullScreen ? 10 : 80) - 10
        // (lo que dejan los botones: la fila menos los dos grupos fijos, los huecos entre ellos y el Spacer mínimo)
        let room = max(Self.tabMin, rowWidth - leftWidth - rightWidth - 3 * Self.spacing - Self.spacerMin)
        let n = CGFloat(model.tabs.count)
        let split = model.split == nil ? 0 : splitWidth + Self.tabGap
        let each = n == 0 ? Self.tabMax
            : min(Self.tabMax, max(Self.tabMin, ((room - split - Self.tabGap * (n - 1)) / n).rounded(.down)))
        let content = split + n * each + max(0, n - 1) * Self.tabGap
        return HStack(spacing: Self.spacing) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Self.tabGap) {
                        if let sp = model.split {
                            SplitChip(split: sp)
                                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { splitWidth = $0 }
                        }
                        // arrastrar una pestaña la cambia de sitio (sólo el orden: la terminal y su proceso siguen igual)
                        ForEach(model.tabs) { s in
                            // (y soltada fuera de la ventana: a otra ventana de la app o a una nueva en esa pantalla)
                            TabChip(session: s, width: each, dragSpace: drag.space) { drag.blocked[s.id] = $0 }
                                .id(s.id)
                                .reorderable(s.id, in: drag, order: { model.tabs.map(\.id) },
                                             move: { model.moveTab($0, to: $1) }, end: {}, tap: { model.show(s) },
                                             tearOff: TearOff(title: s.tabTitle, theme: t) { model.dropTab(s, at: $0, grab: $1) })
                        }
                    }
                    .padding(.vertical, 4)
                    .coordinateSpace(.named(drag.space))
                }
                .onChange(of: model.selection) { reveal(model.selection, proxy) }
                .onChange(of: model.tabs.count) { reveal(model.selection, proxy) }
                .onChange(of: room) { reveal(model.selection, proxy) }
                .onAppear { reveal(model.selection, proxy) }
            }
            .frame(width: min(content, room))
            .keepsWindowStill(model, "pestañas")
            Spacer(minLength: Self.spacerMin)
                .frame(maxWidth: .infinity)
                .snapshotFrame("hueco")
            HStack(spacing: Self.spacing) {
                NewButton()
                    .help(L("Conectar, terminal local, sesión nueva o una favorita"))
                IconButton(icon: "apple.terminal") { model.openLocal() }
                    .help(L("Nueva terminal local: tu shell en este Mac (⌘T)"))
            }
            .fixedSize()
            .layoutPriority(1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { leftWidth = $0 }
            .snapshotFrame("crear")
            HStack(spacing: Self.spacing) {
                IconButton(icon: "doc.on.clipboard.fill") { model.sheet = .paste }
                    .help(L("Pegado seguro: revisa líneas peligrosas antes de enviarlas (⇧⌘V)"))
                MacroMenu()
                    .help(L("Macros: grabar, reproducir (en la pestaña o en MultiExec) y editar"))
                IconButton(icon: "point.3.connected.trianglepath.dotted", active: model.tunnelRunner.activeCount > 0,
                           badge: model.tunnelRunner.activeCount > 0 ? "\(model.tunnelRunner.activeCount)" : nil) { model.present(.tunnels) }
                    .help(L("Túneles SSH: locales, remotos y SOCKS; iniciar, parar y su estado"))
                IconMenu(icon: "rectangle.split.3x1.fill", active: model.split != nil) {
                    ForEach(Split.Layout.allCases) { l in Button(l.title) { model.makeSplit(l) } }
                    MenuDivider()
                    Button(L("Volver a pestañas sueltas")) { model.unsplit() }.disabled(model.split == nil)
                }
                .help(L("Dividir la pantalla"))
                IconMenu(icon: "key.fill") {
                    if let s = model.current {
                        MenuHeader(title: L("Escribir en «\(s.title)»"))
                        ForEach(model.keychainAccounts, id: \.self) { ref in
                            Button { model.typePassword(ref, in: s) } label: { Label(ref.account, systemImage: "key") }
                        }
                        ThemedSubmenu(title: L("Escribir sin esperar a que la pida")) {
                            ForEach(model.keychainAccounts, id: \.self) { ref in
                                ThemedSubmenu(title: ref.account) {
                                    Button(L("Sin Intro")) { model.typePasswordAnyway(ref, in: s, pressReturn: false) }
                                    Button(L("Con Intro")) { model.typePasswordAnyway(ref, in: s, pressReturn: true) }
                                }
                            }
                        }
                        MenuDivider()
                    }
                    Button(L("Contraseñas y Llavero…")) { model.openSettings("contraseñas") }
                }
                .help(L("Escribir una contraseña del Llavero en la pestaña actual"))
                IconButton(icon: "square.stack.3d.forward.dottedline.fill", tint: t.warning, active: model.multiExecOn,
                           badge: model.multiExecOn ? "\(model.multiExecTargets.count)" : nil) { model.multiExecOn.toggle() }
                    .help(L("MultiExec: lo que escribes va a la vez a los paneles (⇧⌘M). Clic derecho en un panel → excluirlo"))
                IconButton(icon: "stop.circle.fill", tint: t.bad) { model.core.abortEverywhere() }
                    .help(L("Corta cualquier secuencia automática (Esc o Ctrl+C en el terminal, ⌘.)"))
                IconButton(icon: "sidebar.right", active: model.current?.sidePanel?.visible == true) { model.current.map(model.toggleSidePanel) }
                    .help(L("Explorador SFTP al lado del terminal ssh: mismo equipo, usuario y saltos (⇧⌘B)"))
                    .disabled(!(model.current.map { SFTPPanel.offers($0.route) } ?? false) || model.showSplit)
                IconButton(icon: "sidebar.left", active: model.settings.sidebarVisible) { model.settings.sidebarVisible.toggle() }
                    .help(L("Mostrar/ocultar sesiones (⌃⌘S)"))
                IconButton(icon: "gearshape.fill") { model.openSettings() }
                    .help(L("Ajustes (⌘,)"))
            }
            // (los botones de la derecha, siempre enteros y dentro de la ventana: las pestañas se encogen antes)
            .fixedSize()
            .layoutPriority(1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rightWidth = $0 }
            .snapshotFrame("controles")
        }
        .frame(width: max(0, rowWidth), alignment: .leading)
        .padding(.leading, model.fullScreen ? 10 : 80)
        .padding(.trailing, 10)
        .frame(height: 38)
        .background(SwiftUI.Color(t.bar)
            .gesture(WindowDragGesture())
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.toggleFill() }))
        .overlay(alignment: .bottom) { Rectangle().fill(SwiftUI.Color(t.tab)).frame(height: 2) }
    }

    /// Que la pestaña activa se vea (lo justo: si ya se ve, la tira no se mueve).
    private func reveal(_ id: TerminalSession.ID?, _ proxy: ScrollViewProxy) {
        guard let id else { return }
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) } }
    }
}

/// El «+» de la barra: abre `NewMenu` en un panel con la temática de la app (el `Menu` nativo no se deja pintar).
struct NewButton: View {
    @Environment(\.theme) private var t
    @Stored private var open = false

    var body: some View {
        IconButton(icon: "plus", active: open) { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                NewMenu { open = false }
                    .presentationBackground(SwiftUI.Color(t.bar.opaque))
            }
            .onAppear {                                       // (capturas: NETDECK_SNAPSHOT_ACTION=nuevo)
                if ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT_ACTION"] == "nuevo" { open = true }
            }
    }
}

/// El menú «+»: conectar, terminal local, sesiones nuevas, listas, las ★ favoritas / la de inicio y los grupos (abre
/// todas las de una carpeta de un clic). Se cierra al elegir o con Esc (lo hace el propio panel).
struct NewMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let close: () -> Void

    var body: some View {
        let favs = model.favorites.compactMap(model.sessions.profile(named:))
        let start = model.startupProfile.flatMap { p in favs.contains { $0.name == p.name } ? nil : p }
        let folders = GroupTree.folders(model.sessions.groups.map { (name: $0.name, items: $0.profiles) })
        VStack(alignment: .leading, spacing: 1) {
            item(L("Conectar / Salto…"), icon: "bolt.horizontal.fill", key: "⌘K") { model.sheet = .connect }
            item(L("Terminal local"), icon: "apple.terminal", key: "⌘T") { model.openLocal() }
            divider
            item(L("Nueva sesión…"), icon: "plus.rectangle.on.rectangle") { model.editSessions(.new(group: nil)) }
            item(L("Nueva sesión SFTP…"), icon: "folder.fill") { model.editSessions(.new(group: nil, kind: .sftp)) }
            item(L("Nueva sesión serie…"), icon: "cable.connector.horizontal") {
                model.editSessions(.new(group: nil, kind: .serial))
            }
            item(L("Listas de equipos…"), icon: "list.bullet.rectangle", key: "⇧⌘L") { model.present(.list) }
            if !favs.isEmpty || start != nil {
                divider
                heading(L("Favoritas"))
                if let p = start {
                    item(p.name, icon: "power", key: L("al arrancar"), tint: t.warning) { model.open(p) }
                }
                ForEach(favs, id: \.name) { p in
                    item(p.name, icon: p.name == model.startupProfile?.name ? "power" : "star.fill",
                         key: p.user.map { "\($0)@\(p.endpoint.host)" } ?? p.endpoint.host, tint: t.warning) { model.open(p) }
                }
            }
            if !folders.isEmpty {
                divider
                heading(L("Grupos"))
                // (muchos: se desplazan dentro del menú, que no crece más de la cuenta)
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(folders, id: \.path) { f in
                            item(L(nombre: f.name), icon: "folder.fill", key: "\(f.count)", indent: f.depth) {
                                Task { await model.openGroup(f.path) }
                            }
                            .help(L("Abrir las \(f.count) (si son varias, en la vista dividida)"))
                        }
                    }
                }
                .frame(height: min(CGFloat(folders.count), 9.5) * 27)
            }
        }
        .padding(6)
        .frame(minWidth: 250)
        .font(t.ui(12))
        .background(SwiftUI.Color(t.bar.opaque))
        .overlay(alignment: .top) { Rectangle().fill(SwiftUI.Color(t.accent)).frame(height: 2).opacity(t.neon ? 0.8 : 0) }
    }

    private var divider: some View {
        Rectangle().fill(SwiftUI.Color(t.panel)).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 6)
    }

    private func heading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(t.ui(9.5, .bold)).tracking(t.tracking)
            .foregroundStyle(SwiftUI.Color(t.dim))
            .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 3)
    }

    private func item(_ title: String, icon: String, key: String? = nil, tint: RGB? = nil, indent: Int = 0,
                      action: @escaping () -> Void) -> some View {
        NewMenuItem(title: title, icon: icon, key: key, tint: tint, indent: indent) {
            close()
            action()
        }
    }
}

private struct NewMenuItem: View {
    @Environment(\.theme) private var t
    let title: String
    let icon: String
    let key: String?
    let tint: RGB?
    /// Subcarpeta (en «Grupos»): un poco a la derecha de su carpeta.
    var indent = 0
    let action: () -> Void
    @Stored private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color(hover ? t.accent : (tint ?? t.accent2)))
                    .frame(width: 16)
                Text(title).foregroundStyle(SwiftUI.Color(hover ? t.accent : t.text)).lineLimit(1)
                Spacer(minLength: 16)
                if let key { Text(key).font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim)).lineLimit(1) }
            }
            .padding(.horizontal, 10)
            .padding(.leading, CGFloat(indent) * 14)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: t.corner ?? 4)
                .fill(SwiftUI.Color(t.accent).opacity(hover ? 0.14 : 0)))
            .overlay(alignment: .leading) {
                Rectangle().fill(SwiftUI.Color(t.accent)).frame(width: 2).opacity(hover && t.neon ? 1 : 0)
                    .shadow(color: SwiftUI.Color(t.accent), radius: t.glow(3))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct Brand: View {
    @Environment(\.theme) private var t

    var body: some View {
        if t.neon { neon } else {
            HStack(spacing: 7) {
                Image(systemName: t.style == .fluent ? "terminal" : "apple.terminal.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(SwiftUI.Color(t.accent))
                Text(L("NetDeck")).font(t.ui(15, .bold)).foregroundStyle(SwiftUI.Color(t.text))
                Text(L("Terminal")).font(t.ui(13)).foregroundStyle(SwiftUI.Color(t.dim))
            }
            .allowsHitTesting(false)
        }
    }

    private var neon: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("▚").font(.system(size: 15, weight: .black)).foregroundStyle(SwiftUI.Color(t.accent2))
            Text(L("NETDECK"))
                .font(t.ui(16, .heavy)).tracking(3)
                .foregroundStyle(SwiftUI.Color(t.accent))
                .shadow(color: SwiftUI.Color(t.accent).opacity(0.8), radius: t.glow(6))
            Text("//").font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            Text(L("TERMINAL")).font(t.ui(10, .bold)).tracking(2.5).foregroundStyle(SwiftUI.Color(t.accent2))
        }
        .allowsHitTesting(false)
    }
}

struct IconButton: View {
    @Environment(\.theme) private var t
    let icon: String
    var tint: RGB?
    var active = false
    var badge: String?
    var action: () -> Void
    @Stored private var hover = false

    var body: some View {
        let color = tint ?? t.accent
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                if let badge { Text(badge).font(t.ui(11, .bold)) }
            }
            .foregroundStyle(SwiftUI.Color(active ? t.background : (hover ? color : (tint ?? t.text))))
            .padding(.horizontal, 7)
            .frame(minWidth: 30, minHeight: 26)
            .background(RoundedRectangle(cornerRadius: t.corner ?? 6)
                .fill(SwiftUI.Color(active ? color : t.panel).opacity(active ? 1 : (hover ? 0.9 : 0.4))))
            .shadow(color: SwiftUI.Color(color).opacity(active ? 0.6 : 0), radius: t.glow(6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Como `IconButton`, pero abre un menú (con la temática).
struct IconMenu<Content: View>: View {
    @Environment(\.theme) private var t
    let icon: String
    var active = false
    @ViewBuilder var content: () -> Content
    @Stored private var hover = false

    var body: some View {
        ThemedMenu(content: content) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SwiftUI.Color(active ? t.background : (hover ? t.accent : t.text)))
                .padding(.horizontal, 7)
                .frame(minWidth: 30, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: t.corner ?? 6)
                    .fill(SwiftUI.Color(active ? t.accent : t.panel).opacity(active ? 1 : (hover ? 0.9 : 0.4))))
                .contentShape(Rectangle())
        }
        .fixedSize()
        .onHover { hover = $0 }
    }
}

// MARK: - pestañas

struct TabChip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let session: TerminalSession
    /// El que le toca en la barra (todas igual de anchas); el título se corta por el centro si no cabe.
    var width: CGFloat = TopBar.tabMax
    /// El espacio de coordenadas de la fila y a quién decirle dónde está la ✕ (ahí no empieza el arrastre).
    var dragSpace: AnyHashable = 0
    var onCloseFrame: (CGRect?) -> Void = { _ in }
    @Stored private var hover = false

    static let closeSize: CGFloat = 24

    private var selected: Bool {
        model.selection == session.id && (!model.showSplit || model.split?.panes.contains(session.id) == true)
    }
    private var showsClose: Bool { selected || hover }

    var body: some View {
        let inSplit = model.split?.panes.contains(session.id) == true
        let selected = selected
        let notice = model.notices[session.id] != nil
        HStack(spacing: 7) {
            Circle()
                .fill(SwiftUI.Color(dotColor(notice)))
                .frame(width: 7, height: 7)
                .shadow(color: SwiftUI.Color(dotColor(notice)).opacity(0.8), radius: t.glow(3))
            if inSplit { Image(systemName: "square.split.2x1").font(.system(size: 9)) }
            // (sólo el destino; el camino entero, en la ayuda)
            Text(session.tabTitle).font(t.ui(12, .semibold)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if session.activity { Text("•").font(t.ui(13, .black)).foregroundStyle(SwiftUI.Color(t.warning)) }
            if notice { Image(systemName: "key.fill").font(.system(size: 10)).foregroundStyle(SwiftUI.Color(t.warning)) }
            // (la ✕ sólo ocupa sitio en la activa o al pasar por encima: en las estrechas, el título se lleva el hueco.
            // Se pulsa en 24×24 alrededor del icono, que queda donde estaba: el margen de la derecha se come lo de más)
            if showsClose {
                Button { model.close(session) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: Self.closeSize, height: Self.closeSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TabCloseStyle(color: selected ? t.onTab : t.accent2, corner: t.neon ? 3 : 5))
                .help(L("Cerrar la pestaña"))
                .accessibilityLabel(L("Cerrar «\(session.tabTitle)»"))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(dragSpace)) } action: { onCloseFrame($0) }
                .onDisappear { onCloseFrame(nil) }
                .snapshotFrame("x:\(session.id)")
            }
        }
        .foregroundStyle(SwiftUI.Color(selected ? t.onTab : t.accent2))
        .padding(.leading, width < 130 ? 9 : 12)
        .padding(.trailing, max(0, (width < 130 ? 11 : 16) - (showsClose ? (Self.closeSize - 9) / 2 : 0)))
        .frame(width: width, height: 29)
        .background(ChamferShape(radius: t.corner).fill(SwiftUI.Color(selected ? t.tab : t.panel).opacity(selected ? 1 : (hover ? 0.95 : 0.6))))
        .shadow(color: SwiftUI.Color(t.tab).opacity(selected ? 0.6 : 0), radius: t.glow(8))
        .contentShape(Rectangle())
        .snapshotFrame("tab:\(session.id)")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.tabFrames[session.id] = $0 }
        .onTapGesture { model.show(session) }
        .onHover { hover = $0 }
        .help(session.pathDescription)
        .themedContextMenu { SessionTabMenu(session: session) }
    }

    private func dotColor(_ notice: Bool) -> RGB { session.statusColor(t, notice: notice) }
}

/// La ✕ de una pestaña: fondo redondeado al pasar el ratón y más marcado al pulsar, con el color de la pestaña.
private struct TabCloseStyle: ButtonStyle {
    let color: RGB
    let corner: CGFloat
    @Stored private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: corner)
                .fill(SwiftUI.Color(color).opacity(configuration.isPressed ? 0.32 : (hover ? 0.16 : 0))))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hover = $0 }
    }
}

/// Clic derecho en una pestaña o en la cabecera de un panel.
struct SessionTabMenu: View {
    @Environment(AppModel.self) private var model
    let session: TerminalSession

    var body: some View {
        Button(L("Reconectar")) { model.reconnect(session) }
        Button(L("Clonar (otra pestaña igual)")) { model.duplicate(session) }
        Button(L("Renombrar la pestaña…")) {
            Task {
                guard let n = await SessionEditor.ask(L("Nombre de la pestaña (se queda hasta que entres en otro equipo)"),
                                                      value: session.tabTitle) else { return }
                session.rename(n)
            }
        }
        if session.customTitle != nil {
            Button(L("Volver al nombre del equipo")) { session.rename(nil) }
        }
        MenuDivider()
        // (a otra ventana sin cortar la conexión: también arrastrándola fuera de ésta)
        if model.tabs.count > 1 {
            Button(L("Mover a una ventana nueva")) { model.moveTabToNewWindow(session) }
        }
        let others = model.core.attachedWindows.enumerated().filter { $0.element !== model }
        if !others.isEmpty {
            ThemedSubmenu(title: L("Mover a la ventana")) {
                ForEach(others, id: \.offset) { i, w in
                    Button(L("Ventana \(String(i + 1)): \(w.current?.tabTitle ?? L("portada")) (\(String(w.tabs.count)))")) {
                        model.moveTab(session, to: w)
                    }
                }
            }
        }
        MenuDivider()
        if model.split?.panes.contains(session.id) == true {
            Button(L("Quitar de la vista dividida")) { model.removeFromSplit(session) }
        } else {
            Button(L("Añadir a la vista dividida")) { model.addToSplit(session) }
        }
        if model.multiExecOn || model.split != nil {
            Button(model.excluded.contains(session.id) ? L("Incluir en MultiExec") : L("Excluir de MultiExec")) {
                model.toggleExcluded(session)
            }
        }
        MenuDivider()
        Button(L("Buscar… (⌘F)")) { session.view.showFind() }
        Button(session.logFile == nil ? L("● Grabar registro") : L("■ Parar el registro")) { model.toggleLog(session) }
        if let f = session.logFile {
            Button(L("Abrir el registro")) { NSWorkspace.shared.open(f) }
        }
        MenuDivider()
        if session.browser != nil, session.route.transport == .sftp {
            Button(session.showConsole ? L("Vista gráfica") : L("Consola sftp")) { model.setConsole(!session.showConsole, in: session) }
        }
        if SFTPPanel.offers(session.route) {
            Button(session.sidePanel?.visible == true ? L("Ocultar el explorador SFTP") : L("Explorador SFTP al lado (⇧⌘B)")) {
                model.show(session)
                model.toggleSidePanel(session)
            }
        }
        Button(role: .destructive) { model.close(session) } label: { Text(L("Cerrar")) }
    }
}

/// ● REC en una esquina mientras se graba la sesión (como NetDeck). Clic: abrir, mostrar en Finder o parar.
struct RecBadge: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let session: TerminalSession
    var compact = false

    var body: some View {
        if let f = session.logFile {
            ThemedMenu {
                Button(L("Abrir el registro")) { NSWorkspace.shared.open(f) }
                Button(L("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([f]) }
                MenuDivider()
                Button(L("Parar el registro")) { model.toggleLog(session) }
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let on = Int(ctx.date.timeIntervalSince1970) % 2 == 0
                    HStack(spacing: 5) {
                        Circle().fill(SwiftUI.Color(t.bad)).frame(width: 8, height: 8).opacity(on ? 1 : 0.35)
                            .shadow(color: SwiftUI.Color(t.bad), radius: t.glow(4))
                        if !compact { Text(L("REC")).font(t.ui(10, .heavy)).tracking(1.5).foregroundStyle(SwiftUI.Color(t.bad)) }
                    }
                    .padding(.horizontal, compact ? 4 : 8).padding(.vertical, 3)
                    .background(Capsule().fill(SwiftUI.Color(t.background.opaque).opacity(0.85)))
                    .overlay(Capsule().strokeBorder(SwiftUI.Color(t.bad).opacity(0.6)))
                }
            }
            .fixedSize()
            .help(L("Grabando en \(AppPaths.tilde(f.path))"))
        }
    }
}

/// «⊞ Vista»: la pantalla dividida (las pestañas siguen arriba, cada una por su cuenta).
struct SplitChip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let split: Split

    var body: some View {
        let on = model.showSplit
        HStack(spacing: 6) {
            Image(systemName: split.layout.icon).font(.system(size: 11, weight: .bold))
            Text(L("VISTA ×\(split.panes.count)")).font(t.ui(11, .bold)).tracking(1)
        }
        .foregroundStyle(SwiftUI.Color(on ? t.background : t.accent))
        .padding(.horizontal, 11)
        .frame(height: 29)
        .background(ChamferShape(radius: t.corner).fill(SwiftUI.Color(on ? t.accent : t.panel).opacity(on ? 1 : 0.7)))
        .shadow(color: SwiftUI.Color(t.accent).opacity(on ? 0.6 : 0), radius: t.glow(8))
        .contentShape(Rectangle())
        .onTapGesture {
            model.showSplit = true
            if let f = split.panes.first, !split.panes.contains(model.selection ?? UUID()) { model.selection = f }
        }
        .themedContextMenu {
            Button(L("Volver a pestañas sueltas")) { model.unsplit() }
        }
        .help(L("Pantalla dividida · clic derecho: volver a pestañas sueltas"))
    }
}


// MARK: - terminal

struct MainArea: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        if model.showSplit, let sp = model.split {
            SplitArea(split: sp)
        } else if let s = model.current {
            VStack(spacing: 0) {
                SessionContent(session: s, focused: true, inset: 8, sidePanel: true)
                    .id(s.id)
                    .overlay(alignment: .topLeading) {
                        // (con el explorador lateral a la vista, el ● REC va a la izquierda: a la derecha estaría encima de él)
                        if s.sidePanel?.visible == true { RecBadge(session: s, compact: true).padding(.top, 8).padding(.leading, 12) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if (s.browser == nil || s.showConsole) && s.sidePanel?.visible != true {
                            RecBadge(session: s).padding(.top, 8).padding(.trailing, 18)
                        }
                    }
            }
            .overlay(alignment: .topTrailing) {
                if let e = model.notices[s.id] { PasswordNotice(session: s, event: e).padding(12) }
            }
            .background(SwiftUI.Color(t.layer))
        } else {
            Welcome()
        }
    }
}

/// Lo de dentro de una pestaña: la terminal o, en SFTP/FTP, el explorador (o su consola, con la barra para volver).
/// `sidePanel` (la pestaña sola, no en la vista dividida): el explorador SFTP a la derecha del terminal ssh, si está a la vista.
struct SessionContent: View {
    let session: TerminalSession
    var focused = false
    var inset: CGFloat = 8
    var sidePanel = false

    var body: some View {
        if let b = session.browser, !session.showConsole {
            RemoteBrowserView(session: session, browser: b)
        } else if sidePanel {
            GeometryReader { g in
                HStack(spacing: 0) {
                    console
                    if let p = session.sidePanel, p.visible {
                        SFTPSidePanelView(session: session, panel: p, available: g.size.width)
                    }
                }
            }
        } else {
            console
        }
    }

    private var console: some View {
        VStack(spacing: 0) {
            if session.browser != nil { RemoteConsoleBar(session: session) }
            TerminalHost(session: session, focused: focused)
                .padding(.leading, inset)
                .padding(.top, inset * 0.75)
        }
    }
}

extension TerminalSession {
    /// El punto de la pestaña: verde conectada, ámbar conectando, rojo cerrada (con explorador, el de su conexión).
    func statusColor(_ t: Theme, notice: Bool = false) -> RGB {
        if let b = browser, !showConsole {
            switch b.state {
            case .connected: return t.good
            case .connecting, .idle, .needsPassword: return t.warning
            case .failed: return t.bad
            }
        }
        switch state {
        case .exited: return t.bad
        case .connecting: return t.warning
        case .connected: return notice ? t.warning : t.good
        }
    }
}

/// Selector ligado al login de esta pestaña; se superpone sin redimensionar el terminal ni su PTY.
struct PasswordNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let session: TerminalSession
    let event: PasswordAutomation.Event

    var body: some View {
        if case .suggested = event {
            if let offer = model.passwordOffers[session.id] {
                panel {
                    Text(L("Contraseña para \(offer.target.host)")).font(t.ui(12, .bold))
                    ForEach(offer.refs, id: \.self) { ref in
                        NeonButton(title: L("Escribir «\(ref.account)»"), icon: "key.fill", tint: t.good) {
                            model.choosePassword(ref, offer: offer, in: session)
                        }
                    }
                }
            }
        } else {
            panel { Text(text).font(t.ui(12)).foregroundStyle(SwiftUI.Color(t.text)).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "key.fill").foregroundStyle(SwiftUI.Color(t.warning))
            VStack(alignment: .leading, spacing: 10, content: content).frame(maxWidth: .infinity, alignment: .leading)
            IconButton(icon: "xmark") { model.dismissPasswordNotice(in: session) }
                .help(L("Cerrar"))
        }
        .padding(12)
        .frame(maxWidth: 360)
        .background(SwiftUI.Color(t.panel), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SwiftUI.Color(t.warning).opacity(0.5)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
    }

    private var text: String {
        switch event {
        case .suggested: ""
        case .manual(let why): L("Piden contraseña: \(Askpass.explain(why)) · o elígela en 🔑")
        case .failed(let r): L("«\(r.account)» no ha valido: bloqueada 15 min en todas las pestañas (cuenta AD)")
        default: ""
        }
    }
}

/// La vista de SwiftTerm de la pestaña (vive en la sesión: cambiar de pestaña o de vista no la recrea). Va dentro de
/// un contenedor: el último que se crea se la queda (pestaña sola ↔ panel de la vista dividida).
struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession
    var focused = false

    func makeNSView(context: Context) -> NSView {
        let box = NSView()
        session.host = box
        adopt(into: box)
        return box
    }

    func updateNSView(_ box: NSView, context: Context) {
        if session.host === box { adopt(into: box) }
        guard focused else { return }
        DispatchQueue.main.async {
            let v = session.view
            if v.superview === box, v.window?.firstResponder !== v { v.window?.makeFirstResponder(v) }
        }
    }

    private func adopt(into box: NSView) {
        let v = session.view
        guard v.superview !== box else { return }
        v.removeFromSuperview()
        v.frame = box.bounds
        v.autoresizingMask = [.width, .height]
        box.addSubview(v)
    }
}

/// Lee la ventana de SwiftUI (pantalla completa, color de fondo, llenar la pantalla).
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> Probe {
        let v = Probe()
        v.found = found
        return v
    }

    func updateNSView(_ v: Probe, context: Context) {
        v.found = found
        if let w = v.window { DispatchQueue.main.async { found(w) } }
    }

    /// Avisa en cuanto entra en su ventana (una ventana nueva y vacía puede no volver a actualizarse después).
    final class Probe: NSView {
        var found: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            DispatchQueue.main.async { [weak self] in self?.found?(w) }
        }
    }
}

// MARK: - barra de estado

struct StatusBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            if let u = model.availableUpdate {
                Button { model.offerUpdate(u) } label: {
                    Tag(text: L("⬆ Versión \(u.version) disponible"), color: t.good)
                }
                .buttonStyle(.plain)
                .help(L("Hay una versión nueva de Terminal NetDeck: clic para verla"))
            }
            if model.multiExecOn {
                Tag(text: L("MULTIEXEC ×\(model.multiExecTargets.count)"), color: t.warning)
            }
            Tag(text: L("🔑 SESIÓN \(model.settings.sessionAutoPassword ? "AUTO" : "MANUAL") · EQUIPOS \(modeText)"), color: t.accent2)
            Text(model.themes.current.name.uppercased()).tracking(1.5).foregroundStyle(SwiftUI.Color(t.dim))
            TimelineView(.everyMinute) { ctx in
                Text(t.clockText(ctx.date)).foregroundStyle(SwiftUI.Color(t.accent))
            }
        }
        .font(t.ui(10.5, .medium))
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(SwiftUI.Color(t.bar))
        .overlay(alignment: .top) { NeonLine(color: t.accent2) }
    }

    private var modeText: String {
        switch model.settings.devicePasswordMode {
        case .autoType: L("AUTO")
        case .suggest: L("SUGERIR")
        case .off: L("NO")
        }
    }
}

/// Aviso pasajero abajo a la derecha: sólo lo importante de `model.status` (✗ errores, 🔑 contraseñas, ⎋ cortes,
/// ⬆ actualizaciones) y lo que está haciendo la galería de temas; lo demás no se muestra.
struct StatusToast: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        if let text = model.themes.busy ?? model.toast {
            Text(text)
                .font(t.ui(11.5, .medium))
                .foregroundStyle(SwiftUI.Color(t.text))
                .lineLimit(2).truncationMode(.middle)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(maxWidth: 520, alignment: .trailing)
                .background(RoundedRectangle(cornerRadius: t.corner ?? 8).fill(SwiftUI.Color(t.bar.opaque)))
                .overlay(RoundedRectangle(cornerRadius: t.corner ?? 8)
                    .strokeBorder(SwiftUI.Color(text.hasPrefix("✗") ? t.bad : t.accent2).opacity(0.7)))
                .shadow(color: .black.opacity(0.3), radius: 6)
                .onTapGesture { model.toast = nil }
                .transition(.opacity)
                .allowsHitTesting(true)
        }
    }
}

struct Tag: View {
    @Environment(\.theme) private var t
    let text: String
    let color: RGB

    var body: some View {
        Text(text)
            .font(t.ui(9.5, .bold)).tracking(1)
            .foregroundStyle(SwiftUI.Color(color))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SwiftUI.Color(color).opacity(0.6)))
    }
}
