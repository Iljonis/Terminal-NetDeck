import Foundation

/// Las filas del búfer de una pestaña (historial + pantalla) leídas por partes, con un número absoluto que nunca
/// retrocede. Leer el búfer entero con cada Intro o salida costaba 10-40 ms con 2.500-10.000 líneas de historial y
/// 250 ms con 100.000 (en el hilo principal, y bloqueando al terminal): ahora se lee la pantalla y lo que ha pasado al
/// historial desde la lectura anterior (`readFrom`). SwiftTerm (1.99.3, `terminalContentSnapshot(region: .rows)`)
/// numera las filas sin que cambien al expulsar las de arriba con el historial lleno; lo que ya era historial no
/// cambia, salvo si se borra (`clear` con CSI 3 J, ESC c), se reduce, se recoloca (otro tamaño) o se cambia de pantalla
/// (vi, less, tmux). Entonces la numeración no casa con la anterior y todo lo de antes se da por expulsado: la fila
/// salta hacia delante, nunca hacia atrás, y lo anclado antes deja de ver nada anterior al cursor de ese momento
/// (`resync`): un «Permission denied» viejo, recolocado, no se puede tomar por nuevo.
public struct BufferRows: Sendable {
    /// Lo leído: desde la primera fila que aún guarda SwiftTerm (o la de la última recolocación) hasta la última.
    public private(set) var lines: [String] = []
    /// El índice de la fila del cursor en `lines`.
    public private(set) var cursor = 0
    /// La fila absoluta del cursor la última vez que se perdió la alineación: nada de antes vale como «nuevo».
    public private(set) var resync = 0
    /// Cuántas veces se ha perdido (la pestaña suelta entonces lo anclado a filas: contraseña enviada, último Intro…).
    public private(set) var resyncs = 0
    /// Fila absoluta = `offset` + número de SwiftTerm (cambia sólo al recolocar, y siempre hacia delante).
    private var offset = 0
    /// El número de SwiftTerm de `lines[0]` y el de la primera fila de la pantalla en la última lectura.
    private var start = 0, screenTop = 0
    /// Columnas, filas y pantalla alternativa (1) de la última lectura; nil = aún ninguna.
    private var layout: [Int]?
    /// Las filas que ya eran historial y se vuelven a leer para comprobar que la numeración sigue siendo la misma.
    static let minimumOverlap = 8

    public init() {}

    /// La fila absoluta de `lines[0]`.
    public var base: Int { offset + start }

    /// Desde qué número de fila de SwiftTerm hay que leer (hasta el final): la pantalla de la última lectura (lo que ha
    /// pasado de ella al historial pudo cambiar antes de pasar) y unas filas de antes, para comprobar. nil = todo (la
    /// primera vez).
    public var readFrom: Int? { layout == nil ? nil : max(start, screenTop - Self.minimumOverlap) }

    /// Una lectura de SwiftTerm por filas (`terminalContentSnapshot(region:)`): `rows` desde el número `first` hasta el
    /// final, la primera fila de la pantalla (`screenTop`), la del cursor (`cursorRow`) y el tamaño (`layout`).
    public struct Read: Sendable {
        public var rows: [String]
        public var first: Int, screenTop: Int, cursorRow: Int
        public var layout: [Int]

        public init(rows: [String], first: Int, screenTop: Int, cursorRow: Int, layout: [Int]) {
            (self.rows, self.first, self.screenTop, self.cursorRow, self.layout) = (rows, first, screenTop, cursorRow, layout)
        }
    }

    /// Lo que ha podido cambiar desde la lectura anterior: `top`, una lectura sin filas (`.rows(0..<0)`) con la primera
    /// fila que SwiftTerm aún guarda (lo de antes se suelta) y el tamaño; `rows(n)` lee desde el número `n` (nil =
    /// todo); `screen`, sólo la pantalla. Con otro tamaño o desde la pantalla alternativa, sólo la pantalla: lo de antes
    /// no casa (al salir de vi, `readFrom` es 0 y leer el historial entero eran 460 ms con 100.000 líneas, para nada).
    /// Cada una coge el lock de SwiftTerm por separado: si entre una y otra llega salida, la siguiente lectura vuelve a
    /// leer lo que ha cambiado.
    public mutating func refresh(top: () -> Read?, rows: (Int?) -> Read?, screen: () -> Read?) {
        let t = top()
        if let old = layout, old[2] == 1 || t.map({ $0.layout != old }) == true {
            if let s = screen(), !merge(s) { restart(s) }
            return
        }
        guard let r = rows(readFrom) else { return }
        if !merge(r, retainedTop: t?.first), let s = screen() { restart(s) }
    }

    /// Si casa con lo anterior (mismo tamaño y pantalla, la numeración no retrocede y lo que ya era historial sale
    /// igual), sólo cambia lo leído; si no, se recoloca con lo leído si trae la pantalla. false = ni casa ni la trae (la
    /// numeración ha vuelto atrás): hay que leer la pantalla y llamar a `restart`.
    @discardableResult
    public mutating func merge(_ r: Read, retainedTop: Int? = nil) -> Bool {
        guard let old = layout else {
            (lines, start, screenTop, layout) = (r.rows, r.first, r.screenTop, r.layout)
            cursor = clampedCursor(r.cursorRow)
            return true
        }
        if let from = readFrom, r.layout == old, r.screenTop >= screenTop, r.first >= from {
            // (si se ha expulsado lo pedido, todo lo leído es nuevo: no hay con qué comparar)
            let checked = r.first == from ? max(0, min(screenTop, from + r.rows.count) - from) : 0
            let k = from - start
            // (sin historial con el que comparar, un `clear` con CSI 3 J o un ESC c y salida de sobra reutilizan los
            // números: si el cursor retrocede, no es lo mismo; en la alternativa no hay historial y vi lo mueve)
            let back = checked == 0 && r.layout[2] == 0 && r.cursorRow < start + cursor
            if !back, (0..<checked).allSatisfy({ k + $0 < lines.count && lines[k + $0] == r.rows[$0] }) {
                if r.first == from {
                    lines.removeSubrange(min(lines.count, k)...)
                    lines += r.rows
                } else {
                    (lines, start) = (r.rows, r.first)
                }
                screenTop = r.screenTop
                // (lo que SwiftTerm ya no guarda; nunca lo que acaba de llegar)
                if let t = retainedTop, min(t, r.first) > start {
                    lines.removeFirst(min(t, r.first) - start)
                    start = min(t, r.first)
                }
                cursor = clampedCursor(r.cursorRow)
                return true
            }
        }
        guard r.first <= r.screenTop, r.first + r.rows.count > r.screenTop else { return false }
        restart(r)
        return true
    }

    /// La numeración no casa con la anterior: lo de ahora (al menos la pantalla) va después de todo lo leído.
    public mutating func restart(_ r: Read) {
        offset = base + lines.count - r.first
        (lines, start, screenTop, layout) = (r.rows, r.first, r.screenTop, r.layout)
        cursor = clampedCursor(r.cursorRow)
        resync = base + cursor
        resyncs += 1
    }

    private func clampedCursor(_ row: Int) -> Int { max(0, min(lines.count - 1, row - start)) }

    /// La primera fila absoluta que se puede leer desde `row` (lo de antes del último `resync`, no).
    public func first(from row: Int) -> Int { max(row, resync) }
}
