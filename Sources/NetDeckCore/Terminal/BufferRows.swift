import Foundation

/// Filas absolutas del búfer de una pestaña (historial + pantalla) que nunca retroceden. Con el historial lleno, el
/// terminal expulsa las de arriba y el número de líneas deja de crecer: la fila del cursor se quedaba quieta y todo lo
/// anclado a filas (el Intro de una orden, la contraseña enviada, «lo nuevo» desde una marca) dejaba de ver lo nuevo.
/// SwiftTerm 2 no dice desde la vista cuántas ha expulsado: se deduce comparando el historial anterior con el nuevo
/// (el historial sólo pierde filas por arriba y gana por abajo). Si no casan (borrar el historial, la pantalla
/// alternativa, otro ancho), todo lo de antes se da por expulsado: la fila salta hacia delante, nunca hacia atrás.
public struct BufferRows: Sendable {
    /// Filas ya expulsadas (o dadas por perdidas): fila absoluta = `base` + índice en el búfer.
    public private(set) var base = 0
    /// El historial de la última lectura (sin la pantalla), resumido por línea.
    private var history: [Int] = []
    private var count = 0

    public init() {}

    /// Con cada lectura nueva del búfer: todas sus líneas (las `screenRows` últimas son la pantalla).
    public mutating func update(_ lines: [String], screenRows: Int) {
        let hashes = lines.map(\.hashValue)
        let old = history, oldCount = count
        history = Array(hashes.prefix(max(0, lines.count - max(0, screenRows))))
        count = lines.count
        guard !old.isEmpty else { return }
        let kept = Self.overlap(suffixOf: old, prefixOf: hashes)
        base += kept > 0 ? old.count - kept : oldCount
    }

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
