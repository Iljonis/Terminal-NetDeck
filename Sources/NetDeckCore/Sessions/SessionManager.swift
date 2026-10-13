import Foundation
import Observation

/// Sesiones de NetDeck: las del ssh_config (o de ejemplo), rutas con saltos y contraseñas candidatas de cada una.
@MainActor @Observable
public final class SessionManager {
    public private(set) var profiles: [SessionProfile]
    public private(set) var source: URL?
    public private(set) var loadError: String?

    public static var defaultConfigURL: URL {
        AppPaths.home.appendingPathComponent(".ssh/config")
    }

    public init(profiles: [SessionProfile] = []) {
        self.profiles = profiles
    }

    // MARK: - carga

    public func load(from url: URL = SessionManager.defaultConfigURL) {
        do {
            profiles = try SSHConfigParser().parse(contentsOf: url)
            source = url
            loadError = nil
        } catch {
            loadError = L("No se puede leer \(url.path): \(error.localizedDescription)")
        }
    }

    /// Sin ssh_config: un salto y equipos detrás (datos de ejemplo, nada real).
    public func loadSamples() {
        profiles = SSHConfigParser().parse("""
            # @grupo Saltos
            Host bastion
              HostName 192.0.2.1
              User tu.usuario
              # @desc Salto de ejemplo
            # @grupo Core
            # @clave-grupo AD
            Host core-01
              HostName 192.0.2.11
              User tu.usuario
              ProxyJump bastion
            Host core-02
              HostName 192.0.2.12
              User admin
              ProxyJump bastion
              # @clave admin-core
            Host olt-01
              HostName 192.0.2.21
              ProxyJump bastion
              # @telnet
            """)
        source = nil
        loadError = nil
    }

    public func profile(named name: String) -> SessionProfile? {
        profiles.first { $0.name == name }
    }

    /// Grupos en el orden en que aparecen («Sin grupo» al final).
    public var groups: [(name: String, profiles: [SessionProfile])] {
        var order: [String] = []
        var by: [String: [SessionProfile]] = [:]
        for p in profiles {
            let g = p.group ?? ""
            if by[g] == nil { order.append(g) }
            by[g, default: []].append(p)
        }
        order.sort { $1.isEmpty && !$0.isEmpty }
        return order.map { ($0.isEmpty ? "Sin grupo" : $0, by[$0]!) }
    }

    // MARK: - rutas

    public func route(to p: SessionProfile) throws -> ConnectionRoute {
        ConnectionRoute(title: p.name, target: p.endpoint, jumps: try resolve(p.proxyJump, seen: [p.name]),
                        transport: p.transport, alias: p.transport == .ssh ? p.name : nil, sessionName: p.name)
    }

    /// Acceso directo de salto, como NetDeck: se abre la sesión del salto y, al salir su prompt, se escribe
    /// «ssh equipo» (o «telnet equipo»). Vale aunque el salto no deje reenviar (-J: «administratively prohibited»).
    /// `device`: alias o usuario@equipo[:puerto]; `jump`: alias del ssh_config o usuario@equipo.
    public func jumpShortcut(to device: String, via jump: String, user: String? = nil,
                             transport: SessionProfile.Transport = .ssh) throws -> ConnectionRoute {
        var r = try jumpRoute(jump)
        var target: Endpoint
        var t = transport
        if let p = profile(named: device) {
            target = p.endpoint
            t = p.transport
        } else {
            guard let e = Endpoint(parsing: device) else { throw RouteError.badDevice(device) }
            target = e
        }
        if target.user == nil { target.user = user }
        guard let cmd = ConnectionRoute.hopCommand(to: target, transport: t) else { throw RouteError.badDevice(device) }
        r.title = "\(profile(named: device)?.name ?? target.host) ⟵ \(jump)"
        r.thenCommand = cmd
        r.thenUser = target.user
        return r
    }

