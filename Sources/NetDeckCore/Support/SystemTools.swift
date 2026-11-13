import Foundation

/// Los programas del sistema que lanza la app (OpenSSH).
public enum SystemTools {
    #if os(Windows)
    public static let ssh = locate("ssh")
    public static let sftp = locate("sftp")
    public static let scp = locate("scp")
    public static let sshKeygen = locate("ssh-keygen")

    /// El OpenSSH que trae Windows (System32\OpenSSH, desde Windows 10 1809); si no está, el primero del PATH (como
    /// «where», pero sin mirar la carpeta actual: no se ejecuta un ssh.exe que alguien haya dejado en ella). Si no
    /// hay ninguno, la ruta del sistema: quien la use dirá que no existe.
    static func locate(_ name: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                       exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        let env = Dictionary(environment.map { ($0.key.uppercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        let root = env["SYSTEMROOT"].flatMap { $0.isEmpty ? nil : $0 } ?? "C:\\Windows"
        let system = "\(root)\\System32\\OpenSSH\\\(name).exe"
        if exists(system) { return system }
        for dir in (env["PATH"] ?? "").split(separator: ";") {
            let d = dir.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            guard d.count > 2, d.dropFirst().hasPrefix(":\\") || d.hasPrefix("\\\\") else { continue }     // (sólo absolutas)
            let candidate = (d.hasSuffix("\\") ? d : d + "\\") + "\(name).exe"
            if exists(candidate) { return candidate }
        }
        return system
    }
    #else
    public static let ssh = "/usr/bin/ssh"
    public static let sftp = "/usr/bin/sftp"
    public static let scp = "/usr/bin/scp"
    public static let sshKeygen = "/usr/bin/ssh-keygen"
    #endif
}
