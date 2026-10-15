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
/// desde el salto y la contraseña sólo cuando la piden. Una sola pestaña prueba la contraseña a la vez; si falla, las
/// demás no la escriben. Reintentos: sólo las fallidas que siguen en el prompt del salto, `maxRetries` veces.
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
        var sent: (ref: CredentialRef, row: Int)?
        let clock = ContinuousClock()
        var end = clock.now + settings.deviceTimeout
        while clock.now < end {
            try await Task.sleep(for: settings.poll)
            try abort.check()
            let line = io.cursorLine.trimmed
            let moved = io.cursorRow > (sent?.row ?? mark)
            if let s = sent {
                ledger.keepProbing(s.ref)
                if PasswordPrompt.asksForPassword(line), io.cursorRow != s.row {    // otra vez: no valía
                    ledger.markFailed(s.ref)
                    return .denied(L("«\(s.ref)» no ha valido: no se prueba en más equipos (15 min)"))
                }
                if jump.matches(line), moved {                                     // volvió al salto
                    if io.lines(from: s.row).contains(where: Self.denied.matches) {
                        ledger.markFailed(s.ref)
                        return .denied(L("«\(s.ref)» denegada"))
                    }
                    ledger.release(s.ref)
                    return .failed(L("no se ha podido conectar desde el salto"))
                }
                if DevicePrompt.generic.matches(line), moved {
                    ledger.confirm(s.ref)
                    return .connected
                }
                continue
            }
            if let request = PasswordPrompt.detect(cursorLine: line, above: io.linesAbove(3)) {
                let cands = [list.credential].compactMap { $0 }.filter { store.contains($0.ref) }
                switch policy.decide(request, commandUser: target.user, candidates: cands, isBlocked: ledger.isBlocked) {
                case .manual(.recentlyFailed(let r)): return .skipped(L("«\(r)» falló hace poco: la escribes tú"))
                case .manual(let why): return .skipped(L("contraseña a mano (\(Askpass.explain(why)))"))
                case .inject(let ref):
                    switch ledger.beginProbe(ref) {
                    case .blocked: return .skipped(L("«\(ref)» falló hace poco: la escribes tú"))
                    case .wait:                                            // otra pestaña la está probando:
                        end = max(end, clock.now + settings.poll * 4)       // (no se agota mientras espera su turno)
                        continue
                    case .go:
                        guard let pw = await store.passwordInBackground(for: ref) else {
                            ledger.release(ref)
                            return .failed(L("no está en el Llavero"))
                        }
                        // Esc antes de escribirla: no se ha probado, que no se queden esperando las demás
                        do { try abort.check() } catch { ledger.release(ref); throw error }
                        let row = io.cursorRow                  // (antes de enviar: la respuesta puede ser inmediata)
                        io.sendLine(pw)
                        sent = (ref, row)
                        set(target, .passwordSent)
                        end = clock.now + settings.passwordTimeout
                    }
                }
                continue
            }
            if jump.matches(line), moved { return .failed(L("no se ha podido conectar desde el salto")) }
            if DevicePrompt.generic.matches(line), moved { return .connected }           // clave pública
        }
        if let s = sent {                      // ni sí ni no: no se prueba en más equipos (para no bloquear la cuenta)
            ledger.markFailed(s.ref)
            return .denied(L("sin respuesta a «\(s.ref)»"))
        }
        return .failed(L("el equipo no ha contestado"))
    }

    private func set(_ d: Endpoint, _ s: DeviceStatus) {
        let key = list.devices.first { $0.host == d.host && ($0.port == d.port) } ?? d
        status[key] = s
        onChange?(key, s)
    }
}
