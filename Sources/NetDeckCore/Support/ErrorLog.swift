import Foundation

/// Registro de errores: ~/Library/Application Support/Terminal NetDeck/logs/error.log. Siempre activo (al contrario
/// que `DebugLog`), corto y para el usuario: guardados que fallan, Llavero, procesos que no arrancan, importaciones…
/// Una línea por error: «2026-10-14T10:00:00Z [ERROR] área: detalle». Nunca contraseñas ni lo que se teclea.
public enum ErrorLog {
    public enum Level: String, Sendable { case error = "ERROR", warning = "WARNING" }

    public static var directory: URL { AppPaths.support.appendingPathComponent("logs", isDirectory: true) }
    public static var file: URL { directory.appendingPathComponent("error.log") }
    /// Al pasar de esto se guarda como `error.log.1` (sólo una copia) y se empieza otro.
    public static let maxSize = 2_000_000

    private static let queue = DispatchQueue(label: "netdeck.errorlog")

    /// La línea tal cual (en UTC; los saltos de línea del detalle, en una sola línea).
    public static func line(_ level: Level, _ area: String, _ message: String, date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        let flat = message.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        return "\(f.string(from: date)) [\(level.rawValue)] \(area): \(flat)\n"
    }

    public static func error(_ area: String, _ message: String) { write(.error, area, message) }
    public static func warning(_ area: String, _ message: String) { write(.warning, area, message) }

    public static func write(_ level: Level, _ area: String, _ message: String) {
        let text = line(level, area, message)
        DebugLog.log(area, "\(level.rawValue): \(message)")
        queue.async { append(text, to: file) }
    }

    /// Espera a que se escriba lo pendiente (antes de abrirlo o de salir).
    public static func flush() { queue.sync {} }

    /// Añade al final (carpeta 0700, archivo 0600), rotando antes si el archivo ya pasa de `limit`.
    public static func append(_ text: String, to url: URL, limit: Int = maxSize) {
        let fm = FileManager.default
        AppPaths.ensure(url.deletingLastPathComponent())
        if let a = try? fm.attributesOfItem(atPath: url.path), (a[.size] as? Int ?? 0) >= limit {
            let old = URL(fileURLWithPath: url.path + ".1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(text.utf8))
    }
}

/// Qué mensajes de estado merecen un aviso en pantalla (el resto sólo va al registro de depuración).
public enum StatusNotice {
    /// ✗ errores · 🔑 contraseñas · ⎋ cortes · ⬆ actualizaciones.
    public static let prefixes = ["✗", "🔑", "⎋", "⬆"]

    public static func isImportant(_ status: String) -> Bool {
        let s = status.trimmingCharacters(in: .whitespaces)
        return prefixes.contains { s.hasPrefix($0) }
    }
}
