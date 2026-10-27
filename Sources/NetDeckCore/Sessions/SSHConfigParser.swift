import Foundation

/// Lector de ssh_config con las mismas reglas que ssh: bloques «Host» con comodines y «!negación», el primer valor
/// gana, «Include» (relativo a ~/.ssh) y «Match» ignorado. Más las anotaciones de NetDeck en comentarios:
///   # @grupo X          las sesiones que vienen detrás van al grupo X (un comentario no cierra el bloque)
///   # @clave-grupo X    contraseña con nombre del grupo
///   # @clave X          (dentro del bloque) contraseña con nombre de esa sesión
///   # @desc …           (dentro del bloque) descripción
///   # @antiguo          (dentro del bloque) algoritmos antiguos
///   # @telnet           (dentro del bloque) se entra por telnet (a través del salto, si lo hay)
///   # @tipo X           (dentro del bloque) sftp, ftp, serie o local (sin él: ssh)
///   # @serie DEV VEL 8N1  (dentro del bloque) el puerto serie de una sesión «@tipo serie»
///   # @fuente · @tema · @scrollback · @teclado · @prompt   (dentro del bloque) su perfil de terminal (`TerminalProfile`)
public struct SSHConfigParser: Sendable {
    public init() {}

    struct Block {
        var patterns: [String]
        var options: [(key: String, value: String)] = []
        var notes: [String: String] = [:]
        var group: String?
    }

    public func parse(contentsOf url: URL) throws -> [SessionProfile] {
        parse(try String(contentsOf: url, encoding: .utf8), sshDirectory: url.deletingLastPathComponent())
    }

    public func parse(_ text: String, sshDirectory: URL? = nil) -> [SessionProfile] {
        var groupCredentials: [String: String] = [:]
        var group: String?
        let blocks = self.blocks(text, sshDirectory: sshDirectory, depth: 0, group: &group, groupCredentials: &groupCredentials)
        var seen = Set<String>()
        var out: [SessionProfile] = []
        for b in blocks {
            for alias in b.patterns where !Self.isPattern(alias) && seen.insert(alias).inserted {
                var p = profile(alias, blocks)
                if p.namedCredential == nil, let g = p.group { p.namedCredential = groupCredentials[g] }
                if p.namedCredential == "-" { p.namedCredential = nil } // (propia del equipo: tampoco hereda la del grupo)
                out.append(p)
            }
        }
        return out
    }

    // MARK: - bloques

