import Foundation

/// Un archivo o carpeta de un servidor (SFTP/FTP) o del Mac.
public struct RemoteEntry: Hashable, Sendable, Identifiable {
    public enum Kind: Sendable, Hashable { case file, directory, link, other }

    public var id: String { path }
    public var name: String
    /// Ruta completa (la carpeta + «/» + el nombre).
    public var path: String
    public var kind: Kind
    public var size: Int64?
    /// Modo Unix (0o755…) si el servidor lo dice.
    public var permissions: UInt32?
    public var modified: Date?
    /// Dueño y grupo, si se saben (el «ls -l» del servidor).
    public var owner: String?
    public var group: String?
    /// Enlace que apunta a una carpeta (se entra en él como en una carpeta).
    public var linkToDirectory = false

    public init(name: String, path: String, kind: Kind, size: Int64? = nil, permissions: UInt32? = nil,
                modified: Date? = nil, owner: String? = nil, group: String? = nil) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.permissions = permissions
        self.modified = modified
        self.owner = owner
        self.group = group
    }

    public var isDirectory: Bool { kind == .directory || (kind == .link && linkToDirectory) }

    /// «drwxr-xr-x» (o «—» si no se sabe).
    public var permissionString: String {
        guard let p = permissions else { return "—" }
        let t: Character = switch kind {
        case .directory: "d"
        case .link: "l"
        case .file, .other: "-"
        }
        return String(t) + RemoteEntry.rwx(p)
    }

    public static func rwx(_ p: UInt32) -> String {
        let bits: [(UInt32, Character)] = [(0o400, "r"), (0o200, "w"), (0o100, "x"), (0o40, "r"), (0o20, "w"), (0o10, "x"),
                                           (0o4, "r"), (0o2, "w"), (0o1, "x")]
        return String(bits.map { p & $0.0 != 0 ? $0.1 : "-" })
    }

    /// Carpetas primero y luego por nombre (sin mirar mayúsculas, con números en orden natural).
    public static func sorted(_ list: [RemoteEntry]) -> [RemoteEntry] {
        list.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

/// Rutas remotas (siempre con «/», sean del servidor que sean).
public enum RemotePath {
    public static func join(_ dir: String, _ name: String) -> String {
        if dir.isEmpty { return name }
        return dir.hasSuffix("/") ? dir + name : dir + "/" + name
    }

    public static func parent(_ path: String) -> String {
        let p = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        guard p != "/", let i = p.lastIndex(of: "/") else { return "/" }
        return i == p.startIndex ? "/" : String(p[..<i])
    }

    public static func name(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Las carpetas de la barra de ruta: «/», «/var», «/var/log»…
    public static func breadcrumbs(_ path: String) -> [(name: String, path: String)] {
        var out = [(name: "/", path: "/")]
        var cur = ""
        for part in path.split(separator: "/") {
            cur += "/" + part
            out.append((String(part), cur))
        }
        return out
    }

    /// Un nombre que se puede crear o usar en el servidor (sin «/», ni vacío, ni «.»/«..», ni saltos de línea: en FTP
    /// un salto de línea metería otra orden).
    public static func isValidName(_ n: String) -> Bool {
        !n.isEmpty && n != "." && n != ".." && !n.contains("/") && !n.contains(where: { $0.isNewline || $0 == "\0" })
    }
}

public struct RemoteError: LocalizedError, Equatable, Sendable {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var errorDescription: String? { message }
}

/// Lee un archivo a trozos: nil = se acabó.
public protocol RemoteReader: AnyObject, Sendable {
    func read() async throws -> Data?
    func close() async
}

/// Escribe un archivo a trozos; `finish` lo cierra bien (y espera lo pendiente), `abort` lo deja a medias.
public protocol RemoteWriter: AnyObject, Sendable {
    func write(_ data: Data) async throws
    func finish() async throws
    func abort() async
}

/// Un servidor SFTP/FTP (o el Mac) visto como carpetas y archivos.
public protocol RemoteFileSystem: AnyObject, Sendable {
    /// «SFTP usuario@equipo».
    var label: String { get }
    /// La carpeta en la que empieza (la de inicio del usuario).
    func home() async throws -> String
    func list(_ path: String) async throws -> [RemoteEntry]
    func makeDirectory(_ path: String) async throws
    func remove(_ path: String, directory: Bool) async throws
    func rename(_ from: String, to: String) async throws
    /// Tamaño (para la barra de progreso), si se sabe.
    func size(of path: String) async -> Int64?
    func openRead(_ path: String) async throws -> any RemoteReader
    func openWrite(_ path: String) async throws -> any RemoteWriter
    func close() async
    /// Permisos Unix (0o644…) de un archivo, si el servidor los da (nil: no existe o no se sabe).
    func permissions(of path: String) async -> UInt32?
    /// Qué hay con ese nombre, sin seguir enlaces (nil: no existe o el protocolo no lo dice).
    func kind(of path: String) async -> RemoteEntry.Kind?
    /// Cambia los permisos (si el protocolo no sabe, no hace nada).
    func setPermissions(_ mode: UInt32, of path: String) async throws
}

extension RemoteFileSystem {
    public func permissions(of path: String) async -> UInt32? { nil }
    public func kind(of path: String) async -> RemoteEntry.Kind? { nil }
    public func setPermissions(_ mode: UInt32, of path: String) async throws {}
}
