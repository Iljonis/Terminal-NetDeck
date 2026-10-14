import Foundation
import Network

/// Conexión TCP con lectura y escritura asíncronas (Network.framework).
final class TCPStream: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "netdeck.ftp")

    init(host: String, port: UInt16) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 21, using: .tcp)
    }

    /// Espera a que conecte (15 s como mucho).
    func start() async throws {
        do { try await connect() } catch {
            connection.cancel()                     // (si no, Network sigue reintentando por su cuenta)
            throw error
        }
    }

    private func connect() async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.take() { c.resume() }
                case .failed(let e), .waiting(let e): if once.take() { c.resume(throwing: RemoteError(e.localizedDescription)) }
                case .cancelled: if once.take() { c.resume(throwing: RemoteError(L("Conexión cerrada"))) }
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 15) {
                if once.take() { c.resume(throwing: RemoteError(L("No contesta (15 s)"))) }
            }
        }
    }

    func send(_ d: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: d, completion: .contentProcessed { e in
                if let e { c.resume(throwing: RemoteError(e.localizedDescription)) } else { c.resume() }
            })
        }
    }

    /// Lo siguiente que llegue; nil = el otro lado ha cerrado.
    func receive() async throws -> Data? {
        try await withCheckedThrowingContinuation { c in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, complete, e in
                if let data, !data.isEmpty { c.resume(returning: data) } else if let e, !complete {
                    c.resume(throwing: RemoteError(e.localizedDescription))
                } else { c.resume(returning: nil) }
            }
        }
    }

    /// Cierra la escritura (fin del archivo en STOR) y espera a que se haya enviado.
    func finishSending() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { e in
                if let e { c.resume(throwing: RemoteError(e.localizedDescription)) } else { c.resume() }
            })
        }
    }

    func cancel() { connection.cancel() }
}

/// Sólo la primera vez (para no reanudar dos veces una continuación).
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool { lock.withLock { defer { done = true }; return !done } }
}

/// Lo que se interpreta del FTP (sin red: se prueba en los tests).
public enum FTPParse {
    /// «229 Entering Extended Passive Mode (|||6446|)» → 6446.
    public static func epsvPort(_ text: String) -> UInt16? {
        guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else { return nil }
        let inner = text[text.index(after: open)..<close]
        guard let d = inner.first else { return nil }
        let parts = inner.split(separator: d, omittingEmptySubsequences: false)
        return parts.count >= 4 ? UInt16(parts[3]) : nil
    }

    /// «227 Entering Passive Mode (192,0,2,7,19,77)» → 19·256+77. La IP no se usa: se va al mismo equipo que el
    /// control (que un servidor no mande la conexión de datos a otra máquina).
    public static func pasvPort(_ text: String) -> UInt16? {
        let nums = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard nums.count >= 6 else { return nil }
        let p1 = nums[nums.count - 2], p2 = nums[nums.count - 1]
        guard (0...255).contains(p1), (0...255).contains(p2) else { return nil }
        return UInt16(p1 * 256 + p2)
    }

