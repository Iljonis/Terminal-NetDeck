import Foundation
import Testing
@testable import NetDeckCore

@Suite @MainActor struct ListaReservasCredencialesTests {
    let ref = CredentialRef.named("AD")
    let device = Endpoint(host: "192.0.2.11")

    private func runner(store: any CredentialStore, ledger: CredentialLedger, abort: AbortSwitch,
                        io: any TerminalIO) -> JumpBatchRunner {
        let list = JumpList(name: "prueba", jump: "bastion", user: "tu.usuario", devices: [device],
                            credential: .init(ref: ref, owners: ["tu.usuario"], origin: .defaultCredential))
        var settings = JumpBatchRunner.Settings()
        settings.spacing = .milliseconds(1)
        settings.poll = .milliseconds(1)
        settings.jumpTimeout = .seconds(3)
        settings.deviceTimeout = .seconds(3)
        settings.passwordTimeout = .milliseconds(80)
        return JumpBatchRunner(list: list, settings: settings, store: store, ledger: ledger, abort: abort) { _ in io }
    }

    private func terminal(_ response: [String]) -> FakeTerminal {
        FakeTerminal(["tu.usuario@bastion:~$ "]) { command in
            command.hasPrefix("ssh ") ? ["tu.usuario@192.0.2.11's password:"] : response
        }
    }

    @Test func cancelarMientrasLeeNoEnviaNiDejaReserva() async {
        let abort = AbortSwitch(), ledger = CredentialLedger()
        let store = CredencialAlLeer { abort.trip() }
        let io = terminal([])
        let batch = runner(store: store, ledger: ledger, abort: abort, io: io)
        await batch.run()
        #expect(io.sent == ["ssh tu.usuario@192.0.2.11\r"])
        #expect(ledger.state(of: ref) == nil)
        if case .skipped = batch.status[device] {} else { Issue.record("la cancelación no detuvo la lista") }
    }

    @Test func cancelarDespuesDeEnviarConservaLaReservaHastaSaberElResultado() async {
        let abort = AbortSwitch(), ledger = CredentialLedger(), io = terminal([])
        let batch = runner(store: MemoryCredentialStore([ref: "secreto-demo"]), ledger: ledger, abort: abort, io: io)
        batch.onChange = { _, state in if state == .passwordSent { abort.trip() } }
        await batch.run()
        #expect(io.sent == ["ssh tu.usuario@192.0.2.11\r", "secreto-demo\r"])
        #expect(ledger.reserveProbe(ref).result == .wait)
        #expect(!ledger.isBlocked(ref))
    }

