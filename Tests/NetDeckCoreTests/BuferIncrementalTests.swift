import Foundation
import Testing
import SwiftTerm
@testable import NetDeckCore

/// La pestaña ya no lee el búfer entero con cada Intro o salida (250 ms con 100.000 líneas de historial): lee la
/// pantalla y lo que ha pasado al historial desde la lectura anterior (`BufferRows`). Aquí, con un SwiftTerm sin vista
/// leído igual que la pestaña, lo leído tiene que ser siempre lo mismo que leerlo entero: historial lleno, `clear`,
/// ESC c, la pantalla alternativa, otro tamaño, otro historial, regiones de desplazamiento y mucha salida de golpe.
@Suite struct BuferIncrementalTests {
    // MARK: - lo leído es lo mismo que leerlo entero

    @Test func conElHistorialLlenoUnIntroLeeSoloLaPantalla() {
        let p = Pestana(historial: 2_000)
        for i in 0..<3_000 { p.t.feed(text: "Gi0/\(i % 48) 192.0.2.\(i % 250) up up\r\n") }
        p.escribir("core-01#")
        var filas: [Int] = []
        for _ in 0..<20 {
            p.escribir("\r\ncore-01#")                     // (Intro sostenido: la pantalla se ve igual)
            filas.append(p.cursorRow)
            #expect(p.leidas <= 24 + BufferRows.minimumOverlap + 1)
            p.comprobar()
        }
        #expect(filas == Array(filas[0]..<(filas[0] + 20)))       // (una fila más por Intro, con el historial lleno)
        #expect(p.filas.resyncs == 0 && p.lines(from: p.cursorRow - 1) == ["core-01#", "core-01#"])
        // (y el eco de una tecla, sólo la pantalla)
        p.escribir("s")
        #expect(p.leidas <= 24 + BufferRows.minimumOverlap && p.cursorLine == "core-01#s")
    }

    @Test func loQueCambiaAntesDePasarAlHistorialSeRelee() {
        let p = Pestana(historial: 100)
        for i in 0..<200 { p.t.feed(text: "línea \(i)\r\n") }
        p.escribir("Building configuration... 10%")
        // (la fila cambia y pasa al historial entre dos lecturas)
        p.t.feed(text: "\rBuilding configuration... [OK]\u{1b}[K\r\n")
        for i in 0..<30 { p.t.feed(text: "interface Gi0/\(i)\r\n") }
        p.escribir("core-01#")
        p.comprobar()
        #expect(p.lines(from: p.cursorRow - 31).first == "Building configuration... [OK]")
    }

    @Test func clearYEscCRecolocanYNoSeLeeLoViejo() {
        for borrar in ["\u{1b}[H\u{1b}[2J\u{1b}[3J", "\u{1b}c"] {
            let p = Pestana(historial: 500)
            for i in 0..<300 { p.t.feed(text: "línea \(i)\r\n") }
            p.escribir("tu.usuario@core-02: Permission denied (password).\r\ncore-01#")
            let marca = p.cursorRow - 1, recolocados = p.filas.resyncs
            p.escribir(borrar + "core-01#")
            p.comprobar()
            #expect(p.filas.resyncs == recolocados + 1 && p.cursorRow > marca)
            #expect(!p.lines(from: marca).contains { $0.contains("Permission denied") })
            // (aunque luego vuelva a llenarse más allá de donde estaba: lo de antes ya no sale)
            for i in 0..<400 { p.t.feed(text: "nueva \(i)\r\n") }
            p.escribir("core-01#")
            p.comprobar()
            #expect(!p.lines(from: marca).contains { $0.contains("Permission denied") })
        }
    }

