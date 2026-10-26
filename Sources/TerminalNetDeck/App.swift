import AppKit
import NetDeckCore
import SwiftUI

/// `@State` como envoltorio clásico: en el SDK de macOS 27 `@State` es una macro y CommandLineTools no trae su plugin
/// (con Xcode da igual).
typealias Stored<Value> = SwiftUI.State<Value>

struct TerminalNetDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let core = AppCore.shared

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false   // (las pestañas son las de la app, no las de macOS)
        AppCore.shared.prepareLaunch()
    }

    var body: some Scene {
        // (cada ventana, con su token: la del arranque y las de «Nueva ventana» o al sacar una pestaña a otra pantalla)
        WindowGroup("Terminal NetDeck", id: "main", for: UUID.self) { $token in
            WindowRoot(token: token)
        } defaultValue: {
            UUID()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 860)
        .restorationBehavior(.disabled)                 // (las ventanas y sus pestañas las reabre la app: abiertas.json)
        .commands { NetDeckCommands(core: core, menus: core.menus) }
    }
}

/// Una ventana: su `AppModel` (uno por ventana, en `AppCore`), el tema y su título (el de la pestaña elegida: es el
/// que sale en el menú Ventana y en Mission Control).
struct WindowRoot: View {
    let token: UUID
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let model = AppCore.shared.model(for: token)
        ContentView()
            .id(model.settings.language)                 // (otro idioma: se rehace la interfaz)
            .environment(model)
            .environment(\.theme, model.uiTheme)
            .preferredColorScheme(model.themes.current.isLight ? .light : .dark)
            .frame(minWidth: 960, minHeight: 600)
            .navigationTitle(model.current?.tabTitle ?? "Terminal NetDeck")
            // (en ventana, las pestañas comparten la barra de título; en pantalla completa, macOS gestiona el
            // espacio de su barra y la de la app queda en el mismo flujo que el buscador y el terminal)
            .ignoresSafeArea(.container, edges: model.fullScreen ? [] : .top)
            // (siempre, también con el asistente: una ventana sin enganchar no contaría al cerrar las demás)
            .background(WindowReader { model.attach($0) })
            .onAppear { AppCore.shared.openWindowAction = openWindow }
    }
}

/// Los menús, siempre sobre la ventana de delante (`AppCore.front`). SwiftUI no los vuelve a mirar cuando cambia algo
/// `@Observable`: `menus` (un ObservableObject que `AppCore` avisa) los refresca al cambiar de ventana, abrir una hoja…
/// Y cada acción comprueba al hacerse que esa ventana no tenga una hoja, Ajustes o el asistente abiertos (`modalOpen`).
struct NetDeckCommands: Commands {
    let core: AppCore
    @ObservedObject var menus: MenuRefresh

    /// En la ventana de delante, si no tiene una hoja, Ajustes o el asistente abiertos.
    private func onFront(_ f: (AppModel) -> Void) {
        guard let m = core.front, !m.modalOpen else { return }
        f(m)
    }

