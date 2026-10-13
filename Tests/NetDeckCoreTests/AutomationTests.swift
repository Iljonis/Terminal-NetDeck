import Foundation
import Testing
@testable import NetDeckCore

@Suite @MainActor struct EscTests {
    @Test func teclasQueCortan() {
        #expect(AbortKey.isAbort([0x1B]))
        #expect(!AbortKey.isAbort([0x1B, 0x5B, 0x41]))          // flecha arriba: no
        #expect(AbortKey.isAbort([0x03]))
    }

    @Test func escSeComeSoloSiHayAlgoEnMarcha() {
        let gate = AutomationGate()
        #expect(!gate.intercept([0x1B]))                         // nada en marcha: Esc llega al equipo (vi…)
        let sw = gate.begin()
        #expect(gate.intercept([0x1B]))
        #expect(sw.isTripped)
        let sw2 = gate.begin()
        #expect(!gate.intercept([0x03]))                         // Ctrl+C corta y además llega al equipo
        #expect(sw2.isTripped)
    }

    @Test func escAntesDeLaContraseñaNoEnviaNada() async {
        let io = FakeTerminal(["login: "])
        let store = MemoryCredentialStore([.named("AD"): "secreto"])
        let sw = AbortSwitch()
        let script = InputScript([.line("tu.usuario"), .waitFor(PasswordPrompt.asks, timeout: .seconds(2)), .secret(.named("AD"))])
        io.respond = { _ in sw.trip(); return ["Password:"] }      // Esc justo cuando piden la contraseña
        #expect(await script.run(on: io, store: store, abort: sw) == .aborted)
        #expect(io.sent == ["tu.usuario\r"])
    }
}

@Suite @MainActor struct PasswordAutomationTests {
    func make(_ io: FakeTerminal, _ store: MemoryCredentialStore, _ ledger: CredentialLedger,
              default d: DefaultCredential? = nil) -> PasswordAutomation {
        let a = PasswordAutomation(mode: .autoType, store: store, ledger: ledger) { req in
            SessionManager().credentialCandidates(for: req, route: nil, defaultCredential: d)
        }
        a.settle = .milliseconds(1)
        return a
    }

    @Test func laPorDefectoNuncaAOtroUsuario() async {
        let io = FakeTerminal(["$ ssh root@192.0.2.1", "root@192.0.2.1's password:"])
        let a = make(io, MemoryCredentialStore([.named("AD"): "x"]), CredentialLedger(),
                     default: .init(name: "AD", user: "tu.usuario"))
        #expect(await a.observe(io, gate: AutomationGate()) == .manual(.userMismatch(requested: "root")))
        #expect(io.sent.isEmpty)
    }

    @Test func promptFalsoTrasLaOrdenNoRecibeNada() async {
        let io = FakeTerminal(["$ ssh root@192.0.2.1", "(tu.usuario@192.0.2.1) Password:"])
        let a = make(io, MemoryCredentialStore([.named("AD"): "x"]), CredentialLedger(),
                     default: .init(name: "AD", user: "tu.usuario"))
        a.commandUser = "root"
        #expect(await a.observe(io, gate: AutomationGate()) == .manual(.conflictingUsers(command: "root", prompt: "tu.usuario")))
        a.commandJumpUsers = ["tu.usuario"]
        io.screen += ["(tu.usuario@bastion) Password:"]
        #expect(await a.observe(io, gate: AutomationGate()) == .typed(.named("AD")))
    }

    /// «Escribir sin esperar a que la pida»: sin prompt reconocido, Intro sólo si se pide; bloqueada sólo con `force`.
    @Test func escribirSinQueLaPidan() {
        let io = FakeTerminal(["Clave de acceso >"])
        let ledger = CredentialLedger()
        let a = make(io, MemoryCredentialStore([.named("AD"): "pw"]), ledger)
        #expect(a.typeManually(.named("AD"), into: io) == .notAsked)
        #expect(a.typeAnyway(.named("AD"), into: io, pressReturn: false) == .typed)
        #expect(a.typeAnyway(.named("AD"), into: io, pressReturn: true) == .typed)
        #expect(io.sent == ["pw", "pw\r"])
        ledger.markFailed(.named("AD"))
        #expect(a.typeAnyway(.named("AD"), into: io, pressReturn: true) == .blocked)
        #expect(a.typeAnyway(.named("AD"), into: io, pressReturn: false, force: true) == .typed)
        #expect(ledger.isBlocked(.named("AD")))                              // (no la desbloquea)
        #expect(a.typeAnyway(.named("otra"), into: io, pressReturn: false) == .missing)
    }

