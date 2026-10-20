import Foundation

/// Puerto serie de una sesión de consola: «# @serie /dev/cu.usbserial-0001 9600 8N1». Lo abre la propia app
/// (`SerialPort`, termios: velocidad, bits de datos, paridad y bits de parada, comprobados al abrir).
public struct SerialLine: Hashable, Sendable, Codable {
    public enum Parity: String, Sendable, Codable, CaseIterable { case none = "N", even = "E", odd = "O" }

    public var device: String
    public var speed: Int
    public var dataBits: Int
    public var parity: Parity
    public var stopBits: Int

    public static let speeds = [9600, 19200, 38400, 57600, 115200]
    /// Sólo /dev/cu.* o /dev/tty.*, sin espacios ni nada que una shell entienda.
    private static let deviceRule = Pattern(#"^/dev/(cu|tty)\.[A-Za-z0-9._-]+$"#, ignoreCase: false)

    public init(device: String = "", speed: Int = 9600, dataBits: Int = 8, parity: Parity = .none, stopBits: Int = 1) {
        self.device = device
        self.speed = speed
        self.dataBits = dataBits
        self.parity = parity
        self.stopBits = stopBits
    }

    /// «/dev/cu.usbserial-0001 9600 8N1» (velocidad y trama opcionales). nil si no es un puerto válido.
    public init?(annotation: String) {
        let p = annotation.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let dev = p.first else { return nil }
        self.init(device: dev)
        if p.count > 1 { guard let s = Int(p[1]) else { return nil }; speed = s }
        if p.count > 2 {
            guard let f = Self.parseFrame(p[2]) else { return nil }
            (dataBits, parity, stopBits) = f
        }
        guard isValid else { return nil }
    }

    /// «8N1», «7E2», «5O1»…: bits de datos (5–8), paridad (N/E/O) y bits de parada (1–2); nil si no es eso.
    public static func parseFrame(_ s: String) -> (dataBits: Int, parity: Parity, stopBits: Int)? {
        let f = Array(s.uppercased())
        guard f.count == 3, f.allSatisfy(\.isASCII), let d = f[0].wholeNumberValue, (5...8).contains(d), let par = Parity(rawValue: String(f[1])),
              let st = f[2].wholeNumberValue, (1...2).contains(st) else { return nil }
        return (d, par, st)
    }

    public static func isValidDevice(_ d: String) -> Bool { deviceRule.matches(d) && !d.contains("..") }

    public var isValid: Bool { problem == nil }

    /// Por qué no se puede abrir (antes de tocar el dispositivo), o nil.
    public var problem: String? {
        if !Self.isValidDevice(device) { return L("Puerto serie no válido: «\(device)» (sólo /dev/cu.* o /dev/tty.*)") }
        if !Self.speeds.contains(speed) { return L("Velocidad no admitida: \(String(speed))") }
        if !(5...8).contains(dataBits) || !(1...2).contains(stopBits) { return L("Trama no admitida: «\(frame)»") }
        return nil
    }

    /// «8N1»
    public var frame: String { "\(dataBits)\(parity.rawValue)\(stopBits)" }
    public var annotation: String { "\(device) \(speed) \(frame)" }

    /// Los puertos /dev/cu.* de este Mac (adaptadores USB-serie, consolas…), sin los que no son de verdad.
    public static func devices(in dir: String = "/dev") -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasPrefix("cu.") && $0 != "cu.Bluetooth-Incoming-Port" && $0 != "cu.debug-console" }
            .map { "\(dir)/\($0)" }.filter(isValidDevice).sorted()
    }
}
