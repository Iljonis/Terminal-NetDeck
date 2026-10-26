import Foundation
import Testing
@testable import NetDeckCore

@Suite struct LedgerProcesosTests {
    @Test func unaAutenticacionVivaNoCaducaConElPlazoDeLaInterfaz() {
        let clock = Clock(), storage = MemoryLedgerStorage(), ref = CredentialRef.named("AD")
        let first = CredentialLedger(storage: storage, now: { clock.now }, processID: 111, processAlive: { _ in true })
        let second = CredentialLedger(storage: storage, now: { clock.now }, processID: 222, processAlive: { _ in true })
        #expect(first.beginProbe(ref) == .go)
        for delay in [8.1, 90.0, 119.0] {                    // (hasta el tope de `reservationLimit`)
            clock.now = Date(timeIntervalSince1970: delay)
            #expect(second.beginProbe(ref) == .wait)
        }
        first.confirm(ref)
        #expect(second.beginProbe(ref) == .go)
    }

    /// Un login anidado cuyo final no se reconoce (un «# @prompt» propio) no deja la contraseña pendiente horas en las
    /// demás pestañas mientras la app sigue abierta; su resultado tardío tampoco pisa la reserva siguiente.
    @Test func unaReservaPropiaCaducaAlTopeAunqueSuPropietarioSigaVivo() throws {
        let clock = Clock(), storage = MemoryLedgerStorage(), ref = CredentialRef.named("AD")
        let first = CredentialLedger(storage: storage, now: { clock.now }, processID: 111, processAlive: { _ in true })
        let second = CredentialLedger(storage: storage, now: { clock.now }, processID: 222, processAlive: { _ in true })
        let old = try #require(first.reserveProbe(ref).token)
        clock.now = Date(timeIntervalSince1970: 119)
        #expect(second.beginProbe(ref) == .wait)
        clock.now = Date(timeIntervalSince1970: 121)
        let fresh = try #require(second.reserveProbe(ref).token)
        first.markFailed(ref, reservation: old)
        first.confirm(ref, reservation: old)
        if case .probing(_, let owner, let token) = second.state(of: ref) { #expect(owner == 222 && token == fresh) }
        else { Issue.record("la respuesta de la reserva caducada pisó la nueva") }
    }

    @Test func unProcesoMuertoLiberaLaReservaSinEsperarUnReloj() {
        let storage = MemoryLedgerStorage(), ref = CredentialRef.named("AD")
        let first = CredentialLedger(storage: storage, processID: 111, processAlive: { _ in true })
        #expect(first.beginProbe(ref) == .go)
        let second = CredentialLedger(storage: storage, processID: 222, processAlive: { $0 == 222 })
        #expect(second.beginProbe(ref) == .go)
        #expect(second.beginProbe(ref) == .wait)
        second.markFailed(ref)
        #expect(first.isBlocked(ref))
    }

    /// Las marcas «probando» de la versión anterior no llevan PID (owner 0): caducan a los `probeWindow` s, como
    /// entonces. Sin plazo, una que quedara al actualizar dejaba «otra autenticación sigue pendiente» para siempre.
    @Test func unaMarcaAntiguaSinPropietarioCaducaComoAntes() {
        let clock = Clock(), storage = MemoryLedgerStorage(), ref = CredentialRef.named("AD")
        storage.write(ref, .probing(since: Date(timeIntervalSince1970: 0), owner: 0))
        let ledger = CredentialLedger(storage: storage, now: { clock.now }, processAlive: { _ in false })
        clock.now = Date(timeIntervalSince1970: 7)
        #expect(ledger.beginProbe(ref) == .wait)              // (aún podría estar entrando)
        clock.now = Date(timeIntervalSince1970: 8.5)
        #expect(ledger.beginProbe(ref) == .go)
    }

    /// Lo mismo leída del disco tal como la escribía la versión anterior («probando\t<hora>», sin PID ni reserva).
    @Test func laMarcaDelFormatoAnteriorSeLeeSinPropietario() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ref = CredentialRef.named("AD"), storage = DirectoryLedgerStorage(dir)
        storage.write(ref, .probing(since: Date(timeIntervalSince1970: 0), owner: 0))
        let file = try #require(FileManager.default.contentsOfDirectory(atPath: dir.path).first { !$0.hasPrefix(".") })
        try "probando\t0.0".write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        #expect(storage.read(ref) == .probing(since: Date(timeIntervalSince1970: 0), owner: 0, reservation: nil))
        #expect(CredentialLedger(storage: storage, now: { Date(timeIntervalSince1970: 9) }).beginProbe(ref) == .go)
    }

