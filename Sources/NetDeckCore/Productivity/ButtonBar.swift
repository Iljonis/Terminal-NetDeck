import Foundation

/// Un botón de la barra (botones.txt de NetDeck): «Grupo :: modo :: Nombre [F5] :: comando».
public struct CommandButton: Hashable, Sendable, Identifiable {
    public enum Mode: String, CaseIterable, Sendable {
        /// Escribe la orden y pulsa Intro (varias: separadas con « ;; », una a una esperando al equipo).
        case run
        /// Sólo la escribe, para que la completes.
        case type
        /// La contraseña del Llavero con ese nombre + Intro (sólo donde piden «Password:»).
        case pass
        /// «usuario / nombre-contraseña»: usuario, Intro y la contraseña cuando la pidan.
        case login
        /// Abre una pestaña con esa sesión del ssh_config.
        case session = "sesion"

        public var title: String {
            switch self {
            case .run: L("Ejecutar")
            case .type: L("Escribir")
            case .pass: L("Contraseña")
            case .login: "Login"
            case .session: L("Sesión")
            }
        }
    }

    public let id = UUID()
    public var group: String
    public var mode: Mode
    /// Sin la tecla.
    public var name: String
    public var command: String
    /// «F5», «S-F5» (Mayús), «M-F5» (Opción), «C-F5» (Ctrl).
    public var hotkey: String?

    public init(group: String, mode: Mode, name: String, command: String, hotkey: String? = nil) {
        self.group = group
        self.mode = mode
        self.name = name
        self.command = command
        self.hotkey = hotkey
    }

    public static func == (a: Self, b: Self) -> Bool {
        (a.group, a.mode, a.name, a.command, a.hotkey) == (b.group, b.mode, b.name, b.command, b.hotkey)
    }

    public func hash(into h: inout Hasher) { h.combine(name); h.combine(command) }

