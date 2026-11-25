import Foundation

/// Cómo se leen los registros de `LogSearch`: por trozos (nunca un archivo entero en memoria) y con lo que cada
/// sistema sepa abrir. Se inyecta para poder probar la búsqueda y para que Windows lea sólo los `.log`.
public protocol LogFileReader: Sendable {
    /// ¿Sabe leer este archivo? Si no, la búsqueda lo cuenta como «sin leer».
    func canRead(_ file: URL) -> Bool
    /// Entrega el contenido a trozos; si `chunk` devuelve false, se para.
    func read(_ file: URL, chunk: (Data) -> Bool) throws
}

/// Los `.log` tal cual, a trozos de 64 KB.
public struct PlainLogReader: LogFileReader {
    public static let chunkSize = 64 * 1024

    public init() {}

    public func canRead(_ file: URL) -> Bool { file.lastPathComponent.lowercased().hasSuffix(".log") }

    public func read(_ file: URL, chunk: (Data) -> Bool) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        while let data = try handle.read(upToCount: Self.chunkSize), !data.isEmpty {
            if !chunk(data) { return }
        }
    }
}

#if os(macOS)
/// En el Mac, además, los `.log.gz` (con `gzcat`, a trozos de lo que va saliendo).
public struct SystemLogReader: LogFileReader {
    private let plain = PlainLogReader()

    public init() {}

    private func isGzip(_ file: URL) -> Bool { file.lastPathComponent.lowercased().hasSuffix(".log.gz") }

    public func canRead(_ file: URL) -> Bool { isGzip(file) || plain.canRead(file) }

    public func read(_ file: URL, chunk: (Data) -> Bool) throws {
        guard isGzip(file) else { return try plain.read(file, chunk: chunk) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/gzcat")
        p.arguments = [file.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        let h = pipe.fileHandleForReading
        while case let d = h.availableData, !d.isEmpty {
            if !chunk(d) { break }
        }
        if p.isRunning { p.terminate() }                            // (cancelado o con el tope: no se descomprime el resto)
        p.waitUntilExit()
    }
}
#endif
