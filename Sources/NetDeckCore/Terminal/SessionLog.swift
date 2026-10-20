import Foundation

/// La salida de una pestaña como texto limpio, como «registro.py» de NetDeck: lo que se veía en la pantalla. Los
/// movimientos del cursor se aplican (el «---- More ----» de Huawei se borra con ESC[42D + espacios, el «--More--» de
/// Cisco con retrocesos, las barras de progreso reescriben la línea con \r) y los colores se quitan, aunque una
/// secuencia llegue partida en dos lecturas.
public struct LogLineRenderer: Sendable {
    /// Una línea más larga se corta y el cursor no pasa de ahí (un «ESC[999999999C» no reserva memoria sin fin).
    public static let maxLine = 65_536
    private var chars: [Character] = []
    private var x = 0
    /// Lo que quedó a medias (una secuencia de escape o un carácter UTF-8 partido).
    private var carry: [UInt8] = []
    /// Las líneas acabadas en este trozo (también las cortadas por largas).
    private var done: [String] = []

    public init() {}

    /// Las líneas terminadas con este trozo.
    public mutating func feed<S: Sequence>(_ bytes: S) -> [String] where S.Element == UInt8 {
        var data = carry + Array(bytes)
        carry = []
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
                case 0x0A: done.append(take())
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
        let out = done
        done = []
        return out
    }

    /// Lo que queda en la línea (al cerrar).
    public mutating func finish() -> String? {
        let s = take()
        return s.isEmpty ? nil : s
    }

    /// La línea sin los espacios del final (de atrás hacia delante: una línea de espacios no cuesta más que su largo).
    private mutating func take() -> String {
        var end = chars.count
        while end > 0, chars[end - 1].isWhitespace { end -= 1 }
        let s = String(chars[..<end])
        chars = []
        x = 0
        return s
    }

    private mutating func put(_ s: String) {
        for ch in s {
            if x >= Self.maxLine { done.append(take()) }    // (sin saltos de línea: no crece sin límite)
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
        // (con tope: «ESC[9223372036854775807C» no desborda y el cursor no sale de la línea)
        let n = min(Int(params.split(separator: ";").first ?? "") ?? 0, Self.maxLine)
        switch final {
        case "D": x = max(0, x - max(n, 1))
        case "C": x = min(Self.maxLine, x + max(n, 1))
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
/// Uno por conexión: si ya hay otro con ese nombre (la misma sesión abierta dos veces en el mismo segundo), «…-2.log».
/// Si no se puede escribir, se deja de grabar y se avisa (`onFailure`), nunca en silencio.
public final class SessionLogger: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private var renderer = LogLineRenderer()
    private var failed: String?
    private var failureHandler: (@Sendable (String) -> Void)?
    /// Una vez, desde la cola de salida, con el motivo: no se ha podido escribir y ya no se graba.
    public var onFailure: (@Sendable (String) -> Void)? {
        get { lock.withLock { failureHandler } }
        set { lock.withLock { failureHandler = newValue } }
    }
    /// (pruebas) cómo se escribe en el archivo.
    var writeData: (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) }

    public static var defaultDirectory: URL { AppPaths.home.appendingPathComponent("Documents/netdeck-logs", isDirectory: true) }

    public init(directory: URL, name: String, host: String, date: Date = Date()) throws {
        let day = DateFormatter(), time = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        time.dateFormat = "HH-mm-ss"
        let safe = name.replacingOccurrences(of: #"[^A-Za-z0-9._@-]+"#, with: "_", options: .regularExpression)
        let dir = directory.appendingPathComponent(day.string(from: date), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let base = "\(safe)_\(time.string(from: date))"
        var n = 1, fd: Int32 = -1, candidate = dir
        while fd < 0 {
            candidate = dir.appendingPathComponent(n == 1 ? "\(base).log" : "\(base)-\(n).log")
            // (O_EXCL: sólo uno nuevo; nunca se sigue escribiendo en el de otra conexión)
            fd = open(candidate.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
            if fd < 0 {
                let code = errno
                guard code == EEXIST, n < 1000 else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
                n += 1
            }
        }
        url = candidate
        let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle = h
        try h.write(contentsOf: Data("=== NetDeck · \(host) · \(Self.stamp()) ===\n".utf8))
    }

    /// El motivo si ha dejado de grabar porque no se podía escribir.
    public var failure: String? { lock.withLock { failed } }

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
            failureHandler = nil                    // (suelta el aviso: si lo retenía a él, no queda un ciclo)
        }
    }

    private func writeLocked(_ s: String) {
        guard let h = handle else { return }
        do { try writeData(h, Data(s.utf8)) } catch {
            let why = error.localizedDescription
            failed = why
            try? h.close()
            handle = nil
            ErrorLog.error("registro", "\(AppPaths.tilde(url.path)): \(why)")
            failureHandler?(why)
        }
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
