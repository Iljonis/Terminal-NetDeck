import Foundation

/// Filas absolutas del búfer de una pestaña (historial + pantalla) que nunca retroceden. Con el historial lleno, el
/// terminal expulsa las de arriba y el número de líneas deja de crecer: la fila del cursor se quedaba quieta y todo lo
/// anclado a filas (el Intro de una orden, la contraseña enviada, «lo nuevo» desde una marca) dejaba de ver lo nuevo.
/// SwiftTerm 2 no dice desde la vista cuántas ha expulsado: se deduce comparando el historial anterior con el nuevo
/// (el historial sólo pierde filas por arriba y gana por abajo). Si no casan (borrar el historial, la pantalla
/// alternativa, otro tamaño con las líneas recolocadas), todo lo de antes se da por expulsado: la fila salta hacia
/// delante, nunca hacia atrás, y lo anclado antes deja de ver nada anterior al cursor de ese momento (`resync`): un
/// «Permission denied» viejo, recolocado, no se puede tomar por nuevo.
public struct BufferRows: Sendable {
    /// Filas ya expulsadas (o dadas por perdidas): fila absoluta = `base` + índice en el búfer.
    public private(set) var base = 0
    /// La fila absoluta del cursor la última vez que se perdió la alineación: nada de antes vale como «nuevo».
    public private(set) var resync = 0
    /// Cuántas veces se ha perdido (la pestaña suelta entonces lo anclado a filas: contraseña enviada, último Intro…).
    public private(set) var resyncs = 0
    /// El historial de la última lectura (sin la pantalla), resumido por línea.
    private var history: [Int] = []
    private var count = 0
    private var layout: [Int]?
    /// Menos que esto en común (con historial para tenerlo) no demuestra que sea el mismo historial desplazado.
    static let minimumOverlap = 8

    public init() {}

    /// Con cada lectura nueva del búfer: todas sus líneas (las `screenRows` últimas son la pantalla), el índice del
    /// cursor en ellas y el tamaño (`layout`: columnas y filas; si cambia, las líneas se han recolocado).
    public mutating func update(_ lines: [String], screenRows: Int, cursor: Int? = nil, layout: [Int]? = nil) {
        let hashes = lines.map(\.hashValue)
        let old = history, oldCount = count, oldLayout = self.layout
        history = Array(hashes.prefix(max(0, lines.count - max(0, screenRows))))
        count = lines.count
        self.layout = layout ?? oldLayout
        let resized = layout != nil && oldLayout != nil && layout != oldLayout
        guard !old.isEmpty || resized else { return }
        let kept = resized ? 0 : Self.overlap(suffixOf: old, prefixOf: hashes)
        if kept >= min(old.count, Self.minimumOverlap), kept > 0 {
            base += old.count - kept
        } else {
            base += oldCount
            resync = base + (cursor ?? max(0, lines.count - 1))
            resyncs += 1
        }
    }

    /// ¿Es la pantalla alternativa (tmux, screen, less, vi)? SwiftTerm 2 no lo dice desde la vista, y sus lecturas
    /// cogen el lock por separado (con salida continua, un trozo puede llegar entre una y otra). Sólo con pruebas:
    /// true = el activo es del tamaño de la pantalla e igual al alternativo, que tiene algo escrito; false = el activo
    /// tiene historial (el alternativo nunca lo tiene); nil = no se sabe (difieren, o la alternativa está en blanco):
    /// se queda lo que había y no cuenta como recolocar. Entrar y salir de verdad sí cuentan (`layout`).
    public static func alternateEvidence(active: [String], alternate: [String], screenRows: Int) -> Bool? {
        guard active.count == screenRows else { return false }
        guard active == alternate, alternate.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        return true
    }

    /// La primera fila absoluta que se puede leer desde `row` (lo de antes del último `resync`, no).
    public func first(from row: Int) -> Int { max(row, resync) }

    /// Fila absoluta de un índice del búfer.
    public func absolute(_ index: Int) -> Int { base + index }

    /// Índice del búfer de una fila absoluta (negativo: ya expulsada).
    public func local(_ row: Int) -> Int { row - base }

    /// La parte más larga del final de `a` con la que empieza `b` (KMP: lineal, sin probar cada desplazamiento).
    /// La más larga es el desplazamiento más pequeño: con filas repetidas se queda corto, nunca se pasa.
    static func overlap(suffixOf a: [Int], prefixOf b: [Int]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var fail = [Int](repeating: 0, count: b.count), k = 0
        for i in b.indices.dropFirst() {
            while k > 0, b[i] != b[k] { k = fail[k - 1] }
            if b[i] == b[k] { k += 1 }
            fail[i] = k
        }
        var q = 0
        for x in a {
            while q > 0, q == b.count || x != b[q] { q = fail[q - 1] }
            if x == b[q] { q += 1 }
        }
        return q
    }
}
