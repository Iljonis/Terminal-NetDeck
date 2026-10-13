import Foundation

/// La contraseña de un terminal cuando la pide: decide con `CredentialPolicy`, espera un instante (Esc la cancela),
/// comprueba que la petición sigue ahí y la escribe. Si la vuelven a pedir, ha fallado: queda bloqueada en todas las
/// pestañas (`CredentialLedger`) y se elige a mano.
@MainActor
public final class PasswordAutomation {
    public enum Mode: String, Sendable, CaseIterable {
        case off          // nada
        case suggest      // avisa con la que escribiría (un clic)
        case autoType     // la escribe sola
    }

    public enum Event: Equatable, Sendable {
        case typed(CredentialRef)
        case suggested(CredentialRef)
        case manual(ManualReason)
        case failed(CredentialRef)
        case confirmed(CredentialRef)
        case cancelled
    }

    public var mode: Mode
    /// Hasta que la pestaña llega a su primer prompt, la contraseña es la de la SESIÓN (su propio login, p. ej. telnet
    /// o ssh sin askpass): con este modo. Después, las de los equipos con `mode`. nil = `mode` también para la sesión.
    public var sessionMode: Mode?
    public private(set) var loggedIn = false
    public var settle: Duration = .milliseconds(150)
    /// Usuario de la última orden «ssh/telnet …» tecleada aquí (lo pone la vista al pulsar Intro).
    public var commandUser: String?
    /// Los usuarios explícitos de los saltos de esa orden (`ssh -J tu.usuario@bastion …`).
    public var commandJumpUsers: Set<String> = []
    /// Candidatas para cada petición (las da la app con lo que sabe de la sesión: `SessionManager`).
    public var candidates: (PasswordRequest) -> [CredentialCandidate]

    private let store: CredentialStore
    private let policy: CredentialPolicy
    private let ledger: CredentialLedger
    private var handledSite: String?
    private var pending: (ref: CredentialRef, site: String)?
    private var busy = false

    public init(mode: Mode = .suggest, store: CredentialStore, policy: CredentialPolicy = .init(),
                ledger: CredentialLedger, candidates: @escaping (PasswordRequest) -> [CredentialCandidate] = { _ in [] }) {
        self.mode = mode
        self.store = store
        self.policy = policy
        self.ledger = ledger
        self.candidates = candidates
    }

    /// Mirar la pantalla (tras cada salida del equipo). nil = nada que hacer.
    public func observe(_ io: TerminalIO, gate: AutomationGate) async -> Event? {
        let line = io.cursorLine
        if !loggedIn, DevicePrompt.generic.matches(line.trimmed) { loggedIn = true }
        let mode = loggedIn ? self.mode : (sessionMode ?? self.mode)
        guard mode != .off, !busy else { return nil }
        guard let request = PasswordPrompt.detect(cursorLine: line, above: io.linesAbove(3)) else {
            if let p = pending, DevicePrompt.generic.matches(line.trimmed) {     // ha entrado
                ledger.confirm(p.ref)
                pending = nil
                return .confirmed(p.ref)
            }
            return nil
        }
        let site = "\(io.cursorRow):\(line.trimmed)"
        guard site != handledSite else { return nil }
        handledSite = site
        if let p = pending {                                   // otra vez «Password:» = no valía
            pending = nil
            ledger.markFailed(p.ref)
            return .failed(p.ref)
        }
        let cands = candidates(request).filter { store.contains($0.ref) }
        let decision = policy.decide(request, commandUser: commandUser, jumpUsers: commandJumpUsers, candidates: cands,
                                     isBlocked: ledger.isBlocked)
        guard case .inject(let ref) = decision else {
            if case .manual(let why) = decision { return .manual(why) }
            return nil
        }
        guard mode == .autoType else { return .suggested(ref) }
        guard ledger.beginProbe(ref) == .go else { return .manual(.recentlyFailed(ref)) }

        busy = true
        defer { busy = false }
        let sw = gate.begin()
        defer { gate.end(sw) }
        try? await Task.sleep(for: settle)
        // (el Llavero, fuera del hilo principal: si tarda, la ventana no se congela)
        let store = self.store
        let secret = await Task.detached { try? store.password(for: ref) }.value
        // (justo antes de escribir: ni Esc, ni otra pantalla)
        guard !sw.isTripped, "\(io.cursorRow):\(io.cursorLine.trimmed)" == site, let pw = secret else {
            ledger.release(ref)
            return sw.isTripped ? .cancelled : nil
        }
        io.sendLine(pw)
        pending = (ref, site)
        return .typed(ref)
    }

    public enum ManualResult: Equatable, Sendable { case typed, blocked, notAsked, missing }

    /// Elección manual (menú 🔑): sin la regla de usuario (la eliges tú), pero nunca una bloqueada sin `force`.
    public func typeManually(_ ref: CredentialRef, into io: TerminalIO, force: Bool = false) -> ManualResult {
        if !force, ledger.isBlocked(ref) { return .blocked }
        guard PasswordPrompt.asksForPassword(io.cursorLine) else { return .notAsked }
        guard let pw = try? store.password(for: ref) else { return .missing }
        if force { ledger.reset(ref) }
        let site = "\(io.cursorRow):\(io.cursorLine.trimmed)"
        io.sendLine(pw)
        pending = (ref, site)
        handledSite = site
        return .typed
    }

    /// «Escribir sin esperar a que la pida» (menú 🔑): la manda al terminal aunque la línea no sea «Password:» (un
    /// prompt que no se reconoce). Intro sólo con `pressReturn`. Nunca una bloqueada sin `force` (y no la desbloquea).
    public func typeAnyway(_ ref: CredentialRef, into io: TerminalIO, pressReturn: Bool, force: Bool = false) -> ManualResult {
        if !force, ledger.isBlocked(ref) { return .blocked }
        guard let pw = try? store.password(for: ref) else { return .missing }
        if pressReturn { io.sendLine(pw) } else { io.send(pw) }
        return .typed
    }
}
