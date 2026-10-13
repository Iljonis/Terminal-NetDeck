import Foundation

/// Una lista guardada (Listas → listas.json): nombre, salto, usuario, contraseña (sólo el NOMBRE de la del Llavero) y
/// los equipos, uno por línea como se escriben («core-01», «192.0.2.5», «tu.usuario@core-01:2222»).
public struct SavedList: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var jump: String
    public var user: String
    /// Cuenta del Llavero («AD», «tu.usuario@core-01»); vacío = a mano.
    public var credential: String
    public var devices: [String]

    public init(id: UUID = UUID(), name: String, jump: String = "", user: String = "", credential: String = "",
                devices: [String] = []) {
        self.id = id
        self.name = name
        self.jump = jump
        self.user = user
        self.credential = credential
        self.devices = devices
    }

    /// Los equipos válidos (los demás se ignoran).
    public var endpoints: [Endpoint] { DeviceListText.parse(devices.joined(separator: "\n")).devices }
}

/// Texto de equipos: uno por línea (o separados por espacios, «,» o «;»); «#» comenta. Sólo los que valen para
/// escribirlos en la shell del salto: nada que empiece por «-» (sería una opción de ssh), ni «;», «$(…)»…
public enum DeviceListText {
    public static func parse(_ text: String) -> (devices: [Endpoint], rejected: [String]) {
        var seen = Set<Endpoint>()
        var ok: [Endpoint] = [], bad: [String] = []
        let tokens = text.components(separatedBy: .newlines)
            .map { $0.components(separatedBy: "#")[0] }
            .flatMap { $0.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace }) }
            .map(String.init)
        for t in tokens {
            guard let e = valid(t) else { bad.append(t); continue }
            if seen.insert(e).inserted { ok.append(e) }
        }
        return (ok, bad)
    }

    /// Un equipo, o nil si no vale (vacío, «-x», «a@-x», caracteres de shell…).
    public static func valid(_ s: String) -> Endpoint? {
        guard !s.hasPrefix("-"), let e = Endpoint(parsing: s), e.isShellSafe else { return nil }
        return e
    }

    /// Un .txt o .csv importado → un equipo por línea: la primera columna («,», «;» o tabulador), sin comillas ni la
    /// cabecera («host», «ip», «nombre»…).
    public static func importing(_ fileText: String) -> String {
        let headers: Set<String> = ["host", "hostname", "name", "nombre", "ip", "equipo", "device", "address", "direccion"]
        var out: [String] = []
        for (n, raw) in fileText.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmed
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let first = line.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\t" }).first.map(String.init) ?? ""
            let v = first.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespaces))
            guard !v.isEmpty else { continue }
            if n == 0 || out.isEmpty, headers.contains(v.lowercased()) { continue }
            out.append(v)
        }
        return out.joined(separator: "\n")
    }
}

/// Las listas guardadas: `AppPaths.support/listas.json` (0600, con copia antes de sustituirlo). Sin contraseñas.
public struct ListLibrary: Codable, Sendable, Equatable {
    public var lists: [SavedList] = []

    public static var defaultURL: URL { AppPaths.support.appendingPathComponent("listas.json") }

    public init(lists: [SavedList] = []) { self.lists = lists }

    /// nil si no existe (vacía); error si existe y no se puede leer (no se pisa).
    public init(contentsOf url: URL) throws {
        guard let text = try SafeFile.read(url) else { self.init(); return }
        self = try JSONDecoder().decode(ListLibrary.self, from: Data(text.utf8))
    }

    public func save(to url: URL = ListLibrary.defaultURL) throws {
        AppPaths.ensure(url.deletingLastPathComponent())
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let text = String(decoding: try enc.encode(self), as: UTF8.self)
        try SafeFile.backup(url)
        try SafeFile.write(text + "\n", to: url)
    }

    public func list(_ id: SavedList.ID?) -> SavedList? { lists.first { $0.id == id } }

    /// «base», «base 2», «base 3»… (sin repetir, sin mirar mayúsculas).
    public func uniqueName(_ base: String) -> String {
        let b = base.trimmed.isEmpty ? "lista" : base.trimmed
        let taken = Set(lists.map { $0.name.lowercased() })
        var n = b, k = 2
        while taken.contains(n.lowercased()) { n = "\(b) \(k)"; k += 1 }
        return n
    }

    /// La guarda (nueva o sustituyendo la del mismo id), con nombre único.
    @discardableResult
    public mutating func upsert(_ l: SavedList) -> SavedList {
        var l = l
        let others = ListLibrary(lists: lists.filter { $0.id != l.id })
        l.name = others.uniqueName(l.name)
        if let i = lists.firstIndex(where: { $0.id == l.id }) { lists[i] = l } else { lists.append(l) }
        return l
    }

    @discardableResult
    public mutating func rename(_ id: SavedList.ID, to name: String) -> Bool {
        guard let i = lists.firstIndex(where: { $0.id == id }), !name.trimmed.isEmpty else { return false }
        let others = ListLibrary(lists: lists.filter { $0.id != id })
        lists[i].name = others.uniqueName(name)
        return true
    }

    /// Copia justo debajo («nombre 2»). Devuelve la copia.
    @discardableResult
    public mutating func duplicate(_ id: SavedList.ID) -> SavedList? {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return nil }
        var c = lists[i]
        c.id = UUID()
        c.name = uniqueName(c.name)
        lists.insert(c, at: i + 1)
        return c
    }

    public mutating func remove(_ id: SavedList.ID) { lists.removeAll { $0.id == id } }
}
