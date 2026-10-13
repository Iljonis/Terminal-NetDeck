import Foundation

/// Una contraseña del Llavero, con los mismos servicios que NetDeck (las ya guardadas con «pw» sirven tal cual):
///   netdeck-ssh  cuenta usuario@equipo (la de una sesión)
///   netdeck      cuenta = el nombre (contraseñas con nombre: «AD», las de los botones…)
public struct CredentialRef: Hashable, Sendable, CustomStringConvertible {
    public enum Service: String, Sendable { case device = "netdeck-ssh", named = "netdeck" }

    public var service: Service
    public var account: String

    public init(service: Service, account: String) {
        self.service = service
        self.account = account
    }

    public static func device(_ user: String, _ host: String) -> Self { .init(service: .device, account: "\(user)@\(host)") }
    public static func named(_ name: String) -> Self { .init(service: .named, account: name) }

    public var description: String { account }
}

/// La contraseña «por defecto» y el usuario al que pertenece (sólo se escribe sola para ese usuario).
public struct DefaultCredential: Codable, Hashable, Sendable {
    public var name: String
    public var user: String

    public init(name: String, user: String) {
        self.name = name
        self.user = user
    }
}

public protocol CredentialStore: Sendable {
    func password(for ref: CredentialRef) throws -> String?
    /// ¿Existe? (sin leer el secreto: no pide permiso al Llavero)
    func contains(_ ref: CredentialRef) -> Bool
    func save(_ password: String, for ref: CredentialRef) throws
    func delete(_ ref: CredentialRef) throws
    func accounts(in service: CredentialRef.Service) throws -> [String]
}

/// En memoria: tests y modo demostración.
public final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CredentialRef: String]

    public init(_ items: [CredentialRef: String] = [:]) {
        self.items = items
    }

    public func password(for ref: CredentialRef) throws -> String? { lock.withLock { items[ref] } }
    public func contains(_ ref: CredentialRef) -> Bool { lock.withLock { items[ref] != nil } }
    public func save(_ password: String, for ref: CredentialRef) throws { lock.withLock { items[ref] = password } }
    public func delete(_ ref: CredentialRef) throws { _ = lock.withLock { items.removeValue(forKey: ref) } }
    public func accounts(in service: CredentialRef.Service) throws -> [String] {
        lock.withLock { items.keys.filter { $0.service == service }.map(\.account).sorted() }
    }
}
