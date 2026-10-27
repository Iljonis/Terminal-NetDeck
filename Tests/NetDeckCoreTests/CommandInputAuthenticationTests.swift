import Foundation
import Testing
@testable import NetDeckCore

/// El recorrido de entrada usado por TerminalSession: sólo el teclado enviado produce órdenes, nunca la salida.
@Suite @MainActor struct EntradaAutenticacionTests {
    @Test func configuracionesYBannersNoSeConviertenEnOrdenes() async {
        let recorder = MacroRecorder(allowScreenFallback: true, soloConexiones: true), io = FakeTerminal(["core-01#"])
        let store = MemoryCredentialStore(), ref = CredentialRef.named("AD")
        try? store.save("ejemplo", for: ref)
        let a = PasswordAutomation(mode: .autoType, store: store, ledger: CredentialLedger())
        var lookups = 0
        a.candidates = { _ in lookups += 1; return [.init(ref: ref, owners: ["tu.usuario"], origin: .defaultCredential)] }
        for command in ["show config", "show running-config", "show run", "display current-configuration", "echo ssh tu.usuario@core-02"] {
            io.screen += ["core-01#"]
            recorder.feed(Array((command + "\r").utf8), from: io)
            for sent in recorder.takeLines() { a.beginCommand(sent, after: io.cursorRow) }
            for output in ["ssh tu.usuario@core-02", "telnet core-02", "Username: tu.usuario", "Password:",
                           "(tu.usuario@core-02) Enter password:", "banner login ^", "PASSCODE:"] {
                io.screen += [output]
                #expect(await a.observe(io, gate: AutomationGate()) == nil)
            }
        }
        #expect(lookups == 0 && io.sent.isEmpty)
    }

    @Test func laOrdenEnviadaSiArmaElLoginPeroNoGrabaLaRespuestaSecreta() async {
        let recorder = MacroRecorder(allowScreenFallback: true, soloConexiones: true), io = FakeTerminal(["bastion#"])
        let ref = CredentialRef.named("AD"), store = MemoryCredentialStore()
        try? store.save("ejemplo", for: ref)
        let a = PasswordAutomation(mode: .suggest, store: store, ledger: CredentialLedger()) { _ in
            [.init(ref: ref, owners: ["tu.usuario"], origin: .defaultCredential)]
        }
        recorder.feed(Array("ssh tu.usuario@core-01\r".utf8), from: io)
        for command in recorder.takeLines() { a.beginCommand(command, after: io.cursorRow) }
        io.screen += ["Password:"]
        #expect(await a.observe(io, gate: AutomationGate()) == .suggested(ref))
        recorder.feed(Array("no-se-guarda\r".utf8), from: io)
        #expect(recorder.takeLines().isEmpty)
        a.cancelCommand()
        io.screen += ["core-01#"]
        recorder.feed(Array("show version\r".utf8), from: io)
        #expect(recorder.takeLines() == ["show version"])
    }

    @Test func consumirLasLineasNoQuitaLaProteccionDePegadosSeguidos() {
        let recorder = MacroRecorder(allowScreenFallback: true, soloConexiones: true), io = FakeTerminal(["bastion#"])
        recorder.feed(Array("ssh tu.usuario@core-01\r".utf8), from: io)
        #expect(recorder.takeLines() == ["ssh tu.usuario@core-01"])
        // (el equipo aún no ha contestado: lo siguiente puede ser una contraseña de un pegado multilínea)
        recorder.feed(Array("ssh secreto@core-02\r".utf8), from: io)
        #expect(recorder.takeLines().isEmpty)
    }

    @Test func editarOtraOrdenNoLaConvierteEnUnSshDelRemoto() async {
        for edit in ["show \t", "show \u{1b}[D", "\u{1b}[A\u{15}show \t"] {
            let recorder = MacroRecorder(allowScreenFallback: true, soloConexiones: true), io = FakeTerminal(["core-01#"])
            let a = PasswordAutomation(store: MemoryCredentialStore(), ledger: CredentialLedger())
            var lookups = 0
            a.candidates = { _ in lookups += 1; return [] }
            recorder.feed(Array(edit.utf8), from: io)
            io.screen[0] = "core-01#ssh tu.usuario@192.0.2.11"
            recorder.feed([13], from: io)
            let commands = recorder.takeLines()
            for command in commands { a.beginCommand(command, after: io.cursorRow) }
            #expect(commands.isEmpty && recorder.skipped == 1)
            io.screen += ["Password:"]
            #expect(await a.observe(io, gate: AutomationGate()) == nil)
            #expect(lookups == 0 && io.sent.isEmpty)
        }
    }

    @Test(arguments: ["\u{1b}[A", "\u{1b}OA", "\u{10}", "ssh tu.usuario@co\t", "\u{12}core"])
    func historialYTabPermitenRepetirElLogin(_ keys: String) async {
        let recorder = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
        let io = FakeTerminal(["bastion#"]), ref = CredentialRef.named("AD"), ledger = CredentialLedger()
        let a = PasswordAutomation(mode: .autoType, store: MemoryCredentialStore([ref: "ejemplo"]), ledger: ledger) { _ in
            [.init(ref: ref, owners: ["tu.usuario"], origin: .defaultCredential)]
        }
        a.settle = .milliseconds(1)
        let command = "ssh tu.usuario@core-01"
        // (el mismo equipo, después de salir: el segundo login también se arma y se confirma)
        for _ in 0..<2 {
            io.screen += ["bastion#"]
            recorder.feed(Array(keys.utf8), from: io)
            io.screen[io.screen.count - 1] = keys.hasPrefix("\u{12}")
                ? "(reverse-i-search)`core': \(command)" : "bastion#\(command)"
            recorder.feed([13], from: io)
            let commands = recorder.takeLines()
            #expect(commands == [command])
            for sent in commands { a.beginCommand(sent, after: io.cursorRow) }
            io.screen += ["tu.usuario@core-01's password:"]
            #expect(await a.observe(io, gate: AutomationGate()) == .typed(ref))
            io.screen += ["core-01#"]
            #expect(await a.observe(io, gate: AutomationGate()) == .confirmed(ref))
        }
        #expect(io.sent == ["ejemplo\r", "ejemplo\r"])
    }

    @Test func elHistorialExigeEdicionPropiaYElMismoPrompt() {
        for changedPrompt in [false, true] {
            let recorder = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
            let io = FakeTerminal(["bastion#"])
            if changedPrompt { recorder.feed(Array("\u{1b}[A".utf8), from: io) }
            io.screen[0] = "otro#ssh tu.usuario@core-01"
            recorder.feed([13], from: io)
            #expect(recorder.takeLines().isEmpty)
        }
        let recorder = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
        let io = FakeTerminal(["Password:"])
        recorder.feed(Array("\u{1b}[A".utf8), from: io)
        io.screen[0] = "Password:ssh tu.usuario@core-01"
        recorder.feed([13], from: io)
        #expect(recorder.takeLines().isEmpty)
    }
}
