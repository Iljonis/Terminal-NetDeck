import Foundation

/// Lo que escribe ssh cuando la clave del equipo no es la de known_hosts («REMOTE HOST IDENTIFICATION HAS CHANGED»):
/// para quién («Host key for … has changed»), dónde está la clave vieja («Offending … key in archivo:línea») y la
/// huella de la nueva. Puede ser un ataque (alguien en medio): sólo se limpia si el usuario lo acepta.
public struct HostKeyMismatch: Equatable, Sendable {
    /// Como lo escribe ssh: «core-01», «192.0.2.11» o «[192.0.2.11]:2222». nil si ssh no lo ha dicho (aún).
    public var host: String?
    /// El known_hosts con la clave vieja y su línea.
    public var file: String?
    public var line: Int?
    /// Tipo y huella de la clave nueva: «ED25519», «SHA256:…».
    public var keyType: String?
    public var fingerprint: String?
    /// ssh ha cortado ya («Host key verification failed.»).
    public var failed = false

    public init(host: String? = nil, file: String? = nil, line: Int? = nil, keyType: String? = nil,
                fingerprint: String? = nil, failed: Bool = false) {
        (self.host, self.file, self.line, self.keyType, self.fingerprint, self.failed) = (host, file, line, keyType, fingerprint, failed)
    }

    /// Busca el aviso en las líneas de la pantalla (las del propio ssh, al principio de la línea). nil si no está.
    public static func detect(_ lines: [String]) -> HostKeyMismatch? {
        let t = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let start = t.firstIndex(where: { $0.hasPrefix("@") && $0.contains("WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!") })
        else { return nil }
        var m = HostKeyMismatch()
        let rest = Array(t[(start + 1)...])
        for (i, l) in rest.enumerated() {
            if l.hasPrefix("The fingerprint for the "), l.hasSuffix(" key sent by the remote host is") {
                m.keyType = l.dropFirst("The fingerprint for the ".count).split(separator: " ").first.map(String.init)
                if i + 1 < rest.count {
                    let f = rest[i + 1].hasSuffix(".") ? String(rest[i + 1].dropLast()) : rest[i + 1]
                    if f.hasPrefix("SHA256:") || f.hasPrefix("MD5:"), !f.contains(" ") { m.fingerprint = f }
                }
            } else if l.hasPrefix("Offending "), !l.hasPrefix("Offending key for IP"), m.file == nil,
                      let r = l.range(of: " key in "), let colon = l.lastIndex(of: ":"), colon > r.upperBound {
                m.file = String(l[r.upperBound..<colon])
                m.line = Int(l[l.index(after: colon)...])
            } else if l.hasPrefix("Host key for "), let r = l.range(of: " has changed") {
                // (tal cual, aunque no sea válido: así no se limpia otro equipo en su lugar; `verify` lo rechaza)
                m.host = String(l[l.index(l.startIndex, offsetBy: "Host key for ".count)..<r.lowerBound])
            } else if l.hasPrefix("Host key verification failed") {
                m.failed = true
            }
        }
        return m
    }
}

/// known_hosts: quitar la clave de un equipo (como «ssh-keygen -R») y reconocer la pregunta de un equipo nuevo.
public enum KnownHosts {
    public static var defaultURL: URL { AppPaths.home.appendingPathComponent(".ssh/known_hosts") }

    /// «core-01», «192.0.2.11», «2001:db8::1» o «[192.0.2.11]:2222»: nada que ssh-keygen pudiera tomar por una opción
    /// ni espacios, comodines o caracteres de control.
    public static func isValidHost(_ h: String) -> Bool {
        guard !h.isEmpty, h.count <= 260, !h.hasPrefix("-") else { return false }
        let ok = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_:[]%"))
        return h.unicodeScalars.allSatisfy { $0.isASCII && ok.contains($0) }
    }

    /// Cómo se apunta un equipo en known_hosts: «equipo» con el puerto 22 y «[equipo]:puerto» con otro.
    public static func entry(host: String, port: Int?) -> String {
        guard let port, port != 22 else { return host }
        return "[\(host)]:\(port)"
    }

    /// Lo que ssh usaría de verdad para esta conexión (según «ssh -G»): cómo apunta el equipo en known_hosts
    /// (`HostKeyAlias` o `HostName`, con «[…]:puerto» si no es el 22) y en qué archivos (`UserKnownHostsFile`).
    public struct Context: Equatable, Sendable {
        public var names: Set<String>
        public var files: [URL]

        public init(names: Set<String>, files: [URL]) {
            self.names = names
            self.files = files
        }

        /// De la salida de «ssh -G». nil si falta el equipo.
        public static func parse(sshG output: String) -> Context? {
            var opt: [String: String] = [:]
            for line in output.components(separatedBy: .newlines) {
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                if parts.count == 2, opt[parts[0]] == nil { opt[parts[0]] = parts[1] }
            }
            guard let host = opt["hostkeyalias"] ?? opt["hostname"], !host.isEmpty else { return nil }
            let port = opt["port"].flatMap(Int.init)
            let files = SSHConfigParser.arguments(opt["userknownhostsfile"] ?? "~/.ssh/known_hosts ~/.ssh/known_hosts2")
                .filter { $0 != "none" }
                .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            return Context(names: [entry(host: host, port: port)], files: files)
        }
    }

