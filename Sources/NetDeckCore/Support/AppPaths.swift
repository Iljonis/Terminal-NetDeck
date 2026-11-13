import Foundation

/// Dónde guarda sus cosas la app (nada de contraseñas: ésas, sólo en el Llavero).
public enum AppPaths {
    /// La carpeta personal. Desarrollo: NETDECK_HOME=/otra/carpeta (capturas con datos de ejemplo, sin tocar los tuyos).
    public static var home: URL {
        if let h = ProcessInfo.processInfo.environment["NETDECK_HOME"], !h.isEmpty { return URL(fileURLWithPath: h, isDirectory: true) }
        if underTests { return testHome }
        #if os(Windows)
        // %USERPROFILE% (C:\Users\tú); si faltara, lo que diga Foundation.
        if let h = ProcessInfo.processInfo.environment["USERPROFILE"], !h.isEmpty { return URL(fileURLWithPath: h, isDirectory: true) }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Los tests sin NETDECK_HOME (`swift test` a mano, sin ./test.sh): ni sus registros ni sus archivos van a los tuyos.
    static let underTests: Bool = {
        let p = ProcessInfo.processInfo
        #if os(Windows)
        // En Windows el proceso de los tests es «<Target>-test-runner.exe» (SwiftPM con Swift Build) o
        // «<Paquete>PackageTests.xctest» (SwiftPM clásico); el nombre llega con o sin «.exe» y sin mayúsculas fijas.
        let nombres = [p.processName, URL(fileURLWithPath: CommandLine.arguments.first ?? "").lastPathComponent].map { n -> String in
            let n = n.lowercased()
            return n.hasSuffix(".exe") ? String(n.dropLast(4)) : n
        }
        if nombres.contains(where: { $0.hasSuffix("-test-runner") || $0.hasSuffix(".xctest") || $0.hasSuffix("packagetests")
                                     || $0 == "xctest" || $0 == "swiftpm-testing-helper" }) { return true }
        #endif
        return ["xctest", "swiftpm-testing-helper"].contains(p.processName)
            || p.environment["XCTestConfigurationFilePath"] != nil || p.environment["XCTestSessionIdentifier"] != nil
    }()
    private static let testHome = FileManager.default.temporaryDirectory
        #if os(Windows)
        .appendingPathComponent("netdeck-pruebas-\(_getpid())", isDirectory: true)
        #else
        .appendingPathComponent("netdeck-pruebas-\(getpid())", isDirectory: true)
        #endif

    /// Tu usuario del Mac para enseñarlo (usuario por defecto de una sesión, del explorador…). En una captura
    /// (NETDECK_SNAPSHOT), «tu.usuario»: así no sale el tuyo en las imágenes que se publican.
    public static var userName: String {
        ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] != nil ? "tu.usuario" : NSUserName()
    }

    /// ~/Library/Application Support/Terminal NetDeck
    /// Una ruta para enseñarla: la carpeta personal (la real y la de NETDECK_HOME) como «~».
    public static func tilde(_ path: String) -> String {
        #if os(Windows)
        // «C:\Users\tú\…» y «C:/Users/tú/…» son la misma carpeta, y Windows no distingue mayúsculas de minúsculas.
        func igual(_ a: Character, _ b: Character) -> Bool {
            (a == "\\" ? "/" : a.lowercased()) == (b == "\\" ? "/" : b.lowercased())
        }
        let casas = [home.path, ProcessInfo.processInfo.environment["USERPROFILE"] ?? "", NSHomeDirectory()]
        for h in casas where !h.isEmpty && path.count >= h.count && zip(path, h).allSatisfy(igual) {
            let resto = path.dropFirst(h.count)
            // (carpeta completa: el prefijo ha de terminar en separador o el resto empezar con uno)
            if resto.isEmpty || resto.first == "/" || resto.first == "\\" || h.last == "/" || h.last == "\\" { return "~" + resto }
        }
        return path
        #else
        var p = path
        for h in [home.path, NSHomeDirectory()] where !h.isEmpty && p.hasPrefix(h) { p = "~" + p.dropFirst(h.count) }
        return p
        #endif
    }

    /// «~/…» con la carpeta personal de la app (también la de NETDECK_HOME).
    public static func expand(_ path: String) -> String {
        #if os(Windows)
        // (también «~\…», como se escribe en Windows)
        return path == "~" ? home.path
            : path.hasPrefix("~/") || path.hasPrefix("~\\") ? home.appendingPathComponent(String(path.dropFirst(2))).path
            : (path as NSString).expandingTildeInPath
        #else
        path == "~" ? home.path : path.hasPrefix("~/") ? home.appendingPathComponent(String(path.dropFirst(2))).path
                                                     : (path as NSString).expandingTildeInPath
        #endif
    }

    public static var support: URL {
        #if os(Windows)
        // %APPDATA%\Terminal NetDeck. Con otra carpeta personal (NETDECK_HOME, los tests), dentro de ella: nunca en la tuya.
        let env = ProcessInfo.processInfo.environment
        if (env["NETDECK_HOME"] ?? "").isEmpty, !underTests, let a = env["APPDATA"], !a.isEmpty {
            return URL(fileURLWithPath: a, isDirectory: true).appendingPathComponent("Terminal NetDeck", isDirectory: true)
        }
        return home.appendingPathComponent("AppData/Roaming/Terminal NetDeck", isDirectory: true)
        #else
        home.appendingPathComponent("Library/Application Support/Terminal NetDeck", isDirectory: true)
        #endif
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
        // (también si ya existía con otros permisos: sólo tú)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        #if os(Windows)
        // El 0700 de Windows: ACL sólo para ti y SYSTEM, que heredan los archivos que se creen dentro.
        WindowsACL.restrict(dir, directory: true)
        #endif
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
