import Foundation

/// Archivos del usuario (ssh_config, botones…): nunca se pisa uno que existe pero no se puede leer, y antes de
/// sustituirlo se guarda copia (`.anterior`, la de la vez anterior; `.original`, la primera, que no se toca nunca).
public enum SafeFile {
    public struct Unreadable: LocalizedError, Equatable {
        public let path: String
        public var errorDescription: String? {
            L("No se puede leer \(path): no lo sobrescribo (¿no es UTF-8?). Revísalo o muévelo y vuelve a probar.")
        }
    }

    /// El texto del archivo; nil si no existe. Si existe y no se puede leer, error (no «vacío»).
    public static func read(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = FileManager.default.contents(atPath: url.path) else { throw Unreadable(path: url.path) }
        guard let s = String(data: data, encoding: .utf8) else { throw Unreadable(path: url.path) }
        return s
    }

    /// Copias antes de sustituir `url` (si existe y se puede leer). Si no se puede copiar, error: no se sustituye.
    public static func backup(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        _ = try read(url)
        let original = url.appendingPathExtension("original")
        if !fm.fileExists(atPath: original.path) { try fm.copyItem(at: url, to: original) }
        let prev = url.appendingPathExtension("anterior")
        let tmp = url.appendingPathExtension("anterior.tmp")
        try? fm.removeItem(at: tmp)
        try fm.copyItem(at: url, to: tmp)
        if fm.fileExists(atPath: prev.path) {
            _ = try fm.replaceItemAt(prev, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: prev)
        }
    }

    /// Escribe de forma atómica con permisos 0600 (sólo tú).
    public static func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
