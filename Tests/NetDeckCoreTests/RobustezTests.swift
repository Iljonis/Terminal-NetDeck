import Darwin
import Foundation
import Testing
@testable import NetDeckCore

/// Guardar sesiones (copia obligatoria, Include en el ssh_config elegido, «ssh -G» fuera del hilo principal), Include
/// estricto, cambiar la .app sin quedarse sin ninguna y el aviso de clave de equipo cambiada (known_hosts).
@Suite struct RobustezTests {
    private struct Carpeta {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var sessions: URL { raiz.appendingPathComponent("netdeck/ssh_config") }
        var copias: URL { raiz.appendingPathComponent("copias", isDirectory: true) }
        var backup: DataBackup { DataBackup(items: [("ssh_config", sessions)], directory: copias, sessions: sessions) }

        init() throws {
            try FileManager.default.createDirectory(at: sessions.deletingLastPathComponent(), withIntermediateDirectories: true)
            try SafeFile.write("Host core-01\n    HostName 192.0.2.11\n", to: sessions)
        }
        func remove() { try? FileManager.default.removeItem(at: raiz) }
    }

    private func archivo(_ nombre: String, _ equipo: String) -> SessionFile {
        var f = SessionFile()
        var s = EditableSession(name: nombre)
        s.host = equipo
        f.sessions = [s]
        return f
    }

