import Darwin
import Foundation
import Observation

// Túneles SSH (-L local, -R remoto, -D SOCKS): un ssh sin terminal ni orden («-N -T») por túnel, con el mismo ssh_config
// («-F»), saltos y ProxyCommand compartido que la pestaña de esa sesión. Sólo arrancan con «Iniciar» (cargarlos no
// lanza nada); escuchan en este Mac (127.0.0.1) salvo que se marque expresamente; las contraseñas, por el askpass.

/// Un túnel guardado.
public struct Tunnel: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case local, remote = "remoto", dynamic = "socks"

        /// La opción de ssh.
        public var flag: String {
            switch self {
            case .local: "-L"
            case .remote: "-R"
            case .dynamic: "-D"
            }
        }
    }

    public var id: UUID
    public var name: String
    /// Sesión guardada (alias del ssh_config). Si está vacía, `server` (y `jump`).
    public var session: String
    /// «usuario@equipo[:puerto]» sin sesión guardada.
    public var server: String
    /// Saltos de `server` («bastion» o «admin@192.0.2.1:2222», separados por comas). Vacío: sin salto.
    public var jump: String
    public var kind: Kind
    /// Dónde escucha (en este Mac; en -R, en el servidor). Vacío: `defaultListen`.
    public var listenAddress: String
    public var listenPort: Int
    /// Adónde lleva (no en -D).
    public var targetHost: String
    public var targetPort: Int
    /// Escuchar fuera de loopback (0.0.0.0, «*», una IP de la red): sólo si se marca a propósito.
    public var exposed: Bool

    public static let maxName = 80
    /// Comprobación de que la conexión sigue viva (s).
    public static let aliveInterval = 30

    public init(id: UUID = UUID(), name: String, session: String = "", server: String = "", jump: String = "",
                kind: Kind = .local, listenAddress: String = "", listenPort: Int = 8080, targetHost: String = "",
                targetPort: Int = 80, exposed: Bool = false) {
        self.id = id
        self.name = name
        self.session = session
        self.server = server
        self.jump = jump
        self.kind = kind
        self.listenAddress = listenAddress
        self.listenPort = listenPort
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.exposed = exposed
    }

    enum CodingKeys: String, CodingKey {
        case id, name = "nombre", session = "sesion", server = "equipo", jump = "salto", kind = "tipo",
             listenAddress = "escucha", listenPort = "puerto", targetHost = "destino", targetPort = "puerto-destino",
             exposed = "abierto"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        session = try c.decodeIfPresent(String.self, forKey: .session) ?? ""
        server = try c.decodeIfPresent(String.self, forKey: .server) ?? ""
        jump = try c.decodeIfPresent(String.self, forKey: .jump) ?? ""
        kind = try c.decode(Kind.self, forKey: .kind)
        listenAddress = try c.decodeIfPresent(String.self, forKey: .listenAddress) ?? ""
        listenPort = try c.decode(Int.self, forKey: .listenPort)
        targetHost = try c.decodeIfPresent(String.self, forKey: .targetHost) ?? ""
        targetPort = try c.decodeIfPresent(Int.self, forKey: .targetPort) ?? 0
        exposed = try c.decodeIfPresent(Bool.self, forKey: .exposed) ?? false
    }

    /// Sin escucha escrita: este Mac (127.0.0.1) o, en -R, «localhost» del servidor.
    public var defaultListen: String { kind == .remote ? "localhost" : "127.0.0.1" }
    /// La escucha que se usa (sin corchetes).
    public var listen: String {
        let a = listenAddress.trimmed
        return a.isEmpty ? defaultListen : Self.unbracket(a)
    }

    /// Sólo este equipo: una IPv4 numérica de 127/8, ::1 (o una IPv4 de 127/8 mapeada en IPv6) o «localhost». Un nombre
    /// que empiece por «127.» no cuenta: lo resuelve el DNS a donde quiera (escuchar ahí hay que marcarlo).
    public static func isLoopback(_ address: String) -> Bool {
        let a = unbracket(address.trimmed).lowercased()
        if a == "localhost" { return true }
        var v4 = in_addr()
        if inet_pton(AF_INET, a, &v4) == 1 { return UInt32(bigEndian: v4.s_addr) >> 24 == 127 }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, a, &v6) == 1 else { return false }
        let b = withUnsafeBytes(of: &v6) { Array($0) }
        if b[0..<15].allSatisfy({ $0 == 0 }), b[15] == 1 { return true }                   // ::1
        return b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF && b[12] == 127   // ::ffff:127.x
    }

    static func unbracket(_ s: String) -> String {
        s.hasPrefix("[") && s.hasSuffix("]") && s.count > 2 ? String(s.dropFirst().dropLast()) : s
    }

    // (equipo o IP: letras, cifras, «.», «-», «_», «:» de IPv6 («::1»); nada de espacios, control ni «-» al principio)
    static let hostPattern = Pattern(#"^([A-Za-z0-9_][A-Za-z0-9_.:-]*|:[0-9A-Fa-f:.]*)\z"#, ignoreCase: false)
    static let jumpPattern = Pattern(#"^[A-Za-z0-9_][A-Za-z0-9_.@:\[\]-]*\z"#, ignoreCase: false)

    /// ¿Vale como equipo o IP (destino o escucha)? (con o sin corchetes)
    static func validHost(_ raw: String) -> Bool {
        let h = unbracket(raw.trimmed)
        return !h.isEmpty && h.count <= 253 && hostPattern.matches(h)
    }

    /// Sin caracteres de control (para enseñarlo).
    static func printable(_ s: String) -> String {
        String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
    }

    /// Por qué no se puede guardar ni iniciar, o nil.
    public var problem: String? {
        let n = name.trimmed
        if n.isEmpty { return L("sin nombre") }
        if n.count > Self.maxName { return L("nombre de más de \(String(Self.maxName)) caracteres") }
        if SessionFile.hasControl(n) { return L("el nombre lleva caracteres de control") }
        let s = session.trimmed
        if !s.isEmpty {
            if s.hasPrefix("-") || s.contains(where: \.isWhitespace) || SessionFile.hasControl(s) {
                return L("Sesión no válida: «\(Self.printable(s))»")
            }
        } else {
            let sv = server.trimmed
            if sv.isEmpty { return L("elige una sesión o escribe el equipo") }
            guard let e = Endpoint(parsing: sv), Self.hostPattern.matches(Self.unbracket(e.host)), !SessionFile.hasControl(sv) else {
                return L("Equipo no válido: «\(Self.printable(sv))»")
            }
            for j in jumps where !Self.jumpPattern.matches(j) { return L("Salto no válido: «\(Self.printable(j))»") }
        }
        let a = listenAddress.trimmed
        if !a.isEmpty, a != "*", !Self.validHost(a) { return L("Escucha no válida: «\(Self.printable(a))»") }
        if !(1...65535).contains(listenPort) { return L("el puerto de escucha va de 1 a 65535") }
        if !Self.isLoopback(listen), !exposed {
            return L("escuchar en «\(listen)» abre el túnel a otros equipos: márcalo expresamente o deja 127.0.0.1")
        }
        if kind != .dynamic {
            if targetHost.trimmed.isEmpty { return L("falta el destino (equipo y puerto)") }
            if !Self.validHost(targetHost) { return L("Destino no válido: «\(Self.printable(targetHost.trimmed))»") }
            if !(1...65535).contains(targetPort) { return L("el puerto de destino va de 1 a 65535") }
        }
        return nil
    }

    /// Avisos que no impiden guardarlo.
    public var warnings: [String] {
        var w: [String] = []
        if (1..<1024).contains(listenPort) {
            w.append(kind == .remote ? L("puerto \(String(listenPort)) por debajo de 1024: en el servidor sólo lo puede abrir root")
                                     : L("puerto \(String(listenPort)) por debajo de 1024: reservado para servicios del sistema"))
        }
        if !Self.isLoopback(listen) {
            w.append(kind == .remote ? L("⚠ Escucha en «\(listen)» del servidor: cualquiera que llegue a él entra por el túnel (y el servidor tiene que permitirlo con GatewayPorts)")
                                     : L("⚠ Escucha en «\(listen)»: cualquiera que llegue a este Mac por la red entra por el túnel"))
        }
        return w
    }

    var jumps: [String] {
        jump.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    /// «[escucha]:puerto[:destino:puerto]» (IPv6 entre corchetes; «*» tal cual).
    public var forwardSpec: String {
        func b(_ h: String) -> String { h.contains(":") ? "[\(h)]" : h }
        let l = listen == "*" ? "*" : b(listen)
        let base = "\(l):\(listenPort)"
        return kind == .dynamic ? base : base + ":\(b(Self.unbracket(targetHost.trimmed))):\(targetPort)"
    }

    /// La ruta hasta el servidor: la de la sesión guardada (su alias, saltos y ProxyCommand del ssh_config; también las
    /// sftp, que son ssh) o la del equipo escrito con sus saltos («-J»). Sesiones telnet, serie, FTP o locales, no.
    @MainActor
    public func route(using manager: SessionManager) throws -> ConnectionRoute {
        if let p = problem { throw TunnelError.invalid(p) }
        let s = session.trimmed
        if !s.isEmpty {
            guard let profile = manager.profile(named: s) else { throw TunnelError.noSession(s) }
            guard profile.transport == .ssh || profile.transport == .sftp else { throw TunnelError.notSSH(s) }
            var r = try manager.route(to: profile)                   // (rechaza nombre, equipo o usuario con «-»)
            r.transport = .ssh
            return r
        }
        guard let e = Endpoint(parsing: server.trimmed) else { throw TunnelError.invalid(L("Equipo no válido: «\(server)»")) }
        let title = name.trimmed
        return ConnectionRoute(title: title, target: e, jumpSpec: jumps.isEmpty ? nil : jumps)
    }

    /// Los argumentos de ssh (sin shell: un array tal cual para el proceso; nunca una contraseña): opciones del túnel
    /// delante del «--» con el que acaba la orden de la sesión.
    public func arguments(route: ConnectionRoute, sharing: JumpSharing?, configFile: String?) throws -> [String] {
        if let p = problem { throw TunnelError.invalid(p) }
        var r = route
        guard !r.isLocal, r.transport == .ssh || r.transport == .sftp else { throw TunnelError.notSSH(r.title) }
        r.transport = .ssh
        let cmd = r.command(sharing: sharing, configFile: configFile)
        guard cmd.executable == "/usr/bin/ssh", let dash = cmd.arguments.lastIndex(of: "--") else { throw TunnelError.notSSH(r.title) }
        // (su propia conexión, sin ControlMaster: parar el túnel cierra justo ésa y no deja nada abierto detrás;
        // LogLevel=VERBOSE: «Authenticated to …» dice cuándo ha entrado, para el -R)
        let opts = ["-N", "-T", "-x", "-a",
                    "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=\(Self.aliveInterval)",
                    "-o", "ServerAliveCountMax=3", "-o", "ConnectTimeout=20", "-o", "BatchMode=no",
                    "-o", "ControlMaster=no", "-o", "ControlPath=none", "-o", "ControlPersist=no",
                    "-o", "ForkAfterAuthentication=no", "-o", "ClearAllForwardings=no", "-o", "GatewayPorts=no",
                    "-o", "PermitLocalCommand=no",
                    "-o", "RemoteCommand=none", "-o", "RequestTTY=no", "-o", "LogLevel=VERBOSE",
                    kind.flag, forwardSpec]
        var a = cmd.arguments
        a.insert(contentsOf: opts, at: dash)
        return a
    }

    /// La misma orden, sin el forward pedido y con «-G»: SSH resuelve Include, Host *, Match y el alias, sin conectar.
    /// `TunnelManager` la comprueba antes de lanzar la conexión (ClearAllForwardings=yes borraría también el de CLI).
    func configurationArguments(arguments: [String]) throws -> [String] {
        guard let dash = arguments.lastIndex(of: "--"), dash == arguments.count - 2, dash >= 2,
              arguments[dash - 2] == kind.flag, arguments[dash - 1] == forwardSpec else {
            throw TunnelError.invalid(L("ssh -G ha devuelto una configuración incompleta o demasiado grande"))
        }
        var a = arguments
        a.removeSubrange((dash - 2)..<dash)
        a.insert("-G", at: 0)
        return a
    }

    static func configurationProblem(_ output: String) -> String? {
        let fields = output.split(separator: "\n").map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
        if fields.contains(where: { ["localforward", "remoteforward", "dynamicforward"].contains($0.first?.lowercased() ?? "") }) {
            return L("El ssh_config añade LocalForward, RemoteForward o DynamicForward a esta conexión. Usa una sesión sin reenvíos heredados para iniciar sólo este túnel.")
        }
        guard fields.contains(where: { $0.first == "host" && $0.count == 2 }),
              fields.contains(["clearallforwardings", "no"]) else {
            return L("ssh -G ha devuelto una configuración incompleta o demasiado grande")
        }
        return nil
    }
}

public enum TunnelError: LocalizedError, Equatable {
    case invalid(String)
    case noSession(String)
    case notSSH(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let s): s
        case .noSession(let s): L("No está la sesión «\(s)» en el ssh_config")
        case .notSSH(let s): L("«\(s)» no es una sesión ssh: los túneles van por ssh")
        }
    }
}

