import CryptoKit
import Darwin
import Foundation

/// Estado de cada contraseña entre todas las pestañas y el askpass, para no bloquear cuentas AD:
///  · probando: alguien la acaba de escribir; los demás esperan a ver si vale (TACACS/RADIUS lentos)
///  · fallo: no ha valido; no se vuelve a escribir sola en ningún sitio durante `blockWindow` (15 min)
///  · confirmada: ha entrado; los demás pueden usarla ya
public final class CredentialLedger: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case probing(since: Date, owner: Int32 = ProcessInfo.processInfo.processIdentifier, reservation: UUID? = nil)
        case failed(at: Date)
        case confirmed(at: Date)
    }

    public enum Probe: Equatable, Sendable { case go, wait, blocked }

    public var blockWindow: TimeInterval = 15 * 60
    /// Una marca «probando» sin propietario (las de la versión anterior no llevan PID) caduca a los 8 s, como entonces.
    public var probeWindow: TimeInterval = 8
    /// Una reserva de la app (listas, login anidado) dura lo que su proceso y, como mucho, esto: un login cuyo final no
    /// se reconoce (un «# @prompt» propio, un banner…) no deja la contraseña pendiente horas en las demás pestañas.
    public var reservationLimit: TimeInterval = 120
    private let storage: LedgerStorage
    private let now: @Sendable () -> Date
    private let processID: Int32
    private let processAlive: @Sendable (Int32) -> Bool

    public init(storage: LedgerStorage = MemoryLedgerStorage(), now: @escaping @Sendable () -> Date = { Date() },
                processID: Int32 = ProcessInfo.processInfo.processIdentifier,
                processAlive: @escaping @Sendable (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) {
        self.storage = storage
        self.now = now
        self.processID = processID
        self.processAlive = processAlive
    }

    /// La de verdad: compartida con el askpass y las demás ventanas (~/Library/Application Support/…/marcas).
    public static func shared() -> CredentialLedger {
        CredentialLedger(storage: DirectoryLedgerStorage(AppPaths.ensure(AppPaths.marks)))
    }

    public func state(of ref: CredentialRef) -> State? { storage.locked { current(ref) } }

    public func isBlocked(_ ref: CredentialRef) -> Bool {
        if case .failed = state(of: ref) { return true }
        return false
    }

    /// ¿Se puede escribir ya? `.go` la deja «probando» (los demás esperan); `.wait`: otro la está probando.
    public func beginProbe(_ ref: CredentialRef) -> Probe { reserveProbe(ref).result }

    /// El token permite cancelar un intento sin quitar la reserva de otra pestaña tras un cambio manual.
    public func reserveProbe(_ ref: CredentialRef) -> (result: Probe, token: UUID?) {
        storage.locked {
            switch current(ref) {
            case .failed: return (.blocked, nil)
            case .probing: return (.wait, nil)
            case .confirmed, nil:
                let token = UUID()
                storage.write(ref, .probing(since: now(), owner: processID, reservation: token))
                return (.go, token)
            }
        }
    }

    /// Sigue probándose (un servidor lento): que los demás no se cansen de esperar.
    public func keepProbing(_ ref: CredentialRef) {
        storage.locked {
            if case .probing(_, let owner, let token) = current(ref) {
                storage.write(ref, .probing(since: now(), owner: owner, reservation: token))
            }
        }
    }

    public func markFailed(_ ref: CredentialRef) { storage.locked { storage.write(ref, .failed(at: now())) } }

    /// El rechazo de un intento hecho en `attempt` (el askpass al repreguntar, ssh al terminar…). Si después la has
    /// restablecido (guardada otra vez, desbloqueada), era de la anterior y no bloquea la de ahora. true = bloqueada.
    /// (con un segundo de margen: la hora suele ser la de un archivo, que no cuadra al milisegundo con el reloj; ante
    /// la duda, se bloquea)
    @discardableResult
    public func markFailed(_ ref: CredentialRef, attemptedAt attempt: Date) -> Bool {
        storage.locked {
            if let r = storage.lastReset(ref), attempt < r.addingTimeInterval(-1) { return false }
            storage.write(ref, .failed(at: now()))
            return true
        }
    }

    /// Una respuesta antigua no resuelve la reserva creada después de cambiar o cancelar la contraseña.
    public func markFailed(_ ref: CredentialRef, reservation token: UUID) {
        storage.locked {
            guard case .probing(_, _, let currentToken) = current(ref), currentToken == token else { return }
            storage.write(ref, .failed(at: now()))
        }
    }
    /// Ha valido. Pero si está marcada como fallida (otra pestaña, o ésta antes de que la escribieras a mano), el fallo
    /// manda: sólo `reset` (la has cambiado o la eliges tú) lo quita. Así ninguna confirmación levanta el bloqueo de
    /// 15 min que protege las cuentas de AD.
    public func confirm(_ ref: CredentialRef) {
        storage.locked {
            if case .failed = current(ref) { return }
            storage.write(ref, .confirmed(at: now()))
        }
    }

    public func confirm(_ ref: CredentialRef, reservation token: UUID) {
        storage.locked {
            guard case .probing(_, _, let currentToken) = current(ref), currentToken == token else { return }
            storage.write(ref, .confirmed(at: now()))
        }
    }

    /// El login inicial no reserva credenciales: su éxito no debe quitar una reserva de un equipo anidado.
    public func confirmDirect(_ ref: CredentialRef) {
        storage.locked {
            switch current(ref) {
            case .failed, .probing: return
            case .confirmed, nil: storage.write(ref, .confirmed(at: now()))
            }
        }
    }

    /// No se supo si valía (el equipo no contestó por otra cosa): la contraseña no tiene la culpa.
    public func release(_ ref: CredentialRef) {
        storage.locked { if case .probing = storage.read(ref) { storage.write(ref, nil) } }
    }

    public func release(_ ref: CredentialRef, reservation token: UUID) {
        storage.locked {
            if case .probing(_, _, let ownerToken) = storage.read(ref), ownerToken == token { storage.write(ref, nil) }
        }
    }

    /// La has cambiado o la eliges a mano: se olvida el fallo y se apunta cuándo (también para el askpass, otro
    /// proceso): un rechazo tardío de un intento de antes no bloquea la recién guardada.
    public func reset(_ ref: CredentialRef) {
        storage.locked {
            storage.write(ref, nil)
            storage.noteReset(ref, at: now())
        }
    }

    private func current(_ ref: CredentialRef) -> State? {
        let s = storage.read(ref)
        switch s {
        case .probing(let since, let owner, _) where expired(since: since, owner: owner):
            storage.write(ref, nil)
            return nil
        case .failed(let t) where now().timeIntervalSince(t) > blockWindow:
            storage.write(ref, nil)
            return nil
        default:
            return s
        }
    }

    /// (el reloj de la interfaz no prueba que ssh haya terminado: una reserva de la app vale mientras viva su proceso,
    /// con `reservationLimit` de tope. Una sin propietario es de la versión anterior y caduca como entonces)
    private func expired(since: Date, owner: Int32) -> Bool {
        let age = now().timeIntervalSince(since)
        if owner <= 0 { return age > probeWindow }
        return !processAlive(owner) || age > reservationLimit
    }
}

