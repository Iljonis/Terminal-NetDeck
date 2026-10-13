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
            Button(L("Conectar / Salto…")) { model.sheet = .connect }.keyboardShortcut("k")
            Button(L("Lista por salto…")) { model.sheet = .list }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button(L("Sesiones…")) { model.editSessions() }.keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button(L("Cerrar pestaña")) { model.closeCurrent() }.keyboardShortcut("w")
        }
        CommandGroup(replacing: .appSettings) {
            Button(L("Ajustes…")) { model.openSettings() }.keyboardShortcut(",")
            Button(L("Asistente de instalación…")) { model.showSetup = true }
            Button(L("Buscar actualizaciones…")) { model.checkForUpdates() }
            Button(L("Actualizar desde el código…")) { model.updateFromSource() }
                .disabled(AppModel.sourceFolder == nil)
        }
        CommandGroup(after: .textEditing) {
            Button(L("Buscar en la salida…")) { model.current?.view.showFind() }.keyboardShortcut("f")
            Button(L("Buscar en todos los registros…")) { model.sheet = .logs }.keyboardShortcut("f", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Button(L("Abrir el registro de depuración")) {
                DebugLog.flush()
                NSWorkspace.shared.open(DebugLog.file)
            }
            Button(L("Carpeta de registros")) { NSWorkspace.shared.open(DebugLog.directory) }
        }
        // (contraseñas, dividir y ajustes van en la barra de la ventana; aquí solo lo que tiene atajo)
        CommandMenu(L("Terminal")) {
            Button(L("Pegado seguro…")) { model.sheet = .paste }.keyboardShortcut("v", modifiers: [.command, .shift])
            Toggle(L("MultiExec"), isOn: Binding(get: { model.multiExecOn }, set: { model.multiExecOn = $0 }))
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Toggle(L("Resaltado"), isOn: Binding(get: { model.settings.highlightEnabled },
                                              set: { model.settings.highlightEnabled = $0; model.applyHighlight() }))
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button(L("Reconectar")) { model.current.map(model.reconnect) }.keyboardShortcut("r")
            Button(L("Clonar pestaña")) { model.current.map(model.duplicate) }.keyboardShortcut("d")
            Divider()
            Button(L("Pestaña siguiente")) { model.selectNext(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button(L("Pestaña anterior")) { model.selectNext(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            Button(L("Mostrar/ocultar sesiones")) { model.settings.sidebarVisible.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
            Button(L("Cancelar lo automático (Esc)")) { model.abortAll() }.keyboardShortcut(".")
            Button(L("Recargar ssh_config")) { model.reloadSessions() }.keyboardShortcut("r", modifiers: [.command, .shift])
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