    @Test func unResetDuranteLaLecturaNoEnviaNiSueltaLaReservaNueva() async throws {
        let ledger = CredentialLedger(), box = TokenLista()
        let ref = self.ref
        let store = CredencialAlLeer {
            ledger.reset(ref)
            box.set(ledger.reserveProbe(ref).token)
        }
        let io = terminal([])
        let batch = runner(store: store, ledger: ledger, abort: AbortSwitch(), io: io)
        await batch.run()
        let fresh = try #require(box.get())
        defer { ledger.release(ref, reservation: fresh) }
        #expect(io.sent == ["ssh tu.usuario@192.0.2.11\r"])
        if case .probing(_, _, let token) = ledger.state(of: ref) { #expect(token == fresh) }
        else { Issue.record("la lectura anterior soltó la reserva nueva") }
    }

    @Test func lasRespuestasAntiguasNoResuelvenLaReservaNueva() async throws {
        for response in [["core-01#"], ["Permission denied", "Password:"], ["tu.usuario@bastion:~$ "]] {
            let ledger = CredentialLedger(), io = terminal(response)
            let batch = runner(store: MemoryCredentialStore([ref: "secreto-demo"]), ledger: ledger, abort: AbortSwitch(), io: io)
            var fresh: UUID?
            batch.onChange = { _, state in
                if state == .passwordSent { ledger.reset(ref); fresh = ledger.reserveProbe(ref).token }
            }
            await batch.run()
            let token = try #require(fresh)
            defer { ledger.release(ref, reservation: token) }
            if case .probing(_, _, let current) = ledger.state(of: ref) { #expect(current == token) }
            else { Issue.record("una respuesta antigua cambió la reserva nueva") }
        }
    }

    @Test func unSegundoFactorFallidoOAgotadoNoBloqueaLaContrasena() async {
        for (index, response) in [["Verification code:", "Permission denied", "tu.usuario@bastion:~$ "], ["Verification code:"]].enumerated() {
            let ledger = CredentialLedger(), io = terminal(response)
            let batch = runner(store: MemoryCredentialStore([ref: "secreto-demo"]), ledger: ledger, abort: AbortSwitch(), io: io)
            await batch.run()
            #expect(!ledger.isBlocked(ref))
            if index == 0 {
                #expect(ledger.state(of: ref) == nil)             // (el prompt del salto confirma que ssh terminó)
                if case .failed = batch.status[device] {} else { Issue.record("no se reconoció el retorno al salto") }
            } else {
                #expect(ledger.reserveProbe(ref).result == .wait) // (el OTP sigue pendiente, sin resultado conocido)
                if case .skipped = batch.status[device] {} else { Issue.record("el segundo factor pendiente se atribuyó a la contraseña") }
            }
            #expect(io.sent.filter { $0 == "secreto-demo\r" }.count == 1)
        }
    }

    @Test func unTacacsTardioNoPermiteUnSegundoIntentoAlVencerLaInterfaz() async {
        let ledger = CredentialLedger(), io = terminal([])
        let store = MemoryCredentialStore([ref: "secreto-demo"])
        let batch = runner(store: store, ledger: ledger, abort: AbortSwitch(), io: io)
        await batch.run()
        #expect(!ledger.isBlocked(ref) && ledger.reserveProbe(ref).result == .wait)
        if case .skipped = batch.status[device] {} else { Issue.record("el plazo no demuestra que ssh haya terminado") }
        let other = terminal([])
        let second = runner(store: store, ledger: ledger, abort: AbortSwitch(), io: other)
        await second.run()                                      // (no espera indefinidamente ni envía otra contraseña)
        #expect(other.sent == ["ssh tu.usuario@192.0.2.11\r"])
        if case .skipped = second.status[device] {} else { Issue.record("se intentó de nuevo mientras TACACS seguía pendiente") }
        io.screen += ["Permission denied", "tu.usuario@bastion:~$ "] // (respuesta tardía, cuando el observador ya terminó)
        #expect(ledger.reserveProbe(ref).result == .wait)        // (se conserva hasta comprobar el resultado o restablecer)
    }

    @Test func losIntentosEnviadosSinResultadoSeTransfierenALaPestana() async {
        for outcome in 0..<3 {
            let ledger = CredentialLedger(), abort = AbortSwitch()
            let io = TerminalListaPendiente(terminal(outcome == 2 ? ["Verification code:", "Password:"] : []))
            let batch = runner(store: MemoryCredentialStore([ref: "secreto-demo"]), ledger: ledger, abort: abort, io: io)
            batch.onChange = { _, state in
                if state == .passwordSent {
                    #expect(io.registered.count == 1)            // (registrado antes del aviso y de poder reconectar)
                    if outcome == 1 { abort.trip() }
                }
            }
            await batch.run()                                  // (plazo, Esc o segundo factor sin resultado conocido)
            #expect(io.registered.count == 1 && io.registered.first?.ref == ref)
            #expect(io.retained.count == 1 && io.retained.first?.ref == ref)
            #expect(io.registered.first?.token == io.retained.first?.token)
            if case .probing(_, _, let token) = ledger.state(of: ref) { #expect(token == io.retained.first?.token) }
            else { Issue.record("se perdió el intento que debe vigilar la pestaña") }
        }
    }

    @Test func unIntentoResueltoOReemplazadoNoSeTransfiere() async {
        for response in [["core-01#"], ["Permission denied", "Password:"], ["tu.usuario@bastion:~$ "], []] {
            let ledger = CredentialLedger(), io = TerminalListaPendiente(terminal(response))
            let batch = runner(store: MemoryCredentialStore([ref: "secreto-demo"]), ledger: ledger, abort: AbortSwitch(), io: io)
            if response.isEmpty { batch.onChange = { _, state in if state == .passwordSent { ledger.reset(ref) } } }
            await batch.run()                                  // (éxito, rechazo, vuelta al salto o reserva reemplazada)
            #expect(io.registered.count == 1 && io.retained.isEmpty)
        }
        let ledger = CredentialLedger(), abort = AbortSwitch(), io = TerminalListaPendiente(terminal([]))
        let batch = runner(store: CredencialAlLeer { abort.trip() }, ledger: ledger, abort: abort, io: io)
        await batch.run()                                      // (cancelada antes de enviar: sólo se libera)
        #expect(io.registered.isEmpty && io.retained.isEmpty && ledger.state(of: ref) == nil)
    }

    // MARK: - varios equipos con la misma contraseña

    /// Una lista de varios equipos y sus pestañas (cada una contesta «password:» al ssh y nada a la contraseña).
    private func lista(_ hosts: [String], ledger: CredentialLedger, passwordTimeout: Duration = .seconds(5))
        -> (batch: JumpBatchRunner, panes: [Endpoint: FakeTerminal]) {
        let devices = hosts.map { Endpoint(host: $0) }
        let panes = Dictionary(uniqueKeysWithValues: devices.map { d in
            (d, FakeTerminal(["tu.usuario@bastion:~$ "]) { $0.hasPrefix("ssh ") ? ["tu.usuario@\(d.host)'s password:"] : [] })
        })
        let list = JumpList(name: "prueba", jump: "bastion", user: "tu.usuario", devices: devices,
                            credential: .init(ref: ref, owners: ["tu.usuario"], origin: .defaultCredential))
        var settings = JumpBatchRunner.Settings()
        settings.spacing = .milliseconds(1)
        settings.poll = .milliseconds(1)
        settings.jumpTimeout = .seconds(5)
        settings.deviceTimeout = .seconds(5)
        settings.passwordTimeout = passwordTimeout
        let store = MemoryCredentialStore([ref: "secreto-demo"])
        return (JumpBatchRunner(list: list, settings: settings, store: store, ledger: ledger, abort: AbortSwitch()) { panes[$0] }, panes)
    }

    /// Antes, el que encontraba la reserva de otro se saltaba sin reintento (con 10 equipos quedaba media lista sin
    /// probar). Ahora espera su turno: entran todos, de uno en uno, y cada uno la escribe una sola vez.
    @Test func losQueCompartenCredencialEsperanSuTurnoYEntranTodos() async {
        let ledger = CredentialLedger()
        let (batch, panes) = lista(["192.0.2.11", "192.0.2.12", "192.0.2.13"], ledger: ledger)
        var probando = 0, maximo = 0
        batch.onChange = { device, state in
            if state == .connected { probando -= 1 }
            guard state == .passwordSent, let io = panes[device] else { return }
            probando += 1
            maximo = max(maximo, probando)
            Task { @MainActor in                                // (entra al rato: mientras, las demás esperan)
                try? await Task.sleep(for: .milliseconds(20))
                io.screen += ["core-\(device.host.split(separator: ".").last ?? "")#"]
            }
        }
        await batch.run()
        for (device, io) in panes {
            #expect(batch.status[device] == .connected, "\(device.host): \(String(describing: batch.status[device]))")
            #expect(io.sent == ["ssh tu.usuario@\(device.host)\r", "secreto-demo\r"])
        }
        #expect(maximo == 1)                                     // (nunca dos pruebas a la vez)
        if case .confirmed = ledger.state(of: ref) {} else { Issue.record("la última no quedó confirmada") }
    }

    @Test func siLaPrimeraNoValeLasQueEsperanNoLaEscriben() async {
        let ledger = CredentialLedger()
        let (batch, panes) = lista(["192.0.2.11", "192.0.2.12"], ledger: ledger)
        batch.onChange = { device, state in
            guard state == .passwordSent, let io = panes[device] else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                io.screen += ["Permission denied (publickey,password).", "tu.usuario@bastion:~$ "]
            }
        }
        await batch.run()
        let sent = panes.values.filter { $0.sent.contains("secreto-demo\r") }
        #expect(sent.count == 1 && ledger.isBlocked(ref))
        #expect(batch.status.values.filter { if case .denied = $0 { true } else { false } }.count == 1)
        #expect(batch.status.values.contains(.skipped(L("«\(ref)» falló hace poco: la escribes tú"))))
    }

    /// La reserva de otra pestaña que no se resuelve: se espera `passwordTimeout` y se deja sin intentar, sin
    /// quitársela ni escribir nada.
    @Test func unaReservaAjenaSinResultadoSeEsperaYNoSeToma() async throws {
        let ledger = CredentialLedger()
        let foreign = try #require(ledger.reserveProbe(ref).token)
        let (batch, panes) = lista(["192.0.2.11"], ledger: ledger, passwordTimeout: .milliseconds(80))
        let start = ContinuousClock.now
        await batch.run()
        #expect(ContinuousClock.now - start >= .milliseconds(80))
        #expect(batch.status[device] == .skipped(Askpass.explain(.pendingAttempt(ref))))
        #expect(panes[device]?.sent == ["ssh tu.usuario@192.0.2.11\r"])
        if case .probing(_, _, let token) = ledger.state(of: ref) { #expect(token == foreign) }
        else { Issue.record("se quitó la reserva ajena") }
        ledger.release(ref, reservation: foreign)
    }

    /// Si mientras espera turno el equipo deja de pedirla (corta y vuelve el salto), al quedar libre no se escribe
    /// la contraseña en la shell del salto.
    @Test func siDejanDePedirlaMientrasEsperaNoLaEscribeEnElSalto() async throws {
        let ledger = CredentialLedger()
        let foreign = try #require(ledger.reserveProbe(ref).token)
        let (batch, panes) = lista(["192.0.2.11"], ledger: ledger)
        let io = try #require(panes[device])
        Task { @MainActor in
            while !PasswordPrompt.asksForPassword(io.cursorLine) { try? await Task.sleep(for: .milliseconds(2)) }
            try? await Task.sleep(for: .milliseconds(20))
            io.screen += ["Connection closed by 192.0.2.11 port 22", "tu.usuario@bastion:~$ "]
            ledger.release(ref, reservation: foreign)         // (queda libre justo cuando ya no la piden)
        }
        await batch.run()
        #expect(io.sent == ["ssh tu.usuario@192.0.2.11\r"])
        #expect(batch.status[device] == .failed(L("no se ha podido conectar desde el salto")))
        #expect(ledger.state(of: ref) == nil)
    }
}

@MainActor
private final class TerminalListaPendiente: PendingAuthenticationIO {
    let base: FakeTerminal
    var registered: [(ref: CredentialRef, token: UUID)] = []
    var retained: [(ref: CredentialRef, token: UUID)] = []
    init(_ base: FakeTerminal) { self.base = base }
    func registerPendingAuthentication(_ ref: CredentialRef, reservation: UUID) { registered.append((ref, reservation)) }
    func retainPendingAuthentication(_ ref: CredentialRef, reservation: UUID) { retained.append((ref, reservation)) }
    func send(bytes: [UInt8]) { base.send(bytes: bytes) }
    var cursorRow: Int { base.cursorRow }
    var cursorLine: String { base.cursorLine }
    func lines(from row: Int) -> [String] { base.lines(from: row) }
    var revision: Int { base.revision }
    var promptRule: PromptRule? { base.promptRule }
}

private final class CredencialAlLeer: CredentialStore, Sendable {
    private let action: @Sendable () -> Void
    init(_ action: @escaping @Sendable () -> Void) { self.action = action }
    func password(for ref: CredentialRef) throws -> String? { action(); return "secreto-demo" }
    func contains(_ ref: CredentialRef) -> Bool { true }
    func save(_ password: String, for ref: CredentialRef) throws {}
    func delete(_ ref: CredentialRef) throws {}
    func accounts(in service: CredentialRef.Service) throws -> [String] { [] }
}

private final class TokenLista: @unchecked Sendable {
    private let lock = NSLock()
    private var token: UUID?
    func set(_ value: UUID?) { lock.withLock { token = value } }
    func get() -> UUID? { lock.withLock { token } }
}
