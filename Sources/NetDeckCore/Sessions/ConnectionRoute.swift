import Foundation

/// Cómo se llega a un equipo: los saltos resueltos y la orden que abre la pestaña.
public struct ConnectionRoute: Hashable, Sendable, Codable {
    public var title: String
    public var target: Endpoint
    /// Saltos resueltos (usuario@equipo:puerto), del primero al último.
    public var jumps: [Endpoint]
    public var transport: SessionProfile.Transport
    /// Alias del ssh_config, si viene de una sesión: ssh lo lee todo de ahí (claves, algoritmos, ProxyJump…).
    public var alias: String?
    /// «-J» explícito (accesos directos de salto); nil = lo que diga el ssh_config.
    public var jumpSpec: [String]?
    /// Sesión de la que sale (para la contraseña con nombre).
    public var sessionName: String?
    /// Salto «a mano»: al salir el prompt del salto se escribe esta orden («ssh admin@core-01»).
    /// Así vale aunque el salto no deje reenviar puertos (-J da «administratively prohibited»).
    public var thenCommand: String?
    /// Usuario de esa orden (para la regla de la contraseña del equipo).
    public var thenUser: String?
    /// Terminal local: la shell de inicio del Mac (sin ssh, sin askpass ni contraseñas automáticas). nil = remota.
    public var localShell: String?
    /// Sesión de consola por puerto serie (transport .serial).
    public var serial: SerialLine?

    public init(title: String, target: Endpoint, jumps: [Endpoint] = [], transport: SessionProfile.Transport = .ssh,
                alias: String? = nil, jumpSpec: [String]? = nil, sessionName: String? = nil) {
        self.title = title
        self.target = target
        self.jumps = jumps
        self.transport = transport
        self.alias = alias
        self.jumpSpec = jumpSpec
        self.sessionName = sessionName
    }

    /// Terminal local: `shell` (si no, `$SHELL`; si no está en /etc/shells, /bin/zsh) como shell de login, en tu carpeta.
    public static func local(shell: String? = ProcessInfo.processInfo.environment["SHELL"],
                             allowed: [String] = ConnectionRoute.systemShells) -> ConnectionRoute {
        var r = ConnectionRoute(title: L("Terminal local"), target: Endpoint(user: NSUserName(), host: "localhost"))
        r.localShell = loginShell(shell, allowed: allowed)
        r.transport = .local
        return r
    }

    /// Consola por puerto serie (screen); no es un equipo de red.
    public static func serial(_ line: SerialLine, title: String, sessionName: String? = nil) -> ConnectionRoute {
        var r = ConnectionRoute(title: title, target: Endpoint(host: line.device), transport: .serial, sessionName: sessionName)
        r.serial = line
        return r
    }

    public var isLocal: Bool { localShell != nil || transport == .local }

    /// MultiExec sólo escribe en equipos (ssh/telnet): ni en el Mac, ni en el prompt de sftp, ni en una consola serie.
    public var acceptsMultiExec: Bool { !isLocal && (transport == .ssh || transport == .telnet) }

    /// Askpass y contraseñas automáticas: sólo lo que pide la contraseña de un equipo (ssh, telnet y sftp, que es ssh).
    public var usesPasswords: Bool { !isLocal && transport != .serial && transport != .ftp }

    /// «ftp://usuario@equipo:puerto» (para abrirlo también en el Finder, sólo lectura). nil si no es FTP o el equipo
    /// no es válido.
    public var ftpURL: URL? {
        guard transport == .ftp, Endpoint(user: target.user, host: target.host).isShellSafe else { return nil }
        var c = URLComponents()
        c.scheme = "ftp"
        c.host = target.host
        c.user = target.user
        c.port = target.port == 21 ? nil : target.port
        return c.url
    }

    /// El explorador de archivos de una pestaña SFTP: ssh sin terminal con el subsistema «sftp» (mismo alias del
    /// ssh_config, saltos, puerto y usuario que la consola), sin reenvíos ni orden local. nil si no es SFTP.
    public var sftpSubsystemCommand: (executable: String, arguments: [String])? {
        guard transport == .sftp, !isLocal else { return nil }
        var a = ["-T", "-x", "-a", "-o", "ClearAllForwardings=yes", "-o", "PermitLocalCommand=no", "-o", "RequestTTY=no",
                 "-o", "BatchMode=no", "-o", "RemoteCommand=none", "-s"]
        if let j = jumpSpec, !j.isEmpty { a += ["-J", j.joined(separator: ",")] }
        if let alias {
            a.append(alias)
        } else {
            if let p = target.port { a += ["-p", String(p)] }
            if let u = target.user { a += ["-l", u] }
            a.append(target.host)
        }
        return ("/usr/bin/ssh", a + ["sftp"])
    }