// MARK: - archivo

/// Los túneles guardados: `AppPaths.support/tuneles.json` (0600, con copia antes de sustituirlo), versionado. Leerlos
/// no arranca ninguno.
public struct TunnelLibrary: Sendable, Equatable {
    public static let version = 1
    public var tunnels: [Tunnel]

    public static var defaultURL: URL { AppPaths.support.appendingPathComponent("tuneles.json") }

    public init(tunnels: [Tunnel] = []) { self.tunnels = tunnels }

    /// Lo leído: los válidos, avisos de los ignorados y, si el archivo no se puede usar (ilegible, JSON roto o versión
    /// desconocida), el error: entonces no se toca y, al guardar, se aparta a `.ilegible`.
    public struct Loaded: Sendable {
        public var library: TunnelLibrary
        public var warnings: [String]
        public var error: String?
    }

    private struct Lenient: Decodable {
        var tunnel: Tunnel?
        init(from decoder: Decoder) throws { tunnel = try? Tunnel(from: decoder) }
    }
    private struct File: Decodable { var version: Int; var tuneles: [Lenient] }
    private struct Header: Decodable { var version: Int }

    public static func load(from url: URL = defaultURL) -> Loaded {
        let path = AppPaths.tilde(url.path)
        let text: String
        do {
            guard let t = try SafeFile.read(url) else { return Loaded(library: .init(), warnings: [], error: nil) }
            text = t
        } catch {
            return Loaded(library: .init(), warnings: [], error: error.localizedDescription)
        }
        let data = Data(text.utf8)
        let broken = L("\(path) no se entiende (JSON roto): no lo sobrescribo hasta que guardes; entonces queda aparte en tuneles.json.ilegible")
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
            return Loaded(library: .init(), warnings: [], error: broken)
        }
        guard header.version == version else {
            return Loaded(library: .init(), warnings: [], error: L("\(path) es de otra versión (\(String(header.version))): no lo sobrescribo hasta que guardes; entonces queda aparte en tuneles.json.ilegible"))
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            return Loaded(library: .init(), warnings: [], error: broken)
        }
        var lib = TunnelLibrary(), warnings: [String] = []
        for (i, entry) in file.tuneles.enumerated() {
            guard var t = entry.tunnel else { warnings.append(L("túnel \(String(i + 1)): no se entiende; se ignora")); continue }
            if let p = t.problem { warnings.append(L("«\(Tunnel.printable(t.name))»: \(p); se ignora")); continue }
            t.name = t.name.trimmed
            if lib.tunnels.contains(where: { $0.name.lowercased() == t.name.lowercased() || $0.id == t.id }) {
                warnings.append(L("«\(t.name)»: repetido; se ignora"))
                continue
            }
            lib.tunnels.append(t)
        }
        return Loaded(library: lib, warnings: warnings, error: nil)
    }

    /// Por qué no se puede guardar, o nil.
    public var problem: String? {
        var seen = Set<String>(), ids = Set<UUID>()
        for t in tunnels {
            if let p = t.problem { return L("«\(Tunnel.printable(t.name))»: \(p)") }
            if !seen.insert(t.name.trimmed.lowercased()).inserted { return L("Hay dos túneles con el nombre «\(t.name.trimmed)»") }
            if !ids.insert(t.id).inserted { return L("Hay dos túneles con el mismo identificador") }
        }
        return nil
    }

    /// Guarda (validados). `setAsideUnusable`: el archivo de ahora no se pudo usar al leerlo; antes de escribir se
    /// aparta a `tuneles.json.ilegible` (no se pierde).
    public func save(to url: URL = TunnelLibrary.defaultURL, setAsideUnusable: Bool = false) throws {
        try save(to: url, setAsideUnusable: setAsideUnusable, write: { try SafeFile.write($0, to: $1) })
    }

    // (la escritura se puede sustituir en las pruebas para comprobar el rollback sin depender de permisos)
    func save(to url: URL, setAsideUnusable: Bool, write: (String, URL) throws -> Void) throws {
        if let p = problem { throw TunnelError.invalid(p) }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        struct Out: Encodable { var version: Int; var tuneles: [Tunnel] }
        let out = Out(version: Self.version, tuneles: tunnels.map { var t = $0; t.name = t.name.trimmed; return t })
        let text = String(decoding: try enc.encode(out), as: UTF8.self) + "\n"
        AppPaths.ensure(url.deletingLastPathComponent())
        let fm = FileManager.default
        if setAsideUnusable, fm.fileExists(atPath: url.path) {
            let aside = url.appendingPathExtension("ilegible")
            let held = url.appendingPathExtension("ilegible-\(UUID().uuidString)")
            try fm.moveItem(at: url, to: held)
            do {
                try write(text, url)
                if fm.fileExists(atPath: aside.path) { _ = try fm.replaceItemAt(aside, withItemAt: held) }
                else { try fm.moveItem(at: held, to: aside) }
            } catch {
                // (la copia .ilegible anterior sólo se sustituye tras escribir; si falla, vuelve el archivo original)
                if fm.fileExists(atPath: held.path) {
                    if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: held) }
                    else { try fm.moveItem(at: held, to: url) }
                }
                throw error
            }
        } else {
            try SafeFile.backup(url)
            try write(text, url)
        }
    }

    public func tunnel(_ id: Tunnel.ID?) -> Tunnel? { tunnels.first { $0.id == id } }

    /// «base», «base 2»… sin repetir (sin mirar mayúsculas), sin contar el de `except`.
    public func uniqueName(_ base: String, except: Tunnel.ID? = nil) -> String {
        let b = base.trimmed.isEmpty ? "tunel" : String(base.trimmed.prefix(Tunnel.maxName - 4))
        let taken = Set(tunnels.filter { $0.id != except }.map { $0.name.trimmed.lowercased() })
        var n = b, k = 2
        while taken.contains(n.lowercased()) { n = "\(b) \(k)"; k += 1 }
        return n
    }
}

