import AppKit
import Foundation
import NetDeckCore

/// Sin pestaña (SFTP, procesos sin terminal): el askpass pregunta en una ventana.
final class DialogAskpass: AskpassUI {
    private var notes: [String] = []

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.activate()
    }

    func say(_ s: String) {
        let clean = s.replacingOccurrences(of: #"\u{1b}\[[0-9;]*m"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { notes.append(clean) }
    }

    func read(secret: Bool) -> String? {
        let a = NSAlert()
        a.messageText = notes.last ?? "Terminal NetDeck"
        a.informativeText = notes.dropLast().joined(separator: "\n")
        notes = []
        let f: NSTextField = secret ? NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
                                    : NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        a.accessoryView = f
        a.addButton(withTitle: L("Aceptar"))
        a.addButton(withTitle: L("Cancelar"))
        a.window.initialFirstResponder = f
        return a.runModal() == .alertFirstButtonReturn ? f.stringValue : nil
    }

    func yesNo(_ question: String, default d: Bool) -> Bool? {
        let a = NSAlert()
        a.messageText = question
        a.addButton(withTitle: L("Sí"))
        a.addButton(withTitle: L("No"))
        return a.runModal() == .alertFirstButtonReturn
    }
}

// El mismo ejecutable es el SSH_ASKPASS de las pestañas (contraseña de sesión automática): sin interfaz.
if ProcessInfo.processInfo.environment[Askpass.flag] == "1" {
    let code = MainActor.assumeIsolated {
        Askpass.run(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment,
                    dialog: { DialogAskpass() })
    }
    DebugLog.flush()
    exit(code)
}
TerminalNetDeckApp.main()
