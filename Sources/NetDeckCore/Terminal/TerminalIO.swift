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
    /// El prompt propio de su sesión («# @prompt …»); nil = el genérico.
    var promptRule: PromptRule? { get }
}

public extension TerminalIO {
    var promptRule: PromptRule? { nil }
    func send(_ text: String) { send(bytes: Array(text.utf8)) }
    /// Una línea + Intro (CR, como el teclado).
    func sendLine(_ text: String) { send(text + "\r") }
    /// Las `n` filas de encima del cursor (sin la suya).
    func linesAbove(_ n: Int) -> [String] { Array(lines(from: max(0, cursorRow - n)).dropLast()) }
}

/// El reloj de las esperas que sondean la pantalla: el de verdad o, en las pruebas, uno que avanza lo pedido sin
/// depender de cuándo despierte el sistema a la tarea (con el pool de Swift ocupado, un sleep de 5 ms tardaba un
/// segundo y los topes de las pruebas vencían sin que el equipo de mentira hubiera podido contestar).
public protocol PollClock: Sendable {
    /// Tiempo transcurrido desde un origen fijo.
    func now() -> Duration
    func sleep(for duration: Duration) async throws
}

public struct SystemPollClock: PollClock {
    private static let origin = ContinuousClock.now
    public init() {}
    public func now() -> Duration { ContinuousClock.now - Self.origin }
    public func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

/// Esperas que sondean la pantalla y se cortan con Esc.
@MainActor
enum Poll {
    /// Llama a `check` cada `every` hasta que devuelve algo, se acaba `timeout` (nil) o se pulsa Esc (lanza).
    static func until<T>(every: Duration, timeout: Duration, abort: AbortSwitch, clock: any PollClock = SystemPollClock(),
                         _ check: () -> T?) async throws -> T? {
        let end = clock.now() + timeout
        while clock.now() < end {
            try abort.check()
            if let v = check() { return v }
            try await clock.sleep(for: every)
        }
        try abort.check()
        return check()
    }
}
