import Foundation
import Testing
@testable import NetDeckCore

/// Un trozo de salida puede cambiar la revisión sin cambiar el prompt mientras responde el Llavero.
@Suite @MainActor struct AutopassReintentosTests {
    private let ref = CredentialRef.named("AD")

    private func automation(_ store: AlmacenAutopassDemorado, ledger: CredentialLedger = CredentialLedger()) -> PasswordAutomation {
        let a = PasswordAutomation(mode: .autoType, store: store, ledger: ledger) { _ in
            [.init(ref: .named("AD"), owners: ["tu.usuario"], origin: .defaultCredential)]
        }
        a.settle = .milliseconds(1)
        a.beginCommand("ssh tu.usuario@core-01")
        return a
    }

    private func esperar(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }

    @Test func revisionDuranteLaBusquedaPermiteReobservarElMismoPrompt() async {
        let store = AlmacenAutopassDemorado(demorarConsulta: true), a = automation(store)
        defer { store.continuar(); a.cancelCommand() }
        let io = FakeTerminal(["tu.usuario@core-01's password:"]), gate = AutomationGate()
        let first = Task { await a.observe(io, gate: gate) }
        #expect(await esperar { store.consultas == 1 })
        io.revision += 1
        #expect(await a.observe(io, gate: gate) == nil) // (la salida intermedia se encuentra la búsqueda en curso)
        store.continuar()
        #expect(await first.value == nil)
        #expect(io.sent.isEmpty && store.lecturas == 0)
        #expect(await a.observe(io, gate: gate) == .typed(ref))
        #expect(io.sent == ["secreto-demo\r"] && store.consultas == 2 && store.lecturas == 1)
        #expect(await a.observe(io, gate: gate) == nil)
        #expect(io.sent.count == 1)
    }

    @Test func revisionDuranteLaLecturaDescartaElSecretoYReintentaUnaVez() async {
        let store = AlmacenAutopassDemorado(demorarLectura: true), ledger = CredentialLedger()
        let a = automation(store, ledger: ledger), io = FakeTerminal(["Password:"]), gate = AutomationGate()
        defer { store.continuar(); a.cancelCommand() }
        let first = Task { await a.observe(io, gate: gate) }
        #expect(await esperar { store.lecturas == 1 })
        io.revision += 1
        #expect(await a.observe(io, gate: gate) == nil)
        store.continuar()
        #expect(await first.value == nil)
        #expect(io.sent.isEmpty && ledger.state(of: ref) == nil)
        #expect(await a.observe(io, gate: gate) == .typed(ref))
        #expect(io.sent == ["secreto-demo\r"] && store.lecturas == 2)
    }

    @Test func unaCancelacionDuranteLaConsultaNoReabreElContexto() async {
        let store = AlmacenAutopassDemorado(demorarConsulta: true), a = automation(store)
        defer { store.continuar() }
        let io = FakeTerminal(["Password:"]), gate = AutomationGate()
        let task = Task { await a.observe(io, gate: gate) }
        #expect(await esperar { store.consultas == 1 })
        io.revision += 1
        a.cancelCommand()
        store.continuar()
        #expect(await task.value == .cancelled)
        #expect(await a.observe(io, gate: gate) == nil)
        #expect(a.commandTarget == nil && io.sent.isEmpty && store.lecturas == 0)
    }

    @Test func cambiarDePantallaDuranteLaLecturaNoEnviaLaContrasena() async {
        let store = AlmacenAutopassDemorado(demorarLectura: true), a = automation(store)
        defer { store.continuar(); a.cancelCommand() }
        let io = FakeTerminal(["Password:"]), gate = AutomationGate()
        let task = Task { await a.observe(io, gate: gate) }
        #expect(await esperar { store.lecturas == 1 })
        io.screen = ["core-01#"]
        io.revision += 1
        store.continuar()
        #expect(await task.value == nil)
        #expect(await a.observe(io, gate: gate) == nil)
        #expect(io.sent.isEmpty && a.commandTarget == nil)
    }

    @Test func otraPestanaConfirmadaPermiteReintentarElPromptPendiente() async throws {
        let store = AlmacenAutopassDemorado(), ledger = CredentialLedger()
        let token = try #require(ledger.reserveProbe(ref).token)
        let a = automation(store, ledger: ledger), io = FakeTerminal(["Password:"]), gate = AutomationGate()
        defer { a.cancelCommand() }
        #expect(await a.observe(io, gate: gate) == .manual(.pendingAttempt(ref)))
        #expect(io.sent.isEmpty && store.lecturas == 0)
        ledger.confirm(ref, reservation: token)
        #expect(await a.observe(io, gate: gate) == .typed(ref))
        #expect(io.sent == ["secreto-demo\r"])
    }