public protocol LedgerStorage: AnyObject, Sendable {
    func read(_ ref: CredentialRef) -> CredentialLedger.State?
    func write(_ ref: CredentialRef, _ state: CredentialLedger.State?)
    /// El último «restablecer» de esa contraseña (sólo la hora, nunca un secreto); sobrevive a los cambios de estado.
    func lastReset(_ ref: CredentialRef) -> Date?
    func noteReset(_ ref: CredentialRef, at date: Date)
    func locked<T>(_ body: () throws -> T) rethrows -> T
}

public final class MemoryLedgerStorage: LedgerStorage, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var states: [CredentialRef: CredentialLedger.State] = [:]
    private var resets: [CredentialRef: Date] = [:]

    public init() {}

    public func read(_ ref: CredentialRef) -> CredentialLedger.State? { states[ref] }
    public func write(_ ref: CredentialRef, _ s: CredentialLedger.State?) { states[ref] = s }
    public func lastReset(_ ref: CredentialRef) -> Date? { resets[ref] }
    public func noteReset(_ ref: CredentialRef, at date: Date) { resets[ref] = date }
    public func locked<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
}

/// Un archivo por contraseña («probando\t1739999999.5»), con candado entre procesos (flock), como las marcas de
/// NetDeck: el askpass de una pestaña y la app ven lo mismo.
public final class DirectoryLedgerStorage: LedgerStorage, @unchecked Sendable {
    private let dir: URL
    private let threadLock = NSRecursiveLock()
    private var depth = 0
    private var lockFD: Int32 = -1

