import Foundation

/// Patrones de «enviar-lineas» en NetDeck.
public enum PasteRules {
    public static let errors = Pattern(#"^\s*(?:error:|% ?invalid|% ?incomplete|% ?ambiguous|% ?unknown command|% ?unrecognized|syntax error|unknown command|bad command name|unrecognized command|invalid input|wrong parameter|failure:)"#)
    public static let pager = Pattern(#"(-+ ?more ?-+|--more--|press any key|<--- more --->|\(more\)|\[more\])\s*$"#)
    /// Órdenes que reinician, borran, sustituyen la configuración o cortan el acceso (`DangerousCommands`).
    public static let dangerous = DangerousCommands()

    /// Las líneas a enviar (sin vacías). Se corta por LF, CRLF y también por un CR solo: en el equipo es un Intro.
    public static func lines(of text: String) -> [String] { rows(of: text).filter { !$0.trimmed.isEmpty } }

    /// Las líneas tal como llegarían al equipo, también las vacías («\r\n» es un solo `Character`).
    public static func rows(of text: String) -> [String] {
        text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }.map(String.init)
    }

    /// Las peligrosas (para pedir confirmación ANTES de empezar).
    public static func dangerousLines(in text: String) -> [String] { lines(of: text).filter(dangerous.matches) }

    /// Con los caracteres de control a la vista, para enseñarlos (la revisión del pegado, los avisos): «␈», «␡», «␛»,
    /// «^U» y los demás C0 como «^X»; los C1, «<9B>». TAB, CR y LF, tal cual.
    public static func visible(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { ($0.value < 0x20 && !"\t\r\n".unicodeScalars.contains($0)) || (0x7F...0x9F).contains($0.value) }) else { return s }
        var out = ""
        for u in s.unicodeScalars {
            switch u.value {
            case 0x09, 0x0A, 0x0D: out.unicodeScalars.append(u)
            case 0x08: out += "␈"
            case 0x1B: out += "␛"
            case 0x7F: out += "␡"
            case 0x00...0x1F: out += "^" + String(UnicodeScalar(UInt8(u.value + 0x40)))
            case 0x80...0x9F: out += String(format: "<%02X>", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        return out
    }
}

/// ¿Sale la ventana de revisión al pegar (⌘V, «Pegar», clic derecho)? Como el aviso de pegado de varias líneas de
/// iTerm2, `multiLinePasteWarning` de Windows Terminal o `clipboard-paste-protection` de Ghostty: sólo pregunta; al
/// aceptar se pega entero y de golpe. Con más de `threshold` líneas no vacías o alguna orden peligrosa. Apagada, nunca
/// (ni con peligrosas: es criterio del usuario). Si la pestaña pide un secreto, tampoco: lo pegado es la contraseña
/// («Delete!2024») y no se enseña ni se cuenta. Una línea con caracteres de control es peligrosa
/// (`DangerousCommands.erased`): también la que lleva un «ESC[201~» que cerraría antes de tiempo el pegado entre corchetes
/// y haría que el resto se ejecutase como tecleado.
public struct PasteReview: Equatable, Sendable {
    public static let defaultThreshold = 3
    /// Las que se ofrecen en Ajustes.
    public static let thresholds = [1, 2, 3, 5, 10, 20, 50]

    /// Las líneas tal como se ven (también las vacías).
    public let rows: [String]
    /// Las peligrosas (índices de `rows`), miradas antes de enseñar la ventana.
    public let dangerous: [Int]
    /// Las no vacías.
    public let count: Int

    /// Las líneas del texto tal como llegarían al equipo: también con CR solo (un CR también es un Intro).
    public static func lines(of text: String) -> [String] { PasteRules.rows(of: text) }

    /// La revisión de `text`, o nil si se pega sin preguntar.
    public static func review(_ text: String, enabled: Bool, threshold: Int = defaultThreshold,
                              secretPrompt: Bool = false) -> PasteReview? {
        guard enabled, !secretPrompt else { return nil }
        let rows = lines(of: text)
        let full = rows.indices.filter { !rows[$0].trimmed.isEmpty }
        let dangerous = full.filter { PasteRules.dangerous.matches(rows[$0]) }
        guard full.count > max(0, threshold) || !dangerous.isEmpty else { return nil }
        return PasteReview(rows: rows, dangerous: dangerous, count: full.count)
    }

    public static func needed(_ text: String, enabled: Bool, threshold: Int = defaultThreshold, secretPrompt: Bool = false) -> Bool {
        review(text, enabled: enabled, threshold: threshold, secretPrompt: secretPrompt) != nil
    }
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
/// Si el equipo pide un secreto (contraseña, passphrase, OTP…) se para: la línea siguiente iría como contraseña (se vería en
/// el registro del equipo y contaría como intento fallido de la cuenta).
public struct SafePaster: Sendable {
    public var lineTimeout: Duration = .seconds(20)
    public var quiet: Duration = .milliseconds(500)
    public var poll: Duration = .milliseconds(100)
    public var allowDangerous = false
    /// El reloj de las esperas (las pruebas ponen uno que no depende de cuándo despierte la tarea).
    public var clock: any PollClock = SystemPollClock()

    public init(allowDangerous: Bool = false) {
        self.allowDangerous = allowDangerous
    }

    enum Wait { case ready, error(String), pager, password, timeout }

    @MainActor
    public func paste(_ text: String, into io: TerminalIO, abort: AbortSwitch) async -> PasteReport {
        let lines = PasteRules.lines(of: text)
        let prompt = DevicePrompt(sample: io.cursorLine, custom: io.promptRule)
        func report(_ sent: Int, _ o: PasteReport.Outcome) -> PasteReport { .init(sent: sent, total: lines.count, outcome: o) }

        for (i, line) in lines.enumerated() {
            if !allowDangerous, PasteRules.dangerous.matches(line) {
                return report(i, .dangerousNotConfirmed(line: i + 1, command: line))
            }
            if abort.isTripped { return report(i, .aborted) }
            if SecretPrompt.asks(io.cursorLine) { return report(i, .passwordPrompt(line: i)) }
            if PasteRules.pager.matches(io.cursorLine) { return report(i, .pager(line: i)) }
            if PasteRules.errors.matches(io.cursorLine) || PromptRule.authenticationFailed(io.cursorLine) {
                return report(i, .deviceError(line: i, output: io.cursorLine.trimmed))
            }
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
    func waitForDevice(_ io: TerminalIO, after mark: Int, prompt: DevicePrompt, abort: AbortSwitch,
                       allowQuietFallback: Bool = true) async throws -> Wait {
        let clock = self.clock
        let start = io.revision
        var rev = start
        var changed = clock.now()
        let w: Wait? = try await Poll.until(every: poll, timeout: lineTimeout, abort: abort, clock: clock) {
            if io.revision != rev { rev = io.revision; changed = clock.now() }
            let new = io.lines(from: mark)                         // (incluida una respuesta que sobrescribe la misma fila)
            if let bad = new.first(where: { PasteRules.errors.matches($0) || PromptRule.authenticationFailed($0) }) {
                return .error(bad.trimmed)
            }
            let cur = io.cursorLine
            if new.contains(where: SecretPrompt.asks) { return .password }
            if PasteRules.pager.matches(cur) { return .pager }
            guard io.cursorRow > mark else { return nil }
            if prompt.matches(cur), clock.now() - changed >= poll { return .ready }
            if allowQuietFallback, io.promptRule == nil, !cur.trimmed.isEmpty,
               rev != start, clock.now() - changed >= quiet { return .ready }     // prompt desconocido: salida quieta
            return nil
        }
        return w ?? .timeout
    }
}
