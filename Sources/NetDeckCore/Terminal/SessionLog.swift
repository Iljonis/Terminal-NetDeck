import Foundation

/// La salida de una pestaña como texto limpio, como «registro.py» de NetDeck: lo que se veía en la pantalla. Los
/// movimientos del cursor se aplican (el «---- More ----» de Huawei se borra con ESC[42D + espacios, el «--More--» de
/// Cisco con retrocesos, las barras de progreso reescriben la línea con \r) y los colores se quitan, aunque una
/// secuencia llegue partida en dos lecturas.
public struct LogLineRenderer: Sendable {
    private var chars: [Character] = []
    private var x = 0
    /// Lo que quedó a medias (una secuencia de escape o un carácter UTF-8 partido).
    private var carry: [UInt8] = []

    public init() {}

    /// Las líneas terminadas con este trozo.
    public mutating func feed<S: Sequence>(_ bytes: S) -> [String] where S.Element == UInt8 {
        var data = carry + Array(bytes)
        carry = []
        var out: [String] = []
        var i = 0
        var text: [UInt8] = []
        func flushText() {
            guard !text.isEmpty else { return }
            put(String(decoding: text, as: UTF8.self))
            text.removeAll(keepingCapacity: true)
        }
        while i < data.count {
            let b = data[i]
            if b == 0x1B {
                flushText()
                guard let end = Self.escapeEnd(data, i) else {           // a medias: para la siguiente lectura
                    if data.count - i < 4096 { carry = Array(data[i...]) }
                    data.removeAll()
                    break
                }
                if data.count > i + 1, data[i + 1] == UInt8(ascii: "["), end > i + 2 {
                    let params = String(decoding: data[(i + 2)..<(end - 1)], as: UTF8.self)
                    csi(params, Character(UnicodeScalar(data[end - 1])))
                }
                i = end
            } else if b < 0x20 || b == 0x7F {
                flushText()
                switch b {
                case 0x0A: out.append(take())
                case 0x0D: x = 0
                case 0x08: x = max(0, x - 1)
                case 0x09: put("\t")
                default: break
                }
                i += 1
            } else {
                text.append(b)
                i += 1
            }
        }
        // un carácter UTF-8 partido al final: se guarda entero para la siguiente
        if !text.isEmpty {
            let cut = Self.incompleteUTF8Tail(text)
            if cut > 0 { carry = Array(text.suffix(cut)) + carry; text.removeLast(cut) }
            flushText()
        }
        return out
    }

    /// Lo que queda en la línea (al cerrar).
    public mutating func finish() -> String? {
        let s = take()
        return s.isEmpty ? nil : s
    }

    private mutating func take() -> String {
        let s = String(chars).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        chars = []
        x = 0
        return s
    }

    private mutating func put(_ s: String) {
        for ch in s {
            if x < chars.count {
                chars[x] = ch
            } else {
                chars += Array(repeating: " ", count: x - chars.count)
                chars.append(ch)
            }
            x += 1
        }
    }

    /// Sólo importan los que mueven el cursor en la línea o la borran.
    private mutating func csi(_ params: String, _ final: Character) {
        let n = Int(params.split(separator: ";").first ?? "") ?? 0
        switch final {
        case "D": x = max(0, x - max(n, 1))
        case "C": x += max(n, 1)
        case "G": x = max(0, max(n, 1) - 1)
        case "K":
            switch n {
            case 0: if x < chars.count { chars.removeSubrange(x...) }
            case 1: for j in 0..<min(x, chars.count) { chars[j] = " " }
            default: chars = []
            }
        default: break
        }
    }

    /// Fin (exclusivo) de la secuencia que empieza en `i` (ESC), o nil si está a medias.
    static func escapeEnd(_ d: [UInt8], _ i: Int) -> Int? {
        guard i + 1 < d.count else { return nil }
        let c = d[i + 1]
        switch c {
        case UInt8(ascii: "["):
            var j = i + 2
            while j < d.count {
                if (0x40...0x7E).contains(d[j]) { return j + 1 }
                j += 1
            }
            return nil
        case UInt8(ascii: "]"), UInt8(ascii: "P"), UInt8(ascii: "_"), UInt8(ascii: "^"):
            var j = i + 2
            while j < d.count {
                if d[j] == 0x07 { return j + 1 }
                if d[j] == 0x1B { return j + 1 < d.count ? (d[j + 1] == UInt8(ascii: "\\") ? j + 2 : j + 1) : nil }
                j += 1
            }
            return nil
        case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: "#"):
            return i + 2 < d.count ? i + 3 : nil
        default:
            return i + 2
        }
    }

    /// Bytes del final que son un carácter UTF-8 sin terminar.
    static func incompleteUTF8Tail(_ b: [UInt8]) -> Int {
        var n = 0
        for k in stride(from: b.count - 1, through: max(0, b.count - 4), by: -1) {
            n += 1
            let v = b[k]
            if v & 0xC0 == 0x80 { continue }                         // continuación
            let need = v & 0xE0 == 0xC0 ? 2 : (v & 0xF0 == 0xE0 ? 3 : (v & 0xF8 == 0xF0 ? 4 : 1))
            return need > n ? n : 0
        }
        return 0
    }
}

/// El registro de una pestaña en disco (~/Documents/netdeck-logs/AAAA-MM-DD/sesión_HH-MM-SS.log, como NetDeck: así
/// «buscar-registros» de NetDeck también los encuentra). Sólo lo puede leer el usuario (lleva todo lo de la sesión).
public final class SessionLogger: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private var renderer = LogLineRenderer()

    public static var defaultDirectory: URL { AppPaths.home.appendingPathComponent("Documents/netdeck-logs", isDirectory: true) }

    public init?(directory: URL, name: String, host: String, date: Date = Date()) {
        let day = DateFormatter(), time = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        time.dateFormat = "HH-mm-ss"
        let safe = name.replacingOccurrences(of: #"[^A-Za-z0-9._@-]+"#, with: "_", options: .regularExpression)
        let dir = directory.appendingPathComponent(day.string(from: date), isDirectory: true)
        url = dir.appendingPathComponent("\(safe)_\(time.string(from: date)).log")
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            handle = try FileHandle(forWritingTo: url)
            _ = try handle?.seekToEnd()
        } catch {
            return nil
        }
        write("=== NetDeck · \(host) · \(Self.stamp()) ===\n")
    }

    /// Lo que sale de la sesión, tal cual (desde la cola de salida).
    public func feed(_ bytes: ArraySlice<UInt8>) {
        lock.withLock {
            let lines = renderer.feed(bytes)
            if !lines.isEmpty { writeLocked(lines.map { $0 + "\n" }.joined()) }
        }
    }

    public func close() {
        lock.withLock {
            if let rest = renderer.finish() { writeLocked(rest + "\n") }
            writeLocked("=== fin · \(Self.stamp()) ===\n")
            try? handle?.close()
            handle = nil
        }
    }

    private func write(_ s: String) { lock.withLock { writeLocked(s) } }
    private func writeLocked(_ s: String) { try? handle?.write(contentsOf: Data(s.utf8)) }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
