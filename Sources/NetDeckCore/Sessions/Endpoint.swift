import Foundation

/// Un extremo de conexión: [usuario@]equipo[:puerto].
public struct Endpoint: Hashable, Sendable, Codable, CustomStringConvertible {
    public var user: String?
    public var host: String
    public var port: Int?

    public init(user: String? = nil, host: String, port: Int? = nil) {
        self.user = user
        self.host = host
        self.port = port
    }

    /// «admin@192.0.2.1:2222», «core-01», «admin@bastion». nil si no lo parece (vacío, una opción «-x», espacios…).
    public init?(parsing text: String) {
        var rest = Substring(text.trimmed)
        guard !rest.isEmpty, !rest.hasPrefix("-"), !rest.contains(where: \.isWhitespace) else { return nil }
        var user: String?
        if let at = rest.lastIndex(of: "@") {
            user = String(rest[..<at])
            rest = rest[rest.index(after: at)...]
            if user!.isEmpty { return nil }
        }
        var port: Int?
        if rest.filter({ $0 == ":" }).count == 1, let c = rest.firstIndex(of: ":") {   // (varios «:» = IPv6)
            guard let p = Int(rest[rest.index(after: c)...]), (1...65535).contains(p) else { return nil }
            port = p
            rest = rest[..<c]
        }
        guard !rest.isEmpty else { return nil }
        self.init(user: user, host: String(rest), port: port)
    }

    public var description: String {
        (user.map { "\($0)@" } ?? "") + host + (port.map { ":\($0)" } ?? "")
    }

    /// Seguro para escribirlo en la shell de un salto: nada de «;», «$(…)», espacios… (y sin empezar por «-»).
    public var isShellSafe: Bool {
        Self.safeHost.matches(host) && (user.map(Self.safeUser.matches) ?? true)
    }

    private static let safeUser = Pattern(#"^[A-Za-z0-9_][A-Za-z0-9_.-]*$"#, ignoreCase: false)
    private static let safeHost = Pattern(#"^[A-Za-z0-9][A-Za-z0-9_.:-]*$"#, ignoreCase: false)
}
