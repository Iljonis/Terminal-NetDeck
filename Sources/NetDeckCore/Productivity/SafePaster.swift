import Foundation

/// Patrones de «enviar-lineas» en NetDeck.
public enum PasteRules {
    public static let errors = Pattern(#"^\s*(?:error:|% ?invalid|% ?incomplete|% ?ambiguous|% ?unknown command|% ?unrecognized|syntax error|unknown command|bad command name|unrecognized command|invalid input|wrong parameter|failure:)"#)
    public static let pager = Pattern(#"(-+ ?more ?-+|--more--|press any key|<--- more --->|\(more\)|\[more\])\s*$"#)
    public static let dangerous = Pattern(#"\b(reload|reboot|reset|delete|erase|format|undo|shutdown|clear|rollback|request system|write erase|kill)\b"#)

    /// Las líneas a enviar (sin vacías ni finales de línea de Windows).
    public static func lines(of text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            .filter { !$0.trimmed.isEmpty }
    }

    /// Las peligrosas (para pedir confirmación ANTES de empezar).
    public static func dangerousLines(in text: String) -> [String] { lines(of: text).filter(dangerous.matches) }
}

public struct PasteReport: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case completed
        case aborted                                   // Esc / Ctrl+C
        case deviceError(line: Int, output: String)    // «% Invalid input…»: se para ahí
        case pager(line: Int)                          // «--More--»: falta «terminal length 0»
        case timeout(line: Int)
        case dangerousNotConfirmed(line: Int, command: String)
        case passwordPrompt(line: Int)                 // «Password:» tras esa línea (0 = ya estaba): nada se escribe ahí
    }

    public var sent: Int
    public var total: Int
    public var outcome: Outcome
}

/// Pegado seguro: línea a línea, cada una espera al prompt del equipo (o a que la salida lleve `quiet` quieta) y se
/// para ante un error de la CLI, un paginador o Esc. Las peligrosas (reload, delete…) sólo con `allowDangerous`.
/// Si el equipo pide una contraseña («enable», «ssh …») se para: la línea siguiente iría como contraseña (se vería en
/// el registro del equipo y contaría como intento fallido de la cuenta).
public struct SafePaster: Sendable {
    public var lineTimeout: Duration = .seconds(20)
    public var quiet: Duration = .milliseconds(500)
    public var poll: Duration = .milliseconds(100)
    public var allowDangerous = false

    public init(allowDangerous: Bool = false) {
        self.allowDangerous = allowDangerous
    }

    enum Wait { case ready, error(String), pager, password, timeout }

    @MainActor
    public func paste(_ text: String, into io: TerminalIO, abort: AbortSwitch) async -> PasteReport {
        let lines = PasteRules.lines(of: text)
        let prompt = DevicePrompt(sample: io.cursorLine)
        func report(_ sent: Int, _ o: PasteReport.Outcome) -> PasteReport { .init(sent: sent, total: lines.count, outcome: o) }

        for (i, line) in lines.enumerated() {
            if !allowDangerous, PasteRules.dangerous.matches(line) {
                return report(i, .dangerousNotConfirmed(line: i + 1, command: line))
            }
            if abort.isTripped { return report(i, .aborted) }
            if PasswordPrompt.asksForPassword(io.cursorLine) { return report(i, .passwordPrompt(line: i)) }
            let mark = io.cursorRow
            io.sendLine(line)
            let w: Wait
            do {
                w = try await waitForDevice(io, after: mark, prompt: prompt, abort: abort)
            } catch {
                return report(i + 1, .aborted)
            }
            switch w {
            case .ready: continue
            case .error(let out): return report(i + 1, .deviceError(line: i + 1, output: out))
            case .pager: return report(i + 1, .pager(line: i + 1))
            case .password: return report(i + 1, .passwordPrompt(line: i + 1))
            case .timeout: return report(i + 1, .timeout(line: i + 1))
            }
        }
        return report(lines.count, .completed)
    }

    @MainActor
    func waitForDevice(_ io: TerminalIO, after mark: Int, prompt: DevicePrompt, abort: AbortSwitch) async throws -> Wait {
        let clock = ContinuousClock()
        let start = io.revision
        var rev = start
        var changed = clock.now
        let w: Wait? = try await Poll.until(every: poll, timeout: lineTimeout, abort: abort) {
            if io.revision != rev { rev = io.revision; changed = clock.now }
            let new = io.lines(from: mark + 1)                     // (los errores salen justo después de la orden)
            if let bad = new.prefix(4).first(where: PasteRules.errors.matches) { return .error(bad.trimmed) }
            let cur = io.cursorLine
            if PasteRules.pager.matches(cur) { return .pager }
            guard io.cursorRow > mark else { return nil }
            if PasswordPrompt.asksForPassword(cur) { return .password }
            if prompt.matches(cur), clock.now - changed >= poll { return .ready }
            if rev != start, clock.now - changed >= quiet { return .ready }     // prompt desconocido: salida quieta
            return nil
        }
        return w ?? .timeout
    }
}
