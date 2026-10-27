import Foundation
import Network

/// Conexión TCP con lectura y escritura asíncronas (Network.framework). Cancelar la tarea que espera cierra la
/// conexión al momento (y la espera termina con error): así «Cancelar» no se queda colgado en un servidor mudo.
final class TCPStream: @unchecked Sendable {
    /// Lo más que se espera a que acepte la conexión (como el Finder: si no contesta, se avisa enseguida).
    static let connectTimeout: TimeInterval = 10

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "netdeck.ftp")
    private let host: String
    private let port: UInt16
    /// El otro lado ya ha cerrado (el último trozo llegó «completo»): lo siguiente es el final, sin volver a leer.
    private let ended = Once()

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = Int(Self.connectTimeout)
        tcp.noDelay = true                          // (las órdenes de control son cortas: sin esperar a juntar)
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 21,
                                  using: NWParameters(tls: nil, tcp: tcp))
    }

    /// Espera a que conecte (`connectTimeout` como mucho).
    func start() async throws {
        do { try await cancellable { try await self.connect() } } catch {
            connection.cancel()                     // (si no, Network sigue reintentando por su cuenta)
            throw error
        }
    }

    private func connect() async throws {
        let once = Once()
        let host = host, port = port
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.take() { c.resume() }
                case .failed(let e), .waiting(let e): if once.take() { c.resume(throwing: Self.explain(e, host: host, port: port)) }
                case .cancelled: if once.take() { c.resume(throwing: RemoteError(L("Conexión cerrada"))) }
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + Self.connectTimeout) {
                if once.take() {
                    c.resume(throwing: RemoteError(L("\(host):\(String(port)) no contesta en \(Int(Self.connectTimeout)) s (¿cortafuegos, VPN o puerto equivocado?)")))
                }
            }
        }
    }

    /// Un error de red en palabras: rechazada (nadie escucha en ese puerto), sin nombre (DNS) o lo que diga el sistema.
    static func explain(_ e: NWError, host: String, port: UInt16) -> RemoteError {
        switch e {
        case .posix(.ECONNREFUSED): RemoteError(L("\(host) rechaza la conexión en el puerto \(String(port))"))
        case .posix(.ETIMEDOUT): RemoteError(L("\(host):\(String(port)) no contesta en \(Int(connectTimeout)) s (¿cortafuegos, VPN o puerto equivocado?)"))
        case .posix(.EHOSTUNREACH), .posix(.ENETUNREACH): RemoteError(L("No hay ruta hasta \(host) (¿VPN desconectada?)"))
        case .dns: RemoteError(L("No se encuentra el equipo «\(host)»"))
        default: RemoteError(e.localizedDescription)
        }
    }

    /// Si la tarea se cancela mientras espera, se cierra la conexión (Network termina la espera con error).
    private func cancellable<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()                // (ya cancelada: ni se empieza)
        return try await withTaskCancellationHandler(operation: body, onCancel: { connection.cancel() })
    }

    func send(_ d: Data) async throws {
        try await cancellable {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                self.connection.send(content: d, completion: .contentProcessed { e in
                    if let e { c.resume(throwing: RemoteError(e.localizedDescription)) } else { c.resume() }
                })
            }
        }
    }

    /// Lo siguiente que llegue; nil = el otro lado ha cerrado. `timeout`: sin nada en ese tiempo, se corta (control).
    /// El último trozo llega con `complete` (el servidor cerró tras mandarlo: así acaba un LIST o un RETR); volver a
    /// leer después da ENODATA («No message available on STREAM»), que también es el final, no un error.
    func receive(timeout: TimeInterval? = nil) async throws -> Data? {
        if ended.isTaken { return nil }
        return try await cancellable {
            let once = Once()
            let ended = self.ended
            return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data?, Error>) in
                self.connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, complete, e in
                    guard once.take() else { return }
                    if complete { _ = ended.take() }
                    if let data, !data.isEmpty {
                        c.resume(returning: data)
                    } else if let e, !complete, e != .posix(.ENODATA) {
                        c.resume(throwing: RemoteError(e.localizedDescription))
                    } else {
                        c.resume(returning: nil)
                    }
                }
                if let timeout {
                    self.queue.asyncAfter(deadline: .now() + timeout) {
                        guard once.take() else { return }
                        self.connection.cancel()
                        c.resume(throwing: RemoteError(L("FTP: el servidor no contesta (\(Int(timeout)) s)")))
                    }
                }
            }
        }
    }

    /// Cierra la escritura (fin del archivo en STOR) y espera a que se haya enviado.
    func finishSending() async throws {
        try await cancellable {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                self.connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { e in
                    if let e { c.resume(throwing: RemoteError(e.localizedDescription)) } else { c.resume() }
                })
            }
        }
    }

    func cancel() { connection.cancel() }
}

