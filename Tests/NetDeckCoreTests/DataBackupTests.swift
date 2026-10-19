import Foundation
import Testing
@testable import NetDeckCore

private let sesiones = """
    # @grupo Saltos

    Host bastion
        HostName 192.0.2.1
        User tu.usuario

    # @grupo Core
    # @clave-grupo AD

    Host core-01
        HostName 192.0.2.11
        ProxyJump bastion

    Host olt-01
        # @telnet
        HostName 192.0.2.21
    """

/// Una carpeta personal de prueba con lo que deja una versión anterior: ~/.config/netdeck/ssh_config, ~/.ssh/config
/// con su Include y botones.
private struct Casa {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    var netdeck: URL { home.appendingPathComponent(".config/netdeck", isDirectory: true) }
    var sessions: URL { netdeck.appendingPathComponent("ssh_config") }
    var sshConfig: URL { home.appendingPathComponent(".ssh/config") }
    var support: URL { home.appendingPathComponent("Library/Application Support/Terminal NetDeck", isDirectory: true) }
    var documents: URL { home.appendingPathComponent("Documents", isDirectory: true) }

    var backup: DataBackup {
        DataBackup(items: [("ssh_config", sessions), ("ssh-config", sshConfig),
                           ("botones.txt", netdeck.appendingPathComponent("botones.txt"))],
                   directory: support.appendingPathComponent("copias", isDirectory: true),
                   sessions: sessions, foreignCopies: [documents])
    }

    init(withSessions: Bool = true) throws {
        let fm = FileManager.default
        for d in [netdeck, sshConfig.deletingLastPathComponent(), support, documents] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        if withSessions { try SafeFile.write(sesiones, to: sessions) }
        try SafeFile.write("Include ~/.config/netdeck/ssh_config\n", to: sshConfig)
        try SafeFile.write("[Cisco]\nshow version\n", to: netdeck.appendingPathComponent("botones.txt"))
    }

    func remove() { try? FileManager.default.removeItem(at: home) }
}

private func perms(_ u: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as? Int) ?? -1 }

@Suite struct DataBackupTests {
    /// Actualizar desde una versión anterior: la copia de antes de cambiar la app guarda las sesiones tal cual, la
    /// actualización no las toca y, si algo borra después la carpeta (el desinstalador de NetDeck), al arrancar vuelven
    /// todas, idénticas.
    @Test func actualizarConservaLasSesiones() throws {
        let c = try Casa()
        defer { c.remove() }
        let antes = try #require(try SafeFile.read(c.sessions))
        let copia = try #require(c.backup.snapshot(reason: "actualizar-0.9.1"))
        #expect(copia.lastPathComponent.hasSuffix("-actualizar-0.9.1"))
        #expect(try SafeFile.read(copia.appendingPathComponent("ssh_config")) == antes)
        #expect(try SafeFile.read(copia.appendingPathComponent("ssh-config")) == "Include ~/.config/netdeck/ssh_config\n")
        #expect(perms(copia) == 0o700)
        #expect(perms(copia.appendingPathComponent("ssh_config")) == 0o600)

        // (la nueva arranca con el archivo en su sitio: no se recupera nada ni se toca)
        #expect(c.backup.recoverSessionsIfMissing() == nil)
        #expect(try SafeFile.read(c.sessions) == antes)

        // (rm -rf ~/.config/netdeck, como el desinstalador de NetDeck)
        try FileManager.default.removeItem(at: c.netdeck)
        let r = try #require(c.backup.recoverSessionsIfMissing())
        #expect(r.count == 3)
        #expect(r.source.resolvingSymlinksInPath().path == copia.appendingPathComponent("ssh_config").resolvingSymlinksInPath().path)
        let ahora = try #require(try SafeFile.read(c.sessions))
        #expect(SessionFile(text: ahora).render() == SessionFile(text: antes).render())
        #expect(SessionFile(text: ahora).sessions.map(\.host) == ["192.0.2.1", "192.0.2.11", "192.0.2.21"])
        #expect(SessionFile(text: ahora).sessions.map(\.name) == ["bastion", "core-01", "olt-01"])
        #expect(SessionFile(text: ahora).groupCredentials["Core"] == "AD")
        #expect(perms(c.sessions) == 0o600)
    }

