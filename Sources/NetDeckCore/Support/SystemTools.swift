import Foundation

/// Los programas del sistema que lanza la app (OpenSSH y, en Windows, el cliente telnet).
public enum SystemTools {
    #if os(Windows)
    public static let ssh = locate("ssh")
    public static let sftp = locate("sftp")
    public static let scp = locate("scp")
    public static let sshKeygen = locate("ssh-keygen")
    /// El cliente Telnet de Windows (característica opcional: puede no estar). Siempre el de System32, nunca el PATH.
    public static let telnet = locate("telnet", subfolder: "", searchPath: false)

    // no verificado en Windows (sólo se compila allí; la lógica de `locateWindows` sí se prueba en el Mac)
    static func locate(_ name: String, subfolder: String = "OpenSSH", searchPath: Bool = true) -> String {
        locateWindows(name, subfolder: subfolder, searchPath: searchPath, environment: ProcessInfo.processInfo.environment,
                      exists: { FileManager.default.fileExists(atPath: $0) })
    }
    #else
    public static let ssh = "/usr/bin/ssh"
    public static let sftp = "/usr/bin/sftp"
    public static let scp = "/usr/bin/scp"
    public static let sshKeygen = "/usr/bin/ssh-keygen"
    #endif

    // (la lógica, sin #if: se prueba también en el Mac con `environment` y `exists` inyectados)

    /// Dónde está `name.exe` en Windows: `System32\<subfolder>` (OpenSSH desde Windows 10 1809; el cliente Telnet, en
    /// System32 a secas). Si no está ahí y `searchPath`, el primero del PATH que esté dentro de una carpeta de
    /// instalación del sistema (SystemRoot, Program Files…: Win32-OpenSSH, Git). Sólo un administrador escribe en ellas,
    /// así que un directorio del PATH al alcance de cualquier proceso del usuario (descargas, temporales…) no puede
    /// colar un ssh.exe que recibiría las contraseñas (en macOS la ruta está fijada). Tampoco se mira la carpeta actual
    /// (como «where»). Si no hay ninguno, la ruta de System32: quien la use dirá que no existe.
    static func locateWindows(_ name: String, subfolder: String, searchPath: Bool, environment: [String: String],
                              exists: (String) -> Bool) -> String {
        let env = Dictionary(environment.map { ($0.key.uppercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        func value(_ key: String) -> String? { env[key].flatMap { $0.isEmpty ? nil : $0 } }
        let root = value("SYSTEMROOT") ?? "C:\\Windows"
        let system = "\(root)\\System32\\" + (subfolder.isEmpty ? "" : subfolder + "\\") + "\(name).exe"
        if exists(system) || !searchPath { return system }
        let trusted = ([root] + ["PROGRAMFILES", "PROGRAMFILES(X86)", "PROGRAMW6432"].compactMap(value))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\\")).lowercased() + "\\" }
        for dir in (env["PATH"] ?? "").split(separator: ";") {
            let d = dir.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            guard d.count > 2, d.dropFirst().hasPrefix(":\\") else { continue }                 // (sólo absolutas con unidad)
            guard !d.split(whereSeparator: { $0 == "\\" || $0 == "/" }).contains("..") else { continue }
            let lower = d.lowercased() + (d.hasSuffix("\\") ? "" : "\\")
            guard trusted.contains(where: lower.hasPrefix) else { continue }
            let candidate = (d.hasSuffix("\\") ? d : d + "\\") + "\(name).exe"
            if exists(candidate) { return candidate }
        }
        return system
    }
}
