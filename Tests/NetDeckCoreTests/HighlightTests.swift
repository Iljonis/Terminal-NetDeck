import Foundation
import Testing
@testable import NetDeckCore

@Suite struct HighlightTests {
    static let rulesFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resaltado/netdeck.yml")

    func make() throws -> Highlighter {
        let c = try HighlightConfig(contentsOf: Self.rulesFile)
        return Highlighter(rules: c.rules, palette: Theme.builtIn.highlightPalette)
    }

    /// Quita lo que mete el resaltado: lo que ve el equipo y lo que llega al terminal dicen lo mismo.
    func plain(_ b: [UInt8]) -> String {
        String(decoding: b, as: UTF8.self).replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    @Test func lasReglasDeNetDeckSeLeenTodas() throws {
        let c = try HighlightConfig(contentsOf: Self.rulesFile)
        #expect(c.problems.isEmpty, "\(c.problems)")
        #expect(c.rules.count >= 30)
        #expect(c.palette["cyan"] != nil)
        #expect(c.rules.first { $0.description == "Prompt Juniper (usuario@equipo>)" }?.styles.count == 4)
    }

    @Test func colorea() throws {
        let h = try make()
        let out = String(decoding: h.process(Array("xe-0/0/1 is up, 192.0.2.1/30 -27.5 dBm\r\n".utf8)), as: UTF8.self)
        let cyan = Theme.builtIn.accent2, green = Theme.builtIn.good
        #expect(out.contains("38;2;\(Int(cyan.r));\(Int(cyan.g));\(Int(cyan.b))m192.0.2.1/30"))
        #expect(out.contains("38;2;\(Int(green.r));\(Int(green.g));\(Int(green.b))mup"))
        #expect(out.contains("4;38;2"))                                   // dBm malo: subrayado (exclusiva)
        #expect(plain(Array(out.utf8)) == "xe-0/0/1 is up, 192.0.2.1/30 -27.5 dBm\r\n", "\(out.debugDescription)")
    }

    @Test func respetaLosColoresDelEquipo() throws {
        let h = try make()
        let out = String(decoding: h.process(Array("\u{1b}[33mlink up\u{1b}[0m done\r\n".utf8)), as: UTF8.self)
        #expect(out.contains("\u{1b}[0m\u{1b}[33m"))                      // tras «up», vuelve el amarillo del equipo
        #expect(plain(Array(out.utf8)) == "link up done\r\n")
    }

    @Test func loPartidoEsperaAlSiguienteTrozo() throws {
        let h = try make()
        let a = h.process(Array("ok \u{1b}[3".utf8))
        let b = h.process(Array("1mrojo\u{1b}[0m contraseñ".utf8).dropLast())   // (la «ñ» partida)
        let c = h.process([0xB1] + Array(" 192.0.2.1\n".utf8))
        let all = a + b + c
        #expect(String(decoding: all, as: UTF8.self).contains("\u{1b}[31mrojo"))
        #expect(plain(all) == "ok rojo contraseñ 192.0.2.1\n")
    }

    @Test func pantallaCompletaNoSeToca() throws {
        let h = try make()
        let s = "\u{1b}[?1049h192.0.2.1 up\r\n"
        #expect(h.process(Array(s.utf8)) == Array(s.utf8), "\(String(decoding: h.process(Array(s.utf8)), as: UTF8.self).debugDescription)")
        _ = h.process(Array("\u{1b}[?1049l".utf8))
        #expect(String(decoding: h.process(Array("192.0.2.1\n".utf8)), as: UTF8.self).contains("38;2"))
    }

    @Test func desactivadoPasaTalCual() throws {
        let h = try make()
        h.enabled = false
        #expect(h.process(Array("192.0.2.1 up\n".utf8)) == Array("192.0.2.1 up\n".utf8))
    }

    @Test func gruposYComentariosYAML() throws {
        let c = try HighlightConfig(text: """
            palette:  # >>> paleta
              red: '#ff0000'
            rules:
            - description: Prompt  # comentario
              regex: (?m)^([\\w.-]+)(@)([\\w.-]+)([>#%])
              color: {1: f.red bold, 4: b#00ff00}
              exclusive: true
            - description: Mala
              regex: '(sin cerrar'
              color: f.red
            """)
        #expect(c.palette["red"] == RGB(hex: "#ff0000"))
        #expect(c.rules.count == 1)
        #expect(c.rules[0].description == "Prompt")
        #expect(c.rules[0].styles[4]?.background == "#00ff00")
        #expect(c.problems == ["Mala: expresión no válida"])
        let runs = Highlighter(rules: c.rules, palette: c.palette).styledRuns("admin@core-01>")
        #expect(runs.count == 2)
    }
}
