#if os(Windows)
import Foundation
import Testing
@testable import NetDeckCore

@Suite struct UpdateCheckerWindowsTests {
    static let repo = "Iljonis/Terminal-NetDeck"
    static let hash = String(repeating: "ab", count: 32)

    static func release(tag: String = "v1.2.0", assets: [[String: Any]], body: String = "Notas") -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "body": body, "assets": assets])
    }

    static func asset(_ name: String, digest: String? = nil, path: String? = nil) -> [String: Any] {
        var a: [String: Any] = ["name": name,
                                "browser_download_url": "https://github.com/\(repo)/releases/download/v1.2.0/" + (path ?? name)]
        if let digest { a["digest"] = digest }
        return a
    }

    @Test func eligeElMsiConSuDigestYLasNotas() throws {
        let data = Self.release(assets: [Self.asset("Terminal-NetDeck.dmg"), Self.asset("Terminal-NetDeck-1.2.0.msi", digest: "sha256:" + Self.hash)],
                                body: "Cambios de la 1.2.0")
        let c = try #require(UpdateChecker.candidate(from: data, repo: Self.repo))
        #expect(c.version == "1.2.0" && c.installer.lastPathComponent == "Terminal-NetDeck-1.2.0.msi")
        #expect(c.digest == Self.hash && c.notes == "Cambios de la 1.2.0" && c.checksum == nil)
    }

    @Test func prefiereElSetupConElRuntimeAlMsiSuelto() throws {
        // (la Release de Windows lleva los tres: con el .msi, quien instaló con el Setup.exe acabaría con dos entradas en Aplicaciones)
        let data = Self.release(assets: [Self.asset("Terminal-NetDeck-1.2.0.msi"), Self.asset("Terminal-NetDeck-1.2.0-portable-x64.zip"),
                                         Self.asset("Terminal-NetDeck-1.2.0-Setup.exe"), Self.asset("Terminal-NetDeck-1.2.0-Setup.exe.sha256")])
        let c = try #require(UpdateChecker.candidate(from: data, repo: Self.repo))
        #expect(c.installer.lastPathComponent == "Terminal-NetDeck-1.2.0-Setup.exe")
        #expect(c.checksum?.lastPathComponent == "Terminal-NetDeck-1.2.0-Setup.exe.sha256")
    }

    @Test func elSha256PuedeVenirEnUnArchivoAparte() throws {
        let data = Self.release(assets: [Self.asset("Setup.exe"), Self.asset("Setup.exe.sha256")])
        let c = try #require(UpdateChecker.candidate(from: data, repo: Self.repo))
        #expect(c.installer.lastPathComponent == "Setup.exe" && c.digest == nil)
        #expect(c.checksum?.lastPathComponent == "Setup.exe.sha256")
    }

    @Test func sinInstaladorDeWindowsNoHayActualizacion() {
        #expect(UpdateChecker.candidate(from: Self.release(assets: [Self.asset("Terminal-NetDeck.dmg")]), repo: Self.repo) == nil)
        #expect(UpdateChecker.candidate(from: Data("no es json".utf8), repo: Self.repo) == nil)
    }

    @Test func soloVaLoQueEsDeGithubDelRepositorio() {
        func ok(_ s: String) -> Bool { UpdateChecker.isAllowedDownload(URL(string: s)!, repo: Self.repo) }
        #expect(ok("https://github.com/Iljonis/Terminal-NetDeck/releases/download/v1/a.msi"))
        #expect(!ok("http://github.com/Iljonis/Terminal-NetDeck/releases/download/v1/a.msi"))
        #expect(!ok("https://evil.example/Iljonis/Terminal-NetDeck/releases/download/v1/a.msi"))
        #expect(!ok("https://github.com.evil.example/Iljonis/Terminal-NetDeck/releases/download/v1/a.msi"))
        #expect(!ok("https://github.com/otro/repo/releases/download/v1/a.msi"))
        #expect(!ok("https://github.com/Iljonis/Terminal-NetDeck/releases/download/../../../x/a.msi"))
        #expect(!ok("https://usuario" + "\u{40}github.com/Iljonis/Terminal-NetDeck/releases/download/v1/a.msi"))   // (con usuario@: sin escribir la arroba)
        // (un instalador de otra parte en la release no se coge)
        let malo = ["name": "a.msi", "browser_download_url": "https://evil.example/a.msi"]
        #expect(UpdateChecker.candidate(from: Self.release(assets: [malo]), repo: Self.repo) == nil)
    }

    @Test func leeElSha256DeUnArchivoDeSumas() {
        #expect(UpdateChecker.checksum(in: Self.hash + "\n") == Self.hash)
        #expect(UpdateChecker.checksum(in: Self.hash.uppercased() + " *Setup.msi\r\n") == Self.hash)
        #expect(UpdateChecker.checksum(in: "corto") == nil)
        #expect(UpdateChecker.checksum(in: String(repeating: "g", count: 64)) == nil)
    }

    @Test func nombresDeArchivoSeguros() {
        #expect(UpdateChecker.safeFileName("Terminal-NetDeck-1.2.0.msi") == "Terminal-NetDeck-1.2.0.msi")
        for malo in ["", "..", ".oculto", "a/b.msi", "a\u{5C}b.msi", "a:b.msi", "a\"b.msi", String(repeating: "a", count: 200)] {
            #expect(UpdateChecker.safeFileName(malo) == nil)
        }
    }

    @Test func laVersionTieneQueSerMasNueva() {
        #expect(UpdateCheck.isNewer("1.2.0", than: UpdateChecker.currentVersion))
        #expect(!UpdateCheck.isNewer(UpdateChecker.currentVersion, than: UpdateChecker.currentVersion))
        #expect(!UpdateCheck.isNewer("0.8.9", than: UpdateChecker.currentVersion))
    }

    @Test func unArchivoSinFirmaNoPasaLaComprobacion() throws {
        let archivo = FileManager.default.temporaryDirectory.appendingPathComponent("sin-firma-\(UUID().uuidString).msi")
        try Data("no es un instalador".utf8).write(to: archivo)
        defer { try? FileManager.default.removeItem(at: archivo) }
        let estado = UpdateChecker.signatureStatus(of: archivo)
        #expect(estado != .valid)
        #expect(UpdateChecker.signatureStatus(of: archivo.appendingPathExtension("no-existe")) != .valid)
    }

    /// Una DLL de Microsoft con firma Authenticode incrustada (la trae el runtime de Swift): comprueba que las estructuras de
    /// WinVerifyTrust están bien. Si no hay red, la comprobación de revocación falla y se tolera sólo ese caso.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: Self.firmada.path)))
    func unaDllDeMicrosoftTieneFirmaValida() {
        let estado = UpdateChecker.signatureStatus(of: Self.firmada)
        #expect(estado == .valid || estado == .invalid(Int32(bitPattern: 0x80092013)))      // CRYPT_E_REVOCATION_OFFLINE
    }

    /// Entre la comprobación y el lanzamiento nadie puede cambiar el instalador, y sólo se lanza uno comprobado.
    @Test func elInstaladorComprobadoNoSePuedeCambiarYNoSeLanzaOtro() throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("NetDeckBloqueo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let msi = carpeta.appendingPathComponent("a.msi")
        try Data("uno".utf8).write(to: msi)
        #expect(!UpdateChecker.shared.launchInstaller(at: msi))                  // (sin comprobar: ni se intenta)
        #expect(InstallerLock.shared.hold(msi))
        #expect(InstallerLock.shared.isHeld(msi))
        #expect(throws: (any Error).self) { try Data("dos".utf8).write(to: msi) }
        #expect(throws: (any Error).self) { try FileManager.default.removeItem(at: msi) }
        #expect(try Data(contentsOf: msi) == Data("uno".utf8))                   // (leerlo sí: msiexec lo necesita)
        InstallerLock.shared.release(msi)
        #expect(!InstallerLock.shared.isHeld(msi))
        try Data("dos".utf8).write(to: msi)
    }

    @Test func sinFirmaNoSeAdmiteEnLaAppPublicada() {
        #if !DEBUG
        #expect(!UpdateChecker.allowUnsigned)
        #endif
    }

    static var firmada: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? "")
            .appendingPathComponent("Programs/Swift/Runtimes/6.4.2/usr/bin/msvcp140.dll")
    }
}
#endif
