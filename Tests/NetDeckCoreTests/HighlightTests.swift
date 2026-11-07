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

    /// Los selectores nombran el color que se ve, no el hueco: en NetDeck Cyberpunk «cyan» es rosa y «yellow», cian; y
    /// si se cambia «cyan» a verde, dice verde. Los huecos de los archivos («f.cyan») siguen igual.
    @Test func nombreDelColorQueSeVe() throws {
        func tono(_ hex: String) throws -> Tono { try #require(RGB(hex: hex)).tono.tono }
        let p = Theme.builtIn.highlightPalette
        #expect(p["cyan"]?.tono.tono == .rosa && p["yellow"]?.tono.tono == .cian && p["magenta"]?.tono.tono == .morado)
        #expect(p["dark"]?.tono.tono == .negro && p["white"]?.tono.tono == .blanco)
        for (hex, t) in [("#fcee0a", Tono.amarillo), ("#00f0ff", .cian), ("#ff003c", .rojo), ("#00ff9f", .verde),
                         ("#ff2bd6", .magenta), ("#fe7723", .naranja), ("#7397ed", .azul), ("#08090d", .negro),
                         ("#5e8a94", .cian), ("#00ff00", .verde), ("#ffffff", .blanco), ("#808080", .gris),
                         ("#2ecc71", .verde), ("#e74c3c", .rojo), ("#3498db", .azul), ("#9b59b6", .morado)] {
            #expect(try tono(hex) == t, "\(hex)")
        }
        #expect(try #require(RGB(hex: "#ffd1e8")).tono == (.rosa, 1) && RGB(hex: "#00401f")!.tono == (.verde, -1))
        // (oliva: Solarized #859900, Gruvbox #b8bb26 y #66620c, verdes; el amarillo de Solarized, #b58900, no)
        for (hex, t) in [("#859900", Tono.verde), ("#b8bb26", .verde), ("#66620c", .verde), ("#b58900", .amarillo),
                         ("#7a5f9a", .morado), ("#b9b9dc", .azul), ("#c4a0c0", .magenta), ("#ffc0cb", .rosa)] {
            #expect(try tono(hex) == t, "\(hex)")
        }
        #expect(RGB(hex: "#66620c")!.tono == (.verde, -1))
        #expect(RGB(hex: "#c8c8c8")!.tono == (.gris, 1) && RGB(hex: "#404040")!.tono == (.gris, -1)
                && RGB(hex: "#808080")!.tono == (.gris, 0))
        #expect(RGB(hex: "#c8c8c8")!.nombre == L("\(Tono.gris.nombre) claro"))
        #expect(Theme.builtIn.background.contraste(Theme.builtIn.background) == 1 && RGB.white.contraste(.black) > 20)
        #expect(Set(Tono.allCases.map(\.nombre)).count == Tono.allCases.count)
        #expect(Idioma.traducir("\(Idioma.traducir("rosa", a: .en)) claro", a: .en) == "light pink")
        // (cambiar el hueco «cyan» a verde: el nombre pasa a «verde»; el archivo sigue diciendo «f.cyan»)
        let mine = p.merging(["cyan": RGB(hex: "#00ff00")!]) { $1 }
        #expect(mine["cyan"]?.nombre == Tono.verde.nombre)
        #expect(Theme.highlightColors("cyan #00ff00")["cyan"] == RGB(hex: "#00ff00"))
        #expect(HighlightStyle("f.cyan bold").foreground == "cyan")
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

    /// Los nombres largos de Cisco se colorean enteros, como «GigabitEthernet»: «TenGigabitEthernet0/1» salía sin color
    /// (la regla aceptaba «TenGigabitE» y luego esperaba el número).
    @Test func interfacesConNombreLargo() throws {
        let c = try HighlightConfig(contentsOf: Self.rulesFile)
        let h = Highlighter(rules: c.rules, palette: Theme.builtIn.highlightPalette)
        for name in ["GigabitEthernet0/0/0", "TenGigabitEthernet0/1", "TwentyFiveGigE1/0/1", "FortyGigabitEthernet1/1/1",
                     "HundredGigE0/0/0/1", "HundredGigabitEthernet0/1/0", "FourHundredGigE0/0/0/2", "TenGigE0/0/0/3",
                     "Te1/0/1"] {
            let line = "interface \(name) is up"
            let r = try #require(line.range(of: name))
            #expect(h.styledRuns(line).contains { $0.range.lowerBound <= r.lowerBound && $0.range.upperBound >= r.upperBound },
                    "\(name)")
        }
    }

    /// Nokia SR7750 (SR-OS / TiMOS): prompts clásico y MD-CLI, contexto, puertos, alarmas, estados, AS e IPs.
    @Test func nokiaSROS() throws {
        let c = try HighlightConfig(contentsOf: Self.rulesFile)
        let h = Highlighter(rules: c.rules, palette: Theme.builtIn.highlightPalette)
        func color(_ word: String, in line: String) -> String? {
            guard let r = line.range(of: word) else { return "«\(word)» no está" }
            return h.styledRuns(line).first { $0.range.lowerBound <= r.lowerBound && $0.range.upperBound >= r.upperBound }?
                .style.foreground
        }
        func runStyle(_ word: String, in line: String) -> HighlightStyle? {
            guard let r = line.range(of: word) else { return nil }
            return h.styledRuns(line).first { $0.range.lowerBound <= r.lowerBound && $0.range.upperBound >= r.upperBound }?.style
        }
        let classic = "*A:PE-MAD-01>config>router# show router interface"
        #expect(color("*", in: classic) == "red")                  // cambios sin guardar
        #expect(color("A", in: classic) == "magenta")              // CPM activa
        #expect(color("PE-MAD-01", in: classic) == "yellow")
        #expect(color(">config>router", in: classic) == "blue")
        #expect(color("# ", in: classic) == nil || color("#", in: classic) == "red")
        #expect(color("show", in: classic) == nil && runStyle("show", in: classic)?.bold == true)   // la orden, en negrita
        let md = "A:admin@PE-MAD-01# admin display-config"
        #expect(color("admin@", in: md) == nil)                   // (usuario y @ van aparte)
        #expect(color("PE-MAD-01", in: md) == "yellow")
        #expect(color("admin display-config", in: md) == nil)
        #expect(h.styledRuns(md).contains { md[$0.range] == "admin" && $0.range.lowerBound > md.startIndex && $0.style.bold })
        let ctx = "[ex:/configure service vprn \"100\"]"
        #expect(color("ex:", in: ctx) == "magenta")
        #expect(color("/configure service vprn \"100\"", in: ctx) == "blue")
        for port in ["1/1/1", "1/1/c1/1", "1/2/c2", "esat-1/1/3", "lag-10"] {
            #expect(color(port, in: "Port \(port) is up") == "yellow", "\(port)")
        }
        #expect(color("2026/10/17", in: "5 2026/10/17 10:12:01.33 CEST MINOR: PORT #2004") == "dim")   // fecha, no puerto
        #expect(color("0/75/0/0", in: "  Input queue: 0/75/0/0 (size/max/drops/flushes)") == nil)    // la cola de Cisco, no
        for (w, col) in [("CRITICAL", "red"), ("MAJOR", "red"), ("MINOR", "orange"), ("WARNING", "orange"), ("CLEARED", "green"),
                         ("FLAG_NOK", "red")] {
            #expect(color(w, in: "12 2026/10/17 10:12:01 CEST \(w): CHASSIS #2001 Base") == col, "\(w)")
        }
        let state = "Admin State       : Up                Oper State        : Down"
        #expect(color("Admin State", in: state) == "blue" && color("Oper State", in: state) == "blue")
        #expect(color("Up", in: state) == "green" && color("Down", in: state) == "red")
        #expect(color("Local AS          : 65001", in: "Local AS          : 65001") == "blue")
        #expect(color("Autonomous System : 65001", in: "Autonomous System : 65001") == "blue")
        #expect(color("2001:db8::1/64", in: "IPv6 Address : 2001:db8::1/64") == "cyan")
    }

    /// Las reglas de serie que no están en las personalizadas (las que trae una versión nueva) se añaden en su sitio,
    /// detrás de la de serie que las precede; las del usuario (cambiadas o suyas) no se tocan.
    @Test func anadirLasNuevasDeSerie() throws {
        func r(_ d: String, _ re: String = "x") throws -> HighlightRule {
            try HighlightRule(description: d, regex: re, styles: [0: HighlightStyle(foreground: "red")])
        }
        let bundled = try [r("A"), r("Nueva1"), r("B"), r("C"), r("Nueva2")]
        let mine = try [r("Mía"), r("C", "cambiada"), r("A")]
        #expect(HighlightConfig.missing(from: bundled, in: mine).map(\.description) == ["Nueva1", "B", "Nueva2"])
        let merged = HighlightConfig.addingMissing(from: bundled, to: mine)
        #expect(merged.map(\.description) == ["Mía", "C", "Nueva2", "A", "Nueva1", "B"])
        #expect(merged.first { $0.description == "C" }?.source == "cambiada")
        #expect(HighlightConfig.addingMissing(from: bundled, to: merged).map(\.description) == merged.map(\.description))
        let none = try [r("Nueva0")]
        #expect(HighlightConfig.addingMissing(from: none, to: []).map(\.description) == ["Nueva0"])
    }

    /// El color de lo que cubre `word` (la primera vez que sale en `line`; nil = sin color).
    func color(_ word: String, in line: String, _ h: Highlighter) -> String? {
        guard let r = line.range(of: word) else { return "«\(word)» no está" }
        return h.styledRuns(line).first { $0.range.lowerBound <= r.lowerBound && $0.range.upperBound >= r.upperBound }?
            .style.foreground
    }

    /// Contadores con el número delante (IOS, IOS-XR, NX-OS) o detrás (Junos, Huawei, Linux): rojo sólo si no es 0.
    @Test func contadoresDeErrores() throws {
        let h = try make()
        var l = "     12 input errors, 10 CRC, 0 frame, 0 overrun, 0 ignored"
        #expect(color("12", in: l, h) == "red" && color("input errors", in: l, h) == "orange")
        #expect(color("10", in: l, h) == "red" && color("CRC", in: l, h) == "orange")
        #expect(color("frame", in: l, h) == nil && color("overrun", in: l, h) == nil)
        l = "     0 output errors, 0 collisions, 3 interface resets"
        #expect(color("3", in: l, h) == "red" && color("interface resets", in: l, h) == "orange")
        #expect(color("output errors", in: l, h) == nil)
        l = "     0 lost carrier, 0 no carrier"
        #expect(color("lost", in: l, h) == nil && color("no carrier", in: l, h) == nil)
        l = "     2 lost carrier, 0 no carrier"
        #expect(color("2", in: l, h) == "red" && color("lost carrier", in: l, h) == "orange")
        l = "  0 input error  0 short frame  4 overrun   0 underrun  0 ignored"           // NX-OS
        #expect(color("4", in: l, h) == "red" && color("overrun", in: l, h) == "orange" && color("short frame", in: l, h) == nil)
        #expect(color("error", in: l, h) == nil && color("error", in: "  0 output error  0 collision  0 deferred", h) == nil)
        l = "  0 watchdog  0 bad etype drop  0 bad proto drop  0 if down drop"
        #expect(color("down", in: l, h) == nil)
        l = "  1 carrier transitions"                                                   // IOS-XR
        #expect(color("1", in: l, h) == "red")
        l = "    Input errors: 12, Drops: 0, Framing errors: 0, Runts: 0, Policed discards: 0"   // Junos
        #expect(color("12", in: l, h) == "red" && color("Input errors", in: l, h) == "orange" && color("Drops", in: l, h) == nil)
        l = "    Carrier transitions: 1, Errors: 0, Drops: 0, Collisions: 0"           // (el 1 no es de «Errors»)
        #expect(color("Carrier transitions", in: l, h) == "orange" && color("1", in: l, h) == "red" && color("Errors", in: l, h) == nil)
        l = "  CRC:                2, Giants:              0"                            // Huawei
        #expect(color("2", in: l, h) == "red" && color("Giants", in: l, h) == nil)
        l = "     rx_crc_errors: 12"                                                     // ethtool -S
        #expect(color("rx_crc_errors", in: l, h) == "orange" && color("12", in: l, h) == "red")
        #expect(h.styledRuns("     rx_missed_errors: 0").isEmpty)
        l = "        TX errors 0  dropped 3 overruns 0  carrier 0  collisions 0"         // ifconfig: el 3 es de «dropped»
        #expect(color("dropped", in: l, h) == "orange" && color("3", in: l, h) == "red" && color("overruns", in: l, h) == nil)
        l = "  Input queue: 0/75/0/0 (size/max/drops/flushes); Total output drops: 7"
        #expect(color("0/75/0/0", in: l, h) == nil && color("Total output drops", in: l, h) == nil)
        #expect(color("7", in: "  Total output drops: 7", h) == "red")
        l = "    CRC/Align errors                        5                0"            // Junos: columnas al final
        #expect(color("5", in: l, h) == "red" && color("errors", in: l, h) == "orange")
        l = "    0 runts  0 giants  0 CRC  5 no buffer"                                 // NX-OS: el 5 es de «no buffer»
        #expect(color("CRC", in: l, h) == nil && color("5", in: l, h) == "red" && color("no buffer", in: l, h) == "orange")
        l = "     1 carrier transitions"
        #expect(color("1", in: l, h) == "red" && color("carrier transitions", in: l, h) == "orange")
        l = "     12 total input drops, 0 total output drops"                           // IOS-XR
        #expect(color("12", in: l, h) == "red" && color("total input drops", in: l, h) == "orange")
        #expect(h.styledRuns("     0 output buffer failures, 4 output buffers swapped out").isEmpty)
    }

    /// La rama de Linux («rx_…_errors») tiene topes: una palabra de 4096 caracteres tardaba 47-76 ms.
    @Test func contadoresDeLinuxRapidosEnPalabrasLargas() throws {
        let c = try HighlightConfig(contentsOf: Self.rulesFile)
        let rule = try #require(c.rules.first { $0.description == "Contador de errores distinto de cero" })
        let line = String(repeating: "tx_drop_", count: 512)
        var best = Double.infinity
        for _ in 0..<10 {
            let t0 = Date()
            _ = rule.regex.allMatches(line)
            best = min(best, Date().timeIntervalSince(t0))
        }
        #expect(best < 0.005, "\(best * 1000) ms")
    }

    /// BGP: Active, Idle y Connect en la columna de estado, en rojo; una parada a propósito (Idle (Admin),
    /// administratively down, *down), en «dim»; Active de HSRP o de systemd, no.
    @Test func estadosDeBGPYParadas() throws {
        let h = try make()
        for l in ["192.0.2.2       4        65002       0       0        1    0    0 never    Active",          // IOS
                  "192.0.2.3       4        65003       0       0        1    0    0 00:01:12 Idle",
                  "192.0.2.5       4        65005       0       0        1    0    0 00:00:05 Connect",
                  "198.51.100.9          65009          0          0       0       3        12:01 Active",     // Junos
                  "  203.0.113.2     4       65002        0        0     0 00:00:12      Active        0",   // Huawei
                  "                65001       0    0 01h02m03s Active",                                    // Nokia
                  "2001:db8::2     4        65006       0       0        1    0    0 never    Active",
                  "  BGP state = Active",
                  "  Type: External    State: Active         Flags: <>"] {
            let state = try #require(["Active", "Idle", "Connect"].first { l.hasSuffix($0) || l.contains("\($0) ") })
            #expect(color(state, in: l, h) == "red", "\(l)")
        }
        #expect(color("192.0.2.2", in: "192.0.2.2       4        65002       0       0        1    0    0 never    Active", h) == "cyan")
        #expect(color("Idle (Admin)", in: "192.0.2.4       4        65004       0       0        1    0    0 never    Idle (Admin)", h) == "dim")
        #expect(color("Up/Down", in: "Neighbor        V           AS MsgRcvd MsgSent   TblVer  InQ OutQ Up/Down  State/PfxRcd", h) == nil)
        #expect(color("Active", in: "Vl10        10   110 P Active  local           192.0.2.3       192.0.2.1", h) == nil)   // HSRP
        #expect(color("active (running)", in: "     Active: active (running) since Sat 2026-11-07", h) == "green")
        #expect(color("administratively down", in: "GigabitEthernet0/2     unassigned      YES unset  administratively down down", h) == "dim")
        #expect(color("*down", in: "GE0/0/2                 *down    down        0%     0%", h) == "dim")
        #expect(color("admin down", in: "Gi0/3                          admin down     down     ", h) == "dim")
        #expect(color("shutdown", in: " shutdown", h) == "dim")
        #expect(color("Shut (Admin)", in: "192.0.2.12      4 65012       0       0        0    0    0 00:05:00 Shut (Admin)", h) == "dim")
        #expect(color("down", in: "GigabitEthernet0/1 is down, line protocol is down", h) == "red")
    }

    /// Syslog de IOS-XR (%FAC-SUB-SEV-MSG) y Huawei (%%01MOD/SEV/MSG(t)) con la gravedad de IOS.
    @Test func syslogIOSXRYHuawei() throws {
        let h = try make()
        for (msg, col) in [("%PKT_INFRA-LINK-3-UPDOWN", "red"), ("%PLATFORM-ENVMON-4-ALARM", "orange"),
                           ("%PKT_INFRA-LINEPROTO-5-UPDOWN", "cyan"), ("%%01DEVM/1/hwBoardFail_active(t)", "red"),
                           ("%%01IFNET/4/LINK_STATE(l)", "orange"), ("%%01SHELL/5/CMDRECORD(s)", "cyan"),
                           ("%LINK-3-UPDOWN", "red"), ("%SYS-5-CONFIG_I", "cyan")] {
            let l = "RP/0/RSP0/CPU0:Nov  7 10:12:01.123 UTC: core-01 \(msg)[0]: Interface GigabitEthernet0/0/0/1, changed state to Down"
            #expect(color(msg, in: l, h) == col, "\(msg)")
        }
    }

    /// Lo que no es un estado: cabeceras, opciones de la configuración, «Not OK», descripciones y una IPv6 con «dead».
    @Test func sinFalsosPositivos() throws {
        let h = try make()
        #expect(color("Dead", in: "Neighbor ID     Pri   State           Dead Time   Address         Interface", h) == nil)
        #expect(color("Dead", in: "  Timer intervals configured, Hello 10, Dead 40, Wait 40, Retransmit 5", h) == nil)
        #expect(color("dead", in: " ip ospf dead-interval 40", h) == nil)
        #expect(color("Dead", in: "Address          Interface              State     ID               Pri  Dead", h) == nil)   // Junos
        #expect(color("dead", in: "Status: dead", h) == "red")
        #expect(color("timeout", in: " exec-timeout 10 0", h) == nil)
        #expect(color("timeout", in: "radius-server timeout 5", h) == nil)
        #expect(color("timeout", in: "Connection timeout", h) == "red")
        #expect(color("Not OK", in: "Fan 1: Not OK", h) == "red")
        #expect(color("OK", in: "Fan 2: OK", h) == "green")
        #expect(color("OK", in: "Interface              IP-Address      OK? Method Status                Protocol", h) == nil)
        #expect(color("shutdown", in: " no shutdown", h) == nil && color("shutdown", in: " undo shutdown", h) == nil)
        for l in [" description Uplink core-01 down for maintenance", "  Description: backup link down, up soon",
                  #"    description "to core-01 - link down";"#] {
            #expect(color("down", in: l, h) == nil, "\(l)")
        }
        #expect(color("dead:beef::1/64", in: "IPv6 Address : dead:beef::1/64", h) == "cyan")
        #expect(color("2001:db8:dead::1", in: "  2001:db8:dead::1  ", h) == "cyan")
        let junos = "  Link-level type: Ethernet, MTU: 1514, Speed: 1000mbps, BPDU Error: None, Loop Detect PDU Error: None"
        #expect(!h.styledRuns(junos).contains { $0.style.foreground == "red" })
        #expect(color("error", in: "  error: configuration check-out failed", h) == "red")
    }

    /// Nombres de interfaz que no salían (Cisco, NX-OS, Junos, Huawei): todos en amarillo y enteros.
    @Test func interfacesQueFaltaban() throws {
        let h = try make()
        for name in ["BDI100", "BVI1", "BE1", "nve1", "irb", "irb.100", "Twe1/0/1", "400GE1/0/1", "MEth0/0/1", "mgmt0",
                     "Management1", "Tunnel0", "reth0", "FastEthernet0/1", "Vl10", "Ethernet1/1.100"] {
            #expect(color(name, in: "interface \(name) is up", h) == "yellow", "\(name)")
        }
    }

    /// «Interfaces» va agrupada por la primera letra: en una línea de 4000 caracteres llena de palabras cortas tardaba
    /// 4-6 ms (10-18 en el Mac del autor) y ahora ~1 ms. Margen amplio para la CI: el mejor de 10 intentos, < 5 ms.
    @Test func interfacesRapidaEnLineasLargas() throws {
        let c = try HighlightConfig(contentsOf: Self.rulesFile)
        let rule = try #require(c.rules.first { $0.description == "Interfaces" })
        let line = String(String(repeating: "x1 te f h ", count: 400).prefix(4000))
        var best = Double.infinity
        for _ in 0..<10 {
            let t0 = Date()
            _ = rule.regex.allMatches(line)
            best = min(best, Date().timeIntervalSince(t0))
        }
        #expect(best < 0.005, "\(best * 1000) ms")
        let h = Highlighter(rules: c.rules, palette: Theme.builtIn.highlightPalette)
        let t0 = Date()
        _ = h.process(Array((line + "\r\n").utf8))
        #expect(Date().timeIntervalSince(t0) < 0.25)                     // (todas las reglas, con mucho margen)
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
