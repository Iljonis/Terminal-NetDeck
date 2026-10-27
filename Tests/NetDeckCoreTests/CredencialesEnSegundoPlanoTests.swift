import Foundation
import Testing
@testable import NetDeckCore

/// El Llavero puede esperar: el resto de tareas async debe seguir avanzando mientras la operación síncrona está parada.
@Suite struct CredencialesEnSegundoPlanoTests {
    enum Operacion: String, CaseIterable, Sendable { case leer, consultar, listar, crear, guardar, borrar }

    /// Con LIBDISPATCH_COOPERATIVE_POOL_STRICT=1, un Task.detached bloqueado impediría continuar esta misma prueba.
    /// El doble vence a los dos segundos para que esa regresión falle sin dejar el runner colgado.
    @Test(arguments: Operacion.allCases) func unaEsperaNoRetieneElEjecutor(_ operation: Operacion) async throws {
        let (events, started) = AsyncStream.makeStream(of: Void.self)
        let store = CredencialesBloqueantes(started: started), ref = CredentialRef.named("AD")
        defer { store.continuar() }
        let task = Task {
            switch operation {
            case .leer:
                #expect(await store.passwordInBackground(for: ref) == "ejemplo")
            case .consultar:
                let candidate = CredentialCandidate(ref: ref, owners: ["tu.usuario"], origin: .defaultCredential)
                #expect(await store.availableInBackground([candidate]) == [candidate])
            case .guardar:
                try await store.saveInBackground("ejemplo", for: ref)
            case .listar:
                #expect(try await store.accountsInBackground().isEmpty)
            case .crear:
                await #expect(throws: KeychainError.self) { try await store.createInBackground("ejemplo", for: ref) }
            case .borrar:
                try await store.deleteInBackground(ref)
            }
        }
        var iterator = events.makeAsyncIterator()
        _ = await iterator.next()
        store.continuar()
        try await task.value
        #expect(!store.expiro, "la tarea que libera la operación debe avanzar antes de que venza la espera")
    }

    @Test func losErroresSeConservanAlCruzarElPuenteAsync() async {
        let store = CredencialesConError(), ref = CredentialRef.named("AD")
        #expect(await store.passwordInBackground(for: ref) == nil)
        await #expect(throws: CredencialesConError.Fallo.simulado) { try await store.saveInBackground("ejemplo", for: ref) }
        await #expect(throws: CredencialesConError.Fallo.simulado) { try await store.deleteInBackground(ref) }
        await #expect(throws: CredencialesConError.Fallo.simulado) { _ = try await store.accountsInBackground() }
    }
}

private final class CredencialesBloqueantes: CredentialStore, @unchecked Sendable {
    private let condition = NSCondition()
    private let started: AsyncStream<Void>.Continuation
    private var permitido = false
    private var agotado = false

    init(started: AsyncStream<Void>.Continuation) { self.started = started }
    var expiro: Bool { condition.lock(); defer { condition.unlock() }; return agotado }
    func continuar() { condition.lock(); permitido = true; condition.broadcast(); condition.unlock() }

    private func esperar() {
        condition.lock()
        defer { condition.unlock() }
        started.yield()
        let deadline = Date().addingTimeInterval(2)
        while !permitido && condition.wait(until: deadline) {}
        agotado = !permitido
    }

    func password(for ref: CredentialRef) throws -> String? { esperar(); return "ejemplo" }
    func contains(_ ref: CredentialRef) -> Bool { esperar(); return true }
    func save(_ password: String, for ref: CredentialRef) throws { esperar() }
    func delete(_ ref: CredentialRef) throws { esperar() }
    func accounts(in service: CredentialRef.Service) throws -> [String] { esperar(); return [] }
}

private struct CredencialesConError: CredentialStore {
    enum Fallo: Error { case simulado }
    func password(for ref: CredentialRef) throws -> String? { throw Fallo.simulado }
    func contains(_ ref: CredentialRef) -> Bool { false }
    func save(_ password: String, for ref: CredentialRef) throws { throw Fallo.simulado }
    func delete(_ ref: CredentialRef) throws { throw Fallo.simulado }
    func accounts(in service: CredentialRef.Service) throws -> [String] { throw Fallo.simulado }
}
