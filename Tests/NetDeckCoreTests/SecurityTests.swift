import Foundation
import Testing
@testable import NetDeckCore

@Suite struct PasswordPromptTests {
    @Test(arguments: [
        ("admin@192.0.2.1's password:", "admin"),
        ("(admin@192.0.2.1) Enter password:", "admin"),
        ("(admin@192.0.2.1) Password:", "admin"),
    ])
    func usuarioDeLaPeticion(line: String, user: String) throws {
        let r = try #require(PasswordPrompt.detect(cursorLine: line, above: []))
        #expect(r.user == user)
        #expect(r.account == "\(user)@192.0.2.1")
    }

    @Test func usuarioTecleadoEnUsername() throws {
        for prompt in ["Username: pepe", "login: pepe", "User: pepe", "login as: pepe"] {
            let r = try #require(PasswordPrompt.detect(cursorLine: "Password:", above: ["", prompt]))
            #expect(r.user == "pepe")
        }
    }

    @Test func noEsUnaPeticion() {
        #expect(!PasswordPrompt.asksForPassword("core-01#show run | i password:"))
        #expect(!PasswordPrompt.asksForPassword("core-01#"))
        #expect(PasswordPrompt.detect(cursorLine: "New password:", above: [])?.isChangeOrConfirm == true)
        #expect(PasswordPrompt.detect(cursorLine: "Retype password:", above: [])?.isChangeOrConfirm == true)
    }

    @Test func usuarioDeLaOrden() {
        #expect(CommandLineUser.parse("ssh root@192.0.2.1")?.user == "root")
        #expect(CommandLineUser.parse("ssh -p 2222 -l pepe 192.0.2.1") == Endpoint(user: "pepe", host: "192.0.2.1", port: 2222))
        #expect(CommandLineUser.parse("tu.usuario@bastion:~$ ssh -J bastion admin@192.0.2.5")?.user == "admin")
        #expect(CommandLineUser.parse("$ telnet -l admin 192.0.2.5 23") == Endpoint(user: "admin", host: "192.0.2.5", port: 23))
        #expect(CommandLineUser.parse("ssh -oUser=root 192.0.2.1")?.user == "root")
        #expect(CommandLineUser.parse("ls -la") == nil)
    }

    @Test func usuariosDeLosSaltosDeLaOrden() {
        #expect(CommandLineUser.jumpUsers("ssh -J tu.usuario@bastion,ops@b2:2222 admin@192.0.2.5") == ["tu.usuario", "ops"])
        #expect(CommandLineUser.jumpUsers("ssh -Jtu.usuario@bastion admin@192.0.2.5") == ["tu.usuario"])
        #expect(CommandLineUser.jumpUsers("ssh -o ProxyJump=ops@bastion 192.0.2.5") == ["ops"])
        #expect(CommandLineUser.jumpUsers("ssh -J bastion admin@192.0.2.5") == [])       // sin usuario: no se sabe
        #expect(CommandLineUser.jumpUsers("ssh admin@192.0.2.5 -J x@y") == [])          // (eso es la orden remota)
        #expect(CommandLineUser.jumpUsers("telnet 192.0.2.5") == [])
    }
}

/// REGLA CRÍTICA: nunca la por defecto (ni ninguna) a un usuario que no es el suyo.
@Suite struct CredentialPolicyTests {
    let policy = CredentialPolicy()
    let porDefecto = CredentialCandidate(ref: .named("AD"), owners: ["tu.usuario"], origin: .defaultCredential)
    let deAdmin = CredentialCandidate(ref: .device("admin", "192.0.2.1"), owners: ["admin"], origin: .device)

    func decide(_ line: String, above: [String] = [], command: String? = nil, _ c: [CredentialCandidate],
                blocked: Set<CredentialRef> = []) -> InjectionDecision {
        policy.decide(PasswordPrompt.detect(cursorLine: line, above: above)!, commandUser: command, candidates: c,
                      isBlocked: blocked.contains)
    }

    @Test func otroUsuarioEnLaOrdenNoRecibeLaPorDefecto() {
        #expect(decide("Password:", command: "root", [porDefecto]) == .manual(.userMismatch(requested: "root")))
    }

