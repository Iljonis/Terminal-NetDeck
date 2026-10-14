import CryptoKit
import Foundation

/// Actualizaciones: la última release del repositorio en GitHub («usuario/repo», `NetDeckRepo` en el Info.plist que
/// pone install.sh). No se descarga ni se instala nada sin preguntar: «Actualizar» baja el .dmg de github.com, lo
/// comprueba con el sha256 que publica GitHub y que sea esta misma app (id) en la versión anunciada.
public enum UpdateCheck {
    public struct Release: Equatable, Sendable {
        public var version: String
        public var page: URL
        /// El .dmg de la release, si lo trae.
        public var dmg: URL?
        /// Su sha256 según GitHub («digest» del asset), en hexadecimal.
        public var sha256: String? = nil
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
        let asset = assets.first { ($0["browser_download_url"] as? String)?.hasSuffix(".dmg") == true }
        let dmg = (asset?["browser_download_url"] as? String).flatMap(URL.init(string:))
        let digest = (asset?["digest"] as? String).flatMap { d -> String? in
            guard d.hasPrefix("sha256:") else { return nil }
            let h = d.dropFirst(7).lowercased()
            return h.count == 64 && h.allSatisfy(\.isHexDigit) ? h : nil
        }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page,
                       dmg: dmg.flatMap { isGitHub($0) ? $0 : nil }, sha256: digest)
    }

    /// Sólo enlaces https a github.com (lo que se abre al pulsar «Descargar»).
    static func isGitHub(_ u: URL) -> Bool { u.scheme == "https" && u.host == "github.com" }

    /// sha256 de un archivo (en trozos: el .dmg pesa varios MB), en hexadecimal.
    public static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let d = try h.read(upToCount: 1 << 20), !d.isEmpty { hasher.update(data: d) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Que la app bajada sea ésta (mismo id) y la versión anunciada; si no, el motivo.
    public static func validate(app: URL, bundleID: String, version: String) -> String? {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else {
            return L("el .dmg no trae la app")
        }
        if info["CFBundleIdentifier"] as? String != bundleID { return L("la app del .dmg no es Terminal NetDeck") }
        if info["CFBundleShortVersionString"] as? String != version { return L("la app del .dmg no es la versión \(version)") }
        return nil
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
