import Foundation
import Testing
@testable import NetDeckCore

@Suite struct SessionLogTests {
    private func render(_ chunks: [String]) -> [String] {
        var r = LogLineRenderer()
        var out: [String] = []
        for c in chunks { out += r.feed(Array(c.utf8)) }
        if let rest = r.finish() { out.append(rest) }
        return out
    }

    @Test func sinColoresYConSecuenciasPartidas() {
        #expect(render(["\u{1b}[1;3", "2mup\u{1b}[0m 10.0.0.1\r\n"]) == ["up 10.0.0.1"])
        #expect(render(["título\u{1b}]0;ventana\u{07}ok\n"]) == ["títulook"])
    }

    @Test func paginadoresSeBorran() {
        // Huawei: «  ---- More ----» y luego ESC[42D + espacios + ESC[42D
        let more = "  ---- More ----"
        let huawei = "línea 1\r\n" + more + "\u{1b}[42D" + String(repeating: " ", count: 42) + "\u{1b}[42Dlínea 2\r\n"
        #expect(render([huawei]) == ["línea 1", "línea 2"])
        // Cisco: « --More-- » y retrocesos
        let cisco = " --More-- " + String(repeating: "\u{08}", count: 10) + String(repeating: " ", count: 10)
            + String(repeating: "\u{08}", count: 10) + "Gi0/1 up\n"
        #expect(render([cisco]) == ["Gi0/1 up"])
    }

    @Test func retornoDeCarroReescribe() {
        #expect(render(["10%\r50%\r100% hecho\n"]) == ["100% hecho"])
    }

    @Test func utf8Partido() {
        let b = Array("año\n".utf8)
        var r = LogLineRenderer()
        var out = r.feed(b[0..<2])
        out += r.feed(b[2...])
        #expect(out == ["año"])
    }

    @Test func archivoDeRegistro() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try #require(SessionLogger(directory: dir, name: "core 01/x", host: "10.0.0.1"))
        log.feed(Array("\u{1b}[32mhola\u{1b}[0m\r\nadiós".utf8)[...])
        log.close()
        let text = try String(contentsOf: log.url, encoding: .utf8)
        #expect(log.url.lastPathComponent.hasPrefix("core_01_x_"))
        #expect(text.contains("=== NetDeck · 10.0.0.1 · "))
        #expect(text.contains("\nhola\nadiós\n=== fin · "))
        let perms = try FileManager.default.attributesOfItem(atPath: log.url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }
}

@Suite struct PromptDeviceTests {
    @Test func equiposDeCadaMarca() {
        #expect(PromptDevice.name("<core-01>") == "core-01")
        #expect(PromptDevice.name("[~core-01-GigabitEthernet0/0/1]", previous: "core-01") == "core-01")
        #expect(PromptDevice.name("core-01(config-if)#") == "core-01")
        #expect(PromptDevice.name("RP/0/RSP0/CPU0:pe-01#") == "pe-01")
        #expect(PromptDevice.name("admin@mx-01> ") == "mx-01")
        #expect(PromptDevice.name("root@rut955:~#") == "rut955")
        #expect(PromptDevice.name("[admin@MikroTik] >") == "MikroTik")
        #expect(PromptDevice.name("A:admin@bb01.almeria#") == "bb01.almeria")
        #expect(PromptDevice.name("*A:bb01>config>router#") == "bb01")
        #expect(PromptDevice.name("Password:") == nil)
        #expect(PromptDevice.name("show ip route") == nil)
    }
}
