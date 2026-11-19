import Foundation
import NetDeckCore
import WinSDK

/// Diálogos Win32 modales, con la ventana de NetDeck como propietaria.
enum SelectorArchivos {
    static func abrir(titulo: String, tipo: String, patron: String, owner: HWND) throws -> URL? {
        var dialogo = OPENFILENAMEW()
        dialogo.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
        dialogo.hwndOwner = owner
        dialogo.nFilterIndex = 1
        dialogo.Flags = DWORD(OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR)
        var ruta = [WCHAR](repeating: 0, count: 32768)
        let filtro = Array("\(tipo)\0\(patron)\0".utf16) + [0]
        let nombre = Array(titulo.utf16) + [0]
        let elegido = ruta.withUnsafeMutableBufferPointer { buffer in
            filtro.withUnsafeBufferPointer { filtro in
                nombre.withUnsafeBufferPointer { nombre in
                    dialogo.lpstrFile = buffer.baseAddress
                    dialogo.nMaxFile = DWORD(buffer.count)
                    dialogo.lpstrFilter = filtro.baseAddress
                    dialogo.lpstrTitle = nombre.baseAddress
                    return GetOpenFileNameW(&dialogo)
                }
            }
        }
        guard elegido else {
            let error = CommDlgExtendedError()
            if error != 0 { throw RemoteError(L("No se puede abrir el selector de archivos (Windows: \(error))")) }
            return nil
        }
        return URL(fileURLWithPath: String(decoding: ruta.prefix { $0 != 0 }, as: UTF16.self))
    }

    static func carpeta(titulo: String, owner: HWND) -> URL? {
        var dialogo = BROWSEINFOW()
        dialogo.hwndOwner = owner
        dialogo.ulFlags = UINT(BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE)
        let nombre = Array(titulo.utf16) + [0]
        guard let pidl = nombre.withUnsafeBufferPointer({ nombre in
            dialogo.lpszTitle = nombre.baseAddress
            return SHBrowseForFolderW(&dialogo)
        }) else { return nil }
        defer { CoTaskMemFree(pidl) }
        var ruta = [WCHAR](repeating: 0, count: 32768)
        guard SHGetPathFromIDListEx(pidl, &ruta, DWORD(ruta.count), .init(0)) else { return nil }
        return URL(fileURLWithPath: String(decoding: ruta.prefix { $0 != 0 }, as: UTF16.self), isDirectory: true)
    }

    static func color(_ actual: RGB, owner: HWND) -> RGB? {
        var dialogo = CHOOSECOLORW()
        dialogo.lStructSize = DWORD(MemoryLayout<CHOOSECOLORW>.size)
        dialogo.hwndOwner = owner
        dialogo.Flags = DWORD(CC_RGBINIT | CC_FULLOPEN)
        let c = EstiloMac.color(actual)
        dialogo.rgbResult = DWORD(c.r) | (DWORD(c.g) << 8) | (DWORD(c.b) << 16)
        var personalizados = [COLORREF](repeating: 0, count: 16)
        let elegido = personalizados.withUnsafeMutableBufferPointer { buffer in
            dialogo.lpCustColors = buffer.baseAddress
            return ChooseColorW(&dialogo)
        }
        guard elegido else { return nil }
        return RGB(Double(dialogo.rgbResult & 0xff), Double((dialogo.rgbResult >> 8) & 0xff),
                   Double((dialogo.rgbResult >> 16) & 0xff))
    }

}
