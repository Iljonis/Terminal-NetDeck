import Foundation

/// «Lista» de NetDeck: varios equipos detrás de un mismo salto, cada uno en su pestaña.
public struct JumpList: Hashable, Sendable {
    public var name: String
    /// Alias del ssh_config del salto (o usuario@equipo).
    public var jump: String
    /// Usuario en los equipos (nil = el de cada línea o el del salto).
    public var user: String?
    public var devices: [Endpoint]
    /// La contraseña de los equipos y sus dueños (se aplica la misma regla de usuario).
    public var credential: CredentialCandidate?

    public init(name: String, jump: String, user: String? = nil, devices: [Endpoint], credential: CredentialCandidate? = nil) {
        self.name = name
        self.jump = jump
        self.user = user
        self.devices = devices
        self.credential = credential
    }

    /// Texto pegado: uno por línea o separados por espacios/comas; «#» comenta. Sin repetir.
    public static func devices(in text: String) -> [Endpoint] {
        var seen = Set<Endpoint>()
        return text.components(separatedBy: .newlines)
            .map { $0.components(separatedBy: "#")[0] }
            .flatMap { $0.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace }) }
            .compactMap { Endpoint(parsing: String($0)) }
            .filter { seen.insert($0).inserted }
    }
}

public enum DeviceStatus: Equatable, Sendable {
    case pending
    case waitingJump
    case connecting
    case passwordSent
    case connected
    /// La contraseña no vale («Permission denied», la vuelven a pedir…): no se prueba en más equipos (15 min).
    case denied(String)
    case failed(String)
    /// No se intenta: contraseña bloqueada, regla de usuario, Esc…
    case skipped(String)

    /// Para la barra de estado.
    public var texto: String {
        switch self {
        case .pending: L("en cola")
        case .waitingJump: L("esperando al salto")
        case .connecting: L("conectando")
        case .passwordSent: L("contraseña enviada")
        case .connected: L("dentro ✓")
        case .denied(let why): L("denegada: \(why)")
        case .failed(let why): L("fallo: \(why)")
        case .skipped(let why): L("sin intentar: \(why)")
        }
    }

    /// Se puede reintentar sola (nunca una denegada: bloquearía la cuenta AD).
    public var isRetryable: Bool { if case .failed = self { return true } else { return false } }
}

/// Abre la lista: pestañas escalonadas (que no lleguen todas al salto en el mismo instante), en cada una «ssh equipo»
/// desde el salto y la contraseña sólo cuando la piden. Una sola pestaña prueba la contraseña a la vez (las demás
/// esperan su turno, como mucho `passwordTimeout`); si falla, las demás no la escriben. Reintentos: sólo las fallidas
/// que siguen en el prompt del salto, `maxRetries` veces.
@MainActor
public final class JumpBatchRunner {
    public struct Settings: Sendable {
        public var spacing: Duration = .milliseconds(600)
        public var jumpTimeout: Duration = .seconds(30)
        public var deviceTimeout: Duration = .seconds(30)
        public var passwordTimeout: Duration = .seconds(25)
        public var poll: Duration = .milliseconds(500)
        public var maxRetries = 1
        public init() {}
    }

