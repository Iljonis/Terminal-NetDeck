import Foundation

/// Una línea que acierta: dónde está, su texto (cortado a `LogQuery.maxLine` bytes) y qué trozos resaltar.
public struct LogHit: Sendable, Hashable, Identifiable {
    public let file: URL
    public let line: Int
    public let text: String
    /// Los trozos que aciertan, en posiciones de carácter de `text`.
    public let ranges: [Range<Int>]
    public let host: String

    public var id: String { "\(file.path):\(line)" }
}

public struct LogHostCount: Sendable, Hashable {
    public let host: String
    public let count: Int
}

public struct LogSearchResult: Sendable {
    public var hits: [LogHit] = []
    /// Los archivos que se han leído y los que tenían aciertos.
    public var filesSearched = 0
    public var filesWithHits = 0
    /// Los que el lector no sabe abrir (en Windows, los `.log.gz`).
    public var filesSkipped = 0
    /// Había más aciertos que `maxHits`.
    public var truncated = false
    public var cancelled = false
    /// Aciertos por equipo, de más a menos.
    public var hostCounts: [LogHostCount] = []
}

/// Un trozo de una línea, con o sin acierto (para pintar el resaltado sin saber de posiciones).
public struct LogSegment: Sendable, Hashable {
    public let text: String
    public let isMatch: Bool

    /// La línea partida en trozos según los `ranges` (posiciones de carácter, en orden y sin solaparse).
    public static func split(_ text: String, ranges: [Range<Int>]) -> [LogSegment] {
        let chars = Array(text)
        var out: [LogSegment] = []
        var pos = 0
        for r in ranges where r.lowerBound >= pos && r.upperBound <= chars.count && !r.isEmpty {
            if r.lowerBound > pos { out.append(LogSegment(text: String(chars[pos..<r.lowerBound]), isMatch: false)) }
            out.append(LogSegment(text: String(chars[r]), isMatch: true))
            pos = r.upperBound
        }
        if pos < chars.count { out.append(LogSegment(text: String(chars[pos...]), isMatch: false)) }
        return out
    }
}

extension LogHit {
    /// Para una fila de una sola línea: si el primer acierto queda a más de `lead` caracteres del principio, la línea
    /// empieza justo antes («…») y los rangos se corren con ella.
    public func preview(lead: Int = 40) -> (text: String, ranges: [Range<Int>]) {
        let drop = max(0, (ranges.first?.lowerBound ?? 0) - lead)
        guard drop > 0 else { return (text, ranges) }
        return ("…" + text.dropFirst(drop), ranges.filter { $0.lowerBound >= drop }.map { ($0.lowerBound - drop + 1)..<($0.upperBound - drop + 1) })
    }
}

/// Una línea del contexto de un acierto.
public struct LogContextLine: Sendable, Hashable {
    public let number: Int
    public let text: String
    public let isHit: Bool
}

/// «Buscar en todos los registros»: la lógica de la hoja del Mac y del panel de Windows, que sólo la pintan. Lee
/// `carpeta/AAAA-MM-DD/equipo_HH-MM-SS.log` (lo que graba `SessionLogger`), lo más reciente primero, a trozos.
public enum LogSearch {
    public static let contextLines = 12

    public static var defaultReader: any LogFileReader {
        #if os(macOS)
        SystemLogReader()
        #else
        PlainLogReader()
        #endif
    }