// MARK: - puertos

public enum PortCheck {
    /// Por qué no se puede escuchar en `address:port` en este Mac (otro lo usa, la dirección no es de este Mac…), o nil
    /// si está libre. Bind de prueba con SO_REUSEADDR, como hace ssh. «*»: todas las direcciones.
    public static func problem(address: String, port: Int) -> String? {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_PASSIVE
        var list: UnsafeMutablePointer<addrinfo>?
        let host: String? = address == "*" ? nil : address
        guard getaddrinfo(host, String(port), &hints, &list) == 0, let first = list else {
            return L("no se encuentra la dirección «\(address)»")
        }
        defer { freeaddrinfo(list) }
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let ai = p {
            p = ai.pointee.ai_next
            let fd = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
            if fd < 0 { continue }
            defer { close(fd) }
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
            if ai.pointee.ai_family == AF_INET6 {
                setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &one, socklen_t(MemoryLayout<Int32>.size))
            }
            if bind(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen) != 0 {
                let e = errno
                if e == EADDRNOTAVAIL && ai.pointee.ai_family == AF_INET6 && host == nil { continue }   // (sin IPv6)
                switch e {
                case EADDRINUSE: return L("el puerto \(String(port)) ya está en uso en \(address)")
                case EACCES: return L("sin permiso para escuchar en el puerto \(String(port))")
                case EADDRNOTAVAIL: return L("«\(address)» no es una dirección de este Mac")
                default: return L("no se puede escuchar en \(address):\(String(port)) (\(String(cString: strerror(e))))")
                }
            }
        }
        return nil
    }

    /// ¿Alguien escucha ya en `address:port`? (conexión de prueba; «*» y 0.0.0.0 se prueban en 127.0.0.1, «::» en ::1)
    public static func isListening(address: String, port: Int, timeout: Int32 = 300) -> Bool {
        let a = address == "*" || address == "0.0.0.0" ? "127.0.0.1" : address == "::" ? "::1" : address
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(a, String(port), &hints, &list) == 0, let first = list else { return false }
        defer { freeaddrinfo(list) }
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let ai = p {
            p = ai.pointee.ai_next
            let fd = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
            if fd < 0 { continue }
            defer { close(fd) }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            if connect(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen) == 0 { return true }
            guard errno == EINPROGRESS else { continue }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&pfd, 1, timeout) == 1 else { continue }
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            if getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) == 0, err == 0 { return true }
        }
        return false
    }
}

