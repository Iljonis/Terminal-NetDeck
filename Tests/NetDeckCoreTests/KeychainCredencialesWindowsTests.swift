#if os(Windows)
import Foundation
import Testing
@testable import NetDeckCore

/// KeychainStore en Windows: escribe, lee y borra credenciales del Administrador de credenciales con un servicio de prueba.
/// Cada test usa una cuenta distinta para que los tests paralelos no interfieran entre si.
@Suite struct KeychainCredencialesWindowsTests {
    @Test func guardarYLeerCredencial() throws {
        let ref = CredentialRef(service: .named, account: "test-p6-rw")
        let store = KeychainStore()
        defer { try? store.delete(ref) }
        try store.save("clave-de-prueba", for: ref)
        #expect(try store.password(for: ref) == "clave-de-prueba")
    }

    @Test func borrarCredencial() throws {
        let ref = CredentialRef(service: .named, account: "test-p6-del")
        let store = KeychainStore()
        try store.save("temporal", for: ref)
        try store.delete(ref)
        #expect(try store.password(for: ref) == nil)
    }

    @Test func createFallaSiYaExiste() throws {
        let ref = CredentialRef(service: .named, account: "test-p6-cre")
        let store = KeychainStore()
        defer { try? store.delete(ref) }
        try store.save("primera", for: ref)
        #expect(throws: KeychainError.self) {
            try store.create("segunda", for: ref)
        }
    }

    @Test func accountsListaLaCuentaGuardada() throws {
        let ref = CredentialRef(service: .named, account: "test-p6-lst")
        let store = KeychainStore()
        defer { try? store.delete(ref) }
        try store.save("clave-de-prueba", for: ref)
        let cuentas = try store.accounts(in: .named)
        #expect(cuentas.contains("test-p6-lst"))
    }

    @Test func borrarInexistenteNoLanzaError() throws {
        let store = KeychainStore()
        let refInexistente = CredentialRef(service: .named, account: "test-p6-no-existe")
        #expect(throws: Never.self) {
            try store.delete(refInexistente)
        }
    }

    @Test func contieneFalsoParaCredencialInexistente() {
        let store = KeychainStore()
        let refInexistente = CredentialRef(service: .named, account: "test-p6-inexistente")
        #expect(!store.contains(refInexistente))
    }
}
#endif