    @Test func otroUsuarioEnElPromptNoRecibeLaPorDefecto() {
        #expect(decide("root@192.0.2.1's password:", [porDefecto]) == .manual(.userMismatch(requested: "root")))
        #expect(decide("(pepe@192.0.2.1) Enter password:", [porDefecto]) == .manual(.userMismatch(requested: "pepe")))
        #expect(decide("Password:", above: ["Username: pepe"], [porDefecto]) == .manual(.userMismatch(requested: "pepe")))
    }

    @Test func coincidenciaExacta() {
        #expect(decide("tu.usuario@192.0.2.1's password:", [porDefecto]) == .inject(.named("AD")))
        #expect(decide("Tu.Usuario@192.0.2.1's password:", [porDefecto]) == .manual(.userMismatch(requested: "Tu.Usuario")))
    }

    @Test func saltaLasDeOtrosYTomaLaSuya() {
        #expect(decide("admin@192.0.2.1's password:", [porDefecto, deAdmin]) == .inject(.device("admin", "192.0.2.1")))
    }

    @Test func ordenYPromptSeContradicen() {
        #expect(decide("Password:", above: ["login: pepe"], command: "admin", [deAdmin])
                == .manual(.conflictingUsers(command: "admin", prompt: "pepe")))
    }

    /// v0.4: estricta por defecto. Sin saber qué usuario la pide, nada se escribe solo.
    @Test func sinUsuarioConocidoNadaSeEscribe() {
        #expect(decide("Password:", [porDefecto]) == .manual(.unknownUser))
        let sinDueño = CredentialCandidate(ref: .named("X"), owners: [], origin: .sessionNamed)
        #expect(decide("Password:", [sinDueño]) == .manual(.unknownUser))
        #expect(CredentialPolicy(allowWhenUserUnknown: true).decide(
            PasswordRequest(line: "Password:"), commandUser: nil, candidates: [porDefecto], isBlocked: { _ in false })
                == .inject(.named("AD")))
    }

    /// El equipo no puede desviar la contraseña: tras «ssh root@…» un «tu.usuario@…'s password:» falso no la recibe.
    @Test func elPromptNoContradiceALaOrden() {
        #expect(decide("tu.usuario@192.0.2.1's password:", command: "root", [porDefecto])
                == .manual(.conflictingUsers(command: "root", prompt: "tu.usuario")))
        #expect(decide("(tu.usuario@192.0.2.1) Password:", command: "root", [porDefecto])
                == .manual(.conflictingUsers(command: "root", prompt: "tu.usuario")))
        #expect(decide("admin@192.0.2.1's password:", command: "admin", [porDefecto, deAdmin])
                == .inject(.device("admin", "192.0.2.1")))
    }

    /// «ssh -J tu.usuario@bastion admin@…»: el salto pide la suya (otro usuario) y vale, porque la orden lo dice.
    @Test func losSaltosDeLaOrdenCuentan() {
        let r = PasswordPrompt.detect(cursorLine: "tu.usuario@bastion's password:", above: [])!
        #expect(policy.decide(r, commandUser: "admin", jumpUsers: ["tu.usuario"], candidates: [porDefecto],
                              isBlocked: { _ in false }) == .inject(.named("AD")))
        #expect(policy.decide(r, commandUser: "admin", jumpUsers: ["ops"], candidates: [porDefecto],
                              isBlocked: { _ in false }) == .manual(.conflictingUsers(command: "admin", prompt: "tu.usuario")))
    }

    @Test func bloqueadaPorFalloReciente() {
        #expect(decide("Password:", command: "tu.usuario", [porDefecto], blocked: [.named("AD")])
                == .manual(.recentlyFailed(.named("AD"))))
    }

    @Test func nuevaORepetirNuncaSola() {
        #expect(decide("New password:", [porDefecto]) == .manual(.changeOrConfirm))
    }
}

final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 0)
}