// MARK: - procesos

/// Por qué ha terminado ssh, leído de lo que escribe por su salida de errores.
public enum TunnelFailure {
    public static func reason(stderr: String, status: Int32?) -> String {
        let lines = stderr.components(separatedBy: .newlines).map { Tunnel.printable($0).trimmed }.filter { !$0.isEmpty }
        let all = lines.joined(separator: "\n").lowercased()
        if all.contains("address already in use") || all.contains("cannot listen to port") || all.contains("could not request local forwarding") {
            return L("el puerto de escucha ya está en uso (Address already in use)")
        }
        if all.contains("remote port forwarding failed") || all.contains("error: remote port forwarding") {
            return L("el servidor no deja abrir el puerto remoto (remote port forwarding failed: ¿ocupado, menor que 1024 o prohibido?)")
        }
        if all.contains("administratively prohibited") || all.contains("stdio forwarding failed") {
            return L("el servidor o el salto no permiten reenviar puertos (administratively prohibited)")
        }
        if all.contains("permission denied") || all.contains("too many authentication failures") {
            return L("autenticación fallida (Permission denied)")
        }
        if all.contains("host key verification failed") || all.contains("remote host identification has changed") {
            return L("la clave del equipo no coincide con known_hosts (Host key verification failed)")
        }
        if all.contains("could not resolve hostname") { return L("no se encuentra el equipo (Could not resolve hostname)") }
        if all.contains("connection refused") { return L("conexión rechazada (Connection refused)") }
        if all.contains("timed out") { return L("no responde (tiempo agotado)") }
        // (lo último que ha dicho ssh, sin las líneas de LogLevel=VERBOSE que no son el error)
        let useful = lines.filter { l in
            !["authenticated to", "warning: permanently added", "server accepts key", "authentications that can continue",
              "connection established", "connecting to", "transferred:", "bytes per second", "local forwarding listening",
              "remote connections from", "**"].contains { l.lowercased().hasPrefix($0) }
        }
        if let last = useful.last { return String(last.prefix(300)) }
        if let s = status, WIFSIGNALED(s) { return L("ssh ha terminado (señal \(String(WTERMSIG(s))))") }
        return L("ssh ha terminado (código \(String(status.map(WEXITSTATUS) ?? -1)))")
    }

