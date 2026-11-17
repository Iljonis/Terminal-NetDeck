#if os(Windows)
import Foundation
import WinSDK
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Una actualizacion de Windows lista para descargar: el instalador, su sha256 y las notas de la release.
public struct UpdateInfo: Sendable, Equatable {
    public let version: String
    public let downloadURL: URL
    public let sha256: String
    public let releaseNotes: String

    public init(version: String, downloadURL: URL, sha256: String, releaseNotes: String) {
        self.version = version
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.releaseNotes = releaseNotes
    }
}

public struct UpdateFailure: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Lo que se saca de la respuesta de GitHub antes de tener el sha256 (que puede venir en otro asset).
struct UpdateCandidate: Equatable {
    var version: String
    var installer: URL
    var digest: String?
    var checksum: URL?
    var notes: String
}

/// Actualizaciones de Windows (ADR-0003), con las mismas reglas que macOS (`UpdateCheck`): sólo enlaces https de
/// github.com del repositorio, sha256 del instalador, y además la firma Authenticode con `WinVerifyTrust`. Nada se
/// descarga ni se instala sin que el usuario lo pida (no hay comprobaciones automáticas) y no hay actualizaciones silenciosas.
public actor UpdateChecker {
    public static let shared = UpdateChecker()

    public static let repo = "Iljonis/Terminal-NetDeck"
    /// La version de esta app (en Windows no hay Info.plist). Debe coincidir con AppxManifest.xml y NetDeckWindows.wxs.
    public static let currentVersion = "0.9.0"

    public init() {}

    // MARK: - buscar

    /// La actualizacion mas nueva que la instalada, o nil si estas al dia, no hay instalador de Windows en la release o
    /// algo ha fallado (la interfaz usa `check` para distinguirlo).
    public func checkForUpdates() async -> UpdateInfo? {
        try? await check()
    }

    /// Como `checkForUpdates`, pero lanza el motivo si no se ha podido comprobar.
    public func check(current: String = UpdateChecker.currentVersion) async throws -> UpdateInfo? {
        guard let data = try await Self.get("https://api.github.com/repos/\(Self.repo)/releases/latest") else { return nil }
        guard let candidate = Self.candidate(from: data, repo: Self.repo),
              UpdateCheck.isNewer(candidate.version, than: current) else { return nil }
        // (el sha256: el «digest» que publica GitHub y/o el archivo «.sha256» de la release; si hay los dos tienen que coincidir)
        var published: String?
        if let url = candidate.checksum, let text = try await Self.get(url.absoluteString).flatMap({ String(decoding: $0.prefix(4096), as: UTF8.self) }) {
            published = Self.checksum(in: text)
        }
        if let a = candidate.digest, let b = published, a != b {
            throw UpdateFailure(L("el sha256 de la release no coincide con el de su archivo .sha256"))
        }
        guard let sha = candidate.digest ?? published else {
            throw UpdateFailure(L("la release no publica el sha256 del instalador: no se ofrece"))
        }
        return UpdateInfo(version: candidate.version, downloadURL: candidate.installer, sha256: sha, releaseNotes: candidate.notes)
    }

    // MARK: - descargar y comprobar

    /// Baja el instalador a una carpeta temporal y lo comprueba: sha256 y firma. Si algo no cuadra se borra y se lanza el motivo.
    public func downloadAndVerify(_ info: UpdateInfo) async throws -> URL {
        guard Self.isAllowedDownload(info.downloadURL, repo: Self.repo),
              let name = Self.safeFileName(info.downloadURL.lastPathComponent) else {
            throw UpdateFailure(L("el enlace de descarga no es de github.com/\(Self.repo)"))
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NetDeckUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(name)
        do {
            try await Self.download(info.downloadURL, to: target)
            let actual = try UpdateCheck.sha256(of: target)
            guard actual == info.sha256.lowercased() else {
                throw UpdateFailure(L("el sha256 del instalador no es el publicado"))
            }
            switch Self.signatureStatus(of: target) {
            case .valid:
                break
            case .unsigned where Self.allowUnsigned:
                break
            case .unsigned:
                throw UpdateFailure(L("el instalador no está firmado"))
            case .invalid(let code):
                throw UpdateFailure(L("la firma del instalador no es válida (error \(String(format: "0x%08X", UInt32(bitPattern: code))))"))
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return target
    }

    /// Lanza el instalador con el aviso de administrador (UAC). Sólo tras el clic del usuario. true si Windows lo ha aceptado.
    @discardableResult
    public nonisolated func launchInstaller(at url: URL) -> Bool {
        let path = url.path.replacingOccurrences(of: "/", with: "\\")
        let isMSI = url.pathExtension.lowercased() == "msi"
        let file = isMSI ? "msiexec.exe" : path
        let parameters: String? = isMSI ? "/i \"\(path)\"" : nil
        let result: Int = file.withCString(encodedAs: UTF16.self) { file in
            "runas".withCString(encodedAs: UTF16.self) { verb in
                (parameters ?? "").withCString(encodedAs: UTF16.self) { args in
                    Int(bitPattern: ShellExecuteW(nil, verb, file, parameters == nil ? nil : args, nil, SW_SHOWNORMAL))
                }
            }
        }
        return result > 32                       // (ShellExecute: mas de 32 es exito)
    }

    /// Instaladores de prueba sin firma (el CI sin certificado): sólo con NETDECK_UPDATE_ALLOW_UNSIGNED=1.
    static var allowUnsigned: Bool { ProcessInfo.processInfo.environment["NETDECK_UPDATE_ALLOW_UNSIGNED"] == "1" }

    // MARK: - lo que no depende de la red (con tests)

    /// La respuesta de `GET /repos/{repo}/releases/latest`: el instalador de Windows (.msi y, si no, .exe) y su sha256.
    static func candidate(from data: Data, repo: String) -> UpdateCandidate? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = j["tag_name"] as? String else { return nil }
        let assets = j["assets"] as? [[String: Any]] ?? []
        func url(_ a: [String: Any]) -> URL? { (a["browser_download_url"] as? String).flatMap(URL.init(string:)) }
        func name(_ a: [String: Any]) -> String { (a["name"] as? String ?? "").lowercased() }
        guard let installer = assets.first(where: { name($0).hasSuffix(".msi") }) ?? assets.first(where: { name($0).hasSuffix(".exe") }),
              let installerURL = url(installer), isAllowedDownload(installerURL, repo: repo) else { return nil }
        let digest = (installer["digest"] as? String).flatMap { d -> String? in
            d.hasPrefix("sha256:") ? checksum(in: String(d.dropFirst(7))) : nil
        }
        let sidecar = assets.first { name($0) == name(installer) + ".sha256" }.flatMap(url).flatMap { isAllowedDownload($0, repo: repo) ? $0 : nil }
        return UpdateCandidate(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, installer: installerURL,
                               digest: digest, checksum: sidecar, notes: String((j["body"] as? String ?? "").prefix(4000)))
    }

    /// El primer sha256 (64 hexadecimales) de un texto: vale «hash», «hash  archivo» y «hash *archivo».
    static func checksum(in text: String) -> String? {
        for token in text.split(whereSeparator: { $0.isWhitespace || $0 == "*" }) {
            let t = token.lowercased()
            if t.count == 64, t.allSatisfy(\.isHexDigit) { return t }
        }
        return nil
    }

    /// Sólo https://github.com/<repo>/releases/download/…, sin «..»: lo que se descarga y se ejecuta con permisos de administrador.
    static func isAllowedDownload(_ url: URL, repo: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.port == nil
            && url.path.hasPrefix("/\(repo)/releases/download/") && !url.path.contains("..")
    }

    /// El nombre del archivo en la carpeta temporal: sin rutas ni caracteres raros.
    static func safeFileName(_ name: String) -> String? {
        guard !name.isEmpty, name.count <= 120, !name.hasPrefix("."),
              name.range(of: "^[A-Za-z0-9._ -]+$", options: .regularExpression) != nil else { return nil }
        return name
    }

    // MARK: - red

    /// GET: los datos con 200, nil con 404; el resto, error.
    private static func get(_ address: String) async throws -> Data? {
        guard let url = URL(string: address), url.scheme == "https" else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Terminal-NetDeck-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return data
        case 404: return nil
        default: throw URLError(.badServerResponse)
        }
    }

    private static func download(_ url: URL, to target: URL) async throws {
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.setValue("Terminal-NetDeck-Updater", forHTTPHeaderField: "User-Agent")
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            URLSession.shared.downloadTask(with: request) { temporary, response, error in
                if let error { done.resume(throwing: error); return }
                guard let temporary, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    done.resume(throwing: UpdateFailure(L("la descarga no ha terminado bien")))
                    return
                }
                do {
                    try FileManager.default.moveItem(at: temporary, to: target)
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }.resume()
        }
    }

    // MARK: - firma Authenticode

    enum SignatureStatus: Equatable {
        case valid
        case unsigned
        case invalid(Int32)
    }

    /// La firma Authenticode de un archivo con `WinVerifyTrust` (cargado de wintrust.dll: WinSDK no lo expone). Cualquier duda,
    /// «inválida»: nunca se da por buena una firma que no se ha podido comprobar.
    /// OJO: comprueba que la firma es válida y de confianza, no QUIEN firma. Fijar el firmante (el Subject del certificado de
    /// Azure Code Signing) queda pendiente.
    static func signatureStatus(of url: URL) -> SignatureStatus {
        struct Guid { var d1: UInt32; var d2: UInt16; var d3: UInt16; var d4: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) }
        struct FileInfo {
            var cbStruct: UInt32; var path: UnsafePointer<UInt16>?; var file: UnsafeMutableRawPointer?; var knownSubject: UnsafeMutableRawPointer?
        }
        struct TrustData {
            var cbStruct: UInt32; var policyCallback: UnsafeMutableRawPointer?; var sipClient: UnsafeMutableRawPointer?
            var uiChoice: UInt32; var revocation: UInt32; var unionChoice: UInt32
            var fileInfo: UnsafeMutablePointer<FileInfo>?
            var stateAction: UInt32; var stateData: UnsafeMutableRawPointer?; var urlReference: UnsafeMutablePointer<UInt16>?
            var provFlags: UInt32; var uiContext: UInt32; var signatureSettings: UnsafeMutableRawPointer?
        }
        // (el mismo disposicion que WINTRUST_DATA y WINTRUST_FILE_INFO en x64)
        guard MemoryLayout<TrustData>.size == 88, MemoryLayout<FileInfo>.size == 32,
              MemoryLayout<Guid>.size == 16 else { return .invalid(-1) }
        typealias Verify = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32
        let module = "wintrust.dll".withCString(encodedAs: UTF16.self) { LoadLibraryW($0) }
        guard let module, let proc = GetProcAddress(module, "WinVerifyTrust") else { return .invalid(-2) }
        let verify = unsafeBitCast(proc, to: Verify.self)

        // WINTRUST_ACTION_GENERIC_VERIFY_V2
        var action = Guid(d1: 0x00AAC56B, d2: 0xCD44, d3: 0x11D0, d4: (0x8C, 0xC2, 0x00, 0xC0, 0x4F, 0xC2, 0x95, 0xEE))
        let path = url.path.replacingOccurrences(of: "/", with: "\\")
        return path.withCString(encodedAs: UTF16.self) { wide in
            var info = FileInfo(cbStruct: UInt32(MemoryLayout<FileInfo>.size), path: wide, file: nil, knownSubject: nil)
            return withUnsafeMutablePointer(to: &info) { infoPointer in
                var data = TrustData(cbStruct: UInt32(MemoryLayout<TrustData>.size), policyCallback: nil, sipClient: nil,
                                     uiChoice: 2 /* WTD_UI_NONE */, revocation: 1 /* WTD_REVOKE_WHOLECHAIN */,
                                     unionChoice: 1 /* WTD_CHOICE_FILE */, fileInfo: infoPointer,
                                     stateAction: 1 /* WTD_STATEACTION_VERIFY */, stateData: nil, urlReference: nil,
                                     provFlags: 0, uiContext: 0, signatureSettings: nil)
                let invalidHandle = UnsafeMutableRawPointer(bitPattern: -1)          // INVALID_HANDLE_VALUE: sin ventana
                let code = withUnsafeMutablePointer(to: &action) { guid in
                    withUnsafeMutablePointer(to: &data) { verify(invalidHandle, UnsafeMutableRawPointer(guid), UnsafeMutableRawPointer($0)) }
                }
                data.stateAction = 2                                                  // WTD_STATEACTION_CLOSE
                _ = withUnsafeMutablePointer(to: &action) { guid in
                    withUnsafeMutablePointer(to: &data) { verify(invalidHandle, UnsafeMutableRawPointer(guid), UnsafeMutableRawPointer($0)) }
                }
                switch UInt32(bitPattern: code) {
                case 0: return .valid
                case 0x800B0100: return .unsigned                                    // TRUST_E_NOSIGNATURE
                default: return .invalid(code)
                }
            }
        }
    }
}
#endif
