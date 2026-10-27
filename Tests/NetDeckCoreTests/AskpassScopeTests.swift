import Foundation
import Testing
@testable import NetDeckCore

/// El flujo real del ayudante, sustituyendo sólo Llavero, terminal y salida de ssh por memoria.
@MainActor @Suite(.serialized) struct AskpassScopeTests {
    let a = SessionProfile(name: "core-01", hostName: "192.0.2.11", user: "tu.usuario", namedCredential: "clave-a")
    let b = SessionProfile(name: "core-01-alterno", hostName: "192.0.2.11", user: "tu.usuario", port: 2222, namedCredential: "clave-b")

    @Test func elAliasExactoGanaAunqueCompartaEquipoYUsuario() throws {
        let test = try Inicio(profiles: [a, b], selected: b, items: [.named("clave-a"): "primera", .named("clave-b"): "segunda"])
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        #expect(test.answers == ["segunda"] && test.ui.secretReads.isEmpty)
        #expect(test.ledger.state(of: .named("clave-b")) == nil)       // (no crea una reserva)
    }

    @Test func sinCredencialPropiaNoPruebaOtraSesionNiLaPredeterminada() throws {
        let test = try Inicio(profiles: [a, b], selected: b, items: [.named("clave-a"): "primera", .named("general"): "generica"])
        test.environment["NETDECK_DEFAULT"] = "general\ttu.usuario"
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 1)
        #expect(test.answers.isEmpty && test.ui.secretReads == [true])
        #expect(test.ledger.state(of: .named("general")) == nil)
    }

    @Test func noGuardaLaDeOtroUsuarioEnLaClaveDelPerfil() throws {
        let admin = SessionProfile(name: "core-admin", hostName: a.endpoint.host, user: "admin", namedCredential: "administracion")
        let test = try Inicio(profiles: [a, admin], selected: a,
                              items: [.named("clave-a"): "primera", .named("administracion"): "otra"])
        test.ui.responses = ["manual"]; test.ui.save = true
        #expect(test.ask("admin@192.0.2.11's password:") == 0)
        #expect(test.answers == ["manual"])
        #expect(try test.store.password(for: .named("clave-a")) == "primera")
        #expect(try test.store.password(for: .named("administracion")) == "otra")
        #expect(try test.store.password(for: .device("admin", "192.0.2.11")) == "manual")
    }

    @Test func guardarManualUsaElAliasSeleccionadoSinReserva() throws {
        let test = try Inicio(profiles: [a, b], selected: b, items: [.named("clave-a"): "primera"])
        test.environment[Askpass.manualFlag] = "1"
        test.ui.responses = ["manual"]; test.ui.save = true
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        #expect(try test.store.password(for: .named("clave-b")) == "manual")
        #expect(try test.store.password(for: .named("clave-a")) == "primera")
        #expect(test.ledger.state(of: .named("clave-b")) == nil)
    }

    @Test func elGrupoPropioSeUsaTambienEnSftp() throws {
        let profiles = SSHConfigParser().parse("""
            # @grupo Core
            # @clave-grupo grupo-core
            Host core-01
              HostName 192.0.2.11
              User tu.usuario
              # @tipo sftp
            """)
        let test = try Inicio(profiles: profiles, selected: #require(profiles.first), items: [.named("grupo-core"): "grupo"])
        #expect(test.ask("(tu.usuario@192.0.2.11) Password:") == 0)
        #expect(test.answers == ["grupo"] && test.ui.secretReads.isEmpty)
    }

    @Test func unaConexionDirectaSinGuardarUsaSoloSuUsuarioEquipo() throws {
        let route = ConnectionRoute(title: "directa", target: Endpoint(user: "tu.usuario", host: "192.0.2.11", port: 2222))
        let test = try Inicio(profiles: [a, b], route: route,
                              items: [.named("clave-a"): "primera", .named("clave-b"): "segunda", .device("tu.usuario", "192.0.2.11"): "propia"])
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        #expect(test.answers == ["propia"])
    }

    @Test func cadaProxyJumpUsaSuAliasSinBuscarPorHostName() throws {
        let jumpA = SessionProfile(name: "bastion", hostName: "192.0.2.1", user: "tu.usuario", namedCredential: "salto-a")
        let jumpB = SessionProfile(name: "bastion-alterno", hostName: "192.0.2.1", user: "tu.usuario", port: 2222, namedCredential: "salto-b")
        var target = a; target.proxyJump = [jumpB.name]
        let test = try Inicio(profiles: [jumpA, jumpB, target], selected: target,
                              items: [.named("salto-a"): "primera", .named("salto-b"): "salto", .named("clave-a"): "destino"])
        #expect(test.ask("tu.usuario@192.0.2.1's password:") == 0)
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        #expect(test.answers == ["salto", "destino"])
        #expect(!test.ledger.isBlocked(.named("salto-b")))
    }

    @Test func unPuertoExplicitoDelSaltoSeRespeta() throws {
        let jump = SessionProfile(name: "bastion", hostName: "192.0.2.1", user: "tu.usuario", namedCredential: "salto")
        var target = a; target.proxyJump = ["admin@bastion:2222"]
        let manager = SessionManager(profiles: [jump, target])
        let route = try manager.route(to: target)
        #expect(route.jumps == [Endpoint(user: "admin", host: "192.0.2.1", port: 2222)])
        let test = try Inicio(profiles: [jump, target], route: route, items: [.named("salto"): "otra"])
        #expect(test.ask("admin@192.0.2.1's password:") == 1)             // (no hereda la del otro usuario/puerto)
        #expect(test.answers.isEmpty)
    }

    @Test func etapasAmbiguasConDistintoPuertoQuedanManuales() throws {
        var target = b; target.proxyJump = [a.name]
        let test = try Inicio(profiles: [a, target], selected: target, items: [.named("clave-a"): "primera", .named("clave-b"): "segunda"])
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 1)
        #expect(test.answers.isEmpty && test.ui.secretReads == [true])
    }

    @Test func elSaltoManualConservaElPerfilDelPrimerSsh() throws {
        let jump = SessionProfile(name: "bastion", hostName: "192.0.2.1", user: "admin", namedCredential: "salto")
        var target = a; target.proxyJump = ["admin@bastion"]
        let manager = SessionManager(profiles: [jump, target])
        let saved = try manager.route(to: target), fallback = try manager.typedHop(for: saved)
        let route = try #require(fallback)
        #expect(route.sessionName == target.name && route.authenticationProfile == jump.name && route.alias == nil)
        let test = try Inicio(profiles: [jump, target], route: route, items: [.named("salto"): "propia", .named("clave-a"): "destino"])
        #expect(test.ask("admin@192.0.2.1's password:") == 0)
        #expect(test.answers == ["propia"])
        // (la contraseña del destino se tratará dentro de la sesión, no en este askpass)
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 1)
        #expect(test.answers == ["propia"])
        let restored = try JSONDecoder().decode(ConnectionRoute.self, from: JSONEncoder().encode(route))
        #expect(restored.authenticationProfile == jump.name)
    }

    @Test func elSaltoManualConOtroUsuarioOPuertoNoHeredaLaClave() throws {
        let jump = SessionProfile(name: "bastion", hostName: "192.0.2.1", user: "tu.usuario", namedCredential: "salto")
        for spec in ["admin@bastion", "tu.usuario@bastion:2222"] {
            var target = a; target.proxyJump = [spec]
            let manager = SessionManager(profiles: [jump, target])
            let saved = try manager.route(to: target), fallback = try manager.typedHop(for: saved)
            let route = try #require(fallback)
            #expect(route.authenticationProfile == jump.name)
            let test = try Inicio(profiles: [jump, target], route: route, items: [.named("salto"): "otra"])
            let user = spec.hasPrefix("admin@") ? "admin" : "tu.usuario"
            #expect(test.ask("\(user)@192.0.2.1's password:") == 1)
            #expect(test.answers.isEmpty)
            if spec.hasSuffix(":2222") { #expect(route.target.port == 2222) }
        }
    }

    @Test func elEstadoProbandoDeOtraPestanaNoHaceEsperarAlInicio() throws {
        let test = try Inicio(profiles: [a], selected: a, items: [.named("clave-a"): "propia"])
        #expect(test.ledger.beginProbe(.named("clave-a")) == .go)
        let before = test.ledger.state(of: .named("clave-a"))
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        #expect(test.answers == ["propia"] && test.ui.secretReads.isEmpty)
        #expect(!test.ui.messages.contains { $0.contains("probando") })
        #expect(test.ledger.state(of: .named("clave-a")) == before)
    }

    /// Un fallo de esa misma contraseña en otra parte (la por defecto escrita sola) no impide a la sesión probarla una
    /// vez: el bloqueo es sólo de la por defecto escrita sola.
    @Test func unFalloEnOtraParteNoImpideProbarlaEnLaSesion() throws {
        let test = try Inicio(profiles: [a], selected: a, items: [.named("clave-a"): "propia"])
        test.ledger.markFailed(.named("clave-a"))
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        #expect(test.answers == ["propia"] && test.ui.secretReads.isEmpty)
    }

    /// ssh vuelve a preguntar: la guardada no valía → te la pide a ti, sin bloquearla. Si la que escribes tú (sin
    /// guardarla) tampoco vale, te la vuelve a pedir: la guardada no se prueba sola otra vez en este ssh.
    @Test func repetirLaPreguntaTeLaPideSinBloquear() throws {
        let test = try Inicio(profiles: [a], selected: a, items: [.named("clave-a"): "rechazada"])
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        test.ui.responses = ["mala"]
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)            // (te la pide: la escribes tú)
        #expect(test.ui.messages.contains { $0.contains("escríbela tú") })
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 1)            // (otra vez a ti; aquí, Esc)
        #expect(test.answers == ["rechazada", "mala"] && test.ui.secretReads == [true, true])
        #expect(!test.ledger.isBlocked(.named("clave-a")))
        #expect(!test.ui.messages.contains { $0.contains("15 min") })
    }

    /// ssh repregunta tarde (TACACS lento) y, mientras, la has guardado otra vez en otra pestaña o en Ajustes: lo
    /// rechazado era la anterior. No se bloquea la nueva (antes, 15 min), aunque esta vez te la pide a ti.
    @Test func repetirTrasGuardarlaOtraVezNoBloqueaLaNueva() throws {
        let test = try Inicio(profiles: [a], selected: a, items: [.named("clave-a"): "anterior"])
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        let state = test.directory.appendingPathComponent("estado")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-5)], ofItemAtPath: state.path)
        test.ledger.reset(.named("clave-a"))
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 1)          // (te la pide: aquí, Esc)
        #expect(!test.ledger.isBlocked(.named("clave-a")) && test.ui.secretReads == [true])
        #expect(!test.ui.messages.contains { $0.contains("15 min") })
        #expect(test.answers == ["anterior"])
    }

    @Test func preguntarPorOtroUsuarioNoEsUnRechazoDelPrimero() throws {
        let test = try Inicio(profiles: [a], selected: a, items: [.named("clave-a"): "propia"])
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        #expect(test.ask("admin@192.0.2.11's password:") == 1)
        #expect(!test.ledger.isBlocked(.named("clave-a")))
    }

    @Test func cancelarOtpNoBloqueaLaContrasenaAnterior() throws {
        let test = try Inicio(profiles: [a], selected: a, items: [.named("clave-a"): "propia"])
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        #expect(test.ask("(tu.usuario@192.0.2.11) Enter PASSCODE:") == 1)
        let failed = Askpass.settleAfterExit(session: test.session, ledger: test.ledger, directory: test.directory) {
            Askpass.rejection(in: ["tu.usuario@192.0.2.11: Permission denied (keyboard-interactive)."])
        }
        #expect(failed.isEmpty && !test.ledger.isBlocked(.named("clave-a")))
        #expect(test.ui.secretReads == [true])
    }

    @Test func unOtpIncorrectoTampocoBloqueaLaContrasena() throws {
        let test = try Inicio(profiles: [a], selected: a, items: [.named("clave-a"): "propia"])
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        test.ui.responses = ["codigo"]
        #expect(test.ask("(tu.usuario@192.0.2.11) Enter PASSCODE:") == 0)
        let failed = Askpass.settleAfterExit(session: test.session, ledger: test.ledger, directory: test.directory) {
            Askpass.rejection(in: ["tu.usuario@192.0.2.11: Permission denied (keyboard-interactive)."])
        }
        #expect(failed.isEmpty && !test.ledger.isBlocked(.named("clave-a")))
    }

    @Test func volverAPedirContrasenaTrasElOtpNoEsUnRechazoSeguroDeElla() throws {
        let test = try Inicio(profiles: [a], selected: a, items: [.named("clave-a"): "propia"])
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        test.ui.responses = ["codigo"]
        #expect(test.ask("(tu.usuario@192.0.2.11) Enter PASSCODE:") == 0)
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        #expect(test.answers == ["propia", "codigo", "propia"] && !test.ledger.isBlocked(.named("clave-a")))
    }

    @Test func unaCredencialPosteriorAlOtpSiSePuedeAtribuir() throws {
        let jump = SessionProfile(name: "bastion", hostName: "192.0.2.1", user: "tu.usuario", namedCredential: "salto")
        var target = a; target.proxyJump = [jump.name]
        let test = try Inicio(profiles: [jump, target], selected: target, items: [.named("salto"): "propia", .named("clave-a"): "rechazada"])
        #expect(test.ask("tu.usuario@192.0.2.1's password:") == 0)
        test.ui.responses = ["codigo"]
        #expect(test.ask("(tu.usuario@192.0.2.1) Enter PASSCODE:") == 0)
        #expect(test.ask("tu.usuario@192.0.2.11's password:") == 0)
        let failed = Askpass.settleAfterExit(session: test.session, ledger: test.ledger, directory: test.directory) {
            Askpass.rejection(in: ["tu.usuario@192.0.2.11: Permission denied (password)."])
        }
        #expect(failed == [.named("clave-a")] && !test.ledger.isBlocked(.named("clave-a")))   // (se dice; no se bloquea)
        #expect(!test.ledger.isBlocked(.named("salto")))
    }

    @Test func entrarTrasElOtpConfirmaLaContrasena() {
        let ref = CredentialRef.named("clave-a")
        let attempts = [Askpass.Attempt(ref: ref, host: "core-01"),
                        Askpass.Attempt(ref: nil, host: "core-01", manualFactor: true)]
        let result = Askpass.attribute(attempts)
        #expect(result.confirmed == [ref] && result.failed.isEmpty)
    }

    @Test func otpYPassphraseSiguenManualesYSinEco() throws {
        let test = try Inicio(profiles: [a], selected: a, items: [.named("clave-a"): "propia"])
        for question in ["Enter PASSCODE:", "Enter passphrase for key '/x':", "New password:"] {
            test.ui.responses = ["manual"]
            #expect(test.ask(question) == 0)
        }
        #expect(test.answers == ["manual", "manual", "manual"] && test.ui.secretReads == [true, true, true])
        #expect(test.ledger.state(of: .named("clave-a")) == nil)
    }

    @Test func unEquipoAjenoALaRutaNoRecibeNingunaGuardada() throws {
        let test = try Inicio(profiles: [a, b], selected: a, items: [.device("tu.usuario", "192.0.2.12"): "ajena"])
        #expect(test.ask("tu.usuario@192.0.2.12's password:") == 1)
        #expect(test.answers.isEmpty)
    }

    @Test func laOrdenInternaRespetaElAliasExplicito() {
        let manager = SessionManager(profiles: [a, b])
        let request = PasswordRequest(line: "tu.usuario@192.0.2.11's password:", account: "tu.usuario@192.0.2.11")
        let candidates = manager.credentialCandidates(for: request, route: nil, defaultCredential: nil, typedHosts: [b.name])
        #expect(candidates.first?.ref == .named("clave-b"))
        let ambiguous = manager.credentialCandidates(for: request, route: nil, defaultCredential: nil, typedHosts: ["192.0.2.11"])
        #expect(ambiguous.map(\.ref) == [.device("tu.usuario", "192.0.2.11")])
    }

    @Test func otroEquipoNoPuedePedirLaPredeterminadaDelUsuarioCorrecto() {
        let manager = SessionManager(profiles: [a])
        let request = PasswordRequest(line: "tu.usuario@192.0.2.12's password:", account: "tu.usuario@192.0.2.12")
        let candidates = manager.credentialCandidates(for: request, route: nil,
                                                       defaultCredential: .init(name: "general", user: "tu.usuario"), typedHosts: [a.name])
        #expect(candidates.isEmpty)
    }

    @Test func cambiarElPuertoNoHeredaUnaClaveDeOtroExtremo() {
        let manager = SessionManager(profiles: [a])
        let request = PasswordRequest(line: "tu.usuario@192.0.2.11's password:", account: "tu.usuario@192.0.2.11")
        let route = ConnectionRoute(title: a.name, target: Endpoint(user: "tu.usuario", host: "192.0.2.11", port: 2222), sessionName: a.name)
        let routed = manager.credentialCandidates(for: request, route: route, defaultCredential: nil)
        #expect(routed.map(\.ref) == [.device("tu.usuario", "192.0.2.11")])
        let typed = manager.credentialCandidates(for: request, route: nil, defaultCredential: nil, typedHosts: [a.name],
                                                typedTarget: Endpoint(user: "tu.usuario", host: a.name, port: 2222))
        #expect(typed.map(\.ref) == [.device("tu.usuario", "192.0.2.11")])
    }
}