    // (las macros de wait.h no llegan a Swift)
    static func WIFSIGNALED(_ s: Int32) -> Bool { s & 0x7f != 0 && s & 0x7f != 0x7f }
    static func WTERMSIG(_ s: Int32) -> Int32 { s & 0x7f }
    static func WEXITSTATUS(_ s: Int32) -> Int32 { (s >> 8) & 0xff }
}

/// El proceso ssh de un túnel: sin terminal (sesión propia: el askpass pregunta en una ventana), sin entrada, y con
/// su salida de errores guardada para saber por qué ha terminado. Grupo de procesos propio: parar mata también su
/// ProxyCommand.
public final class TunnelProcess: @unchecked Sendable {
    public let pid: pid_t
    private let lock = NSLock()
    private var output = Data()
    private var truncated = false
    private var status: Int32?
    private let stderr: FileHandle
    private let captureOutput: Bool
    private var exitSource: DispatchSourceProcess?

    public init(executable: String, arguments: [String], environment: [String: String], captureOutput: Bool = false) throws {
        let errPipe = Pipe()
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        if captureOutput {
            posix_spawn_file_actions_adddup2(&actions, errPipe.fileHandleForWriting.fileDescriptor, 1)
        } else {
            posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        }
        posix_spawn_file_actions_adddup2(&actions, errPipe.fileHandleForWriting.fileDescriptor, 2)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // (sesión propia; sólo hereda 0, 1 y 2; las señales de parada, sin bloquear ni ignorar)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var defaults = sigset_t(), mask = sigset_t()
        sigemptyset(&defaults)
        sigemptyset(&mask)
        for sig in [SIGPIPE, SIGTERM, SIGINT, SIGHUP] { sigaddset(&defaults, sig) }
        posix_spawnattr_setsigdefault(&attr, &defaults)
        posix_spawnattr_setsigmask(&attr, &mask)
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var child: pid_t = 0
        let rc = posix_spawn(&child, executable, &actions, &attr, argv, envp)
        try? errPipe.fileHandleForWriting.close()
        guard rc == 0 else { throw TunnelError.invalid(L("No arranca \(executable): \(String(cString: strerror(rc)))")) }
        pid = child
        self.captureOutput = captureOutput
        stderr = errPipe.fileHandleForReading
        let fd = stderr.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        stderr.readabilityHandler = { [weak self] h in
            guard let self else { return }
            if self.lock.withLock({ self.readOutput() }) { h.readabilityHandler = nil }
        }
        let src = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: .global())
        src.setEventHandler { [weak self] in self?.reap(); src.cancel() }
        exitSource = src
        src.resume()
        reap()                                                 // (también si salió antes de instalar el aviso)
    }

    // (con lock: el lector y la recogida final nunca compiten por la tubería; no se espera un EOF de un nieto)
    private func readOutput() -> Bool {
        var bytes = [UInt8](repeating: 0, count: 8192)
        for _ in 0..<128 {
            let n = read(stderr.fileDescriptor, &bytes, bytes.count)
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return n == 0 }
            let limit = captureOutput ? 1_048_576 : 8000
            if captureOutput {
                if output.count + n > limit { truncated = true }
                output.append(contentsOf: bytes.prefix(min(n, max(0, limit - output.count))))
            } else {
                output.append(contentsOf: bytes.prefix(n))
                if output.count > limit { output = Data(output.suffix(4000)) }
            }
        }
        return false
    }

    private func reap() {
        lock.withLock {
            guard status == nil else { return }
            var info = siginfo_t()
            // (WNOWAIT mantiene el PID reservado hasta haber matado su grupo: ni huérfanos ni señales a un PID reciclado)
            var ready: Int32
            repeat { ready = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) } while ready < 0 && errno == EINTR
            guard ready == 0, info.si_pid == pid else { return }
            killpg(pid, SIGKILL)
            var st: Int32 = 0, result: pid_t
            repeat { result = waitpid(pid, &st, 0) } while result < 0 && errno == EINTR
            _ = readOutput()                                   // (el último error ya está leído cuando exited sea true)
            if result == pid { status = st }
        }
        if exited { stderr.readabilityHandler = nil; exitSource?.cancel() }
    }

    deinit {
        stderr.readabilityHandler = nil
        exitSource?.cancel()
        signal(SIGKILL)
        if !exited {
            let child = pid
            DispatchQueue.global().async {
                var st: Int32 = 0, result: pid_t
                repeat { result = waitpid(child, &st, 0) } while result < 0 && errno == EINTR
            }
        }
    }

    public var exited: Bool { lock.withLock { status != nil } }
    public var exitStatus: Int32? { lock.withLock { status } }
    public var errorOutput: String { lock.withLock { String(decoding: output, as: UTF8.self) } }
    public var outputTruncated: Bool { lock.withLock { truncated } }

    /// A todo su grupo (ssh y su ProxyCommand), sólo si sigue vivo (un pid ya recogido podría ser de otro).
    public func signal(_ sig: Int32) {
        lock.withLock {
            guard status == nil else { return }
            if killpg(pid, sig) != 0 { kill(pid, sig) }
        }
    }

    /// La limpieza continúa aunque se cancele quien está esperando a «Parar».
    func stop(grace: Double) async {
        await Task.detached { [self] in
            signal(SIGTERM)
            let deadline = Date().addingTimeInterval(grace)
            while !exited, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
            if !exited { signal(SIGKILL) }
            let end = Date().addingTimeInterval(2)
            while !exited, Date() < end { try? await Task.sleep(for: .milliseconds(20)) }
        }.value
    }
}

