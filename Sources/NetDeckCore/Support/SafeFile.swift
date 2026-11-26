import Foundation
#if os(Windows)
import WinSDK
#endif

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

    /// Sustituye `url` por `tmp` en un solo paso: si falla, `url` queda como estaba y `tmp` sigue en su sitio. En macOS,
    /// `replaceItemAt`; en Windows, `MoveFileExW` con REPLACE_EXISTING (borrar y luego mover dejaba una ventana sin archivo).
    public static func replace(_ url: URL, with tmp: URL) throws {
        #if os(Windows)
        let flags: DWORD = 0x1 | 0x8                      // MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH
        var code: DWORD = 0
        for intento in 0..<8 {
            code = tmp.path.withCString(encodedAs: UTF16.self) { from in
                url.path.withCString(encodedAs: UTF16.self) { to in
                    MoveFileExW(from, to, flags) ? 0 : GetLastError()
                }
            }
            // (acceso denegado, violación de uso compartido o de bloqueo: un antivirus o el indexador tienen el archivo
            // abierto un instante; se reintenta unos milisegundos antes de rendirse)
            guard [5, 32, 33].contains(code), intento < 7 else { break }
            Thread.sleep(forTimeInterval: 0.03)
        }
        guard code == 0 else {
            throw NSError(domain: "NetDeck.SafeFile", code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey: "Windows error \(code) al sustituir \(url.lastPathComponent)"])
        }
        #else
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        #endif
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
            try SafeFile.replace(prev, with: tmp)
        } else {
            try fm.moveItem(at: tmp, to: prev)
        }
    }

    /// Escribe de forma atómica con permisos 0600 (sólo tú).
    public static func write(_ text: String, to url: URL) throws {
        #if os(Windows)
        // (misma razón que en `replace`: Windows rechaza un instante el renombrado si algo tiene el archivo abierto)
        for intento in 0..<5 {
            do { try Data(text.utf8).write(to: url, options: .atomic); break }
            catch { if intento == 4 { throw error }; Thread.sleep(forTimeInterval: 0.03) }
        }
        #else
        try Data(text.utf8).write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #if os(Windows)
        // El 0600 de Windows: ACL sólo para ti y SYSTEM, sin heredar la de la carpeta. Si el volumen no tiene ACL
        // (FAT, algunas unidades de red) no es un error: el archivo ya está escrito.
        WindowsACL.restrict(url, directory: false)
        #endif
    }
}
