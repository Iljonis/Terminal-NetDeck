import Foundation

/// Una sesión tal y como la edita el gestor de Sesiones (los mismos campos que el de NetDeck).
public struct EditableSession: Hashable, Sendable, Identifiable {
    public var id = UUID()
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
    /// SSH, Telnet, SFTP, FTP, serie o local («# @telnet» / «# @tipo …»).
    public var kind = SessionProfile.Transport.ssh
    /// «# @serie …» (sólo cuenta si `kind` es .serial).
    public var serial = SerialLine()
    /// Perfil de terminal («# @fuente», «# @tema», «# @scrollback», «# @teclado», «# @prompt»): vacío = Ajustes.
    public var terminal = TerminalProfile()
    /// Comentarios libres del bloque («# lo que sea», «# @proyecto X»): se conservan tal cual, sin el «# ».
    public var notes: [String] = []
    /// Opciones que el editor no gestiona: se conservan tal cual.
    public var extra: [String] = []

    public var telnet: Bool {
        get { kind == .telnet }
        set { kind = newValue ? .telnet : (kind == .telnet ? .ssh : kind) }
    }

    public init(group: String = "General", name: String) {
        self.group = group
        self.name = name
    }

    /// Puerto de cada tipo: ssh y sftp 22, telnet 23, ftp 21 (serie y local no tienen).
    public static func defaultPort(_ kind: SessionProfile.Transport) -> String {
        switch kind {
        case .telnet: "23"
        case .ftp: "21"
        case .ssh, .sftp, .serial, .local: "22"
        }
    }

    /// Una sesión nueva: con tu usuario del Mac (se puede cambiar) y el puerto de su tipo.
    public static func new(group: String, name: String, kind: SessionProfile.Transport = .ssh,
                           user: String = AppPaths.userName) -> EditableSession {
        var s = EditableSession(group: group, name: name)
        s.kind = kind
        s.port = defaultPort(kind)
        if kind.isNetwork { s.user = user }
        return s
    }

    /// Cambia el tipo y, si el puerto era el del tipo anterior (o ninguno), pone el del nuevo: SSH/SFTP → 22,
    /// Telnet → 23, FTP → 21. Un puerto propio (2222…) se respeta.
    public mutating func setKind(_ k: SessionProfile.Transport) {
        let standard = port.trimmed.isEmpty || ["21", "22", "23"].contains(port.trimmed)
        kind = k
        if standard { port = Self.defaultPort(k) }
    }

    public static func == (a: Self, b: Self) -> Bool {
        (a.group, a.name, a.summary, a.host, a.user, a.port) == (b.group, b.name, b.summary, b.host, b.user, b.port)
            && (a.jump, a.keyFile, a.legacy, a.credential, a.kind, a.extra) == (b.jump, b.keyFile, b.legacy, b.credential, b.kind, b.extra)
            && (a.serial, a.notes, a.terminal) == (b.serial, b.notes, b.terminal)
    }

    public func hash(into h: inout Hasher) { h.combine(name) }