    /// AAAAMMDD de un día (para comparar la carpeta del día con el periodo sin husos horarios de por medio).
    static func dayKey(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// El equipo y el día de un registro: carpeta `AAAA-MM-DD/` y archivo `<nombre>_HH-mm-ss[-N].log[.gz]`.
    public static func info(of file: URL) -> (host: String, day: Int?) {
        var name = file.lastPathComponent
        for ext in [".log.gz", ".log"] where name.lowercased().hasSuffix(ext) {
            name = String(name.dropLast(ext.count))
            break
        }
        var host = name
        if let r = name.range(of: #"_\d{2}-\d{2}-\d{2}(-\d+)?$"#, options: .regularExpression) { host = String(name[..<r.lowerBound]) }
        let parts = file.deletingLastPathComponent().lastPathComponent.split(separator: "-", omittingEmptySubsequences: false)
        let nums = parts.compactMap { Int($0) }
        let day = parts.count == 3 && nums.count == 3 && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
            ? nums[0] * 10_000 + nums[1] * 100 + nums[2] : nil
        return (host, day)
    }

    /// Los registros de la carpeta (`.log` y `.log.gz`), lo más reciente primero.
    static func logFiles(in dir: URL) -> [URL] {
        var files: [URL] = []
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        while let f = e?.nextObject() as? URL {
            let n = f.lastPathComponent.lowercased()
            if n.hasSuffix(".log") || n.hasSuffix(".log.gz") { files.append(f) }
        }
        return files.sorted { $0.path > $1.path }
    }

    /// Los equipos que tienen registros (para el selector), por orden alfabético.
    public static func hosts(in dir: URL) -> [String] {
        let all = Set(logFiles(in: dir).map { info(of: $0).host })
        return all.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Las líneas de un archivo, una a una y numeradas desde 1 (sin el «\r» de un CRLF y cortadas a `maxLine` bytes).
    /// `body` devuelve false para parar. Un archivo que no se puede leer, se da por vacío.
    /// Con `matcher`, los trozos sin ningún acierto posible se saltan sin mirar sus líneas una a una.
    static func eachLine(_ file: URL, reader: any LogFileReader, matcher: LogMatcher? = nil, isCancelled: () -> Bool,
                         _ body: (Int, String) -> Bool) {
        var splitter = LineSplitter(maxLine: LogQuery.maxLine)
        var n = 0, stopped = false
        func clean(_ raw: String) -> String { raw.utf8.last == 0x0D ? String(raw.dropLast()) : raw }
        func emit(_ line: String) {
            n += 1
            if !body(n, line) { stopped = true }
        }
        try? reader.read(file) { data in
            if isCancelled() { stopped = true; return false }
            let lines = splitter.feed(data).map(clean)
            if let matcher, !lines.isEmpty, !matcher.mayMatch(block: lines.joined(separator: "\n")) {
                n += lines.count
                return true
            }
            for l in lines {
                emit(l)
                if stopped { return false }
            }
            return true
        }
        if !stopped { splitter.finish().map(clean).forEach(emit) }
    }

    /// Busca en todos los registros de `dir`. Un regex que no compila lanza `LogSearchError`; con `isCancelled` en true
    /// devuelve lo que lleva (`cancelled`). Nunca tiene un archivo entero en memoria.
    public static func search(_ query: LogQuery, in dir: URL, reader: any LogFileReader = defaultReader,
                              now: Date = Date(), calendar: Calendar = .current,
                              isCancelled: () -> Bool = { false }) throws -> LogSearchResult {
        var result = LogSearchResult()
        guard !query.trimmed.isEmpty else { return result }
        let matcher = try query.matcher()
        let firstDay = query.period.firstDay(now: now, calendar: calendar)
        searching: for file in logFiles(in: dir) {
            if isCancelled() { result.cancelled = true; break }
            let (host, day) = info(of: file)
            if let wanted = query.host, host.caseInsensitiveCompare(wanted) != .orderedSame { continue }
            if let firstDay, (day ?? 0) < firstDay { continue }          // (sin carpeta de día no se sabe de cuándo es)
            guard reader.canRead(file) else { result.filesSkipped += 1; continue }
            result.filesSearched += 1
            eachLine(file, reader: reader, matcher: matcher, isCancelled: isCancelled) { n, text in
                guard matcher.matches(text) else { return true }
                result.hits.append(LogHit(file: file, line: n, text: text, ranges: matcher.ranges(in: text), host: host))
                return result.hits.count <= query.maxHits                // (uno de más: así se sabe que hay más)
            }
            if isCancelled() { result.cancelled = true; break }
            if result.hits.count > query.maxHits {
                result.hits.removeLast()
                result.truncated = true
                break searching
            }
        }
        result.filesWithHits = Set(result.hits.map(\.file)).count
        let counts = Dictionary(grouping: result.hits, by: \.host).map { LogHostCount(host: $0.key, count: $0.value.count) }
        result.hostCounts = counts.sorted { $0.count != $1.count ? $0.count > $1.count : $0.host < $1.host }
        return result
    }

    /// Las líneas de alrededor de la `line` de un archivo (la suya incluida, marcada), leídas hasta donde hacen falta.
    /// Vacío si el archivo no llega a esa línea.
    public static func context(file: URL, line: Int, before: Int = contextLines, after: Int = contextLines,
                               reader: any LogFileReader = defaultReader,
                               isCancelled: () -> Bool = { false }) -> [LogContextLine] {
        var out: [LogContextLine] = []
        var found = false
        eachLine(file, reader: reader, isCancelled: isCancelled) { n, text in
            if n >= line - before, n <= line + after { out.append(LogContextLine(number: n, text: text, isHit: n == line)) }
            if n == line { found = true }
            return n < line + after
        }
        return found ? out : []
    }
}

/// Los textos de debajo del buscador, los mismos en el Mac y en Windows.
extension LogSearchResult {
    /// «12 líneas en 3 archivos» (con «+» si hay más que el tope).
    public var summary: String {
        let lines = hits.count == 1 && !truncated ? L("1 línea") : L("\(hits.count)\(truncated ? "+" : "") líneas")
        let files = filesWithHits == 1 ? L("1 archivo") : L("\(filesWithHits) archivos")
        return L("\(lines) en \(files)")
    }

    /// Lo que el usuario debe saber del resultado (el tope y lo que no se ha podido leer).
    public var warnings: [String] {
        var out: [String] = []
        if truncated { out.append(L("Hay más aciertos: se muestran los primeros \(hits.count). Afina la búsqueda.")) }
        if filesSkipped == 1 { out.append(L("1 archivo comprimido sin leer")) }
        if filesSkipped > 1 { out.append(L("\(filesSkipped) archivos comprimidos sin leer")) }
        return out
    }

    /// «core-01 12 · bastion 3 · …» (los `limit` equipos con más aciertos); nil si hay uno o ninguno.
    public func hostSummary(limit: Int = 6) -> String? {
        guard hostCounts.count > 1 else { return nil }
        let shown = hostCounts.prefix(limit).map { "\($0.host) \($0.count)" }.joined(separator: " · ")
        return L("Por equipo: \(shown + (hostCounts.count > limit ? " …" : ""))")
    }
}
