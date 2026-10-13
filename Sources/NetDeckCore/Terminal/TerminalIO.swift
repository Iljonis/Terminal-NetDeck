import Foundation

/// Lo que la lógica necesita de una pestaña o panel, sin saber si detrás hay SwiftTerm, NIO SSH o un doble de pruebas.
/// Las filas son absolutas (historial + pantalla): la del cursor antes de enviar algo sirve de marca para «lo nuevo».
@MainActor
public protocol TerminalIO: AnyObject, Sendable {
    /// Bytes tal cual al proceso/canal (no pasan por el teclado del usuario ni por MultiExec).
    func send(bytes: [UInt8])
    /// Fila absoluta del cursor.
    var cursorRow: Int { get }
    /// Texto de la fila del cursor (el prompt, «Password:»…).
    var cursorLine: String { get }
    /// Filas desde `row` (absoluta) hasta la del cursor, incluidas.
    func lines(from row: Int) -> [String]
    /// Cambia con cada salida del equipo (para saber si la pantalla lleva un rato quieta).
    var revision: Int { get }
}

public extension TerminalIO {
    func send(_ text: String) { send(bytes: Array(text.utf8)) }
    /// Una línea + Intro (CR, como el teclado).
    func sendLine(_ text: String) { send(text + "\r") }
    /// Las `n` filas de encima del cursor (sin la suya).
    func linesAbove(_ n: Int) -> [String] { Array(lines(from: max(0, cursorRow - n)).dropLast()) }
}

/// Esperas que sondean la pantalla y se cortan con Esc.
@MainActor
enum Poll {
    /// Llama a `check` cada `every` hasta que devuelve algo, se acaba `timeout` (nil) o se pulsa Esc (lanza).
    static func until<T>(every: Duration, timeout: Duration, abort: AbortSwitch,
                         _ check: () -> T?) async throws -> T? {
        let clock = ContinuousClock()
        let end = clock.now + timeout
        while clock.now < end {
            try abort.check()
            if let v = check() { return v }
            try await Task.sleep(for: every)
        }
        try abort.check()
        return check()
    }
}
