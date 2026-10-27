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
    /// Alta sin sustituir una entrada existente (el Llavero lo comprueba de forma atómica).
    func create(_ password: String, for ref: CredentialRef) throws
    func delete(_ ref: CredentialRef) throws
    func accounts(in service: CredentialRef.Service) throws -> [String]
}

extension CredentialStore {
    public func create(_ password: String, for ref: CredentialRef) throws {
        guard !contains(ref) else { throw KeychainError(message: L("Ya existe una contraseña con ese nombre o cuenta")) }
        try save(password, for: ref)
    }

    /// Sólo los metadatos de las dos clases de contraseñas, sin leer ningún secreto.
    public func accountsInBackground() async throws -> [CredentialRef] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let named = try self.accounts(in: .named).map(CredentialRef.named)
                    let devices = try self.accounts(in: .device).map { CredentialRef(service: .device, account: $0) }
                    continuation.resume(returning: named + devices)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func createInBackground(_ password: String, for ref: CredentialRef) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do { try self.create(password, for: ref); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    /// Fuera del hilo principal: `security` puede tardar (o esperar a que se desbloquee el Llavero) y la ventana no se
    /// debe congelar. Un error del Llavero cuenta como «no está» (igual que `try?`).
    public func passwordInBackground(for ref: CredentialRef) async -> String? {
        // (una vacía cuenta como «no está»: escribirla sería un fallo más en la cuenta)
        await withCheckedContinuation { continuation in
            // (el Llavero es síncrono y puede bloquear: no debe ocupar el pool cooperativo de Swift)
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: (try? self.password(for: ref)).flatMap { $0.isEmpty ? nil : $0 })
            }
        }
    }

    /// Las candidatas que están en el Llavero (sin leer su secreto), también fuera del hilo principal: comprobar si
    /// existe puede esperar igual al servicio del Llavero.
    public func availableInBackground(_ candidates: [CredentialCandidate]) async -> [CredentialCandidate] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: candidates.filter { self.contains($0.ref) })
            }
        }
    }

    public func saveInBackground(_ password: String, for ref: CredentialRef) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.save(password, for: ref)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func deleteInBackground(_ ref: CredentialRef) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.delete(ref)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
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
    public func create(_ password: String, for ref: CredentialRef) throws {
        try lock.withLock {
            guard items[ref] == nil else { throw KeychainError(message: L("Ya existe una contraseña con ese nombre o cuenta")) }
            items[ref] = password
        }
    }
    public func delete(_ ref: CredentialRef) throws { _ = lock.withLock { items.removeValue(forKey: ref) } }
    public func accounts(in service: CredentialRef.Service) throws -> [String] {
        lock.withLock { items.keys.filter { $0.service == service }.map(\.account).sorted() }
    }
}
