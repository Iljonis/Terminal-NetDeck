import Foundation
import Testing
@testable import NetDeckCore

/// tools/test_ssh_local.sh proporciona un sshd y claves efímeras: nunca el ssh_config ni el Llavero del usuario.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["NETDECK_SSH_QA_DIR"] != nil))
struct IntegracionSSHTests {
    var folder: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["NETDECK_SSH_QA_DIR"]!) }
    var config: String { folder.appendingPathComponent("ssh_config").path }
    func route(_ alias: String, transport: SessionProfile.Transport = .ssh) -> ConnectionRoute {
        ConnectionRoute(title: alias, target: Endpoint(host: "127.0.0.1"), transport: transport, alias: alias)
    }
    func run(_ exe: String, _ args: [String]) throws -> (Int32, String) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: exe); process.arguments = args
        let output = Pipe(); process.standardOutput = output; process.standardError = output; process.standardInput = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit(); watchdog.cancel()
        return (process.terminationStatus, text)
    }
    @Test func sshSftpYSaltosConConfiguracionPropia() async throws {
        for name in ["qa-direct", "qa-via"] {
            let cmd = route(name).command(sharing: nil, configFile: config)
            let answer = try run(cmd.executable, ["-o", "BatchMode=yes"] + cmd.arguments + ["printf netdeck-qa"])
            #expect(answer.0 == 0 && answer.1 == "netdeck-qa")
            let sftp = try #require(route(name, transport: .sftp).sftpSubsystemCommand(sharing: nil, configFile: config))
            let fs = try await SFTPFileSystem.connect(label: name, executable: sftp.executable, arguments: sftp.arguments,
                                                     environment: ProcessInfo.processInfo.environment)
            let remote = folder.appendingPathComponent(name + ".cfg")
            try SafeFile.write("hostname core-01\n", to: remote)
            let file = try await RemoteEdit.download(fs, remote.path, into: folder.appendingPathComponent("editor"))
            try SafeFile.write("hostname core-02\n", to: file.local)
            guard case .uploaded = try await RemoteEdit.upload(fs, file) else { Issue.record("no se sube el guardado del editor"); await fs.close(); return }
            #expect(try SafeFile.read(remote) == "hostname core-02\n")
            // (otro escritor cambia el remoto: la edición local se conserva y el remoto no se pisa)
            try SafeFile.write("hostname core-03\n", to: remote)
            try SafeFile.write("hostname core-04\n", to: file.local)
            #expect(try await RemoteEdit.upload(fs, file) == .conflict(.changed))
            #expect(try SafeFile.read(remote) == "hostname core-03\n")
            await fs.close()
        }
    }
    @Test func claveCambiadaRealVerificadaAntesDeLimpiar() throws {
        let cmd = route("qa-mismatch").command(sharing: nil, configFile: config)
        let rejected = try run(cmd.executable, ["-o", "BatchMode=yes"] + cmd.arguments + ["true"])
        #expect(rejected.0 == 255)
        let mismatch = try #require(HostKeyMismatch.detect(rejected.1.components(separatedBy: .newlines)))
        let context = try #require(KnownHosts.context(for: route("qa-mismatch"), configFile: config))
        let allowed = try KnownHosts.verify(mismatch, against: context).get()
        #expect(allowed.file.lastPathComponent == "old_known_hosts")
        #expect(KnownHosts.remove(host: allowed.host, from: allowed.file) == nil)
        // (al aceptar explícitamente la nueva se puede conectar; el archivo distinto queda intacto)
        let accepted = try run(cmd.executable, ["-o", "StrictHostKeyChecking=accept-new", "-o", "BatchMode=yes"] + cmd.arguments + ["true"])
        #expect(accepted.0 == 0)
        #expect(try SafeFile.read(folder.appendingPathComponent("known_hosts"))?.isEmpty == false)
    }
}
