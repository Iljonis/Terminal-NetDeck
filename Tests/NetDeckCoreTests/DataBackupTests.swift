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

    /// Antes de cada guardado, las sesiones de antes van a copias/ssh_config.bak (fuera de ~/.config/netdeck): si luego
    /// se borra la carpeta, se recuperan de ahí aunque haya una copia de versión más vieja; un archivo vacío no la pisa.
    @Test func copiaAntesDeGuardar() throws {
        let c = try Casa()
        defer { c.remove() }
        let b = c.backup
        let vieja = try #require(b.snapshot(reason: "version-0.9.0"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)],
                                              ofItemAtPath: vieja.appendingPathComponent("ssh_config").path)
        let antes = try #require(try SafeFile.read(c.sessions))
        #expect(b.backupSessionsBeforeSave())
        #expect(try SafeFile.read(b.sessionsBak) == antes)
        #expect(perms(b.sessionsBak) == 0o600)
        var f = SessionFile(text: antes)
        var nueva = EditableSession(name: "core-02")
        nueva.host = "192.0.2.12"
        f.sessions.append(nueva)
        #expect(f.save(to: c.sessions, validate: false) == nil)

        // (vaciarlo a propósito no pisa la copia buena)
        try SafeFile.write("", to: c.sessions)
        #expect(b.backupSessionsBeforeSave())
        #expect(try SafeFile.read(b.sessionsBak) == antes)

        try FileManager.default.removeItem(at: c.netdeck)
        #expect(b.sessionCandidates.first?.lastPathComponent == "ssh_config.bak")
        let r = try #require(b.recoverSessionsIfMissing())
        #expect(r.source.lastPathComponent == "ssh_config.bak")
        #expect(r.count == 3)
        #expect(b.snapshots.count == 1)                           // (no es una copia más: no echa a ninguna)
    }

    /// Una copia de versión más nueva que la .bak va antes que ella.
    @Test func laBakMasViejaVaDetras() throws {
        let c = try Casa()
        defer { c.remove() }
        let b = c.backup
        #expect(b.backupSessionsBeforeSave())
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: b.sessionsBak.path)
        let nueva = try #require(b.snapshot(reason: "version-0.9.1"))
        #expect(b.sessionCandidates.map { $0.resolvingSymlinksInPath().path }
                == [nueva.appendingPathComponent("ssh_config"), b.sessionsBak].map { $0.resolvingSymlinksInPath().path })
    }

    /// El archivo está pero ~/.ssh/config ya no lo incluye (o el Include está comentado): la lista saldría vacía. Se
    /// vuelve a incluir sin tocar las sesiones, con copia del ~/.ssh/config de antes; si ya está, no se toca.
    @Test func vuelveAPonerElInclude() throws {
        let c = try Casa()
        defer { c.remove() }
        let b = c.backup
        let antes = try #require(try SafeFile.read(c.sessions))
        #expect(try !b.restoreIncludeIfMissing(sshConfig: c.sshConfig))   // (ya lo incluye)

        let propio = "# Include ~/.config/netdeck/ssh_config\nHost *\n    ServerAliveInterval 30\n"
        try SafeFile.write(propio, to: c.sshConfig)
        #expect(try b.restoreIncludeIfMissing(sshConfig: c.sshConfig))
        let ahora = try #require(try SafeFile.read(c.sshConfig))
        #expect(SessionFile.hasInclude(ahora))
        #expect(ahora.hasSuffix(propio))                             // (lo tuyo, tal cual, debajo)
        #expect(perms(c.sshConfig) == 0o600)
        let copias = try FileManager.default.contentsOfDirectory(atPath: c.sshConfig.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("config.antes-netdeck-") }
        #expect(copias.count == 1)
        #expect(try SafeFile.read(c.sessions) == antes)
        #expect(try !b.restoreIncludeIfMissing(sshConfig: c.sshConfig))   // (una sola vez)

        // (sin sesiones no se añade nada: quien sólo usa su ~/.ssh/config no lo necesita)
        let sin = try Casa(withSessions: false)
        defer { sin.remove() }
        try SafeFile.write("Host *\n", to: sin.sshConfig)
        #expect(try !sin.backup.restoreIncludeIfMissing(sshConfig: sin.sshConfig))
        #expect(try SafeFile.read(sin.sshConfig) == "Host *\n")
    }

    /// Si falta el ssh_config (el de siempre o el elegido en Ajustes), se crea con el Include: las sesiones siguen ahí y
    /// sin él la lista saldría vacía. Las sesiones, intactas.
    @Test func sinSshConfigSeReconstruye() throws {
        let c = try Casa()
        defer { c.remove() }
        let antes = try #require(try SafeFile.read(c.sessions))
        try FileManager.default.removeItem(at: c.sshConfig)
        #expect(try c.backup.restoreIncludeIfMissing(sshConfig: c.sshConfig))
        #expect(SessionFile.hasInclude(try #require(try SafeFile.read(c.sshConfig))))
        let elegido = c.home.appendingPathComponent("otra/ssh_config")
        #expect(try c.backup.restoreIncludeIfMissing(sshConfig: elegido))
        #expect(SessionFile.hasInclude(try #require(try SafeFile.read(elegido))))
        #expect(try SafeFile.read(c.sessions) == antes)
    }

    /// Un archivo que no se puede leer no es un archivo vacío: error, y no se toca nada.
    @Test func ilegibleEsError() throws {
        let c = try Casa()
        defer { c.remove() }
        try SafeFile.write("Host *\n", to: c.sshConfig)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: c.sshConfig.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: c.sshConfig.path) }
        #expect(throws: (any Error).self) { try c.backup.restoreIncludeIfMissing(sshConfig: c.sshConfig) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: c.sshConfig.path)
        #expect(try SafeFile.read(c.sshConfig) == "Host *\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: c.sessions.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: c.sessions.path) }
        #expect(throws: (any Error).self) { try c.backup.restoreIncludeIfMissing(sshConfig: c.sshConfig) }
    }

    /// Antes de cambiar la app la copia es obligatoria: un archivo que no se puede leer es un error (y quien llama no
    /// cambia la app), sin datos no hay nada que copiar, y con todo legible la copia lleva todos.
    @Test func copiaObligatoriaAntesDeInstalar() throws {
        let c = try Casa()
        defer { c.remove() }
        let dir = try #require(try c.backup.snapshotBeforeInstall(reason: "instalar-0.9.2"))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("ssh_config").path))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: c.sessions.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: c.sessions.path) }
        #expect(throws: BackupError.self) { try c.backup.snapshotBeforeInstall(reason: "actualizar-0.9.2") }
        _ = c.backup.snapshot(reason: "version-0.9.2")                              // (la normal no lanza: se salta el ilegible)
        let vacia = try Casa(withSessions: false)
        defer { vacia.remove() }
        for item in vacia.backup.items { try? FileManager.default.removeItem(at: item.url) }
        #expect(try vacia.backup.snapshotBeforeInstall(reason: "instalar") == nil)
    }

    @Test func detectaElInclude() {
        #expect(SessionFile.hasInclude("Include ~/.config/netdeck/ssh_config\n"))
        #expect(SessionFile.hasInclude("  include \(AppPaths.home.path)/.config/netdeck/ssh_config\n"))
        #expect(!SessionFile.hasInclude("# Include ~/.config/netdeck/ssh_config\n"))
        #expect(!SessionFile.hasInclude("Host core-01\n    HostName 192.0.2.11\n"))
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
