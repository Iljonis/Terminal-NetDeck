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

    @Test func pasaElEntornoPreparado() async throws {
        var env = entorno
        env["NETDECK_CONPTY_TEST"] = "entorno-conpty-ok"
        let proceso = try ConPTYProcess(executable: cmd, arguments: ["/c", "set", "NETDECK_CONPTY_TEST"],
                                        environment: env)
        defer { proceso.terminate() }
        let esperado = "NETDECK_CONPTY_TEST=entorno-conpty-ok"
        let datos = await recoger(proceso, plazo: .seconds(5)) { $0.range(of: Data(esperado.utf8)) != nil }
        #expect(String(decoding: datos, as: UTF8.self).contains(esperado))
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

    // MARK: - P7 tarea 4: secuencias VT avanzadas

    /// ConPTY transmite secuencias de color de 256 colores sin modificarlas.
    /// Nota: ConPTY puede convertir ESC[38;5;Nm a SGR básico (ej: ESC[31m) dependiendo de la versión de Windows.
    /// Si este test falla, ConPTY suprime/convierte la secuencia; documentado en windows/ESTADO.md.
    @Test func color256() async throws {
        let proceso = try ConPTYProcess(
            executable: pshPath,
            arguments: ["-NoProfile", "-NonInteractive", "-Command",
                        "Write-Host ([char]27 + '[38;5;196mROJO' + [char]27 + '[0m')"],
            environment: entorno)
        defer { proceso.terminate() }
        let datos = await recoger(proceso, plazo: .seconds(10)) { $0.range(of: Data("ROJO".utf8)) != nil }
        let texto = String(decoding: datos, as: UTF8.self)
        #expect(texto.contains("ROJO"), "El texto visible debe llegar aunque se supriman los colores")
        #expect(texto.contains("\u{1B}[38;5;196m"),
                "ConPTY debería transmitir la secuencia de 256 colores sin modificarla")
    }

    /// ConPTY transmite secuencias de color de 24 bits (true color) sin modificarlas.
    /// Nota: ConPTY puede suprimir true color en hosts sin COLORTERM=truecolor.
    /// Si este test falla, ConPTY suprime/convierte ESC[38;2;R;G;Bm; documentado en windows/ESTADO.md.
    @Test func color24bit() async throws {
        let proceso = try ConPTYProcess(
            executable: pshPath,
            arguments: ["-NoProfile", "-NonInteractive", "-Command",
                        "Write-Host ([char]27 + '[38;2;255;0;0mROJO_TC' + [char]27 + '[0m')"],
            environment: entorno)
        defer { proceso.terminate() }
        let datos = await recoger(proceso, plazo: .seconds(10)) { $0.range(of: Data("ROJO_TC".utf8)) != nil }
        let texto = String(decoding: datos, as: UTF8.self)
        #expect(texto.contains("ROJO_TC"), "El texto visible debe llegar aunque se supriman los colores")
        #expect(texto.contains("\u{1B}[38;2;255;0;0m"),
                "ConPTY debería transmitir la secuencia de true color sin modificarla")
    }

    /// ConPTY transmite la secuencia OSC de título de ventana al lector de la tubería.
    /// Nota: conhost.exe puede consumir OSC 0 internamente y no reenviarlo.
    /// Si este test falla, ConPTY consume OSC 0; documentado en windows/ESTADO.md.
    @Test func tituloVentana() async throws {
        // ESC ]0;titulo-prueba BEL establece el título de la ventana del terminal.
        let proceso = try ConPTYProcess(
            executable: pshPath,
            arguments: ["-NoProfile", "-NonInteractive", "-Command",
                        "Write-Host -NoNewLine ([char]27 + ']0;titulo-prueba' + [char]7);" +
                        " Write-Host 'TITULO_OK'"],
            environment: entorno)
        defer { proceso.terminate() }
        let datos = await recoger(proceso, plazo: .seconds(10)) { $0.range(of: Data("TITULO_OK".utf8)) != nil }
        let texto = String(decoding: datos, as: UTF8.self)
        #expect(texto.contains("TITULO_OK"), "El texto posterior al OSC tiene que llegar")
        #expect(texto.contains("\u{1B}]0;titulo-prueba"),
                "ConPTY debería transmitir la secuencia OSC de título al lector")
    }

    /// ConPTY no bloquea el flujo de salida al recibir ESC[?1000h (activación del ratón) en el input.
    /// Nota: ConPTY puede ignorar la secuencia de ratón (no la reenvía al proceso hijo).
    /// Lo que verificamos aquí es que el flujo no se bloquea; el eco de ratón se prueba en P8 con la interfaz.
    @Test func activacionRaton() async throws {
        // ESC[?1000h activa el modo X10 de seguimiento del ratón.
        let proceso = try ConPTYProcess(executable: cmd, arguments: ["/c", "echo", "RATON_OK"], environment: entorno)
        defer { proceso.terminate() }
        // Enviamos la secuencia al input; cmd /c echo no es interactivo pero ConPTY no debe bloquear la salida.
        try? proceso.write(Data("\u{1B}[?1000h".utf8))
        let datos = await recoger(proceso, plazo: .seconds(5)) { $0.range(of: Data("RATON_OK".utf8)) != nil }
        let texto = String(decoding: datos, as: UTF8.self)
        #expect(texto.contains("RATON_OK"),
                "ConPTY no debe bloquear la salida tras recibir \\e[?1000h en el input")
    }

    // MARK: - apoyo

    private var cmd: String {
        (ProcessInfo.processInfo.environment["WINDIR"] ?? "C:\\Windows") + "\\System32\\cmd.exe"
    }

    private var pshPath: String {
        (ProcessInfo.processInfo.environment["WINDIR"] ?? "C:\\Windows") +
        "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
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