    /// Sin copias de la app, vale la que deja el desinstalador de NetDeck en ~/Documents/netdeck-copia-* (la más nueva),
    /// pero pasada por el filtro de importar: nada de ProxyCommand ni bloques «Host *» para todo ssh del Mac.
    @Test func recuperaDeLaCopiaDeNetDeckFiltrada() throws {
        let c = try Casa(withSessions: false)
        defer { c.remove() }
        for (nombre, texto) in [("netdeck-copia-20261001-120000", "Host vieja\n    HostName 192.0.2.99\n"),
                                ("netdeck-copia-20261018-120000", sesiones + "\n    ProxyCommand nc %h %p\n\nHost *\n    ProxyCommand nc %h %p\n")] {
            let d = c.documents.appendingPathComponent(nombre, isDirectory: true)
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try SafeFile.write(texto, to: d.appendingPathComponent("ssh_config"))
        }
        let r = try #require(c.backup.recoverSessionsIfMissing())
        #expect(r.count == 3)
        #expect(r.source.path.contains("20261018"))
        let ahora = try #require(try SafeFile.read(c.sessions))
        #expect(SessionFile(text: ahora).sessions.map(\.name) == ["bastion", "core-01", "olt-01"])
        #expect(!ahora.contains("ProxyCommand"))
        #expect(!ahora.components(separatedBy: .newlines).contains("Host *"))
    }

    /// Con copias propias no se mira ~/Documents; y una copia que ssh no entiende se salta.
    @Test func lasPropiasPrimeroYValidadas() throws {
        let c = try Casa()
        defer { c.remove() }
        let suya = c.documents.appendingPathComponent("netdeck-copia-29991231-235959", isDirectory: true)
        try FileManager.default.createDirectory(at: suya, withIntermediateDirectories: true)
        try SafeFile.write("Host ajena\n    HostName 192.0.2.50\n", to: suya.appendingPathComponent("ssh_config"))
        c.backup.snapshot(reason: "buena", now: Date(timeIntervalSince1970: 1_800_000_000))
        try SafeFile.write("Host rota\n    OpcionQueNoExiste si\n", to: c.sessions)
        c.backup.snapshot(reason: "rota", now: Date(timeIntervalSince1970: 1_800_000_060))
        try FileManager.default.removeItem(at: c.sessions)
        let r = try #require(c.backup.recoverSessionsIfMissing())
        #expect(r.source.path.contains("-buena"))
        #expect(r.count == 3)
    }

    /// Si existe (aunque vacío: las has borrado tú) no se toca; y una copia sin sesiones no vale para recuperar.
    @Test func noPisaNiRecuperaVacios() throws {
        let c = try Casa()
        defer { c.remove() }
        c.backup.snapshot(reason: "a")
        try SafeFile.write("", to: c.sessions)
        #expect(c.backup.recoverSessionsIfMissing() == nil)
        #expect(try SafeFile.read(c.sessions) == "")

        try FileManager.default.removeItem(at: c.sessions)
        try FileManager.default.removeItem(at: c.backup.directory)
        try SafeFile.write("Host *\n    ServerAliveInterval 30\n", to: c.sessions.appendingPathExtension("anterior"))
        #expect(c.backup.recoverSessionsIfMissing() == nil)
        #expect(!FileManager.default.fileExists(atPath: c.sessions.path))
    }

    /// La más reciente gana; sólo quedan las `keep` últimas copias; sin nada que copiar, ninguna.
    @Test func laMasRecienteYLimite() throws {
        let c = try Casa()
        defer { c.remove() }
        var b = c.backup
        b.keep = 3
        for i in 0..<5 { b.snapshot(reason: "v\(i)", now: Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 60)) }
        #expect(b.snapshots.count == 3)
        #expect(b.snapshots.first?.lastPathComponent.hasSuffix("-v4") == true)

        let nueva = sesiones + "\n\nHost core-02\n    HostName 192.0.2.12\n"
        try SafeFile.write(nueva, to: c.sessions)
        b.snapshot(reason: "v5", now: Date(timeIntervalSince1970: 1_800_001_000))
        try FileManager.default.removeItem(at: c.sessions)
        #expect(b.recoverSessionsIfMissing()?.count == 4)

        let vacia = try Casa(withSessions: false)
        defer { vacia.remove() }
        var v = vacia.backup
        v.items = [("ssh_config", vacia.sessions)]
        #expect(v.snapshot(reason: "nada") == nil)
        #expect(v.snapshots.isEmpty)
    }

    /// Dos copias en el mismo segundo no se pisan.
    @Test func mismoSegundo() throws {
        let c = try Casa()
        defer { c.remove() }
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try #require(c.backup.snapshot(reason: "x", now: t))
        let b = try #require(c.backup.snapshot(reason: "x", now: t))
        #expect(a != b)
        #expect(c.backup.snapshots.count == 2)
    }
}