    /// La pestaña del salto: su sesión del ssh_config o usuario@equipo directo.
    public func jumpRoute(_ jump: String) throws -> ConnectionRoute {
        if let p = profile(named: jump) { return try route(to: p) }
        guard let e = Endpoint(parsing: jump) else { throw RouteError.badJump(jump) }
        if let p = profile(named: e.host) {                     // «admin@bastion»: la sesión, con ese usuario
            var r = try route(to: p)
            r.alias = nil
            r.target.user = e.user ?? r.target.user
            r.jumps = try resolve(p.proxyJump, seen: [p.name])
            r.jumpSpec = p.proxyJump.isEmpty ? nil : p.proxyJump
            r.target.host = p.endpoint.host
            r.target.port = p.endpoint.port
            return r
        }
        return ConnectionRoute(title: e.host, target: e)
    }

    /// La ruta de una sesión con ProxyJump, pero escribiendo el ssh en el último salto (cuando -J no está permitido).
    public func typedHop(for route: ConnectionRoute) throws -> ConnectionRoute? {
        guard route.thenCommand == nil, route.transport == .ssh, !route.jumps.isEmpty else { return nil }
        let p = route.sessionName.flatMap(profile(named:))
        guard let last = (p?.proxyJump.last ?? route.jumpSpec?.last) else { return nil }
        var r = try jumpRoute(last)
        var target = route.target
        if target.user == nil { target.user = p?.user }
        guard let cmd = ConnectionRoute.hopCommand(to: target, transport: .ssh) else { return nil }
        r.title = route.title
        r.thenCommand = cmd
        r.thenUser = target.user
        r.sessionName = route.sessionName
        return r
    }

    /// Los saltos de cada uno van antes que él (ProxyJump encadenados); un bucle es un error.
    func resolve(_ specs: [String], seen: Set<String>) throws -> [Endpoint] {
        var out: [Endpoint] = []
        for s in specs {
            let e = Endpoint(parsing: s)
            guard let name = profile(named: s)?.name ?? e.flatMap({ profile(named: $0.host)?.name }) else {
                guard let e else { throw RouteError.badJump(s) }
                out.append(e)
                continue
            }
            guard !seen.contains(name) else { throw RouteError.loop(name) }
            let p = profile(named: name)!
            out += try resolve(p.proxyJump, seen: seen.union([name]))
            var end = p.endpoint
            if let u = e?.user, profile(named: s) == nil { end.user = u }     // «admin@bastion»: el usuario escrito
            out.append(end)
        }
        return out
    }

    // MARK: - contraseñas candidatas

    /// Usuarios dueños de una contraseña con nombre: los de las sesiones que la usan.
    public func owners(ofNamed name: String) -> Set<String> {
        Set(profiles.filter { $0.namedCredential == name }.map(\.effectiveUser))
    }

    /// Candidatas en orden para una petición de contraseña (como NetDeck): la con nombre de ese usuario@equipo y la
    /// guardada para él, la de la sesión de la pestaña, la del salto y la por defecto. Cada una con sus dueños:
    /// `CredentialPolicy` descarta las que no son del usuario pedido.
    public func credentialCandidates(for request: PasswordRequest, route: ConnectionRoute?,
                                     defaultCredential: DefaultCredential?) -> [CredentialCandidate] {
        var out: [CredentialCandidate] = []
        func session(_ p: SessionProfile?, user: String, host: String, origin: CredentialCandidate.Origin) {
            if let n = p?.namedCredential { out.append(.init(ref: .named(n), owners: owners(ofNamed: n), origin: origin)) }
            out.append(.init(ref: .device(user, host), owners: [user], origin: origin == .sessionNamed ? .device : origin))
        }
        if let a = request.account, let at = a.lastIndex(of: "@") {
            let host = String(a[a.index(after: at)...])
            session(profiles.first { $0.endpoint.host == host } ?? profile(named: host),
                    user: String(a[..<at]), host: host, origin: .sessionNamed)
        }
        if let route {
            let p = route.sessionName.flatMap(profile(named:))
            session(p, user: route.target.user ?? p?.effectiveUser ?? NSUserName(), host: route.target.host,
                    origin: .sessionNamed)
            if let j = route.jumps.last {
                session(profiles.first { $0.endpoint.host == j.host }, user: j.user ?? NSUserName(), host: j.host,
                        origin: .jumpSession)
            }
        }
        if let d = defaultCredential {
            out.append(.init(ref: .named(d.name), owners: [d.user], origin: .defaultCredential))
        }
        var seen = Set<CredentialRef>()
        return out.filter { seen.insert($0.ref).inserted }
    }
}
