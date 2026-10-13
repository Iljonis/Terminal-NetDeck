import Foundation

/// Una sesión tal y como la edita el gestor de Sesiones (los mismos campos que el de NetDeck).
public struct EditableSession: Hashable, Sendable, Identifiable {
    public let id = UUID()
    public var group: String
    public var name: String
    public var summary = ""
    public var host = ""
    public var user = ""
    public var port = "22"
    /// «Saltar por»: ProxyJump (alias o usuario@equipo). Si el salto no deja reenviar, la app escribe el ssh en él.
    public var jump = ""
    public var keyFile = ""
    /// «Equipo antiguo»: algoritmos viejos.
    public var legacy = false
    /// Contraseña con nombre («# @clave AD»); «-» = la propia del equipo.
    public var credential = ""
    public var telnet = false
    /// Opciones que el editor no gestiona: se conservan tal cual.
    public var extra: [String] = []

    public init(group: String = "General", name: String) {
        self.group = group
        self.name = name
    }

    public static func == (a: Self, b: Self) -> Bool {
        (a.group, a.name, a.summary, a.host, a.user, a.port) == (b.group, b.name, b.summary, b.host, b.user, b.port)
            && (a.jump, a.keyFile, a.legacy, a.credential, a.telnet, a.extra) == (b.jump, b.keyFile, b.legacy, b.credential, b.telnet, b.extra)
    }

    public func hash(into h: inout Hasher) { h.combine(name) }

    /// Nombre válido para un «Host» (sin espacios ni comodines).
    public static func isValidName(_ n: String) -> Bool { Self.nameRule.matches(n) }
    private static let nameRule = Pattern(#"^[A-Za-z0-9_][A-Za-z0-9_.@:+-]*$"#, ignoreCase: false)
}

/// El ssh_config de sesiones de NetDeck (~/.config/netdeck/ssh_config): se lee y se escribe con el mismo formato que
/// su gestor de Sesiones, así ambos ven lo mismo. «Host *», «Host a b» y «Match» no son sesiones: se conservan tal cual.
public struct SessionFile: Sendable {
    public var sessions: [EditableSession] = []
    /// Bloques que no son sesiones: antes de la primera (Include…) y después (Host *, Match…).
    public var head: [[String]] = []
    public var tail: [[String]] = []
    /// «# @clave-grupo NOMBRE» de cada grupo.
    public var groupCredentials: [String: String] = [:]

    public static var defaultURL: URL { AppPaths.netdeck.appendingPathComponent("ssh_config") }

