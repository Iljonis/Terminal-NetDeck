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
    /// Salto «a mano» (como NetDeck): al salir el prompt del salto se escribe esta orden («ssh admin@core-01»).
    /// Así vale aunque el salto no deje reenviar puertos (-J da «administratively prohibited»).
    public var thenCommand: String?
    /// Usuario de esa orden (para la regla de la contraseña del equipo).
    public var thenUser: String?

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
