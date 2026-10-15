import Foundation

/// Importar sesiones de tu programa anterior (como «importar» de NetDeck): SecureCRT (Config/Sessions o un .ini),
/// MobaXterm (.mxtsessions / MobaXterm.ini), PuTTY (.reg), electerm (.json), CSV del inventario, ~/.ssh/config y el JSON
/// que exporta el propio gestor (`SessionExport`).
/// Las carpetas pasan a ser grupos; los nombres repetidos quedan como core-01-2. Nunca se importa ninguna contraseña.
public enum SessionImporter {
    public struct Found: Hashable, Sendable {
        public var group: String
        public var original: String
        public var host: String
        public var user = ""
        public var port = "22"
        /// La referencia a otra sesión del mismo archivo (su ruta o nombre) o «usuario@host:puerto».
        public var jump = ""
        public var ref: String?
        public var summary = ""
        public var telnet = false
        public var keyFile = ""
        public var legacy = false
        public var extra: [String] = []
        /// SFTP, FTP, serie, local… (telnet también vale con `telnet`).
        public var kind = SessionProfile.Transport.ssh
        public var serial: SerialLine?
        public var notes: [String] = []
    }

    public struct Result: Sendable {
        public var format: String
        public var sessions: [EditableSession]
        /// (nombre, por qué)
        public var skipped: [(String, String)]
    }

    public static var secureCRTFolder: URL {
        AppPaths.home.appendingPathComponent("Library/Application Support/VanDyke/SecureCRT/Config/Sessions")
    }

    // lo que puede ir en el ssh_config: un salto de línea o un espacio colaría otra opción (ProxyCommand…)
    // (sin «-» al principio: llegaría a ssh como una opción)
    static let hostRule = Pattern(#"^[A-Za-z0-9._:%][A-Za-z0-9._:%-]*$"#, ignoreCase: false)
    static let userRule = Pattern(#"^[A-Za-z0-9._@\\][A-Za-z0-9._@\\-]*$"#, ignoreCase: false)
    static let moba = ["109": "SSH", "98": "Telnet", "91": "RDP", "128": "VNC", "130": "FTP", "131": "Serie"]

    /// Lo que se ve importable en este Mac: SecureCRT, ~/.ssh/config y exports en Descargas/Escritorio/Documentos.
    public static func suggestions() -> [(String, URL)] {
        let fm = FileManager.default
        var out: [(String, URL)] = []
        if fm.fileExists(atPath: secureCRTFolder.path) { out.append((L("SecureCRT de este Mac"), secureCRTFolder)) }
        for dir in ["Downloads", "Desktop", "Documents"] {
            let d = AppPaths.home.appendingPathComponent(dir)
            for f in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] {
                let n = f.lastPathComponent.lowercased()
                if n.hasSuffix(".mxtsessions") || n == "mobaxterm.ini" || (n.hasSuffix(".reg") && n.contains("putty")) {
                    out.append(("\(f.lastPathComponent) (\(dir))", f))
                }
            }
        }
        return out
    }

    // MARK: - leer

    public static func read(_ url: URL, existing: [EditableSession]) -> Result {
        let (format, found, skipped) = parse(url)
        let (sessions, more) = prepare(found, existing: existing)
        return Result(format: format, sessions: sessions, skipped: skipped + more)
    }

    static func parse(_ url: URL) -> (String, [Found], [(String, String)]) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { let r = secureCRT(url); return ("SecureCRT", r.0, r.1) }
        let name = url.lastPathComponent.lowercased()
        let text = Self.text(of: url)
        let head = String(text.prefix(20000))
        if name.hasSuffix(".mxtsessions") || head.lowercased().contains("[bookmarks") {
            let (f, s) = mobaXterm(text); return ("MobaXterm", f, s)
        }
        if name.hasSuffix(".reg"), head.contains("SimonTatham") { let (f, s) = putty(text); return ("PuTTY", f, s) }
        if name.hasSuffix(".json"), head.contains(SessionExport.format), let f = SessionExport.found(text) {
            return ("Terminal NetDeck", f, [])
        }
        if name.hasSuffix(".json"), head.contains("\"bookmarks\"") { let (f, s) = electerm(text); return ("electerm", f, s) }
        if name.hasSuffix(".ini"), head.contains("S:\"Hostname\"") { let (f, s) = secureCRT(url); return ("SecureCRT", f, s) }
        if name.hasSuffix(".csv") || name.hasSuffix(".txt") { return ("CSV", csv(text), []) }
        let file = SessionFile(text: text)
        if !file.sessions.isEmpty {
            return ("ssh_config", file.sessions.map {
                Found(group: $0.group == "General" ? "ssh_config" : $0.group, original: $0.name,
                      host: $0.host.isEmpty && $0.kind.isNetwork ? $0.name : $0.host, user: $0.user, port: $0.port,
                      jump: $0.jump, ref: $0.name, summary: $0.summary, telnet: $0.telnet, keyFile: $0.keyFile,
                      legacy: $0.legacy, extra: $0.extra, kind: $0.kind, serial: $0.kind == .serial ? $0.serial : nil,
                      notes: $0.notes)
            }, [])
        }
        return ("desconocido", [], [(url.lastPathComponent, L("no reconozco el formato"))])
    }

