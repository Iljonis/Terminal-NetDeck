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
              let page = (j["html_url"] as? String).flatMap(URL.init(string:)), page.scheme == "https" else { return nil }
        let assets = j["assets"] as? [[String: Any]] ?? []
        let dmg = assets.compactMap { $0["browser_download_url"] as? String }
            .first { $0.hasSuffix(".dmg") }.flatMap(URL.init(string:))
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page,
                       dmg: dmg?.scheme == "https" ? dmg : nil)
    }

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

    /// La última release si es más nueva que la instalada; nil si ya estás al día.
    public static func check(repo: String, current: String = currentVersion) async throws -> Release? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let r = parse(data) else {
            throw URLError(.badServerResponse)
        }
        return isNewer(r.version, than: current) ? r : nil
    }
}
