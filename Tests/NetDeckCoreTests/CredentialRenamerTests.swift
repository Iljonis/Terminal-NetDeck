import Foundation
import Testing
@testable import NetDeckCore

@Suite struct CredentialRenamerTests {
    private struct Files {
        let root: URL
        let paths: CredentialRenamer.Paths
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("renombrar-credencial-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            paths = .init(sessions: root.appendingPathComponent("ssh_config"), buttons: root.appendingPathComponent("botones.txt"),
                          lists: root.appendingPathComponent("listas.json"))
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func cambiaSoloReferenciasYConservaComentariosFormatoYCamposDesconocidos() throws {
        let files = try Files()
        defer { files.remove() }
        let source = CredentialRef.named("AD"), destination = CredentialRef.named("Red España β")
        let store = RenameStore([source: "secreto de ejemplo"])
        let sessions = "# AD: comentario\r\n  # @clave-grupo AD \r\nHost core-01\r\n  # @clave AD  \r\n  # @clave AD extra\r\n  # @desc AD\r\n  User tu.usuario\r\n"
        let buttons = "# AD no se cambia\nCore :: pass :: AD ::  AD  \nCore :: login :: Entrar :: tu.usuario / AD \nCore :: run :: Mostrar :: echo AD\nCore :: type :: Escribir :: AD\ntexto desconocido AD\n"
        let lists = "{\"extra\":{\"credential\":\"AD\"},\"lists\":[{\"id\":\"00000000-0000-4000-8000-000000000001\",\"name\":\"Core\",\"jump\":\"bastion\",\"user\":\"tu.usuario\",\"credential\" : \"AD\",\"devices\":[\"192.0.2.1\"],\"extra\":{\"credential\":\"AD\"}}]}\n"
        try SafeFile.write(sessions, to: files.paths.sessions)
        try SafeFile.write(buttons, to: files.paths.buttons)
        try SafeFile.write(lists, to: files.paths.lists)
        let refs = try CredentialRenamer.rename(from: source, to: destination, store: store, paths: files.paths)
        #expect(refs == 5)
        #expect(try store.password(for: source) == "secreto de ejemplo") // (el llamador decide cuándo borrar la anterior)
        #expect(try store.password(for: destination) == "secreto de ejemplo")
        #expect(try SafeFile.read(files.paths.sessions) == sessions.replacingOccurrences(of: "# @clave-grupo AD ", with: "# @clave-grupo Red España β ")
            .replacingOccurrences(of: "# @clave AD  ", with: "# @clave Red España β  "))
        #expect(try SafeFile.read(files.paths.buttons) == buttons.replacingOccurrences(of: "::  AD  ", with: "::  Red España β  ")
            .replacingOccurrences(of: "tu.usuario / AD ", with: "tu.usuario / Red España β "))
        #expect(try SafeFile.read(files.paths.lists) == lists.replacingOccurrences(of: "\"credential\" : \"AD\"", with: "\"credential\" : \"Red España β\""))
        #expect(try SafeFile.read(files.paths.sessions.appendingPathExtension("anterior")) == sessions)
        let mode = try FileManager.default.attributesOfItem(atPath: files.paths.sessions.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test(arguments: [false, true]) func nombresQueEmpiezanPorMarcasUnicodeNoRompenElJson(_ bom: Bool) throws {
        let files = try Files()
        defer { files.remove() }
        let source = CredentialRef.named("\u{0301}AD"), destination = CredentialRef.named("\u{FE0F}Nueva")
        let store = RenameStore([source: "ejemplo"])
        try SafeFile.write("# @grupo Core\n# @clave-grupo \(source.account)\nHost core-01\n    # @clave \(source.account)\n", to: files.paths.sessions)
        try ListLibrary(lists: [.init(name: "\u{0301}Core", credential: source.account)]).save(to: files.paths.lists)
        if bom {
            let text = try #require(try SafeFile.read(files.paths.lists))
            try SafeFile.write("\u{FEFF}" + text, to: files.paths.lists)
        }
        #expect(try CredentialRenamer.rename(from: source, to: destination, store: store, paths: files.paths) == 3)
        let sessions = try SessionFile(contentsOf: files.paths.sessions)
        #expect(sessions.sessions.first?.credential == destination.account)
        #expect(sessions.groupCredentials["Core"] == destination.account)
        let library = try ListLibrary(contentsOf: files.paths.lists)
        #expect(library.lists.first?.credential == destination.account)
        #expect(library.lists.first?.name == "\u{0301}Core")
    }

    @Test func unaCuentaDeEquipoSoloCambiaSuReferenciaEnListas() throws {
        let files = try Files()
        defer { files.remove() }
        let source = CredentialRef.device("tu.usuario", "192.0.2.1"), destination = CredentialRef.device("tu.usuario", "192.0.2.2")
        let store = RenameStore([source: "anterior"])
        let session = "Host core-01\n # @clave tu.usuario@192.0.2.1\n"
        let button = "Core :: pass :: Entrar :: tu.usuario@192.0.2.1\n"
        try SafeFile.write(session, to: files.paths.sessions)
        try SafeFile.write(button, to: files.paths.buttons)
        try ListLibrary(lists: [.init(name: "Core", credential: source.account)]).save(to: files.paths.lists)
        #expect(try CredentialRenamer.rename(from: source, to: destination, password: "nueva", store: store, paths: files.paths) == 1)
        #expect(try ListLibrary(contentsOf: files.paths.lists).lists.first?.credential == destination.account)
        #expect(try SafeFile.read(files.paths.sessions) == session)
        #expect(try SafeFile.read(files.paths.buttons) == button)
        #expect(try store.password(for: source) == "anterior")
        #expect(try store.password(for: destination) == "nueva")
    }

    @Test func noCreaNadaSiUnArchivoExistenteEsIlegibleORoto() throws {
        for malformedJSON in [false, true] {
            let files = try Files()
            defer { files.remove() }
            let source = CredentialRef.named("AD"), destination = CredentialRef.named("Nueva")
            let store = RenameStore([source: "ejemplo"])
            if malformedJSON { try SafeFile.write("{archivo roto", to: files.paths.lists) }
            else { try Data([0xFF, 0xFE]).write(to: files.paths.sessions) }
            #expect(throws: (any Error).self) {
                try CredentialRenamer.rename(from: source, to: destination, store: store, paths: files.paths)
            }
            #expect(!store.contains(destination) && store.contains(source))
        }
    }