    @Test func elAvisoDeReintentoSeEntregaTrasLiberarLaOperacionYLaReserva() async throws {
        let store = AlmacenAutopassDemorado(demorarLectura: true), ledger = CredentialLedger()
        let a = automation(store, ledger: ledger), io = FakeTerminal(["Password:"]), gate = AutomationGate()
        defer { store.continuar(); a.onRetry = nil; a.cancelCommand() }
        var retries = 0
        var next: Task<PasswordAutomation.Event?, Never>?
        a.onRetry = {
            retries += 1
            #expect(!gate.isBusy && ledger.state(of: self.ref) == nil)
            next = Task { await a.observe(io, gate: gate) }
        }
        let first = Task { await a.observe(io, gate: gate) }
        #expect(await esperar { store.lecturas == 1 })
        io.revision += 1
        store.continuar()
        #expect(await first.value == nil)
        let resumed = try #require(next)
        #expect(await resumed.value == .typed(ref))
        #expect(retries == 1 && io.sent == ["secreto-demo\r"])
    }

    @Test func laConfirmacionEnOtraPestanaReobservaSinMasSalida() async throws {
        let store = AlmacenAutopassDemorado(), ledger = CredentialLedger()
        let token = try #require(ledger.reserveProbe(ref).token)
        let a = automation(store, ledger: ledger), io = FakeTerminal(["Password:"]), gate = AutomationGate()
        defer { a.onRetry = nil; a.cancelCommand() }
        var retries = 0
        var next: Task<PasswordAutomation.Event?, Never>?
        a.onRetry = { retries += 1; next = Task { await a.observe(io, gate: gate) } }
        #expect(await a.observe(io, gate: gate) == .manual(.pendingAttempt(ref)))
        // (las comprobaciones de salida que llegan entretanto no repiten el aviso ni leen el secreto)
        #expect(await a.observe(io, gate: gate) == nil)
        #expect(await a.observe(io, gate: gate) == nil)
        ledger.confirm(ref, reservation: token)
        #expect(await esperar { next != nil })
        let resumed = try #require(next)
        #expect(await resumed.value == .typed(ref))
        #expect(retries == 1 && io.sent == ["secreto-demo\r"] && store.lecturas == 1)
    }

    @Test func unFalloEnOtraPestanaMantieneElBloqueoDuranteLaEspera() async throws {
        let store = AlmacenAutopassDemorado(), ledger = CredentialLedger()
        let token = try #require(ledger.reserveProbe(ref).token)
        let a = automation(store, ledger: ledger), io = FakeTerminal(["Password:"]), gate = AutomationGate()
        defer { a.onRetry = nil; a.cancelCommand() }
        var next: Task<PasswordAutomation.Event?, Never>?
        a.onRetry = { next = Task { await a.observe(io, gate: gate) } }
        #expect(await a.observe(io, gate: gate) == .manual(.pendingAttempt(ref)))
        ledger.markFailed(ref, reservation: token)
        #expect(await esperar { next != nil })
        let resumed = try #require(next)
        #expect(await resumed.value == .manual(.recentlyFailed(ref)))
        #expect(io.sent.isEmpty && store.lecturas == 0 && ledger.isBlocked(ref))
    }

    @Test func cancelarElPendienteAntesDeLaConfirmacionNoReintenta() async throws {
        let store = AlmacenAutopassDemorado(), ledger = CredentialLedger()
        let token = try #require(ledger.reserveProbe(ref).token)
        let a = automation(store, ledger: ledger), io = FakeTerminal(["Password:"]), gate = AutomationGate()
        var retries = 0
        a.onRetry = { retries += 1 }
        #expect(await a.observe(io, gate: gate) == .manual(.pendingAttempt(ref)))
        a.cancelCommand()
        ledger.confirm(ref, reservation: token)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(retries == 0 && io.sent.isEmpty && store.lecturas == 0)
    }
}

/// Las esperas siempre tienen tope: un test roto no puede retener un hilo ni el resto de la batería.
private final class AlmacenAutopassDemorado: CredentialStore, @unchecked Sendable {
    private let condition = NSCondition()
    private let demorarConsulta: Bool
    private let demorarLectura: Bool
    private var permitido = false
    private var consultadas = 0
    private var leidas = 0

    init(demorarConsulta: Bool = false, demorarLectura: Bool = false) {
        self.demorarConsulta = demorarConsulta
        self.demorarLectura = demorarLectura
    }

    var consultas: Int { condition.lock(); defer { condition.unlock() }; return consultadas }
    var lecturas: Int { condition.lock(); defer { condition.unlock() }; return leidas }
    func continuar() { condition.lock(); permitido = true; condition.broadcast(); condition.unlock() }

    private func esperarSiHaceFalta(_ demorar: Bool) {
        let limite = Date().addingTimeInterval(2)
        while demorar && !permitido {
            if !condition.wait(until: limite) { break }
        }
    }

    func contains(_ ref: CredentialRef) -> Bool {
        condition.lock(); defer { condition.unlock() }
        consultadas += 1
        esperarSiHaceFalta(demorarConsulta && consultadas == 1)
        return true
    }

    func password(for ref: CredentialRef) throws -> String? {
        condition.lock(); defer { condition.unlock() }
        leidas += 1
        esperarSiHaceFalta(demorarLectura && leidas == 1)
        return "secreto-demo"
    }

    func save(_ password: String, for ref: CredentialRef) throws {}
    func delete(_ ref: CredentialRef) throws {}
    func accounts(in service: CredentialRef.Service) throws -> [String] { [] }
}
