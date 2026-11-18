#if os(Windows)
import Foundation
import WinSDK

/// El «0600/0700» de Windows: una ACL protegida (sin heredar la de la carpeta de arriba) con control total sólo
/// para ti y para SYSTEM. Los bits POSIX de Foundation en Windows sólo cambian «sólo lectura»: no protegen nada.
enum WindowsACL {
    /// El SID del usuario de este proceso, como texto («S-1-5-21-…»). nil si no se puede leer.
    private static let userSID: String? = {
        var token: HANDLE?
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else { return nil }
        defer { CloseHandle(token) }
        var size: DWORD = 0
        GetTokenInformation(token, TokenUser, nil, 0, &size)
        guard size > 0 else { return nil }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<TOKEN_USER>.alignment)
        defer { buf.deallocate() }
        guard GetTokenInformation(token, TokenUser, buf, size, &size) else { return nil }
        var text: LPWSTR?
        guard ConvertSidToStringSidW(buf.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid, &text), let text else { return nil }
        defer { LocalFree(UnsafeMutableRawPointer(text)) }
        return String(decodingCString: text, as: UTF16.self)
    }()

    /// Deja `url` sólo para ti y SYSTEM. En una carpeta, lo que se cree dentro lo hereda. false si no se ha podido
    /// (un volumen sin ACL, como FAT o algunas unidades de red): el archivo queda con los permisos de su carpeta.
    @discardableResult
    static func restrict(_ url: URL, directory: Bool) -> Bool {
        guard let sid = userSID else { return false }
        let herencia = directory ? "OICI" : ""
        // D:P = DACL protegida (sin herencia del padre); FA = control total; SY = SYSTEM.
        let sddl = "D:P(A;\(herencia);FA;;;\(sid))(A;\(herencia);FA;;;SY)"
        var sd: PSECURITY_DESCRIPTOR?
        let ok = sddl.withCString(encodedAs: UTF16.self) {
            ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &sd, nil)
        }
        guard ok, let sd else { return false }
        defer { LocalFree(sd) }
        var present: WindowsBool = false, defaulted: WindowsBool = false
        var dacl: PACL?
        guard GetSecurityDescriptorDacl(sd, &present, &dacl, &defaulted), present.boolValue, let dacl else { return false }
        // DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION
        let info: SECURITY_INFORMATION = 0x0000_0004 | 0x8000_0000
        let path = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
        return path.withCString(encodedAs: UTF16.self) { w in
            SetNamedSecurityInfoW(UnsafeMutablePointer(mutating: w), SE_FILE_OBJECT, info, nil, nil, dacl, nil) == DWORD(ERROR_SUCCESS)
        }
    }
}
#endif