@Suite struct LedgerTests {
    /// Una confirmación (p. ej. la temprana del salto) nunca levanta el bloqueo de 15 min: sólo `reset` lo quita.
    @Test func confirmarNoQuitaUnFallo() {
        let c = Clock()
        let l = CredentialLedger(now: { c.now })
        let ad = CredentialRef.named("AD")
        l.markFailed(ad)
        l.confirm(ad)
        #expect(l.isBlocked(ad))
        #expect(l.beginProbe(ad) == .blocked)
        l.reset(ad)
        l.confirm(ad)
        #expect(!l.isBlocked(ad) && l.beginProbe(ad) == .go)
    }

    @Test func probandoFalloYCaducidad() {
        let c = Clock()
        let l = CredentialLedger(now: { c.now })
        let ad = CredentialRef.named("AD")
        #expect(l.beginProbe(ad) == .go)
        #expect(l.beginProbe(ad) == .wait)                 // otra pestaña la está probando
        l.markFailed(ad)
        #expect(l.beginProbe(ad) == .blocked)
        c.now += 15 * 60 + 1
        #expect(l.beginProbe(ad) == .go)
    }

    /// El askpass (otro proceso) y la app ven las mismas marcas.
    @Test func compartidoEnDisco() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = CredentialLedger(storage: DirectoryLedgerStorage(dir))
        let b = CredentialLedger(storage: DirectoryLedgerStorage(dir))
        #expect(a.beginProbe(.named("AD")) == .go)
        #expect(b.beginProbe(.named("AD")) == .wait)
        a.markFailed(.named("AD"))
        #expect(b.isBlocked(.named("AD")))
        b.reset(.named("AD"))
        #expect(a.state(of: .named("AD")) == nil)
    }
}

@Suite struct AskpassTests {
    @Test func loQueEscribeNoEsUnaPeticion() {
        #expect(!PasswordPrompt.asksForPassword("[NetDeck] admin@192.0.2.1's password: "))
    }

    @Test func preguntasDeSSH() {
        let q = Askpass.questions
        #expect(q[0].group(1, in: "admin@192.0.2.1's password: ") == "admin@192.0.2.1")
        #expect(q[1].group(1, in: "(admin@192.0.2.1) Password:") == "admin@192.0.2.1")
        #expect(Askpass.git.matches("Password for 'https://git.example': "))
    }

    @Test func idaYVuelta() {
        let r = CredentialRef.device("tu.usuario", "192.0.2.1")
        #expect(Askpass.decode(Askpass.encode(r)) == r)
        let env = Askpass.environment(executable: "/x", configPath: nil, session: UUID())
        #expect(env["SSH_ASKPASS_REQUIRE"] == "force")
        // (la predeterminada ya no va: nadie la leía y su nombre y usuario los veía todo lo que cuelga de ssh)
        #expect(env["NETDECK_DEFAULT"] == nil)
    }
}

@Suite struct KeychainQuotingTests {
    /// La contraseña va por la entrada de «security -i», entre comillas: «"» y «\» escapados, lo demás tal cual.
    @Test func comillasParaSecurityInteractivo() {
        #expect(KeychainStore.quoted(#"a"b\c d'e$f"#) == #""a\"b\\c d'e$f""#)
    }

    /// Lo que devuelve «security find-generic-password -g»: entre comillas o, si lleva algo fuera del ASCII
    /// imprimible (ñ, €, \…), en hexadecimal. Con «-w» esas salían en hexadecimal y se escribía el hexadecimal.
    @Test func contraseñaComplejaDelLlavero() {
        #expect(KeychainStore.decodePassword(#"password: "Ab$1!"q""#) == #"Ab$1!"q"#)
        #expect(KeychainStore.decodePassword(#"password: "deadbeef""#) == "deadbeef")
        #expect(KeychainStore.decodePassword(#"password: " lead trail ""#) == " lead trail ")
        #expect(KeychainStore.decodePassword(#"password: 0x70C3A4737377E282AC7264  "p\303\244ssw\342\202\254rd""#) == "pässw€rd")
        #expect(KeychainStore.decodePassword(#"password: 0x615C62  "a\134b""#) == #"a\b"#)
        #expect(KeychainStore.decodePassword("password:") == "")
        #expect(KeychainStore.decodePassword("algo raro") == nil)
        #expect(KeychainStore.decodePassword("password: 0xZZ") == nil)
    }
}
