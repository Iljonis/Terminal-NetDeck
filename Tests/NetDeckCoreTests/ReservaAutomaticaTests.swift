import Foundation
import Testing
@testable import NetDeckCore

@MainActor @Suite struct ReservaAutomaticaTests {
    @Test func noMezclaOperacionesNiLiberaLaReservaAjena() throws {
        let r = AutomationReservation(), a = UUID(), b = UUID()
        let first = try #require(r.reserve([a]))
        #expect(r.reserve([a, b]) == nil)
        let second = try #require(r.reserve([b]))
        r.release(first)
        #expect(!r.contains(a) && r.contains(b))
        let third = try #require(r.reserve([a]))
        r.release(first)
        #expect(r.contains(a) && r.contains(b))
        r.release(second); r.release(third)
        #expect(!r.contains(a) && !r.contains(b))
    }
    @Test func reconectarCortaLaSecuenciaAnterior() throws {
        let gate = AutomationGate(), first = gate.begin()
        gate.abortAll()
        let next = gate.begin()
        #expect(first.isTripped && !next.isTripped)
        #expect(throws: AbortedByUser.self) { try first.check() }
        gate.end(next)
    }
}
