import Foundation

/// Registro de depuración: ~/Library/Logs/Terminal NetDeck/debug.log (app y askpass escriben en el mismo).
/// Nunca contraseñas ni lo que se teclea: sólo qué pasa (pestañas, saltos, MultiExec, decisiones de contraseña…).
public enum DebugLog {
    public static var directory: URL { AppPaths.home.appendingPathComponent("Library/Logs/Terminal NetDeck", isDirectory: true) }
    public static var file: URL { directory.appendingPathComponent("debug.log") }
    /// Se puede apagar en Ajustes → General (y con NETDECK_DEBUG=0).
    nonisolated(unsafe) public static var enabled = ProcessInfo.processInfo.environment["NETDECK_DEBUG"] != "0"

    private static let queue = DispatchQueue(label: "netdeck.debug")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// `area`: «pestaña», «salto», «multiexec», «contraseña»…
    public static func log(_ area: String, _ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(stamp.string(from: Date())) [\(getpid())] \(area): \(message())\n"
        queue.async {
            let fm = FileManager.default
            if !fm.fileExists(atPath: directory.path) {
                try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            if let a = try? fm.attributesOfItem(atPath: file.path), (a[.size] as? Int ?? 0) > 5_000_000 {
                let old = directory.appendingPathComponent("debug.anterior.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: file, to: old)
            }
            if !fm.fileExists(atPath: file.path) {
                fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            guard let h = try? FileHandle(forWritingTo: file) else { return }
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(line.utf8))
        }
    }

    /// Espera a que se escriba lo pendiente (antes de salir).
    public static func flush() { queue.sync {} }
}