    @Test func borrarYVolverALlenarEntreDosLecturasNoPasaPorElMismoHistorial() {
        let p = Pestana(historial: 500)
        for i in 0..<100 { p.t.feed(text: "línea \(i)\r\n") }
        p.escribir("tu.usuario@core-02: Permission denied (password).\r\ncore-01#")
        let marca = p.cursorRow - 1
        // (CSI 3 J y salida de sobra para que la numeración pase de donde estaba, sin leer entre medias)
        p.t.feed(text: "\u{1b}[H\u{1b}[2J\u{1b}[3J")
        for i in 0..<200 { p.t.feed(text: "nueva \(i)\r\n") }
        p.escribir("core-01#")
        p.comprobar()
        #expect(p.filas.resyncs == 1 && !p.lines(from: marca).contains { $0.contains("Permission denied") })
    }

    @Test func laPantallaAlternativaRecolocaAlEntrarYAlSalir() {
        let p = Pestana(historial: 500)
        for i in 0..<100 { p.t.feed(text: "línea \(i)\r\n") }
        p.escribir("core-01#")
        p.escribir("\u{1b}[?1049h\u{1b}[H\u{1b}[2J~\r\n~\r\n\"running-config\" 120L")
        #expect(p.filas.resyncs == 1)
        p.comprobar()
        let dentro = p.cursorRow
        for i in 0..<50 { p.escribir("\u{1b}[\(i % 20 + 1);1H\u{1b}[Kfila \(i)") }        // (vi repinta: no recoloca)
        #expect(p.filas.resyncs == 1)
        p.comprobar()
        p.escribir("\u{1b}[?1049l")
        p.comprobar()
        #expect(p.filas.resyncs == 2 && p.filas.first(from: dentro) > dentro && p.cursorLine == "core-01#")
    }

    /// Sin historial con el que comparar (pestaña recién abierta), un `clear` o un ESC c reutilizan los números de
    /// fila: si el cursor queda por detrás del de antes, se recoloca, y lo anclado no se queda esperando una fila que ya
    /// ha pasado (el «Permission denied» nuevo sale en una fila de número menor).
    @Test func sinHistorialUnClearQueRetrocedeRecoloca() {
        for borrar in ["\u{1b}[H\u{1b}[2J\u{1b}[3J", "\u{1b}c"] {
            let p = Pestana(historial: 500)
            for i in 0..<10 { p.t.feed(text: "línea \(i)\r\n") }
            p.escribir("core-01#ssh tu.usuario@core-02\r\nPassword: ")
            let marca = p.cursorRow
            #expect(p.filas.resyncs == 0)
            p.t.feed(text: borrar + "línea\r\n")
            p.escribir("tu.usuario@core-02: Permission denied (password).\r\ncore-01#")
            p.comprobar()
            #expect(p.filas.resyncs == 1 && p.cursorRow > marca)
            // (vi o un progreso que sube el cursor en la pantalla alternativa no recolocan)
            p.escribir("\u{1b}[?1049h\u{1b}[20;1Hfila\u{1b}[2;1Hfila")
            p.escribir("\u{1b}[1;1Hfila")
            #expect(p.filas.resyncs == 2)
        }
    }

    /// Al salir de vi, less o top (y con otro tamaño) sólo se lee la pantalla, no el historial entero: lo de antes no
    /// casa y se recoloca igual. Antes, 460 ms con 100.000 líneas, en el hilo principal.
    @Test func alSalirDeLaAlternativaSoloSeLeeLaPantalla() {
        let p = Pestana(historial: 20_000)
        p.t.feed(text: (0..<20_100).map { "Gi0/\($0 % 48) 192.0.2.\($0 % 250) up up\r\n" }.joined())
        p.escribir("core-01#")
        p.escribir("\u{1b}[?1049h\u{1b}[H\u{1b}[2J~\r\n~")
        #expect(p.leidas <= 24 && p.filas.resyncs == 1)
        let c = ContinuousClock.now
        p.escribir("\u{1b}[?1049l")
        let d = ContinuousClock.now - c
        #expect(p.leidas <= 24 && p.filas.resyncs == 2 && p.cursorLine == "core-01#")
        #expect(d < .seconds(5))                                         // (margen de CI; leerlo todo, ~90 ms)
        p.comprobar()
        p.t.resize(cols: 100, rows: 30)
        p.escribir("")
        #expect(p.leidas <= 30 && p.filas.resyncs == 3)
        p.comprobar()
    }

