import Foundation
import NetDeckCore
import WinAppSDK
import WinSDK
import WinUI

/// Punto de entrada: como `SwiftApplication.main` (swift-winui 0.1.1), pero con el hilo de la interfaz en STA.
/// Con el MTA de la librería, las consultas de UI Automation (Narrador, lectores de pantalla) entraban por hilos COM
/// que no son el de WinUI y la app se cerraba (E_UNEXPECTED / RPC_E_WRONG_THREAD, 0xC000027B).
@main
enum Arranque {
    static func main() {
        activarModoPortable()
        do {
            try withExtendedLifetime(WindowsAppRuntimeInitializer(threadingModel: .single)) {
                cargarFuentesIncluidas()
                var app: NetDeckWindows?
                Application.start { _ in
                    // RunLoop.main (temporizadores, cola principal) no lo atiende nadie en el bucle de mensajes de WinUI.
                    _ = SetTimer(nil, 0, 15) { _, _, _, _ in _ = RunLoop.main.limitDate(forMode: .default) }
                    app = NetDeckWindows()
                }
                app?.onShutdown()
            }
        } catch {
            fatalError("No se pudo iniciar Windows App Runtime: \(error)")
        }
    }

    /// La versión portable (.zip): con `NetDeck.portable` junto al ejecutable, los datos van a la carpeta `datos` de al lado.
    /// Se hace con `NETDECK_HOME` (lo mismo que la demo) ANTES de que nada lea el entorno; lo heredan ssh y el askpass.
    /// Si el usuario ya fijó `NETDECK_HOME`, manda el suyo. no verificado en Windows
    private static func activarModoPortable() {
        guard (ProcessInfo.processInfo.environment["NETDECK_HOME"] ?? "").isEmpty else { return }
        var ruta = [WCHAR](repeating: 0, count: 32768)
        let n = GetModuleFileNameW(nil, &ruta, DWORD(ruta.count))
        guard n > 0, Int(n) < ruta.count else { return }
        let ejecutable = URL(fileURLWithPath: String(decoding: ruta.prefix(Int(n)), as: UTF16.self))
        guard let datos = PortableMode.dataFolder(executableDirectory: ejecutable.deletingLastPathComponent()) else { return }
        try? FileManager.default.createDirectory(at: datos, withIntermediateDirectories: true)
        _ = datos.path.withCString(encodedAs: UTF16.self) { valor in
            "NETDECK_HOME".withCString(encodedAs: UTF16.self) { nombre in SetEnvironmentVariableW(nombre, valor) }
        }
    }

    /// Las fuentes redistribuibles se cargan en privado para esta app, sin registrarlas en Windows.
    private static func cargarFuentesIncluidas() {
        let carpeta = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .deletingLastPathComponent().appendingPathComponent("Fonts", isDirectory: true)
        guard let archivos = try? FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil) else { return }
        for archivo in archivos where archivo.pathExtension.lowercased() == "ttf" {
            let ruta = Array(archivo.path.utf16) + [0]
            ruta.withUnsafeBufferPointer { buffer in
                _ = AddFontResourceExW(buffer.baseAddress, DWORD(0x10), nil) // FR_PRIVATE
            }
        }
    }
}
