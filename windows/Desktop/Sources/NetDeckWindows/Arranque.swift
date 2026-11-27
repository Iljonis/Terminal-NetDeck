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
        anteponerOpenSSHIncluido()
        if let runtime = runtimeIncluido() {
            arrancarConRuntimeIncluido(runtime)
            return
        }
        do {
            try withExtendedLifetime(WindowsAppRuntimeInitializer(threadingModel: .single)) { ejecutarApp() }
        } catch {
            // Sin el Windows App Runtime instalado (aquí sólo llega una compilación de desarrollo: la instalación y la portable lo llevan
            // dentro): el bootstrapper ya ha enseñado el aviso de Microsoft con el enlace de descarga (OnNoMatch_ShowUI, porque no hay
            // WindowsAppRuntimeInstaller.exe al lado). Se sale sin más, en vez de colgarse. Con el runtime instalado, el fallo es otro: se enseña.
            if runtimeInstalado() { avisarDeError(L("Terminal NetDeck no ha podido iniciar Windows App Runtime 1.5: \(error)")) }
            exit(1)
        }
    }

    private static func ejecutarApp() {
        cargarFuentesIncluidas()
        var app: NetDeckWindows?
        Application.start { _ in
            // RunLoop.main (temporizadores, cola principal) no lo atiende nadie en el bucle de mensajes de WinUI.
            _ = SetTimer(nil, 0, 15) { _, _, _, _ in _ = RunLoop.main.limitDate(forMode: .default) }
            app = NetDeckWindows()
        }
        app?.onShutdown()
    }

    /// `Microsoft.WindowsAppRuntime.dll` junto al ejecutable: la instalación y la portable llevan Windows App Runtime 1.5 DENTRO
    /// (modo «self-contained» de Microsoft; lo monta windows/installer/incluir-dependencias.ps1). En una compilación de desarrollo
    /// no está y se usa el runtime instalado en Windows con el bootstrapper, como siempre.
    private static func runtimeIncluido() -> URL? {
        guard let carpeta = carpetaDelEjecutable() else { return nil }
        let dll = carpeta.appendingPathComponent("Microsoft.WindowsAppRuntime.dll")
        return FileManager.default.fileExists(atPath: dll.path) ? dll : nil
    }

    /// Lo que hace `WindowsAppRuntimeInitializer` (swift-windowsappsdk 0.1.2) sin el bootstrapper, que sólo sabe buscar el runtime
    /// instalado y falla si no está: RoInitialize en STA y DPI por monitor. Las clases de WinUI se activan por el manifiesto que lleva
    /// el .exe (las entradas `activatableClass` que genera incluir-dependencias.ps1, como el `WindowsAppSDKSelfContained` de MSBuild),
    /// y cargar antes `Microsoft.WindowsAppRuntime.dll` activa su RegFree WinRT, como el AutoInitializer de Microsoft. no verificado en Windows
    private static func arrancarConRuntimeIncluido(_ dll: URL) {
        typealias FnRoInitialize = @convention(c) (Int32) -> HRESULT
        typealias FnRoUninitialize = @convention(c) () -> Void
        let combase = "combase.dll".withCString(encodedAs: UTF16.self) { LoadLibraryW($0) }
        let ruta = dll.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? dll.path
        let modulo = ruta.withCString(encodedAs: UTF16.self) { LoadLibraryExW($0, nil, DWORD(LOAD_WITH_ALTERED_SEARCH_PATH)) }
        guard modulo != nil, let combase, let ini = GetProcAddress(combase, "RoInitialize"),
              let fin = GetProcAddress(combase, "RoUninitialize") else {
            let codigo = GetLastError()
            avisarDeError(L("Terminal NetDeck no ha podido cargar el Windows App Runtime que lleva dentro (código \(codigo))."))
            exit(1)
        }
        let roInitialize = unsafeBitCast(ini, to: FnRoInitialize.self)
        let roUninitialize = unsafeBitCast(fin, to: FnRoUninitialize.self)
        let resultado = roInitialize(0)                                                 // RO_INIT_SINGLETHREADED
        guard resultado >= 0 else {
            avisarDeError(L("Terminal NetDeck no ha podido iniciar Windows App Runtime 1.5: \(resultado)"))
            exit(1)
        }
        _ = SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE)
        ejecutarApp()
        roUninitialize()
    }

    private static func avisarDeError(_ texto: String) {
        _ = texto.withCString(encodedAs: UTF16.self) { mensaje in
            "Terminal NetDeck".withCString(encodedAs: UTF16.self) { titulo in
                MessageBoxW(nil, mensaje, titulo, UINT(MB_OK | MB_ICONERROR))
            }
        }
    }

    private static func carpetaDelEjecutable() -> URL? {
        var ruta = [WCHAR](repeating: 0, count: 32768)
        let n = GetModuleFileNameW(nil, &ruta, DWORD(ruta.count))
        guard n > 0, Int(n) < ruta.count else { return nil }
        return URL(fileURLWithPath: String(decoding: ruta.prefix(Int(n)), as: UTF16.self)).deletingLastPathComponent()
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
        guard (ProcessInfo.processInfo.environment["NETDECK_HOME"] ?? "").isEmpty, let carpeta = carpetaDelEjecutable(),
              let datos = PortableMode.dataFolder(executableDirectory: carpeta) else { return }
        try? FileManager.default.createDirectory(at: datos, withIntermediateDirectories: true)
        _ = datos.path.withCString(encodedAs: UTF16.self) { valor in
            "NETDECK_HOME".withCString(encodedAs: UTF16.self) { nombre in SetEnvironmentVariableW(nombre, valor) }
        }
    }

    /// La carpeta `OpenSSH` que llevan la instalación y la portable (Win32-OpenSSH de Microsoft; SystemTools la prefiere), al principio
    /// del PATH de este proceso y de lo que lance: ssh relanza «ssh» a secas para el ProxyJump (-J) y sftp.exe busca ssh.exe, y así
    /// usan el mismo aunque Windows no tenga la característica opcional. Es la carpeta de la app: no da a nadie más de lo que ya
    /// tendría cambiando el propio .exe. no verificado en Windows
    private static func anteponerOpenSSHIncluido() {
        guard let carpeta = carpetaDelEjecutable()?.appendingPathComponent("OpenSSH"),
              FileManager.default.fileExists(atPath: carpeta.appendingPathComponent("ssh.exe").path) else { return }
        let ruta = carpeta.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? carpeta.path
        let actual = ProcessInfo.processInfo.environment.first { $0.key.uppercased() == "PATH" }?.value ?? ""
        _ = (actual.isEmpty ? ruta : ruta + ";" + actual).withCString(encodedAs: UTF16.self) { valor in
            "PATH".withCString(encodedAs: UTF16.self) { nombre in SetEnvironmentVariableW(nombre, valor) }
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
