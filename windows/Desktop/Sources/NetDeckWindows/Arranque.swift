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
            // Sin el Windows App Runtime (la versión portable en un equipo que no lo tiene; el Setup.exe lo instala): el bootstrapper ya
            // ha enseñado el aviso de Microsoft con el enlace de descarga (OnNoMatch_ShowUI, porque no hay WindowsAppRuntimeInstaller.exe
            // al lado). Se sale sin más, en vez de colgarse. Con el runtime instalado, el fallo es otro: se enseña.
            if runtimeInstalado() {
                let texto = L("Terminal NetDeck no ha podido iniciar Windows App Runtime 1.5: \(error)")
                _ = texto.withCString(encodedAs: UTF16.self) { mensaje in
                    "Terminal NetDeck".withCString(encodedAs: UTF16.self) { titulo in
                        MessageBoxW(nil, mensaje, titulo, UINT(MB_OK | MB_ICONERROR))
                    }
                }
            }
            exit(1)
        }
    }

    /// Si está el paquete Framework de Windows App Runtime 1.5 para este usuario (lo mismo que mira windows/installer/detectar-runtime.ps1;
    /// la versión es la de swift-windowsappsdk, WINDOWSAPPSDK_RELEASE_MAJORMINOR).
    private static func runtimeInstalado() -> Bool {
        var cuantos: UInt32 = 0
        var longitud: UInt32 = 0
        let r = "Microsoft.WindowsAppRuntime.1.5_8wekyb3d8bbwe".withCString(encodedAs: UTF16.self) {
            GetPackagesByPackageFamily($0, &cuantos, nil, &longitud, nil)
        }
        return (Int(r) == Int(ERROR_SUCCESS) || Int(r) == Int(ERROR_INSUFFICIENT_BUFFER)) && cuantos > 0
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
