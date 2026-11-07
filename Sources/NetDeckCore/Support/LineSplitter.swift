import Foundation

/// Parte en líneas lo que llega a trozos (la salida de grep en «Buscar en todos los registros»), sin tenerla entera en
/// memoria: cada línea, como mucho de `maxLine` bytes (lo que sobra hasta su salto de línea se descarta).
public struct LineSplitter: Sendable {
    public let maxLine: Int
    private var pending = Data()
    private var cut = false

    public init(maxLine: Int = 4096) { self.maxLine = max(1, maxLine) }

    /// Las líneas que ya se han completado con este trozo (sin su «\n»).
    public mutating func feed(_ data: Data) -> [String] {
        var out: [String] = []
        var start = data.startIndex
        while let nl = data[start...].firstIndex(of: 0x0A) {
            keep(data[start..<nl])
            out.append(flush())
            start = data.index(after: nl)
        }
        keep(data[start...])
        return out
    }

    /// La última, si no acababa en «\n».
    public mutating func finish() -> [String] { pending.isEmpty && !cut ? [] : [flush()] }

    private mutating func keep(_ part: Data) {
        guard !cut, !part.isEmpty else { return }
        let room = maxLine - pending.count
        if part.count > room { pending.append(part.prefix(room)); cut = true } else { pending.append(part) }
    }

    private mutating func flush() -> String {
        defer { pending.removeAll(keepingCapacity: true); cut = false }
        return String(decoding: pending, as: UTF8.self)
    }
}
