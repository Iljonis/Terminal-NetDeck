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

extension CredentialStore {
    /// Fuera del hilo principal: `security` puede tardar (o esperar a que se desbloquee el Llavero) y la ventana no se
    /// debe congelar. Un error del Llavero cuenta como «no está» (igual que `try?`).
    public func passwordInBackground(for ref: CredentialRef) async -> String? {
        // (una vacía cuenta como «no está»: escribirla sería un fallo más en la cuenta)
        await Task.detached { (try? self.password(for: ref)).flatMap { $0.isEmpty ? nil : $0 } }.value
    }

    /// Las candidatas que están en el Llavero (sin leer su secreto), también fuera del hilo principal: comprobar si
    /// existe puede esperar igual al servicio del Llavero.
    public func availableInBackground(_ candidates: [CredentialCandidate]) async -> [CredentialCandidate] {
        await Task.detached { candidates.filter { self.contains($0.ref) } }.value
    }

    public func saveInBackground(_ password: String, for ref: CredentialRef) async throws {
        try await Task.detached { try self.save(password, for: ref) }.value
    }

    public func deleteInBackground(_ ref: CredentialRef) async throws {
        try await Task.detached { try self.delete(ref) }.value
    }
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
