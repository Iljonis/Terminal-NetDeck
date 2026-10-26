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

    // MARK: - editar categorías (grupos) y botones; el orden es el del archivo, un bloque por grupo

    /// Cada grupo en un solo bloque, en el orden en que aparece por primera vez (los botones no cambian de orden dentro).
    public mutating func compactGroups() {
        let order = groups
        buttons = order.flatMap { g in buttons.filter { $0.group == g } }
    }

    /// Categoría nueva con un botón de partida (en el archivo no hay grupos vacíos). nil si el nombre ya está o es vacío.
    @discardableResult
    public mutating func addGroup(_ name: String, buttonName: String = "Nuevo") -> CommandButton.ID? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard Self.validGroup(n), !groups.contains(n) else { return nil }
        let b = CommandButton(group: n, mode: .run, name: buttonName, command: "")
        buttons.append(b)
        return b.id
    }

    /// Cambia el nombre en todos sus botones. Si ya existe otro con ese nombre, se juntan (al sitio del primero).
    @discardableResult
    public mutating func renameGroup(_ old: String, to new: String) -> Bool {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard Self.validGroup(n), groups.contains(old), n != old else { return false }
        for i in buttons.indices where buttons[i].group == old { buttons[i].group = n }
        compactGroups()
        return true
    }

    /// Quita la categoría: con sus botones (`movingTo` nil) o pasándolos al final de otra.
    public mutating func removeGroup(_ g: String, movingTo target: String? = nil) {
        guard let target, target != g else { buttons.removeAll { $0.group == g }; return }
        let moved = buttons.filter { $0.group == g }.map { b -> CommandButton in var c = b; c.group = target; return c }
        buttons.removeAll { $0.group == g }
        let at = (buttons.lastIndex { $0.group == target }).map { $0 + 1 } ?? buttons.count
        buttons.insert(contentsOf: moved, at: at)
    }

    /// Sube (-1) o baja (+1) el bloque entero de la categoría.
    @discardableResult
    public mutating func moveGroup(_ g: String, by offset: Int) -> Bool {
        var order = groups
        guard let i = order.firstIndex(of: g), order.indices.contains(i + offset) else { return false }
        compactGroups()                                   // (sólo si se mueve de verdad)
        order.swapAt(i, i + offset)
        buttons = order.flatMap { o in buttons.filter { $0.group == o } }
        return true
    }

    /// Sube o baja un botón dentro de su categoría.
    @discardableResult
    public mutating func moveButton(_ id: CommandButton.ID, by offset: Int) -> Bool {
        guard let i = buttons.firstIndex(where: { $0.id == id }), offset != 0 else { return false }
        let g = buttons[i].group
        let step = offset > 0 ? 1 : -1
        var j = i, left = abs(offset)
        while left > 0 {
            j += step
            guard buttons.indices.contains(j) else { return false }
            if buttons[j].group == g { left -= 1 }
        }
        let b = buttons.remove(at: i)
        buttons.insert(b, at: j)
        return true
    }

    /// Lo pasa al final de otra categoría (existente o nueva, que va al final).
    @discardableResult
    public mutating func moveButton(_ id: CommandButton.ID, toGroup target: String) -> Bool {
        let t = target.trimmingCharacters(in: .whitespaces)
        guard Self.validGroup(t), let i = buttons.firstIndex(where: { $0.id == id }), buttons[i].group != t else { return false }
        var b = buttons.remove(at: i)
        b.group = t
        let at = (buttons.lastIndex { $0.group == t }).map { $0 + 1 } ?? buttons.count
        buttons.insert(b, at: at)
        return true
    }

    /// Arrastrar en la barra: `id` ocupa el sitio de `target` (si venía de antes queda detrás, si de después, delante)
    /// y pasa a su categoría (queda pegado a `target`: el bloque del grupo no se parte).
    @discardableResult
    public mutating func moveButton(_ id: CommandButton.ID, onto target: CommandButton.ID) -> Bool {
        guard id != target, let i = buttons.firstIndex(where: { $0.id == id }),
              let j = buttons.firstIndex(where: { $0.id == target }) else { return false }
        var b = buttons.remove(at: i)
        b.group = buttons[j > i ? j - 1 : j].group
        buttons.insert(b, at: j)
        return true
    }

    /// Copia justo debajo (sin la tecla rápida: no puede haber dos con la misma). Devuelve la copia.
    @discardableResult
    public mutating func duplicateButton(_ id: CommandButton.ID, suffix: String = " 2") -> CommandButton.ID? {
        guard let i = buttons.firstIndex(where: { $0.id == id }) else { return nil }
        let o = buttons[i]
        let c = CommandButton(group: o.group, mode: o.mode, name: o.name + suffix, command: o.command)
        buttons.insert(c, at: i + 1)
        return c.id
    }

    /// Importar los botones de otro (un botones.txt que te pasan): se añaden al final de su categoría los que no
    /// tienes ya (mismo grupo, modo, nombre y orden); si su tecla rápida ya es de otro, entra sin ella.
    /// Devuelve cuántos se han añadido y cuántos ya estaban.
    @discardableResult
    public mutating func merge(_ other: ButtonFile) -> (added: Int, repeated: Int) {
        var added = 0, repeated = 0
        var keys = Set(buttons.compactMap(\.hotkey))
        for b in other.buttons {
            if buttons.contains(where: { $0.group == b.group && $0.mode == b.mode && $0.name == b.name && $0.command == b.command }) {
                repeated += 1
                continue
            }
            let k = b.hotkey.flatMap { keys.insert($0).inserted ? $0 : nil }
            let c = CommandButton(group: b.group, mode: b.mode, name: b.name, command: b.command, hotkey: k)
            let at = (buttons.lastIndex { $0.group == c.group }).map { $0 + 1 } ?? buttons.count
            buttons.insert(c, at: at)
            added += 1
        }
        return (added, repeated)
    }

    /// Un nombre de grupo que se puede escribir en el archivo (ni vacío, ni « :: », ni «#» delante, ni saltos).
    public static func validGroup(_ g: String) -> Bool {
        !g.isEmpty && !g.contains("::") && !g.hasPrefix("#") && !g.contains(where: \.isNewline)
    }

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
        try SafeFile.backup(url)                         // (si no se puede leer o copiar, no se toca)
        try SafeFile.write(render(), to: url)
    }

    static let defaultHeader = """
        # ─────────────────────────────────────────────────────────────
        #  Botones de la barra (se editan en Ajustes → Botones)
        #
        #  Formato:   Grupo :: modo :: Nombre :: comando
        #  modo:  run (escribe y pulsa Intro; varias con " ;; ") · type (sólo escribe) · pass (contraseña del Llavero
        #         con ese nombre) · login (usuario / nombre-contraseña) · sesion (abre esa sesión)
        #  Tecla rápida al final del nombre: [F5] · [S-F5] Mayús · [M-F5] Opción · [C-F5] Ctrl
        #  Huecos: {{interfaz}} o {{vlan=100}}: al pulsarlo te los pregunta.
        # ─────────────────────────────────────────────────────────────
        """

    /// De muestra, sólo si se piden (Ajustes → Botones): órdenes genéricas, sin equipos ni datos de nadie.
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