    public typealias Opener = @MainActor (Endpoint) async -> (any TerminalIO)?
    static let denied = Pattern(#"permission denied|authentication failed|access denied|login incorrect"#)

    public let list: JumpList
    public var settings: Settings
    public private(set) var status: [Endpoint: DeviceStatus] = [:]
    public var onChange: ((Endpoint, DeviceStatus) -> Void)?

    private let store: CredentialStore
    private let policy: CredentialPolicy
    private let ledger: CredentialLedger
    private let abort: AbortSwitch
    private let open: Opener
    private var panes: [Endpoint: (io: any TerminalIO, jump: DevicePrompt)] = [:]
    private var attempts: [Endpoint: Int] = [:]

    public init(list: JumpList, settings: Settings = .init(), store: CredentialStore, policy: CredentialPolicy = .init(),
                ledger: CredentialLedger, abort: AbortSwitch, open: @escaping Opener) {
        self.list = list
        self.settings = settings
        self.store = store
        self.policy = policy
        self.ledger = ledger
        self.abort = abort
        self.open = open
        list.devices.forEach { status[$0] = .pending }
    }

    public func run() async {
        var tasks: [Task<Void, Never>] = []
        for d in list.devices {
            guard !abort.isTripped else { set(d, .skipped("Esc")); continue }
            guard let io = await open(d) else { set(d, .failed(L("no se ha podido abrir la pestaña"))); continue }
            tasks.append(Task { @MainActor in await self.connect(d, io: io, jump: nil) })
            try? await Task.sleep(for: settings.spacing)
        }
        for t in tasks { await t.value }
    }

    /// Reintenta las fallidas (no las denegadas) que siguen en el prompt del salto.
    public func retryFailed() async {
        var tasks: [Task<Void, Never>] = []
        for d in list.devices {
            guard !abort.isTripped else { break }                            // (Esc: tampoco se reintenta)
            guard status[d]?.isRetryable == true, attempts[d, default: 0] <= settings.maxRetries,
                  let p = panes[d], p.jump.matches(p.io.cursorLine) else { continue }
            tasks.append(Task { @MainActor in await self.connect(d, io: p.io, jump: p.jump) })
            try? await Task.sleep(for: settings.spacing)
        }
        for t in tasks { await t.value }
    }

    // MARK: - un equipo

    func connect(_ device: Endpoint, io: any TerminalIO, jump known: DevicePrompt?) async {
        attempts[device, default: 0] += 1
        do {
            set(device, .waitingJump)
            var target = device
            if target.user == nil { target.user = list.user }
            guard target.isShellSafe else { return set(device, .failed(L("nombre no válido para la shell del salto"))) }
            // 1. el prompt del salto
            guard let jumpLine = try await Poll.until(every: settings.poll, timeout: settings.jumpTimeout, abort: abort, {
                DevicePrompt.generic.matches(io.cursorLine.trimmed) ? io.cursorLine.trimmed : nil
            }) else { return set(device, .failed(L("el salto no ha llegado a su prompt"))) }
            let jump = known ?? DevicePrompt(sample: jumpLine)
            panes[device] = (io, jump)
            // 2. ssh desde el salto
            set(device, .connecting)
            let mark = io.cursorRow
            try abort.check()
            io.sendLine(target.port.map { "ssh -p \($0) \(Endpoint(user: target.user, host: target.host))" } ?? "ssh \(target)")
            set(device, try await login(target, io: io, jump: jump, mark: mark))
        } catch {
            set(device, .skipped("Esc"))
        }
    }

    private func login(_ target: Endpoint, io: any TerminalIO, jump: DevicePrompt, mark: Int) async throws -> DeviceStatus {
        var sent: (ref: CredentialRef, row: Int, token: UUID)?
        var reservation: (ref: CredentialRef, token: UUID)?
        var secondFactor = false
        // (Esc o el plazo de la interfaz no detienen el ssh del salto ni un TACACS lento. Una vez enviada, sólo un
        // resultado conocido resuelve la reserva; si falta, la pestaña continúa vigilándola. Sin ese soporte se
        // conserva hasta que la persona la restablezca)
        defer {
            if let s = sent {
                if owns(s.ref, token: s.token) {
                    (io as? any PendingAuthenticationIO)?.retainPendingAuthentication(s.ref, reservation: s.token)
                }
            } else if let r = reservation {
                ledger.release(r.ref, reservation: r.token)
            }
        }
        let clock = ContinuousClock()
        var end = clock.now + settings.deviceTimeout
        while clock.now < end {
            try await Task.sleep(for: settings.poll)
            try abort.check()
            let line = io.cursorLine.trimmed
            let moved = io.cursorRow > (sent?.row ?? mark)
            if let s = sent {
                guard owns(s.ref, token: s.token) else { return .skipped(L("Conexión cancelada")) }
                let output = io.lines(from: s.row)
                if output.contains(where: { SecretPrompt.asks($0) && !PasswordPrompt.asksForPassword($0) }) {
                    secondFactor = true                          // (un OTP rechazado no acusa a la contraseña anterior)
                }
                if !secondFactor, output.contains(where: Self.denied.matches) {
                    ledger.markFailed(s.ref, reservation: s.token)
                    return .denied(L("«\(s.ref)» denegada"))
                }
                if PasswordPrompt.asksForPassword(line), io.cursorRow != s.row {    // otra vez: no valía
                    if secondFactor { return .failed(L("no se ha podido conectar desde el salto")) }
                    ledger.markFailed(s.ref, reservation: s.token)
                    return .denied(L("«\(s.ref)» no ha valido: no se prueba en más equipos (15 min)"))
                }
                if jump.matches(line), moved {                                     // volvió al salto
                    ledger.release(s.ref, reservation: s.token)
                    return .failed(L("no se ha podido conectar desde el salto"))
                }
                if DevicePrompt.generic.matches(line), moved {
                    ledger.confirm(s.ref, reservation: s.token)
                    return .connected
                }
                continue
            }
            if let request = PasswordPrompt.detect(cursorLine: line, above: io.linesAbove(3)) {
                // (la petición en pantalla: si cambia mientras se espera turno o se lee el Llavero, no se escribe)
                let site = "\(io.cursorRow):\(line)"
                func asked() -> Bool { "\(io.cursorRow):\(io.cursorLine.trimmed)" == site }
                let cands = await store.availableInBackground([list.credential].compactMap { $0 })
                try abort.check()
                guard asked() else { continue }
                switch policy.decide(request, commandUser: target.user, candidates: cands, isBlocked: ledger.isBlocked) {
                case .manual(.recentlyFailed(let r)): return .skipped(L("«\(r)» falló hace poco: la escribes tú"))
                case .manual(let why): return .skipped(L("contraseña a mano (\(Askpass.explain(why)))"))
                case .inject(let ref):
                    // (otro equipo de la lista u otra pestaña la está probando: se espera su resultado, sondeando y
                    // sin quitarle nunca la reserva; con la misma contraseña, entran uno detrás de otro)
                    var probe = ledger.reserveProbe(ref)
                    let turn = clock.now + settings.passwordTimeout
                    while probe.result == .wait, clock.now < turn, asked() {
                        try await Task.sleep(for: settings.poll)
                        try abort.check()
                        if asked() { probe = ledger.reserveProbe(ref) }
                    }
                    switch probe.result {
                    case .blocked: return .skipped(L("«\(ref)» falló hace poco: la escribes tú"))
                    case .wait:
                        if !asked() { continue }                     // (ya no la piden: se mira qué ha pasado)
                        return .skipped(Askpass.explain(.pendingAttempt(ref)))
                    case .go:
                        guard let token = probe.token else { return .skipped(L("Conexión cancelada")) }
                        reservation = (ref, token)
                        guard let pw = await store.passwordInBackground(for: ref) else {
                            return .failed(L("no está en el Llavero"))
                        }
                        // Esc antes de escribirla: no se ha probado, que no se queden esperando las demás
                        try abort.check()
                        try Task.checkCancellation()
                        guard owns(ref, token: token), asked() else {
                            return .skipped(L("Conexión cancelada"))
                        }
                        let row = io.cursorRow                  // (antes de enviar: la respuesta puede ser inmediata)
                        sent = (ref, row, token)
                        io.sendLine(pw)
                        (io as? any PendingAuthenticationIO)?.registerPendingAuthentication(ref, reservation: token)
                        set(target, .passwordSent)
                        end = clock.now + settings.passwordTimeout
                    }
                }
                continue
            }
            if jump.matches(line), moved { return .failed(L("no se ha podido conectar desde el salto")) }
            if DevicePrompt.generic.matches(line), moved { return .connected }           // clave pública
        }
        // (sin resultado no se acusa ni se libera: puede seguir autenticándose o esperando un OTP)
        if let s = sent { return .skipped(Askpass.explain(.pendingAttempt(s.ref))) }
        return .failed(L("el equipo no ha contestado"))
    }

    private func owns(_ ref: CredentialRef, token: UUID) -> Bool {
        if case .probing(_, _, let current) = ledger.state(of: ref) { return current == token }
        return false
    }

    private func set(_ d: Endpoint, _ s: DeviceStatus) {
        let key = list.devices.first { $0.host == d.host && ($0.port == d.port) } ?? d
        status[key] = s
        onChange?(key, s)
    }
}