    var body: some Commands {
        let _ = menus.tick
        let _ = core.settings.language                      // (los menús, también en el idioma nuevo)
        let model = core.front
        let modal = model?.modalOpen ?? false
        CommandGroup(replacing: .newItem) {
            Button(L("Nueva ventana")) { core.openWindow() }.keyboardShortcut("n")
            Button(L("Nueva terminal local")) { onFront { $0.openLocal() } }.keyboardShortcut("t").disabled(modal)
            Button(L("Conectar / Salto…")) { onFront { $0.sheet = .connect } }.keyboardShortcut("k").disabled(modal)
            Button(L("Abrir la sesión de inicio")) { onFront { $0.openStartupSession() } }.keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(model?.startupProfile == nil || modal)
            Button(L("Sesiones…")) { onFront { $0.editSessions() } }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(modal)
            Divider()
            Button(L("Cerrar pestaña")) { onFront { $0.closeCurrent() } }.keyboardShortcut("w").disabled(modal)
            Button(L("Cerrar ventana")) { onFront { $0.askToCloseWindow() } }.keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(modal)
        }
        // (sin «Cerrar» ni «Cerrar todas» de macOS: cerraban sin preguntar y, con varias ventanas, se perdían pestañas)
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .appSettings) {
            Button(L("Ajustes…")) {
                guard let m = core.front, m.sheet == nil else { return }
                m.openSettings()
            }
            .keyboardShortcut(",").disabled(model?.sheet != nil)
            Button(L("Asistente de instalación…")) { core.front?.showSetup = true }
            Button(L("Buscar actualizaciones…")) { core.front?.checkForUpdates() }
            Button(L("Actualizar desde el código…")) { core.front?.updateFromSource() }
                .disabled(AppModel.sourceFolder == nil)
        }
        CommandGroup(after: .textEditing) {
            Button(L("Buscar en la salida…")) { onFront { $0.current?.view.showFind() } }.keyboardShortcut("f").disabled(modal)
        }
        CommandGroup(replacing: .help) {
            Button(L("Abrir el registro de depuración")) {
                DebugLog.flush()
                NSWorkspace.shared.open(DebugLog.file)
            }
            Button(L("Abrir el registro de errores")) {
                ErrorLog.flush()
                if !FileManager.default.fileExists(atPath: ErrorLog.file.path) {
                    ErrorLog.append("", to: ErrorLog.file)              // (vacío: que se abra igual)
                }
                NSWorkspace.shared.open(ErrorLog.file)
            }
            Button(L("Carpeta de registros")) { NSWorkspace.shared.open(DebugLog.directory) }
        }
        // (contraseñas, dividir y ajustes van en la barra de la ventana; aquí solo lo que tiene atajo. Con una hoja,
        // Ajustes o el asistente abiertos se apagan los que cambian de hoja o tocan las pestañas: `modalOpen`)
        CommandMenu(L("Terminal")) {
            Toggle(L("MultiExec"), isOn: Binding(get: { core.front?.multiExecOn ?? false },
                                                set: { on in onFront { $0.multiExecOn = on } }))
                .keyboardShortcut("m", modifiers: [.command, .shift]).disabled(modal)
            Toggle(L("Resaltado"), isOn: Binding(get: { core.settings.highlightEnabled },
                                              set: { core.settings.highlightEnabled = $0; core.front?.applyHighlight() }))
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button(L("Reconectar")) { onFront { m in m.current.map(m.reconnect) } }.keyboardShortcut("r").disabled(modal)
            Button(L("Enviar BREAK (consola serie)")) {
                onFront { m in if m.current?.route.transport == .serial { m.current?.sendSerialBreak() } }
            }
            .disabled(modal || model?.current?.route.transport != .serial || model?.current?.exited != false)
            Button(L("Clonar pestaña")) { onFront { m in m.current.map(m.duplicate) } }.keyboardShortcut("d").disabled(modal)
            Button(L("Mover la pestaña a una ventana nueva")) {
                onFront { m in if m.tabs.count > 1, let s = m.current { m.moveTabToNewWindow(s) } }
            }
            .disabled(modal || (model?.tabs.count ?? 0) < 2)
            Button(L("Mostrar/ocultar el explorador SFTP")) { onFront { m in m.current.map(m.toggleSidePanel) } }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(modal || !(model?.current.map { SFTPPanel.offers($0.route) } ?? false))
            Divider()
            Button(L("Pestaña siguiente")) { onFront { $0.selectNext(1) } }.keyboardShortcut("]", modifiers: [.command, .shift]).disabled(modal)
            Button(L("Pestaña anterior")) { onFront { $0.selectNext(-1) } }.keyboardShortcut("[", modifiers: [.command, .shift]).disabled(modal)
            Button(L("Mostrar/ocultar sesiones")) { core.settings.sidebarVisible.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
            Button(L("Cancelar lo automático (Esc)")) { core.abortEverywhere() }.keyboardShortcut(".")
            Button(L("Recargar ssh_config")) { onFront { $0.reloadSessions() } }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(modal)
        }
        CommandMenu(L("Herramientas")) {
            Button(L("Listas de equipos…")) { onFront { $0.present(.list) } }.keyboardShortcut("l", modifiers: [.command, .shift]).disabled(modal)
            Button(L("Pegado seguro…")) { onFront { $0.sheet = .paste } }.keyboardShortcut("v", modifiers: [.command, .shift]).disabled(modal)
            Button(L("Macros…")) { onFront { $0.present(.macros) } }.disabled(modal)
            Button(L("Túneles SSH…")) { onFront { $0.present(.tunnels) } }.disabled(modal)
            Button(L("Espacios de trabajo…")) { onFront { $0.sheet = .workspaces } }.disabled(modal)
            Button(model?.recording == nil ? L("Grabar macro") : L("Parar la grabación")) { onFront { $0.toggleRecording() } }
                .disabled(modal || (model?.recording == nil && model?.current == nil))
            Button(L("Buscar en todos los registros…")) { onFront { $0.sheet = .logs } }.keyboardShortcut("f", modifiers: [.command, .shift]).disabled(modal)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // (con «swift run» no hay .app: que salga en el Dock y con ventana al frente)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        MainActor.assumeIsolated { TunnelSignals.install() }
        if let path = ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] { snapshot(to: path) }
    }