    static let maxFileSize = 20_000_000

    /// Opciones de ssh que se traen al importar: sólo las que ni ejecutan nada, ni abren puertos, ni tocan la
    /// verificación de las claves de host, ni abren otro bloque (Host/Match). Las demás se quitan: un ssh_config o un
    /// export ajeno podría ejecutar algo al conectar o cambiar ssh en todo el Mac. Las tuyas en tu propio ssh_config
    /// (o escritas en el gestor) no se tocan.
    static let allowedOptions: Set<String> = [
        "serveraliveinterval", "serveralivecountmax", "tcpkeepalive", "connecttimeout", "connectionattempts",
        "compression", "ciphers", "kexalgorithms", "hostkeyalgorithms", "macs", "pubkeyacceptedalgorithms",
        "pubkeyacceptedkeytypes", "casignaturealgorithms", "preferredauthentications", "pubkeyauthentication",
        "passwordauthentication", "kbdinteractiveauthentication", "challengeresponseauthentication",
        "gssapiauthentication", "identitiesonly", "identityfile", "addkeystoagent", "usekeychain", "loglevel",
        "requesttty", "hostkeyalias", "checkhostip", "addressfamily", "ipqos", "numberofpasswordprompts",
        "rekeylimit", "escapechar", "hashknownhosts", "fingerprinthash", "visualhostkey",
    ]

    static let reservedNotes = ["grupo", "clave", "tipo", "serie", "telnet", "desc", "antiguo"]