    @Test func unaCancelacionAntiguaNoLiberaLaReservaNueva() throws {
        let ledger = CredentialLedger(), ref = CredentialRef.named("AD")
        let old = try #require(ledger.reserveProbe(ref).token)
        ledger.reset(ref)                                     // (se cambia la contraseña / elección explícita)
        let fresh = try #require(ledger.reserveProbe(ref).token)
        ledger.release(ref, reservation: old)
        #expect(ledger.beginProbe(ref) == .wait)
        ledger.keepProbing(ref)
        ledger.release(ref, reservation: fresh)
        #expect(ledger.state(of: ref) == nil)
    }

    @Test func unaRespuestaAntiguaNoResuelveLaReservaNueva() throws {
        for failed in [false, true] {
            let ledger = CredentialLedger(), ref = CredentialRef.named("AD")
            let old = try #require(ledger.reserveProbe(ref).token)
            ledger.reset(ref)
            let fresh = try #require(ledger.reserveProbe(ref).token)
            if failed { ledger.markFailed(ref, reservation: old) }
            else { ledger.confirm(ref, reservation: old) }
            #expect(ledger.beginProbe(ref) == .wait)
            ledger.confirm(ref, reservation: fresh)
            #expect(ledger.beginProbe(ref) == .go)
        }
    }

    @Test func unLoginInicialNoResuelveLaReservaDeUnEquipo() throws {
        let ledger = CredentialLedger(), ref = CredentialRef.named("AD")
        let token = try #require(ledger.reserveProbe(ref).token)
        ledger.confirmDirect(ref)
        #expect(ledger.beginProbe(ref) == .wait)
        ledger.markFailed(ref, reservation: token)
        ledger.confirmDirect(ref)
        #expect(ledger.isBlocked(ref))
    }

    /// La hora del último «restablecer» se comparte en disco con el askpass (otro proceso) y sobrevive a una reserva
    /// nueva: el rechazo tardío de un intento de antes no bloquea la recién guardada; el de uno de después, sí.
    @Test func unRechazoDeAntesDeRestablecerNoBloqueaLaNueva() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ref = CredentialRef.named("AD")
        let app = CredentialLedger(storage: DirectoryLedgerStorage(dir), now: { Date(timeIntervalSince1970: 1000) })
        let askpass = CredentialLedger(storage: DirectoryLedgerStorage(dir), now: { Date(timeIntervalSince1970: 1010) })
        app.markFailed(ref)
        app.reset(ref)                                        // (guardada otra vez en Ajustes o en otra pestaña)
        #expect(app.beginProbe(ref) == .go)
        #expect(!askpass.markFailed(ref, attemptedAt: Date(timeIntervalSince1970: 995)))
        #expect(askpass.beginProbe(ref) == .wait && !askpass.isBlocked(ref))
        #expect(askpass.markFailed(ref, attemptedAt: Date(timeIntervalSince1970: 1005)))
        #expect(app.isBlocked(ref))
        // (al lado de la marca, sólo la hora: ningún secreto ni nombre)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".restablecida") }
        #expect(files.count == 1)
        let text = try String(contentsOf: dir.appendingPathComponent(files[0]), encoding: .utf8)
        #expect(TimeInterval(text) == 1000)
    }

    @Test func elPropietarioSeComparteEntreProcesosEnDisco() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ref = CredentialRef.named("AD")
        let first = CredentialLedger(storage: DirectoryLedgerStorage(dir), processID: 111, processAlive: { _ in true })
        let second = CredentialLedger(storage: DirectoryLedgerStorage(dir), processID: 222, processAlive: { _ in true })
        #expect(first.beginProbe(ref) == .go)
        #expect(second.beginProbe(ref) == .wait)
        if case .probing(_, let owner, _) = second.state(of: ref) { #expect(owner == 111) }
        else { Issue.record("No se conservó el propietario de la reserva") }
        first.release(ref)
        #expect(second.beginProbe(ref) == .go)
    }
}
