import Foundation
import Testing
@testable import NetDeckCore

/// Sólo órdenes propias, con su contexto vivo; ni el login inicial ni un banner abren el almacén de contraseñas.
@Suite @MainActor struct AutenticacionAnidadaTests {
    let ref = CredentialRef.named("AD")

    private func automation(_ store: CredencialesControladas, _ ledger: CredentialLedger) -> PasswordAutomation {
        let a = PasswordAutomation(mode: .autoType, store: store, ledger: ledger) { _ in
            [.init(ref: .named("AD"), owners: ["tu.usuario"], origin: .defaultCredential)]
        }
        a.settle = .milliseconds(1)
        return a
    }

    private func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }

    @Test func sinOrdenNoSeMiranCandidatasNiAlmacen() async {
        let store = CredencialesControladas(), a = automation(store, CredentialLedger())
        var lookups = 0
        a.candidates = { _ in lookups += 1; return [] }
        a.commandUser = "tu.usuario"
        a.commandHosts = ["core-01"]                         // (asignar datos no equivale a enviar una orden)
        for screen in [["Username: tu.usuario", "Password:"], ["tu.usuario@core-01's password:"],
                       ["Bienvenido", "Password:"], ["Verification code:"], ["core-01#echo ssh tu.usuario@core-02", "Password:"]] {
            #expect(await a.observe(FakeTerminal(screen), gate: AutomationGate()) == nil)
        }
        #expect(lookups == 0 && store.consultas == 0 && store.lecturas == 0)
    }

    @Test func showRunCancelaElContextoYLaConfiguracionNoLoReabre() async {
        for command in ["show run", "show running-config"] {
            let store = CredencialesControladas(), ledger = CredentialLedger(), a = automation(store, ledger)
            var lookups = 0
            a.candidates = { _ in lookups += 1; return [.init(ref: .named("AD"), owners: ["tu.usuario"], origin: .defaultCredential)] }
            a.beginCommand("ssh tu.usuario@192.0.2.11")
            a.beginCommand(command)
            #expect(a.commandTarget == nil)
            let io = FakeTerminal(["core-01#\(command)"])
            for line in ["Building configuration...", "ssh admin@192.0.2.11", "telnet 192.0.2.11",
                         "username tu.usuario privilege 15 password 0 ejemplo", "Username: tu.usuario", "Password:",
                         "banner login ^", "(tu.usuario@192.0.2.11) Password:", "^", "core-01#"] {
                io.screen += [line]
                #expect(await a.observe(io, gate: AutomationGate()) == nil)
            }
            #expect(lookups == 0 && store.consultas == 0 && store.lecturas == 0 && io.sent.isEmpty)
            #expect(ledger.state(of: ref) == nil)                 // (ni probada, ni fallida, ni confirmada)
        }
    }

    @Test func soloUnaOrdenDeConexionSeguraArmaElContexto() async {
        let store = CredencialesControladas(), a = automation(store, CredentialLedger())
        for command in ["echo ssh tu.usuario@core-01", "show ssh tu.usuario@core-01", "sudo ssh tu.usuario@core-01",
                        "ssh tu.usuario@core-01; show clock", "ssh tu.usuario@core-01$(id)", "ssh -l -admin core-01",
                        "ssh core-01 ssh tu.usuario@core-02", "telnet -l tu.usuario core-01\nshow clock"] {
            a.beginCommand(command)
            #expect(a.commandTarget == nil, "«\(command)» no debe armarse")
            #expect(await a.observe(FakeTerminal(["Password:"]), gate: AutomationGate()) == nil)
        }
        #expect(store.consultas == 0 && store.lecturas == 0)
        a.beginCommand("ssh -p 2222 -J ops@bastion tu.usuario@core-01")
        #expect(a.commandTarget == Endpoint(user: "tu.usuario", host: "core-01", port: 2222))
        #expect(a.commandHosts == ["bastion", "core-01"] && a.commandJumpUsers == ["ops"])
    }

    @Test func passwordSinCuentaUsaSoloElUsuarioDeEstaOrden() async {
        for command in ["ssh tu.usuario@core-01", "telnet -l tu.usuario core-01"] {
            let store = CredencialesControladas(), a = automation(store, CredentialLedger())
            let io = FakeTerminal(["Password:"])
            a.beginCommand(command)
            #expect(await a.observe(io, gate: AutomationGate()) == .typed(ref))
            #expect(io.sent == ["secreto-demo\r"])
            a.cancelCommand()
        }
        let store = CredencialesControladas(), a = automation(store, CredentialLedger())
        a.beginCommand("telnet core-01")
        #expect(await a.observe(FakeTerminal(["Username: tu.usuario", "Password:"]), gate: AutomationGate()) == .typed(ref))
        a.cancelCommand()
    }

    @Test func noSeHeredaElUsuarioDelLoginInicial() async {
        let store = CredencialesControladas(), a = automation(store, CredentialLedger())
        let io = FakeTerminal(["Username: tu.usuario", "Password:"])
        #expect(await a.observe(io, gate: AutomationGate()) == nil)
        a.beginCommand("telnet core-01")
        io.screen += ["Password:"]                           // (el Username anterior era de la sesión, no del equipo)
        #expect(await a.observe(io, gate: AutomationGate()) == .manual(.unknownUser))
        #expect(io.sent.isEmpty && store.lecturas == 0)
    }

    @Test func otpYBannerNoRecibenLaContrasena() async {
        let store = CredencialesControladas(), a = automation(store, CredentialLedger())
        a.beginCommand("ssh tu.usuario@core-01")
        for line in ["Verification code:", "PASSCODE:", "Token:", "Bienvenido a core-01", "Last login: ayer"] {
            #expect(await a.observe(FakeTerminal([line]), gate: AutomationGate()) == nil)
        }
        #expect(store.consultas == 0 && store.lecturas == 0)
    }

    @Test func escDuranteLaPausaNoLlegaALeerElSecreto() async {
        let store = CredencialesControladas(), ledger = CredentialLedger(), a = automation(store, ledger)
        a.beginCommand("ssh tu.usuario@core-01")
        a.settle = .milliseconds(40)
        let io = FakeTerminal(["Password:"]), gate = AutomationGate()
        let task = Task { await a.observe(io, gate: gate) }
        #expect(await until { gate.isBusy })
        gate.abortAll()
        #expect(await task.value == .cancelled)
        #expect(io.sent.isEmpty && store.lecturas == 0 && ledger.state(of: ref) == nil)
        #expect(a.commandTarget == nil)
    }

    @Test func cancelarUnaLecturaNoEnviaNiDejaReserva() async {
        let store = CredencialesControladas(demoradas: true), ledger = CredentialLedger(), a = automation(store, ledger)
        defer { store.continuar() }
        a.beginCommand("ssh tu.usuario@core-01")
        let io = FakeTerminal(["Password:"])
        let task = Task { await a.observe(io, gate: AutomationGate()) }
        #expect(await until { store.lecturas == 1 })
        a.cancelCommand()
        #expect(ledger.state(of: ref) == nil)
        store.continuar()
        #expect(await task.value == .cancelled)
        #expect(io.sent.isEmpty && a.commandTarget == nil)
    }

    @Test func apagarElAutomatismoMientrasLeeNoEnvia() async {
        for suggestOnly in [false, true] {
            let store = CredencialesControladas(demoradas: true), ledger = CredentialLedger(), a = automation(store, ledger)
            defer { store.continuar() }
            a.beginCommand("ssh tu.usuario@core-01")
            let io = FakeTerminal(["Password:"])
            let task = Task { await a.observe(io, gate: AutomationGate()) }
            #expect(await until { store.lecturas == 1 })
            if suggestOnly { a.onlySuggestDevices = true } else { a.mode = .off }
            store.continuar()
            #expect(await task.value == .cancelled)
            #expect(io.sent.isEmpty && ledger.state(of: ref) == nil)
        }
    }

    @Test func unAwaitAntiguoNoLiberaLaReservaDelNuevoContexto() async {
        let store = CredencialesControladas(demoradas: true), ledger = CredentialLedger(), a = automation(store, ledger)
        defer { store.continuar(); a.cancelCommand() }
        a.beginCommand("ssh tu.usuario@core-01")
        let old = FakeTerminal(["Password:"])
        let first = Task { await a.observe(old, gate: AutomationGate()) }
        #expect(await until { store.lecturas == 1 })
        a.beginCommand("ssh tu.usuario@core-02")
        let current = FakeTerminal(["Password:"])
        let second = Task { await a.observe(current, gate: AutomationGate()) }
        #expect(await until { store.lecturas == 2 })
        store.continuar()
        #expect(await first.value == .cancelled)
        #expect(await second.value == .typed(ref))
        #expect(old.sent.isEmpty && current.sent == ["secreto-demo\r"])
        if case .probing = ledger.state(of: ref) {} else { Issue.record("el await antiguo soltó la reserva nueva") }
    }

    @Test func cancelarNoLiberaLaReservaDeOtraPestanaTrasReset() async throws {
        let store = CredencialesControladas(demoradas: true), ledger = CredentialLedger(), a = automation(store, ledger)
        defer { store.continuar() }
        a.beginCommand("ssh tu.usuario@core-01")
        let io = FakeTerminal(["Password:"])
        let task = Task { await a.observe(io, gate: AutomationGate()) }
        #expect(await until { store.lecturas == 1 })
        ledger.reset(ref)
        let other = ledger.reserveProbe(ref)
        let token = try #require(other.token)
        defer { ledger.release(ref, reservation: token) }
        a.cancelCommand()
        if case .probing = ledger.state(of: ref) {} else { Issue.record("la cancelación soltó la reserva ajena") }
        store.continuar()
        #expect(await task.value == .cancelled)
        #expect(io.sent.isEmpty)
    }

    @Test func resetInvalidaTambienLaEleccionManualEnCurso() async {
        for anyway in [false, true] {
            let store = CredencialesControladas(demoradas: true), a = automation(store, CredentialLedger())
            defer { store.continuar() }
            let io = FakeTerminal(["Password:"])
            let task = Task {
                if anyway { return await a.typeAnyway(ref, into: io, pressReturn: true) }
                return await a.typeManually(ref, into: io)
            }
            #expect(await until { store.lecturas == 1 })
            a.reset()
            store.continuar()
            #expect(await task.value == .notAsked)
            #expect(io.sent.isEmpty)
        }
    }

    @Test func cambiarLaCredencialDuranteLaLecturaInvalidaElIntentoSinCancelarLaPestana() async throws {
        for suggest in [false, true] {
            let store = CredencialesControladas(demoradas: true), ledger = CredentialLedger(), a = automation(store, ledger)
            defer { store.continuar(); a.cancelCommand() }
            a.mode = suggest ? .suggest : .autoType
            a.beginCommand("ssh tu.usuario@core-01")
            let io = FakeTerminal(["Password:"])
            if suggest { _ = await a.observe(io, gate: AutomationGate()) }
            let offer = a.offer?.id
            let task = Task {
                if let offer { _ = await a.choose(ref, offer: offer, into: io) }
                else { _ = await a.observe(io, gate: AutomationGate()) }
            }
            #expect(await until { store.lecturas == 1 })
            ledger.reset(ref)
            let fresh = try #require(ledger.reserveProbe(ref).token)
            store.continuar()
            await task.value
            #expect(io.sent.isEmpty)
            if case .probing(_, _, let token) = ledger.state(of: ref) { #expect(token == fresh) }
            else { Issue.record("el intento anterior resolvió la reserva nueva") }
            ledger.release(ref, reservation: fresh)
        }
    }

    @Test func confirmarOFallarTerminaElContexto() async {
        for succeeds in [false, true] {
            let store = CredencialesControladas(), ledger = CredentialLedger(), a = automation(store, ledger)
            let io = FakeTerminal(["Password:"]) { _ in succeeds ? ["core-01#"] : ["Permission denied", "Password:"] }
            a.beginCommand("ssh tu.usuario@core-01")
            #expect(await a.observe(io, gate: AutomationGate()) == .typed(ref))
            #expect(await a.observe(io, gate: AutomationGate()) == (succeeds ? .confirmed(ref) : .failed(ref)))
            #expect(a.commandTarget == nil && a.commandHosts.isEmpty)
            io.screen += ["Password:"]
            #expect(await a.observe(io, gate: AutomationGate()) == nil)
            #expect(store.lecturas == 1)
        }
    }

    /// La eliges tú (menú 🔑, botones): si no vale, se dice, pero no se bloquea; y se escribe aunque la por defecto
    /// esté bloqueada por un fallo suyo al escribirse sola.
    @Test func laEleccionManualNoBloqueaNiSeBloquea() async {
        let store = CredencialesControladas(), ledger = CredentialLedger(), a = automation(store, ledger)
        let io = FakeTerminal(["Password:"]) { _ in ["Password:"] }
        #expect(await a.typeManually(ref, into: io) == .typed)
        #expect(await a.observe(io, gate: AutomationGate()) == .rejected(ref))
        #expect(!ledger.isBlocked(ref))
        ledger.markFailed(ref)
        #expect(await a.typeManually(ref, into: io) == .typed)
        #expect(ledger.isBlocked(ref))                                     // (no la desbloquea)
    }

    @Test func elExitoManualNoResuelveLaReservaDeOtraPestana() async throws {
        let store = CredencialesControladas(), ledger = CredentialLedger(), a = automation(store, ledger)
        let other = try #require(ledger.reserveProbe(ref).token)
        let io = FakeTerminal(["Password:"]) { _ in ["core-01#"] }
        #expect(await a.typeManually(ref, into: io) == .typed)
        #expect(await a.observe(io, gate: AutomationGate()) == .confirmed(ref))
        if case .probing(_, _, let token) = ledger.state(of: ref) { #expect(token == other) }
        else { Issue.record("un éxito manual quitó la reserva ajena") }
        ledger.release(ref, reservation: other)
    }

    /// Sólo las compatibles, en orden y sin repetir; una bloqueada también (el aviso es tu clic, no se escribe sola).
    @Test func elSelectorSoloOfreceCompatiblesOrdenadas() async throws {
        let store = CredencialesControladas(), ledger = CredentialLedger(), a = automation(store, ledger)
        let second = CredentialRef.device("tu.usuario", "core-01"), blocked = CredentialRef.named("bloqueada"), other = CredentialRef.named("admin")
        ledger.markFailed(blocked)
        a.candidates = { _ in
            [.init(ref: self.ref, owners: ["tu.usuario"], origin: .defaultCredential),
             .init(ref: other, owners: ["admin"], origin: .sessionNamed),
             .init(ref: blocked, owners: ["tu.usuario"], origin: .sessionNamed),
             .init(ref: second, owners: ["tu.usuario"], origin: .device),
             .init(ref: self.ref, owners: ["tu.usuario"], origin: .defaultCredential)]
        }
        a.mode = .suggest; a.beginCommand("ssh tu.usuario@core-01")
        let io = FakeTerminal(["Password:"])
        #expect(await a.observe(io, gate: AutomationGate()) == .suggested(ref))
        let offer = try #require(a.offer)
        #expect(offer.refs == [ref, blocked, second] && offer.target.host == "core-01")
        #expect(await a.choose(other, offer: offer.id, into: io) == .notAsked)
        #expect(await a.choose(ref, offer: UUID(), into: io) == .notAsked)
        #expect(store.lecturas == 0 && io.sent.isEmpty)
        #expect(await a.choose(second, offer: offer.id, into: io) == .typed)
        #expect(a.offer == nil && io.sent == ["secreto-demo\r"])
        #expect(await a.choose(second, offer: offer.id, into: io) == .notAsked)
        a.cancelCommand()
    }

    @Test func cancelarONuevaOrdenInvalidaLaOfertaDeInmediato() async throws {
        for newCommand in [false, true] {
            let store = CredencialesControladas(), a = automation(store, CredentialLedger())
            a.mode = .suggest; a.beginCommand("ssh tu.usuario@core-01")
            let io = FakeTerminal(["Password:"])
            _ = await a.observe(io, gate: AutomationGate())
            let token = try #require(a.offer?.id)
            var hidden = false
            a.onOfferChange = { if $0 == nil { hidden = true } }
            if newCommand { a.beginCommand("ssh tu.usuario@core-02") } else { a.cancelCommand() }
            #expect(hidden && a.offer == nil)
            #expect(await a.choose(ref, offer: token, into: io) == .notAsked)
            #expect(store.lecturas == 0 && io.sent.isEmpty)
        }
    }

    @Test func unaOfertaNoSobreviveAlPromptNiAConfiguracionPosterior() async throws {
        for screen in [["core-01#"], ["core-01#show running-config", "Password:"], ["Username: admin", "Password:"]] {
            let store = CredencialesControladas(), a = automation(store, CredentialLedger())
            a.mode = .suggest; a.beginCommand("ssh tu.usuario@core-01")
            let io = FakeTerminal(["Username: tu.usuario", "Password:"])
            _ = await a.observe(io, gate: AutomationGate())
            let token = try #require(a.offer?.id)
            io.screen = screen
            #expect(await a.choose(ref, offer: token, into: io) == .notAsked)
            #expect(a.offer == nil && store.lecturas == 0 && io.sent.isEmpty)
        }
    }

    @Test func dobleClicYLookupCanceladoNoEnviaLaOfertaVieja() async throws {
        let store = CredencialesControladas(demoradas: true), ledger = CredentialLedger(), a = automation(store, ledger)
        defer { store.continuar() }
        a.mode = .suggest; a.beginCommand("ssh tu.usuario@core-01")
        let io = FakeTerminal(["Password:"])
        _ = await a.observe(io, gate: AutomationGate())
        let token = try #require(a.offer?.id)
        let task = Task { await a.choose(ref, offer: token, into: io) }
        #expect(await until { store.lecturas == 1 })
        #expect(a.offer?.id == token)                         // (sigue visible, pero no acepta otro envío)
        #expect(await a.choose(ref, offer: token, into: io) == .busy)
        a.cancelCommand()
        #expect(a.offer == nil && ledger.state(of: ref) == nil)
        store.continuar()
        #expect(await task.value == .notAsked)
        #expect(io.sent.isEmpty)
    }

    @Test func lookupDeOfertaConPantallaCambiadaNoEscribe() async throws {
        let store = CredencialesControladas(demoradas: true), ledger = CredentialLedger(), a = automation(store, ledger)
        defer { store.continuar() }
        a.mode = .suggest; a.beginCommand("ssh tu.usuario@core-01")
        let io = FakeTerminal(["Password:"])
        _ = await a.observe(io, gate: AutomationGate())
        let token = try #require(a.offer?.id)
        let task = Task { await a.choose(ref, offer: token, into: io) }
        #expect(await until { store.lecturas == 1 })
        io.screen += ["core-01#show running-config", "Password:"]
        store.continuar()
        #expect(await task.value == .notAsked)
        #expect(io.sent.isEmpty && a.offer == nil && ledger.state(of: ref) == nil)
    }

    /// Un fallo de la por defecto en otra pestaña mientras se lee la que has elegido en el aviso: la eliges tú, se escribe.
    @Test func unFalloMientrasSeLeeLaOfertaNoImpideTuEleccion() async throws {
        let store = CredencialesControladas(demoradas: true), ledger = CredentialLedger(), a = automation(store, ledger)
        defer { store.continuar() }
        a.mode = .suggest; a.beginCommand("ssh tu.usuario@core-01")
        let io = FakeTerminal(["Password:"])
        _ = await a.observe(io, gate: AutomationGate())
        let token = try #require(a.offer?.id)
        let task = Task { await a.choose(ref, offer: token, into: io) }
        #expect(await until { store.lecturas == 1 })
        ledger.markFailed(ref)
        store.continuar()
        #expect(await task.value == .typed)
        #expect(io.sent.count == 1 && ledger.isBlocked(ref))
    }

    @Test func otroIntentoPendienteNoSeAnunciaComoFallo() async {
        let store = CredencialesControladas(), ledger = CredentialLedger(), a = automation(store, ledger)
        _ = ledger.beginProbe(ref)
        a.beginCommand("ssh tu.usuario@core-01")
        #expect(await a.observe(FakeTerminal(["Password:"]), gate: AutomationGate()) == .manual(.pendingAttempt(ref)))
        #expect(store.lecturas == 0 && !ledger.isBlocked(ref))
    }

    /// El aviso dice cómo salir, con los nombres que se ven en Ajustes (en los dos idiomas).
    @Test func elAvisoDePendienteDiceComoSalir() {
        let text = Askpass.explain(.pendingAttempt(ref))
        #expect(text.contains(L("Restablecer pendiente")) && text.contains(L("Contraseñas")), "«\(text)»")
        #expect(Idioma.traducir("Restablecer pendiente", a: .en) == "Reset pending attempt")
    }

    @Test func unSegundoFactorNoCulpaALaContrasenaInterna() async {
        for screen in [["Verification code:"], ["PASSCODE:", "Authentication failed", "Password:"]] {
            let store = CredencialesControladas(), ledger = CredentialLedger(), a = automation(store, ledger)
            let io = FakeTerminal(["Password:"])
            a.beginCommand("ssh tu.usuario@core-01")
            #expect(await a.observe(io, gate: AutomationGate()) == .typed(ref))
            io.screen += screen
            #expect(await a.observe(io, gate: AutomationGate()) == .cancelled)
            #expect(!ledger.isBlocked(ref) && ledger.reserveProbe(ref).result == .wait && a.commandTarget == nil)
            io.screen += ["Password:"]
            #expect(await a.observe(io, gate: AutomationGate()) == nil)
            #expect(store.lecturas == 1 && io.sent == ["secreto-demo\r"])
            io.screen += ["core-01#"]
            _ = await a.observe(io, gate: AutomationGate())
            #expect(ledger.state(of: ref) == nil)                // (la shell confirma el fin del login pendiente)
        }
    }

    @Test func cancelarTrasEnviarNoPermiteOtraPruebaHastaVolverALaShell() async {
        let store = CredencialesControladas(), ledger = CredentialLedger(), a = automation(store, ledger)
        let io = FakeTerminal(["Password:"])
        a.beginCommand("ssh tu.usuario@core-01")
        #expect(await a.observe(io, gate: AutomationGate()) == .typed(ref))
        a.cancelCommand()
        #expect(ledger.reserveProbe(ref).result == .wait)
        #expect(await a.observe(io, gate: AutomationGate()) == nil)
        #expect(ledger.reserveProbe(ref).result == .wait)
        io.screen += ["bastion#"]
        _ = await a.observe(io, gate: AutomationGate())
        #expect(ledger.state(of: ref) == nil)
    }

    /// Con un «# @prompt» propio (el del equipo de la sesión), el prompt genérico del equipo al que se salta también
    /// termina su login: antes la reserva seguía pendiente mientras trabajabas en él y las demás pestañas no la usaban.
    @Test func elPromptGenericoTerminaElLoginAnidadoConPromptPropio() async throws {
        for cancels in [false, true] {
            let ledger = CredentialLedger(), a = automation(CredencialesControladas(), ledger)
            let io = PromptTerminal(["bastion$ ssh tu.usuario@core-01", "tu.usuario@core-01's password:"],
                                    prompt: try #require(PromptRule(#"^bastion\$$"#)))
            a.beginCommand("ssh tu.usuario@core-01")
            #expect(await a.observe(io, gate: AutomationGate()) == .typed(ref))
            if cancels { a.cancelCommand() }                    // (Esc tras enviarla: queda por resolver)
            io.screen += ["core-01#"]
            io.revision += 1
            let event = await a.observe(io, gate: AutomationGate())
            if cancels {
                #expect(event == nil && ledger.state(of: ref) == nil)
            } else {
                #expect(event == .confirmed(ref))
                if case .confirmed = ledger.state(of: ref) {} else { Issue.record("la reserva siguió pendiente") }
            }
            #expect(io.sent == ["secreto-demo\r"])
        }
    }

    @Test func cerrarLaConexionPreparaLaLimpiezaPeroNoLiberaAntesDeSuFin() async throws {
        let store = CredencialesControladas(), ledger = CredentialLedger(), a = automation(store, ledger)
        a.beginCommand("ssh tu.usuario@core-01")
        #expect(await a.observe(FakeTerminal(["Password:"]), gate: AutomationGate()) == .typed(ref))
        let cleanup = try #require(a.connectionCleanup())
        #expect(ledger.reserveProbe(ref).result == .wait)
        cleanup()                                             // (la vista sólo lo llama cuando el proceso ha terminado)
        #expect(ledger.state(of: ref) == nil)
    }

    @Test func laPestanaResuelveElPendienteQueLeEntregaUnaLista() async throws {
        for closes in [false, true] {
            let ledger = CredentialLedger(), a = automation(CredencialesControladas(), ledger)
            let token = try #require(ledger.reserveProbe(ref).token)
            a.registerPendingAuthentication(ref, reservation: token)
            a.retainPendingAuthentication(ref, reservation: token)
            #expect(ledger.reserveProbe(ref).result == .wait)
            if closes { a.connectionEnded() }
            else { _ = await a.observe(FakeTerminal(["bastion#"]), gate: AutomationGate()) }
            #expect(ledger.state(of: ref) == nil)
        }
    }

    @Test func reconectarAntesDeLaEntregaTardiaConservaLaLimpiezaEnLaConexionAnterior() throws {
        let ledger = CredentialLedger(), a = automation(CredencialesControladas(), ledger)
        let old = try #require(ledger.reserveProbe(ref).token)
        a.registerPendingAuthentication(ref, reservation: old)
        let cleanup = try #require(a.connectionCleanup())
        a.reset()                                             // (la conexión nueva todavía no ha llegado a prompt)
        a.retainPendingAuthentication(ref, reservation: old, ended: true) // (defer viejo; la nueva ya está en shell)
        #expect(ledger.reserveProbe(ref).result == .wait)      // (sigue siendo del PID anterior, que aún no terminó)
        cleanup()                                             // (termina el PID anterior)
        #expect(ledger.state(of: ref) == nil)
        let current = try #require(ledger.reserveProbe(ref).token)
        a.connectionEnded()
        if case .probing(_, _, let token) = ledger.state(of: ref) { #expect(token == current) }
        else { Issue.record("la limpieza vieja se llevó la conexión nueva") }
        ledger.release(ref, reservation: current)
    }

    @Test func soloSshYTelnetInteractivosSinPayloadArmanDeteccion() async {
        let store = CredencialesControladas(), a = automation(store, CredentialLedger())
        for command in ["ssh tu.usuario@core-01 echo Password:", "ssh tu.usuario@core-01 show running-config",
                        "ssh -N tu.usuario@core-01", "ssh -f tu.usuario@core-01", "ssh -T tu.usuario@core-01",
                        "ssh -G tu.usuario@core-01", "ssh -W core-02:22 tu.usuario@core-01", "ssh -V",
                        "ssh -oRemoteCommand=show tu.usuario@core-01", "telnet core-01 23 otra"] {
            a.beginCommand(command)
            #expect(a.commandTarget == nil, "«\(command)» no es un login interactivo")
            #expect(await a.observe(FakeTerminal(["Password:"]), gate: AutomationGate()) == nil)
        }
        for command in ["ssh -vv -p2222 -l tu.usuario -- core-01", "ssh -J ops@bastion tu.usuario@core-01",
                        "ssh -oUser=tu.usuario -oPort=2222 core-01", "telnet -l tu.usuario core-01 23"] {
            a.beginCommand(command)
            #expect(a.commandTarget?.user == "tu.usuario", "«\(command)» debe conservar el usuario")
        }
    }
}

/// La espera al retirar una autenticación (`TerminalSession`): antes, si el proceso no moría, no acababa nunca.
@Suite @MainActor struct FinDelProcesoTests {
    @Test func siNoMuereConSigtermSeMataALos3sYNoSeEsperaMasDe5s() async {
        let reloj = RelojVirtual()
        var kills: [Duration] = []
        await ProcessExit.wait(alive: { true }, kill: { kills.append(reloj.now()) }, clock: reloj)
        #expect(kills == [.seconds(3)])                         // (una sola vez)
        #expect(reloj.now() == .seconds(5))
    }

    @Test func siMuereNoSeMataYSiSeMataNoSeEsperaMas() async {
        let reloj = RelojVirtual()
        var kills = 0
        await ProcessExit.wait(alive: { reloj.now() < .seconds(1) }, kill: { kills += 1 }, clock: reloj)
        #expect(kills == 0 && reloj.now() == .seconds(1))
        let otro = RelojVirtual()
        var muerto = false
        await ProcessExit.wait(alive: { !muerto }, kill: { muerto = true }, clock: otro)
        #expect(muerto && otro.now() == .milliseconds(3100))  // (en cuanto muere, sin esperar a los 5 s)
    }
}

/// El único acceso externo de estos tests es este doble en memoria; la lectura puede esperar a que la prueba cancele.
private final class CredencialesControladas: CredentialStore, @unchecked Sendable {
    private let condition = NSCondition()
    private let demoradas: Bool
    private var permitido = false
    private var leidas = 0
    private var consultadas = 0
    init(demoradas: Bool = false) { self.demoradas = demoradas }
    var lecturas: Int { condition.lock(); defer { condition.unlock() }; return leidas }
    var consultas: Int { condition.lock(); defer { condition.unlock() }; return consultadas }
    func continuar() { condition.lock(); permitido = true; condition.broadcast(); condition.unlock() }
    func password(for ref: CredentialRef) throws -> String? {
        condition.lock()
        defer { condition.unlock() }
        leidas += 1
        while demoradas && !permitido { condition.wait() }
        return "secreto-demo"
    }
    func contains(_ ref: CredentialRef) -> Bool {
        condition.lock(); defer { condition.unlock() }
        consultadas += 1
        return true
    }
    func save(_ password: String, for ref: CredentialRef) throws {}
    func delete(_ ref: CredentialRef) throws {}
    func accounts(in service: CredentialRef.Service) throws -> [String] { [] }
}