/// Estado de un túnel en esta ejecución de la app.
public enum TunnelState: Equatable, Sendable {
    case stopped, starting, active, failed(String)

    public var isRunning: Bool { self == .starting || self == .active }
}

/// Arranca, vigila y para los túneles. No relanza nada: si ssh muere, el túnel queda en error con el motivo.
@MainActor @Observable
public final class TunnelManager {
    public private(set) var states: [Tunnel.ID: TunnelState] = [:]
    private final class Running {
        var process: TunnelProcess
        var stopping = false
        init(_ process: TunnelProcess) { self.process = process }
    }
    @ObservationIgnored private var running: [Tunnel.ID: Running] = [:]
    @ObservationIgnored private var authenticationRejections: [Tunnel.ID: Askpass.Rejection] = [:]
    /// Tras SIGTERM, cuánto esperar antes de SIGKILL.
    @ObservationIgnored public var killAfter: Double = 3
    @ObservationIgnored public var pollInterval: Double = 0.2
    @ObservationIgnored public var configurationTimeout: Double = 10
    /// -R: activo cuando ha entrado y sigue vivo este tiempo (si el servidor no deja, ssh sale enseguida).
    @ObservationIgnored public var remoteGrace: Double = 1.5
    /// Cada cambio de estado (askpass, avisos).
    @ObservationIgnored public var onChange: ((Tunnel.ID, TunnelState) -> Void)?