    public init(_ dir: URL) {
        self.dir = dir
    }

    public func read(_ ref: CredentialRef) -> CredentialLedger.State? {
        guard let text = try? String(contentsOf: file(ref), encoding: .utf8) else { return nil }
        let parts = text.trimmed.components(separatedBy: "\t")
        guard parts.count >= 2, let ts = TimeInterval(parts[1]) else { return nil }
        let kind = parts[0], d = Date(timeIntervalSince1970: ts)
        switch kind {
        case "probando": return .probing(since: d, owner: parts.count >= 3 ? Int32(parts[2]) ?? 0 : 0,
                                          reservation: parts.count >= 4 ? UUID(uuidString: parts[3]) : nil)
        case "fallo": return .failed(at: d)
        case "valida": return .confirmed(at: d)
        default: return nil
        }
    }

    public func write(_ ref: CredentialRef, _ s: CredentialLedger.State?) {
        let url = file(ref)
        guard let s else { try? FileManager.default.removeItem(at: url); return }
        let text: String = switch s {
        case .probing(let d, let owner, let token): "probando\t\(d.timeIntervalSince1970)\t\(owner)\t\(token?.uuidString ?? "")"
        case .failed(let d): "fallo\t\(d.timeIntervalSince1970)"
        case .confirmed(let d): "valida\t\(d.timeIntervalSince1970)"
        }
        try? SafeFile.write(text, to: url)                     // (0600: sólo tú; nunca un secreto)
    }

    /// Al lado de la marca («….restablecida» con la hora): una marca nueva no la borra.
    public func lastReset(_ ref: CredentialRef) -> Date? {
        guard let text = try? String(contentsOf: resetFile(ref), encoding: .utf8), let ts = TimeInterval(text.trimmed) else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    public func noteReset(_ ref: CredentialRef, at date: Date) {
        try? SafeFile.write("\(date.timeIntervalSince1970)", to: resetFile(ref))
    }

    public func locked<T>(_ body: () throws -> T) rethrows -> T {
        threadLock.lock()
        defer { threadLock.unlock() }
        if depth == 0 {
            lockFD = open(dir.appendingPathComponent(".candado").path, O_CREAT | O_RDWR, 0o600)
            if lockFD >= 0 { flock(lockFD, LOCK_EX) }
        }
        depth += 1
        defer {
            depth -= 1
            if depth == 0, lockFD >= 0 {
                flock(lockFD, LOCK_UN)
                close(lockFD)
                lockFD = -1
            }
        }
        return try body()
    }

    private func file(_ ref: CredentialRef) -> URL {
        let h = SHA256.hash(data: Data("\(ref.service.rawValue)\t\(ref.account)".utf8))
        return dir.appendingPathComponent(h.prefix(16).map { String(format: "%02x", $0) }.joined())
    }

    private func resetFile(_ ref: CredentialRef) -> URL { file(ref).appendingPathExtension("restablecida") }
}