/// Sólo la primera vez (para no reanudar dos veces una continuación).
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool { lock.withLock { defer { done = true }; return !done } }
    var isTaken: Bool { lock.withLock { done } }
}

/// Lo que se interpreta del FTP (sin red: se prueba en los tests).
public enum FTPParse {
    /// Primera línea de una respuesta: «220 Hola» → (220, false, "Hola"); «220-Hola» abre una de varias líneas
    /// (`more`), que sigue hasta «220 …» (`replyEnds`).
    static func replyStart(_ first: String) throws -> (code: Int, more: Bool, text: String) {
        guard first.count >= 3, let code = Int(first.prefix(3)), (100...599).contains(code) else {
            throw RemoteError(L("FTP: respuesta no válida"))
        }
        return (code, first.dropFirst(3).first == "-", String(first.dropFirst(4)))
    }

    /// Una línea más de una respuesta de varias: true si es la última («211 End»). Las de en medio pueden venir
    /// con «211-» delante o sin código (RFC 959); el prefijo se quita.
    static func replyEnds(_ line: String, code: Int, into lines: inout [String]) -> Bool {
        let c = String(code)
        if line == c || line.hasPrefix(c + " ") {
            lines.append(String(line.dropFirst(4)))
            return true
        }
        lines.append(line.hasPrefix(c + "-") ? String(line.dropFirst(4)) : line)
        return false
    }

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
            // (el nombre: lo que queda tras la hora/año y UN espacio; puede llevar espacios, también delante: « a» no
            // es «a», que sería otro archivo)
            var rest = Substring(line)
            for _ in 0..<8 {
                rest = rest.drop(while: { $0 == " " })
                rest = rest.drop(while: { $0 != " " })
            }
            var name = String(rest.dropFirst())
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
        // (IIS alinea en columnas: el nombre empieza siempre en la 39; los espacios de más hasta ahí son del nombre. Sin
        // esas columnas no se sabe dónde empieza: con espacios delante, mejor no enseñarlo que confundirlo con otro)
        let start = line.distance(from: line.startIndex, to: rest.startIndex)      // (el espacio tras el tamaño)
        let gap = rest.prefix(while: { $0 == " " }).count
        let name: String
        if start < Self.iisNameColumn, start + gap >= Self.iisNameColumn {
            name = String(line.dropFirst(Self.iisNameColumn))
        } else if gap == 1 {
            name = String(rest.dropFirst())
        } else {
            return nil
        }
        guard RemotePath.isValidName(name) else { return nil }
        let isDir = f[2].uppercased() == "<DIR>"
        return RemoteEntry(name: name, path: RemotePath.join(dir, name), kind: isDir ? .directory : .file,
                           size: isDir ? nil : Int64(f[2]))
    }

    /// «01-31-24  09:15AM       <DIR>          nombre»: IIS pone el nombre en la columna 39.
    static let iisNameColumn = 39

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
    private struct Turn {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private var turn: [Turn] = []
    var queuedOperations: Int { turn.count }
    private(set) var features: Set<String> = []
    /// EPSV ha dado un puerto al que no se puede conectar, o no lo entiende (NAT, cortafuegos): desde entonces, PASV.
    /// Lo hereda cada conexión nueva del mismo servidor (`FTPFileSystem`), para no perder 10 s en cada archivo.
    private(set) var epsvBroken = false
    /// Lo más que se espera una respuesta del canal de control.
    static let replyTimeout: TimeInterval = 30

    init(host: String, port: UInt16, epsvBroken: Bool = false) {
        self.host = host
        self.port = port
        self.epsvBroken = epsvBroken
        control = TCPStream(host: host, port: port)
    }

    /// Conecta e inicia sesión. 530 = usuario o contraseña no válidos (`FTPLoginError`).
    func login(user: String, password: String) async throws {
        try await control.start()
        var r = try await reply()
        // («120 listo en n minutos» va antes del saludo: se espera al 220)
        for _ in 0..<3 where r.code == 120 { r = try await reply() }
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

    /// Para usar la conexión sin que se cruce otra orden en medio. Cancelar una espera sólo la quita de la cola:
    /// no cierra el control que está usando otra operación.
    func exclusive<T: Sendable>(_ body: @Sendable (FTPConnection) async throws -> T) async throws -> T {
        try await acquireTurn()
        defer { releaseTurn() }
        try Task.checkCancellation()                         // (también si se canceló justo al recibir el turno)
        return try await body(self)
    }

    private func acquireTurn() async throws {
        try Task.checkCancellation()
        if !busy { busy = true; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { c.resume(throwing: CancellationError()) }
                else { turn.append(Turn(id: id, continuation: c)) }
            }
        } onCancel: {
            Task { await self.cancelTurn(id) }
        }
    }

    private func cancelTurn(_ id: UUID) {
        guard let i = turn.firstIndex(where: { $0.id == id }) else { return }
        turn.remove(at: i).continuation.resume(throwing: CancellationError())
    }

    private func releaseTurn() {
        if turn.isEmpty { busy = false }
        else { turn.removeFirst().continuation.resume() }    // (busy sigue reservado al siguiente: no se cuela nadie)
    }

    private func readLine() async throws -> String {
        while true {
            if let nl = buffer.firstIndex(of: 10) {
                var line = buffer[buffer.startIndex..<nl]
                if line.last == 13 { line = line.dropLast() }
                buffer = Data(buffer[(nl + 1)...])
                return String(decoding: line, as: UTF8.self)
            }
            guard let d = try await control.receive(timeout: Self.replyTimeout) else {
                throw RemoteError(L("FTP: el servidor ha cerrado la conexión"))
            }
            buffer.append(d)
            if buffer.count > 1_000_000 { throw RemoteError(L("FTP: respuesta demasiado larga")) }
        }
    }

    /// Una respuesta (las de varias líneas «211-…» hasta «211 …»).
    func reply() async throws -> (code: Int, text: String) {
        let (code, more, text) = try FTPParse.replyStart(try await readLine())
        var lines = [text]
        if more { while !FTPParse.replyEnds(try await readLine(), code: code, into: &lines) {} }
        return (code, lines.joined(separator: "\n"))
    }

    func command(_ cmd: String, secret: Bool = false) async throws -> (code: Int, text: String) {
        guard !cmd.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\0" }) else {
            throw RemoteError(L("Nombre no válido"))
        }
        try await control.send(Data((cmd + "\r\n").utf8))
        return try await reply()
    }

    /// Abre la conexión de datos, siempre al mismo equipo del control: EPSV y, si el servidor no lo entiende o su
    /// puerto no se deja conectar (NAT, cortafuegos), PASV (como el Finder y curl). Desde ese fallo, sólo PASV.
    func openData() async throws -> TCPStream {
        if !epsvBroken {
            let e = try await command("EPSV")
            if e.code == 229, let port = FTPParse.epsvPort(e.text) {
                let s = TCPStream(host: host, port: port)
                do {
                    try await s.start()             // (start ya cancela la conexión si falla)
                    return s
                } catch {
                    try Task.checkCancellation()
                    DebugLog.log("ftp", "EPSV al puerto \(port) no conecta (\(error.localizedDescription)): PASV")
                }
            }
            epsvBroken = true
        }
        let p = try await command("PASV")
        guard p.code == 227 else { throw RemoteError(L("FTP: \(p.text)")) }
        guard let port = FTPParse.pasvPort(p.text) else { throw RemoteError(L("FTP: modo pasivo no válido")) }
        let s = TCPStream(host: host, port: port)
        try await s.start()
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
    /// La contraseña ya no vale (530 en una transferencia): avisa una vez y no se vuelve a probar.
    private let rejected: @Sendable () -> Void
    private let lock = NSLock()
    private var refused = false
    private var epsvBroken = false

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
        let mainBroken = await main.epsvBroken
        let c = FTPConnection(host: host, port: port, epsvBroken: mainBroken || lock.withLock { epsvBroken })
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
            let data = try await c.begin("RETR \(path)")
            await remember(c)
            return FTPFileReader(connection: c, data: data)
        } catch { await remember(c); await c.quit(); throw error }
    }

    public func openWrite(_ path: String) async throws -> any RemoteWriter {
        let c = try await fresh()
        do {
            let data = try await c.begin("STOR \(path)")
            await remember(c)
            return FTPFileWriter(connection: c, data: data)
        } catch { await remember(c); await c.quit(); throw error }
    }

    /// Si esa conexión ha visto que EPSV no vale, las siguientes van directas a PASV.
    private func remember(_ c: FTPConnection) async {
        if await c.epsvBroken { lock.withLock { epsvBroken = true } }
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
