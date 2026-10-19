import Testing
@testable import NetDeckCore

/// Las filas como las da SwiftTerm: el texto y el ancho de cada celda (2 + 0 para un carácter ancho).
private func fila(_ s: String, cols: Int = 40) -> (text: String, cellWidths: [Int]) {
    var w: [Int] = []
    for ch in s { if ch.unicodeScalars.first.map({ $0.value >= 0x3000 }) == true { w += [2, 0] } else { w.append(1) } }
    return (s, w + Array(repeating: 1, count: max(0, cols - w.count)))
}

@Suite struct TerminalSelectionTests {
    private let pantalla = [
        fila("Interface              IP-Address      OK? Method"),
        fila("GigabitEthernet0/0/0   192.0.2.11      YES NVRAM"),
        fila("Te0/1   203.0.113.5"),
        fila(""),
    ]

    /// ⌥ + arrastrar: sólo esas columnas de cada fila, sin los espacios del final.
    @Test func columnaDeIPs() {
        let b = BlockSelection(from: (row: 0, col: 23), to: (row: 1, col: 35))
        #expect(b.text(of: pantalla) == "IP-Address\n192.0.2.11")
    }

    /// Se arrastre desde la esquina que sea, el mismo rectángulo; filas cortas o vacías salen vacías.
    @Test func cualquierEsquinaYFilasCortas() {
        let b = BlockSelection(from: (row: 3, col: 35), to: (row: 1, col: 23))
        #expect(b == BlockSelection(from: (row: 1, col: 23), to: (row: 3, col: 35)))
        #expect(b.text(of: pantalla) == "192.0.2.11\n\n")
        #expect(BlockSelection(from: (row: 9, col: 0), to: (row: 9, col: 5)).text(of: pantalla) == "")
    }

    /// Un carácter ancho (dos celdas) cuenta en sus dos columnas, y entra entero si el borde lo corta.
    @Test func caracteresAnchos() {
        let p = [fila("ab東京cd")]                                   // a b 東東 京京 c d → columnas 0 1 2-3 4-5 6 7
        #expect(BlockSelection(from: (row: 0, col: 2), to: (row: 0, col: 5)).text(of: p) == "東京")
        #expect(BlockSelection(from: (row: 0, col: 3), to: (row: 0, col: 6)).text(of: p) == "東京c")
        #expect(BlockSelection(from: (row: 0, col: 6), to: (row: 0, col: 7)).text(of: p) == "cd")
    }

    @Test func historial() {
        #expect(TerminalHistory.defaultLines == 2_500)
        #expect(TerminalHistory.options == [1_000, 2_500, 5_000, 10_000])
        #expect(TerminalHistory.lines(nil) == 2_500)
        #expect(TerminalHistory.lines(5_000) == 5_000)
        #expect(TerminalHistory.lines("10000") == 10_000)                // («-scrollback 10000» llega como texto)
        #expect(TerminalHistory.lines("muchas") == 2_500)
        #expect(TerminalHistory.lines(5) == 100)
        #expect(TerminalHistory.lines(10_000_000) == 100_000)
        #expect(TerminalHistory.grouped(2_500, idioma: .es) == "2.500")
        #expect(TerminalHistory.grouped(10_000, idioma: .en) == "10,000")
        #expect(TerminalHistory.grouped(100_000, idioma: .es) == "100.000")
        #expect(TerminalHistory.grouped(500, idioma: .es) == "500")
        #expect(Idioma.traducir("\(TerminalHistory.grouped(1_000, idioma: .en)) líneas", a: .en) == "1,000 lines")
    }
}
