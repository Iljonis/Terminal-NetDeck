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
}

#if canImport(SwiftTerm)
private final class SilentDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
#endif

#endif