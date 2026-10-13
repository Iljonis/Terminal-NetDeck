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
        CommandGroup(replacing: .newItem) {
            Button("Conectar / Salto…") { model.sheet = .connect }.keyboardShortcut("k")
            Button("Lista por salto…") { model.sheet = .list }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Sesiones…") { model.editSessions() }.keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Cerrar pestaña") { model.closeCurrent() }.keyboardShortcut("w")
        }
        CommandGroup(replacing: .appSettings) {
            Button("Ajustes…") { model.openSettings() }.keyboardShortcut(",")
            Button("Asistente de instalación…") { model.showSetup = true }
            Button("Buscar actualizaciones…") { model.checkForUpdates() }
            Button("Actualizar desde el código…") { model.updateFromSource() }
                .disabled(AppModel.sourceFolder == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Buscar en la salida…") { model.current?.view.showFind() }.keyboardShortcut("f")
            Button("Buscar en todos los registros…") { model.sheet = .logs }.keyboardShortcut("f", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Button("Abrir el registro de depuración") {
                DebugLog.flush()
                NSWorkspace.shared.open(DebugLog.file)
            }
            Button("Carpeta de registros") { NSWorkspace.shared.open(DebugLog.directory) }
        }
        // (contraseñas, dividir y ajustes van en la barra de la ventana; aquí solo lo que tiene atajo)
        CommandMenu("Terminal") {
            Button("Pegado seguro…") { model.sheet = .paste }.keyboardShortcut("v", modifiers: [.command, .shift])
            Toggle("MultiExec", isOn: Binding(get: { model.multiExecOn }, set: { model.multiExecOn = $0 }))
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Toggle("Resaltado", isOn: Binding(get: { model.settings.highlightEnabled },
                                              set: { model.settings.highlightEnabled = $0; model.applyHighlight() }))
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button("Reconectar") { model.current.map(model.reconnect) }.keyboardShortcut("r")
            Button("Clonar pestaña") { model.current.map(model.duplicate) }.keyboardShortcut("d")
            Divider()
            Button("Pestaña siguiente") { model.selectNext(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Pestaña anterior") { model.selectNext(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Mostrar/ocultar sesiones") { model.settings.sidebarVisible.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
            Button("Cancelar lo automático (Esc)") { model.abortAll() }.keyboardShortcut(".")
            Button("Recargar ssh_config") { model.reloadSessions() }.keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // (con «swift run» no hay .app: que salga en el Dock y con ventana al frente)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let path = ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] { snapshot(to: path) }
    }

    /// Desarrollo: NETDECK_SNAPSHOT=/ruta.png → la app guarda una imagen de su ventana (sin permisos de pantalla).
    private func snapshot(to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            for (i, w) in NSApp.windows.filter({ $0.isVisible && $0.contentView != nil }).enumerated() {
                guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
                let url = URL(fileURLWithPath: i == 0 ? path : path.replacingOccurrences(of: ".png", with: "-\(i).png"))
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.instance?.saveOpenTabs() }
        DebugLog.log("app", "sale")
        DebugLog.flush()
    }
}
