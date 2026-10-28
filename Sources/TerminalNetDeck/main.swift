import AppKit
import Foundation
import NetDeckCore

/// Sin pestaña (SFTP, procesos sin terminal): el askpass pregunta en una ventana.
final class DialogAskpass: AskpassUI {
    private var notes: [String] = []
    /// (sin pestaña: lo dice el explorador al conectar, `Askpass.takeSaved`)
    var reportsSaved: Bool { true }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.activate()
    }

    func say(_ s: String) {
        let clean = s.replacingOccurrences(of: #"\u{1b}\[[0-9;]*m"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // (se enseña con la siguiente pregunta. Lo dicho al final —«guardada ✓», un error al guardarla— no: ssh espera
        // a que termine el askpass y una ventana más lo dejaría parado hasta Aceptar; queda en los registros)
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
        a.addButton(withTitle: L("Cancelar")).keyEquivalent = "\u{1b}"
        a.window.initialFirstResponder = f
        return a.runModal() == .alertFirstButtonReturn ? f.stringValue : nil
    }

    /// El botón por defecto (Intro) es el que diga `d`; Esc, siempre «No».
    func yesNo(_ question: String, default d: Bool) -> Bool? {
        let a = NSAlert()
        a.messageText = question
        a.informativeText = notes.joined(separator: "\n")
        notes = []
        let yes = a.addButton(withTitle: L("Sí")), no = a.addButton(withTitle: L("No"))
        yes.keyEquivalent = d ? "\r" : ""
        no.keyEquivalent = d ? "\u{1b}" : "\r"
        return a.runModal() == .alertFirstButtonReturn
    }
}


// Escribir en una tubería ya cerrada (security, ssh, gzcat que terminan antes) da error, no cierra la app.
signal(SIGPIPE, SIG_IGN)

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
