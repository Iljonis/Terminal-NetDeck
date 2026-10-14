import Foundation

/// SFTP versión 3 (draft-ietf-secsh-filexfer-02, la que habla OpenSSH): tipos de paquete y cómo se escriben y leen.
public enum SFTP {
    public enum Kind: UInt8, Sendable {
        case initialize = 1, version = 2, open = 3, close = 4, read = 5, write = 6, lstat = 7, fstat = 8, setstat = 9,
             fsetstat = 10, opendir = 11, readdir = 12, remove = 13, mkdir = 14, rmdir = 15, realpath = 16, stat = 17,
             rename = 18, readlink = 19, symlink = 20
        case status = 101, handle = 102, data = 103, name = 104, attrs = 105
    }

    public enum Status: UInt32, Sendable {
        case ok = 0, eof = 1, noSuchFile = 2, permissionDenied = 3, failure = 4, badMessage = 5, noConnection = 6,
             connectionLost = 7, unsupported = 8
    }

    public struct OpenFlags: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let read = OpenFlags(rawValue: 0x01)
        public static let write = OpenFlags(rawValue: 0x02)
        public static let append = OpenFlags(rawValue: 0x04)
        public static let create = OpenFlags(rawValue: 0x08)
        public static let truncate = OpenFlags(rawValue: 0x10)
        public static let exclusive = OpenFlags(rawValue: 0x20)
    }

    /// Atributos de un archivo (los que manda cada servidor: todo es opcional).
    public struct Attributes: Equatable, Sendable {
        public var size: UInt64?
        public var uid: UInt32?, gid: UInt32?
        public var permissions: UInt32?
        public var atime: UInt32?, mtime: UInt32?

        public init(size: UInt64? = nil, permissions: UInt32? = nil, mtime: UInt32? = nil) {
            self.size = size
            self.permissions = permissions
            self.mtime = mtime
            atime = mtime
        }

        static let sizeFlag: UInt32 = 0x1, uidgidFlag: UInt32 = 0x2, permissionsFlag: UInt32 = 0x4,
                   timesFlag: UInt32 = 0x8, extendedFlag: UInt32 = 0x8000_0000

        /// Tipo según los bits S_IFMT del modo.
        public var kind: RemoteEntry.Kind {
            guard let p = permissions else { return .file }
            switch p & 0o170000 {
            case 0o040000: return .directory
            case 0o120000: return .link
            case 0o100000: return .file
            default: return .other
            }
        }
    }

    /// Una entrada de SSH_FXP_NAME.
    public struct Name: Equatable, Sendable {
        public var filename: String
        public var longname: String
        public var attributes: Attributes
    }

    // MARK: escribir

    public struct Writer {
        public private(set) var data = Data()
        public init() {}

        public mutating func byte(_ b: UInt8) { data.append(b) }
        public mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
        public mutating func u64(_ v: UInt64) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
        public mutating func bytes(_ d: Data) { u32(UInt32(d.count)); data.append(d) }
        public mutating func string(_ s: String) { bytes(Data(s.utf8)) }

        public mutating func attributes(_ a: Attributes) {
            var flags: UInt32 = 0
            if a.size != nil { flags |= Attributes.sizeFlag }
            if a.permissions != nil { flags |= Attributes.permissionsFlag }
            if a.mtime != nil { flags |= Attributes.timesFlag }
            u32(flags)
            if let s = a.size { u64(s) }
            if let p = a.permissions { u32(p) }
            if let m = a.mtime { u32(a.atime ?? m); u32(m) }
        }
    }

    /// Paquete completo: longitud, tipo, id (salvo INIT) y el resto.
    public static func packet(_ kind: Kind, id: UInt32?, _ body: (inout Writer) -> Void = { _ in }) -> Data {
        var w = Writer()
        w.byte(kind.rawValue)
        if let id { w.u32(id) }
        body(&w)
        var out = Writer()
        out.u32(UInt32(w.data.count))
        return out.data + w.data
    }

    // MARK: leer

    public struct Reader {
        let data: Data
        var at: Int

        public init(_ data: Data) {
            self.data = data
            at = data.startIndex
        }

        public var remaining: Int { data.endIndex - at }

        public mutating func byte() throws -> UInt8 {
            guard remaining >= 1 else { throw RemoteError(L("SFTP: paquete cortado")) }
            defer { at += 1 }
            return data[at]
        }

        public mutating func u32() throws -> UInt32 {
            guard remaining >= 4 else { throw RemoteError(L("SFTP: paquete cortado")) }
            defer { at += 4 }
            return data[at..<at + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }

        public mutating func u64() throws -> UInt64 {
            UInt64(try u32()) << 32 | UInt64(try u32())
        }

        public mutating func bytes() throws -> Data {
            let n = Int(try u32())
            guard n <= remaining else { throw RemoteError(L("SFTP: paquete cortado")) }
            defer { at += n }
            return data[at..<at + n]
        }

        public mutating func string() throws -> String { String(decoding: try bytes(), as: UTF8.self) }

        public mutating func attributes() throws -> Attributes {
            let flags = try u32()
            var a = Attributes()
            if flags & Attributes.sizeFlag != 0 { a.size = try u64() }
            if flags & Attributes.uidgidFlag != 0 { a.uid = try u32(); a.gid = try u32() }
            if flags & Attributes.permissionsFlag != 0 { a.permissions = try u32() }
            if flags & Attributes.timesFlag != 0 { a.atime = try u32(); a.mtime = try u32() }
            if flags & Attributes.extendedFlag != 0 {
                for _ in 0..<(try u32()) { _ = try bytes(); _ = try bytes() }
            }
            return a
        }

        public mutating func names() throws -> [Name] {
            let n = try u32()
            var out: [Name] = []
            for _ in 0..<n {
                out.append(Name(filename: try string(), longname: try string(), attributes: try attributes()))
            }
            return out
        }
    }

    /// Saca los paquetes completos del principio de `buffer` (lo que sobra se queda para la próxima vez).
    public static func split(_ buffer: inout Data) throws -> [(kind: UInt8, body: Data)] {
        var out: [(UInt8, Data)] = []
        var s = buffer.startIndex
        while buffer.endIndex - s >= 4 {
            let len = Int(buffer[s..<s + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            guard len >= 1, len <= 4 * 1024 * 1024 else { throw RemoteError(L("SFTP: el servidor no habla SFTP")) }
            guard buffer.endIndex - s >= 4 + len else { break }
            out.append((buffer[s + 4], Data(buffer[s + 5..<s + 4 + len])))
            s += 4 + len
        }
        if s != buffer.startIndex { buffer = Data(buffer[s...]) }
        return out
    }

    /// Dueño y grupo del «ls -l» que manda el servidor (longname): «-rw-r--r--  1 tu.usuario staff 12 …».
    public static func owner(fromLongname l: String) -> (owner: String, group: String)? {
        let f = l.split(separator: " ", omittingEmptySubsequences: true)
        guard f.count >= 8, f[0].count >= 10 else { return nil }
        return (String(f[2]), String(f[3]))
    }

    public static func message(for status: UInt32, _ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch Status(rawValue: status) {
        case .noSuchFile: return L("No existe")
        case .permissionDenied: return L("Permiso denegado")
        case .eof: return L("Fin del archivo")
        case .unsupported: return L("El servidor no lo admite")
        case .noConnection, .connectionLost: return L("Se ha perdido la conexión")
        default: return t.isEmpty ? L("Error del servidor (\(status))") : t
        }
    }
}
