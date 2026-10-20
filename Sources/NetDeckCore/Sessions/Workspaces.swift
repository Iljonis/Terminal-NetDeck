import Foundation

/// Una pestaña del espacio: las sesiones guardadas se resuelven de nuevo por nombre al abrirlo.
public struct WorkspaceTab: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var route: ConnectionRoute
    public var panel: SFTPPanelLayout?
    public init(id: UUID = UUID(), route: ConnectionRoute, panel: SFTPPanelLayout? = nil) {
        self.id = id; self.route = route; self.panel = panel
    }
}

/// Sólo disposición y conexiones: nunca salida, secretos, MultiExec ni automatismos que se ejecuten al restaurar.
public struct Workspace: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var tabs: [WorkspaceTab]
    public var selected: UUID?
    public var layout: String?
    public var panes: [UUID]
    public var fractions: [String: [Double]]

    public init(id: UUID = UUID(), name: String, tabs: [WorkspaceTab], selected: UUID? = nil,
                layout: String? = nil, panes: [UUID] = [], fractions: [String: [Double]] = [:]) {
        self.id = id; self.name = name; self.tabs = tabs.filter { !$0.route.isLoopback }
        let ids = Set(self.tabs.map(\.id))
        self.selected = selected.flatMap { ids.contains($0) ? $0 : nil }
        self.layout = layout; self.panes = panes.filter { ids.contains($0) }; self.fractions = fractions
    }

    public static let layouts: Set<String> = ["side2", "stack2", "cols3", "onePlusTwo", "grid4", "grid"]
    public var problem: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 120 {
            return L("El espacio necesita un nombre de 1 a 120 caracteres")
        }
        if tabs.isEmpty || tabs.count > 64 { return L("Un espacio necesita entre 1 y 64 pestañas") }
        let ids = Set(tabs.map(\.id))
        if ids.count != tabs.count || Set(panes).count != panes.count || !Set(panes).isSubset(of: ids)
            || selected.map({ !ids.contains($0) }) == true {
            return L("Las referencias de las pestañas del espacio no son válidas")
        }
        if layout.map({ !Self.layouts.contains($0) }) == true || fractions.count > 32
            || fractions.values.contains(where: { $0.isEmpty || $0.count > 16 || $0.contains { !$0.isFinite || $0 <= 0 || $0 > 1 } }) {
            return L("La distribución del espacio no es válida")
        }
        for t in tabs {
            let r = t.route
            if r.isLoopback { return L("No se guardan conexiones de loopback en los espacios") }
            if r.title.count > 300 || r.thenCommand != nil || r.manualHop == true {
                return L("No se guardan saltos escritos a mano en los espacios")
            }
            if !r.isLocal && r.transport != .serial {
                guard r.target.isShellSafe, r.jumps.allSatisfy(\.isShellSafe),
                      r.alias.map({ !$0.hasPrefix("-") && !$0.contains("\n") && !$0.contains("\0") }) ?? true else {
                    return L("El espacio contiene una conexión no válida")
                }
            }
            if r.transport == .serial, r.serial?.isValid != true { return L("El espacio contiene una conexión no válida") }
        }
        return nil
    }

    /// Pesos válidos para los divisores; se normalizan también al cambiar el tamaño de la ventana.
    public static func weights(_ saved: [Double]?, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard let saved, saved.count == count, saved.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return Array(repeating: 1 / Double(count), count: count)
        }
        let sum = saved.reduce(0, +)
        return saved.map { $0 / sum }
    }
}

public struct WorkspaceLibrary: Codable, Equatable, Sendable {
    public var version = 1
    public var workspaces: [Workspace] = []
    public init(workspaces: [Workspace] = []) { self.workspaces = workspaces }
    public static var defaultURL: URL { AppPaths.support.appendingPathComponent("espacios.json") }
    /// El mismo tope al leer y al guardar: nunca se escribe un archivo que luego no se pueda abrir.
    public static let maxBytes = 5_000_000
    public var problem: String? {
        if version != 1 { return L("Formato de espacios de otra versión: se conserva el archivo") }
        if workspaces.count > 100 { return L("Se permiten hasta 100 espacios") }
        if Set(workspaces.map(\.id)).count != workspaces.count
            || Set(workspaces.map { $0.name.lowercased() }).count != workspaces.count {
            return L("Los nombres y los identificadores de los espacios deben ser únicos")
        }
        return workspaces.compactMap(\.problem).first
    }
    public static func load(from url: URL = defaultURL) throws -> Self {
        guard let text = try SafeFile.read(url) else { return Self() }
        guard text.utf8.count <= maxBytes else { throw WorkspaceError(L("El archivo de espacios es demasiado grande")) }
        let lib = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
        if let p = lib.problem { throw WorkspaceError(p) }
        return lib
    }
    public func save(to url: URL = Self.defaultURL) throws {
        if let p = problem { throw WorkspaceError(p) }
        // (uno roto o de otra versión no se sustituye por una lista vacía)
        _ = try Self.load(from: url)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let text = String(decoding: try encoder.encode(self), as: UTF8.self)
        guard text.utf8.count <= Self.maxBytes else {
            throw WorkspaceError(L("Los espacios ocuparían más de 5 MB: quita alguno o algunas pestañas (no se ha guardado)"))
        }
        AppPaths.ensure(url.deletingLastPathComponent())
        try SafeFile.backup(url)
        try SafeFile.write(text, to: url)
    }
}
public struct WorkspaceError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

extension Workspace {
    /// Se prepara todo antes de abrir o cerrar una pestaña. Una sesión borrada se avisa y se omite.
    @MainActor public func resolve(using manager: SessionManager) throws -> (tabs: [WorkspaceTab], missing: [String]) {
        if let p = problem { throw WorkspaceError(p) }
        var out: [WorkspaceTab] = [], missing: [String] = []
        for var tab in tabs {
            if let name = tab.route.sessionName {
                guard let p = manager.profile(named: name) else { missing.append(name); continue }
                tab.route = try manager.route(to: p)
            } else if tab.route.isLocal {
                // (no se vuelve a ejecutar una ruta de shell arbitraria de un JSON modificado)
                tab.route = .local(shell: tab.route.localShell)
            }
            if !tab.route.isLoopback { out.append(tab) }
        }
        return (out, missing)
    }
}
