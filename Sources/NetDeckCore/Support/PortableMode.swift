import Foundation

/// La versión portable de Windows (un .zip que se descomprime donde se quiera): si junto al ejecutable hay un archivo
/// `NetDeck.portable`, todo lo de la app (sesiones, botones, listas, copias, registros de depuración) va a la carpeta `datos`
/// de al lado, en vez de a %USERPROFILE% y %APPDATA%. La app de Windows lo aplica al arrancar con `NETDECK_HOME`, el mismo
/// mecanismo de la demo y de los tests: con él el `ssh_config` propio se pasa a ssh con `-F` y no se toca el de `~/.ssh`.
/// La lógica no depende de la plataforma, así que se prueba en macOS.
public enum PortableMode {
    public static let markerName = "NetDeck.portable"
    public static let dataFolderName = "datos"

    /// La carpeta de datos si `executableDirectory` lleva el archivo marcador; nil si no (instalación normal).
    public static func dataFolder(executableDirectory: URL,
                                  fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL? {
        guard fileExists(executableDirectory.appendingPathComponent(markerName).path) else { return nil }
        return executableDirectory.appendingPathComponent(dataFolderName, isDirectory: true)
    }
}
