import Foundation
import Testing
@testable import NetDeckCore

@Suite @MainActor struct CredentialManagementTests {
    @Test func nombresUnicodeSeConservanEnSesionesYGrupos() throws {
        let name = "\u{0301}Red España", group = "\u{FE0F}Core"
        let text = "# @grupo \(group)\n# @clave-grupo \(name)\nHost core-01\n    User tu.usuario\n    # @clave \(name)\n"
        let file = SessionFile(text: text)
        #expect(file.sessions.first?.credential == name)
        #expect(file.groupCredentials[group] == name)
        #expect(SSHConfigParser().parse(file.render()).first?.namedCredential == name)
    }
    @Test func unNombrePuedeLlevarBarrasEnUnBotonLogin() throws {
        let parts = try #require(CommandButton.loginParts("tu.usuario / Red/principal / España"))
        #expect(parts.user == "tu.usuario" && parts.credential == "Red/principal / España")
    }
    @Test func propiaDelEquipoNoEsUnaCredencialConNombreNiHeredaElGrupo() throws {
        let profiles = SSHConfigParser().parse("""
        # @grupo Core
        # @clave-grupo Red principal
        Host core-01
            HostName 192.0.2.11
            User tu.usuario
            # @clave -
        """)
        let profile = try #require(profiles.first)
        #expect(profile.namedCredential == nil)
        let sessions = SessionManager(profiles: profiles), route = try sessions.route(to: profile)
        let scope = sessions.initialCredentialScope(account: Endpoint(user: "tu.usuario", host: "192.0.2.11"), route: route)
        #expect(scope.named == nil)
        #expect(scope.candidates.map(\.ref) == [.device("tu.usuario", "192.0.2.11")])
    }

    @Test func renombrarConservaLaFechaDelBloqueoYSuCaducidad() {
        let date = Date(), storage = MemoryLedgerStorage()
        let old = CredentialRef.named("Red principal"), new = CredentialRef.named("Red nueva")
        storage.write(old, .failed(at: date.addingTimeInterval(-400)))
        let ledger = CredentialLedger(storage: storage, now: { date })
        #expect(ledger.copyFailure(from: old, to: new))
        #expect(ledger.state(of: new) == ledger.state(of: old))
        let later = CredentialLedger(storage: storage, now: { date.addingTimeInterval(501) })
        #expect(!later.isBlocked(new))
    }

    @Test func noSeRenombraUnLoginPendienteNiSeRebajaUnBloqueoMasReciente() {
        let storage = MemoryLedgerStorage(), date = Date()
        let ledger = CredentialLedger(storage: storage, now: { date })
        let old = CredentialRef.named("Red principal"), new = CredentialRef.named("Red nueva")
        _ = ledger.beginProbe(old)
        #expect(!ledger.copyFailure(from: old, to: new))
        #expect(ledger.state(of: new) == nil)
        ledger.release(old)
        storage.write(old, .failed(at: date.addingTimeInterval(-60)))
        storage.write(new, .failed(at: date))
        #expect(ledger.copyFailure(from: old, to: new))
        #expect(ledger.state(of: new) == .failed(at: date))
    }
}
