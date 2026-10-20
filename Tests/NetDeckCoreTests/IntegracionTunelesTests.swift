import Darwin
import Foundation
import Testing
@testable import NetDeckCore

/// Sólo el sshd y HTTP efímeros de tools/test_ssh_local.sh (sin ssh_config, claves ni servicios del usuario).
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["NETDECK_SSH_QA_DIR"] != nil))
struct IntegracionSSHTestsTuneles {
    func until(_ seconds: Double = 20, _ condition: () -> Bool) async throws -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            try Task.checkCancellation()
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(40))
        }
        return condition()
    }

    func freePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        try #require(fd >= 0)
        defer { close(fd) }
        var address = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET),
                                  sin_port: 0, sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
                                  sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        try #require(bound == 0)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        try #require(named == 0)
        return Int(UInt16(bigEndian: address.sin_port))
    }

    func curl(_ url: String, socks: Int? = nil) async throws -> (Int32, String) {
        // (--disable no lee ~/.curlrc; los proxies del entorno tampoco pueden sacar la prueba de loopback)
        var args = ["--disable", "--silent", "--show-error", "--fail", "--connect-timeout", "3", "--max-time", "8"]
        if let socks { args += ["--noproxy", "", "--socks5-hostname", "127.0.0.1:\(socks)"] }
        else { args += ["--proxy", "", "--noproxy", "*"] }
        let process = try TunnelProcess(executable: "/usr/bin/curl", arguments: args + [url],
                                        environment: ["PATH": "/usr/bin:/bin"], captureOutput: true)
        defer { process.signal(SIGKILL) }
        return try await withTaskCancellationHandler {
            let completed = try await until(12) { process.exited }
            try #require(completed, "curl no ha terminado dentro del plazo")
            return (try #require(process.exitStatus) >> 8, process.errorOutput)
        } onCancel: { process.signal(SIGKILL) }
    }

    @Test(arguments: ["qa-direct", "qa-via"], Tunnel.Kind.allCases)
    func reenviaHTTPYAlPararNoQuedanListeners(_ alias: String, _ kind: Tunnel.Kind) async throws {
        let env = ProcessInfo.processInfo.environment
        let folder = URL(fileURLWithPath: try #require(env["NETDECK_SSH_QA_DIR"]))
        let httpText = try #require(env["NETDECK_SSH_QA_HTTP_PORT"])
        let http = try #require(Int(httpText))
        try #require((1...65535).contains(http))
        let config = folder.appendingPathComponent("ssh_config").path
        var port = try freePort()
        while port == http { port = try freePort() }
        let tunnel = Tunnel(name: "qa-\(kind.rawValue)-\(alias)", session: alias, kind: kind,
                            listenPort: port, targetHost: "127.0.0.1", targetPort: http)
        let route = ConnectionRoute(title: alias, target: Endpoint(host: "127.0.0.1"), alias: alias)
        let args = try tunnel.arguments(route: route, sharing: nil, configFile: config)
        let manager = TunnelManager()
        manager.pollInterval = 0.05
        manager.remoteGrace = 0.3
        manager.killAfter = 0.5
        defer { manager.stopAll(wait: 0) }
        manager.start(tunnel, executable: "/usr/bin/ssh", arguments: args,
                      environment: ["PATH": "/usr/bin:/bin", "SSH_ASKPASS_REQUIRE": "never"])
        let settled = try await until {
            manager.state(tunnel.id) == .active || !manager.state(tunnel.id).isRunning
        }
        try #require(settled && manager.state(tunnel.id) == .active, "Estado del túnel: \(manager.state(tunnel.id))")
        let listening = try await until { PortCheck.isListening(address: "127.0.0.1", port: port, timeout: 50) }
        try #require(listening, "no escucha el forward solicitado")
        let url = "http://127.0.0.1:\(kind == .dynamic ? http : port)/"
        let answer = try await curl(url, socks: kind == .dynamic ? port : nil)
        #expect(answer.0 == 0)
        #expect(answer.1 == "netdeck-qa\n")
        await manager.stop(tunnel.id)
        #expect(manager.state(tunnel.id) == .stopped && manager.activeCount == 0)
        // (-R escucha en este mismo Mac porque el servidor de QA también es local; se comprueban ambas familias)
        let closed = try await until(5) {
            !PortCheck.isListening(address: "127.0.0.1", port: port, timeout: 50)
                && !PortCheck.isListening(address: "::1", port: port, timeout: 50)
        }
        #expect(closed)
        #expect(PortCheck.problem(address: "127.0.0.1", port: port) == nil)
    }
}