    @Test func otroTamanoUOtroHistorialRecolocan() {
        let p = Pestana(historial: 1_000)
        for i in 0..<1_500 { p.t.feed(text: "línea \(i) con texto de sobra para que se recoloque al estrechar\r\n") }
        p.escribir("core-01#")
        let antes = p.cursorRow
        p.t.resize(cols: 40, rows: 30)
        p.escribir("")
        p.comprobar()
        #expect(p.filas.resyncs == 1 && p.cursorRow > antes)
        // (menos historial: las filas cambian de número; más, no)
        p.t.changeScrollback(300)
        p.escribir("\r\ncore-01#")
        p.comprobar()
        #expect(p.filas.resyncs == 2)
        p.t.changeScrollback(5_000)
        p.escribir("\r\ncore-01#")
        p.comprobar()
        #expect(p.filas.resyncs == 2)
    }

    @Test func muchaSalidaDeGolpeNoRecoloca() {
        let p = Pestana(historial: 300)
        p.escribir("core-01#show tech")
        let antes = p.cursorRow
        for i in 0..<5_000 { p.t.feed(text: "\r\nlínea \(i)") }       // (más que todo el historial entre dos lecturas)
        p.escribir("\r\ncore-01#")
        p.comprobar()
        #expect(p.filas.resyncs == 0 && p.cursorRow == antes + 5_001 && p.filas.lines.count == 300 + 24)
    }

    /// Salida al azar (con semilla): saltos, retornos, borrar, insertar y quitar filas, regiones, letras anchas,
    /// espacios al final, pantalla alternativa, otro tamaño y lecturas a destiempo. Siempre lo mismo que leerlo entero.
    @Test(arguments: [1, 2, 3, 4])
    func alAzarEsLoMismoQueLeerloEntero(_ semilla: UInt64) {
        var g = Semilla(semilla)
        let p = Pestana(historial: 150)
        let trozos = ["\r\n", "\n", "\r", "core-01#", "Password: ", "é", "漢字", "  ", "\u{1b}[K", "\u{1b}[2J", "\u{1b}[1J",
                      "\u{1b}[L", "\u{1b}[M", "\u{1b}[3S", "\u{1b}[2T", "\u{1b}D", "\u{1b}M", "\u{1b}E", "\u{1b}[5;12r",
                      "\u{1b}[r", "\u{1b}[?1049h", "\u{1b}[?1049l", "\u{1b}[3J", "Gi0/1 up up\r\n", "\u{1b}[31mrojo\u{1b}[0m"]
        for paso in 0..<1_500 {
            switch g.siguiente() % 20 {
            case 0: p.t.feed(text: "\u{1b}[\(g.siguiente() % 26 + 1);\(g.siguiente() % 82 + 1)H")
            case 1 where paso % 200 == 1: p.t.resize(cols: Int(g.siguiente() % 60) + 30, rows: Int(g.siguiente() % 20) + 5)
            case 2: p.t.feed(text: (0..<Int(g.siguiente() % 400)).map { "salida \($0)\r\n" }.joined())
            default: p.t.feed(text: trozos[Int(g.siguiente() % UInt64(trozos.count))])
            }
            if g.siguiente() % 3 == 0 {
                p.leer()
                p.comprobar()
            }
        }
    }

    // MARK: - rendimiento

