import Foundation

/// Temas: todos los que trae la app están ya disponibles (no se instalan), más los de NetDeck
/// (~/.config/netdeck/temas, si los has retocado ahí) y los que importes de un archivo .tema.
public struct ThemeLibrary: Sendable {
    public enum Source: String, Sendable { case builtIn, app, netdeck, imported }

    public var appDirectory: URL?
    public var importDirectory: URL
    public var netdeckDirectory: URL?

    public init(appDirectory: URL?, importDirectory: URL = AppPaths.themes,
                netdeckDirectory: URL? = AppPaths.netdeck.appendingPathComponent("temas")) {
        self.appDirectory = appDirectory
        self.importDirectory = importDirectory
        self.netdeckDirectory = netdeckDirectory
    }

    /// Todos, en el orden de NetDeck. Si un id se repite gana el importado y luego el de NetDeck (puede estar retocado).
    public func all() -> [(theme: Theme, source: Source)] {
        var by: [String: (Theme, Source)] = [:]
        let found = [(Theme.builtIn, Source.builtIn)]
            + Self.read(appDirectory).map { ($0, Source.app) }
            + Self.read(netdeckDirectory).map { ($0, Source.netdeck) }
            + Self.read(importDirectory).map { ($0, Source.imported) }
        for (t, s) in found {
            // (el de NetDeck que también trae la app sigue contando como de la app)
            by[t.id] = (t, s == .netdeck && by[t.id]?.1 == .app ? .app : s)
        }
        return Theme.sorted(by.values.map(\.0)).map { (theme: $0, source: by[$0.id]!.1) }
    }

    public func theme(id: String) -> Theme? { all().first { $0.theme.id == id }?.theme }

    /// Un .tema de cualquier sitio (se comprueba antes de copiarlo).
    @discardableResult
    public func importTheme(file: URL) throws -> Theme {
        let t = try Theme(contentsOf: file)
        AppPaths.ensure(importDirectory)
        let dest = importDirectory.appendingPathComponent("\(t.id).tema")
        if dest.standardizedFileURL != file.standardizedFileURL {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: file, to: dest)
        }
        return t
    }

    /// Sólo los importados se pueden quitar.
    public func remove(_ id: String) throws {
        try FileManager.default.removeItem(at: importDirectory.appendingPathComponent("\(id).tema"))
    }

    static func read(_ dir: URL?) -> [Theme] {
        guard let dir, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "tema" }.compactMap { try? Theme(contentsOf: $0) }
    }
}

/// Rótulo de 5×5 bloques (las letras de NetDeck): «NETDECK» → 5 filas de «█»/« ».
public enum Banner {
    static let letters: [Character: String] = Dictionary(uniqueKeysWithValues: zip("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.", [
        ".###.|#...#|#####|#...#|#...#", "####.|#...#|####.|#...#|####.", ".####|#....|#....|#....|.####",
        "####.|#...#|#...#|#...#|####.", "#####|#....|####.|#....|#####", "#####|#....|####.|#....|#....",
        ".####|#....|#..##|#...#|.####", "#...#|#...#|#####|#...#|#...#", "#####|..#..|..#..|..#..|#####",
        "..###|...#.|...#.|#..#.|.##..", "#...#|#..#.|###..|#..#.|#...#", "#....|#....|#....|#....|#####",
        "#...#|##.##|#.#.#|#...#|#...#", "#...#|##..#|#.#.#|#..##|#...#", ".###.|#...#|#...#|#...#|.###.",
        "####.|#...#|####.|#....|#....", ".###.|#...#|#.#.#|#..#.|.##.#", "####.|#...#|####.|#..#.|#...#",
        ".####|#....|.###.|....#|####.", "#####|..#..|..#..|..#..|..#..", "#...#|#...#|#...#|#...#|.###.",
        "#...#|#...#|#...#|.#.#.|..#..", "#...#|#...#|#.#.#|##.##|#...#", "#...#|.#.#.|..#..|.#.#.|#...#",
        "#...#|.#.#.|..#..|..#..|..#..", "#####|...#.|..#..|.#...|#####", ".###.|#..##|#.#.#|##..#|.###.",
        "..#..|.##..|..#..|..#..|.###.", ".###.|#...#|..##.|.#...|#####", "####.|....#|.###.|....#|####.",
        "#..#.|#..#.|#####|...#.|...#.", "#####|#....|####.|....#|####.", ".###.|#....|####.|#...#|.###.",
        "#####|....#|...#.|..#..|..#..", ".###.|#...#|.###.|#...#|.###.", ".###.|#...#|.####|....#|.###.",
        ".....|.....|.###.|.....|.....", ".....|.....|.....|.....|..#..",
    ]))

    /// 5 filas de casillas (true = bloque), con una columna de separación entre letras.
    public static func grid(_ text: String) -> [[Bool]] {
        var rows = Array(repeating: [Bool](), count: 5)
        for ch in text.uppercased() {
            let g = ch == " " ? "...|...|...|...|..." : (letters[ch] ?? ".....|.....|.....|.....|.....")
            for (i, f) in g.split(separator: "|").enumerated() { rows[i] += f.map { $0 == "#" } + [false] }
        }
        return rows.map { Array($0.dropLast()) }
    }

    /// 5 filas; cada bloque «██» (doble ancho, más proporcionado).
    public static func rows(_ text: String, pixel: String = "██") -> [String] {
        let blank = String(repeating: " ", count: pixel.count)
        var rows = Array(repeating: "", count: 5)
        for ch in text.uppercased() {
            let g = ch == " " ? "...|...|...|...|..." : (letters[ch] ?? ".....|.....|.....|.....|.....")
            for (i, f) in g.split(separator: "|").enumerated() {
                rows[i] += f.map { $0 == "#" ? pixel : blank }.joined() + blank
            }
        }
        return rows.map { String($0.reversed().drop { $0 == " " }.reversed()) }
    }
}
