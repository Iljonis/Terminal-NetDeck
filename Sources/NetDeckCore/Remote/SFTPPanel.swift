import Foundation

/// El explorador SFTP al lado del terminal ssh de una pestaña: la misma ruta que el terminal (alias del ssh_config,
/// usuario, equipo, puerto, saltos «-J» o los del ProxyJump del alias, y la sesión, para la contraseña con nombre),
/// sólo que con el subsistema «sftp». La «-F» y la conexión compartida al último salto se añaden al conectar, como en
/// la pestaña (`sftpSubsystemCommand(sharing:configFile:)`): así se reutiliza el ControlMaster del salto si existe.
public enum SFTPPanel {
    /// ¿Tiene sentido el panel en esta pestaña? Sólo en las ssh (ni telnet, ni la local, ni serie, ni sftp/ftp, que ya
    /// son el explorador).
    public static func offers(_ terminal: ConnectionRoute) -> Bool {
        !terminal.isLocal && terminal.transport == .ssh
    }

    /// La ruta del explorador a partir de la del terminal. Error si el terminal no es ssh o llega por un salto «a
    /// mano» (el salto no deja reenviar: el explorador acabaría en el salto y no en el equipo).
    public static func route(for terminal: ConnectionRoute) throws -> ConnectionRoute {
        guard offers(terminal) else { throw RemoteError(L("El explorador lateral sólo está en las pestañas ssh")) }
        if terminal.thenCommand != nil || terminal.manualHop == true {
            throw RemoteError(L("El salto no deja reenviar (-J): el explorador lateral no puede llegar a «\(terminal.target.host)»"))
        }
        var r = terminal                    // (todo igual: alias, saltos, configJumps, usuario, puerto y sesión)
        r.transport = .sftp
        return r
    }

    /// Con qué se recuerda el panel de una pestaña: la sesión si viene de una; si no, usuario@equipo:puerto.
    public static func key(for terminal: ConnectionRoute) -> String {
        if let s = terminal.sessionName, !s.isEmpty { return "sesion:" + s }
        if let a = terminal.alias, !a.isEmpty { return "alias:" + a }
        let t = terminal.target
        return "equipo:\(t.user ?? "")@\(t.host):\(t.port ?? 22)"
    }
}

/// Visible y ancho del panel de una sesión.
public struct SFTPPanelLayout: Codable, Equatable, Sendable {
    public var visible: Bool
    public var width: Double

    public static let minWidth = 340.0
    public static let maxWidth = 900.0
    public static let defaultWidth = 440.0
    /// Lo mínimo que se le deja al terminal al lado.
    public static let minTerminal = 360.0

    public init(visible: Bool = false, width: Double = SFTPPanelLayout.defaultWidth) {
        self.visible = visible
        self.width = Self.clamp(width)
    }

    private enum CodingKeys: String, CodingKey { case visible = "visible", width = "ancho" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visible = (try? c.decode(Bool.self, forKey: .visible)) ?? false
        width = Self.clamp((try? c.decode(Double.self, forKey: .width)) ?? Self.defaultWidth)
    }

    /// Entre el mínimo y el máximo; con `available` (el ancho de la pestaña), dejando sitio al terminal.
    public static func clamp(_ w: Double, available: Double? = nil) -> Double {
        var top = maxWidth
        if let available { top = min(top, max(minWidth, available - minTerminal)) }
        guard w.isFinite else { return defaultWidth }
        return min(max(w, minWidth), top)
    }
}

/// Lo recordado de los paneles (un JSON pequeño con versión en la carpeta de la app, 0600; nunca en el ssh_config).
/// Si el archivo está roto, se empieza con lo de por defecto (y se guarda copia antes de sustituirlo); si es de una
/// versión que no se conoce o no se puede leer, también, pero no se sobrescribe.
public struct SFTPPanelStore: Sendable {
    public static let version = 1
    /// Como mucho tantas sesiones recordadas (las conexiones rápidas no lo hacen crecer sin fin).
    public static let maxEntries = 400

    public let url: URL
    public private(set) var layouts: [String: SFTPPanelLayout] = [:]
    /// false: es de otra versión o no se puede leer: se usa lo de por defecto sin tocar el archivo.
    public private(set) var writable = true
    private var corrupt = false

    private struct Archivo: Codable {
        var version: Int
        var paneles: [String: SFTPPanelLayout]
    }

    public static var standard: URL { AppPaths.support.appendingPathComponent("panel-sftp.json") }

    public init(url: URL = SFTPPanelStore.standard) {
        self.url = url
        let text: String?
        do { text = try SafeFile.read(url) } catch {
            writable = false
            ErrorLog.warning("panel-sftp", "no se puede leer \(url.lastPathComponent): no se sobrescribe")
            return
        }
        guard let text else { return }
        struct Version: Decodable { var version: Int? }
        guard let v = try? JSONDecoder().decode(Version.self, from: Data(text.utf8)) else {
            corrupt = true
            ErrorLog.warning("panel-sftp", "\(url.lastPathComponent) roto: valores por defecto")
            return
        }
        guard v.version == Self.version else {
            writable = false
            ErrorLog.warning("panel-sftp", "\(url.lastPathComponent) de la versión \(v.version.map(String.init) ?? "?"): no se sobrescribe")
            return
        }
        if let a = try? JSONDecoder().decode(Archivo.self, from: Data(text.utf8)) { layouts = a.paneles } else { corrupt = true }
    }

    public func layout(for key: String) -> SFTPPanelLayout { layouts[key] ?? SFTPPanelLayout() }

    /// Guarda el de una sesión (si no ha cambiado, no escribe nada).
    public mutating func set(_ layout: SFTPPanelLayout, for key: String) throws {
        guard layouts[key] != layout else { return }
        layouts[key] = layout
        if layouts.count > Self.maxEntries {                // (fuera primero los ocultos)
            for k in layouts.keys.sorted() where layouts.count > Self.maxEntries && k != key && layouts[k]?.visible == false {
                layouts[k] = nil
            }
        }
        guard writable else { return }
        AppPaths.ensure(url.deletingLastPathComponent())
        if corrupt {                                        // (el roto, apartado en .anterior/.original antes de sustituirlo)
            try SafeFile.backup(url)
            corrupt = false
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(Archivo(version: Self.version, paneles: layouts))
        try SafeFile.write(String(decoding: data, as: UTF8.self), to: url)
    }
}