    @Test func knownHostsRechazaFifoAntesDeLeer() throws {
        let dir = AppPaths.ensure(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: dir) }
        let fifo = dir.appendingPathComponent("known_hosts")
        try #require(mkfifo(fifo.path, 0o600) == 0)
        let context = KnownHosts.Context(names: ["core-01"], files: [fifo])
        let mismatch = HostKeyMismatch(host: "core-01", file: fifo.path, line: 1)
        if case .success = KnownHosts.verify(mismatch, against: context) { Issue.record("acepta FIFO como known_hosts") }
    }

    // MARK: 1) ssh_config elegido en Ajustes

    /// Con otro ssh_config (no ~/.ssh/config), el Include va a ése; si no se puede escribir, no se guarda nada.
    @Test func elIncludeVaAlSshConfigElegido() throws {
        let c = try Carpeta()
        defer { c.remove() }
        let propio = c.raiz.appendingPathComponent("otro/ssh_config_trabajo")
        try FileManager.default.createDirectory(at: propio.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SafeFile.write("Host *\n    ServerAliveInterval 30\n", to: propio)
        #expect(archivo("core-02", "192.0.2.12").save(to: c.sessions, including: propio, backup: c.backup, validate: false) == nil)
        let texto = try #require(try SafeFile.read(propio))
        #expect(SessionFile.hasInclude(texto))
        #expect(texto.hasSuffix("Host *\n    ServerAliveInterval 30\n"))
        #expect(FileManager.default.fileExists(atPath: propio.appendingPathExtension("anterior").path))
        #expect(try SafeFile.read(c.sessions)?.contains("core-02") == true)

        // (uno que no se puede leer: ni Include ni sesiones nuevas)
        let roto = c.raiz.appendingPathComponent("otro/roto")
        try Data([0xff, 0xfe, 0x00, 0xc3]).write(to: roto)
        let antes = try SafeFile.read(c.sessions)
        let err = archivo("core-03", "192.0.2.13").save(to: c.sessions, including: roto, backup: c.backup, validate: false)
        #expect(err?.contains("Include") == true)
        #expect(try SafeFile.read(c.sessions) == antes)
        #expect(try Data(contentsOf: roto) == Data([0xff, 0xfe, 0x00, 0xc3]))
    }

    /// Validar antes de tocar nada: unas sesiones que ssh no entiende no cambian ni el ssh_config ni las sesiones.
    @Test func validaAntesDeTocarNada() throws {
        let c = try Carpeta()
        defer { c.remove() }
        let config = c.raiz.appendingPathComponent("config")
        try SafeFile.write("Host *\n    ServerAliveInterval 30\n", to: config)
        var f = archivo("core-02", "192.0.2.12")
        f.sessions[0].extra = ["OpcionQueNoExiste si"]
        let antes = try SafeFile.read(c.sessions)
        #expect(f.save(to: c.sessions, including: config, backup: c.backup) != nil)
        #expect(try SafeFile.read(config) == "Host *\n    ServerAliveInterval 30\n")
        #expect(!FileManager.default.fileExists(atPath: config.appendingPathExtension("anterior").path))
        #expect(try SafeFile.read(c.sessions) == antes)
    }

    /// Si falla el último paso (cambiar el archivo de sesiones), el ssh_config vuelve a como estaba (o se quita si no
    /// existía): se guardan los dos o ninguno.
    @Test func siFallanLasSesionesVuelveElSshConfig() throws {
        let c = try Carpeta()
        defer { c.remove() }
        let config = c.raiz.appendingPathComponent("config")
        try SafeFile.write("Host *\n    ServerAliveInterval 30\n", to: config)
        let antes = try SafeFile.read(c.sessions)
        let falla: (URL, URL, Int) -> String? = { _, _, _ in "disco lleno" }
        let f = archivo("core-02", "192.0.2.12")
        #expect(f.save(to: c.sessions, including: config, backup: c.backup, validate: false, install: falla) == "disco lleno")
        #expect(try SafeFile.read(config) == "Host *\n    ServerAliveInterval 30\n")
        #expect(try SafeFile.read(c.sessions) == antes)
        #expect(!FileManager.default.fileExists(atPath: c.sessions.appendingPathExtension("tmp").path))

        let nuevo = c.raiz.appendingPathComponent("nuevo/config")                     // (no existía: se quita)
        #expect(f.save(to: c.sessions, including: nuevo, backup: c.backup, validate: false, install: falla) == "disco lleno")
        #expect(!FileManager.default.fileExists(atPath: nuevo.path))
    }

    // MARK: 2) copia obligatoria

    /// Si no se puede hacer la copia de las sesiones de ahora, no se guarda nada (y se dice).
    @Test func sinCopiaNoSeGuarda() throws {
        let c = try Carpeta()
        defer { c.remove() }
        // («copias» es un archivo: no se puede crear la carpeta ni escribir la copia dentro)
        try SafeFile.write("no soy una carpeta", to: c.copias)
        #expect(!c.backup.backupSessionsBeforeSave())
        let antes = try SafeFile.read(c.sessions)
        let config = c.raiz.appendingPathComponent("config")
        let err = archivo("core-02", "192.0.2.12").save(to: c.sessions, including: config, backup: c.backup, validate: false)
        #expect(err != nil)
        #expect(try SafeFile.read(c.sessions) == antes)
        #expect(!FileManager.default.fileExists(atPath: config.path))       // (ni siquiera el Include)
    }

    // MARK: 3) Include estricto y con SafeFile

    @Test func includeEstricto() {
        #expect(SessionFile.hasInclude("Include ~/.config/netdeck/ssh_config\n"))
        #expect(SessionFile.hasInclude("INCLUDE=~/.config/netdeck/ssh_config\n"))
        #expect(SessionFile.hasInclude("Include ~/.ssh/otros \"~/.config/netdeck/ssh_config\"\n"))
        #expect(SessionFile.hasInclude("Include ~/.config/netdeck/ssh_config # sesiones\n"))
        #expect(SessionFile.hasInclude("Host core-01\n    User tu.usuario\nHost *\nInclude ~/.config/netdeck/ssh_config\n"))
        #expect(!SessionFile.hasInclude("#Include ~/.config/netdeck/ssh_config\n"))
        #expect(!SessionFile.hasInclude("IncludeX ~/.config/netdeck/ssh_config\n"))
        #expect(!SessionFile.hasInclude("Include ~/.config/netdeck/ssh_config.bak\n"))
        #expect(!SessionFile.hasInclude("Include /otra/.config/netdeck/ssh_config\n"))
        #expect(!SessionFile.hasInclude("Include ~/x/.config/netdeck/ssh_config\n"))
        #expect(!SessionFile.hasInclude("Host core-01\n    # ~/.config/netdeck/ssh_config\n"))
        #expect(!SessionFile.hasInclude("Host core-01\n    Include ~/.config/netdeck/ssh_config\n"))   // (sólo para core-01)
    }

    /// Añadir el Include deja copias (`.anterior`, `.original` y la de fecha), 0600, y lo tuyo debajo tal cual; si el
    /// ~/.ssh/config es un enlace, se cambia el archivo al que apunta y el enlace se queda.
    @Test func ensureIncludeConSafeFile() throws {
        let c = try Carpeta()
        defer { c.remove() }
        let real = c.raiz.appendingPathComponent("dotfiles/ssh_config")
        let enlace = c.raiz.appendingPathComponent("ssh/config")
        let fm = FileManager.default
        try fm.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: enlace.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SafeFile.write("Host bastion\n    HostName 198.51.100.1\n", to: real)
        try fm.createSymbolicLink(at: enlace, withDestinationURL: real)
        #expect(SessionFile.ensureInclude(sshConfig: enlace))
        #expect(try fm.destinationOfSymbolicLink(atPath: enlace.path) == real.path)
        let texto = try #require(try SafeFile.read(real))
        #expect(SessionFile.hasInclude(texto))
        #expect(texto.hasSuffix("Host bastion\n    HostName 198.51.100.1\n"))
        #expect(try SafeFile.read(real.appendingPathExtension("anterior")) == "Host bastion\n    HostName 198.51.100.1\n")
        #expect(fm.fileExists(atPath: real.appendingPathExtension("original").path))
        #expect(try fm.contentsOfDirectory(atPath: real.deletingLastPathComponent().path).contains { $0.hasPrefix("ssh_config.antes-netdeck-") })
        #expect((try fm.attributesOfItem(atPath: real.path)[.posixPermissions] as? Int) == 0o600)
        #expect(SessionFile.ensureInclude(sshConfig: enlace))                        // (una sola vez)
        #expect(try SafeFile.read(real) == texto)
    }

    // MARK: 4) cambiar la .app de forma atómica

    @Test func cambiarLaAppSinQuedarseSinNinguna() throws {
        let c = try Carpeta()
        defer { c.remove() }
        let fm = FileManager.default
        func app(_ dir: String, _ version: String) throws -> URL {
            let a = c.raiz.appendingPathComponent("\(dir)/Terminal NetDeck.app", isDirectory: true)
            try fm.createDirectory(at: a.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try version.write(to: a.appendingPathComponent("Contents/version"), atomically: true, encoding: .utf8)
            return a
        }
        func version(_ a: URL) -> String? { try? String(contentsOf: a.appendingPathComponent("Contents/version"), encoding: .utf8) }
        let instalada = try app("Applications", "vieja")
        let nueva = try app("build", "nueva")
        try AppInstall.replace(instalada, with: nueva)
        #expect(version(instalada) == "nueva")
        #expect(try fm.contentsOfDirectory(atPath: instalada.deletingLastPathComponent().path) == ["Terminal NetDeck.app"])

        // (la copia falla a medias: la de antes sigue entera y no quedan restos)
        let rota = try app("rota", "rota")
        let ilegible = rota.appendingPathComponent("Contents/ilegible")
        try "x".write(to: ilegible, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: ilegible.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ilegible.path) }
        #expect(throws: AppInstall.Failure.self) { try AppInstall.replace(instalada, with: rota) }
        #expect(version(instalada) == "nueva")
        #expect(try fm.contentsOfDirectory(atPath: instalada.deletingLastPathComponent().path) == ["Terminal NetDeck.app"])

        // (lo que no es una .app no se toca)
        #expect(throws: AppInstall.Failure.self) { try AppInstall.replace(c.raiz.appendingPathComponent("Applications/datos"), with: nueva) }
    }

    /// Si no puede ponerse la nueva y tampoco volver la de antes, no se borra nada: las dos siguen en la temporal.
    @Test func vueltaAtrasFallidaNoBorraNada() throws {
        let c = try Carpeta()
        defer { c.remove() }
        let fm = FileManager.default
        func app(_ dir: String, _ version: String) throws -> URL {
            let a = c.raiz.appendingPathComponent("\(dir)/Terminal NetDeck.app", isDirectory: true)
            try fm.createDirectory(at: a.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try version.write(to: a.appendingPathComponent("Contents/version"), atomically: true, encoding: .utf8)
            return a
        }
        func version(_ a: URL) -> String? { try? String(contentsOf: a.appendingPathComponent("Contents/version"), encoding: .utf8) }
        let nueva = try app("build", "nueva")

        // (falla poner la nueva: vuelve la de antes, sin restos)
        let una = try app("Una", "vieja")
        #expect(throws: AppInstall.Failure.self) {
            try AppInstall.replace(una, with: nueva) { from, to in
                if from.lastPathComponent == "Terminal NetDeck.app", from.path.contains(".nueva-") { throw CocoaError(.fileWriteUnknown) }
                try fm.moveItem(at: from, to: to)
            }
        }
        #expect(version(una) == "vieja")
        #expect(try fm.contentsOfDirectory(atPath: una.deletingLastPathComponent().path) == ["Terminal NetDeck.app"])

        // (fallan poner la nueva y volver la de antes: la temporal se queda con las dos)
        let doble = try app("Doble", "vieja")
        #expect(throws: AppInstall.Failure.self) {
            try AppInstall.replace(doble, with: nueva) { from, to in
                if from.path.contains(".nueva-") { throw CocoaError(.fileWriteUnknown) }
                try fm.moveItem(at: from, to: to)
            }
        }
        let resto = try #require(try fm.contentsOfDirectory(atPath: doble.deletingLastPathComponent().path).first { $0.contains(".nueva-") })
        let temporal = doble.deletingLastPathComponent().appendingPathComponent(resto)
        #expect(version(temporal.appendingPathComponent("anterior.app")) == "vieja")
        #expect(version(temporal.appendingPathComponent("Terminal NetDeck.app")) == "nueva")
    }

    // MARK: 2b) el ssh_config elegido llega a ssh, sftp, el explorador y los saltos

    @Test func elSshConfigLlegaAlTransporte() {
        let cfg = "/tmp/netdeck-pruebas/ssh_config"
        func f(_ a: [String]) -> Bool {
            guard let i = a.firstIndex(of: "-F"), let fin = a.firstIndex(of: "--") else { return false }
            return a[i + 1] == cfg && i < fin
        }
        let ssh = ConnectionRoute(title: "core-01", target: Endpoint(host: "192.0.2.11"), alias: "core-01")
        #expect(f(ssh.command(sharing: nil, configFile: cfg).arguments))
        #expect(!ssh.command(sharing: nil).arguments.contains("-F"))                         // (el de siempre: sin -F)
        var sftp = ssh
        sftp.transport = .sftp
        #expect(sftp.command(sharing: nil, configFile: cfg).executable == "/usr/bin/sftp")
        #expect(f(sftp.command(sharing: nil, configFile: cfg).arguments))
        #expect(f(sftp.sftpSubsystemCommand(sharing: nil, configFile: cfg)?.arguments ?? []))
        let telnet = ConnectionRoute(title: "olt-01", target: Endpoint(host: "192.0.2.21"), jumps: [Endpoint(host: "198.51.100.1")], transport: .telnet)
        #expect(f(telnet.command(sharing: nil, configFile: cfg).arguments))
        var salto = ConnectionRoute(title: "core-01", target: Endpoint(host: "192.0.2.11"), jumps: [Endpoint(host: "198.51.100.1")],
                                    jumpSpec: ["198.51.100.1"])
        salto.alias = nil
        #expect(f(salto.command(sharing: nil, configFile: cfg).arguments))
        // (compartiendo el salto: el ProxyCommand también lleva -F; con una ruta que la shell tocaría, -J, que ya lo pasa ssh)
        let sharing = JumpSharing(directory: "/tmp/netdeck-pruebas")
        let proxy = sharing.proxyCommand(hops: ["198.51.100.1"], socket: "/tmp/netdeck-pruebas/s", configFile: cfg)
        #expect(proxy?.contains("-F \(cfg) ") == true)
        #expect(sharing.proxyCommand(hops: ["198.51.100.1"], socket: "/tmp/netdeck-pruebas/s", configFile: "/tmp/con espacio") == nil)
    }

    // MARK: 6) Include: el lector y hasInclude leen igual

    @Test func includeIgualQueElLector() throws {
        let c = try Carpeta()
        defer { c.remove() }
        let ssh = c.raiz.appendingPathComponent("ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: ssh.appendingPathComponent("con espacio"), withIntermediateDirectories: true)
        try SafeFile.write("Host extra-01\n    HostName 192.0.2.31\n", to: ssh.appendingPathComponent("con espacio/extra"))
        let texto = "Include \"con espacio/extra\" # comentario\nHost core-01\n    HostName 192.0.2.11\n"
        let nombres = SSHConfigParser().parse(texto, sshDirectory: ssh).map(\.name)
        #expect(nombres.contains("extra-01") && nombres.contains("core-01"))
        #expect(SSHConfigParser.includePaths("\"con espacio/extra\" otro", sshDirectory: ssh)
                == [ssh.appendingPathComponent("con espacio/extra").path, ssh.appendingPathComponent("otro").path])
        // (la misma lectura para el Include de NetDeck: relativa a ~/.ssh y entre comillas)
        let home = AppPaths.home.appendingPathComponent(".ssh", isDirectory: true)
        #expect(SessionFile.hasInclude("Include \"../.config/netdeck/ssh_config\"\n", sshDirectory: home))
        #expect(SessionFile.hasInclude("Include=../.config/netdeck/ssh_config\n", sshDirectory: home))
        #expect(!SessionFile.hasInclude("Include .config/netdeck/ssh_config\n", sshDirectory: home))
    }

    // MARK: 5) «ssh -G» fuera del hilo principal y sin dar por bueno lo que no se ha comprobado

    @Test func sinSshNoSeDaPorBueno() throws {
        let c = try Carpeta()
        defer { c.remove() }
        #expect(SessionFile.sshCheck(c.sessions, host: "core-01", ssh: c.raiz.appendingPathComponent("no-hay-ssh").path) != nil)
        #expect(SessionFile.sshCheck(c.sessions, host: "core-01", ssh: c.sessions.path) != nil)     // (no ejecutable)
        #expect(SessionFile.sshCheck(c.sessions, host: "core-01") == nil)
    }

    @Test func guardarEnSegundoPlano() async throws {
        let c = try Carpeta()
        defer { c.remove() }
        let config = c.raiz.appendingPathComponent("config")
        let err = await archivo("core-02", "192.0.2.12").saveInBackground(to: c.sessions, including: config, backup: c.backup)
        #expect(err == nil)
        #expect(try SafeFile.read(c.sessions)?.contains("192.0.2.12") == true)
        #expect(try SafeFile.read(c.backup.sessionsBak)?.contains("core-01") == true)      // (la copia de antes)
        #expect(SessionFile.hasInclude(try SafeFile.read(config) ?? ""))
    }

    // MARK: 6) clave de equipo cambiada

    private static let aviso = """
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
        Someone could be eavesdropping on you right now (man-in-the-middle attack)!
        It is also possible that a host key has just been changed.
        The fingerprint for the ED25519 key sent by the remote host is
        SHA256:Gm0bqsCq2Uqx0n3lZ5yD1v8JkP2eQb3t9wX4yZ7aBcD.
        Please contact your system administrator.
        Add correct host key in ~/.ssh/known_hosts to get rid of this message.
        Offending ECDSA key in ~/.ssh/known_hosts:2
        Host key for [192.0.2.11]:2222 has changed and you have requested strict checking.
        Host key verification failed.
        """

    @Test func detectaElCambioDeClave() {
        let m = HostKeyMismatch.detect(Self.aviso.components(separatedBy: "\n"))
        #expect(m == HostKeyMismatch(host: "[192.0.2.11]:2222", file: "~/.ssh/known_hosts", line: 2, keyType: "ED25519",
                                     fingerprint: "SHA256:Gm0bqsCq2Uqx0n3lZ5yD1v8JkP2eQb3t9wX4yZ7aBcD", failed: true))
        #expect(HostKeyMismatch.detect(["Host key for core-01 has changed", "Last login: hoy"]) == nil)
        // (un equipo que ssh-keygen tomaría por una opción no vale)
        let raro = Self.aviso.replacingOccurrences(of: "[192.0.2.11]:2222", with: "-oProxyCommand=x")
        let rara = HostKeyMismatch.detect(raro.components(separatedBy: "\n"))
        #expect(rara?.host == "-oProxyCommand=x")                     // (tal cual: no se cambia por otro equipo)
        #expect(!KnownHosts.isValidHost("-oProxyCommand=x"))
        #expect(KnownHosts.entry(host: "192.0.2.11", port: 2222) == "[192.0.2.11]:2222")
        #expect(KnownHosts.entry(host: "core-01", port: 22) == "core-01")
        #expect(KnownHosts.newHostPrompt(["ED25519 key fingerprint is SHA256:abc.",
                                          "Are you sure you want to continue connecting (yes/no/[fingerprint])? "]) == "SHA256:abc")
        #expect(KnownHosts.newHostPrompt(["Password:"]) == nil)
    }

    /// Simulación de known_hosts: se quita sólo la clave del equipo (también con puerto y en líneas cifradas), con copia.
    @Test func limpiaKnownHosts() throws {
        let c = try Carpeta()
        defer { c.remove() }
        func clave(_ n: String) throws -> String {
            let k = c.raiz.appendingPathComponent(n)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            p.arguments = ["-q", "-t", "ed25519", "-N", "", "-C", "", "-f", k.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            return try String(contentsOf: k.appendingPathExtension("pub"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let (a, b) = (try clave("a"), try clave("b"))
        let kh = c.raiz.appendingPathComponent("known_hosts")
        let original = "192.0.2.11 \(a)\n[192.0.2.12]:2222 \(b)\nbastion \(b)\n"
        try SafeFile.write(original, to: kh)
        #expect(KnownHosts.remove(host: "[192.0.2.12]:2222", from: kh) == nil)
        var ahora = try #require(try SafeFile.read(kh))
        #expect(!ahora.contains("192.0.2.12"))
        #expect(ahora.contains("192.0.2.11 ") && ahora.contains("bastion "))
        #expect(try SafeFile.read(kh.appendingPathExtension("anterior")) == original)
        #expect((try FileManager.default.attributesOfItem(atPath: kh.path)[.posixPermissions] as? Int) == 0o600)

        // (HashKnownHosts: la línea no dice el equipo, ssh-keygen la encuentra igual)
        let h = Process()
        h.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        h.arguments = ["-H", "-f", kh.path]
        h.standardOutput = FileHandle.nullDevice
        h.standardError = FileHandle.nullDevice
        try h.run()
        h.waitUntilExit()
        #expect(KnownHosts.remove(host: "192.0.2.11", from: kh) == nil)
        ahora = try #require(try SafeFile.read(kh))
        #expect(ahora.split(separator: "\n").count == 1)                       // (queda sólo bastion)

        #expect(KnownHosts.remove(host: "-oProxyCommand=x", from: kh) != nil)
        #expect(KnownHosts.remove(host: "core-01", from: c.raiz.appendingPathComponent("no-existe")) == nil)
    }

    /// Sólo se limpia lo de esta conexión: el equipo que usa ssh para ella y uno de sus known_hosts (enlaces resueltos);
    /// si no cuadra, error, sin cambiar a otro archivo.
    @Test func verificaEquipoYArchivo() throws {
        let c = try Carpeta()
        defer { c.remove() }
        let fm = FileManager.default
        let kh = c.raiz.appendingPathComponent("ssh/known_hosts")
        try fm.createDirectory(at: kh.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SafeFile.write("", to: kh)
        let enlace = c.raiz.appendingPathComponent("kh-enlace")
        try fm.createSymbolicLink(at: enlace, withDestinationURL: kh)
        let ctx = KnownHosts.Context(names: ["[192.0.2.11]:2222"], files: [enlace])          // (también resuelto)
        let real = kh.resolvingSymlinksInPath().standardizedFileURL

        let ok = KnownHosts.verify(HostKeyMismatch(host: "[192.0.2.11]:2222", file: enlace.path), against: ctx)
        #expect((try? ok.get())?.host == "[192.0.2.11]:2222")
        #expect((try? ok.get())?.file == real)
        #expect((try? KnownHosts.verify(HostKeyMismatch(file: kh.path), against: ctx).get())?.host == "[192.0.2.11]:2222")

        func rechaza(_ m: HostKeyMismatch) -> Bool { if case .failure = KnownHosts.verify(m, against: ctx) { true } else { false } }
        #expect(rechaza(HostKeyMismatch(host: "198.51.100.1", file: kh.path)))              // (otro equipo: p. ej. el salto)
        #expect(rechaza(HostKeyMismatch(host: "-oProxyCommand=x", file: kh.path)))
        #expect(rechaza(HostKeyMismatch(host: "[192.0.2.11]:2222", file: "/etc/ssh/ssh_known_hosts")))
        #expect(rechaza(HostKeyMismatch(host: "[192.0.2.11]:2222", file: c.raiz.appendingPathComponent("no-existe").path)))
        #expect(rechaza(HostKeyMismatch(host: "[192.0.2.11]:2222", file: c.raiz.path)))    // (una carpeta)
        #expect(rechaza(HostKeyMismatch(host: "[192.0.2.11]:2222")))                         // (sin archivo: nada por defecto)
        #expect(rechaza(HostKeyMismatch(file: kh.path)) == false)
        #expect(KnownHosts.Context(names: ["a", "b"], files: [kh]).names.count == 2)
        if case .success = KnownHosts.verify(HostKeyMismatch(file: kh.path), against: KnownHosts.Context(names: ["a", "b"], files: [kh])) {
            Issue.record("sin equipo en el aviso y dos posibles: no se elige uno")
        }
    }

    /// «ssh -G» de verdad con el ssh_config elegido (-F): equipo (HostKeyAlias o HostName, con puerto) y known_hosts
    /// de esa conexión; el flujo completo hasta quitar la clave por el enlace, que se queda.
    @Test func contextoDeLaConexionConSshG() throws {
        let c = try Carpeta()
        defer { c.remove() }
        let fm = FileManager.default
        let kh = c.raiz.appendingPathComponent("kh")
        let enlace = c.raiz.appendingPathComponent("kh-enlace")
        let cfg = c.raiz.appendingPathComponent("cfg")
        try SafeFile.write("""
            Host core-01
                HostName 192.0.2.11
                Port 2222
                UserKnownHostsFile \(enlace.path)
            Host olt-01
                HostName 192.0.2.21
                HostKeyAlias olt-alias
                UserKnownHostsFile \(enlace.path)

            """, to: cfg)
        let r = ConnectionRoute(title: "core-01", target: Endpoint(host: "192.0.2.11", port: 2222), alias: "core-01")
        let ctx = try #require(KnownHosts.context(for: r, configFile: cfg.path))
        #expect(ctx.names == ["[192.0.2.11]:2222"])
        let ctx2 = try #require(KnownHosts.context(for: ConnectionRoute(title: "olt-01", target: Endpoint(host: "192.0.2.21"), alias: "olt-01"),
                                                   configFile: cfg.path))
        #expect(ctx2.names == ["olt-alias"])

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        p.arguments = ["-q", "-t", "ed25519", "-N", "", "-C", "", "-f", c.raiz.appendingPathComponent("k").path]
        try p.run()
        p.waitUntilExit()
        let pub = try String(contentsOf: c.raiz.appendingPathComponent("k.pub"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        try SafeFile.write("[192.0.2.11]:2222 \(pub)\nbastion \(pub)\n", to: kh)
        try fm.createSymbolicLink(at: enlace, withDestinationURL: kh)
        let aviso = Self.aviso.replacingOccurrences(of: "~/.ssh/known_hosts:2", with: "\(enlace.path):1")
        let m = try #require(HostKeyMismatch.detect(aviso.components(separatedBy: "\n")))
        let t = try KnownHosts.verify(m, against: ctx).get()
        #expect(KnownHosts.remove(host: t.host, from: enlace) == nil)
        #expect(try fm.destinationOfSymbolicLink(atPath: enlace.path) == kh.path)        // (el enlace sigue)
        #expect(try SafeFile.read(kh) == "bastion \(pub)\n")
    }

    /// Los textos nuevos del aviso, en las dos lenguas.
    @Test func textosDelAviso() {
        for clave in ["⚠️ La clave del equipo «%@» ha cambiado", "Aceptar y Actualizar Clave", "Cancelar",
                      "Huella de la clave nueva (%@): %@", "Clave antigua en %@",
                      "no se ha podido hacer la copia de seguridad de las sesiones (%@): no se ha guardado nada",
                      "no se ha podido añadir el Include a %@: no se ha guardado nada"] {
            #expect(Ingles.textos[clave] != nil, "falta en inglés: \(clave)")
        }
        #expect(Idioma.traducir("Aceptar y Actualizar Clave", a: .en) == "Accept and Update Key")
    }
}
