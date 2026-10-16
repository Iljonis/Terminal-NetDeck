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

    /// MobaXterm Net: el tema fija los colores del resaltado (up verde, down/disconnected/error rojo, IPs y máscaras azul,
    /// protocolos morado) sin tocar las reglas, que siguen diciendo «f.green», «f.cyan», «f.blue»…
    @Test func mobaXtermNet() throws {
        let catalog = Self.rulesFile.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Temas")
        let t = try Theme(contentsOf: catalog.appendingPathComponent("mobaxterm-net.tema"))
        #expect(t.name == "MobaXterm Net" && t.text == RGB(hex: "#ffffff"))
        let p = t.highlightPalette
        #expect(p["green"] == RGB(hex: "#2ecc71") && p["red"] == RGB(hex: "#e74c3c"))
        #expect(p["cyan"] == RGB(hex: "#3498db") && p["blue"] == RGB(hex: "#9b59b6"))
        let c = try HighlightConfig(contentsOf: Self.rulesFile)
        let h = Highlighter(rules: c.rules, palette: p)
        let line = "BGP neighbor 192.0.2.1 255.255.255.0 is Up, OSPF Disconnected, EVPN down, MPLS error, VRRP Connected"
        func color(of word: String) -> String? {
            let r = try? #require(line.range(of: word))
            return h.styledRuns(line).first { r.map($0.range.overlaps) ?? false }?.style.foreground
        }
        for w in ["BGP", "OSPF", "EVPN", "MPLS", "VRRP"] { #expect(color(of: w) == "blue", "\(w)") }
        for w in ["192.0.2.1", "255.255.255.0"] { #expect(color(of: w) == "cyan", "\(w)") }
        for w in ["Up", "Connected"] { #expect(color(of: w) == "green", "\(w)") }
        for w in ["Disconnected", "down", "error"] { #expect(color(of: w) == "red", "\(w)") }
    }

    /// «resaltado =» sólo acepta nombres del resaltado y #hex válidos; sin él, todo sale de los colores del tema.
    @Test func coloresDelResaltadoEnElTema() throws {
        #expect(Theme.highlightColors("green #00ff00, nada #112233, red rojo, blue  #0000ff") ==
                ["green": RGB(hex: "#00ff00")!, "blue": RGB(hex: "#0000ff")!])
        #expect(Theme.builtIn.highlightColors.isEmpty && Theme.builtIn.highlightPalette["blue"] == Theme.builtIn.blue)
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

    @Test func estiloIdaYVuelta() {
        for spec in ["f.cyan bold", "b#00ff00 underline", "f#ff2e88 b.dark bold italic underline", ""] {
            #expect(HighlightStyle(HighlightStyle(spec).spec) == HighlightStyle(spec), "\(spec)")
        }
        #expect(HighlightStyle(foreground: "red", bold: true).spec == "f.red bold")
        #expect(HighlightRule.colorSpec([0: HighlightStyle("f.red")]) == "f.red")
        #expect(HighlightRule.colorSpec([2: HighlightStyle("f.dim"), 1: HighlightStyle("f.cyan bold")]) == "{1: f.cyan bold, 2: f.dim}")
    }

    /// Lo que guarda el editor de Ajustes se vuelve a leer igual (comillas, « #», «: », llaves y grupos incluidos).
    @Test func reglasIdaYVuelta() throws {
        var c = try HighlightConfig(contentsOf: Self.rulesFile)
        c.rules.append(try HighlightRule(description: "Rara: 'comillas' # y dos puntos", regex: #"it's (a) #x: {1,2}\b"#,
                                         styles: [1: HighlightStyle("f#ff0000 bold"), 0: HighlightStyle("b.dim")], exclusive: true))
        let back = try HighlightConfig(text: c.yaml())
        #expect(back.problems.isEmpty, "\(back.problems)")
        #expect(back.palette == c.palette)
        #expect(back.rules.count == c.rules.count)
        for (a, b) in zip(c.rules, back.rules) {
            #expect(a.description == b.description)
            #expect(a.source == b.source)
            #expect(a.styles == b.styles)
            #expect(a.exclusive == b.exclusive)
        }
        #expect(try HighlightConfig(text: back.yaml()).yaml() == back.yaml())
    }

    @Test func compruebaLaExpresion() {
        #expect(HighlightRule.problem(regex: #"\bvlan\s?\d+"#) == nil)
        #expect(HighlightRule.problem(regex: "(sin cerrar") != nil)
        #expect(HighlightRule.problem(regex: "") != nil)
        #expect(HighlightRule.problem(regex: "a*") != nil)                       // (encaja con nada)
        #expect(HighlightRule.problem(regex: "(?P<n>x)y") == nil)               // (sintaxis de Python)
    }

    @Test func reglasDeSerieNuevas() throws {
        let c = try HighlightConfig(contentsOf: Self.rulesFile)
        let h = Highlighter(rules: c.rules, palette: Theme.builtIn.highlightPalette)
        for line in ["%LINK-3-UPDOWN: Interface Gi0/1", "switchport access vlan 120", "uptime is 3w2d", "198.51.100.0/24",
                     "aa:bb:cc:00:11:22", "Neighbor 203.0.113.9 Establ", "AS65001"] {
            #expect(!h.styledRuns(line).isEmpty, "\(line)")
        }
    }
}