    /// «257 "/home/tu.usuario" is the current directory» → /home/tu.usuario (las «""» son una comilla).
    public static func quotedPath(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "\"") else { return nil }
        var out = ""
        var i = text.index(after: start)
        while i < text.endIndex {
            if text[i] == "\"" {
                let n = text.index(after: i)
                if n < text.endIndex, text[n] == "\"" { out.append("\""); i = text.index(after: n); continue }
                return out
            }
            out.append(text[i])
            i = text.index(after: i)
        }
        return nil
    }

    /// Una línea de MLSD: «type=dir;modify=20240101120000;UNIX.mode=0755; nombre».
    public static func mlsd(_ line: String, in dir: String) -> RemoteEntry? {
        guard let sp = line.firstIndex(of: " ") else { return nil }
        let name = String(line[line.index(after: sp)...])
        guard RemotePath.isValidName(name) else { return nil }
        var facts: [String: String] = [:]
        for f in line[..<sp].split(separator: ";") {
            let (k, _, v) = String(f).partition("=")
            facts[k.lowercased()] = v
        }
        let type = facts["type"]?.lowercased() ?? "file"
        guard type != "cdir", type != "pdir" else { return nil }
        let kind: RemoteEntry.Kind = type == "dir" ? .directory : type.hasPrefix("os.unix=symlink") || type == "os.unix=slink" ? .link : .file
        var e = RemoteEntry(name: name, path: RemotePath.join(dir, name), kind: kind,
                            size: facts["size"].flatMap { Int64($0) },
                            permissions: facts["unix.mode"].flatMap { UInt32($0, radix: 8) },
                            modified: facts["modify"].flatMap(Self.mlsdDate))
        e.owner = facts["unix.owner"] ?? facts["unix.ownername"]
        e.group = facts["unix.group"] ?? facts["unix.groupname"]
        return e
    }

    static func mlsdDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMddHHmmss"
        return f.date(from: String(s.prefix(14)))
    }

    /// Una línea de LIST: la de Unix («drwxr-xr-x 2 tu.usuario staff 4096 Jan 1 12:00 nombre») o la de Windows/IIS
    /// («01-31-24  09:15AM  <DIR>  nombre»).
    public static func list(_ line: String, in dir: String, now: Date = Date()) -> RemoteEntry? {
        let f = line.split(separator: " ", omittingEmptySubsequences: true)
        if let first = f.first, first.count == 10, "dl-cbps".contains(first.first!) {
            guard f.count >= 9 else { return nil }
            // (el nombre: lo que queda tras la hora/año; puede llevar espacios)
            var rest = Substring(line)
            for _ in 0..<8 {
                rest = rest.drop(while: { $0 == " " })
                rest = rest.drop(while: { $0 != " " })
            }
            var name = String(rest.drop(while: { $0 == " " }))
            let kind: RemoteEntry.Kind = first.first == "d" ? .directory : first.first == "l" ? .link : first.first == "-" ? .file : .other
            if kind == .link, let r = name.range(of: " -> ") { name = String(name[..<r.lowerBound]) }
            guard RemotePath.isValidName(name) else { return nil }
            var e = RemoteEntry(name: name, path: RemotePath.join(dir, name), kind: kind, size: Int64(f[4]),
                                permissions: unixMode(String(first.dropFirst())),
                                modified: unixDate(month: String(f[5]), day: String(f[6]), timeOrYear: String(f[7]), now: now))
            e.owner = String(f[2])
            e.group = String(f[3])
            return e
        }
        // Windows: fecha hora <DIR>|tamaño nombre
        guard f.count >= 4, f[0].contains("-"), f[1].contains(":") else { return nil }
        var rest = Substring(line)
        for _ in 0..<3 {
            rest = rest.drop(while: { $0 == " " })
            rest = rest.drop(while: { $0 != " " })
        }
        let name = String(rest.drop(while: { $0 == " " }))
        guard RemotePath.isValidName(name) else { return nil }
        let isDir = f[2].uppercased() == "<DIR>"
        return RemoteEntry(name: name, path: RemotePath.join(dir, name), kind: isDir ? .directory : .file,
                           size: isDir ? nil : Int64(f[2]))
    }

    static func unixMode(_ s: String) -> UInt32? {
        guard s.count == 9 else { return nil }
        var m: UInt32 = 0
        for (i, c) in s.enumerated() {
            let bit = UInt32(1) << UInt32(8 - i)
            if c != "-" { m |= bit }
        }
        return m
    }

    static func unixDate(month: String, day: String, timeOrYear: String, now: Date) -> Date? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let mi = months.firstIndex(of: month.lowercased().prefix(3).description), let d = Int(day) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents(month: mi + 1, day: d)
        if timeOrYear.contains(":") {
            let hm = timeOrYear.split(separator: ":").compactMap { Int($0) }
            guard hm.count == 2 else { return nil }
            c.hour = hm[0]
            c.minute = hm[1]
            c.year = cal.component(.year, from: now)
            if let dt = cal.date(from: c), dt > now.addingTimeInterval(86400) { c.year! -= 1 }    // (sin año: los últimos 12 meses)
        } else {
            guard let y = Int(timeOrYear) else { return nil }
            c.year = y
        }
        return cal.date(from: c)
    }
}

