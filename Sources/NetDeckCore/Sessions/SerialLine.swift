import Foundation

/// Puerto serie de una sesión de consola: «# @serie /dev/cu.usbserial-0001 9600 8N1». Se abre con
/// «/usr/bin/screen dispositivo velocidad,cs8,…» (screen no ejecuta nada más: la ruta se valida igualmente).
public struct SerialLine: Hashable, Sendable, Codable {
    public enum Parity: String, Sendable, Codable, CaseIterable { case none = "N", even = "E", odd = "O" }

    public var device: String
    public var speed: Int
    public var dataBits: Int
    public var parity: Parity
    public var stopBits: Int

    public static let speeds = [9600, 19200, 38400, 57600, 115200]
    public static let screen = "/usr/bin/screen"
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
            let f = Array(p[2].uppercased())
            guard f.count == 3, let d = f[0].wholeNumberValue, let par = Parity(rawValue: String(f[1])),
                  let st = f[2].wholeNumberValue else { return nil }
            (dataBits, parity, stopBits) = (d, par, st)
        }
        guard isValid else { return nil }
    }

    public static func isValidDevice(_ d: String) -> Bool { deviceRule.matches(d) && !d.contains("..") }

    public var isValid: Bool {
        Self.isValidDevice(device) && Self.speeds.contains(speed) && (7...8).contains(dataBits) && (1...2).contains(stopBits)
    }

    /// «8N1»
    public var frame: String { "\(dataBits)\(parity.rawValue)\(stopBits)" }
    public var annotation: String { "\(device) \(speed) \(frame)" }

    /// Lo que entiende screen: velocidad y bits de datos (sin control de flujo). La paridad y los bits de parada no los
    /// admite: se guardan para la ficha, pero el puerto queda como lo deje el sistema (lo habitual, sin paridad y 1).
    public var screenArguments: [String] { [device, "\(speed),cs\(dataBits),-ixon,-ixoff"] }

    /// Los puertos /dev/cu.* de este Mac (adaptadores USB-serie, consolas…), sin los que no son de verdad.
    public static func devices(in dir: String = "/dev") -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasPrefix("cu.") && $0 != "cu.Bluetooth-Incoming-Port" && $0 != "cu.debug-console" }
            .map { "\(dir)/\($0)" }.filter(isValidDevice).sorted()
    }
}