    public init() {}

    public func state(_ id: Tunnel.ID) -> TunnelState { states[id] ?? .stopped }
    public var activeCount: Int { states.values.filter(\.isRunning).count }

    /// El rechazo del ssh de esta ejecución (con su equipo), antes de resumir el error para la interfaz. Un fallo de
    /// configuración, puerto o red no se atribuye a ninguna contraseña.
    public func authenticationRejection(for id: Tunnel.ID) -> Askpass.Rejection? { authenticationRejections[id] }

    private func set(_ id: Tunnel.ID, _ s: TunnelState) {
        guard states[id] != s else { return }
        states[id] = s
        onChange?(id, s)
    }

    /// Primero «ssh -G», con la misma ruta y sin el forward pedido: cualquier reenvío heredado impide arrancar.
    /// El preflight forma parte de «iniciando»: Parar, borrar y salir lo cancelan igual que la conexión.
    public func start(_ tunnel: Tunnel, executable: String, arguments: [String], environment: [String: String]) {
        let id = tunnel.id
        guard !state(id).isRunning, running[id] == nil else { return }
        authenticationRejections[id] = nil
        if let p = tunnel.problem { set(id, .failed(p)); return }
        if tunnel.kind != .remote, let p = PortCheck.problem(address: tunnel.listen, port: tunnel.listenPort) {
            set(id, .failed(p)); return
        }
        let proc: TunnelProcess
        do {
            proc = try TunnelProcess(executable: executable, arguments: tunnel.configurationArguments(arguments: arguments),
                                     environment: environment, captureOutput: true)
        } catch {
            set(id, .failed(error.localizedDescription)); return
        }
        let run = Running(proc)
        running[id] = run
        set(id, .starting)
        let interval = pollInterval
        Task { [weak self] in
            let started = Date()          // (el tope se lee en cada vuelta: cambiarlo vale para el que ya está esperando)
            while self?.running[id] === run, !run.stopping {
                if proc.exited {
                    let why: String?
                    if proc.exitStatus != 0 {
                        why = L("No se ha podido comprobar el ssh_config con ssh -G: \(AppPaths.tilde(TunnelFailure.reason(stderr: proc.errorOutput, status: proc.exitStatus)))")
                    } else if proc.outputTruncated {
                        why = L("ssh -G ha devuelto una configuración incompleta o demasiado grande")
                    } else {
                        why = Tunnel.configurationProblem(proc.errorOutput)
                    }
                    if let why { self?.finish(id, run, .failed(why)) }
                    else { self?.launch(tunnel, run, executable: executable, arguments: arguments, environment: environment) }
                    return
                }
                let timeout = self?.configurationTimeout ?? 10
                if Date().timeIntervalSince(started) >= timeout {
                    await proc.stop(grace: 0)
                    if !run.stopping {
                        self?.finish(id, run, .failed(L("ssh -G no ha contestado en \(Int(timeout)) s")))
                    }
                    return
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func finish(_ id: Tunnel.ID, _ run: Running, _ state: TunnelState, rejection: Askpass.Rejection? = nil) {
        guard running[id] === run, run.process.exited else { return }
        running[id] = nil
        authenticationRejections[id] = rejection              // (ya disponible cuando onChange recibe el error)
        set(id, state)
    }

    private func launch(_ tunnel: Tunnel, _ run: Running, executable: String, arguments: [String], environment: [String: String]) {
        let id = tunnel.id
        guard running[id] === run, !run.stopping else { return }
        // (durante el preflight alguien puede haber ocupado el puerto)
        if tunnel.kind != .remote, let p = PortCheck.problem(address: tunnel.listen, port: tunnel.listenPort) {
            finish(id, run, .failed(p)); return
        }
        let proc: TunnelProcess
        do { proc = try TunnelProcess(executable: executable, arguments: arguments, environment: environment) }
        catch { finish(id, run, .failed(error.localizedDescription)); return }
        run.process = proc
        DebugLog.log("tuneles", "«\(tunnel.name)» inicia (pid \(proc.pid)): \(executable) \(arguments.joined(separator: " "))")
        let kind = tunnel.kind, listen = tunnel.listen, port = tunnel.listenPort
        let interval = pollInterval, grace = remoteGrace
        Task { [weak self] in
            var authed: Date?
            while self?.running[id] === run {
                if proc.exited {
                    let stderr = proc.errorOutput
                    let why = TunnelFailure.reason(stderr: stderr, status: proc.exitStatus)
                    let rejection = run.stopping ? nil : Askpass.rejection(in: stderr.components(separatedBy: .newlines))
                    DebugLog.log("tuneles", "«\(tunnel.name)» termina: \(run.stopping ? "parado" : why)")
                    self?.finish(id, run, run.stopping ? .stopped : .failed(why), rejection: rejection)
                    return
                }
                if !run.stopping, self?.state(id) == .starting {
                    if kind == .remote {
                        if authed == nil, proc.errorOutput.contains("Authenticated to") { authed = Date() }
                        if let a = authed, Date().timeIntervalSince(a) >= grace { self?.set(id, .active) }
                    } else {
                        let listening = await Task.detached { PortCheck.isListening(address: listen, port: port) }.value
                        guard self?.running[id] === run, !run.stopping else { continue }
                        if listening, !proc.exited { self?.set(id, .active) }
                    }
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// No se ha podido ni lanzar (la sesión ya no está, no es ssh…): queda en error con el motivo.
    public func markFailed(_ id: Tunnel.ID, _ why: String) {
        guard !state(id).isRunning else { return }
        authenticationRejections[id] = nil
        set(id, .failed(why))
    }

    /// Para: SIGTERM y, si no sale en `killAfter` s, SIGKILL. Queda «detenido» cuando se ha recogido el proceso.
    public func stop(_ id: Tunnel.ID) async {
        guard let run = running[id] else {
            authenticationRejections[id] = nil
            if case .failed = state(id) { set(id, .stopped) }
            return
        }
        run.stopping = true
        await run.process.stop(grace: killAfter)
        finish(id, run, .stopped)                                // (una parada antigua nunca pisa un nuevo arranque)
    }

    /// Al salir: incluye los preflight, mata los grupos completos y recoge los procesos antes de olvidarlos.
    public func stopAll(wait: Double = 1.5) {
        authenticationRejections.removeAll()
        let all = running
        guard !all.isEmpty else { return }
        for run in all.values { run.stopping = true; run.process.signal(SIGTERM) }
        let deadline = Date().addingTimeInterval(wait)
        while all.values.contains(where: { !$0.process.exited }), Date() < deadline { usleep(20_000) }
        all.values.filter { !$0.process.exited }.forEach { $0.process.signal(SIGKILL) }
        let end = Date().addingTimeInterval(2)
        while all.values.contains(where: { !$0.process.exited }), Date() < end { usleep(20_000) }
        for (id, run) in all { finish(id, run, .stopped) }
        DebugLog.log("tuneles", "parados al salir: \(all.count)")
    }

    /// El túnel ya no existe (borrado): se para si estaba en marcha y se olvida su estado.
    public func forget(_ id: Tunnel.ID) async {
        await stop(id)
        if running[id] == nil { states[id] = nil; authenticationRejections[id] = nil }
    }
}
