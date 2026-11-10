// windows/scripts/askpass-registro.swift: askpass de prueba para el paso P1. Lo compila prueba-askpass.ps1 con swiftc.
// Hace lo mismo que el askpass de NetDeck (un .exe que ssh lanza con la pregunta como argumento), pero sólo apunta la
// pregunta en el archivo de NETDECK_PRUEBA_LOG y contesta una contraseña falsa: la autenticación tiene que fallar.
import Foundation

let pregunta = CommandLine.arguments.dropFirst().joined(separator: " ")
let entorno = ProcessInfo.processInfo.environment
if let ruta = entorno["NETDECK_PRUEBA_LOG"] {
    let linea = "llamado · pregunta: \(pregunta) · SSH_ASKPASS_PROMPT=\(entorno["SSH_ASKPASS_PROMPT"] ?? "-")\n"
    if let h = FileHandle(forWritingAtPath: ruta) {
        h.seekToEndOfFile()
        h.write(Data(linea.utf8))
        h.closeFile()
    } else {
        FileManager.default.createFile(atPath: ruta, contents: Data(linea.utf8))
    }
}
// (una pregunta de sí/no, como la huella del equipo, no se contesta: así no se acepta nada sin querer)
if pregunta.lowercased().contains("yes/no") { exit(1) }
print("no-es-la-clave")