    /// Una opción por línea: cada elemento se parte por sus saltos de línea («ServerAliveInterval 5\nProxyCommand …»
    /// serían dos líneas en el ssh_config), sin caracteres de control, y sólo quedan las de `allowedOptions`.
    static func safeExtra(_ lines: [String], session: String) -> [String] {
        lines.flatMap { $0.split(whereSeparator: \.isNewline) }
            .map { $0.replacingOccurrences(of: #"[\x00-\x1f\x7f]"#, with: " ", options: .regularExpression).trimmed }
            .filter { line in
                guard !line.isEmpty, !line.hasPrefix("#") else { return false }
                let key = SSHConfigParser.option(line)?.0 ?? ""
                guard !allowedOptions.contains(key) else { return true }
                DebugLog.log("importar", "«\(session)»: quitada la opción «\(key)» (no es de las que se importan)")
                return false
            }
    }

    /// UTF-16 (los .reg), UTF-8 con o sin BOM, o Windows-1252.
    static func text(of url: URL) -> String {
        // (un archivo de sesiones no ocupa decenas de megas: si es tan grande no es eso, y no se carga entero)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size <= maxFileSize, let d = try? Data(contentsOf: url) else { return "" }
        if d.starts(with: [0xFF, 0xFE]) || d.starts(with: [0xFE, 0xFF]) { return String(data: d, encoding: .utf16) ?? "" }
        if let s = String(data: d, encoding: .utf8) { return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s }
        return String(data: d, encoding: .windowsCP1252) ?? ""
    }

    /// Config/Sessions: un .ini por sesión, la carpeta es el grupo. S:"Hostname"=…, D:"[SSH2] Port"=00000016 (hex),
    /// S:"Firewall Name"=Session:Carpeta/salto, S:"Protocol Name"=SSH2|Telnet.
    static func secureCRT(_ url: URL) -> ([Found], [(String, String)]) {
        let fm = FileManager.default
        var root = url
        var files: [URL] = []
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            for sub in ["Sessions", "Config/Sessions"] where fm.fileExists(atPath: url.appendingPathComponent(sub).path) {
                root = url.appendingPathComponent(sub)
            }
            let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
            while let f = e?.nextObject() as? URL, files.count < 20_000 {
                // (sin seguir enlaces: no se sale de la carpeta elegida)
                if (try? f.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { e?.skipDescendants(); continue }
                if f.pathExtension == "ini", !f.lastPathComponent.hasPrefix("__") { files.append(f) }
            }
            files.sort { $0.path < $1.path }
        } else {
            files = [url]
            root = url.deletingLastPathComponent()
        }
        let line = Pattern(#"^([SD]):"([^"]+)"=(.*)$"#, ignoreCase: false)
        var out: [Found] = []
        var skipped: [(String, String)] = []
        for f in files {
            var rel = String(f.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            rel = String(rel.dropLast(4))
            if rel == "Default" { continue }
            var v: [String: String] = [:]
            for l in text(of: f).components(separatedBy: .newlines) {
                let l = l.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                guard let k = line.group(2, in: l), let t = line.group(1, in: l) else { continue }
                let raw = line.group(3, in: l) ?? ""
                v[k] = t == "S" ? raw : (Int(raw.trimmed, radix: 16).map(String.init) ?? "")
            }
            let name = (rel as NSString).lastPathComponent
            let dir = (rel as NSString).deletingLastPathComponent
            let proto = v["Protocol Name"] ?? "SSH2"
            let telnet = proto.lowercased() == "telnet"
            guard proto.uppercased().hasPrefix("SSH") || telnet else { skipped.append((rel, proto)); continue }
            var jump = v["Firewall Name"] ?? ""
            jump = jump.hasPrefix("Session:") ? String(jump.dropFirst(8)).replacingOccurrences(of: "\\", with: "/") : ""
            let port = v["[SSH2] Port"].flatMap { $0.isEmpty ? nil : $0 } ?? v["Port"].flatMap { $0.isEmpty ? nil : $0 }
            out.append(Found(group: dir.isEmpty ? "SecureCRT" : dir, original: name, host: v["Hostname"] ?? "",
                             user: v["Username"] ?? "", port: port ?? (telnet ? "23" : "22"), jump: jump, ref: rel,
                             telnet: telnet))
        }
        return (out, skipped)
    }

    /// [Bookmarks], [Bookmarks_1]…: SubRep=Carpeta\Sub es el grupo y «nombre=#109#0%host%puerto%usuario%…» una
    /// sesión (109 = SSH, 98 = Telnet).
    static func mobaXterm(_ text: String) -> ([Found], [(String, String)]) {
        var out: [Found] = []
        var skipped: [(String, String)] = []
        var inside = false
        var group = "MobaXterm"
        for raw in text.components(separatedBy: .newlines) {
            let l = raw.trimmed
            if l.hasPrefix("["), l.hasSuffix("]") {
                inside = l.dropFirst().lowercased().hasPrefix("bookmarks")
                group = "MobaXterm"
                continue
            }
            guard inside, let eq = l.firstIndex(of: "=") else { continue }
            let k = String(l[..<eq]), v = String(l[l.index(after: eq)...])
            if k == "SubRep" {
                let g = v.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                group = g.isEmpty ? "MobaXterm" : g
                continue
            }
            guard v.hasPrefix("#") else { continue }
            let parts = v.components(separatedBy: "#")
            let type = parts.count > 2 ? parts[1] : ""
            let fields = parts.count > 2 ? parts[2].components(separatedBy: "%") : []
            guard type == "109" || type == "98", fields.count >= 4 else {
                skipped.append((k, moba[type] ?? L("tipo \(type)")))
                continue
            }
            let user = type == "109" ? fields[3] : ""
            var name = k
            if !user.isEmpty, name.hasSuffix(" (\(user))") { name = String(name.dropLast(user.count + 3)) }   // «core-01 (admin)»
            out.append(Found(group: group, original: name, host: fields[1], user: user, port: fields[2], ref: k,
                             telnet: type == "98"))
        }
        return (out, skipped)
    }

    /// El .reg: [HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\core%2001] con "HostName", "UserName",
    /// "PortNumber"=dword:00000016 y "Protocol".
    static func putty(_ text: String) -> ([Found], [(String, String)]) {
        let header = Pattern(#"^\[HKEY_[^\]]*\\Sessions\\([^\]\\]+)\]$"#, ignoreCase: false)
        let value = Pattern(#"^"([^"]+)"=(?:"((?:[^"\\]|\\.)*)"|dword:([0-9a-fA-F]+))$"#, ignoreCase: false)
        var sessions: [[String: String]] = []
        var cur: Int?
        for raw in text.components(separatedBy: .newlines) {
            let l = raw.trimmed
            if let n = header.group(1, in: l) {
                sessions.append(["_": n.removingPercentEncoding ?? n])
                cur = sessions.count - 1
            } else if l.hasPrefix("[") {
                cur = nil
            } else if let i = cur, let k = value.group(1, in: l) {
                if let s = value.group(2, in: l) {
                    sessions[i][k] = s.replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression)
                } else if let h = value.group(3, in: l) {
                    sessions[i][k] = Int(h, radix: 16).map(String.init) ?? ""
                }
            }
        }
        var out: [Found] = []
        var skipped: [(String, String)] = []
        for v in sessions where v["_"] != "Default Settings" {
            let proto = v["Protocol"] ?? "ssh"
            guard proto == "ssh" || proto == "telnet" else { skipped.append((v["_"]!, proto)); continue }
            var host = v["HostName"] ?? "", user = v["UserName"] ?? ""
            if let at = host.lastIndex(of: "@") {
                if user.isEmpty { user = String(host[..<at]) }
                host = String(host[host.index(after: at)...])
            }
            out.append(Found(group: "PuTTY", original: v["_"]!, host: host, user: user,
                             port: v["PortNumber"] ?? (proto == "telnet" ? "23" : "22"), ref: v["_"], telnet: proto == "telnet"))
        }
        return (out, skipped)
    }

    /// El export de marcadores de electerm (trae las contraseñas en claro: aquí no se leen).
    static func electerm(_ text: String) -> ([Found], [(String, String)]) {
        guard let any = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return ([], []) }
        let dict = any as? [String: Any]
        let marks = (any as? [[String: Any]]) ?? (dict?["bookmarks"] as? [[String: Any]]) ?? []
        let groups = (dict?["bookmarkGroups"] as? [[String: Any]]) ?? []
        var title: [String: String] = [:], parent: [String: String] = [:], of: [String: String] = [:]
        for g in groups {
            guard let id = g["id"] as? String else { continue }
            title[id] = g["title"] as? String ?? ""
            for s in g["bookmarkGroupIds"] as? [String] ?? [] { parent[s] = id }
        }
        func path(_ id: String?) -> String {
            var parts: [String] = []
            var g = id
            while let x = g, let t = title[x], parts.count < 8 {
                parts.insert(t, at: 0)
                g = parent[x]
            }
            return parts.filter { !$0.isEmpty && $0 != "default" }.joined(separator: "/")
        }
        for g in groups { for b in g["bookmarkIds"] as? [String] ?? [] { of[b] = path(g["id"] as? String) } }
        var out: [Found] = []
        var skipped: [(String, String)] = []
        for b in marks {
            let host = "\(b["host"] ?? "")"
            let name = (b["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? host
            let type = ((b["type"] as? String) ?? "ssh").lowercased()
            guard type == "ssh" || type == "ssh2" || type == "telnet" else { skipped.append((name, type)); continue }
            let g = (b["id"] as? String).flatMap { of[$0] }
            out.append(Found(group: g.flatMap { $0.isEmpty ? nil : $0 } ?? "electerm", original: name, host: host,
                             user: (b["username"] as? String) ?? (b["user"] as? String) ?? "",
                             port: b["port"].map { "\($0)" } ?? "22", ref: name, telnet: type == "telnet"))
        }
        return (out, skipped)
    }

    static let columns: [String: String] = [
        "grupo": "grupo", "group": "grupo", "carpeta": "grupo", "folder": "grupo",
        "nombre": "nombre", "name": "nombre", "sesion": "nombre", "session": "nombre", "equipo": "nombre",
        "host": "host", "hostname": "host", "ip": "host", "direccion": "host", "address": "host",
        "usuario": "usuario", "user": "usuario", "username": "usuario", "puerto": "puerto", "port": "puerto",
        "salto": "salto", "jump": "salto", "proxyjump": "salto", "bastion": "salto",
        "descripcion": "desc", "description": "desc", "desc": "desc",
        "tipo": "tipo", "type": "tipo", "protocolo": "tipo", "protocol": "tipo",
    ]

    /// CSV del inventario (de Excel, con «;» o «,»): grupo;nombre;host;usuario;puerto;salto, o con cabecera en cualquier
    /// orden (también en inglés).
    static func csv(_ text: String) -> [Found] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmed.isEmpty }
        guard let first = lines.first else { return [] }
        let sep: Character = [";", ",", "\t"].max { a, b in first.filter { $0 == a }.count < first.filter { $0 == b }.count }!
        func cells(_ l: String) -> [String] {
            var out: [String] = [], cur = "", quoted = false
            for ch in l {
                if ch == "\"" { quoted.toggle() } else if ch == sep, !quoted { out.append(cur.trimmed); cur = "" } else { cur.append(ch) }
            }
            return out + [cur.trimmed]
        }
        var rows = lines.map(cells)
        var head = rows[0].map { columns[$0.folding(options: .diacriticInsensitive, locale: nil).lowercased().trimmed] }
        if head.contains("host") { rows.removeFirst() } else { head = ["grupo", "nombre", "host", "usuario", "puerto", "salto", "desc", "tipo"] }
        return rows.map { r in
            var v: [String: String] = [:]
            for (i, c) in head.enumerated() { if let c, i < r.count { v[c] = r[i] } }
            let host = v["host"] ?? ""
            var f = Found(group: v["grupo"].flatMap { $0.isEmpty ? nil : $0 } ?? "Importadas",
                          original: v["nombre"].flatMap { $0.isEmpty ? nil : $0 } ?? host, host: host,
                          user: v["usuario"] ?? "", port: v["puerto"].flatMap { $0.isEmpty ? nil : $0 } ?? "22",
                          jump: v["salto"] ?? "", ref: v["nombre"], summary: v["desc"] ?? "")
            // (del CSV sólo los de red: serie y local necesitan más datos que sus columnas)
            if let k = v["tipo"].flatMap(SessionProfile.Transport.init(annotation:)), k.isNetwork { f.kind = k }
            return f
        }
    }

    // MARK: - a sesiones de NetDeck

    /// «Almería Core 1» → «Almeria-Core-1» (es un «Host» de ssh: sin espacios ni comodines).
    public static func validName(_ t: String) -> String {
        var s = t.trimmed.folding(options: .diacriticInsensitive, locale: nil)
        s = s.replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[^A-Za-z0-9._@:+-]"#, with: "-", options: .regularExpression)
        s = s.replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return s.isEmpty ? "sesion" : s
    }

    /// Valida cada campo, quita las que ya tienes (mismo usuario@host:puerto) y las repetidas, da nombres únicos y
    /// resuelve los saltos (a otra importada, a una que ya tenías, o «usuario@host:puerto»).
    static func prepare(_ found: [Found], existing: [EditableSession]) -> ([EditableSession], [(String, String)]) {
        var have: [String: String] = [:]
        for s in existing {
            switch s.kind {
            case .serial: have["serie|\(s.serial.device)"] = s.name
            case .local: have["local|\(s.name.lowercased())"] = s.name
            case .ssh, .telnet, .sftp, .ftp:
                have["\(s.kind == .ssh ? "" : s.kind.annotation + "|")\(s.host.lowercased())|\(s.user)|\(s.port)"] = s.name
            }
        }
        var used = Set(existing.map { $0.name.lowercased() })
        var out: [(EditableSession, String)] = []
        var skipped: [(String, String)] = []
        var byRef: [String: String] = [:]
        for e in found {
            let kind: SessionProfile.Transport = e.telnet ? .telnet : e.kind
            let host = e.host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let key: String
            switch kind {
            case .serial:
                guard let line = e.serial, line.isValid else { skipped.append((e.original, L("puerto serie no válido"))); continue }
                key = "serie|\(line.device)"
            case .local:
                key = "local|\(e.original.lowercased())"
            case .ssh, .telnet, .sftp, .ftp:
                guard !host.isEmpty else { skipped.append((e.original, L("sin host"))); continue }
                guard hostRule.matches(host), e.user.isEmpty || userRule.matches(e.user),
                      let p = Int(e.port), (1...65535).contains(p) else {
                    skipped.append((e.original, L("host, usuario o puerto no válidos")))
                    continue
                }
                key = "\(kind == .ssh ? "" : kind.annotation + "|")\(host.lowercased())|\(e.user)|\(e.port)"
            }
            if let n = have[key] {
                if let r = e.ref, byRef[r] == nil { byRef[r] = n }
                skipped.append((e.original, L("ya la tienes como «\(n)»")))
                continue
            }
            let base = validName(e.original)
            var name = base, n = 2
            while used.contains(name.lowercased()) { name = "\(base)-\(n)"; n += 1 }
            used.insert(name.lowercased())
            have[key] = name
            var s = EditableSession(group: e.group.replacingOccurrences(of: #"[\x00-\x1f\x7f#'"`$\\]"#, with: "",
                                                                         options: .regularExpression).trimmed,
                                    name: name)
            if s.group.isEmpty { s.group = "Importadas" }
            s.summary = e.summary.replacingOccurrences(of: #"[\x00-\x1f\x7f]"#, with: "", options: .regularExpression).trimmed
            if s.summary.isEmpty, name != e.original { s.summary = String(e.original.prefix(60)) }
            let clean = { (t: String) in t.replacingOccurrences(of: #"[\x00-\x1f\x7f]"#, with: "", options: .regularExpression).trimmed }
            s.kind = kind
            if kind.isNetwork {
                s.host = host
                s.user = e.user
                s.port = e.port
            }
            if kind == .serial, let line = e.serial { s.serial = line }
            // (una nota «@clave X» o «@tipo local» cambiaría la sesión al volver a leerla: ésas no se traen)
            s.notes = e.notes.map(clean).filter { n in
                !n.isEmpty && !Self.reservedNotes.contains { n.lowercased().hasPrefix("@" + $0) }
            }
            // (una ruta con comillas o saltos de línea rompería el bloque: se descarta)
            s.keyFile = e.keyFile.contains(where: { $0 == "\"" || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }) ? "" : e.keyFile
            s.legacy = e.legacy
            s.extra = Self.safeExtra(e.extra, session: name)
            if let r = e.ref, byRef[r] == nil { byRef[r] = name }
            out.append((s, e.jump))
        }
        let existingNames = Set(existing.map(\.name))
        let endpoint = Pattern(#"^(?:[A-Za-z0-9._\\-]+@)?[A-Za-z0-9._:%-]+$"#, ignoreCase: false)
        let sessions = out.map { s, j -> EditableSession in
            var s = s
            if j.isEmpty { return s }
            if let n = byRef[j] { s.jump = n } else if existingNames.contains(j) || (endpoint.matches(j) && Endpoint(parsing: j) != nil) { s.jump = j }
            return s
        }
        return (sessions, skipped)
    }
}
