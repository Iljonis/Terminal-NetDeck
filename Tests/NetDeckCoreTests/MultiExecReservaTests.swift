import Foundation
import Testing
@testable import NetDeckCore

@MainActor @Suite struct MultiExecReservaTests {
    @Test func tecladoDesdeOtraPestanaNoEntraEnLaMacro() {
        let a = FakeTerminal(["core-01#"]), b = FakeTerminal(["core-02#"]), g = MultiExecGroup()
        g.join(a); g.join(b); g.isActive = true
        var reserved = Set<ObjectIdentifier>([ObjectIdentifier(a)])
        g.canReceiveKeystrokes = { !reserved.contains(ObjectIdentifier($0)) }
        #expect(g.broadcast(Array("show clock".utf8), from: b))
        #expect(a.sent.isEmpty)
        #expect(!b.sent.isEmpty)
        // (soltar una reserva no añade el destino a una línea que ya estaba empezada)
        reserved.removeAll()
        #expect(g.broadcast([13], from: b))
        #expect(a.sent.isEmpty)
    }
    @Test func reservaQueEmpiezaAMitadDeLineaCortaElReparto() {
        let a = FakeTerminal(["core-01#"]), b = FakeTerminal(["core-02#"]), g = MultiExecGroup()
        g.join(a); g.join(b); g.isActive = true
        var reserved = Set<ObjectIdentifier>()
        g.canReceiveKeystrokes = { !reserved.contains(ObjectIdentifier($0)) }
        #expect(g.broadcast(Array("show".utf8), from: b))
        let before = a.sent
        reserved.insert(ObjectIdentifier(a))
        #expect(g.broadcast(Array(" users\r".utf8), from: b))
        #expect(a.sent == before)
        #expect(g.broadcast(Array("no se envia".utf8), from: a))
        #expect(a.sent == before)
    }

    @Test func liberarReservaNoReincorporaUnDestinoAlSufijo() {
        let a = FakeTerminal(["core-01#"]), b = FakeTerminal(["core-02#"]), g = MultiExecGroup()
        g.join(a); g.join(b); g.isActive = true
        var reserved = false
        g.canReceiveKeystrokes = { io in io !== a || !reserved }
        #expect(g.broadcast(Array("show".utf8), from: b))
        let prefix = a.sent
        reserved = true
        #expect(g.broadcast(Array(" version".utf8), from: b))
        reserved = false
        #expect(g.broadcast(Array(" brief\r".utf8), from: b))
        #expect(a.sent == prefix)
        a.screen = ["core-01#"]; b.screen = ["core-02#"]
        #expect(g.broadcast(Array("show clock\r".utf8), from: b))
        #expect(a.sent != prefix)
    }
}