    /// Desarrollo: NETDECK_SNAPSHOT=/ruta.png → la app guarda una imagen de su ventana (sin permisos de pantalla).
    /// NETDECK_SNAPSHOT_CLICK=«x,y» (puntos desde arriba a la izquierda de la ventana; una «y» negativa, desde abajo:
    /// así vale en cualquier tamaño de pantalla, p. ej. la de GitHub Actions) hace antes un clic derecho ahí,
    /// por la cola de eventos como uno de verdad: el menú que abra sale en la imagen «-1.png». NETDECK_SNAPSHOT_WAIT:
    /// los segundos hasta la imagen (2,5; más para una sesión de verdad).
    static var snapshotWait: Double {
        ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT_WAIT"].flatMap(Double.init).map { min(max($0, 1), 120) } ?? 2.5
    }

    private func snapshot(to path: String) {
        if let spec = ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT_CLICK"] {
            let n = spec.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if n.count == 2 {
                // (el clic, cuando lo de la ventana ya está, no a tiempo fijo: con el Mac cargado el explorador aún no
                // había listado a los 1,8 s y el clic caía en el fondo o en nada; la imagen, después del clic)
                Task { @MainActor in
                    let start = ContinuousClock.now
                    try? await Task.sleep(for: .seconds(1.8))
                    while !Self.contentReady, ContinuousClock.now - start < .seconds(15) { try? await Task.sleep(for: .milliseconds(100)) }
                    try? await Task.sleep(for: .milliseconds(300))          // (que se pinte lo recién listado)
                    let before = Self.visibleWindows.count, clicked = ContinuousClock.now
                    Self.rightClick(x: n[0], y: n[1])
                    // (y la imagen cuando ha salido el menú, no a los 0,7 s: cargado, el Mac tardaba más en sacarlo)
                    try? await Task.sleep(for: .seconds(max(0.7, Self.snapshotWait - 1.8)))
                    while Self.visibleWindows.count <= before, ContinuousClock.now - clicked < .seconds(5) {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    try? await Task.sleep(for: .milliseconds(300))          // (que acabe de pintarse)
                    Self.capture(to: path)
                }
                return
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.snapshotWait) { Self.capture(to: path) }
    }

    /// Los exploradores de las pestañas, conectados y con su carpeta listada (aunque esté vacía).
    @MainActor private static var contentReady: Bool {
        AppCore.shared.allBrowsers.map(\.1).allSatisfy { $0.state == .connected && !$0.path.isEmpty }
    }

    @MainActor private static var visibleWindows: [NSWindow] { NSApp.windows.filter { $0.isVisible && $0.contentView != nil } }

    @MainActor private static func capture(to path: String) {
        for (i, w) in visibleWindows.enumerated() {
            guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            v.cacheDisplay(in: v.bounds, to: rep)
            let url = URL(fileURLWithPath: i == 0 ? path : path.replacingOccurrences(of: ".png", with: "-\(i).png"))
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    @MainActor private static func rightClick(x: Double, y: Double) {
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }), let v = w.contentView else { return }
        let p = NSPoint(x: x, y: y < 0 ? -y : v.bounds.height - y)
        for type in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
            guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                             pressure: 1) else { continue }
            NSApp.postEvent(e, atStart: false)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Antes de que se cierre ninguna ventana: se guardan las pestañas de todas (cada una en la suya) y las que se
    /// cierran al salir ya no cortan nada por su cuenta.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { AppCore.shared.willTerminate() }
        return .terminateNow
    }

    /// El Dock: «Nueva ventana» (macOS añade debajo la lista de las abiertas).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Nueva ventana"), action: #selector(newWindowFromDock(_:)), keyEquivalent: "").target = self
        return menu
    }

    @objc private func newWindowFromDock(_ sender: Any?) {
        MainActor.assumeIsolated { AppCore.shared.openWindow() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppCore.shared.willTerminate()
            AppCore.shared.allBrowsers.forEach { $0.1.edits?.finish() }         // (las copias de edición sin nada pendiente)
            AppCore.shared.tunnelRunner.stopAll()                               // (ningún ssh de túnel sigue tras salir)
        }
        DebugLog.log("app", "sale")
        DebugLog.flush()
        ErrorLog.flush()
    }
}