    /// Las órdenes de un «run» (« ;; » separa varias).
    public var lines: [String] {
        command.components(separatedBy: " ;; ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Huecos «{{interfaz}}», «{{vlan=100}}» (con su valor por defecto), sin repetir.
    public var holes: [(name: String, value: String)] {
        var seen = Set<String>()
        return ButtonFile.hole.matchGroups(in: command).compactMap { m in
            guard let n = m.groups[0], seen.insert(n).inserted else { return nil }
            return (n, m.groups[1] ?? "")
        }
    }

    /// La orden con los huecos rellenos.
    public func filled(_ values: [String: String]) -> String {
        var out = command
        let defaults = Dictionary(holes.map { ($0.name, $0.value) }, uniquingKeysWith: { a, _ in a })
        for m in ButtonFile.hole.matchGroups(in: command).reversed() {
            guard let n = m.groups[0], let r = Range(m.range, in: out) else { continue }
            out.replaceSubrange(r, with: values[n] ?? defaults[n] ?? "")
        }
        return out
    }
}

/// botones.txt: las líneas de botones y los comentarios de arriba (se conservan al guardar).
public struct ButtonFile: Sendable {
    public var header: [String] = []
    public var buttons: [CommandButton] = []
    /// Líneas mal escritas (se saltan con un aviso, como NetDeck).
    public var problems: [String] = []

    static let hole = Pattern(#"\{\{\s*([^{}=]+?)\s*(?:=([^{}]*))?\}\}"#, ignoreCase: false)
    static let key = Pattern(#"\s*\[((?:[SMC]-)*F(?:[1-9]|1[0-2]))\]$"#, ignoreCase: false)

    /// El de NetDeck si está; si no, el de la app.
    public static var netdeckURL: URL { AppPaths.netdeck.appendingPathComponent("botones.txt") }
    public static var appURL: URL { AppPaths.support.appendingPathComponent("botones.txt") }
    public static var defaultURL: URL {
        FileManager.default.fileExists(atPath: netdeckURL.path) ? netdeckURL : appURL
    }

    public init() {}

    public init(contentsOf url: URL) throws { self.init(text: try String(contentsOf: url, encoding: .utf8)) }

    public init(text: String) {
        var keys = Set<String>()
        var seenButton = false
        for (n, raw) in text.components(separatedBy: .newlines).enumerated() {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") {
                if !seenButton, t.hasPrefix("#") || !header.isEmpty { header.append(raw) }
                continue
            }
            seenButton = true
            let parts = raw.components(separatedBy: " :: ")
            guard parts.count >= 4 else {
                problems.append(L("línea \(n + 1): el formato es «Grupo :: modo :: Nombre :: comando»"))
                continue
            }
            let group = parts[0].trimmingCharacters(in: .whitespaces)
            let modeText = parts[1].trimmingCharacters(in: .whitespaces)
            var name = parts[2].trimmingCharacters(in: .whitespaces)
            var command = parts[3...].joined(separator: " :: ")
            guard let mode = CommandButton.Mode(rawValue: modeText) else {
                problems.append(L("línea \(n + 1): modo «\(modeText)» (usa run, type, pass, login o sesion)"))
                continue
            }
            command = mode == .type ? String(command.drop { $0 == " " }) : command.trimmingCharacters(in: .whitespaces)
            var hotkey: String?
            if let k = Self.key.group(1, in: name), let r = Self.key.range(in: name) {
                name = String(name[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                if keys.insert(k).inserted { hotkey = k } else {
                    problems.append(L("línea \(n + 1): la tecla \(k) ya la usa otro botón (éste se queda sin ella)"))
                }
            }
            buttons.append(CommandButton(group: group, mode: mode, name: name, command: command, hotkey: hotkey))
        }
        while header.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { header.removeLast() }
    }

    public var groups: [String] {
        var seen = Set<String>()
        return buttons.map(\.group).filter { seen.insert($0).inserted }
    }

    public func button(forKey k: String) -> CommandButton? { buttons.first { $0.hotkey == k } }

    /// Como lo escribe el editor de NetDeck: columnas alineadas, un hueco entre grupos.
    public func render() -> String {
        let gw = min(14, buttons.map(\.group.count).max() ?? 0)
        let nw = min(22, buttons.map { $0.name.count + ($0.hotkey.map { $0.count + 3 } ?? 0) }.max() ?? 0)
        func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
        var out = header.isEmpty ? Self.defaultHeader : header.joined(separator: "\n")
        out += "\n"
        var last: String?
        for b in buttons {
            if b.group != last { out += "\n"; last = b.group }
            let name = b.name + (b.hotkey.map { " [\($0)]" } ?? "")
            out += "\(pad(b.group, gw)) :: \(pad(b.mode.rawValue, 4)) :: \(pad(name, nw)) :: \(b.command)\n"
        }
        return out
    }

    public func save(to url: URL = ButtonFile.defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let prev = url.appendingPathExtension("anterior")
            try? FileManager.default.removeItem(at: prev)
            try? FileManager.default.copyItem(at: url, to: prev)
        }
        try render().write(to: url, atomically: true, encoding: .utf8)
    }

    static let defaultHeader = """
        # ─────────────────────────────────────────────────────────────
        #  Botones de la barra (los mismos que NetDeck: Ajustes → Botones o «botones»)
        #
        #  Formato:   Grupo :: modo :: Nombre :: comando
        #  modo:  run (escribe y pulsa Intro; varias con " ;; ") · type (sólo escribe) · pass (contraseña del Llavero
        #         con ese nombre) · login (usuario / nombre-contraseña) · sesion (abre esa sesión)
        #  Tecla rápida al final del nombre: [F5] · [S-F5] Mayús · [M-F5] Opción · [C-F5] Ctrl
        #  Huecos: {{interfaz}} o {{vlan=100}}: al pulsarlo te los pregunta.
        # ─────────────────────────────────────────────────────────────
        """

    /// Para empezar (sin datos de nadie).
    public static let samples = ButtonFile(text: defaultHeader + """

        Cisco    :: run  :: Interfaces       :: show ip interface brief
        Cisco    :: type :: Interfaz         :: show interfaces {{interfaz}}
        Cisco    :: run  :: Sin paginar      :: terminal length 0
        Juniper  :: run  :: Interfaces [F5]  :: show interfaces terse
        Juniper  :: type :: Match            :: show configuration | display set | match
        Huawei   :: run  :: Interfaces [F6]  :: display interface brief
        Huawei   :: run  :: Sin paginar      :: screen-length 0 temporary
        General  :: type :: Ping             :: ping {{ip}}
        """)
}

/// Las teclas de función tal y como llegan del terminal → «F5», «S-F5», «M-F5», «C-F5».
public enum FunctionKey {
    static let ss3: [UInt8: Int] = [UInt8(ascii: "P"): 1, UInt8(ascii: "Q"): 2, UInt8(ascii: "R"): 3, UInt8(ascii: "S"): 4]
    static let tilde: [Int: Int] = [11: 1, 12: 2, 13: 3, 14: 4, 15: 5, 17: 6, 18: 7, 19: 8, 20: 9, 21: 10, 23: 11, 24: 12]

    public static func name(_ b: [UInt8]) -> String? {
        guard b.count >= 3, b[0] == 0x1B else { return nil }
        var n: Int?
        var mod = 1
        if b[1] == UInt8(ascii: "O"), b.count == 3 {                          // ESC O P
            n = ss3[b[2]]
        } else if b[1] == UInt8(ascii: "[") {
            let body = String(decoding: b[2...], as: UTF8.self)
            guard let last = body.last else { return nil }
            let params = body.dropLast().split(separator: ";").compactMap { Int($0) }
            if last == "~", let first = params.first {                       // ESC [ 15 ; 2 ~
                n = tilde[first]
                if params.count > 1 { mod = params[1] }
            } else if let a = last.asciiValue, let k = ss3[a], params.first == 1 {   // ESC [ 1 ; 2 P
                n = k
                if params.count > 1 { mod = params[1] }
            }
        }
        guard let n else { return nil }
        let m = mod - 1
        let prefix = (m & 4 != 0 ? "C-" : "") + (m & 2 != 0 ? "M-" : "") + (m & 1 != 0 ? "S-" : "")
        return prefix + "F\(n)"
    }
}

extension Pattern {
    /// Coincidencias con sus grupos (1…n).
    func matchGroups(in s: String) -> [(range: NSRange, groups: [String?])] {
        regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
            (m.range, (1..<max(1, m.numberOfRanges)).map { i in
                Range(m.range(at: i), in: s).map { String(s[$0]) }
            })
        }
    }
}