    @Test func rechazaColisionesAusenciaCambioDeTipoYListasAmbiguas() throws {
        let files = try Files()
        defer { files.remove() }
        let source = CredentialRef.named("AD"), destination = CredentialRef.named("Nueva")
        let store = RenameStore([source: "original", destination: "no sustituir"])
        #expect(throws: (any Error).self) { try CredentialRenamer.rename(from: source, to: destination, store: store, paths: files.paths) }
        #expect(try store.password(for: destination) == "no sustituir")
        #expect(throws: (any Error).self) { try CredentialRenamer.rename(from: .named("Ausente"), to: .named("Libre"), store: store, paths: files.paths) }
        #expect(throws: (any Error).self) { try CredentialRenamer.rename(from: source, to: .device("tu.usuario", "192.0.2.1"), store: store, paths: files.paths) }
        let ambiguous = CredentialRef.named("tu.usuario@192.0.2.1"), device = CredentialRef.device("tu.usuario", "192.0.2.1")
        let mixed = RenameStore([ambiguous: "una", device: "otra"])
        try ListLibrary(lists: [.init(name: "Core", credential: device.account)]).save(to: files.paths.lists)
        #expect(throws: (any Error).self) { try CredentialRenamer.rename(from: device, to: .device("tu.usuario", "192.0.2.2"), store: mixed, paths: files.paths) }
        #expect(!mixed.contains(.device("tu.usuario", "192.0.2.2")))
    }

    @Test func renombraBotonesLoginConBarrasEnElDestinoYEnElOrigen() throws {
        let files = try Files()
        defer { files.remove() }
        let source = CredentialRef.named("AD"), destination = CredentialRef.named("AD / otra"), next = CredentialRef.named("Red / España")
        let store = RenameStore([source: "ejemplo"])
        let original = "Core :: login :: Entrar :: tu.usuario /  AD  \n"
        try SafeFile.write(original, to: files.paths.buttons)
        #expect(try CredentialRenamer.rename(from: source, to: destination, store: store, paths: files.paths) == 1)
        #expect(try SafeFile.read(files.paths.buttons) == original.replacingOccurrences(of: "  AD  ", with: "  AD / otra  "))
        #expect(try CredentialRenamer.rename(from: destination, to: next, store: store, paths: files.paths) == 1)
        #expect(try SafeFile.read(files.paths.buttons) == original.replacingOccurrences(of: "  AD  ", with: "  Red / España  "))
        #expect(store.contains(source) && store.contains(destination) && store.contains(next))
    }

