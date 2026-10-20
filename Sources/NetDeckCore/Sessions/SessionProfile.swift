import Foundation

/// Una sesión de NetDeck: un «Host» del ssh_config (con sus anotaciones) o una conexión rápida.
public struct SessionProfile: Identifiable, Hashable, Sendable {
    /// Tipo de sesión. ssh y telnet llegan al equipo (directo o por salto); sftp es ssh por debajo (mismo alias, saltos y
    /// askpass); sftp y ftp se abren en el explorador de archivos de la app; serie, el puerto abierto por la app; local, la shell del Mac.
    public enum Transport: String, Sendable, Codable, CaseIterable {
        case ssh, telnet, sftp, ftp, serial, local

        /// Cómo se escribe en el ssh_config («# @tipo …»; telnet sigue siendo «# @telnet»).
        public var annotation: String { self == .serial ? "serie" : rawValue }

        public init?(annotation: String) {
            let a = annotation.trimmed.lowercased()
            guard let t = a == "serie" ? .serial : Self(rawValue: a) else { return nil }
            self = t
        }

        public var label: String {
            switch self {
            case .ssh: "SSH"
            case .telnet: "Telnet"
            case .sftp: "SFTP"
            case .ftp: "FTP"
            case .serial: L("Serie")
            case .local: L("Local")
            }
        }

        /// Llega a un equipo por red con usuario y equipo (los demás campos de conexión sobran).
        public var isNetwork: Bool { self != .serial && self != .local }
    }

    public var id: String { name }
    /// Alias del «Host».
    public var name: String
    public var hostName: String?
    public var user: String?
    public var port: Int?
    /// Saltos («ProxyJump»): alias del ssh_config o usuario@equipo[:puerto], en orden.
    public var proxyJump: [String]
    /// Tiene un ProxyCommand propio en el ssh_config (aunque se lea como salto): la app no lo sustituye por el suyo.
    public var hasProxyCommand = false
    public var transport: Transport
    /// «# @grupo X» (vale para las sesiones que vienen detrás).
    public var group: String?
    /// «# @desc …»
    public var summary: String?
    /// Contraseña con nombre del Llavero: «# @clave NOMBRE» o, si no, la del grupo («# @clave-grupo NOMBRE»).
    public var namedCredential: String?
    /// «# @antiguo»: equipo con algoritmos SSH antiguos.
    public var legacy: Bool
    /// «# @serie /dev/cu.… 9600 8N1» (sesiones de consola por puerto serie).
    public var serial: SerialLine?
    /// «# @fuente», «# @tema», «# @scrollback», «# @teclado», «# @prompt»: lo que no dice, de Ajustes.
    public var terminal = TerminalProfile()

    public init(name: String, hostName: String? = nil, user: String? = nil, port: Int? = nil,
                proxyJump: [String] = [], transport: Transport = .ssh, group: String? = nil,
                summary: String? = nil, namedCredential: String? = nil, legacy: Bool = false,
                serial: SerialLine? = nil) {
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
        self.serial = serial
    }

    public var endpoint: Endpoint { Endpoint(user: user, host: hostName ?? name, port: port) }

    /// Usuario con el que entra ssh: el de la sesión o, si no dice, el del Mac.
    public var effectiveUser: String { user ?? NSUserName() }
}
