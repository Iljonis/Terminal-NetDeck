import Foundation

public struct AbortedByUser: Error, Equatable {}

/// Interruptor de una secuencia automática (credenciales, pegado, lista…): se comprueba justo antes de enviar cada
/// cosa, así que tras Esc no sale ni un byte más.
public final class AbortSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var tripped = false

    public init() {}

    public var isTripped: Bool { lock.withLock { tripped } }
    public func trip() { lock.withLock { tripped = true } }
    public func check() throws { if isTripped { throw AbortedByUser() } }
}

public enum AbortKey {
    public static let escape: UInt8 = 0x1B
    public static let ctrlC: UInt8 = 0x03

    /// Esc a secas (las flechas y F1… también empiezan por ESC, pero llegan como secuencia) o Ctrl+C.
    public static func isAbort(_ bytes: some Collection<UInt8>) -> Bool {
        (bytes.count == 1 && bytes.first == escape) || bytes.contains(ctrlC)
    }
}

/// Las secuencias en curso de un terminal. Esc o Ctrl+C las corta todas a la vez y devuelve el control al usuario.
@MainActor
public final class AutomationGate {
    private var running: [ObjectIdentifier: AbortSwitch] = [:]

    public init() {}

    public var isBusy: Bool { !running.isEmpty }

    public func begin() -> AbortSwitch {
        let s = AbortSwitch()
        running[ObjectIdentifier(s)] = s
        return s
    }

    public func end(_ s: AbortSwitch) { running[ObjectIdentifier(s)] = nil }

    public func abortAll() {
        running.values.forEach { $0.trip() }
        running.removeAll()
    }

    /// Tecla del usuario. true = se la come (era el Esc que cortaba algo: no llega al equipo); Ctrl+C corta y además
    /// llega al equipo (para la orden en curso). Sin nada en marcha, todo llega al equipo (vi, menús…).
    public func intercept(_ bytes: some Collection<UInt8>) -> Bool {
        guard isBusy, AbortKey.isAbort(bytes) else { return false }
        abortAll()
        return !bytes.contains(AbortKey.ctrlC)
    }
}
