import Foundation

/// La contraseña de un equipo abierto DESDE una sesión: sólo una orden enviada por la persona arma la detección.
/// Decide con `CredentialPolicy`, espera un instante (Esc la cancela) y comprueba otra vez antes de escribir. El
/// login inicial de la sesión no pasa por aquí. Sólo el rechazo de la por defecto escrita sola la bloquea 15 min en
/// todas las pestañas; lo que eliges tú (menú 🔑, botones, el aviso) y las de la sesión o del equipo, nunca.
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
        /// La por defecto, escrita sola, no ha valido: bloqueada 15 min en todas las pestañas.
        case failed(CredentialRef)
        /// Otra (de la sesión, de un equipo, elegida por ti) no ha valido: no se bloquea; la escribes tú.
        case rejected(CredentialRef)
        case confirmed(CredentialRef)
        case cancelled
    }

    /// Una propuesta sólo vale para esta orden, petición y pantalla. La interfaz conserva el id; nunca convierte un
    /// aviso antiguo en una elección global del menú de contraseñas.
    public struct Offer: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let refs: [CredentialRef]
        public let target: Endpoint
        fileprivate let generation: UInt64
        fileprivate let site: String
        fileprivate let revision: Int
        fileprivate let request: PasswordRequest
        fileprivate let user: String?
        fileprivate let jumpUsers: Set<String>
        fileprivate let hosts: Set<String>
    }

    public private(set) var offer: Offer? {
        didSet { if oldValue != offer { onOfferChange?(offer) } }
    }
    public var onOfferChange: ((Offer?) -> Void)?
    /// La pantalla seguía pidiendo la misma contraseña al terminar una consulta obsoleta o una espera ajena.
    /// Se llama con la operación ya liberada; la vista agrupa esta petición con las comprobaciones de salida.
    public var onRetry: (() -> Void)?

    public var mode: Mode { didSet { if mode == .off { cancelCommand() } } }
    public private(set) var loggedIn = false
    public var settle: Duration = .milliseconds(150)
    /// Usuario de la última orden «ssh/telnet …» tecleada aquí (lo pone la vista al pulsar Intro).
    public var commandUser: String?
    /// Los usuarios explícitos de los saltos de esa orden (`ssh -J tu.usuario@bastion …`).
    public var commandJumpUsers: Set<String> = []
    /// Los equipos (destino y saltos) de esa orden: un prompt «usuario@equipo» de otro equipo no cuenta.
    public var commandHosts: Set<String> = []
    /// Destino de la orden realmente enviada (para las candidatas de un «Password:» sin cuenta en pantalla).
    public private(set) var commandTarget: Endpoint?
    /// Tras el salto «a mano» (el salto no dejó reenviar -J): lo que se teclea pasa por la shell del salto, que vería
    /// la contraseña del destino; las de los equipos sólo se sugieren (un clic), nunca se escriben solas.
    public var onlySuggestDevices = false
    /// Candidatas para cada petición (las da la app con lo que sabe de la sesión: `SessionManager`).
    public var candidates: (PasswordRequest) -> [CredentialCandidate]

    private let store: CredentialStore
    private let policy: CredentialPolicy
    private let ledger: CredentialLedger
    private var handledSite: String?
    /// Desde que se envió la contraseña, el cursor ha estado en otra línea (el salto de línea tras ella): si la misma
    /// petición vuelve a salir en la misma fila (con el historial lleno la fila puede no moverse), es que la repiten.
    private var leftSite = false
    /// La enviada que espera respuesta, con la cuenta de su petición («tu.usuario@bastion»; nil si no la decía).
    /// (`revision`: la de la pantalla al enviarla; con el historial lleno la fila del cursor deja de crecer. `blocks`:
    /// sólo la por defecto escrita sola se bloquea si no vale; lo que eliges tú y las de la sesión, nunca)
    private typealias Pending = (ref: CredentialRef, row: Int, reservation: UUID?, account: String?, revision: Int, blocks: Bool)
    private var pending: Pending?
    private var unresolved: [CredentialRef: UUID] = [:]
    private var external: [CredentialRef: UUID] = [:]
    private var generation: UInt64 = 0
    private var operation: UUID?
    private var reservation: (ref: CredentialRef, generation: UInt64, token: UUID)?
    private var commandRow: Int?
    private var lastObservedRow: Int?
    private struct Observation {
        let generation: UInt64
        let site: String
        let request: PasswordRequest
        let target: Endpoint
        let user: String?
        let jumpUsers: Set<String>
        let hosts: Set<String>
        let mode: Mode
        let onlySuggestDevices: Bool
    }
    private var waitingProbe: (id: UUID, ref: CredentialRef, context: Observation, task: Task<Void, Never>)?

    public init(mode: Mode = .suggest, store: CredentialStore, policy: CredentialPolicy = .init(),
                ledger: CredentialLedger, candidates: @escaping (PasswordRequest) -> [CredentialCandidate] = { _ in [] }) {
        self.mode = mode
        self.store = store
        self.policy = policy
        self.ledger = ledger
        self.candidates = candidates
    }

    /// La vista recoge lo realmente enviado con su recolector de líneas; nunca con lo que el remoto dibuja en el
    /// cursor. Una orden distinta termina el contexto anterior; «echo ssh …» o «show … ssh …» no lo abren.
    public func beginCommand(_ command: String, after row: Int? = nil) {
        cancelCommand()
        let words = command.split(whereSeparator: \.isWhitespace)
        guard let first = words.first, ["ssh", "telnet"].contains(String(first)),
              !command.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !command.contains(where: { ";|&$`<>".contains($0) }),
              !words.dropFirst().contains(where: { ["ssh", "telnet"].contains((String($0) as NSString).lastPathComponent) }),
              let target = CommandLineUser.interactiveTarget(command) else { return }
        commandTarget = target
        commandRow = row ?? lastObservedRow
        commandUser = target.user
        commandHosts = CommandLineUser.hosts(command)
        commandJumpUsers = CommandLineUser.jumpUsers(command)
    }

    /// Esc, cierre, reconexión u otra orden: una lectura del Llavero que siga en marcha ya no puede enviar nada.
    public func cancelCommand() {
        generation &+= 1
        waitingProbe?.task.cancel()
        waitingProbe = nil
        if offer == nil { onOfferChange?(nil) } else { offer = nil }
        if let r = reservation { ledger.release(r.ref, reservation: r.token); reservation = nil }
        // (Esc cancela el seguimiento, pero una contraseña ya enviada puede seguir autenticándose en TACACS)
        if let p = pending, let token = p.reservation { unresolved[p.ref] = token }
        pending = nil
        operation = nil
        handledSite = nil
        leftSite = false
        commandTarget = nil
        commandRow = nil
        commandUser = nil
        commandJumpUsers = []
        commandHosts = []
    }

    public func reset() { cancelCommand(); loggedIn = false; lastObservedRow = nil }

    /// El búfer se ha recolocado y lo anclado a filas ya no se puede leer: la enviada se suelta sin confirmarla ni
    /// marcarla (como un corte) y la orden deja de armar nada (no se escribe otra vez sin saber qué ha pasado).
    public func bufferRealigned() {
        guard pending != nil || commandTarget != nil else { return }
        if let p = pending {
            pending = nil
            if let token = p.reservation { ledger.release(p.ref, reservation: token) }
            DebugLog.log("autopass", "búfer recolocado tras «\(p.ref)»: ni se confirma ni cuenta como fallo")
        }
        cancelCommand()
    }

    /// La vista conserva esta limpieza hasta comprobar que ha terminado el proceso de la conexión anterior.
    public func connectionCleanup() -> (@Sendable () -> Void)? {
        cancelCommand()
        guard !unresolved.isEmpty || !external.isEmpty else { return nil }
        let leases = unresolved.merging(external) { _, current in current }, ledger = ledger
        unresolved.removeAll()
        external.removeAll()
        return { for (ref, token) in leases { ledger.release(ref, reservation: token) } }
    }

    public func connectionEnded() { connectionCleanup()?() }

    /// El registro ocurre al enviar, antes de cualquier await: así el cierre se lleva también las reservas de listas.
    public func registerPendingAuthentication(_ ref: CredentialRef, reservation token: UUID) {
        guard owns(ref, token: token) else { return }
        cancelCommand()
        external[ref] = token
    }

    /// Una lista deja de esperar; una entrega antigua tras reconectar no vuelve a registrar la conexión anterior.
    public func retainPendingAuthentication(_ ref: CredentialRef, reservation token: UUID, ended: Bool = false) {
        guard external[ref] == token else { return }
        external[ref] = nil
        guard owns(ref, token: token) else { return }
        if ended { ledger.release(ref, reservation: token); return }
        cancelCommand()
        unresolved[ref] = token
    }

    private func releaseReservation(_ g: UInt64) {
        guard let r = reservation, r.generation == g else { return }
        ledger.release(r.ref, reservation: r.token)
        reservation = nil
    }

    private func site(_ io: TerminalIO) -> String { "\(io.cursorRow):\(io.cursorLine.trimmed)" }

    private func owns(_ ref: CredentialRef, token: UUID) -> Bool {
        if case .probing(_, _, let currentToken) = ledger.state(of: ref) { return currentToken == token }
        return false
    }

    private func request(_ io: TerminalIO) -> PasswordRequest? {
        let above = commandRow.map { Array(io.lines(from: max($0 + 1, io.cursorRow - 3)).dropLast()) } ?? io.linesAbove(3)
        return PasswordPrompt.detect(cursorLine: io.cursorLine, above: above)
    }

    private func compatible(_ request: PasswordRequest, from available: [CredentialCandidate]) -> [CredentialRef] {
        var seen = Set<CredentialRef>()
        return available.compactMap { candidate in
            guard case .inject(let ref) = policy.decide(request, commandUser: commandUser, jumpUsers: commandJumpUsers,
                                                        candidates: [candidate], isBlocked: { _ in false }),
                  seen.insert(ref).inserted else { return nil }
            return ref
        }
    }

    private func current(_ proposal: Offer, io: TerminalIO) -> Bool {
        generation == proposal.generation && commandTarget == proposal.target && commandUser == proposal.user
            && commandJumpUsers == proposal.jumpUsers && commandHosts == proposal.hosts && mode != .off
            && site(io) == proposal.site && io.revision == proposal.revision && request(io) == proposal.request
    }

    /// Una revisión puede cambiar sin mover el prompt (salida fragmentada); el resto del contexto debe ser idéntico.
    private func sameLogin(_ context: Observation, io: TerminalIO) -> Bool {
        generation == context.generation && commandTarget == context.target && commandUser == context.user
            && commandJumpUsers == context.jumpUsers && commandHosts == context.hosts && mode == context.mode
            && onlySuggestDevices == context.onlySuggestDevices && site(io) == context.site
            && request(io) == context.request
    }

    /// Sólo un observador por petición. No reserva ni lee secretos mientras otra pestaña comprueba la contraseña.
    private func waitForProbe(_ ref: CredentialRef, context: Observation, io: TerminalIO, gate: AutomationGate) {
        guard waitingProbe == nil else { return }
        let id = UUID()
        let task = Task { @MainActor [weak self, weak io] in
            let sw = gate.begin()
            var retry = false
            defer {
                gate.end(sw)
                if self?.waitingProbe?.id == id {
                    self?.waitingProbe = nil
                    if retry, let self, let io, self.sameLogin(context, io: io) {
                        self.handledSite = nil
                        self.onRetry?()
                    }
                }
            }
            let end = ContinuousClock.now + .seconds(120)
            repeat {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, let io, !Task.isCancelled, !sw.isTripped,
                      self.sameLogin(context, io: io) else {
                    if sw.isTripped, self?.generation == context.generation { self?.cancelCommand() }
                    return
                }
                if case .probing = self.ledger.state(of: ref) { continue }
                retry = true
                return
            } while ContinuousClock.now < end
        }
        waitingProbe = (id, ref, context, task)
    }

    /// Mirar la pantalla (tras cada salida del equipo). nil = nada que hacer.
    public func observe(_ io: TerminalIO, gate: AutomationGate) async -> Event? {
        let line = io.cursorLine
        let observedGeneration = generation
        defer { if generation == observedGeneration { lastObservedRow = io.cursorRow } }
        if pending != nil, let h = handledSite, site(io) != h { leftSite = true }
        if !unresolved.isEmpty, PromptRule.endsNestedLogin(line, custom: io.promptRule) {
            for (ref, token) in unresolved { ledger.release(ref, reservation: token) }
            unresolved.removeAll()                         // (ha vuelto a una shell; el login cancelado ya terminó)
        }
        if let proposal = offer, !current(proposal, io: io) {
            offer = nil
            handledSite = nil
        }
        if let p = pending, let token = p.reservation, !owns(p.ref, token: token) {
            cancelCommand()
            return .cancelled
        }
        // (un segundo factor manual no prueba que la contraseña fallara, tampoco si el rechazo llegó en este bloque)
        if let p = pending, io.lines(from: p.row).contains(where: {
            let l = $0.trimmed
            return SecretPrompt.asks(l) && !PasswordPrompt.asksForPassword(l) && !l.hasPrefix(Askpass.marker)
                && !l.hasPrefix("Are you sure you want to continue connecting")
        }) {
            cancelCommand()                           // (libera sólo su reserva; el OTP sigue manual)
            return .cancelled
        }
        // (el rechazo puede haber quedado encima de una fila vacía o de un prompt, en el mismo bloque de salida)
        if let p = pending, io.lines(from: p.row).contains(where: PromptRule.authenticationFailed) {
            pending = nil
            return rejected(p)
        }
        if !loggedIn, PromptRule.isPrompt(line, custom: io.promptRule) { loggedIn = true }
        var mode = self.mode
        if onlySuggestDevices, mode == .autoType { mode = .suggest }
        guard operation == nil else { return nil }
        guard let request = request(io) else {
            // (la escrita a mano en el askpass: si vuelve a preguntar en otra fila, no valía; otra cuenta, era el salto)
            if let p = pending, io.cursorRow > p.row || io.revision != p.revision,
               let asked = PasswordPrompt.askpassRequest(line) {
                pending = nil
                return resolveRepeated(p, asking: asked.account)
            }
            // (con «# @prompt», el de la sesión; el login anidado lo termina también el prompt genérico del otro equipo)
            let atShell = PromptRule.isPrompt(line, custom: io.promptRule)
                || (pending != nil && PromptRule.endsNestedLogin(line, custom: io.promptRule))
            // (el equipo cortó entre la contraseña y la vuelta a la shell —«Connection closed by…», un timeout—: ni
            // ha entrado ni la ha rechazado; se suelta la reserva sin confirmarla ni marcarla)
            if atShell, let p = pending, io.lines(from: p.row).contains(where: Self.cutBeforePrompt.matches) {
                pending = nil
                if let token = p.reservation { ledger.release(p.ref, reservation: token) }
                DebugLog.log("autopass", "corte antes del prompt tras «\(p.ref)»: ni se confirma ni cuenta como fallo")
                cancelCommand()
                return nil
            }
            if atShell {
                let confirmed = pending?.ref
                if let p = pending {
                    if let token = p.reservation { ledger.confirm(p.ref, reservation: token) } else { ledger.confirmDirect(p.ref) }
                    pending = nil
                }
                cancelCommand()
                return confirmed.map(Event.confirmed)
            }
            return nil
        }
        let site = "\(io.cursorRow):\(line.trimmed)"
        if let wait = waitingProbe {
            if sameLogin(wait.context, io: io), case .probing = ledger.state(of: wait.ref) { return nil }
            wait.task.cancel()
            waitingProbe = nil
            if sameLogin(wait.context, io: io) { handledSite = nil }
        }
        guard site != handledSite || (pending != nil && leftSite) else { return nil }
        if let p = pending {
            pending = nil
            if let failed = resolveRepeated(p, asking: request.account) { return failed }
        }
        // (sin una orden propia no se buscan candidatas ni se consulta el almacén, aunque parezca una contraseña)
        guard mode != .off, let target = commandTarget else { return nil }
        handledSite = site
        let context = Observation(generation: generation, site: site, request: request, target: target,
                                  user: commandUser, jumpUsers: commandJumpUsers, hosts: commandHosts,
                                  mode: self.mode, onlySuggestDevices: onlySuggestDevices)
        var retry = false
        let listed = candidates(request), lookupGeneration = generation, lookup = UUID(), lookupRevision = io.revision
        let lookupSwitch = gate.begin()
        operation = lookup
        defer {
            gate.end(lookupSwitch)
            if operation == lookup { operation = nil }
            if retry, !Task.isCancelled, !lookupSwitch.isTripped, sameLogin(context, io: io) {
                handledSite = nil
                DebugLog.log("autopass", "misma petición tras cambiar la revisión: vuelvo a comprobarla")
                onRetry?()
            }
        }
        // (también comprobar si existe una entrada puede esperar al servicio del Llavero: fuera de la interfaz)
        let (cands, lookupFailed) = await Self.available(listed, in: store)
        guard sameLogin(context, io: io), !Task.isCancelled, !lookupSwitch.isTripped,
              io.revision == lookupRevision else {
            let cancelled = lookupSwitch.isTripped || Task.isCancelled || generation != lookupGeneration
            if cancelled, generation == lookupGeneration { cancelCommand() }
            if !cancelled, sameLogin(context, io: io), io.revision != lookupRevision { retry = true }
            return cancelled ? .cancelled : nil
        }
        // (no se ha podido mirar el Llavero: que no esté no es seguro. Se avisa y, si lo vuelven a pedir, se reintenta)
        if lookupFailed {
            handledSite = nil
            return .manual(.keychainUnavailable)
        }
        if mode == .suggest, let target = commandTarget {
            let refs = compatible(request, from: cands)
            if let first = refs.first {
                offer = Offer(id: UUID(), refs: refs, target: target, generation: generation, site: site,
                              revision: io.revision, request: request, user: commandUser, jumpUsers: commandJumpUsers, hosts: commandHosts)
                return .suggested(first)
            }
        }
        let (decision, chosen) = policy.choose(request, commandUser: commandUser, jumpUsers: commandJumpUsers,
                                               candidates: cands, isBlocked: ledger.isBlocked)
        guard case .inject(let ref) = decision else {
            if case .manual(let why) = decision { return .manual(why) }
            return nil
        }
        guard mode == .autoType else { return nil }
        let probe = ledger.reserveProbe(ref)
        guard probe.result == .go, let token = probe.token else {
            if probe.result == .wait { waitForProbe(ref, context: context, io: io, gate: gate) }
            return .manual(probe.result == .wait ? .pendingAttempt(ref) : .recentlyFailed(ref))
        }

        let g = generation, op = UUID(), revision = io.revision
        reservation = (ref, g, token)
        operation = op
        let sw = gate.begin()
        defer {
            releaseReservation(g)
            gate.end(sw)
            if operation == op { operation = nil }
        }
        try? await Task.sleep(for: settle)
        guard generation == g, commandTarget != nil, self.mode == .autoType, !onlySuggestDevices,
              !sw.isTripped, !Task.isCancelled, owns(ref, token: token) else {
            if generation == g { cancelCommand() }
            return .cancelled
        }
        guard sameLogin(context, io: io), io.revision == revision else {
            if sameLogin(context, io: io), io.revision != revision { retry = true }
            return nil
        }
        // (el Llavero, fuera del hilo principal: si tarda, la ventana no se congela)
        let read = await Self.read(ref, in: store)
        let event: Event?
        // (justo antes de escribir: ni Esc, ni otra pantalla)
        if sameLogin(context, io: io), !sw.isTripped, !Task.isCancelled, owns(ref, token: token),
           io.revision == revision, !ledger.isBlocked(ref), let pw = read.password {
            reservation = nil                                // (ya enviada: la reserva se resuelve con su respuesta)
            pending = (ref, io.cursorRow, token, request.account, io.revision, chosen?.origin == .defaultCredential)
            leftSite = false
            io.sendLine(pw)
            event = .typed(ref)
        } else if read == .failed, generation == g, sameLogin(context, io: io), !sw.isTripped, !Task.isCancelled {
            handledSite = nil                                // (la reserva se suelta al salir; si la repiten, otra vez)
            event = .manual(.keychainUnavailable)
        } else {
            let cancelled = sw.isTripped || Task.isCancelled || generation != g || self.mode != .autoType || onlySuggestDevices || !owns(ref, token: token)
            if cancelled, generation == g { cancelCommand() }
            if !cancelled, sameLogin(context, io: io), io.revision != revision { retry = true }
            event = cancelled ? .cancelled : nil
        }
        return event
    }

    /// Piden otra vez contraseña tras enviar `p`: con otra cuenta (-J: tras la del salto, la del destino), la anterior
    /// ha entrado; con la misma o sin cuenta, no valía (`rejected`).
    private func resolveRepeated(_ p: Pending, asking account: String?) -> Event? {
        if let asked = p.account?.lowercased(), let now = account?.lowercased(), asked != now {
            if let token = p.reservation { ledger.confirm(p.ref, reservation: token) } else { ledger.confirmDirect(p.ref) }
            return nil
        }
        return rejected(p)
    }

    /// No ha valido: sólo la por defecto escrita sola queda bloqueada (`.failed`); las demás sueltan su reserva y no
    /// se vuelven a escribir solas en esta orden (`.rejected`: la escribes tú).
    private func rejected(_ p: Pending) -> Event {
        if p.blocks {
            if let token = p.reservation { ledger.markFailed(p.ref, reservation: token) } else { ledger.markFailed(p.ref) }
        } else if let token = p.reservation {
            ledger.release(p.ref, reservation: token)
        }
        cancelCommand()
        return p.blocks ? .failed(p.ref) : .rejected(p.ref)
    }

    /// (aparte: con el cierre dentro de observe, el compilador de Swift 6.3 se cae en ClosureLifetimeFixup)
    nonisolated private static func secret(_ ref: CredentialRef, in store: CredentialStore) async -> String? {
        await store.passwordInBackground(for: ref)
    }

    nonisolated private static func read(_ ref: CredentialRef, in store: CredentialStore) async -> CredentialRead {
        await store.readInBackground(ref)
    }

    nonisolated private static func available(_ candidates: [CredentialCandidate], in store: CredentialStore) async -> ([CredentialCandidate], Bool) {
        let r = await store.availabilityInBackground(candidates)
        return (r.available, r.failed)
    }

    /// El equipo corta la conexión (no es un rechazo de la contraseña): «Connection to core-01 closed.», «Connection
    /// closed by 192.0.2.11 port 22», «Connection reset by …», «… timed out».
    static let cutBeforePrompt = Pattern(#"\bconnection (?:to \S+ closed|closed by|reset)\b|\btimed out\b"#)

    /// `busy`: ya se está escribiendo una (dos clics seguidos no la mandan dos veces).
    public enum ManualResult: Equatable, Sendable { case typed, notAsked, missing, busy, pending }

    /// El selector del login interno: una ref ofrecida para su id y su pantalla, con usuario estricto. Mantiene la
    /// propuesta durante la lectura para que un doble clic sea `busy`; cancelarla invalida también el await pendiente.
    /// La eliges tú: también la por defecto bloqueada (sin reserva), y si no vale no se bloquea.
    public func choose(_ ref: CredentialRef, offer token: UUID, into io: TerminalIO) async -> ManualResult {
        guard operation == nil else { return .busy }
        guard let proposal = offer, proposal.id == token, proposal.refs.contains(ref) else { return .notAsked }
        guard current(proposal, io: io) else { offer = nil; return .notAsked }
        guard compatible(proposal.request, from: candidates(proposal.request)).contains(ref) else { return .notAsked }
        let probe = ledger.reserveProbe(ref)
        if probe.result == .wait { return .pending }
        let reservationToken = probe.token
        let g = generation, op = UUID()
        if let t = reservationToken { reservation = (ref, g, t) }
        operation = op
        defer {
            releaseReservation(g)
            if operation == op { operation = nil }
            if offer?.id == token { offer = nil }
        }
        guard let pw = await Self.secret(ref, in: store) else { return .missing }
        guard !Task.isCancelled, offer?.id == token, current(proposal, io: io) else { return .notAsked }
        var held = reservationToken
        if let t = held, !owns(ref, token: t) {
            // (otra pestaña la ha reservado: no; un fallo de la por defecto mientras se leía no cuenta, la eliges tú)
            guard ledger.isBlocked(ref) else { return .notAsked }
            held = nil
        }
        guard compatible(proposal.request, from: candidates(proposal.request)).contains(ref) else { return .notAsked }
        reservation = nil
        pending = (ref, io.cursorRow, held, proposal.request.account, io.revision, false)
        leftSite = false
        handledSite = proposal.site
        offer = nil
        io.sendLine(pw)
        return .typed
    }

    /// Elección manual (menú 🔑, botones): sin la regla de usuario ni el bloqueo de la por defecto (la eliges tú), y si
    /// no vale no se bloquea. También en la pregunta del askpass al abrir la sesión. El Llavero se lee fuera del hilo
    /// principal; justo antes de escribirla se comprueba que la siguen pidiendo.
    public func typeManually(_ ref: CredentialRef, into io: TerminalIO) async -> ManualResult {
        await typeManually(ref, into: io) { [store] in await store.passwordInBackground(for: ref) }
    }

    /// La escrita en un botón (sin Llavero): igual que la manual; `button` sólo la nombra en los avisos.
    public func typeLiteral(_ password: String, button: String, into io: TerminalIO) async -> ManualResult {
        guard !password.isEmpty else { return .missing }
        return await typeManually(.named(L("botón «\(button)»")), into: io) { password }
    }

    private func typeManually(_ ref: CredentialRef, into io: TerminalIO, secret: () async -> String?) async -> ManualResult {
        guard PasswordPrompt.acceptsManual(io.cursorLine) else { return .notAsked }
        let site = "\(io.cursorRow):\(io.cursorLine.trimmed)"
        guard operation == nil, site != handledSite || pending == nil else { return .busy }
        waitingProbe?.task.cancel()
        waitingProbe = nil
        offer = nil
        let g = generation, op = UUID()
        operation = op
        defer { if operation == op { operation = nil } }
        guard let pw = await secret() else { return .missing }
        guard generation == g, !Task.isCancelled else { return .notAsked }
        // (mientras se leía, la pantalla puede haber cambiado)
        guard "\(io.cursorRow):\(io.cursorLine.trimmed)" == site else { return .notAsked }
        if let p = pending, let token = p.reservation { ledger.release(p.ref, reservation: token) }
        let asked = PasswordPrompt.detect(cursorLine: io.cursorLine, above: []) ?? PasswordPrompt.askpassRequest(io.cursorLine)
        pending = (ref, io.cursorRow, nil, asked?.account, io.revision, false)
        leftSite = false
        io.sendLine(pw)
        handledSite = site
        return .typed
    }

    /// «Escribir sin esperar a que la pida» (menú 🔑): la manda al terminal aunque la línea no sea «Password:» (un
    /// prompt que no se reconoce). Intro sólo con `pressReturn`. La eliges tú: también la por defecto bloqueada.
    public func typeAnyway(_ ref: CredentialRef, into io: TerminalIO, pressReturn: Bool) async -> ManualResult {
        guard operation == nil else { return .busy }
        waitingProbe?.task.cancel()
        waitingProbe = nil
        offer = nil
        let g = generation, op = UUID()
        operation = op
        defer { if operation == op { operation = nil } }
        guard let pw = await store.passwordInBackground(for: ref) else { return .missing }
        guard generation == g, !Task.isCancelled else { return .notAsked }
        if pressReturn { io.sendLine(pw) } else { io.send(pw) }
        return .typed
    }
}