    func blocks(_ text: String, sshDirectory: URL?, depth: Int,
                group: inout String?, groupCredentials: inout [String: String]) -> [Block] {
        var out = [Block(patterns: ["*"])]               // lo de antes del primer «Host» vale para todas
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmed
            if line.hasPrefix("#") {
                guard let (k, v) = Self.note(line) else { continue }
                switch k {
                case "grupo": group = v.isEmpty ? nil : v
                case "clave-grupo": if let g = group { groupCredentials[g] = v }
                default: if out[out.count - 1].notes[k] == nil { out[out.count - 1].notes[k] = v }
                }
                continue
            }
            guard let (key, value) = Self.option(line) else { continue }
            switch key {
            case "include" where depth < 8:
                for url in Self.includeFiles(Self.directive(line)?.1 ?? value, sshDirectory: sshDirectory) {
                    guard let t = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    out += blocks(t, sshDirectory: sshDirectory, depth: depth + 1,
                                  group: &group, groupCredentials: &groupCredentials)
                }
            case "host":
                out.append(Block(patterns: value.split(whereSeparator: \.isWhitespace).map(String.init), group: group))
            case "match":
                out.append(Block(patterns: []))          // no se sabe a qué equipos va sin conectar: se salta
            default:
                out[out.count - 1].options.append((key, value))
            }
        }
        return out
    }

    func profile(_ alias: String, _ blocks: [Block]) -> SessionProfile {
        var opt: [String: String] = [:]
        for b in blocks where Self.matches(alias, b.patterns) {
            for (k, v) in b.options where opt[k] == nil { opt[k] = v }
        }
        let own = blocks.filter { $0.patterns.contains(alias) }        // anotaciones: sólo las de su bloque
        func note(_ k: String) -> String? { own.lazy.compactMap { $0.notes[k] }.first }
        var jumps = (opt["proxyjump"] ?? "").split(separator: ",").map { String($0).trimmed }
        if jumps == ["none"] { jumps = [] }
        if jumps.isEmpty, let pc = opt["proxycommand"], let j = Self.jumpOfProxyCommand(pc) { jumps = [j] }
        var p = SessionProfile(
            name: alias,
            hostName: opt["hostname"].map { $0.replacingOccurrences(of: "%h", with: alias) },
            user: opt["user"],
            port: opt["port"].flatMap(Int.init),
            proxyJump: jumps,
            transport: note("telnet") != nil ? .telnet : note("tipo").flatMap(SessionProfile.Transport.init(annotation:)) ?? .ssh,
            group: own.first?.group,
            summary: note("desc"),
            namedCredential: note("clave"),
            legacy: note("antiguo") != nil,
            serial: note("serie").flatMap(SerialLine.init(annotation:)))
        p.hasProxyCommand = opt["proxycommand"].map { $0.lowercased() != "none" } ?? false
        for k in TerminalProfile.keys { if let v = note(k) { p.terminal.read(k, v, session: alias) } }
        return p
    }

    // MARK: - utilidades

    static func isPattern(_ s: String) -> Bool { s.contains(where: { "*?!".contains($0) }) }

    /// ssh: no vale si encaja una «!negación»; si no, vale si encaja alguno.
    static func matches(_ alias: String, _ patterns: [String]) -> Bool {
        var hit = false
        for p in patterns {
            if p.hasPrefix("!") {
                if fnmatch(String(p.dropFirst()), alias, 0) == 0 { return false }
            } else if fnmatch(p, alias, 0) == 0 {
                hit = true
            }
        }
        return hit
    }

    /// «Clave valor», «Clave=valor», «Clave = "valor"» → ("clave", "valor").
    static func option(_ line: String) -> (String, String)? {
        guard var (key, value) = directive(line) else { return nil }
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
        return (key, value)
    }

    /// La directiva tal cual: («clave» en minúsculas, valor sin tocar las comillas). nil si es un comentario o está vacía.
    static func directive(_ line: String) -> (String, String)? {
        let line = line.trimmed
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        let i = line.firstIndex(where: { $0 == "=" || $0.isWhitespace }) ?? line.endIndex
        let key = line[..<i].lowercased()
        var rest = line[i...].drop(while: { $0 == " " || $0 == "\t" })
        if rest.first == "=" { rest = rest.dropFirst() }
        let value = String(rest).trimmed
        return key.isEmpty || value.isEmpty ? nil : (key, value)
    }

    /// Los argumentos de un valor como los separa ssh: por espacios, «"con espacios"» entre comillas, y lo que va tras
    /// un «#» al empezar un argumento es comentario.
    static func arguments(_ value: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false, has = false
        for c in value {
            if c == "\"" { quoted.toggle(); has = true; continue }
            if !quoted, c == "#", !has { break }
            if !quoted, c == " " || c == "\t" {
                if has { out.append(cur) }
                cur = ""; has = false
                continue
            }
            cur.append(c); has = true
        }
        if has { out.append(cur) }
        return out
    }

    /// Las rutas de un «Include» antes de los comodines, como ssh: «~» y relativas a ~/.ssh (o `sshDirectory`).
    /// Las usan el lector y `SessionFile.hasInclude`: los dos entienden igual la misma línea.
    static func includePaths(_ value: String, sshDirectory: URL?) -> [String] {
        let base = sshDirectory ?? AppPaths.home.appendingPathComponent(".ssh")
        return arguments(value).map { tok in
            let path = AppPaths.expand(tok)
            return URL(fileURLWithPath: path.hasPrefix("/") ? path : base.appendingPathComponent(path).path).standardizedFileURL.path
        }
    }

    /// «# @clave AD ES» → ("clave", "AD ES"); «# @antiguo» → ("antiguo", "").
    static func note(_ line: String) -> (String, String)? {
        let re = Pattern(#"^#\s*@([A-Za-z-]+)\s*(.*)$"#, ignoreCase: false)
        guard let k = re.group(1, in: line) else { return nil }
        return (k.lowercased(), (re.group(2, in: line) ?? "").trimmed)
    }

    /// «ssh -q -W %h:%p bastion» → «bastion».
    static func jumpOfProxyCommand(_ cmd: String) -> String? {
        let t = cmd.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let s = t.firstIndex(where: { ($0 as NSString).lastPathComponent == "ssh" }), t.contains("-W") else { return nil }
        var i = s + 1
        while i < t.count {
            if t[i].hasPrefix("-") {
                if t[i].count == 2, "WpliFoJ".contains(t[i].last!) { i += 1 }
            } else {
                return t[i]
            }
            i += 1
        }
        return nil
    }

    /// Archivos de un «Include» (`includePaths` con sus comodines).
    static func includeFiles(_ value: String, sshDirectory: URL?) -> [URL] {
        includePaths(value, sshDirectory: sshDirectory).flatMap { path -> [URL] in
            var g = glob_t()
            defer { globfree(&g) }
            guard glob(path, 0, nil, &g) == 0 else { return [] }
            return (0..<Int(g.gl_pathc)).compactMap { i in
                g.gl_pathv[i].map { URL(fileURLWithPath: String(cString: $0)) }
            }
        }
    }
}
