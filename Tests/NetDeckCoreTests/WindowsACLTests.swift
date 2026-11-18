#if os(Windows)
import Foundation
import Testing
import WinSDK
@testable import NetDeckCore

/// WindowsACL.restrict: aplica ACL «0600/0700» en Windows — control total sólo para el usuario actual y SYSTEM.
@Suite struct WindowsACLTests {
    @Test func restrictArchivoRetornaVerdadero() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acl-test-\(ProcessInfo.processInfo.processIdentifier).tmp")
        _ = FileManager.default.createFile(atPath: url.path, contents: Data("hola".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(WindowsACL.restrict(url, directory: false))
    }

    @Test func restrictCarpetaRetornaVerdadero() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acl-dir-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(WindowsACL.restrict(url, directory: true))
    }

    @Test func propietarioPuedeLeerTrasBlindar() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acl-read-\(ProcessInfo.processInfo.processIdentifier).tmp")
        let contenido = Data("prueba-acl".utf8)
        _ = FileManager.default.createFile(atPath: url.path, contents: contenido)
        defer { try? FileManager.default.removeItem(at: url) }
        guard WindowsACL.restrict(url, directory: false) else { return }
        // El propietario puede leer el archivo despues de blindarlo
        #expect(try Data(contentsOf: url) == contenido)
    }

    @Test func restriccionDejaExactamenteDosAces() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("acl-aces-\(ProcessInfo.processInfo.processIdentifier).tmp")
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        guard WindowsACL.restrict(url, directory: false) else { return }
        // Comprobar el DACL: exactamente 2 ACEs (usuario + SYSTEM)
        // PSECURITY_DESCRIPTOR = UnsafeMutableRawPointer (no optional): usar PSECURITY_DESCRIPTOR?
        var dacl: PACL? = nil
        var sd: PSECURITY_DESCRIPTOR? = nil
        let rc = url.path.withCString(encodedAs: UTF16.self) { w in
            GetNamedSecurityInfoW(UnsafeMutablePointer(mutating: w), SE_FILE_OBJECT,
                                  SECURITY_INFORMATION(4), nil, nil, &dacl, nil, &sd)
        }
        guard rc == DWORD(ERROR_SUCCESS), let sd else { return }
        defer { LocalFree(sd) }
        guard let dacl else { return }
        var nAces = 0
        var pAce: UnsafeMutableRawPointer? = nil
        while GetAce(dacl, DWORD(nAces), &pAce) { nAces += 1 }
        #expect(nAces == 2)
    }
}
#endif