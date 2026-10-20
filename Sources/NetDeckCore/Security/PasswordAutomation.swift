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
    /// Los equipos (destino y saltos) de esa orden: un prompt «usuario@equipo» de otro equipo no cuenta.
    public var commandHosts: Set<String> = []
    /// Tras el salto «a mano» (el salto no dejó reenviar -J): lo que se teclea pasa por la shell del salto, que vería
    /// la contraseña del destino; las de los equipos sólo se sugieren (un clic), nunca se escriben solas.
    public var onlySuggestDevices = false
    /// Candidatas para cada petición (las da la app con lo que sabe de la sesión: `SessionManager`).
    public var candidates: (PasswordRequest) -> [CredentialCandidate]

    private let store: CredentialStore
    private let policy: CredentialPolicy
    private let ledger: CredentialLedger
    private var handledSite: String?
    private var pending: (ref: CredentialRef, row: Int)?
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
        // (el rechazo puede haber quedado encima de una fila vacía o de un prompt, en el mismo bloque de salida)
        if let p = pending, io.lines(from: p.row).contains(where: PromptRule.authenticationFailed) {
            pending = nil
            ledger.markFailed(p.ref)
            // (la petición que sale con el rechazo es la misma: ya está atendida, sin un segundo aviso)
            if PasswordPrompt.asksForPassword(line) { handledSite = "\(io.cursorRow):\(line.trimmed)" }
            return .failed(p.ref)
        }
        if !loggedIn, PromptRule.isPrompt(line, custom: io.promptRule) { loggedIn = true }
        var mode = loggedIn ? self.mode : (sessionMode ?? self.mode)
        if onlySuggestDevices, mode == .autoType { mode = .suggest }
        guard mode != .off, !busy else { return nil }
        guard let request = PasswordPrompt.detect(cursorLine: line, above: io.linesAbove(3)) else {
            if let p = pending, PromptRule.isPrompt(line, custom: io.promptRule) {     // ha entrado
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
        let sw = gate.begin()
        try? await Task.sleep(for: settle)
        // (el Llavero, fuera del hilo principal: si tarda, la ventana no se congela)
        let secret = await Self.secret(ref, in: store)
        let event: Event?
        // (justo antes de escribir: ni Esc, ni otra pantalla)
        if !sw.isTripped, "\(io.cursorRow):\(io.cursorLine.trimmed)" == site, let pw = secret {
            pending = (ref, io.cursorRow)
            io.sendLine(pw)
            event = .typed(ref)
        } else {
            ledger.release(ref)
            event = sw.isTripped ? .cancelled : nil
        }
        gate.end(sw)
        busy = false
        return event
    }

    /// (aparte: con el cierre dentro de observe, el compilador de Swift 6.3 se cae en ClosureLifetimeFixup)
    nonisolated private static func secret(_ ref: CredentialRef, in store: CredentialStore) async -> String? {
        await Task.detached { try? store.password(for: ref) }.value
    }

    /// `busy`: ya se está escribiendo una (dos clics seguidos no la mandan dos veces).
    public enum ManualResult: Equatable, Sendable { case typed, blocked, notAsked, missing, busy }

    /// Elección manual (menú 🔑): sin la regla de usuario (la eliges tú), pero nunca una bloqueada sin `force`.
    /// El Llavero se lee fuera del hilo principal; justo antes de escribirla se comprueba que la siguen pidiendo.
    public func typeManually(_ ref: CredentialRef, into io: TerminalIO, force: Bool = false) async -> ManualResult {
        if !force, ledger.isBlocked(ref) { return .blocked }
        guard PasswordPrompt.asksForPassword(io.cursorLine) else { return .notAsked }
        let site = "\(io.cursorRow):\(io.cursorLine.trimmed)"
        guard !busy, site != handledSite || pending == nil else { return .busy }
        busy = true
        defer { busy = false }
        guard let pw = await store.passwordInBackground(for: ref) else { return .missing }
        // (mientras se leía, otra pestaña puede haberla marcado como fallida, o la pantalla haber cambiado)
        if !force, ledger.isBlocked(ref) { return .blocked }
        guard "\(io.cursorRow):\(io.cursorLine.trimmed)" == site else { return .notAsked }
        if force { ledger.reset(ref) }
        pending = (ref, io.cursorRow)
        io.sendLine(pw)
        handledSite = site
        return .typed
    }

    /// «Escribir sin esperar a que la pida» (menú 🔑): la manda al terminal aunque la línea no sea «Password:» (un
    /// prompt que no se reconoce). Intro sólo con `pressReturn`. Nunca una bloqueada sin `force` (y no la desbloquea).
    public func typeAnyway(_ ref: CredentialRef, into io: TerminalIO, pressReturn: Bool, force: Bool = false) async -> ManualResult {
        if !force, ledger.isBlocked(ref) { return .blocked }
        guard !busy else { return .busy }
        busy = true
        defer { busy = false }
        guard let pw = await store.passwordInBackground(for: ref) else { return .missing }
        if !force, ledger.isBlocked(ref) { return .blocked }
        if pressReturn { io.sendLine(pw) } else { io.send(pw) }
        return .typed
    }
}
