import Foundation
import Testing
@testable import NetDeckCore

/// MultiExec: un Intro que repartiría una orden peligrosa a varias pestañas se confirma antes (`dangerousEnter`).
@MainActor @Suite struct MultiExecPeligrosasTests {
    /// Dos pestañas en su prompt, con MultiExec.
    private func grupo() -> (FakeTerminal, FakeTerminal, MultiExecGroup) {
        let a = FakeTerminal(["core-01#"]), b = FakeTerminal(["core-02#"]), g = MultiExecGroup()
        g.join(a); g.join(b); g.isActive = true
        return (a, b, g)
    }

    /// Teclea `text` en `a` (repartido) y pinta su eco en las dos, como haría el equipo.
    private func teclea(_ text: String, _ a: FakeTerminal, _ b: FakeTerminal, _ g: MultiExecGroup, eco: Bool = true) {
        #expect(g.broadcast(Array(text.utf8), from: a))
        if eco { a.screen[a.screen.count - 1] += text; b.screen[b.screen.count - 1] += text }
    }

    @Test func introConUnaPeligrosaSePregunta() {
        let (a, b, g) = grupo()
        #expect(g.reach(from: a) == 2)
        teclea("reload", a, b, g)
        let d = g.dangerousEnter([13], from: a)
        #expect(d?.command == "reload")
        #expect(d?.tabs == 2)
        // (sin confirmar no se reparte el Intro: la app no llama a broadcast)
        #expect(!a.sent.contains("\r") && !b.sent.contains("\r"))
        // confirmado: el Intro va a las dos
        #expect(g.broadcast([13], from: a))
        #expect(a.sent.last == "\r" && b.sent.last == "\r")
        // (la línea siguiente empieza de cero)
        #expect(g.dangerousEnter([13], from: a) == nil)
    }

    @Test func soloLasPeligrosas() {
        for (orden, peligrosa) in [("show ip bgp summary", false), ("no shutdown", false), ("clear ip bgp *", true),
                                   ("reload cancel", false), ("write erase", true), ("description reload-test", false)] {
            let (a, b, g) = grupo()
            teclea(orden, a, b, g)
            #expect((g.dangerousEnter([13], from: a) != nil) == peligrosa, "«\(orden)»")
        }
    }

    @Test func conElPromptDeConfiguracionYSinEcoTodavia() {
        let (a, b, g) = grupo()
        a.screen = ["core-01(config-if)#"]; b.screen = ["core-02(config-if)#"]
        teclea("shutdown", a, b, g)
        #expect(g.dangerousEnter([13], from: a)?.command == "shutdown")
        // el eco aún no ha llegado al pulsar Intro: cuenta lo tecleado
        let (c, d, h) = grupo()
        teclea("reload", c, d, h, eco: false)
        #expect(h.dangerousEnter([13], from: c)?.command == "reload")
        // con lo tecleado borrado (Ctrl+U) y otra orden, no
        let (e, f, k) = grupo()
        teclea("reload", e, f, k, eco: false)
        #expect(k.broadcast([0x15], from: e))
        teclea("show clock", e, f, k, eco: false)
        #expect(k.dangerousEnter([13], from: e) == nil)
    }

    @Test func sinMultiExecOAUnaSolaNoSePregunta() {
        let (a, b, g) = grupo()
        g.isActive = false
        a.screen = ["core-01#reload"]
        #expect(g.dangerousEnter([13], from: a) == nil)
        #expect(g.reach(from: a) == 1)
        // la otra no está en su prompt: sólo iría a ésta
        g.isActive = true
        a.screen = ["core-01#"]; b.screen = ["--More--"]
        teclea("reload", a, b, g)
        #expect(g.dangerousEnter([13], from: a) == nil)
        // un Intro dentro de un pegado no es la tecla Intro (lo revisa la ventana de pegado)
        let (c, d, h) = grupo()
        teclea("rel", c, d, h)
        #expect(h.dangerousEnter(Array("oad\r".utf8), from: c) == nil)
    }

    @Test func noSeMiraLoQueSeTecleaEnUnaContrasena() {
        let (a, b, g) = grupo()
        a.screen = ["Password:"]
        #expect(!g.broadcast(Array("reload".utf8), from: a))
        #expect(g.dangerousEnter([13], from: a) == nil)
        #expect(b.sent.isEmpty)
    }
}