    /// «Equipo antiguo»: algoritmos viejos que aún acepta el ssh del Mac (como NetDeck).
    public static let legacyOptions = [
        "KexAlgorithms +diffie-hellman-group-exchange-sha1,diffie-hellman-group14-sha1,diffie-hellman-group1-sha1",
        "HostKeyAlgorithms +ssh-rsa", "PubkeyAcceptedAlgorithms +ssh-rsa",
        "Ciphers +aes128-cbc,aes256-cbc,3des-cbc", "MACs +hmac-sha1",
    ]
    static let legacyKeys = Set(legacyOptions.map { $0.split(separator: " ")[0].lowercased() })
    static let free = "# ── Para varias sesiones (Host *, Match…): el editor de Sesiones no los toca ──"
    static let header = """
        # ─────────────────────────────────────────────────────────────
        #  Sesiones de NetDeck — las gestiona la pestaña "Sesiones" (comando: sesiones)
        #  Se puede editar a mano respetando el formato:
        #    # @grupo NOMBRE      agrupa los Host que vienen debajo
        #    # @desc TEXTO        descripción
        #    # @antiguo           equipo antiguo (algoritmos ssh viejos)
        #    # @clave NOMBRE      usa la contraseña con nombre NOMBRE (p. ej. «AD ES»); «-» = la propia del equipo
        #    # @clave-grupo NOMBRE   (debajo de @grupo) la contraseña con nombre de todo el grupo
        #  Los bloques «Host *», «Host a b» o «Match» no son sesiones: se conservan tal cual,
        #  al final (o al principio si estaban antes de la primera sesión).
        # ─────────────────────────────────────────────────────────────

        """
    private static let sessionHost = Pattern(#"^host\s+[^\s*?!]+$"#)

    public init() {}

    public init(contentsOf url: URL) throws {
        self.init(text: try String(contentsOf: url, encoding: .utf8))
    }

    public init(text: String) {
        var group = "General"
        var cur: Int?
        var freeBlock: Int?          // índice en head/tail (inTail)
        var inTail = false
        for line in text.components(separatedBy: .newlines) {
            let s = line.trimmed
            let (key, value) = SSHConfigParser.option(s).map { ($0.0, $0.1) } ?? ("", "")
            if s.hasPrefix("# @grupo ") {
                group = String(s.dropFirst(9)).trimmed
            } else if s.hasPrefix("# @clave-grupo ") {
                groupCredentials[group] = String(s.dropFirst(15)).trimmed
            } else if key == "host", Self.sessionHost.matches("host \(value)"), !value.contains(where: \.isWhitespace) {
                sessions.append(EditableSession(group: group, name: value))
                cur = sessions.count - 1
                freeBlock = nil
            } else if key == "host" || key == "match" {
                cur = nil
                inTail = !sessions.isEmpty
                if inTail { tail.append([line]); freeBlock = tail.count - 1 } else { head.append([line]); freeBlock = head.count - 1 }
            } else if let f = freeBlock {
                if inTail { tail[f].append(line) } else { head[f].append(line) }
            } else if cur == nil {
                if !s.isEmpty, !s.hasPrefix("#") { head.append([line]) }
            } else if let i = cur {
                if s.isEmpty || s == Self.free { continue }
                if s.hasPrefix("# @desc ") { sessions[i].summary = String(s.dropFirst(8)).trimmed }
                else if s == "# @antiguo" { sessions[i].legacy = true }
                else if s == "# @telnet" { sessions[i].telnet = true }
                else if s.hasPrefix("# @clave ") { sessions[i].credential = String(s.dropFirst(9)).trimmed }
                else if s.hasPrefix("#") { continue }
                else {
                    switch key {
                    case "hostname": sessions[i].host = value
                    case "user": sessions[i].user = value
                    case "port": sessions[i].port = value
                    case "proxyjump": sessions[i].jump = value
                    case "identityfile": if sessions[i].keyFile.isEmpty { sessions[i].keyFile = value }
                    case "identitiesonly": break                       // se regenera junto a IdentityFile
                    case _ where sessions[i].legacy && Self.legacyKeys.contains(key): break
                    default: if !Self.legacyOptions.contains(s) { sessions[i].extra.append(s) }
                    }
                }
            }
        }
    }

    /// Grupos en orden de aparición.
    public var groups: [String] {
        var seen = Set<String>()
        return sessions.map(\.group).filter { seen.insert($0).inserted }
    }

    /// El texto del archivo, igual que lo escribe el gestor de Sesiones de NetDeck.
    public func render() -> String {
        func block(_ lines: [String]) -> String {
            "\n" + lines.joined(separator: "\n").trimmingCharacters(in: CharacterSet(charactersIn: "\n")) + "\n"
        }
        func quoted(_ v: String) -> String { v.contains(where: \.isWhitespace) ? "\"\(v)\"" : v }
        var out = Self.header + head.map(block).joined()
        for g in groups {
            out += "\n# @grupo \(g)\n"
            if let cg = groupCredentials[g], !cg.isEmpty { out += "# @clave-grupo \(cg)\n" }
            for s in sessions where s.group == g {
                out += "\nHost \(s.name)\n"
                if !s.summary.isEmpty { out += "    # @desc \(s.summary)\n" }
                if !s.credential.isEmpty { out += "    # @clave \(s.credential)\n" }
                if s.telnet { out += "    # @telnet\n" }
                if !s.host.isEmpty { out += "    HostName \(s.host)\n" }     // (un «HostName» vacío rompe ssh)
                if !s.user.isEmpty { out += "    User \(s.user)\n" }
                if !s.port.isEmpty, s.port != "22" { out += "    Port \(s.port)\n" }
                if !s.jump.isEmpty { out += "    ProxyJump \(s.jump)\n" }
                if !s.keyFile.isEmpty { out += "    IdentityFile \(quoted(s.keyFile))\n    IdentitiesOnly yes\n" }
                if s.legacy { out += "    # @antiguo\n" + Self.legacyOptions.map { "    \($0)\n" }.joined() }
                out += s.extra.map { "    \($0)\n" }.joined()
            }
        }
        if !tail.isEmpty { out += "\n\(Self.free)\n" + tail.map(block).joined() }
        return out
    }

    /// Qué está mal antes de guardar (nombres repetidos o inválidos, puertos, saltos que no existen…).
    public func problems() -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for s in sessions {
            if !EditableSession.isValidName(s.name) { out.append(L("«\(s.name)»: el nombre no puede llevar espacios ni * ? !")) }
            if !seen.insert(s.name.lowercased()).inserted { out.append(L("«\(s.name)» está repetida")) }
            if !s.port.isEmpty, Int(s.port).map({ !(1...65535).contains($0) }) ?? true { out.append(L("«\(s.name)»: puerto «\(s.port)»")) }
            if s.host.contains(where: { $0.isWhitespace || $0 == "\"" }) { out.append(L("«\(s.name)»: equipo «\(s.host)»")) }
            if s.user.contains(where: { $0.isWhitespace || $0 == "\"" }) { out.append(L("«\(s.name)»: usuario «\(s.user)»")) }
            if s.jump == s.name { out.append(L("«\(s.name)» salta por sí misma")) }
        }
        return out
    }

