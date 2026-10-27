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
        let a = PasswordAutomation(mode: .autoType, store: store, ledger: ledger)
        a.candidates = { [weak a] req in
            guard let a else { return [] }
            let manager = SessionManager()
            var request = req
            if let account = request.account, let at = account.lastIndex(of: "@"),
               !manager.expectedHosts(route: nil, typed: a.commandHosts).contains(String(account[account.index(after: at)...]).lowercased()) {
                return []
            }
            if request.account == nil, let user = request.user ?? a.commandUser, let target = a.commandTarget {
                request.account = "\(user)@\(target.host)"          // (sólo para buscar; la política recibe el prompt original)
            }
            return manager.credentialCandidates(for: request, route: nil, defaultCredential: d, typedHosts: a.commandHosts)
        }
        a.settle = .milliseconds(1)
        return a
    }

    @Test func laPorDefectoNuncaAOtroUsuario() async {
        let io = FakeTerminal(["$ ssh root@192.0.2.1", "root@192.0.2.1's password:"])
        let a = make(io, MemoryCredentialStore([.named("AD"): "x"]), CredentialLedger(),
                     default: .init(name: "AD", user: "tu.usuario"))
        a.beginCommand("ssh root@192.0.2.1")
        #expect(await a.observe(io, gate: AutomationGate()) == .manual(.userMismatch(requested: "root")))
        #expect(io.sent.isEmpty)
    }

    @Test func promptFalsoTrasLaOrdenNoRecibeNada() async {
        let io = FakeTerminal(["$ ssh root@192.0.2.1", "(tu.usuario@192.0.2.1) Password:"])
        let a = make(io, MemoryCredentialStore([.named("AD"): "x"]), CredentialLedger(),
                     default: .init(name: "AD", user: "tu.usuario"))
        a.beginCommand("ssh root@192.0.2.1")
        #expect(await a.observe(io, gate: AutomationGate()) == .manual(.conflictingUsers(command: "root", prompt: "tu.usuario")))
        a.beginCommand("ssh -J tu.usuario@bastion root@192.0.2.1")
        io.screen += ["(tu.usuario@bastion) Password:"]
        #expect(await a.observe(io, gate: AutomationGate()) == .typed(.named("AD")))
    }

    /// Las peticiones de siempre (con espacios al final) y la del askpass al abrir la sesión: un botón o el menú 🔑
    /// pueden escribir ahí; sus avisos y el «¿Guardarla?» no son peticiones.
    @Test func peticionesQueAceptanUnaManual() {
        for l in ["tu.usuario@192.0.2.11's password: ", "Password for tu.usuario:", "(tu.usuario@core-01) Password:",
                  "Enter password:", "Password:   ", "Contraseña:"] {
            #expect(PasswordPrompt.asksForPassword(l), "\(l)")
            #expect(PasswordPrompt.acceptsManual(l), "\(l)")
        }
        let askpass = "[NetDeck] tu.usuario@core-01's password: "
        #expect(!PasswordPrompt.asksForPassword(askpass))                  // (la automática no escribe ahí)
        #expect(PasswordPrompt.acceptsManual(askpass))
        #expect(PasswordPrompt.askpassRequest(askpass)?.account == "tu.usuario@core-01")
        #expect(SecretPrompt.asks(askpass))                                // (ni órdenes de botones ni MultiExec)
        for l in ["[NetDeck] Esc = cancelar", "[NetDeck] ¿Guardarla como «AD»? [S/n] (Esc = no)", "core-01#show run | i password:"] {
            #expect(!PasswordPrompt.acceptsManual(l), "\(l)")
        }
    }

    /// El botón de contraseña en la pregunta del askpass: la escribe; si vuelve a preguntar, no valía (sin bloquearla:
    /// la eliges tú).
    @Test func botonDeContraseñaEnElAskpass() async {
        let io = FakeTerminal(["[NetDeck] Esc = cancelar", "[NetDeck] tu.usuario@core-01's password: "]) { _ in
            ["[NetDeck] tu.usuario@core-01's password: "]
        }
        let ledger = CredentialLedger()
        let a = make(io, MemoryCredentialStore([.named("AD"): "pw"]), ledger)
        #expect(await a.typeManually(.named("AD"), into: io) == .typed)
        #expect(io.sent == ["pw\r"])
        #expect(io.screen[1] == "[NetDeck] tu.usuario@core-01's password: ")  // (sin eco)
        #expect(await a.observe(io, gate: AutomationGate()) == .rejected(.named("AD")))
        #expect(!ledger.isBlocked(.named("AD")))
    }

    /// Con -J, tras la del salto el askpass pregunta por el destino: la del salto ha entrado, no se bloquea.
    @Test func botonEnElAskpassDelSalto() async {
        let io = FakeTerminal(["[NetDeck] tu.usuario@bastion's password:"]) { _ in ["[NetDeck] tu.usuario@192.0.2.11's password:"] }
        let ledger = CredentialLedger()
        let a = make(io, MemoryCredentialStore([.named("AD"): "pw"]), ledger)
        #expect(await a.typeManually(.named("AD"), into: io) == .typed)
        #expect(await a.observe(io, gate: AutomationGate()) == nil)
        #expect(!ledger.isBlocked(.named("AD")))
        #expect(await a.typeManually(.named("AD"), into: io) == .typed)        // (y la del destino, otra vez a mano)
    }

    /// Botón «login» con la contraseña ya pedida: nunca la de otro usuario; la suya, con seguimiento y sin bloqueo (la
    /// eliges tú: otro clic la vuelve a escribir).
    @Test func loginConLaContraseñaYaPedida() async {
        let askpass = "[NetDeck] tu.usuario@core-01's password: "
        #expect(PasswordPrompt.otherUser(than: "admin", cursorLine: askpass, above: []) == "tu.usuario")
        #expect(PasswordPrompt.otherUser(than: "TU.USUARIO", cursorLine: askpass, above: []) == nil)
        #expect(PasswordPrompt.otherUser(than: "admin", cursorLine: "Password:", above: ["Username: tu.usuario"]) == "tu.usuario")
        #expect(PasswordPrompt.otherUser(than: "admin", cursorLine: "Password:", above: []) == nil)   // (no lo dice)
        let ledger = CredentialLedger()
        let io = FakeTerminal(["Username: tu.usuario", "Password:"]) { _ in ["Password:"] }
        let a = make(io, MemoryCredentialStore([.named("AD"): "pw"]), ledger)
        #expect(await a.typeManually(.named("AD"), into: io) == .typed)
        #expect(await a.observe(io, gate: AutomationGate()) == .rejected(.named("AD")))
        #expect(!ledger.isBlocked(.named("AD")))
        #expect(await a.typeManually(.named("AD"), into: io) == .typed)
        #expect(io.sent == ["pw\r", "pw\r"])
    }

    /// Con el historial lleno la fila del cursor no crece: la nueva pregunta del askpass se ve por la revisión.
    @Test func askpassRepiteConElHistorialLleno() async {
        let prompt = "[NetDeck] tu.usuario@core-01's password:"
        let io = FakeTerminal(["", prompt])
        io.respond = { [unowned io] _ in io.screen.removeFirst(); return [""] }   // (la fila de arriba sale del historial)
        let ledger = CredentialLedger()
        let a = make(io, MemoryCredentialStore([.named("AD"): "pw"]), ledger)
        #expect(await a.typeManually(.named("AD"), into: io) == .typed)
        #expect(io.cursorRow == 1)
        #expect(await a.observe(io, gate: AutomationGate()) == nil)             // (el salto de línea tras leerla)
        io.screen = ["", prompt]                                                // (misma fila: vuelve a preguntar)
        io.revision += 1
        #expect(await a.observe(io, gate: AutomationGate()) == .rejected(.named("AD")))
        #expect(!ledger.isBlocked(.named("AD")))
    }

    /// «Escribir sin esperar a que la pida»: sin prompt reconocido, Intro sólo si se pide; también la por defecto
    /// bloqueada (la eliges tú), sin desbloquearla.
    @Test func escribirSinQueLaPidan() async {
        let io = FakeTerminal(["Clave de acceso >"])
        let ledger = CredentialLedger()
        let a = make(io, MemoryCredentialStore([.named("AD"): "pw"]), ledger)
        #expect(await a.typeManually(.named("AD"), into: io) == .notAsked)
        #expect(await a.typeAnyway(.named("AD"), into: io, pressReturn: false) == .typed)
        #expect(await a.typeAnyway(.named("AD"), into: io, pressReturn: true) == .typed)
        #expect(io.sent == ["pw", "pw\r"])
        ledger.markFailed(.named("AD"))
        #expect(await a.typeAnyway(.named("AD"), into: io, pressReturn: true) == .typed)
        #expect(ledger.isBlocked(.named("AD")))                              // (no la desbloquea)
        #expect(await a.typeAnyway(.named("otra"), into: io, pressReturn: false) == .missing)
    }

    @Test func passwordASecasSinUsuarioNoSeEscribe() async {
        let io = FakeTerminal(["$ telnet 192.0.2.9", "Password:"])
        let a = make(io, MemoryCredentialStore([.named("AD"): "x"]), CredentialLedger(),
                     default: .init(name: "AD", user: "tu.usuario"))
        a.beginCommand("telnet 192.0.2.9")
        #expect(await a.observe(io, gate: AutomationGate()) == .manual(.unknownUser))
        #expect(io.sent.isEmpty)
    }

    /// La de usuario@equipo escrita sola: si no vale, no se repite en esa orden, pero no se bloquea (no es la por defecto).
    @Test func escribeLaSuyaYSiFallaNoLaRepite() async {
        let io = FakeTerminal(["admin@192.0.2.1's password:"]) { _ in ["Permission denied, please try again.", "admin@192.0.2.1's password:"] }
        let ledger = CredentialLedger()
        let a = make(io, MemoryCredentialStore([.device("admin", "192.0.2.1"): "pw"]), ledger)
        a.beginCommand("ssh admin@192.0.2.1")
        let gate = AutomationGate()
        #expect(await a.observe(io, gate: gate) == .typed(.device("admin", "192.0.2.1")))
        #expect(io.sent == ["pw\r"])
        #expect(await a.observe(io, gate: gate) == .rejected(.device("admin", "192.0.2.1")))
        #expect(await a.observe(io, gate: gate) == nil)                        // la misma petición: nada más
        #expect(!ledger.isBlocked(.device("admin", "192.0.2.1")))
        #expect(ledger.state(of: .device("admin", "192.0.2.1")) == nil)       // (sin reserva colgada)
        #expect(io.sent.count == 1)
    }

    /// La por defecto escrita sola tras «ssh …» en una sesión: si no vale, bloqueada 15 min (la única que se bloquea);
    /// la siguiente orden ya no la escribe sola, pero un botón o el menú 🔑 sí.
    @Test func laPorDefectoSiFallaSeBloquea() async {
        let io = FakeTerminal(["tu.usuario@192.0.2.1's password:"]) { _ in ["Permission denied, please try again.", "tu.usuario@192.0.2.1's password:"] }
        let ledger = CredentialLedger(), gate = AutomationGate()
        let a = make(io, MemoryCredentialStore([.named("AD"): "pw"]), ledger, default: .init(name: "AD", user: "tu.usuario"))
        a.beginCommand("ssh tu.usuario@192.0.2.1")
        #expect(await a.observe(io, gate: gate) == .typed(.named("AD")))
        #expect(await a.observe(io, gate: gate) == .failed(.named("AD")))
        #expect(ledger.isBlocked(.named("AD")))
        a.beginCommand("ssh tu.usuario@192.0.2.1")
        io.screen += ["tu.usuario@192.0.2.1's password:"]
        #expect(await a.observe(io, gate: gate) == .manual(.recentlyFailed(.named("AD"))))
        #expect(io.sent == ["pw\r"])
        #expect(await a.typeManually(.named("AD"), into: io) == .typed)        // (la eliges tú: se escribe)
        #expect(io.sent == ["pw\r", "pw\r"])
    }

    /// «ssh -J tu.usuario@bastion admin@core-01» tecleado con contraseña en los dos: tras la del salto, ssh pide la del
    /// destino. Antes se tomaba por una repregunta y la del salto, que valía, quedaba bloqueada 15 min.
    @Test func laDelDestinoTrasLaDelSaltoNoEsUnRechazo() async {
        let jump = CredentialRef.device("tu.usuario", "bastion"), dest = CredentialRef.device("admin", "core-01")
        let io = FakeTerminal(["tu.usuario@bastion's password:"]) { $0 == "del-salto" ? ["admin@core-01's password:"] : ["core-01#"] }
        let ledger = CredentialLedger(), gate = AutomationGate()
        let a = make(io, MemoryCredentialStore([jump: "del-salto", dest: "del-destino"]), ledger)
        a.beginCommand("ssh -J tu.usuario@bastion admin@core-01")
        #expect(await a.observe(io, gate: gate) == .typed(jump))
        #expect(await a.observe(io, gate: gate) == .typed(dest))          // (otra petición, en la misma orden)
        #expect(!ledger.isBlocked(jump))
        if case .confirmed = ledger.state(of: jump) {} else { Issue.record("la del salto no se confirmó con su reserva") }
        #expect(await a.observe(io, gate: gate) == .confirmed(dest))
        #expect(io.sent == ["del-salto\r", "del-destino\r"])
        // (la misma cuenta otra vez sí es un rechazo de la del salto)
        let again = FakeTerminal(["tu.usuario@bastion's password:"]) { _ in ["tu.usuario@bastion's password:"] }
        let other = CredentialLedger(), b = make(again, MemoryCredentialStore([jump: "del-salto"]), other)
        b.beginCommand("ssh -J tu.usuario@bastion admin@core-01")
        #expect(await b.observe(again, gate: gate) == .typed(jump))
        #expect(await b.observe(again, gate: gate) == .rejected(jump))       // (no es la por defecto: sin bloqueo)
        #expect(!other.isBlocked(jump) && again.sent == ["del-salto\r"])
    }

    /// El login de la sesión nunca arma la detección; la orden enviada hacia otro equipo sí.
    @Test func sesionInicialSinAutomatismoEquiposSugeridos() async {
        let io = FakeTerminal(["Username: tu.usuario", "Password:"]) { _ in ["core-01#"] }
        let a = make(io, MemoryCredentialStore([.named("AD"): "pw"]), CredentialLedger(),
                     default: .init(name: "AD", user: "tu.usuario"))
        a.mode = .suggest
        #expect(await a.observe(io, gate: AutomationGate()) == nil)
        #expect(io.sent.isEmpty)
        io.screen += ["core-01#"]
        #expect(await a.observe(io, gate: AutomationGate()) == nil)
        #expect(a.loggedIn)
        a.beginCommand("telnet 192.0.2.9")
        io.screen += ["core-01#telnet 192.0.2.9", "Username: tu.usuario", "Password:"]
        #expect(await a.observe(io, gate: AutomationGate()) == .suggested(.named("AD"))) // equipo: sugerida
    }

    /// Un equipo hostil escribe «admin@core-01's password:» para llevarse la de core-01: no es el de la pestaña.
    @Test func promptFalsoDeOtroEquipoNoRecibeSuContraseña() async {
        let io = FakeTerminal(["admin@198.51.100.66's password:"])
        let a = make(io, MemoryCredentialStore([.device("admin", "198.51.100.66"): "secreta"]), CredentialLedger())
        a.beginCommand("ssh admin@192.0.2.1")
        #expect(await a.observe(io, gate: AutomationGate()) == .manual(.noCredential))
        #expect(io.sent.isEmpty)
        // (si la orden tecleada en la pestaña es «ssh admin@198.51.100.66», ese equipo sí es el de verdad)
        let io2 = FakeTerminal(["admin@198.51.100.66's password:"])
        let b = make(io2, MemoryCredentialStore([.device("admin", "198.51.100.66"): "secreta"]), CredentialLedger())
        b.beginCommand("ssh admin@198.51.100.66")
        #expect(await b.observe(io2, gate: AutomationGate()) == .typed(.device("admin", "198.51.100.66")))
    }

    /// Tras el salto «a mano», la del destino pasaría por la shell del salto: sólo se sugiere.
    @Test func trasElSaltoAManoSoloSeSugiere() async {
        let io = FakeTerminal(["bastion$ ssh admin@192.0.2.1", "admin@192.0.2.1's password:"])
        let a = make(io, MemoryCredentialStore([.device("admin", "192.0.2.1"): "pw"]), CredentialLedger())
        a.onlySuggestDevices = true
        _ = await a.observe(FakeTerminal(["bastion$"]), gate: AutomationGate())       // (ya en el prompt del salto)
        a.beginCommand("ssh admin@192.0.2.1")
        #expect(await a.observe(io, gate: AutomationGate()) == .suggested(.device("admin", "192.0.2.1")))
        #expect(io.sent.isEmpty)
    }

    @Test func escDuranteLaEsperaCancela() async {
        let io = FakeTerminal(["admin@192.0.2.1's password:"])
        let a = make(io, MemoryCredentialStore([.device("admin", "192.0.2.1"): "pw"]), CredentialLedger())
        a.beginCommand("ssh admin@192.0.2.1")
        a.settle = .milliseconds(300)
        let gate = AutomationGate()
        let t = Task { await a.observe(io, gate: gate) }
        for _ in 0..<10_000 where !gate.isBusy { await Task.yield() }       // (con tope: si no escribe, falla y no cuelga)
        #expect(gate.isBusy)
        #expect(gate.intercept([0x1B]))
        #expect(await t.value == .cancelled)
        #expect(io.sent.isEmpty)
    }
}

/// Los avisos modales (borrar en el explorador…) nunca dentro de la acción de un botón: en la vuelta siguiente.
@Suite @MainActor struct MainTurnTests {
    @Test func elAvisoVaDespuesDeLaAccion() async {
        var order: [String] = []
        let pending = Task { @MainActor in await MainTurn.next { order.append("aviso"); return 7 } }
        order.append("acción terminada")                     // (lo que queda del clic, antes que el aviso)
        #expect(await pending.value == 7)
        #expect(order == ["acción terminada", "aviso"])
    }

    @Test func quienPreguntaNoSeQuedaEsperandoDentroDelClic() async {
        var ran = false
        let pending = Task { @MainActor in await MainTurn.next { ran = true } }
        #expect(!ran)                                       // (el clic acaba sin haber abierto nada)
        await pending.value
        #expect(ran)
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
