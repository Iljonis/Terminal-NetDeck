import Foundation
import Testing
@testable import NetDeckCore

/// Sólo valida y construye órdenes en memoria: ninguna prueba ejecuta `security` ni toca el Llavero real.
@Suite struct CredentialValidationTests {
    @Test func elAltaNoSustituyeUnaCuentaExistente() throws {
        let create = try KeychainStore.saveCommand("ejemplo", for: .named("AD"), replaceExisting: false)
        let update = try KeychainStore.saveCommand("ejemplo", for: .named("AD"))
        #expect(create.hasPrefix("\"add-generic-password\" \"-s\" ") && !create.contains("\"-U\""))
        #expect(update.hasPrefix("\"add-generic-password\" \"-U\" \"-s\" "))
    }

    @Test func nombresUnicodeYEspaciosInterioresSonValidos() throws {
        for name in ["AD", "Operación España", "  acceso  ", "🗝 acceso", "名前"] {
            let ref = CredentialRef.named(name)
            try CredentialValidation.validateReference(ref)
            let command = try KeychainStore.saveCommand("ejemplo", for: ref)
            #expect(command.contains("\"-a\" " + KeychainStore.quoted(name)))
        }
    }

    @Test func rechazaNombresVaciosReservadosYControlesAntesDeConstruirLaOrden() {
        for name in ["", "   ", "\t", "\n", "-", " - ", "AD\0", "AD\nx", "AD\rx", "AD\u{7f}", "AD\u{2028}x", "AD\u{85}x", "AD\u{1b}"] {
            #expect(throws: KeychainError.self) { try KeychainStore.saveCommand("ejemplo", for: .named(name)) }
        }
    }

    @Test func laUltimaArrobaSeparaUsuarioYEquipoInclusoConUpn() throws {
        for account in ["tu.usuario@core-01", "tu.usuario@dominio.example@core-01", "opérador@núcleo-01",
                        "DOMINIO\\tu.usuario@198.51.100.10", "tu.usuario@2001:db8::1"] {
            let ref = CredentialRef(service: .device, account: account)
            try CredentialValidation.validateReference(ref)
            let command = try KeychainStore.saveCommand("ejemplo", for: ref)
            #expect(command.contains("\"-a\" " + KeychainStore.quoted(account)))
        }
        for account in ["core-01", "@core-01", "tu.usuario@", " tu.usuario@core-01", "tu.usuario @core-01",
                        "tu.usuario@core 01", "tu.usuario@core-01 ", "tu.usuario@\tcore-01", "tu.usuario\0@core-01"] {
            let ref = CredentialRef(service: .device, account: account)
            #expect(throws: KeychainError.self) { try KeychainStore.saveCommand("ejemplo", for: ref) }
        }
    }

    @Test func elSecretoConservaEspaciosSimbolosYUnicode() throws {
        for password in ["  ejemplo  ", " ", #"Ab$1!"q\c ' €ñ😀"#, "\tclave\t", "á漢字"] {
            let command = try KeychainStore.saveCommand(password, for: .named("AD"))
            #expect(command.hasSuffix("\"-w\" " + KeychainStore.quoted(password)))
        }
    }

    @Test func rechazaSecretoVacioMultilineaYNulo() {
        for password in ["", "\n", "ejemplo\r", "uno\r\ndos", "\u{2028}", "\u{2029}", "uno\0dos"] {
            #expect(throws: KeychainError.self) { try KeychainStore.saveCommand(password, for: .named("AD")) }
        }
    }
}