@MainActor private final class Inicio {
    let manager: SessionManager
    let store: MemoryCredentialStore
    let ledger = CredentialLedger()
    let directory: URL
    let session = UUID()
    let ui = Entrada()
    var environment: [String: String]
    var answers: [String] = []

    convenience init(profiles: [SessionProfile], selected: SessionProfile, items: [CredentialRef: String]) throws {
        let route = try SessionManager(profiles: profiles).route(to: selected)
        try self.init(profiles: profiles, route: route, items: items)
    }

    init(profiles: [SessionProfile], route: ConnectionRoute, items: [CredentialRef: String]) throws {
        manager = SessionManager(profiles: profiles)
        store = MemoryCredentialStore(items)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("askpass-inicio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        environment = Askpass.environment(executable: "/x", configPath: nil, session: session,
                                          profile: route.sessionName, route: route)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func ask(_ question: String) -> Int32 {
        Askpass.respond(question: question, environment: environment, manager: manager, store: store, ledger: ledger,
                        tty: ui, state: directory.appendingPathComponent("estado"), directory: directory) {
            self.answers.append($0); return 0
        }
    }
}

private final class Entrada: AskpassUI {
    var responses: [String?] = []
    var save = false
    var messages: [String] = []
    var secretReads: [Bool] = []
    func say(_ s: String) { messages.append(s) }
    func read(secret: Bool) -> String? { secretReads.append(secret); return responses.isEmpty ? nil : responses.removeFirst() }
    func yesNo(_ question: String, default d: Bool) -> Bool? { save }
}
