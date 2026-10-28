import Foundation

/// La contraseña que escribes tú en un «Password:», para ofrecer guardarla en el Llavero si entra (como SecureCRT o un
/// navegador). Sólo en memoria y sólo hasta saber si ha valido; nunca se registra ni se escribe en ningún sitio.
public struct TypedPassword: Sendable {
    public struct Candidate: Equatable, Sendable {
        public let secret: String
        /// «usuario@equipo» si el prompt lo dice.
        public let account: String?
        let row: Int
        let at: Date

        /// El usuario del prompt (para proponer el nombre).
        public var user: String? {
            guard let a = account, let at = a.lastIndex(of: "@"), at != a.startIndex else { return nil }
            return String(a[..<at])
        }
    }

    private var buffer: [UInt8] = []
    private var bufferRow: Int?
    public private(set) var candidate: Candidate?

    /// Lo que no es la contraseña: el aviso del equipo de que no ha valido o que se ha cortado.
    static let refused = Pattern(#"denied|fail|incorrect|invalid|bad (?:password|secret)|sorry|closed|try again"#)
    /// Si en este tiempo no se sabe si ha entrado, se olvida (no se guarda en memoria más de lo necesario).
    public static let lifetime: TimeInterval = 60

    public init() {}

    /// Las teclas que mandas, con la línea del cursor de antes de mandarlas. Sólo cuenta un login de verdad: un prompt
    /// que dice la cuenta («usuario@equipo's password:»); ni sudo, ni enable, ni passwd. Tampoco la pregunta del
    /// askpass («[NetDeck] …'s password:»): él mismo ofrece guardarla (serían dos avisos).
    public mutating func feed(_ bytes: [UInt8], cursorLine: String, row: Int, above: [String], now: Date = Date()) {
        guard PasswordPrompt.asksForPassword(cursorLine) else { buffer = []; bufferRow = nil; return }
        if bufferRow != row { buffer = []; bufferRow = row }
        for b in bytes {
            switch b {
            case 13, 10:
                let asked = PasswordPrompt.detect(cursorLine: cursorLine, above: above)
                if let s = String(bytes: buffer, encoding: .utf8), !s.isEmpty, let asked, asked.account != nil, !asked.isChangeOrConfirm {
                    candidate = Candidate(secret: s, account: asked.account, row: row, at: now)
                } else {
                    candidate = nil
                }
                buffer = []; bufferRow = nil
                return
            case 127, 8:                                     // (borrar: el carácter entero, aunque sea ñ o €)
                while let last = buffer.last, last & 0xC0 == 0x80 { buffer.removeLast() }
                if !buffer.isEmpty { buffer.removeLast() }
            case 21: buffer = []                             // Ctrl-U
            case 3, 27: forget(); return                     // Ctrl-C, Esc (y flechas): nada que guardar
            case 0..<32: continue
            default: buffer.append(b)
            }
        }
    }

    /// Tras cada salida, desde la fila en que se mandó hasta el cursor: la devuelve si se ve el prompt del equipo (ha
    /// entrado); la olvida si la vuelven a pedir o el equipo dice que no; nil mientras no se sepa.
    public mutating func resolve(lines: (Int) -> [String], cursorLine: String, row: Int, now: Date = Date()) -> Candidate? {
        guard let c = candidate else { return nil }
        guard now.timeIntervalSince(c.at) < Self.lifetime else { candidate = nil; return nil }
        guard row > c.row else { return nil }
        let line = cursorLine.trimmed
        if PasswordPrompt.acceptsManual(line) || SecretPrompt.asks(line) || lines(c.row + 1).contains(where: Self.refused.matches) {
            candidate = nil
            return nil
        }
        guard DevicePrompt.generic.matches(line) else { return nil }
        candidate = nil
        return c
    }

    public mutating func forget() {
        buffer = []
        bufferRow = nil
        candidate = nil
    }
}