    /// Guarda como NetDeck: primero en un temporal, se comprueba con «ssh -G» (si ssh no lo entiende NO se guarda: rompería
    /// ssh en todo el Mac), copia del anterior (.anterior) y se cambia. Devuelve el error, o nil.
    @discardableResult
    public func save(to url: URL = SessionFile.defaultURL, validate: Bool = true) -> String? {
        if let p = problems().first { return p }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("tmp")
        do {
            try render().write(to: tmp, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        } catch {
            return error.localizedDescription
        }
        if validate, let err = Self.sshCheck(tmp, host: sessions.first?.name ?? "x") {
            let rejected = url.appendingPathExtension("rechazado")
            try? fm.removeItem(at: rejected)
            try? fm.moveItem(at: tmp, to: rejected)
            return L("ssh no lo entiende: \(err)")
        }
        do {
            try SafeFile.backup(url)                     // (si no se puede leer o copiar, no se toca)
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
        } catch {
            try? fm.removeItem(at: tmp)
            return error.localizedDescription
        }
        DebugLog.log("sesiones", "guardadas \(sessions.count) en \(url.path)")
        return nil
    }

    static func sshCheck(_ file: URL, host: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = ["-G", "-F", file.path, host]
        let err = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = err
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmed
        return p.terminationStatus == 0 ? nil : (msg.isEmpty ? L("código \(p.terminationStatus)") : msg)
    }

    /// Que ~/.ssh/config incluya el de NetDeck (como su instalador, con copia del de antes). true si ya lo incluía o se ha añadido.
    @discardableResult
    public static func ensureInclude(sshConfig: URL = AppPaths.home.appendingPathComponent(".ssh/config")) -> Bool {
        let fm = FileManager.default
        let line = "Include ~/.config/netdeck/ssh_config"
        let old: String
        do { old = try SafeFile.read(sshConfig) ?? "" } catch {
            DebugLog.log("sesiones", "\(sshConfig.path) no se puede leer: no añado el Include")
            return false
        }
        if old.contains(line) { return true }
        try? fm.createDirectory(at: sshConfig.deletingLastPathComponent(), withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        if fm.fileExists(atPath: sshConfig.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            do {
                try fm.copyItem(at: sshConfig, to: sshConfig.appendingPathExtension("antes-netdeck-\(f.string(from: Date()))"))
            } catch {
                DebugLog.log("sesiones", "sin copia de \(sshConfig.path): no lo toco")
                return false
            }
        }
        let text = "# Sesiones de NetDeck (☰ Menú → Sesiones, o comando: sesiones)\n\(line)\n\n" + old
        do {
            try text.write(to: sshConfig, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sshConfig.path)
            DebugLog.log("sesiones", "añadido «\(line)» a \(sshConfig.path)")
            return true
        } catch {
            return false
        }
    }
}