    /// «ssh -G» de la conexión de `route` (con el ssh_config de Ajustes, `configFile`), sin conectar. nil si no sale.
    /// Síncrono (hasta 10 s): desde la app, fuera del hilo principal.
    public static func context(for route: ConnectionRoute, configFile: String?, ssh: String = "/usr/bin/ssh") -> Context? {
        guard !route.isLocal, route.transport == .ssh || route.transport == .sftp else { return nil }
        var a = ConnectionRoute.configOptions(configFile) + ["-G"]
        if let alias = route.alias {
            a += ["--", alias]
        } else {
            guard !route.target.host.hasPrefix("-") else { return nil }
            if let p = route.target.port { a += ["-p", String(p)] }
            if let u = route.target.user, !u.hasPrefix("-") { a += ["-l", u] }
            a += ["--", route.target.host]
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ssh)
        p.arguments = a
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        watchdog.cancel()
        guard p.terminationReason == .exit, p.terminationStatus == 0 else { return nil }
        return Context.parse(sshG: String(decoding: data, as: UTF8.self))
    }

    public static func contextInBackground(for route: ConnectionRoute, configFile: String?) async -> Context? {
        await Task.detached(priority: .userInitiated) { context(for: route, configFile: configFile) }.value
    }

    /// Qué limpiar, sólo si lo que dice el aviso es de esta conexión: el equipo tiene que ser el que ssh usa para ella
    /// (un aviso que hable de otro, p. ej. de un salto o puesto por un banner, no vale) y el archivo, uno de sus
    /// known_hosts (enlaces resueltos; archivo normal que existe). Si no cuadra, error: no se toca ningún otro.
    public static func verify(_ m: HostKeyMismatch, against c: Context) -> Result<(host: String, file: URL), Refused> {
        let host: String
        if let h = m.host {
            guard c.names.contains(h) else {
                return .failure(Refused(message: L("el aviso es de «\(h)», no de esta conexión (\(c.names.sorted().joined(separator: ", ")))")))
            }
            host = h
        } else if c.names.count == 1, let only = c.names.first {
            host = only
        } else {
            return .failure(Refused(message: L("ssh no ha dicho de qué equipo es la clave")))
        }
        guard let f = m.file, !f.isEmpty else {
            return .failure(Refused(message: L("ssh no ha dicho en qué known_hosts está la clave vieja")))
        }
        let file = URL(fileURLWithPath: (f as NSString).expandingTildeInPath).resolvingSymlinksInPath().standardizedFileURL
        // (enlaces resueltos al comprobar, en los dos lados: como están ahora en disco)
        let allowed = Set(c.files.map { $0.resolvingSymlinksInPath().standardizedFileURL })
        guard allowed.contains(file),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            return .failure(Refused(message: L("«\(AppPaths.tilde(f))» no es un known_hosts de esta conexión")))
        }
        return .success((host, file))
    }

    public struct Refused: Error, Equatable {
        public let message: String
        public init(message: String) { self.message = message }
    }

    /// Quita las claves de `host` de `file` con «ssh-keygen -R» (también las de líneas cifradas con HashKnownHosts).
    /// Antes, copia con `SafeFile` (`.anterior`/`.original`; ssh-keygen deja además `.old`). Devuelve el error, o nil.
    /// Síncrono: desde la app, fuera del hilo principal.
    public static func remove(host: String, from file: URL = defaultURL, keygen: String = "/usr/bin/ssh-keygen") -> String? {
        guard isValidHost(host) else { return L("«\(host)» no es un equipo válido") }
        // (si es un enlace, se cambia el archivo al que apunta: ssh-keygen sustituiría el enlace por un archivo)
        let file = file.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }        // (nada que quitar)
        do { try SafeFile.backup(file) } catch { return error.localizedDescription }
        guard FileManager.default.isExecutableFile(atPath: keygen) else { return L("no se puede ejecutar \(keygen)") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: keygen)
        p.arguments = ["-R", host, "-f", file.path]
        let err = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return L("no se puede ejecutar \(keygen): \(error.localizedDescription)") }
        let data = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return msg.isEmpty ? L("código \(p.terminationStatus)") : msg
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        DebugLog.log("known_hosts", "quitada la clave de \(host) de \(file.path)")
        return nil
    }

    /// Lo mismo, fuera del hilo principal.
    public static func removeInBackground(host: String, from file: URL) async -> String? {
        await Task.detached(priority: .userInitiated) { remove(host: host, from: file) }.value
    }

    /// La pregunta de ssh ante un equipo que no está en known_hosts («Are you sure you want to continue connecting
    /// (yes/no/[fingerprint])?»), con la huella que enseña. nil si la última línea no es esa pregunta.
    public static func newHostPrompt(_ lines: [String]) -> String? {
        guard let last = lines.last?.trimmingCharacters(in: .whitespaces),
              last.hasPrefix("Are you sure you want to continue connecting (yes/no") else { return nil }
        for l in lines.dropLast().reversed() {
            let t = l.trimmingCharacters(in: .whitespaces)
            if let r = t.range(of: " key fingerprint is ") {
                let f = t[r.upperBound...]
                return String(f.hasSuffix(".") ? f.dropLast() : f)
            }
        }
        return nil
    }
}
