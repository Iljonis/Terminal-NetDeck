import Foundation
import Testing
@testable import NetDeckCore

/// El eco de cada tecla no relee el búfer entero (con 10.000 líneas de historial eran ~36 ms en el hilo principal por
/// tecla, y el carácter se pintaba después): sólo cambia la línea del cursor si nada más se ha movido. Si algo ha
/// pasado al historial o no se ve el final, hay que leerlo entero, como antes.
@Suite struct LatenciaTecleoTests {
    /// Historial lleno de 10.000 líneas y una pantalla de 5 con el prompt en la última.
    private func bufer(_ prompt: String = "core-01#") -> [String] {
        (0..<10_000).map { "Gi0/\($0 % 48) 192.0.2.\($0 % 250) up up" } + ["", "", "", "", prompt]
    }

    @Test func elEcoSoloCambiaLaLineaDelCursor() {
        var lineas = bufer()
        let cursor = lineas.count - 1, arriba = lineas.count - 5
        var pantalla = Array(lineas.suffix(5))
        pantalla[4] = "core-01#sh"
        #expect(BufferRows.applyCursorLineEdit(&lineas, cursor: cursor, screen: pantalla, screenCursor: 4, viewportRow: arriba))
        #expect(lineas == Array(bufer().dropLast()) + ["core-01#sh"])        // (lo mismo que leerlo entero)
        // (y moverse por la línea sin cambiar el texto, también)
        #expect(BufferRows.applyCursorLineEdit(&lineas, cursor: cursor, screen: pantalla, screenCursor: 4, viewportRow: arriba))
    }

    @Test func unSaltoDeLineaObligaALeerloEntero() {
        // (con el historial lleno, el número de líneas no cambia: lo delata la pantalla desplazada)
        var lineas = bufer()
        let cursor = lineas.count - 1, arriba = lineas.count - 5
        let desplazada = ["", "", "", "core-01#show clock", "*10:00:00.000 UTC"]
        #expect(!BufferRows.applyCursorLineEdit(&lineas, cursor: cursor, screen: desplazada, screenCursor: 4, viewportRow: arriba))
        #expect(lineas == bufer())                                          // (sin tocar)
        // (el cursor baja de fila sin desplazar: salida en las filas de abajo)
        let abajo = ["", "", "", "core-01#", ""]
        var otras = bufer()
        otras[otras.count - 2] = "core-01#"
        otras[otras.count - 1] = ""
        #expect(!BufferRows.applyCursorLineEdit(&otras, cursor: otras.count - 2, screen: abajo, screenCursor: 4, viewportRow: arriba))
    }

    @Test func conElHistorialALaVistaOOtroTamanoSeLeeEntero() {
        var lineas = bufer()
        let cursor = lineas.count - 1, arriba = lineas.count - 5
        var pantalla = Array(lineas.suffix(5))
        pantalla[4] = "core-01#s"
        // (subido por el historial: lo que se ve no es la pantalla)
        #expect(!BufferRows.applyCursorLineEdit(&lineas, cursor: cursor, screen: pantalla, screenCursor: 4, viewportRow: arriba - 3))
        // (otra fila del cursor en la pantalla)
        #expect(!BufferRows.applyCursorLineEdit(&lineas, cursor: cursor, screen: pantalla, screenCursor: 3, viewportRow: arriba))
        // (otro número de filas)
        #expect(!BufferRows.applyCursorLineEdit(&lineas, cursor: cursor, screen: Array(pantalla.suffix(4)), screenCursor: 3,
                                                viewportRow: arriba))
        #expect(!BufferRows.applyCursorLineEdit(&lineas, cursor: cursor, screen: [], screenCursor: 0, viewportRow: arriba))
        #expect(lineas == bufer())
    }

    @Test func lasFilasAbsolutasNoCambianAlTeclear() {
        // (lo que hacía `update` con el búfer entero tras un eco: nada pasa al historial, la base se queda)
        var filas = BufferRows()
        var lineas = bufer()
        filas.update(lineas, screenRows: 5, cursor: lineas.count - 1)
        let base = filas.base, resyncs = filas.resyncs
        var pantalla = Array(lineas.suffix(5))
        pantalla[4] = "core-01#show ver"
        #expect(BufferRows.applyCursorLineEdit(&lineas, cursor: lineas.count - 1, screen: pantalla, screenCursor: 4,
                                               viewportRow: lineas.count - 5))
        filas.update(lineas, screenRows: 5, cursor: lineas.count - 1)
        #expect(filas.base == base && filas.resyncs == resyncs)
    }
}
