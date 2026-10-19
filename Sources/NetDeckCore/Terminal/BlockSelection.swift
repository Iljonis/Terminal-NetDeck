import Foundation

/// Selección rectangular (⌥ + arrastrar en el terminal): de cada fila, sólo las columnas del rectángulo, como en
/// SecureCRT o iTerm. Sirve para sacar una columna de un `show interfaces status` sin el resto de la línea.
public struct BlockSelection: Equatable, Sendable {
    /// Filas y columnas de pantalla (desde 0, ambas incluidas).
    public var rows: ClosedRange<Int>
    public var cols: ClosedRange<Int>

    /// El rectángulo entre dos celdas, sea cual sea la esquina desde la que se arrastra.
    public init(from a: (row: Int, col: Int), to b: (row: Int, col: Int)) {
        rows = min(a.row, b.row)...max(a.row, b.row)
        cols = min(a.col, b.col)...max(a.col, b.col)
    }

    /// El texto de esas filas (`text` y el ancho de cada celda, como los da SwiftTerm: 2 la de un carácter ancho y 0 la
    /// que le sigue; las celdas sin escribir del final no vienen). Una fila por línea, sin los espacios del final; un
    /// carácter ancho que queda a medias dentro, entra entero.
    public func text(of screen: [(text: String, cellWidths: [Int])]) -> String {
        rows.map { r -> String in
            guard screen.indices.contains(r) else { return "" }
            let (text, widths) = screen[r]
            var out = ""
            var col = 0
            for ch in text {
                while col < widths.count, widths[col] == 0 { col += 1 }
                let w = col < widths.count ? max(1, widths[col]) : 1
                if col > cols.upperBound { break }
                if col + w - 1 >= cols.lowerBound { out.append(ch) }
                col += w
            }
            while out.last == " " { out.removeLast() }
            return out
        }.joined(separator: "\n")
    }
}