    @Test func passwordASecasSinUsuarioNoSeEscribe() async {
        let io = FakeTerminal(["$ telnet 192.0.2.9", "Password:"])
        let a = make(io, MemoryCredentialStore([.named("AD"): "x"]), CredentialLedger(),
                     default: .init(name: "AD", user: "tu.usuario"))
        #expect(await a.observe(io, gate: AutomationGate()) == .manual(.unknownUser))
        #expect(io.sent.isEmpty)
    }

    @Test func escribeLaSuyaYSiFallaLaBloquea() async {
        let io = FakeTerminal(["admin@192.0.2.1's password:"]) { _ in ["Permission denied, please try again.", "admin@192.0.2.1's password:"] }
        let ledger = CredentialLedger()
        let a = make(io, MemoryCredentialStore([.device("admin", "192.0.2.1"): "pw"]), ledger)
        let gate = AutomationGate()
        #expect(await a.observe(io, gate: gate) == .typed(.device("admin", "192.0.2.1")))
        #expect(io.sent == ["pw\r"])
        #expect(await a.observe(io, gate: gate) == .failed(.device("admin", "192.0.2.1")))
        #expect(await a.observe(io, gate: gate) == nil)                        // la misma petición: nada más
        #expect(ledger.isBlocked(.device("admin", "192.0.2.1")))
        #expect(io.sent.count == 1)
    }

    /// La de la sesión (su login) va aparte de la de los equipos.
    @Test func sesionAutomaticaEquiposSugeridos() async {
        let io = FakeTerminal(["Username: tu.usuario", "Password:"]) { _ in ["core-01#"] }
        let a = make(io, MemoryCredentialStore([.named("AD"): "pw"]), CredentialLedger(),
                     default: .init(name: "AD", user: "tu.usuario"))
        a.mode = .suggest
        a.sessionMode = .autoType
        #expect(await a.observe(io, gate: AutomationGate()) == .typed(.named("AD")))   // login de la sesión: sola
        #expect(await a.observe(io, gate: AutomationGate()) == .confirmed(.named("AD")))
        #expect(a.loggedIn)
        io.screen += ["core-01#telnet 192.0.2.9", "Username: tu.usuario", "Password:"]
        #expect(await a.observe(io, gate: AutomationGate()) == .suggested(.named("AD"))) // equipo: sugerida
    }

    @Test func escDuranteLaEsperaCancela() async {
        let io = FakeTerminal(["admin@192.0.2.1's password:"])
        let a = make(io, MemoryCredentialStore([.device("admin", "192.0.2.1"): "pw"]), CredentialLedger())
        a.settle = .milliseconds(300)
        let gate = AutomationGate()
        let t = Task { await a.observe(io, gate: gate) }
        while !gate.isBusy { await Task.yield() }
        #expect(gate.intercept([0x1B]))
        #expect(await t.value == .cancelled)
        #expect(io.sent.isEmpty)
    }
}

@Suite @MainActor struct SafePasteTests {
    func device(_ errorOn: String? = nil, pager: String? = nil) -> FakeTerminal {
        FakeTerminal(["core-01(config)#"]) { cmd in
            if cmd == errorOn { return ["         ^", "% Invalid input detected at '^' marker.", "core-01(config)#"] }
            if cmd == pager { return ["line 1", " --More-- "] }
            return ["core-01(config\(cmd.hasPrefix("interface") ? "-if" : ""))#"]
        }
    }

    var paster: SafePaster {
        var p = SafePaster()
        p.poll = .milliseconds(5)
        p.quiet = .milliseconds(20)
        p.lineTimeout = .seconds(2)
        return p
    }

    @Test func todasEsperandoAlPrompt() async {
        let io = device()
        let r = await paster.paste("interface xe-0/0/1\r\n description prueba\n\n exit\n", into: io, abort: AbortSwitch())
        #expect(r == PasteReport(sent: 3, total: 3, outcome: .completed))
        #expect(io.sent == ["interface xe-0/0/1\r", " description prueba\r", " exit\r"])
    }

    @Test func seParaEnElError() async {
        let io = device("descripcion mal")
        let r = await paster.paste("interface xe-0/0/1\ndescripcion mal\nexit", into: io, abort: AbortSwitch())
        #expect(r.outcome == .deviceError(line: 2, output: "% Invalid input detected at '^' marker."))
        #expect(io.sent.count == 2)
    }

    @Test func seParaSiPagina() async {
        let io = device(pager: "show run")
        let r = await paster.paste("show run\nexit", into: io, abort: AbortSwitch())
        #expect(r.outcome == .pager(line: 1))
    }

    @Test func peligrosasSinConfirmarNoSalen() async {
        let io = device()
        let r = await paster.paste("interface xe-0/0/1\nshutdown", into: io, abort: AbortSwitch())
        #expect(r.outcome == .dangerousNotConfirmed(line: 2, command: "shutdown"))
        #expect(io.sent.count == 1)
    }

