import Foundation
import Synchronization
import Testing
@testable import NetDeckCore

/// Un lector que cuenta cuántos trozos entrega y el más grande (para comprobar que no se carga un archivo entero).
private final class CountingReader: LogFileReader, @unchecked Sendable {
    private let inner = PlainLogReader()
    private let state = Mutex((chunks: 0, biggest: 0))
    var chunks: Int { state.withLock { $0.chunks } }
    var biggest: Int { state.withLock { $0.biggest } }
    func canRead(_ file: URL) -> Bool { inner.canRead(file) }
    func read(_ file: URL, chunk: (Data) -> Bool) throws {
        try inner.read(file) { d in
            state.withLock { $0.chunks += 1; $0.biggest = max($0.biggest, d.count) }
            return chunk(d)
        }
    }
}

@Suite struct LogSearchTests {
    private let now: Date
    private let calendar: Calendar

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar = c
        now = c.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12)) ?? Date()
    }

    /// Una carpeta temporal con registros `dia/equipo_hora.log`.
    private func logs(_ files: [(day: String, name: String, text: String)]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("netdeck-logsearch-\(UUID().uuidString)")
        for f in files {
            let sub = dir.appendingPathComponent(f.day)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try Data(f.text.utf8).write(to: sub.appendingPathComponent(f.name))
        }
        return dir
    }

    private func search(_ q: LogQuery, _ dir: URL, reader: any LogFileReader = PlainLogReader(),
                        cancel: () -> Bool = { false }) throws -> LogSearchResult {
        try LogSearch.search(q, in: dir, reader: reader, now: now, calendar: calendar, isCancelled: cancel)
    }

    @Test func macEnLosTresFormatos() throws {
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log",
                             "uno aa:bb:cc:dd:ee:ff arriba\ndos aabb.ccdd.eeff abajo\ntres AA-BB-CC-DD-EE-FF fin\ncuatro aabbccddeeff\nnada 11:22:33:44:55:66\n")])
        defer { try? FileManager.default.removeItem(at: dir) }
        for q in ["aa:bb:cc:dd:ee:ff", "aabb.ccdd.eeff", "AA-BB-CC-DD-EE-FF", "aabbccddeeff"] {
            let r = try search(LogQuery(text: q), dir)
            #expect(r.hits.map(\.line) == [1, 2, 3, 4], "«\(q)»")
        }
        // (con mayúsculas activadas, una MAC se sigue encontrando en cualquier caja)
        #expect(try search(LogQuery(text: "aa:bb:cc:dd:ee:ff", caseSensitive: true), dir).hits.count == 4)
        #expect(LogQuery.macPattern("aa:bb:cc") == nil)
        #expect(LogQuery.macPattern("aa:bb:cc:dd:ee:ff:00") == nil)
    }

    @Test func ipv4ConBordes() throws {
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log",
                             "ping 192.0.2.1 ok\nping 192.0.2.11 ok\nping 192.0.2.1.\nping 1.192.0.2.1\nsrc=192.0.2.1,dst\nver 192.0.2.1.5\n")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try search(LogQuery(text: "192.0.2.1"), dir)
        #expect(r.hits.map(\.line) == [1, 3, 5])
        #expect(try search(LogQuery(text: "192.0.2.11"), dir).hits.map(\.line) == [2])
        // (con menos de cuatro grupos es texto: «192.0.2» acierta en todas)
        #expect(try search(LogQuery(text: "192.0.2"), dir).hits.count == 6)
    }

    @Test func regexValidoEInvalido() throws {
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", "Gi0/1 up\nGi0/2 down\nLo0 up\n")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try search(LogQuery(text: #"Gi0/\d (up|down)"#, isRegex: true), dir)
        #expect(r.hits.map(\.line) == [1, 2])
        // (en modo texto, los signos son literales)
        #expect(try search(LogQuery(text: "(up|down)"), dir).hits.isEmpty)
        #expect(throws: LogSearchError.self) { try search(LogQuery(text: "Gi0/(", isRegex: true), dir) }
        #expect(LogSearchError().errorDescription?.isEmpty == false)
        // (el mismo «(» en texto no revienta)
        #expect(try search(LogQuery(text: "Gi0/("), dir).hits.isEmpty)
    }

    @Test func palabraCompletaYMayusculas() throws {
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", "port up\nport UP\nsetup done\nup-link\nbackup\n")])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try search(LogQuery(text: "up"), dir).hits.map(\.line) == [1, 2, 3, 4, 5])
        #expect(try search(LogQuery(text: "up", wholeWord: true), dir).hits.map(\.line) == [1, 2, 4])
        #expect(try search(LogQuery(text: "up", caseSensitive: true), dir).hits.map(\.line) == [1, 3, 4, 5])
        #expect(try search(LogQuery(text: "up", caseSensitive: true, wholeWord: true), dir).hits.map(\.line) == [1, 4])
        #expect(try search(LogQuery(text: "UP", caseSensitive: true), dir).hits.map(\.line) == [2])
        #expect(try search(LogQuery(text: "up|UP", isRegex: true, wholeWord: true), dir).hits.map(\.line) == [1, 2, 4])
    }

    @Test func filtroDeEquipoYDePeriodo() throws {
        let dir = try logs([
            ("2026-11-25", "core-01_09-00-00.log", "hoy core\n"),
            ("2026-11-25", "bastion_09-00-00.log", "hoy bastion\n"),
            ("2026-11-19", "core-01_09-00-00.log", "hace 6 días\n"),
            ("2026-11-18", "core-01_09-00-00.log", "hace 7 días\n"),
            ("2026-10-27", "core-01_09-00-00.log", "hace 29 días\n"),
            ("2026-10-26", "core-01_09-00-00.log", "hace 30 días\n"),
            ("sin-fecha", "core-01_09-00-00.log", "sin carpeta de día\n")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        func lines(_ q: LogQuery) throws -> [String] { try search(q, dir).hits.map(\.text) }
        #expect(try lines(LogQuery(text: "hoy")) == ["hoy core", "hoy bastion"])        // (lo más reciente primero)
        #expect(try lines(LogQuery(text: "hoy", host: "bastion")) == ["hoy bastion"])
        #expect(try lines(LogQuery(text: "hoy", host: "BASTION")) == ["hoy bastion"])
        #expect(try lines(LogQuery(text: "hoy", host: "core")).isEmpty)                 // (el nombre entero, no una parte)
        #expect(try lines(LogQuery(text: "hoy", period: .today)).count == 2)
        #expect(try lines(LogQuery(text: "días", period: .today)).isEmpty)
        #expect(try lines(LogQuery(text: "días", period: .week)) == ["hace 6 días"])
        #expect(try lines(LogQuery(text: "días", period: .month)) == ["hace 6 días", "hace 7 días", "hace 29 días"])
        #expect(try lines(LogQuery(text: "días", period: .all)).count == 4)
        #expect(try lines(LogQuery(text: "carpeta", period: .all)) == ["sin carpeta de día"])
        #expect(try lines(LogQuery(text: "carpeta", period: .month)).isEmpty)
        #expect(LogSearch.hosts(in: dir) == ["bastion", "core-01"])
    }

    @Test func nombreDelEquipoYDiaDelArchivo() {
        func info(_ p: String) -> (host: String, day: Int?) { LogSearch.info(of: URL(fileURLWithPath: "/x/" + p)) }
        #expect(info("2026-11-25/core-01_10-20-30.log") == ("core-01", 20261125))
        #expect(info("2026-11-25/core-01_10-20-30-2.log") == ("core-01", 20261125))
        #expect(info("2026-11-25/tu.usuario@192.0.2.1_10-20-30.log.gz") == ("tu.usuario@192.0.2.1", 20261125))
        #expect(info("2026-11-25/mi_equipo_10-20-30.log") == ("mi_equipo", 20261125))
        #expect(info("otro/suelto.log") == ("suelto", nil))
    }

    @Test func topeDeAciertos() throws {
        let text = (1...30).map { "linea \($0) 192.0.2.1\n" }.joined()
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", text)])
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try search(LogQuery(text: "192.0.2.1", maxHits: 10), dir)
        #expect(r.hits.count == 10 && r.truncated)
        #expect(r.hits.last?.line == 10)
        let justo = try search(LogQuery(text: "192.0.2.1", maxHits: 30), dir)
        #expect(justo.hits.count == 30 && !justo.truncated)
        #expect(try search(LogQuery(text: "192.0.2.1"), dir).hits.count == 30)
        #expect(LogQuery.defaultMaxHits == 500)
    }

    @Test func cancelacion() throws {
        let files = (1...20).map { ("2026-11-25", "eq-\($0)_10-00-00.log", "hola\n") }
        let dir = try logs(files)
        defer { try? FileManager.default.removeItem(at: dir) }
        let seen = Mutex(0)
        let r = try search(LogQuery(text: "hola"), dir) { seen.withLock { $0 += 1; return $0 > 6 } }
        #expect(r.cancelled)
        #expect(r.hits.count < 20)
        #expect(try search(LogQuery(text: "hola"), dir, cancel: { true }).hits.isEmpty)
        #expect(try search(LogQuery(text: "hola"), dir).hits.count == 20)
    }

    @Test func lineaEnormeSeCorta() throws {
        let big = "ini 192.0.2.1 " + String(repeating: "x", count: 200_000) + " fin 192.0.2.99"
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", big + "\nsiguiente 192.0.2.99\n")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try search(LogQuery(text: "192.0.2.1"), dir)
        #expect(r.hits.count == 1)
        #expect(r.hits[0].text.utf8.count <= LogQuery.maxLine)
        // (lo que cae más allá del tope no se encuentra, y la línea siguiente sí se lee)
        #expect(try search(LogQuery(text: "192.0.2.99"), dir).hits.map(\.line) == [2])
    }

    @Test func archivoGrandeSinCargarloEntero() throws {
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", "")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("2026-11-25/core-01_10-00-00.log")
        let h = try FileHandle(forWritingTo: file)
        let block = Data((1...2000).map { "línea de relleno \($0) sin nada de interés\n" }.joined().utf8)
        for _ in 0..<40 { try h.write(contentsOf: block) }                    // (≈ 4 MB)
        try h.write(contentsOf: Data("final 192.0.2.7 aquí\n".utf8))
        try h.close()
        let size = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
        #expect(size > 3_000_000)
        let reader = CountingReader()
        let r = try search(LogQuery(text: "192.0.2.7"), dir, reader: reader)
        #expect(r.hits.map(\.line) == [80_001])
        #expect(reader.biggest <= PlainLogReader.chunkSize)
        #expect(reader.chunks >= size / PlainLogReader.chunkSize)
        // (el contexto se para al llegar a su última línea: no lee lo que sobra)
        let c = LogSearch.context(file: file, line: 5, reader: reader)
        #expect(c.map(\.number) == Array(1...17))
    }

    @Test func elDescarteDeBloquesNoPierdeAciertos() throws {
        // (varios trozos de 64 KB; los anclajes de línea, \A y \z y las palabras completas dan lo mismo que línea a línea)
        let lines = (1...6000).map { "linea \($0) Gi0/\($0 % 7) \($0 % 5 == 0 ? "up" : "down")" }
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", lines.joined(separator: "\r\n") + "\r\n")])
        defer { try? FileManager.default.removeItem(at: dir) }
        func got(_ q: LogQuery) throws -> [Int] { var q = q; q.maxHits = 10_000; return try search(q, dir).hits.map(\.line) }
        func want(_ f: (String) -> Bool) -> [Int] { lines.indices.filter { f(lines[$0]) }.map { $0 + 1 } }
        #expect(try got(LogQuery(text: "^linea 5999", isRegex: true)) == [5999])
        #expect(try got(LogQuery(text: "up$", isRegex: true)) == want { $0.hasSuffix("up") })
        #expect(try got(LogQuery(text: #"\Alinea 4000 "#, isRegex: true)) == [4000])
        #expect(try got(LogQuery(text: #"up\z"#, isRegex: true)) == want { $0.hasSuffix("up") })
        #expect(try got(LogQuery(text: "Gi0/3 up", wholeWord: true)) == want { $0.hasSuffix("Gi0/3 up") })
        #expect(try got(LogQuery(text: "linea 1", wholeWord: true)) == [1])
        #expect(try got(LogQuery(text: #"Gi0/3\s+up"#, isRegex: true)) == want { $0.hasSuffix("Gi0/3 up") })
        #expect(try got(LogQuery(text: "nada de esto")).isEmpty)
    }

    @Test func finesDeLineaCRLF() throws {
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", "uno 192.0.2.1\r\ndos\r\ntres 192.0.2.1")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try search(LogQuery(text: "192.0.2.1"), dir)
        #expect(r.hits.map(\.text) == ["uno 192.0.2.1", "tres 192.0.2.1"])
        #expect(r.hits.map(\.line) == [1, 3])
        #expect(try search(LogQuery(text: #"1$"#, isRegex: true), dir).hits.count == 2)    // (sin «\r» antes del final)
        #expect(LogSearch.context(file: r.hits[0].file, line: 2).map(\.text) == ["uno 192.0.2.1", "dos", "tres 192.0.2.1"])
    }

    @Test func recuentoPorEquipo() throws {
        let dir = try logs([
            ("2026-11-25", "core-01_10-00-00.log", "x\nx\nx\n"),
            ("2026-11-24", "core-01_10-00-00.log", "x\n"),
            ("2026-11-25", "bastion_10-00-00.log", "x\nx\n"),
            ("2026-11-25", "olt-01_10-00-00.log", "nada\n")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try search(LogQuery(text: "x"), dir)
        #expect(r.hostCounts == [LogHostCount(host: "core-01", count: 4), LogHostCount(host: "bastion", count: 2)])
        #expect(r.filesSearched == 4 && r.filesWithHits == 3 && r.filesSkipped == 0)
        #expect(r.hits.allSatisfy { $0.host == LogSearch.info(of: $0.file).host })
    }

    @Test func rangosParaResaltar() throws {
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", "ñandú 192.0.2.1 y 192.0.2.1 otra vez\nGI0/1 gi0/1\n")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try search(LogQuery(text: "192.0.2.1"), dir)
        #expect(r.hits[0].ranges == [6..<15, 18..<27])                        // (posiciones de carácter, no de bytes)
        let t = r.hits[0].text
        #expect(t[t.index(t.startIndex, offsetBy: 6)..<t.index(t.startIndex, offsetBy: 15)] == "192.0.2.1")
        let g = try search(LogQuery(text: "gi0/1"), dir).hits[0]
        #expect(g.ranges == [0..<5, 6..<11])
        let m = try LogQuery(text: "o", isRegex: true).matcher()
        #expect(m.ranges(in: String(repeating: "o", count: 500), limit: 8).count == 8)
        #expect(m.ranges(in: "sin acierto").count == 1)
        #expect(try LogQuery(text: "x*", isRegex: true).matcher().ranges(in: "abc").isEmpty)    // (sin rangos vacíos)
    }

    @Test func trozosYFilaConElAciertoLejos() throws {
        #expect(LogSegment.split("ñandú 192.0.2.1 fin", ranges: [6..<15]) == [
            LogSegment(text: "ñandú ", isMatch: false), LogSegment(text: "192.0.2.1", isMatch: true), LogSegment(text: " fin", isMatch: false)])
        #expect(LogSegment.split("abab", ranges: [0..<2, 2..<4]).map(\.isMatch) == [true, true])
        #expect(LogSegment.split("abc", ranges: []) == [LogSegment(text: "abc", isMatch: false)])
        #expect(LogSegment.split("", ranges: []).isEmpty)
        #expect(LogSegment.split("abc", ranges: [2..<9, 1..<1]).map(\.text) == ["abc"])           // (fuera de la línea o vacío: se ignora)
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", String(repeating: "x", count: 100) + " 192.0.2.1 fin\n192.0.2.1 al principio\n")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let hits = try search(LogQuery(text: "192.0.2.1"), dir).hits
        let far = hits[0].preview(), near = hits[1].preview()
        #expect(far.text.hasPrefix("…") && far.text.count == 54)            // (114 caracteres, el acierto en el 101: se quitan 61)
        #expect(LogSegment.split(far.text, ranges: far.ranges).filter(\.isMatch).map(\.text) == ["192.0.2.1"])
        #expect(near.text == hits[1].text && near.ranges == hits[1].ranges)
    }

    @Test func contextoEnLosBordesDelArchivo() throws {
        let text = (1...30).map { "l\($0)\n" }.joined()
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", text)])
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("2026-11-25/core-01_10-00-00.log")
        let first = LogSearch.context(file: file, line: 1)
        #expect(first.map(\.number) == Array(1...13) && first.map(\.isHit) == [true] + Array(repeating: false, count: 12))
        let last = LogSearch.context(file: file, line: 30)
        #expect(last.map(\.number) == Array(18...30) && last.last?.isHit == true)
        let mid = LogSearch.context(file: file, line: 15, before: 2, after: 1)
        #expect(mid.map(\.text) == ["l13", "l14", "l15", "l16"])
        #expect(LogSearch.context(file: file, line: 31).isEmpty)
        #expect(LogSearch.context(file: file, line: 0).isEmpty)
        #expect(LogSearch.context(file: dir.appendingPathComponent("no-existe.log"), line: 1).isEmpty)
    }

    @Test func textosDelResultado() throws {
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", "x\nx\n"), ("2026-11-25", "bastion_10-00-00.log", "x\n"),
                            ("2026-11-24", "olt-01_10-00-00.log.gz", "x\n")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try search(LogQuery(text: "x"), dir)
        // (sin fijar el idioma: las cifras y los nombres salen en los dos)
        #expect(r.summary.contains("3") && r.summary.contains("2") && !r.summary.contains("+"))
        #expect(r.hostSummary()?.hasSuffix("core-01 2 · bastion 1") == true)
        #expect(r.warnings == [L("1 archivo comprimido sin leer")])
        let t = try search(LogQuery(text: "x", maxHits: 1), dir)
        #expect(t.summary.contains("1+") && t.hostSummary() == nil && t.warnings.count == 1)
        let one = try search(LogQuery(text: "x", host: "bastion"), dir)
        #expect(one.summary == L("\(L("1 línea")) en \(L("1 archivo"))") && one.warnings.isEmpty)
    }

    @Test func consultaVaciaNoBusca() throws {
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", "algo\n")])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try search(LogQuery(text: "   "), dir).hits.isEmpty)
        #expect(try search(LogQuery(text: "  algo  "), dir).hits.count == 1)
    }

    @Test func sinLectorParaLosComprimidos() throws {
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", "x\n"), ("2026-11-20", "core-01_10-00-00.log.gz", "no es gzip")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try search(LogQuery(text: "x"), dir, reader: PlainLogReader())
        #expect(r.hits.count == 1 && r.filesSkipped == 1 && r.filesSearched == 1)
    }

    #if os(macOS)
    @Test func registrosComprimidosEnElMac() throws {
        let dir = try logs([("2026-11-25", "core-01_10-00-00.log", "hoy 192.0.2.1\n"), ("2026-10-01", "core-01_10-00-00.log", "viejo\n")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = dir.appendingPathComponent("2026-10-01/core-01_10-00-00.log")
        try Data("antes\nhace un mes 192.0.2.1\n".utf8).write(to: old)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        p.arguments = ["-f", old.path]
        try p.run()
        p.waitUntilExit()
        #expect(FileManager.default.fileExists(atPath: old.path + ".gz"))
        let r = try search(LogQuery(text: "192.0.2.1"), dir, reader: SystemLogReader())
        #expect(r.hits.map(\.text) == ["hoy 192.0.2.1", "hace un mes 192.0.2.1"])
        #expect(r.hits.map(\.line) == [1, 2] && r.filesSkipped == 0)
        #expect(LogSearch.context(file: r.hits[1].file, line: 2, reader: SystemLogReader()).map(\.text) == ["antes", "hace un mes 192.0.2.1"])
        #expect(try search(LogQuery(text: "192.0.2.1", period: .week), dir, reader: SystemLogReader()).hits.count == 1)
    }
    #endif
}
