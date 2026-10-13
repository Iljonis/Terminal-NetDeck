import Foundation

/// Dónde guarda sus cosas la app (nada de contraseñas: ésas, sólo en el Llavero).
public enum AppPaths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// ~/Library/Application Support/Terminal NetDeck
    public static var support: URL {
        home.appendingPathComponent("Library/Application Support/Terminal NetDeck", isDirectory: true)
    }

    /// Temas instalados (uno por archivo .tema).
    public static var themes: URL { support.appendingPathComponent("Temas", isDirectory: true) }
    /// Marcas «probando»/«fallo» de cada contraseña, compartidas entre pestañas y el askpass.
    public static var marks: URL { support.appendingPathComponent("marcas", isDirectory: true) }
    /// Qué contraseña ha dado el askpass a cada pestaña (para confirmarla cuando entra).
    public static var sessions: URL { support.appendingPathComponent("sesiones", isDirectory: true) }

    /// NetDeck (bash + tmux), si está instalado: sus temas y ajustes se respetan.
    public static var netdeck: URL { home.appendingPathComponent(".config/netdeck", isDirectory: true) }

    @discardableResult
    public static func ensure(_ dir: URL) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir
    }

    /// «clave=valor» por línea (los .conf de NetDeck).
    public static func readConf(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let (k, _, v) = line.trimmed.partition("=")
            if !k.isEmpty { out[k] = v.trimmed }
        }
        return out
    }
}

extension String {
    func partition(_ sep: Character) -> (String, String, String) {
        guard let i = firstIndex(of: sep) else { return (self, "", "") }
        return (String(self[..<i]), String(sep), String(self[index(after: i)...]))
    }
}
