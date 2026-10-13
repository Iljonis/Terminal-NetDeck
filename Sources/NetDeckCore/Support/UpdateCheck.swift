import Foundation

/// Actualizaciones: la última release del repositorio en GitHub («usuario/repo», `NetDeckRepo` en el Info.plist que
/// pone install.sh). Sólo se consulta cuando lo pides; no se descarga ni se instala nada sin preguntar.
public enum UpdateCheck {
    public struct Release: Equatable, Sendable {
        public var version: String
        public var page: URL
        /// El .dmg de la release, si lo trae.
        public var dmg: URL?
    }

    /// El repositorio configurado, o nil (sin publicar todavía).
    public static var repo: String? {
        guard let r = Bundle.main.object(forInfoDictionaryKey: "NetDeckRepo") as? String,
              r.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { return nil }
        return r
    }

    public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// La respuesta de `GET /repos/{repo}/releases/latest`.
    public static func parse(_ data: Data) -> Release? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = j["tag_name"] as? String,
              let page = (j["html_url"] as? String).flatMap(URL.init(string:)), isGitHub(page) else { return nil }
        let assets = j["assets"] as? [[String: Any]] ?? []
        let dmg = assets.compactMap { $0["browser_download_url"] as? String }
            .first { $0.hasSuffix(".dmg") }.flatMap(URL.init(string:))
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page,
                       dmg: dmg.flatMap { isGitHub($0) ? $0 : nil })
    }

    /// Sólo enlaces https a github.com (lo que se abre al pulsar «Descargar»).
    static func isGitHub(_ u: URL) -> Bool { u.scheme == "https" && u.host == "github.com" }

    /// «0.10.0» > «0.4.1» (por números, no por texto).
    public static func isNewer(_ a: String, than b: String) -> Bool {
        func nums(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let x = nums(a), y = nums(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// La última versión publicada si es más nueva que la instalada; nil si ya estás al día. Primero las releases;
    /// si el repositorio aún no tiene ninguna, sus tags «vX.Y.Z».
    public static func check(repo: String, current: String = currentVersion) async throws -> Release? {
        let r: Release
        if let release = try await get("repos/\(repo)/releases/latest").flatMap(parse) {
            r = release
        } else if let tag = try await get("repos/\(repo)/tags").flatMap({ parseTags($0, repo: repo) }) {
            r = tag
        } else {
            return nil
        }
        return isNewer(r.version, than: current) ? r : nil
    }

    /// La respuesta de `GET /repos/{repo}/tags`: la versión más alta de las que parecen «vX.Y.Z».
    public static func parseTags(_ data: Data, repo: String) -> Release? {
        guard let tags = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let versions = tags.compactMap { $0["name"] as? String }
            .filter { $0.range(of: #"^v?\d+(\.\d+){0,2}$"#, options: .regularExpression) != nil }
            .map { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }
        guard let best = versions.max(by: { isNewer($1, than: $0) }),
              let page = URL(string: "https://github.com/\(repo)/releases") else { return nil }
        return Release(version: best, page: page, dmg: nil)
    }

    /// GET a la API de GitHub: los datos con 200, nil con 404 (sin releases / sin tags); el resto, error.
    private static func get(_ path: String) async throws -> Data? {
        var req = URLRequest(url: URL(string: "https://api.github.com/\(path)")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        switch (resp as? HTTPURLResponse)?.statusCode {
        case 200: return data
        case 404: return nil
        default: throw URLError(.badServerResponse)
        }
    }
}
