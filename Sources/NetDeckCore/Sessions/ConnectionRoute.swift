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
        return r
    }

    public var isLocal: Bool { localShell != nil }

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
        }
    }

    /// Orden que abre la pestaña. Telnet con salto: «ssh -t salto telnet equipo puerto» (transparente para el usuario).
    public var command: (executable: String, arguments: [String]) {
        if let localShell { return (Self.loginShell(localShell, allowed: Self.systemShells), ["-l"]) }
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
