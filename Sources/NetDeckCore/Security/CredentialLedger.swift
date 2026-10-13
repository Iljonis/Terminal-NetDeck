import CryptoKit
import Foundation

/// Estado de cada contraseña entre todas las pestañas y el askpass, para no bloquear cuentas AD:
///  · probando: alguien la acaba de escribir; los demás esperan a ver si vale (TACACS/RADIUS lentos)
///  · fallo: no ha valido; no se vuelve a escribir sola en ningún sitio durante `blockWindow` (15 min)
///  · confirmada: ha entrado; los demás pueden usarla ya
public final class CredentialLedger: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case probing(since: Date)
        case failed(at: Date)
        case confirmed(at: Date)
    }

    public enum Probe: Equatable, Sendable { case go, wait, blocked }

    public var blockWindow: TimeInterval = 15 * 60
    public var probeWindow: TimeInterval = 8
    private let storage: LedgerStorage
    private let now: @Sendable () -> Date

    public init(storage: LedgerStorage = MemoryLedgerStorage(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = storage
        self.now = now
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
    public func beginProbe(_ ref: CredentialRef) -> Probe {
        storage.locked {
            switch current(ref) {
            case .failed: return .blocked
            case .probing: return .wait
            case .confirmed, nil:
                storage.write(ref, .probing(since: now()))
                return .go
            }
        }
    }

    /// Sigue probándose (un servidor lento): que los demás no se cansen de esperar.
    public func keepProbing(_ ref: CredentialRef) {
        storage.locked { if case .probing = current(ref) { storage.write(ref, .probing(since: now())) } }
    }

    public func markFailed(_ ref: CredentialRef) { storage.locked { storage.write(ref, .failed(at: now())) } }
    public func confirm(_ ref: CredentialRef) { storage.locked { storage.write(ref, .confirmed(at: now())) } }

    /// No se supo si valía (el equipo no contestó por otra cosa): la contraseña no tiene la culpa.
    public func release(_ ref: CredentialRef) {
        storage.locked { if case .probing = storage.read(ref) { storage.write(ref, nil) } }
    }

    /// La has cambiado o la eliges a mano: se olvida el fallo.
    public func reset(_ ref: CredentialRef) { storage.locked { storage.write(ref, nil) } }

    private func current(_ ref: CredentialRef) -> State? {
        let s = storage.read(ref)
        switch s {
        case .probing(let t) where now().timeIntervalSince(t) > probeWindow,
             .failed(let t) where now().timeIntervalSince(t) > blockWindow:
            storage.write(ref, nil)
            return nil
        default:
            return s
        }
    }
}

public protocol LedgerStorage: AnyObject, Sendable {
    func read(_ ref: CredentialRef) -> CredentialLedger.State?
    func write(_ ref: CredentialRef, _ state: CredentialLedger.State?)
    func locked<T>(_ body: () throws -> T) rethrows -> T
}

public final class MemoryLedgerStorage: LedgerStorage, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var states: [CredentialRef: CredentialLedger.State] = [:]

    public init() {}

    public func read(_ ref: CredentialRef) -> CredentialLedger.State? { states[ref] }
    public func write(_ ref: CredentialRef, _ s: CredentialLedger.State?) { states[ref] = s }
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
        let (kind, _, t) = text.trimmed.partition("\t")
        guard let ts = TimeInterval(t) else { return nil }
        let d = Date(timeIntervalSince1970: ts)
        switch kind {
        case "probando": return .probing(since: d)
        case "fallo": return .failed(at: d)
        case "valida": return .confirmed(at: d)
        default: return nil
        }
    }

    public func write(_ ref: CredentialRef, _ s: CredentialLedger.State?) {
        let url = file(ref)
        guard let s else { try? FileManager.default.removeItem(at: url); return }
        let (kind, d): (String, Date) = switch s {
        case .probing(let d): ("probando", d)
        case .failed(let d): ("fallo", d)
        case .confirmed(let d): ("valida", d)
        }
        try? "\(kind)\t\(d.timeIntervalSince1970)".write(to: url, atomically: true, encoding: .utf8)
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
}