/// Una conexión de control FTP con su sesión iniciada. Una orden cada vez (las demás esperan su turno).
actor FTPConnection {
    let host: String
    let port: UInt16
    private let control: TCPStream
    private var buffer = Data()
    private var busy = false
    private var turn: [CheckedContinuation<Void, Never>] = []
    private(set) var features: Set<String> = []

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
        control = TCPStream(host: host, port: port)
    }

    /// Conecta e inicia sesión. 530 = usuario o contraseña no válidos (`FTPLoginError`).
    func login(user: String, password: String) async throws {
        try await control.start()
        var r = try await reply()
        guard r.code == 220 else { throw RemoteError(L("FTP: \(r.text)")) }
        r = try await command("USER \(user)")
        if r.code == 331 || r.code == 332 { r = try await command("PASS \(password)", secret: true) }
        if r.code == 530 { throw FTPLoginError() }
        guard r.code == 230 || r.code == 202 else { throw RemoteError(L("FTP: \(r.text)")) }
        let feat = try await command("FEAT")
        if feat.code == 211 {
            features = Set(feat.text.components(separatedBy: "\n").dropFirst().map {
                $0.trimmingCharacters(in: .whitespaces).uppercased().split(separator: " ").first.map(String.init) ?? ""
            })
        }
        if features.contains("UTF8") { _ = try await command("OPTS UTF8 ON") }
        _ = try await command("TYPE I")
    }

    /// Para usar la conexión sin que se cruce otra orden en medio.
    func exclusive<T: Sendable>(_ body: @Sendable (FTPConnection) async throws -> T) async throws -> T {
        while busy { await withCheckedContinuation { turn.append($0) } }
        busy = true
        defer {
            busy = false
            if !turn.isEmpty { turn.removeFirst().resume() }
        }
        return try await body(self)
    }

    private func readLine() async throws -> String {
        while true {
            if let nl = buffer.firstIndex(of: 10) {
                var line = buffer[buffer.startIndex..<nl]
                if line.last == 13 { line = line.dropLast() }
                buffer = Data(buffer[(nl + 1)...])
                return String(decoding: line, as: UTF8.self)
            }
            guard let d = try await control.receive() else { throw RemoteError(L("FTP: el servidor ha cerrado la conexión")) }
            buffer.append(d)
            if buffer.count > 1_000_000 { throw RemoteError(L("FTP: respuesta demasiado larga")) }
        }
    }

    /// Una respuesta (las de varias líneas «211-…» hasta «211 …»).
    func reply() async throws -> (code: Int, text: String) {
        let first = try await readLine()
        guard first.count >= 3, let code = Int(first.prefix(3)) else { throw RemoteError(L("FTP: respuesta no válida")) }
        var lines = [String(first.dropFirst(4))]
        if first.dropFirst(3).first == "-" {
            while true {
                let l = try await readLine()
                if l.hasPrefix("\(code) ") || l == "\(code)" { lines.append(String(l.dropFirst(4))); break }
                lines.append(l)
            }
        }
        return (code, lines.joined(separator: "\n"))
    }

    func command(_ cmd: String, secret: Bool = false) async throws -> (code: Int, text: String) {
        guard !cmd.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\0" }) else {
            throw RemoteError(L("Nombre no válido"))
        }
        try await control.send(Data((cmd + "\r\n").utf8))
        return try await reply()
    }

    /// Abre la conexión de datos (EPSV y, si no, PASV), siempre al mismo equipo del control.
    func openData() async throws -> TCPStream {
        var port: UInt16?
        let e = try await command("EPSV")
        if e.code == 229 { port = FTPParse.epsvPort(e.text) }
        if port == nil {
            let p = try await command("PASV")
            guard p.code == 227 else { throw RemoteError(L("FTP: \(p.text)")) }
            port = FTPParse.pasvPort(p.text)
        }
        guard let port else { throw RemoteError(L("FTP: modo pasivo no válido")) }
        let s = TCPStream(host: host, port: port)
        try await s.start()                         // (start ya cancela la conexión si falla)
        return s
    }

    /// Orden que abre una transferencia (RETR, STOR, LIST, MLSD): 125/150 o error.
    func begin(_ cmd: String) async throws -> TCPStream {
        let data = try await openData()
        let r = try await command(cmd)
        guard r.code == 125 || r.code == 150 else {
            data.cancel()
            throw RemoteError(L("FTP: \(r.text)"))
        }
        return data
    }

    /// Tras cerrar la conexión de datos: 226/250 = bien.
    func end() async throws {
        let r = try await reply()
        guard r.code == 226 || r.code == 250 else { throw RemoteError(L("FTP: \(r.text)")) }
    }

    func quit() async {
        _ = try? await control.send(Data("QUIT\r\n".utf8))
        control.cancel()
    }
}

public struct FTPLoginError: LocalizedError, Equatable {
    public init() {}
    public var errorDescription: String? { L("FTP: usuario o contraseña no válidos") }
}

/// Un servidor FTP (sin cifrar: el usuario y la contraseña viajan tal cual). Para listar y lo pequeño, una conexión;
/// cada transferencia abre la suya (así se puede seguir navegando mientras se copia).
public final class FTPFileSystem: RemoteFileSystem, @unchecked Sendable {
    public let label: String
    private let host: String
    private let port: UInt16
    private let user: String
    private let password: String
    private let main: FTPConnection
    /// La contraseña ya no vale (530 en una transferencia): avisa una vez (bloqueo de 15 min) y no se vuelve a probar.
    private let rejected: @Sendable () -> Void
    private let lock = NSLock()
    private var refused = false

    private init(label: String, host: String, port: UInt16, user: String, password: String, main: FTPConnection,
                 rejected: @escaping @Sendable () -> Void) {
        self.rejected = rejected
        self.label = label
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.main = main
    }

