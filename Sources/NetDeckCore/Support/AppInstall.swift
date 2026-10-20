import Foundation

/// Cambiar una .app instalada por otra sin quedarse nunca sin ninguna: la nueva se copia entera a una carpeta temporal
/// junto al destino (mismo disco: cambiarla de nombre es atómico); sólo entonces se aparta la de antes, se pone la nueva
/// y se borra la apartada. Si algo falla, vuelve la de antes y no quedan restos. Si ni siquiera puede volver la de antes,
/// no se borra nada: la carpeta temporal se queda con la nueva y la anterior, y el error dice dónde.
public enum AppInstall {
    public struct Failure: LocalizedError, Equatable {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Instala `source` como `installed` (p. ej. /Applications/Terminal NetDeck.app). Sólo «X.app» dentro de una carpeta
    /// que existe o se puede crear.
    public static func replace(_ installed: URL, with source: URL) throws {
        try replace(installed, with: source, move: { try FileManager.default.moveItem(at: $0, to: $1) })
    }

    /// (`move`: para los tests, que hacen fallar los cambios de nombre)
    static func replace(_ installed: URL, with source: URL, move: (URL, URL) throws -> Void) throws {
        let fm = FileManager.default
        let name = installed.lastPathComponent
        var isDir: ObjCBool = false
        guard name.count > 4, name.hasSuffix(".app"), fm.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue,
              source.standardizedFileURL != installed.standardizedFileURL else {
            throw Failure(message: L("«\(AppPaths.tilde(source.path))» → «\(AppPaths.tilde(installed.path))» no vale"))
        }
        let destination = installed.deletingLastPathComponent()
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let staging = destination.appendingPathComponent(".\(name).nueva-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        var keep = false                                        // (sin app en su sitio: no se borra nada)
        defer { if !keep { try? fm.removeItem(at: staging) } }
        let staged = staging.appendingPathComponent(name)
        do { try fm.copyItem(at: source, to: staged) } catch {
            throw Failure(message: L("no se ha podido copiar la app nueva (sigue la de antes): \(error.localizedDescription)"))
        }
        let previous = staging.appendingPathComponent("anterior.app")
        let hadPrevious = fm.fileExists(atPath: installed.path)
        if hadPrevious {
            do { try move(installed, previous) } catch {
                throw Failure(message: L("no se ha podido apartar la app de antes (sigue en su sitio): \(error.localizedDescription)"))
            }
        }
        do { try move(staged, installed) } catch {
            if hadPrevious {
                do { try move(previous, installed) } catch {
                    keep = true
                    ErrorLog.error("instalar", "ni la nueva ni la anterior en \(installed.path): quedan en \(staging.path)")
                    throw Failure(message: L("no se ha podido poner la app nueva ni volver a la de antes: las dos están en \(AppPaths.tilde(staging.path)) (la anterior es «anterior.app»)"))
                }
            }
            throw Failure(message: L("no se ha podido poner la app nueva (sigue la de antes): \(error.localizedDescription)"))
        }
    }
}
