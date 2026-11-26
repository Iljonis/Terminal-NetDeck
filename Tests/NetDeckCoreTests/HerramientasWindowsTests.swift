import Foundation
import Testing
@testable import NetDeckCore

/// Dónde buscar ssh.exe y telnet.exe en Windows y qué dice el aviso cuando faltan. Corre también en el Mac: la
/// lógica no depende del sistema (se inyectan `environment` y `exists`).
@Suite struct HerramientasWindowsTests {
    private let env = ["SystemRoot": "C:\\Windows", "ProgramFiles": "C:\\Program Files",
                       "ProgramFiles(x86)": "C:\\Program Files (x86)"]

    private func locate(_ name: String = "ssh", sub: String = "OpenSSH", path: Bool = true, env extra: [String: String] = [:],
                        present: Set<String>) -> String {
        SystemTools.locateWindows(name, subfolder: sub, searchPath: path, environment: env.merging(extra) { $1 },
                                  exists: { present.contains($0) })
    }

    @Test func prefiereElOpenSSHDeSystem32() {
        let sys = "C:\\Windows\\System32\\OpenSSH\\ssh.exe"
        #expect(locate(env: ["PATH": "C:\\Program Files\\OpenSSH"], present: [sys, "C:\\Program Files\\OpenSSH\\ssh.exe"]) == sys)
        // (sin SystemRoot, la carpeta de siempre; y las variables van sin distinguir mayúsculas)
        #expect(SystemTools.locateWindows("ssh", subfolder: "OpenSSH", searchPath: true, environment: [:], exists: { _ in false })
                == sys)
        #expect(SystemTools.locateWindows("ssh", subfolder: "OpenSSH", searchPath: true, environment: ["SYSTEMROOT": "D:\\Win"],
                                          exists: { _ in false }) == "D:\\Win\\System32\\OpenSSH\\ssh.exe")
    }

    @Test func sinSystem32CaeAlPathSoloEnCarpetasDelSistema() {
        let sys = "C:\\Windows\\System32\\OpenSSH\\ssh.exe"
        let pf = "C:\\Program Files\\OpenSSH\\ssh.exe"
        #expect(locate(env: ["Path": "C:\\Tools;C:\\Program Files\\OpenSSH\\"], present: [pf, "C:\\Tools\\ssh.exe"]) == pf)
        // un directorio que cualquier proceso del usuario puede escribir no vale, aunque esté en el PATH
        for malo in ["C:\\Users\\tu.usuario\\Downloads", "C:\\Temp", "D:\\Program Files\\OpenSSH", "C:\\Program Files Evil",
                     "C:\\Program Files\\..\\Users\\tu.usuario", "\\\\198.51.100.7\\share", "bin", "."] {
            let ssh = (malo.hasSuffix("\\") ? malo : malo + "\\") + "ssh.exe"
            #expect(locate(env: ["PATH": malo], present: [ssh]) == sys, "\(malo)")
        }
        #expect(locate(env: ["PATH": "C:\\Tools"], present: []) == sys)       // (ninguno: la de System32, que no existe)
    }

    @Test func telnetSoloEnSystem32() {
        let sys = "C:\\Windows\\System32\\telnet.exe"
        #expect(locate("telnet", sub: "", path: false, present: [sys]) == sys)
        // el PATH no se mira nunca para telnet
        #expect(locate("telnet", sub: "", path: false, env: ["PATH": "C:\\Program Files\\Telnet"],
                       present: ["C:\\Program Files\\Telnet\\telnet.exe"]) == sys)
    }

    private func route(_ transport: SessionProfile.Transport, jumps: [Endpoint] = []) -> ConnectionRoute {
        var r = ConnectionRoute(title: "core-01", target: Endpoint(host: "192.0.2.10", port: 2323), transport: transport)
        r.jumps = jumps
        return r
    }

    @Test func telnetDirectoNoVaPorSsh() {
        let c = route(.telnet).command
        #expect(c.arguments.suffix(2) == ["192.0.2.10", "2323"])
        #expect(!c.arguments.contains("-t") && c.executable != SystemTools.ssh)
        #if !os(Windows)
        #expect(c.executable == "/usr/bin/env" && c.arguments.first == "telnet")
        #endif
        // con salto, el ssh al salto como siempre
        let viaSalto = route(.telnet, jumps: [Endpoint(host: "bastion")]).command
        #expect(viaSalto.executable == SystemTools.ssh && viaSalto.arguments.suffix(3) == ["telnet", "192.0.2.10", "2323"])
    }

    @Test func elAvisoNombraElProgramaQueFalta() {
        let telnet = ConnectionRoute.missingProgram("C:\\Windows\\System32\\telnet.exe", windows: true)
        #expect(telnet.contains("telnet.exe") && !telnet.contains("ssh.exe") && telnet.contains("Telnet"))
        let ssh = ConnectionRoute.missingProgram("C:\\Windows\\System32\\OpenSSH\\ssh.exe", windows: true)
        #expect(ssh.contains("ssh.exe") && !ssh.contains("Telnet"))
        #expect(ConnectionRoute.missingProgram("C:\\Windows\\System32\\OpenSSH\\sftp.exe", windows: true).contains("sftp.exe"))
        #expect(ConnectionRoute.missingProgram("/usr/bin/ssh", windows: false).contains("/usr/bin/ssh"))
        // y launchProblem lo usa: el ejecutable que falta de verdad (telnet directo ≠ ssh)
        let faltaTodo = route(.telnet).launchProblem { _ in false }
        #expect(faltaTodo != nil)
        #expect(route(.telnet).launchProblem { _ in true } == nil)
    }
}