    public static func connect(label: String, host: String, port: Int?, user: String, password: String,
                               rejected: @escaping @Sendable () -> Void = {}) async throws -> FTPFileSystem {
        let p = UInt16(clamping: port ?? 21)
        let c = FTPConnection(host: host, port: p)
        do { try await c.login(user: user, password: password) } catch { await c.quit(); throw error }
        return FTPFileSystem(label: label, host: host, port: p, user: user, password: password, main: c, rejected: rejected)
    }

    private func fresh() async throws -> FTPConnection {
        if lock.withLock({ refused }) { throw FTPLoginError() }
        let c = FTPConnection(host: host, port: port)
        do { try await c.login(user: user, password: password) } catch {
            await c.quit()
            if error is FTPLoginError, lock.withLock({ defer { refused = true }; return !refused }) { rejected() }
            throw error
        }
        return c
    }

    public func home() async throws -> String {
        try await main.exclusive { c in
            let r = try await c.command("PWD")
            return r.code == 257 ? FTPParse.quotedPath(r.text) ?? "/" : "/"
        }
    }

    public func list(_ path: String) async throws -> [RemoteEntry] {
        try await main.exclusive { c in
            let cwd = try await c.command("CWD \(path)")
            guard cwd.code == 250 else { throw RemoteError(L("FTP: \(cwd.text)")) }
            let features = await c.features
            let mlsd = features.contains("MLSD") || features.contains("MLST")
            let data = try await c.begin(mlsd ? "MLSD" : "LIST")
            var raw = Data()
            do {
                while let d = try await data.receive() {
                    raw.append(d)
                    if raw.count > 50_000_000 { throw RemoteError(L("FTP: listado demasiado grande")) }
                }
            } catch { data.cancel(); throw error }
            data.cancel()
            try await c.end()
            let lines = String(decoding: raw, as: UTF8.self).components(separatedBy: "\n")
                .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }.filter { !$0.isEmpty }
            let entries = lines.compactMap { mlsd ? FTPParse.mlsd($0, in: path) : FTPParse.list($0, in: path) }
            return RemoteEntry.sorted(entries)
        }
    }

    private func simple(_ cmd: String, ok: Set<Int>) async throws {
        try await main.exclusive { c in
            let r = try await c.command(cmd)
            guard ok.contains(r.code) else { throw RemoteError(L("FTP: \(r.text)")) }
        }
    }

    public func makeDirectory(_ path: String) async throws { try await simple("MKD \(path)", ok: [257, 250]) }

    public func remove(_ path: String, directory: Bool) async throws {
        try await simple(directory ? "RMD \(path)" : "DELE \(path)", ok: [250, 200])
    }

    public func rename(_ from: String, to: String) async throws {
        try await main.exclusive { c in
            let a = try await c.command("RNFR \(from)")
            guard a.code == 350 else { throw RemoteError(L("FTP: \(a.text)")) }
            let b = try await c.command("RNTO \(to)")
            guard b.code == 250 else { throw RemoteError(L("FTP: \(b.text)")) }
        }
    }

    public func size(of path: String) async -> Int64? {
        try? await main.exclusive { c in
            let r = try await c.command("SIZE \(path)")
            return r.code == 213 ? Int64(r.text.trimmingCharacters(in: .whitespaces)) : nil
        }
    }

    public func openRead(_ path: String) async throws -> any RemoteReader {
        let c = try await fresh()
        do {
            return FTPFileReader(connection: c, data: try await c.begin("RETR \(path)"))
        } catch { await c.quit(); throw error }
    }

    public func openWrite(_ path: String) async throws -> any RemoteWriter {
        let c = try await fresh()
        do {
            return FTPFileWriter(connection: c, data: try await c.begin("STOR \(path)"))
        } catch { await c.quit(); throw error }
    }

    public func close() async { await main.quit() }
}

actor FTPFileReader: RemoteReader {
    private let connection: FTPConnection
    private let data: TCPStream
    private var done = false

    init(connection: FTPConnection, data: TCPStream) {
        self.connection = connection
        self.data = data
    }

    func read() async throws -> Data? {
        guard !done else { return nil }
        if let d = try await data.receive() { return d }
        done = true
        data.cancel()
        try await connection.end()
        return nil
    }

    func close() async {
        data.cancel()
        await connection.quit()
    }
}

actor FTPFileWriter: RemoteWriter {
    private let connection: FTPConnection
    private let data: TCPStream
    private var closed = false

    init(connection: FTPConnection, data: TCPStream) {
        self.connection = connection
        self.data = data
    }

    func write(_ d: Data) async throws { try await data.send(d) }

    func finish() async throws {
        closed = true
        defer { Task { await connection.quit() } }
        try await data.finishSending()
        data.cancel()
        try await connection.end()
    }

    func abort() async {
        guard !closed else { return }
        closed = true
        data.cancel()
        await connection.quit()
    }
}
