import Foundation
import Testing
@testable import NetDeckCore

@Suite struct PasswordPromptTests {
    @Test(arguments: [
        ("admin@10.0.0.1's password:", "admin"),
        ("(admin@10.0.0.1) Enter password:", "admin"),
        ("(admin@10.0.0.1) Password:", "admin"),
    ])
    func usuarioDeLaPeticion(line: String, user: String) throws {
        let r = try #require(PasswordPrompt.detect(cursorLine: line, above: []))
        #expect(r.user == user)
        #expect(r.account == "\(user)@10.0.0.1")
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
        #expect(CommandLineUser.parse("ssh root@10.0.0.1")?.user == "root")
        #expect(CommandLineUser.parse("ssh -p 2222 -l pepe 10.0.0.1") == Endpoint(user: "pepe", host: "10.0.0.1", port: 2222))
        #expect(CommandLineUser.parse("tu.usuario@bastion:~$ ssh -J bastion admin@10.0.0.5")?.user == "admin")
        #expect(CommandLineUser.parse("$ telnet -l admin 10.0.0.5 23") == Endpoint(user: "admin", host: "10.0.0.5", port: 23))
        #expect(CommandLineUser.parse("ssh -oUser=root 10.0.0.1")?.user == "root")
        #expect(CommandLineUser.parse("ls -la") == nil)
    }
}

/// REGLA CRÍTICA: nunca la por defecto (ni ninguna) a un usuario que no es el suyo.
@Suite struct CredentialPolicyTests {
    let policy = CredentialPolicy()
    let porDefecto = CredentialCandidate(ref: .named("AD"), owners: ["tu.usuario"], origin: .defaultCredential)
    let deAdmin = CredentialCandidate(ref: .device("admin", "10.0.0.1"), owners: ["admin"], origin: .device)

    func decide(_ line: String, above: [String] = [], command: String? = nil, _ c: [CredentialCandidate],
                blocked: Set<CredentialRef> = []) -> InjectionDecision {
        policy.decide(PasswordPrompt.detect(cursorLine: line, above: above)!, commandUser: command, candidates: c,
                      isBlocked: blocked.contains)
    }

    @Test func otroUsuarioEnLaOrdenNoRecibeLaPorDefecto() {
        #expect(decide("Password:", command: "root", [porDefecto]) == .manual(.userMismatch(requested: "root")))
    }

    @Test func otroUsuarioEnElPromptNoRecibeLaPorDefecto() {
        #expect(decide("root@10.0.0.1's password:", [porDefecto]) == .manual(.userMismatch(requested: "root")))
        #expect(decide("(pepe@10.0.0.1) Enter password:", [porDefecto]) == .manual(.userMismatch(requested: "pepe")))
        #expect(decide("Password:", above: ["Username: pepe"], [porDefecto]) == .manual(.userMismatch(requested: "pepe")))
    }

    @Test func coincidenciaExacta() {
        #expect(decide("tu.usuario@10.0.0.1's password:", [porDefecto]) == .inject(.named("AD")))
        #expect(decide("Tu.Usuario@10.0.0.1's password:", [porDefecto]) == .manual(.userMismatch(requested: "Tu.Usuario")))
    }

    @Test func saltaLasDeOtrosYTomaLaSuya() {
        #expect(decide("admin@10.0.0.1's password:", [porDefecto, deAdmin]) == .inject(.device("admin", "10.0.0.1")))
    }

    @Test func ordenYPromptSeContradicen() {
        #expect(decide("Password:", above: ["login: pepe"], command: "admin", [deAdmin])
                == .manual(.conflictingUsers(command: "admin", prompt: "pepe")))
    }

    @Test func sinUsuarioConocidoValeLaPrimera() {
        #expect(decide("Password:", [porDefecto]) == .inject(.named("AD")))
        #expect(CredentialPolicy(allowWhenUserUnknown: false).decide(
            PasswordRequest(line: "Password:"), commandUser: nil, candidates: [porDefecto], isBlocked: { _ in false })
                == .manual(.noCredential))
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
        #expect(!PasswordPrompt.asksForPassword("[NetDeck] admin@10.0.0.1's password: "))
    }

    @Test func preguntasDeSSH() {
        let q = Askpass.questions
        #expect(q[0].group(1, in: "admin@10.0.0.1's password: ") == "admin@10.0.0.1")
        #expect(q[1].group(1, in: "(admin@10.0.0.1) Password:") == "admin@10.0.0.1")
        #expect(Askpass.git.matches("Password for 'https://git.example': "))
    }

    @Test func idaYVuelta() {
        let r = CredentialRef.device("tu.usuario", "10.0.0.1")
        #expect(Askpass.decode(Askpass.encode(r)) == r)
        let env = Askpass.environment(executable: "/x", configPath: nil, defaultCredential: .init(name: "AD", user: "tu.usuario"),
                                      session: UUID())
        #expect(env["SSH_ASKPASS_REQUIRE"] == "force")
        #expect(env["NETDECK_DEFAULT"] == "AD\ttu.usuario")
    }
}