    @Test func unFalloDeEscrituraRestauraLoTocadoYConservaAmbasEntradas() throws {
        let files = try Files()
        defer { files.remove() }
        let source = CredentialRef.named("AD"), destination = CredentialRef.named("Nueva")
        let store = RenameStore([source: "ejemplo"])
        let sessions = "Host core-01\n # @clave AD\n", buttons = "Core :: pass :: Entrar :: AD\n"
        try SafeFile.write(sessions, to: files.paths.sessions)
        try SafeFile.write(buttons, to: files.paths.buttons)
        var writes = 0
        #expect(throws: (any Error).self) {
            try CredentialRenamer.rename(from: source, to: destination, store: store, paths: files.paths, write: { text, url in
                writes += 1
                try SafeFile.write(text, to: url)
                if writes == 2 { throw RenameStore.Failure.simulated }
            })
        }
        #expect(try SafeFile.read(files.paths.sessions) == sessions)
        #expect(try SafeFile.read(files.paths.buttons) == buttons)
        #expect(store.contains(source) && store.contains(destination))
    }

    @Test func noPisaUnaEdicionSimultaneaAlEscribirNiAlDeshacer() throws {
        let files = try Files()
        defer { files.remove() }
        let source = CredentialRef.named("AD"), destination = CredentialRef.named("Nueva")
        let store = RenameStore([source: "ejemplo"])
        let sessions = "Host core-01\n # @clave AD\n", buttons = "Core :: pass :: Entrar :: AD\n"
        try SafeFile.write(sessions, to: files.paths.sessions)
        try SafeFile.write(buttons, to: files.paths.buttons)
        var writes = 0
        #expect(throws: (any Error).self) {
            try CredentialRenamer.rename(from: source, to: destination, store: store, paths: files.paths, write: { text, url in
                writes += 1
                try SafeFile.write(text, to: url)
                if writes == 1 {
                    try SafeFile.write("edición externa de sesiones", to: files.paths.sessions)
                    try SafeFile.write("edición externa de botones", to: files.paths.buttons)
                }
            })
        }
        #expect(try SafeFile.read(files.paths.sessions) == "edición externa de sesiones")
        #expect(try SafeFile.read(files.paths.buttons) == "edición externa de botones")
        #expect(store.contains(source) && store.contains(destination))
    }

    @Test func callbackDeBloqueoSeAplicaAntesDePublicarReferencias() throws {
        let files = try Files()
        defer { files.remove() }
        let source = CredentialRef.named("AD"), destination = CredentialRef.named("Nueva")
        let store = RenameStore([source: "ejemplo"]), ledger = CredentialLedger()
        try SafeFile.write("Host core-01\n # @clave AD\n", to: files.paths.sessions)
        let changed = try CredentialRenamer.rename(from: source, to: destination, store: store, paths: files.paths,
                                             beforeUpdatingReferences: { ledger.markFailed(destination) }, write: { text, url in
            #expect(ledger.isBlocked(destination))
            try SafeFile.write(text, to: url)
        })
        #expect(changed == 1)
        #expect(ledger.isBlocked(destination))
    }
}

private final class RenameStore: CredentialStore, @unchecked Sendable {
    enum Failure: Error { case simulated, exists }
    private let items: MemoryCredentialStore
    init(_ items: [CredentialRef: String]) { self.items = MemoryCredentialStore(items) }
    func password(for ref: CredentialRef) throws -> String? { try items.password(for: ref) }
    func contains(_ ref: CredentialRef) -> Bool { items.contains(ref) }
    func save(_ password: String, for ref: CredentialRef) throws { try items.save(password, for: ref) }
    func create(_ password: String, for ref: CredentialRef) throws {
        guard !items.contains(ref) else { throw Failure.exists }
        try items.save(password, for: ref)
    }
    func delete(_ ref: CredentialRef) throws { try items.delete(ref) }
    func accounts(in service: CredentialRef.Service) throws -> [String] { try items.accounts(in: service) }
}