    /// `NETDECK_RENDIMIENTO=1 swift test -c release --filter BuferIncrementalTests`: lo que tarda leer tras un Intro o
    /// tras 50 líneas de salida, con el historial lleno, por partes (ahora) y entero (antes).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NETDECK_RENDIMIENTO"] != nil), arguments: [2_500, 10_000, 100_000])
    func medir(_ n: Int) {
        let p = Pestana(columnas: 120, filas: 40, historial: n)
        p.t.feed(text: (0..<(n + 200)).map { "Gi0/\($0 % 48) 192.0.2.\($0 % 250) up up  \($0) paquetes de entrada, 0 errores\r\n" }
            .joined() + "core-01#")
        p.leer()
        func ms(_ trozo: String, _ leer: () -> Void) -> String {
            var t: [Double] = []
            for _ in 0..<15 {
                p.t.feed(text: trozo)
                let c = ContinuousClock.now
                leer()
                let d = ContinuousClock.now - c
                t.append(Double(d.components.seconds) * 1_000 + Double(d.components.attoseconds) / 1e15)
            }
            t.sort()
            return String(format: "%.2f ms (máx %.2f)", t[t.count / 2], t.last!)
        }
        let intro = "\r\ncore-01#", salida = (0..<50).map { "línea \($0) de show run\r\n" }.joined() + "core-01#"
        print("BÚFER \(n) líneas · Intro: \(ms(intro) { p.leer() }) · 50 líneas: \(ms(salida) { p.leer() })"
              + " · entero: \(ms(intro) { _ = p.entero })"
              + " · al salir de vi: \(ms("\u{1b}[?1049h~\u{1b}[?1049l") { p.leer() })")
    }
}

/// Un SwiftTerm sin vista leído como la pestaña (`TerminalSession.readBuffer`).
private final class Pestana {
    private let mudo = Mudo()
    let t: Terminal
    private(set) var filas = BufferRows()
    /// Las filas copiadas en la última lectura.
    private(set) var leidas = 0

    init(columnas: Int = 80, filas n: Int = 24, historial: Int) {
        t = Terminal(delegate: mudo, options: TerminalOptions(cols: columnas, rows: n, scrollback: historial))
        leer()
    }

    func escribir(_ texto: String) {
        t.feed(text: texto)
        leer()
    }

    func leer() {
        leidas = 0
        filas.refresh(top: { self.read(self.t.contentSnapshot(region: .rows(0..<0))) },
                      rows: { self.read(self.t.contentSnapshot(region: $0.map { .rows($0..<Int.max) } ?? .all)) },
                      screen: { self.read(self.t.contentSnapshot(region: .history(maximumScrollbackRows: 0))) })
    }

    private func read(_ s: TerminalContentSnapshot) -> BufferRows.Read {
        leidas += s.rows.count
        return .init(rows: s.rows.map(\.text), first: s.capturedRange.lowerBound, screenTop: s.liveTopRow,
                     cursorRow: s.cursorRow, layout: [s.dimensions.cols, s.dimensions.rows, s.bufferKind == .alt ? 1 : 0])
    }

    /// Todo el búfer, como lo leía antes la pestaña.
    var entero: [String] {
        var l = String(decoding: t.getBufferAsData(), as: UTF8.self).components(separatedBy: "\n")
        if l.last == "" { l.removeLast() }
        return l
    }

    var cursorRow: Int { filas.base + filas.cursor }
    var cursorLine: String { filas.lines[filas.cursor] }

    /// Como `TerminalSession.lines(from:)`.
    func lines(from row: Int) -> [String] {
        let from = filas.first(from: row)
        guard from <= cursorRow, !filas.lines.isEmpty else { return [] }
        return Array(filas.lines[max(0, from - filas.base)...filas.cursor])
    }

    /// Lo leído es el final del búfer entero, con el cursor en la misma fila.
    func comprobar(sourceLocation: SourceLocation = #_sourceLocation) {
        let todo = entero, l = filas.lines
        #expect(!l.isEmpty && l.count <= todo.count, sourceLocation: sourceLocation)
        #expect(l == Array(todo.suffix(l.count)), sourceLocation: sourceLocation)
        let cursor = todo.count - t.rows + t.buffer.y
        #expect(l.count - filas.cursor == todo.count - cursor, sourceLocation: sourceLocation)
    }
}

private final class Mudo: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

/// Números al azar repetibles (xorshift).
private struct Semilla {
    private var x: UInt64
    init(_ s: UInt64) { x = s &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func siguiente() -> UInt64 {
        x ^= x << 13; x ^= x >> 7; x ^= x << 17
        return x
    }
}
