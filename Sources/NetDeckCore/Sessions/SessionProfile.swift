import Foundation

/// Una sesión de NetDeck: un «Host» del ssh_config (con sus anotaciones) o una conexión rápida.
public struct SessionProfile: Identifiable, Hashable, Sendable {
    public enum Transport: String, Sendable, Codable, CaseIterable { case ssh, telnet }

    public var id: String { name }
    /// Alias del «Host».
    public var name: String
    public var hostName: String?
    public var user: String?
    public var port: Int?
    /// Saltos («ProxyJump»): alias del ssh_config o usuario@equipo[:puerto], en orden.
    public var proxyJump: [String]
    public var transport: Transport
    /// «# @grupo X» (vale para las sesiones que vienen detrás).
    public var group: String?
    /// «# @desc …»
    public var summary: String?
    /// Contraseña con nombre del Llavero: «# @clave NOMBRE» o, si no, la del grupo («# @clave-grupo NOMBRE»).
    public var namedCredential: String?
    /// «# @antiguo»: equipo con algoritmos SSH antiguos.
    public var legacy: Bool

    public init(name: String, hostName: String? = nil, user: String? = nil, port: Int? = nil,
                proxyJump: [String] = [], transport: Transport = .ssh, group: String? = nil,
                summary: String? = nil, namedCredential: String? = nil, legacy: Bool = false) {
        self.name = name
        self.hostName = hostName
        self.user = user
        self.port = port
        self.proxyJump = proxyJump
        self.transport = transport
        self.group = group
        self.summary = summary
        self.namedCredential = namedCredential
        self.legacy = legacy
    }

    public var endpoint: Endpoint { Endpoint(user: user, host: hostName ?? name, port: port) }

    /// Usuario con el que entra ssh: el de la sesión o, si no dice, el del Mac.
    public var effectiveUser: String { user ?? NSUserName() }
}