    @Test func seParaSiPidenContraseña() async {
        let io = FakeTerminal(["core-01>"]) { cmd in cmd == "enable" ? ["Password:"] : ["core-01#"] }
        let r = await paster.paste("enable\nconfigure terminal\nhostname x", into: io, abort: AbortSwitch())
        #expect(r.outcome == .passwordPrompt(line: 1))
        #expect(io.sent == ["enable\r"])                  // «configure terminal» NO va como contraseña
    }

    @Test func noPegaEnUnaPeticiónDeContraseña() async {
        let io = FakeTerminal(["(tu.usuario@192.0.2.1) Password:"])
        let r = await paster.paste("show version", into: io, abort: AbortSwitch())
        #expect(r.outcome == .passwordPrompt(line: 0))
        #expect(io.sent.isEmpty)
    }

    @Test func escParaElPegado() async {
        let io = device()
        let sw = AbortSwitch()
        io.respond = { _ in sw.trip(); return ["core-01(config)#"] }
        let r = await paster.paste("a\nb\nc", into: io, abort: sw)
        #expect(r.outcome == .aborted)
        #expect(io.sent == ["a\r"])
    }

    @Test func multiExecPegaEnTodos() async {
        let (a, b) = (device(), device())
        let g = MultiExecGroup()
        g.join(a)
        g.join(b)
        let r = await g.paste("hostname x\n", paster: paster, abort: AbortSwitch())
        #expect(r.map(\.outcome) == [.completed, .completed])
        #expect(a.sent == b.sent)
    }

    @Test func promptDeEquipo() {
        let p = DevicePrompt(sample: "core-01#")
        #expect(p.base == "core-01")
        #expect(p.matches("core-01(config-if)#"))
        #expect(!p.matches("core-02#"))
        #expect(DevicePrompt(sample: "<core-01>").matches("[~core-01-GigabitEthernet0/0/1]"))
        #expect(DevicePrompt(sample: "admin@core-01> ").matches("admin@core-01#"))
        #expect(DevicePrompt(sample: "[tu.usuario@bastion ~]$").matches("[tu.usuario@bastion tmp]$"))
    }
}

@Suite @MainActor struct JumpBatchTests {
    /// Dos equipos por el salto con la misma contraseña AD: falla en el primero → el segundo NO la escribe.
    @Test func unFalloNoSeRepiteEnLosDemas() async {
        let store = MemoryCredentialStore([.named("AD"): "mala"])
        let ledger = CredentialLedger()
        var tabs: [FakeTerminal] = []
        let list = JumpList(name: "prueba", jump: "bastion", user: "tu.usuario",
                            devices: JumpList.devices(in: "192.0.2.5, 192.0.2.6 # comentario"),
                            credential: .init(ref: .named("AD"), owners: ["tu.usuario"], origin: .sessionNamed))
        var s = JumpBatchRunner.Settings()
        s.spacing = .milliseconds(10)
        s.poll = .milliseconds(5)
        s.jumpTimeout = .seconds(2)
        s.deviceTimeout = .seconds(2)
        s.passwordTimeout = .seconds(2)
        let runner = JumpBatchRunner(list: list, settings: s, store: store, ledger: ledger, abort: AbortSwitch()) { d in
            let io = FakeTerminal(["tu.usuario@bastion:~$ "]) { cmd in
                cmd.hasPrefix("ssh ") ? ["tu.usuario@\(d.host)'s password:"]
                                      : ["Permission denied, please try again.", "tu.usuario@\(d.host)'s password:"]
            }
            tabs.append(io)
            return io
        }
        await runner.run()
        let passwordsTyped = tabs.flatMap(\.sent).filter { $0 == "mala\r" }.count
        #expect(passwordsTyped == 1)
        #expect(ledger.isBlocked(.named("AD")))
        #expect(runner.status.values.contains { if case .denied = $0 { true } else { false } })
        #expect(runner.status.values.contains { if case .skipped = $0 { true } else { false } })
        #expect(tabs.first?.sent.first == "ssh tu.usuario@192.0.2.5\r")
    }

    @Test func nombresPeligrososNoSeEscribenEnElSalto() async {
        let list = JumpList(name: "x", jump: "bastion", devices: [Endpoint(host: "192.0.2.5$(id)")])
        let io = FakeTerminal(["tu.usuario@bastion:~$ "])
        let runner = JumpBatchRunner(list: list, store: MemoryCredentialStore(), ledger: CredentialLedger(),
                                     abort: AbortSwitch()) { _ in io }
        await runner.run()
        #expect(io.sent.isEmpty)
    }
}
