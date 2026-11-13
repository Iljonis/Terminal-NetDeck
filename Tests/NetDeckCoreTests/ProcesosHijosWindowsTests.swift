#if os(Windows)
import Foundation
import Testing
@testable import NetDeckCore

/// `ChildProcess` en Windows (`CreateProcessW` + Job Object) y `ProcessAlive`: con `cmd.exe`, `powershell.exe` y
/// `ping.exe` a 127.0.0.1, sin red y sin escribir archivos.
@Suite struct ProcesosHijosWindowsTests {
    @Test func salidaYFin() async throws {
        let p = try ChildProcess(executable: cmd, arguments: ["/c", "echo", "hola-hijo"], environment: entorno)
        // (el flujo se acaba solo: nadie más se ha quedado con el extremo de escritura de la tubería)
        let texto = await recoger(p) { _ in false }
        #expect(texto.contains("hola-hijo"))
        #expect(await espera { p.exited })
        #expect(!ProcessAlive.isAlive(p.pid))
    }

    @Test func entradaPorLaTuberia() async throws {
        let p = try ChildProcess(executable: cmd, arguments: ["/q", "/k"], environment: entorno)
        try p.write(Data("echo linea-de-entrada\r\nexit\r\n".utf8))
        let texto = await recoger(p) { _ in false }
        #expect(texto.contains("linea-de-entrada"))
        #expect(await espera { p.exited })
    }

    @Test func argumentosConEspaciosYComillas() async throws {
        let guion = "Write-Output \"dos palabras\" 'y \\ una barra'"
        let p = try ChildProcess(executable: powershell, arguments: ["-NoProfile", "-NonInteractive", "-Command", guion],
                                 environment: entorno)
        let texto = await recoger(p, plazo: .seconds(30)) { _ in false }
        #expect(texto.contains("dos palabras"))
        #expect(texto.contains("y \\ una barra"))
    }

    @Test func terminarSeLlevaAlNieto() async throws {
        let guion = "$n = Start-Process ping.exe -ArgumentList '-n','60','127.0.0.1' -NoNewWindow -PassThru; "
            + "Write-Output \"nieto=$($n.Id)=\"; Start-Sleep -Seconds 60"
        let p = try ChildProcess(executable: powershell, arguments: ["-NoProfile", "-NonInteractive", "-Command", guion],
                                 environment: entorno)
        let texto = await recoger(p, plazo: .seconds(30)) { Self.nieto(en: $0) != nil }
        let nieto = try #require(Self.nieto(en: texto))
        #expect(ProcessAlive.isAlive(p.pid))
        #expect(ProcessAlive.isAlive(nieto))
        p.terminate()
        #expect(await espera { p.exited })
        #expect(await espera { !ProcessAlive.isAlive(p.pid) && !ProcessAlive.isAlive(nieto) })
    }

    @Test func noArrancaLoQueNoSePuede() {
        #expect(throws: RemoteError.self) {
            _ = try ChildProcess(executable: "C:\\no-existe\\nada.exe", arguments: [], environment: entorno)
        }
        // (un .bat lo ejecutaría cmd.exe, con sus reglas de comillas)
        #expect(throws: RemoteError.self) {
            _ = try ChildProcess(executable: "C:\\no-existe\\guion.bat", arguments: ["a"], environment: entorno)
        }
    }

    @Test func procesoVivo() {
        #expect(ProcessAlive.isAlive(ProcessInfo.processInfo.processIdentifier))
        #expect(!ProcessAlive.isAlive(0))
        #expect(!ProcessAlive.isAlive(-1))
    }

    // MARK: - apoyo

    private var sistema: String { (ProcessInfo.processInfo.environment["WINDIR"] ?? "C:\\Windows") + "\\System32" }
    private var cmd: String { sistema + "\\cmd.exe" }
    private var powershell: String { sistema + "\\WindowsPowerShell\\v1.0\\powershell.exe" }
    private var entorno: [String: String] { ProcessInfo.processInfo.environment }

    private static func nieto(en texto: String) -> pid_t? {
        guard let a = texto.range(of: "nieto="), let b = texto.range(of: "=", range: a.upperBound..<texto.endIndex) else {
            return nil
        }
        return pid_t(texto[a.upperBound..<b.lowerBound])
    }

    /// Lo que sale por `output` hasta que `basta` lo da por bueno, el flujo se acaba o pasa el plazo (que termina el
    /// proceso para que el flujo se cierre).
    private func recoger(_ proceso: ChildProcess, plazo: Duration = .seconds(10),
                         basta: (String) -> Bool) async -> String {
        let limite = Task {
            try? await Task.sleep(for: plazo)
            if !Task.isCancelled { proceso.terminate() }
        }
        defer { limite.cancel() }
        var datos = Data()
        for await trozo in proceso.output {
            datos.append(trozo)
            if basta(String(decoding: datos, as: UTF8.self)) { break }
        }
        return String(decoding: datos, as: UTF8.self)
    }

    private func espera(_ plazo: Double = 5, _ condicion: () -> Bool) async -> Bool {
        let fin = Date().addingTimeInterval(plazo)
        while !condicion() {
            if Date() > fin { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
#endif
