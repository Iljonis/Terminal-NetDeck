import Foundation

/// ★ favoritas y ↻ recientes: los mismos archivos que NetDeck (~/.config/netdeck/favoritas y recientes). Favoritas: un
/// nombre por línea. Recientes: «segundos⇥nombre», la última abajo. Los dos con `SafeFile` (uno que existe y no se
/// puede leer no se pisa); recientes, además, con tope: no crece sin límite.
public enum SessionLists {
    /// Las que se ven en la lista.
    public static let recentShown = 10
    /// Las líneas que se quedan en «recientes» al recortarlo (al pasar del doble; sin repetir sesión).
    public static let recentKept = 100

    public static func favorites(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Las últimas `limit`, la más reciente primero y sin repetir.
    public static func recents(_ text: String, limit: Int = recentShown) -> [String] {
        var seen = Set<String>()
        return Array(text.components(separatedBy: .newlines).reversed()
            .compactMap { $0.split(separator: "\t").last.map(String.init) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(limit))
    }

    /// Lee las favoritas: [] si no hay archivo; error si existe y no se puede leer (y entonces no se guarda encima).
    public static func loadFavorites(_ url: URL) throws -> [String] { favorites(try SafeFile.read(url) ?? "") }

    /// Con copia `.anterior` (y la `.original` la primera vez); si el de ahora no se puede leer, error y no se toca.
    public static func saveFavorites(_ names: [String], to url: URL) throws {
        try SafeFile.backup(url)
        try SafeFile.write(names.joined(separator: "\n") + (names.isEmpty ? "" : "\n"), to: url)
    }

    /// «recientes» con `line` al final; si pasa de 2 × `recentKept` líneas, sólo las últimas `recentKept` (de cada
    /// sesión, la última vez).
    public static func appending(_ line: String, to text: String) -> String {
        var lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        lines.append(line)
        guard lines.count > 2 * recentKept else { return lines.joined(separator: "\n") + "\n" }
        var seen = Set<String>()
        let kept = lines.reversed().filter { l in seen.insert(l.split(separator: "\t").last.map(String.init) ?? l).inserted }
        return kept.prefix(recentKept).reversed().joined(separator: "\n") + "\n"
    }

    /// Apunta `name` en «recientes» (de forma atómica, 0600). Si existe y no se puede leer, error y no se toca.
    public static func noteRecent(_ name: String, at date: Date = Date(), in url: URL) throws {
        // (una línea por sesión, «segundos⇥nombre»: un nombre con tabulador o salto de línea la rompería)
        guard !name.contains(where: { $0 == "\t" || $0.isNewline }) else { return }
        let old = try SafeFile.read(url) ?? ""
        try SafeFile.write(appending("\(Int(date.timeIntervalSince1970))\t\(name)", to: old), to: url)
    }
}