    /// Nombre válido para un «Host» (sin espacios ni comodines).
    public static func isValidName(_ n: String) -> Bool { Self.nameRule.matches(n) }
    private static let nameRule = Pattern(#"^[A-Za-z0-9_][A-Za-z0-9_.@:+-]*$"#, ignoreCase: false)

    /// Una copia con otro nombre (y otro id: es otra sesión).
    public func copy(named n: String) -> EditableSession {
        var c = self
        c.id = UUID()
        c.name = n
        return c
    }
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
        #    # @telnet · # @tipo sftp|ftp|serie|local   tipo de sesión (sin nada: ssh)
        #    # @serie /dev/cu.usbserial-0001 9600 8N1    puerto serie (con «@tipo serie»)
        #    # @fuente Menlo 13 · # @tema ID · # @scrollback 10000 · # @teclado meta retroceso-h
        #    # @prompt REGEX      perfil de la pestaña (sin ellas, lo de Ajustes)
        #  Un grupo con «/» (Clientes/Madrid/Core) se ve como carpetas dentro de carpetas.
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
        var withPort = Set<Int>()
        defer {
            for i in sessions.indices where !withPort.contains(i) { sessions[i].port = EditableSession.defaultPort(sessions[i].kind) }
        }
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
                else if s == "# @telnet" { sessions[i].kind = .telnet }
                else if s.hasPrefix("# @tipo "), let k = SessionProfile.Transport(annotation: String(s.dropFirst(8))) {
                    sessions[i].kind = k
                }
                else if s.hasPrefix("# @serie "), let l = SerialLine(annotation: String(s.dropFirst(9))) { sessions[i].serial = l }
                else if s.hasPrefix("# @clave ") { sessions[i].credential = String(s.dropFirst(9)).trimmed }
                else if let (k, v) = SSHConfigParser.note(s), TerminalProfile.keys.contains(k) {
                    // (la primera de cada clave, como al conectar; una que no vale se ignora con aviso)
                    if !sessions[i].terminal.has(k) { sessions[i].terminal.read(k, v, session: sessions[i].name) }
                }
                else if s.hasPrefix("#") {
                    let n = String(s.dropFirst()).trimmed
                    if !n.isEmpty { sessions[i].notes.append(n) }
                }
                else {
                    switch key {
                    case "hostname": sessions[i].host = value
                    case "user": sessions[i].user = value
                    case "port": sessions[i].port = value; withPort.insert(i)
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

    /// Sube (-1) o baja (+1) una sesión dentro de su grupo: el orden de la lista es el del archivo. false si ya está
    /// en el borde.
    @discardableResult
    public mutating func move(_ id: UUID, by step: Int) -> Bool {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return false }
        let g = sessions[i].group
        let near = step < 0 ? sessions[..<i].lastIndex { $0.group == g }
                            : sessions[(i + 1)...].firstIndex { $0.group == g }
        guard let j = near else { return false }
        sessions.swapAt(i, j)
        return true
    }

    /// Arrastrar: la pone justo delante de `target` (en su grupo) o, si `after`, justo detrás.
    public mutating func move(_ id: UUID, to target: UUID, after: Bool = false) {
        guard id != target, let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        var s = sessions.remove(at: i)
        guard let j = sessions.firstIndex(where: { $0.id == target }) else { sessions.insert(s, at: i); return }
        s.group = sessions[j].group
        sessions.insert(s, at: after ? j + 1 : j)
    }

    /// «core-01-2», «core-01-3»… el primero libre (sin mirar mayúsculas).
    public func uniqueName(_ base: String) -> String {
        var n = base, k = 2
        while sessions.contains(where: { $0.name.lowercased() == n.lowercased() }) { n = "\(base)-\(k)"; k += 1 }
        return n
    }

    /// Quién usa una contraseña con nombre: las sesiones con «# @clave NOMBRE» y los grupos con «# @clave-grupo NOMBRE».
    public func usage(ofNamed name: String) -> (sessions: [String], groups: [String]) {
        (sessions.filter { $0.credential == name }.map(\.name),
         groups.filter { groupCredentials[$0] == name })
    }

    /// La con nombre que usa una sesión (la suya o la de su grupo) y de dónde sale. nil: ninguna o «-» (la propia).
    public func namedCredential(of s: EditableSession) -> (name: String, fromGroup: Bool)? {
        if s.credential == "-" { return nil }
        if !s.credential.isEmpty { return (s.credential, false) }
        if let g = groupCredentials[s.group], !g.isEmpty { return (g, true) }
        return nil
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
                if s.kind == .telnet { out += "    # @telnet\n" } else if s.kind != .ssh { out += "    # @tipo \(s.kind.annotation)\n" }
                if s.kind == .serial { out += "    # @serie \(s.serial.annotation)\n" }
                out += s.terminal.annotations.map { "    # @\($0.key) \($0.value)\n" }.joined()
                out += s.notes.map { "    # \($0)\n" }.joined()
                if !s.host.isEmpty { out += "    HostName \(s.host)\n" }     // (un «HostName» vacío rompe ssh)
                if !s.user.isEmpty { out += "    User \(s.user)\n" }
                if !s.port.isEmpty, s.port != EditableSession.defaultPort(s.kind) { out += "    Port \(s.port)\n" }
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
            if s.kind == .serial, !s.serial.isValid { out.append(L("«\(s.name)»: puerto serie «\(s.serial.device)»")) }
            if s.notes.contains(where: { $0.contains(where: \.isNewline) }) || s.group.contains(where: \.isNewline) {
                out.append(L("«\(s.name)»: saltos de línea en el grupo o las notas"))
            }
            // (un salto de línea o un carácter de control en cualquier campo abriría otra línea en el ssh_config:
            // «ProxyCommand …», «Host *»…)
            if ([s.summary, s.credential, s.jump, s.keyFile, s.serial.device] + s.extra).contains(where: Self.hasControl) {
                out.append(L("«\(s.name)»: saltos de línea o caracteres de control en un campo"))
            }
            if let k = s.extra.compactMap({ SSHConfigParser.option($0.trimmed)?.0 }).first(where: { ["host", "match"].contains($0) }) {
                out.append(L("«\(s.name)»: «\(k)» no puede ir en las opciones (abriría otro bloque)"))
            }
            if [s.host, s.user, s.jump].contains(where: { $0.hasPrefix("-") }) {
                out.append(L("«\(s.name)»: el equipo, el usuario o el salto no pueden empezar por «-»"))
            }
            if s.notes.contains(where: { $0.hasPrefix("@grupo") || $0.hasPrefix("@clave-grupo") }) {
                out.append(L("«\(s.name)»: una nota no puede empezar por @grupo ni @clave-grupo"))
            }
            if let k = TerminalProfile.keys.first(where: { k in s.notes.contains { $0.lowercased().hasPrefix("@" + k) } }) {
                out.append(L("«\(s.name)»: «@\(k)» va en la sección Perfil, no en las notas"))
            }
            out += s.terminal.problems().map { L("«\(s.name)»: \($0)") }
        }
        return out
    }

    /// Guarda como NetDeck: primero en un temporal, se comprueba con «ssh -G» (si ssh no lo entiende NO se guarda: rompería
    /// ssh en todo el Mac), copia del anterior (.anterior) y se cambia. Devuelve el error, o nil.
    @discardableResult
    public func save(to url: URL = SessionFile.defaultURL, validate: Bool = true) -> String? {
        let (tmp, err) = prepare(url, validate: validate)
        guard let tmp else { return err }
        return Self.install(tmp, at: url, count: sessions.count)
    }

    /// El archivo nuevo en «url.tmp», ya comprobado con «ssh -G» (si no vale, queda como «.rechazado»). Sin tocar `url`.
    func prepare(_ url: URL, validate: Bool) -> (URL?, String?) {
        if let p = problems().first { return (nil, p) }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("tmp")
        do {
            try render().write(to: tmp, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        } catch {
            return (nil, error.localizedDescription)
        }
        if validate, let err = Self.sshCheck(tmp, host: sessions.first?.name ?? "x") {
            let rejected = url.appendingPathExtension("rechazado")
            try? fm.removeItem(at: rejected)
            try? fm.moveItem(at: tmp, to: rejected)
            return (nil, L("ssh no lo entiende: \(err)"))
        }
        return (tmp, nil)
    }

    /// Cambia `url` por el temporal ya comprobado (copia antes con `SafeFile.backup`). Si falla, `url` queda como estaba.
    static func install(_ tmp: URL, at url: URL, count: Int) -> String? {
        let fm = FileManager.default
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
        DebugLog.log("sesiones", "guardadas \(count) en \(url.path)")
        return nil
    }

    /// (el tabulador no: ssh_config lo admite entre clave y valor)
    static func hasControl(_ s: String) -> Bool {
        s.unicodeScalars.contains { ($0.value < 0x20 && $0.value != 0x09) || $0.value == 0x7f || $0.properties.generalCategory == .lineSeparator
            || $0.properties.generalCategory == .paragraphSeparator || $0.value == 0x85 }
    }

    /// «ssh -G» sobre `file`. Si ssh no se puede ejecutar (o no es /usr/bin/ssh), error: un archivo sin comprobar no
    /// se da por bueno. Es síncrono y puede tardar hasta `checkTimeout`: desde la app, sólo fuera del hilo principal
    /// (`saveInBackground`).
    static func sshCheck(_ file: URL, host: String, ssh: String = "/usr/bin/ssh") -> String? {
        guard FileManager.default.isExecutableFile(atPath: ssh) else { return L("no se puede ejecutar \(ssh)") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ssh)
        p.arguments = ["-G", "-F", file.path, "--", host]
        let err = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return L("no se puede ejecutar \(ssh): \(error.localizedDescription)") }
        // (se lee mientras corre: con mucho que decir, ssh se quedaría esperando a que alguien vacíe la tubería; y
        // como mucho `checkTimeout`: un Include o un «Match exec» que no acaba no deja la app colgada al guardar)
        let expired = Once()
        let watchdog = DispatchWorkItem { if p.isRunning, expired.take() { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + checkTimeout, execute: watchdog)
        // (stderr en segundo plano: si ssh deja un hijo vivo con la tubería abierta, no se espera por él)
        nonisolated(unsafe) var data = Data()
        let reading = DispatchGroup()
        DispatchQueue.global().async(group: reading) { data = err.fileHandleForReading.readDataToEndOfFile() }
        p.waitUntilExit()
        watchdog.cancel()
        if reading.wait(timeout: .now() + 1) == .timedOut { data = Data() }
        if expired.isTaken, p.terminationReason == .uncaughtSignal {
            return L("ssh -G no ha contestado en \(Int(checkTimeout)) s (¿un Include o «Match exec» que no acaba?)")
        }
        // (muerto por una señal ajena: tampoco vale como comprobado)
        if p.terminationReason == .uncaughtSignal { return L("ssh -G ha terminado con la señal \(p.terminationStatus)") }
        let msg = String(decoding: data, as: UTF8.self).trimmed
        return p.terminationStatus == 0 ? nil : (msg.isEmpty ? L("código \(p.terminationStatus)") : msg)
    }

    static let checkTimeout: TimeInterval = 10

    public static let includeLine = "Include ~/.config/netdeck/ssh_config"

    /// ¿Lo incluye ya? Sólo una directiva «Include» de verdad, leída igual que la lee `SSHConfigParser` (mayúsculas,
    /// «Include=…», varias rutas, comillas, «~» y rutas relativas a `sshDirectory`, por defecto ~/.ssh) con una ruta que
    /// sea exactamente ~/.config/netdeck/ssh_config. No cuentan los comentarios, otra palabra que empiece por «include»,
    /// una ruta que sólo lo contenga (…/ssh_config.bak) ni un Include dentro de un bloque «Host»/«Match» que no sea
    /// para todos (sólo valdría para esos equipos).
    public static func hasInclude(_ sshConfigText: String, sshDirectory: URL? = nil) -> Bool {
        let wanted = Set([defaultURL, AppPaths.home.appendingPathComponent(".config/netdeck/ssh_config")]
            .flatMap { [$0.standardizedFileURL.path, $0.resolvingSymlinksInPath().standardizedFileURL.path] })
        var global = true                                   // (antes del primer Host/Match, o en «Host *»/«Match all»)
        for raw in sshConfigText.components(separatedBy: .newlines) {
            guard let (key, value) = SSHConfigParser.directive(raw) else { continue }
            switch key {
            case "host": global = SSHConfigParser.arguments(value) == ["*"]
            case "match": global = SSHConfigParser.arguments(value).map { $0.lowercased() } == ["all"]
            case "include" where global:
                if SSHConfigParser.includePaths(value, sshDirectory: sshDirectory).contains(where: wanted.contains) { return true }
            default: break
            }
        }
        return false
    }

    /// Qué haría falta para que `sshConfig` incluya el de NetDeck, sin tocar nada: el archivo de verdad (si es un enlace,
    /// al que apunta), su texto de ahora (nil si no existe) y el nuevo (nil si ya lo incluye). Error si no se puede leer.
    struct IncludePlan {
        var target: URL
        var old: String?
        var new: String?
    }

    static func includePlan(_ sshConfig: URL) throws -> IncludePlan {
        let target = sshConfig.resolvingSymlinksInPath()
        // (el propio archivo de sesiones no se incluye a sí mismo)
        if target.standardizedFileURL.path == defaultURL.resolvingSymlinksInPath().standardizedFileURL.path {
            return IncludePlan(target: target, old: nil, new: nil)
        }
        let old = try SafeFile.read(target)
        if let old, hasInclude(old, sshDirectory: target.deletingLastPathComponent()) { return IncludePlan(target: target, old: old, new: nil) }
        let new = "# Sesiones de NetDeck (☰ Menú → Sesiones, o comando: sesiones)\n\(includeLine)\n\n" + (old ?? "")
        return IncludePlan(target: target, old: old, new: new)
    }

    /// Escribe el Include con `SafeFile` (`.anterior`/`.original` y además una copia con fecha), atómico y 0600. Si
    /// falla, el archivo queda como estaba.
    static func applyInclude(_ plan: IncludePlan) throws {
        guard let new = plan.new else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: plan.target.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        if fm.fileExists(atPath: plan.target.path) {
            try SafeFile.backup(plan.target)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            let stamped = plan.target.appendingPathExtension("antes-netdeck-\(f.string(from: Date()))")
            if !fm.fileExists(atPath: stamped.path) { try fm.copyItem(at: plan.target, to: stamped) }
        }
        try SafeFile.write(new, to: plan.target)
        DebugLog.log("sesiones", "añadido «\(includeLine)» a \(plan.target.path)")
    }

    /// Deja `sshConfig` como antes de `applyInclude` (si no existía, se quita). true si lo ha conseguido.
    static func undoInclude(_ plan: IncludePlan) -> Bool {
        guard plan.new != nil else { return true }
        do {
            if let old = plan.old { try SafeFile.write(old, to: plan.target) } else { try FileManager.default.removeItem(at: plan.target) }
            return true
        } catch {
            ErrorLog.error("sesiones", "no se ha podido dejar \(AppPaths.tilde(plan.target.path)) como estaba: \(error.localizedDescription)")
            return false
        }
    }

    /// Que `sshConfig` (~/.ssh/config o el que se haya elegido en Ajustes) incluya el de NetDeck, como su instalador.
    /// true si ya lo incluía o se ha añadido; si falla algo, false y no se toca.
    @discardableResult
    public static func ensureInclude(sshConfig: URL = AppPaths.home.appendingPathComponent(".ssh/config")) -> Bool {
        do {
            try applyInclude(try includePlan(sshConfig))
            return true
        } catch {
            ErrorLog.warning("sesiones", "sin Include en \(AppPaths.tilde(sshConfig.path)): \(error.localizedDescription)")
            return false
        }
    }

    /// Guardar las sesiones como desde el gestor. Primero se comprueba todo sin tocar nada (las sesiones con «ssh -G» y
    /// que `sshConfig`, ~/.ssh/config o el elegido en Ajustes, se pueda leer); luego la copia de las de ahora
    /// (`DataBackup.backupSessionsBeforeSave`; sin ella no se guarda), el Include y el archivo de sesiones. Si falla el
    /// último paso, el ssh_config vuelve a como estaba: o se guardan los dos o ninguno. Devuelve el error, o nil.
    /// Síncrono: desde la app, `saveInBackground`.
    public func save(to url: URL = SessionFile.defaultURL, including sshConfig: URL, backup: DataBackup,
                     validate: Bool = true) -> String? {
        save(to: url, including: sshConfig, backup: backup, validate: validate, install: Self.install)
    }

    /// (`install`: para los tests, que hacen fallar el último paso)
    func save(to url: URL, including sshConfig: URL, backup: DataBackup, validate: Bool,
              install: (URL, URL, Int) -> String?) -> String? {
        let (prepared, err) = prepare(url, validate: validate)
        guard let tmp = prepared else { return err }
        let fm = FileManager.default
        let plan: IncludePlan
        do { plan = try Self.includePlan(sshConfig) } catch {
            try? fm.removeItem(at: tmp)
            return L("no se ha podido añadir el Include a \(AppPaths.tilde(sshConfig.path)): no se ha guardado nada")
        }
        guard backup.backupSessionsBeforeSave() else {
            try? fm.removeItem(at: tmp)
            return L("no se ha podido hacer la copia de seguridad de las sesiones (\(AppPaths.tilde(backup.sessionsBak.path))): no se ha guardado nada")
        }
        do { try Self.applyInclude(plan) } catch {
            try? fm.removeItem(at: tmp)
            return L("no se ha podido añadir el Include a \(AppPaths.tilde(sshConfig.path)): no se ha guardado nada")
        }
        if let err = install(tmp, url, sessions.count) {
            try? fm.removeItem(at: tmp)
            return Self.undoInclude(plan) ? err
                : L("\(err) · y \(AppPaths.tilde(plan.target.path)) no ha vuelto a como estaba: tienes su copia en .anterior")
        }
        return nil
    }

    /// Lo mismo, fuera del hilo principal («ssh -G» puede tardar hasta `checkTimeout`: la ventana no se congela).
    public func saveInBackground(to url: URL = SessionFile.defaultURL, including sshConfig: URL, backup: DataBackup,
                                 validate: Bool = true) async -> String? {
        let file = self
        return await Task.detached(priority: .userInitiated) {
            file.save(to: url, including: sshConfig, backup: backup, validate: validate)
        }.value
    }
}
