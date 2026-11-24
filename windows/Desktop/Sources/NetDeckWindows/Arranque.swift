import Foundation
import WinAppSDK
import WinSDK
import WinUI

/// Punto de entrada: como `SwiftApplication.main` (swift-winui 0.1.1), pero con el hilo de la interfaz en STA.
/// Con el MTA de la librería, las consultas de UI Automation (Narrador, lectores de pantalla) entraban por hilos COM
/// que no son el de WinUI y la app se cerraba (E_UNEXPECTED / RPC_E_WRONG_THREAD, 0xC000027B).
@main
enum Arranque {
    static func main() {
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
