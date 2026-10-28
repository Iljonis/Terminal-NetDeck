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
    /// ¿Existe? (sin leer el secreto: no pide permiso al Llavero). Un error cuenta como «no».
    func contains(_ ref: CredentialRef) -> Bool
    /// ¿Existe?, distinguiendo «no está» (false) de «no se ha podido mirar» (lanza: Llavero bloqueado, sin respuesta…).
    func exists(_ ref: CredentialRef) throws -> Bool
    func save(_ password: String, for ref: CredentialRef) throws
    /// Alta sin sustituir una entrada existente (el Llavero lo comprueba de forma atómica).
    func create(_ password: String, for ref: CredentialRef) throws
    func delete(_ ref: CredentialRef) throws
    func accounts(in service: CredentialRef.Service) throws -> [String]
}

/// Lo leído del Llavero: la contraseña, que no está o que no se ha podido leer (bloqueado, sin respuesta…).
public enum CredentialRead: Equatable, Sendable {
    case found(String)
    case missing
    case failed

    public var password: String? { if case .found(let pw) = self { pw } else { nil } }
}

extension CredentialStore {
    public func exists(_ ref: CredentialRef) throws -> Bool { contains(ref) }

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
        await readInBackground(ref).password
    }

    /// Igual, pero distingue «no está» de «no se ha podido leer» (el error no se convierte en una ausencia).
    public func readInBackground(_ ref: CredentialRef) async -> CredentialRead {
        // (una vacía cuenta como «no está»: escribirla sería un fallo más en la cuenta)
        await withCheckedContinuation { continuation in
            // (el Llavero es síncrono y puede bloquear: no debe ocupar el pool cooperativo de Swift)
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.read(ref))
            }
        }
    }

    /// Síncrona (el askpass, que no tiene interfaz que congelar).
    public func read(_ ref: CredentialRef) -> CredentialRead {
        do {
            guard let pw = try password(for: ref), !pw.isEmpty else { return .missing }
            return .found(pw)
        } catch {
            DebugLog.log("llavero", "no se ha podido leer «\(ref)»")
            return .failed
        }
    }

    /// Las candidatas que están en el Llavero (sin leer su secreto), también fuera del hilo principal: comprobar si
    /// existe puede esperar igual al servicio del Llavero.
    public func availableInBackground(_ candidates: [CredentialCandidate]) async -> [CredentialCandidate] {
        await availabilityInBackground(candidates).available
    }

    /// Igual, y si alguna no se ha podido comprobar (`failed`: entonces su ausencia no es segura).
    public func availabilityInBackground(_ candidates: [CredentialCandidate]) async -> (available: [CredentialCandidate], failed: Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.availability(candidates))
            }
        }
    }

    public func availability(_ candidates: [CredentialCandidate]) -> (available: [CredentialCandidate], failed: Bool) {
        var failed = false
        let available = candidates.filter { c in
            do { return try self.exists(c.ref) } catch {
                DebugLog.log("llavero", "no se ha podido comprobar «\(c.ref)»: \(error.localizedDescription)")
                failed = true
                return false
            }
        }
        return (available, failed)
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