    /// Por qué no se puede abrir la pestaña (falta el programa o el puerto serie), o nil. `exists`: para los tests.
    public func launchProblem(exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        if transport == .serial {
            let dev = serial?.device ?? ""
            guard let s = serial, s.isValid else { return L("Puerto serie no válido: «\(dev)»") }
            if !exists(SerialLine.screen) { return L("No está /usr/bin/screen en este Mac: hace falta para el puerto serie") }
            if !exists(s.device) { return L("No está «\(s.device)»: ¿está conectado el adaptador USB-serie?") }
            return nil
        }
        if transport == .ftp { return L("FTP no tiene consola: usa la vista gráfica") }
        let exe = command.executable
        return exists(exe) ? nil : L("No está \(exe) en este Mac")
    }

    /// Las shells de /etc/shells (las que macOS deja como shell de inicio).
    public static var systemShells: [String] {
        ((try? String(contentsOfFile: "/etc/shells", encoding: .utf8)) ?? "").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("/") }
    }

    /// La shell si es una de las permitidas (la ruta guardada en abiertas.json no se ejecuta a ciegas); si no, /bin/zsh.
    public static func loginShell(_ shell: String?, allowed: [String]) -> String {
        guard let shell, allowed.contains(shell) else { return "/bin/zsh" }
        return shell
    }

    /// Directa a este mismo Mac (127.x, ::1, localhost): no se guarda para reabrirla al arrancar (sería un ssh al
    /// puerto 22 local que normalmente rechaza la conexión). La terminal local no cuenta: no es un ssh.
    public var isLoopback: Bool {
        guard jumps.isEmpty, localShell == nil else { return false }
        let h = target.host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return h == "localhost" || h == "::1" || h.hasPrefix("127.")
    }

    /// Orden que se escribe en el salto para llegar a `device` (nil si no es seguro escribirlo en una shell).
    public static func hopCommand(to device: Endpoint, transport: SessionProfile.Transport) -> String? {
        guard device.isShellSafe else { return nil }
        switch transport {
        case .ssh:
            let dest = Endpoint(user: device.user, host: device.host).description
            return device.port.map { "ssh -p \($0) \(dest)" } ?? "ssh \(dest)"
        case .telnet:
            return "telnet \(device.host)" + (device.port.map { " \($0)" } ?? "")
        case .sftp, .ftp, .serial, .local:
            return nil
        }
    }

    /// Orden que abre la pestaña. Telnet con salto: «ssh -t salto telnet equipo puerto» (transparente para el usuario).
    /// sftp: como ssh (alias del ssh_config o -P/-J usuario@equipo). Serie: screen. FTP no tiene consola (/usr/bin/false):
    /// su pestaña es sólo el explorador.
    public var command: (executable: String, arguments: [String]) {
        if isLocal { return (Self.loginShell(localShell, allowed: Self.systemShells), ["-l"]) }
        switch transport {
        case .ssh:
            var a: [String] = []
            if let j = jumpSpec, !j.isEmpty { a += ["-J", j.joined(separator: ",")] }
            if let alias {
                a.append(alias)
            } else {
                if let p = target.port { a += ["-p", String(p)] }
                if let u = target.user { a += ["-l", u] }
                a.append(target.host)
            }
            return ("/usr/bin/ssh", a)
        case .telnet:
            let telnet = [target.host] + (target.port.map { [String($0)] } ?? [])
            guard let last = jumps.last else { return ("/usr/bin/env", ["telnet"] + telnet) }
            var a = ["-t"]
            if jumps.count > 1 { a += ["-J", jumps.dropLast().map(\.description).joined(separator: ",")] }
            return ("/usr/bin/ssh", a + [last.description, "telnet"] + telnet)
        case .sftp:
            var a: [String] = []
            if let j = jumpSpec, !j.isEmpty { a += ["-J", j.joined(separator: ",")] }
            if let alias {
                a.append(alias)
            } else {
                if let p = target.port { a += ["-P", String(p)] }
                let h = target.host.contains(":") ? "[\(target.host)]" : target.host       // (IPv6)
                a.append((target.user.map { "\($0)@" } ?? "") + h)
            }
            return ("/usr/bin/sftp", a)
        case .serial:
            guard let s = serial, s.isValid else { return ("/usr/bin/false", []) }
            return (SerialLine.screen, s.screenArguments)
        case .ftp, .local:
            return ("/usr/bin/false", [])
        }
    }
}

public enum RouteError: LocalizedError, Equatable {
    case loop(String)
    case badJump(String)
    case badDevice(String)

    public var errorDescription: String? {
        switch self {
        case .loop(let s): L("Los saltos de «\(s)» forman un bucle")
        case .badJump(let s): L("Salto no válido: «\(s)»")
        case .badDevice(let s): L("Equipo no válido: «\(s)»")
        }
    }
}
