import CryptoKit
import Darwin
import Foundation

/// La conexión al último salto, compartida entre pestañas (como SecureCRT): la primera que entra por el bastión deja un
/// ControlMaster de ssh y las demás abren su canal por él sin volver a autenticarse. Queda abierta `persist` segundos
/// tras cerrar la última. El socket va en una carpeta tuya 0700 con una ruta corta (el socket Unix admite 104 bytes).
public struct JumpSharing: Hashable, Sendable {
    /// Carpeta de los sockets (sin «/» final).
    public var directory: String
    public var persist: Int

    public init(directory: String, persist: Int = 120) {
        self.directory = directory
        self.persist = persist
    }

    /// La de la app: «$TMPDIR/nd» (la carpeta temporal de macOS ya es sólo tuya). nil si no se puede crear o no es
    /// tuya y 0700 (entonces se conecta como siempre, sin compartir).
    public static func standard(base: String = NSTemporaryDirectory()) -> JumpSharing? {
        let dir = (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/nd"
        mkdir(dir, 0o700)
        var st = stat()
        guard lstat(dir, &st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid() else { return nil }
        if st.st_mode & 0o077 != 0, chmod(dir, 0o700) != 0 { return nil }
        let s = JumpSharing(directory: dir)
        return s.socket(for: ["x"]) == nil ? nil : s
    }

    /// Lo más largo que puede ser la ruta: ssh crea el socket como «ruta.XXXXXXXXXXXXXXXX» (17 más) y sun_path son 104
    /// bytes con el 0 final. Más largo, ssh se cerraría tras entrar en el salto: entonces no se comparte.
    public static let maxSocketPath = 104 - 1 - 17

    /// El socket de una cadena de saltos (los resueltos, «usuario@equipo:puerto»): el mismo para ssh, sftp y telnet por
    /// ese salto. nil si la ruta no cabe o tiene algo que ssh o la shell interpretarían («%», «~», espacios…).
    public func socket(for chain: [String]) -> String? {
        let h = SHA256.hash(data: Data(chain.joined(separator: ",").utf8))
        let path = directory + "/" + h.prefix(8).map { String(format: "%02x", $0) }.joined()
        guard path.utf8.count <= Self.maxSocketPath, Self.safePath.matches(path) else { return nil }
        return path
    }

    /// Opciones de ssh para ser (o usar) el ControlMaster de `socket`.
    public func options(socket: String) -> [String] {
        ["-o", "ControlMaster=auto", "-o", "ControlPath=\(socket)", "-o", "ControlPersist=\(persist)"]
    }

    /// El ProxyCommand que sustituye a «-J a,b,c»: «/usr/bin/ssh <multiplexado> -J a,b [-l u] [-p n] -W '[%h]:%p' -- c».
    /// ssh lo pasa por tu shell ($SHELL -c): sólo se genera si cada salto es seguro para cualquier shell (sin comillas,
    /// «;», «$(…)», «%»…) y nada empieza por «-». nil = se usa -J como siempre. `configFile`: el ssh_config propio
    /// («-F»; también tiene que ser una ruta segura para la shell, si no se usa -J, al que ssh ya se lo pasa).
    public func proxyCommand(hops: [String], socket: String, configFile: String? = nil) -> String? {
        let parsed = hops.compactMap(Endpoint.init(parsing:))
        guard let last = parsed.last, parsed.count == hops.count,
              parsed.allSatisfy({ $0.isShellSafe && !$0.host.contains(":") }),      // (IPv6 en -J: sin multiplexar)
              Self.safePath.matches(socket), configFile.map(Self.safePath.matches) ?? true else { return nil }
        var a = ["/usr/bin/ssh"] + ConnectionRoute.configOptions(configFile) + options(socket: socket)
        if parsed.count > 1 { a += ["-J", parsed.dropLast().map(\.description).joined(separator: ",")] }
        if let u = last.user { a += ["-l", u] }
        if let p = last.port { a += ["-p", String(p)] }
        return (a + ["-W", "'[%h]:%p'", "--", last.host]).joined(separator: " ")
    }

    /// Rutas sin nada que expandan ssh («%», «~», «${}») o la shell; ni empezar por «-».
    static let safePath = Pattern(#"^/[A-Za-z0-9_./-]+\z"#, ignoreCase: false)
}
