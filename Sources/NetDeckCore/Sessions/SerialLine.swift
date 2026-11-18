import Foundation
#if os(Windows)
import WinSDK
#endif

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
    #if os(Windows)
    /// En Windows, además, COMn (n >= 1): «COM1», «COM3», «COM15».
    private static let deviceRuleWindows = Pattern(#"^COM[1-9][0-9]*$"#, ignoreCase: true)
    #endif

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

    public static func isValidDevice(_ d: String) -> Bool {
        #if os(Windows)
        // (las rutas /dev/* siguen valiendo como texto: un archivo de sesiones escrito en el Mac se lee igual)
        if deviceRuleWindows.matches(d) { return true }
        #endif
        return deviceRule.matches(d) && !d.contains("..")
    }

    /// La ruta con la que se abre el dispositivo. En Windows, COMn pasa a «\\.\COMn»: sin ese prefijo, de COM10 en
    /// adelante no se abre.
    public var deviceForOpen: String {
        #if os(Windows)
        if Self.deviceRuleWindows.matches(device) { return #"\\.\"# + device.uppercased() }
        #endif
        return device
    }

    public var isValid: Bool { problem == nil }

    /// Por qué no se puede abrir (antes de tocar el dispositivo), o nil.
    public var problem: String? {
        #if os(Windows)
        if !Self.isValidDevice(device) { return L("Puerto serie no válido: «\(device)» (sólo COMn)") }
        #else
        if !Self.isValidDevice(device) { return L("Puerto serie no válido: «\(device)» (sólo /dev/cu.* o /dev/tty.*)") }
        #endif
        if !Self.speeds.contains(speed) { return L("Velocidad no admitida: \(String(speed))") }
        if !(5...8).contains(dataBits) || !(1...2).contains(stopBits) { return L("Trama no admitida: «\(frame)»") }
        return nil
    }

    /// «8N1»
    public var frame: String { "\(dataBits)\(parity.rawValue)\(stopBits)" }
    public var annotation: String { "\(device) \(speed) \(frame)" }

    /// Los puertos disponibles: en macOS, /dev/cu.* (adaptadores USB-serie, consolas…) sin los que no son de verdad;
    /// en Windows, los puertos COM del registro (HKLM\HARDWARE\DEVICEMAP\SERIALCOMM).
    public static func devices(in dir: String = "/dev") -> [String] {
        #if os(Windows)
        return _devicesFromRegistry()
        #else
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasPrefix("cu.") && $0 != "cu.Bluetooth-Incoming-Port" && $0 != "cu.debug-console" }
            .map { "\(dir)/\($0)" }.filter(isValidDevice).sorted()
        #endif
    }

    #if os(Windows)
    // HKLM\HARDWARE\DEVICEMAP\SERIALCOMM: nombre de cada valor = \Device\SerialN, dato = COMn.
    private static func _devicesFromRegistry() -> [String] {
        var hKey: HKEY? = nil
        let opened = "HARDWARE\\DEVICEMAP\\SERIALCOMM".withCString(encodedAs: UTF16.self) {
            RegOpenKeyExW(HKEY_LOCAL_MACHINE, $0, 0, DWORD(0x20019 /* KEY_READ */), &hKey)
        }
        guard opened == 0, let key = hKey else { return [] }
        defer { RegCloseKey(key) }

        var ports: [String] = []
        var index: DWORD = 0
        while true {
            var nameBuffer = [WCHAR](repeating: 0, count: 260)
            var nameLen: DWORD = 260
            var dataBuffer = [WCHAR](repeating: 0, count: 260)
            var dataLen: DWORD = DWORD(MemoryLayout<WCHAR>.size * 260)
            var regType: DWORD = 0
            let r: LSTATUS = dataBuffer.withUnsafeMutableBytes { raw in
                RegEnumValueW(key, index, &nameBuffer, &nameLen, nil, &regType,
                              raw.baseAddress?.assumingMemoryBound(to: BYTE.self),
                              &dataLen)
            }
            if r == 259 { break }   // ERROR_NO_MORE_ITEMS
            if r == 0, regType == 1 /* REG_SZ */ {
                let portName = String(decoding: dataBuffer.prefix(while: { $0 != 0 }), as: UTF16.self)
                if isValidDevice(portName) { ports.append(portName) }
            }
            index += 1
        }
        return ports.sorted()
    }
    #endif
}