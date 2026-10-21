import AppKit
import NetDeckCore
import SwiftUI

/// `@State` como envoltorio clásico: en el SDK de macOS 27 `@State` es una macro y CommandLineTools no trae su plugin
/// (con Xcode da igual).
typealias Stored<Value> = SwiftUI.State<Value>

struct TerminalNetDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Stored private var model = AppModel()

    var body: some Scene {
        Window("Terminal NetDeck", id: "main") {
            ContentView()
                .id(model.settings.language)                 // (otro idioma: se rehace la interfaz)
                .environment(model)
                .environment(\.theme, model.uiTheme)
                .preferredColorScheme(model.themes.current.isLight ? .light : .dark)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 860)
        .commands { NetDeckCommands(model: model) }

    }
}

struct NetDeckCommands: Commands {
    let model: AppModel

    var body: some Commands {
        let _ = model.settings.language                     // (los menús, también en el idioma nuevo)
        CommandGroup(replacing: .newItem) {
            Button(L("Nueva terminal local")) { model.openLocal() }.keyboardShortcut("t").disabled(model.modalOpen)
            Button(L("Conectar / Salto…")) { model.sheet = .connect }.keyboardShortcut("k").disabled(model.modalOpen)
            Button(L("Abrir la sesión de inicio")) { model.openStartupSession() }.keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(model.startupProfile == nil || model.modalOpen)
            Button(L("Sesiones…")) { model.editSessions() }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.modalOpen)
            Divider()
            Button(L("Cerrar pestaña")) { model.closeCurrent() }.keyboardShortcut("w").disabled(model.modalOpen)
        }
        CommandGroup(replacing: .appSettings) {
            Button(L("Ajustes…")) { model.openSettings() }.keyboardShortcut(",").disabled(model.sheet != nil)
            Button(L("Asistente de instalación…")) { model.showSetup = true }
            Button(L("Buscar actualizaciones…")) { model.checkForUpdates() }
            Button(L("Actualizar desde el código…")) { model.updateFromSource() }
                .disabled(AppModel.sourceFolder == nil)
        }
        CommandGroup(after: .textEditing) {
            Button(L("Buscar en la salida…")) { model.current?.view.showFind() }.keyboardShortcut("f").disabled(model.modalOpen)
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
            Toggle(L("MultiExec"), isOn: Binding(get: { model.multiExecOn }, set: { model.multiExecOn = $0 }))
                .keyboardShortcut("m", modifiers: [.command, .shift]).disabled(model.modalOpen)
            Toggle(L("Resaltado"), isOn: Binding(get: { model.settings.highlightEnabled },
                                              set: { model.settings.highlightEnabled = $0; model.applyHighlight() }))
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button(L("Reconectar")) { model.current.map(model.reconnect) }.keyboardShortcut("r").disabled(model.modalOpen)
            Button(L("Enviar BREAK (consola serie)")) { model.current?.sendSerialBreak() }
                .disabled(model.modalOpen || model.current?.route.transport != .serial || model.current?.exited != false)
            Button(L("Clonar pestaña")) { model.current.map(model.duplicate) }.keyboardShortcut("d").disabled(model.modalOpen)
            Button(L("Mostrar/ocultar el explorador SFTP")) { model.current.map(model.toggleSidePanel) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(model.modalOpen || !(model.current.map { SFTPPanel.offers($0.route) } ?? false))
            Divider()
            Button(L("Pestaña siguiente")) { model.selectNext(1) }.keyboardShortcut("]", modifiers: [.command, .shift]).disabled(model.modalOpen)
            Button(L("Pestaña anterior")) { model.selectNext(-1) }.keyboardShortcut("[", modifiers: [.command, .shift]).disabled(model.modalOpen)
            Button(L("Mostrar/ocultar sesiones")) { model.settings.sidebarVisible.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
            Button(L("Cancelar lo automático (Esc)")) { model.abortAll() }.keyboardShortcut(".")
            Button(L("Recargar ssh_config")) { model.reloadSessions() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.modalOpen)
        }
        CommandMenu(L("Herramientas")) {
            Button(L("Listas de equipos…")) { model.sheet = .list }.keyboardShortcut("l", modifiers: [.command, .shift]).disabled(model.modalOpen)
            Button(L("Pegado seguro…")) { model.sheet = .paste }.keyboardShortcut("v", modifiers: [.command, .shift]).disabled(model.modalOpen)
            Button(L("Macros…")) { model.sheet = .macros }.disabled(model.modalOpen)
            Button(L("Túneles SSH…")) { model.sheet = .tunnels }.disabled(model.modalOpen)
            Button(L("Espacios de trabajo…")) { model.sheet = .workspaces }.disabled(model.modalOpen)
            Button(model.recording == nil ? L("Grabar macro") : L("Parar la grabación")) { model.toggleRecording() }
                .disabled(model.modalOpen || (model.recording == nil && model.current == nil))
            Button(L("Buscar en todos los registros…")) { model.sheet = .logs }.keyboardShortcut("f", modifiers: [.command, .shift]).disabled(model.modalOpen)
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
        (AppModel.instance?.allBrowsers ?? []).map(\.1).allSatisfy { $0.state == .connected && !$0.path.isEmpty }
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

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.instance?.saveOpenTabs()
            AppModel.instance?.allBrowsers.forEach { $0.1.edits?.finish() }     // (las copias de edición sin nada pendiente)
            AppModel.instance?.tunnelRunner.stopAll()                           // (ningún ssh de túnel sigue tras salir)
        }
        DebugLog.log("app", "sale")
        DebugLog.flush()
        ErrorLog.flush()
    }
}
