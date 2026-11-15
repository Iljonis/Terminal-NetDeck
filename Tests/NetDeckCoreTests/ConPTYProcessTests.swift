#if os(Windows)
import WinSDK
import Foundation
import Testing
#if canImport(SwiftTerm)
import SwiftTerm
#endif
@testable import NetDeckCore

/// `ConPTYProcess` (la pseudoconsola de Windows): lo que escribe un `cmd.exe /c echo …` llega por `output`, y pasado
/// por un SwiftTerm sin vista se lee en el búfer igual que lo leerá la pestaña. Sin red y sin escribir archivos.
@Suite struct ConPTYProcessTests {
    @Test func salidaDeCmd() async throws {
        let proceso = try ConPTYProcess(executable: cmd, arguments: ["/c", "echo", "test-conpty"], environment: entorno)
        defer { proceso.terminate() }
        let datos = await recoger(proceso, plazo: .seconds(5)) { $0.range(of: Data("test-conpty".utf8)) != nil }
        let texto = String(decoding: datos, as: UTF8.self)
        #expect(texto.contains("test-conpty"))
    }

    /// La pregunta de contraseña sale de la pseudoconsola entre secuencias VT (borrado, cursor, título de ventana).
    /// En el texto en bruto, `Askpass.secretQuestion` (busca en cualquier parte de la línea) la sigue reconociendo.
    @Test func deteccionDePromptConPTY() async throws {
        let proceso = try ConPTYProcess(executable: cmd, arguments: ["/c", "echo", "Password:"], environment: entorno)
        defer { proceso.terminate() }
        let datos = await recoger(proceso, plazo: .seconds(5)) { $0.range(of: Data("Password:".utf8)) != nil }
        let texto = String(decoding: datos, as: UTF8.self)
        #expect(texto.contains("Password:"))
        let lineas = texto.components(separatedBy: .newlines)
        #expect(lineas.contains { Askpass.secretQuestion.matches($0) },
                "Askpass.secretQuestion debería reconocer la pregunta en la salida de ConPTY")
    }

    /// Lo mismo con `PasswordPrompt`, que es más estricto (la palabra al principio de la línea o tras un espacio): con
    /// las secuencias VT quitadas reconoce la petición, su cuenta y su usuario, y sólo en esa línea.
    @Test func promptDeContrasenaSinSecuenciasVT() async throws {
        let proceso = try ConPTYProcess(executable: cmd, arguments: ["/c", "echo", "tu.usuario@core-01's", "password:"],
                                        environment: entorno)
        defer { proceso.terminate() }
        let datos = await recoger(proceso, plazo: .seconds(5)) { $0.range(of: Data("password:".utf8)) != nil }
        let lineas = sinVT(String(decoding: datos, as: UTF8.self)).components(separatedBy: .newlines)
        let piden = lineas.filter(PasswordPrompt.asksForPassword)
        #expect(piden.count == 1)
        let peticion = PasswordPrompt.detect(cursorLine: try #require(piden.first), above: [])
        #expect(peticion?.account == "tu.usuario@core-01")
        #expect(peticion?.user == "tu.usuario")
        #expect(peticion?.isChangeOrConfirm == false)
        #expect(piden.allSatisfy(SecretPrompt.asks))
    }

#if canImport(SwiftTerm)
    @Test func salidaAtravesDelBufer() async throws {
        let proceso = try ConPTYProcess(executable: cmd, arguments: ["/c", "echo", "Gi0/0", "192.0.2.1", "up"],
                                        environment: entorno)
        defer { proceso.terminate() }
        let datos = await recoger(proceso, plazo: .seconds(15)) { $0.range(of: Data("192.0.2.1 up".utf8)) != nil }
        #expect(!datos.isEmpty)

        let silencioso = SilentDelegate()
        let t = Terminal(delegate: silencioso, options: TerminalOptions(cols: 80, rows: 24, scrollback: 100))
        t.feed(byteArray: [UInt8](datos))
        let filas = t.contentSnapshot(region: .all).rows.map(\.text)
        #expect(filas.contains { $0.contains("Gi0/0") || $0.contains("192.0.2") })
    }
#endif

    // MARK: - apoyo

    private var cmd: String {
        (ProcessInfo.processInfo.environment["WINDIR"] ?? "C:\\Windows") + "\\System32\\cmd.exe"
    }

    private var entorno: [String: String] { ProcessInfo.processInfo.environment }

    /// Lo que sale por `output` hasta que `basta` lo da por bueno, el proceso acaba o pasa el plazo. La pseudoconsola
    /// no cierra su tubería de salida al acabar el proceso (sólo con `ClosePseudoConsole`), así que el plazo termina
    /// el proceso para que el flujo se cierre.
    private func recoger(_ proceso: ConPTYProcess, plazo: Duration = .seconds(3),
                         basta: (Data) -> Bool) async -> Data {
        let limite = Task {
            try? await Task.sleep(for: plazo)
            if !Task.isCancelled { proceso.terminate() }
        }
        defer { limite.cancel() }
        var datos = Data()
        for await trozo in proceso.output {
            datos.append(trozo)
            if basta(datos) { break }
        }
        return datos
    }

    /// El texto sin las secuencias VT que mete la pseudoconsola: CSI (`ESC [ … letra`) y OSC (`ESC ] … BEL` o `ESC \`).
    private func sinVT(_ texto: String) -> String {
        texto.replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]|\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)"#,
                                   with: "", options: .regularExpression)
    }
}

#if canImport(SwiftTerm)
private final class SilentDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
#endif

#endif