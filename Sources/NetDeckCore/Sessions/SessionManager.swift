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
        switch p.transport {
        case .local:
            var r = ConnectionRoute.local()
            r.title = p.name
            r.sessionName = p.name
            return r
        case .serial:
            guard let line = p.serial, line.isValid else { throw RouteError.badDevice(p.serial?.device ?? p.name) }
            return .serial(line, title: p.name, sessionName: p.name)
        case .ssh, .telnet, .sftp, .ftp:
            break
        }
        // (nombre, equipo o usuario que empiecen por «-» serían opciones de ssh/telnet: -oProxyCommand=…)
        for v in [p.name, p.endpoint.host, p.endpoint.user ?? ""] where v.hasPrefix("-") { throw RouteError.badDevice(v) }
        let jumps = try resolve(p.proxyJump, seen: [p.name])
        // (telnet con salto va como texto a la shell del salto: «ssh -t salto telnet equipo»; nada de «;», «$(…)»…)
        if p.transport == .telnet, !jumps.isEmpty, !Endpoint(host: p.endpoint.host).isShellSafe {
            throw RouteError.badDevice(p.endpoint.host)
        }
        let alias = p.transport == .ssh || p.transport == .sftp ? p.name : nil      // (sftp lee el mismo ssh_config)
        var r = ConnectionRoute(title: p.name, target: p.endpoint, jumps: jumps,
                                transport: p.transport, alias: alias, sessionName: p.name)
        r.authenticationProfile = p.name
        // (con un ProxyCommand suyo en el ssh_config no se comparte: se respeta el suyo)
        if alias != nil, !p.proxyJump.isEmpty, !p.hasProxyCommand { r.configJumps = p.proxyJump }
        return r
    }

    /// «Conectar» del gestor sin guardar: la sesión tal como está en el formulario, con equipo, usuario, puerto y
    /// saltos explícitos (sin el alias: el ssh_config todavía no la tiene así). Los saltos se buscan entre las sesiones
    /// guardadas; la clave privada, «equipo antiguo» y las opciones avanzadas sólo cuentan una vez guardada. Sin
    /// `sessionName`: la contraseña con nombre y el salto de la sesión guardada con ese nombre no valen para otro equipo.
    public func route(unsaved s: EditableSession) throws -> ConnectionRoute {
        var f = SessionFile()
        f.sessions = [s]
        guard let p = SSHConfigParser().parse(f.render()).first(where: { $0.name == s.name }) else {
            throw RouteError.badDevice(s.name)
        }
        var r = try route(to: p)
        if r.alias != nil {
            r.alias = nil
            r.configJumps = nil
            if !r.jumps.isEmpty { r.jumpSpec = r.jumps.map(\.description) }
        }
        r.sessionName = nil
        r.authenticationProfile = nil
        r.transientProfile = s.terminal
        return r
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
            r.configJumps = nil
            r.target.user = e.user ?? r.target.user
            r.jumps = try resolve(p.proxyJump, seen: [p.name])
            r.jumpSpec = p.proxyJump.isEmpty ? nil : p.proxyJump
            r.target.host = p.endpoint.host
            r.target.port = e.port ?? p.endpoint.port
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
        r.transientProfile = route.transientProfile       // («Conectar» sin guardar: su perfil, también por el salto)
        r.manualHop = true
        return r
    }

    /// El ProxyJump actual del ssh_config para una ruta con alias (las pestañas guardadas no lo traen): el mismo
    /// criterio que `route(to:)`.
    public func refreshConfigJumps(_ r: ConnectionRoute) -> ConnectionRoute {
        guard let alias = r.alias, let p = profile(named: alias) else { return r }
        var r = r
        r.configJumps = !p.proxyJump.isEmpty && !p.hasProxyCommand ? p.proxyJump : nil
        return r
    }

    /// Los saltos de cada uno van antes que él (ProxyJump encadenados); un bucle es un error.
    func resolve(_ specs: [String], seen: Set<String>) throws -> [Endpoint] {
        var out: [Endpoint] = []
        for s in specs {
            let e = Endpoint(parsing: s)
            guard let name = profile(named: s)?.name ?? e.flatMap({ profile(named: $0.host)?.name }) else {
                guard let e, !e.host.hasPrefix("-"), e.user?.hasPrefix("-") != true else { throw RouteError.badJump(s) }
                out.append(e)
                continue
            }
            guard !seen.contains(name) else { throw RouteError.loop(name) }
            guard let p = profile(named: name) else { throw RouteError.badJump(s) }
            out += try resolve(p.proxyJump, seen: seen.union([name]))
            var end = p.endpoint
            if profile(named: s) == nil {
                if let u = e?.user { end.user = u }     // («admin@bastion:2222»: lo escrito manda)
                if let port = e?.port { end.port = port }
            }
            // (un salto de otra sesión con equipo o usuario «-…» sería una opción de ssh: «ssh -t -oProxyCommand=…»)
            for v in [end.host, end.user ?? ""] where v.hasPrefix("-") { throw RouteError.badJump(s) }
            out.append(end)
        }
        return out
    }

    // MARK: - contraseñas candidatas

    /// El askpass inicial sólo conoce los extremos de ESTA conexión. Los alias de sus saltos se conservan: buscar
    /// por HostName elegiría la clave de otra sesión al mismo equipo (otro puerto o usuario).
    struct InitialCredentialScope {
        var candidates: [CredentialCandidate]
        var named: String?
    }

    func initialCredentialScope(account: Endpoint, route: ConnectionRoute?) -> InitialCredentialScope {
        guard let route, let user = account.user else { return .init(candidates: [], named: nil) }
        struct Scope: Hashable {
            var endpoint: Endpoint
            var profile: SessionProfile?
            var names: Set<String> { Set([endpoint.host, profile?.name].compactMap { $0?.lowercased() }) }
        }
        func scope(_ endpoint: Endpoint, profile: SessionProfile?) -> Scope {
            var endpoint = endpoint
            if endpoint.user == nil { endpoint.user = profile?.effectiveUser ?? NSUserName() }
            // (un usuario o puerto explícito de otro extremo no hereda su # @clave)
            let own = profile.flatMap { p in
                p.endpoint.host.caseInsensitiveCompare(endpoint.host) == .orderedSame
                    && p.effectiveUser == endpoint.user && (p.port ?? 22) == (endpoint.port ?? 22) ? p : nil
            }
            return Scope(endpoint: endpoint, profile: own)
        }
        func jumps(_ specs: [String], seen: Set<String>) -> [Scope] {
            var out: [Scope] = []
            for spec in specs {
                guard let endpoint = Endpoint(parsing: spec) else { continue }
                guard let p = profile(named: spec) ?? profile(named: endpoint.host) else {
                    out.append(scope(endpoint, profile: nil)); continue
                }
                guard !seen.contains(p.name) else { continue }
                out += jumps(p.proxyJump, seen: seen.union([p.name]))
                var target = p.endpoint
                if profile(named: spec) == nil {
                    if let u = endpoint.user { target.user = u }
                    if let port = endpoint.port { target.port = port }
                }
                out.append(scope(target, profile: p))
            }
            return out
        }
        let selected = (route.authenticationProfile ?? route.alias ?? route.sessionName).flatMap(profile(named:))
        let specs = route.jumpSpec ?? route.configJumps ?? selected?.proxyJump ?? []
        var scopes = jumps(specs, seen: Set([selected?.name].compactMap { $0 }))
        if specs.isEmpty { scopes += route.jumps.map { scope($0, profile: nil) } }
        // (telnet: askpass sólo autentica el ssh al salto, nunca la consola telnet del destino)
        if route.transport == .ssh || route.transport == .sftp { scopes.append(scope(route.target, profile: selected)) }
        let matches = Set(scopes.filter { $0.names.contains(account.host.lowercased()) && $0.endpoint.user == user })
        // (askpass no incluye el puerto: dos etapas con el mismo usuario/equipo son ambiguas)
        guard matches.count == 1, let own = matches.first else { return .init(candidates: [], named: nil) }
        let named = own.profile?.namedCredential
        var candidates: [CredentialCandidate] = []
        if let named { candidates.append(.init(ref: .named(named), owners: [user], origin: .sessionNamed)) }
        candidates.append(.init(ref: .device(user, own.endpoint.host), owners: [user], origin: .device))
        return .init(candidates: candidates, named: named)
    }

    /// Usuarios dueños de una contraseña con nombre: los de las sesiones que la usan.
    public func owners(ofNamed name: String) -> Set<String> {
        Set(profiles.filter { $0.namedCredential == name }.map(\.effectiveUser))
    }

    /// Los equipos que una pestaña puede pedir de verdad: destino y saltos de su ruta (con su nombre de sesión y su
    /// HostName), el de la orden que la app escribe en el salto (`thenCommand`) y los de la última orden «ssh/telnet …»
    /// tecleada (`typed`). Cualquier otro «usuario@equipo» en pantalla lo ha escrito el propio equipo remoto.
    public func expectedHosts(route: ConnectionRoute?, typed: Set<String> = []) -> Set<String> {
        var out = Set<String>()
        func add(_ host: String) {
            out.insert(host.lowercased())
            for p in profiles where p.name == host || p.endpoint.host == host {
                out.insert(p.name.lowercased())
                out.insert(p.endpoint.host.lowercased())
            }
        }
        typed.forEach(add)
        guard let route else { return out }
        add(route.target.host)
        route.alias.map(add)
        route.sessionName.map(add)
        route.authenticationProfile.map(add)
        route.jumps.forEach { add($0.host) }
        if let t = route.thenCommand.flatMap(CommandLineUser.parse) { add(t.host) }
        return out
    }

    /// Candidatas en orden para una petición de contraseña (como NetDeck): la con nombre de ese usuario@equipo y la
    /// guardada para él, la de la sesión de la pestaña, la del salto y la por defecto. Cada una con sus dueños:
    /// `CredentialPolicy` descarta las que no son del usuario pedido.
    /// El «usuario@equipo» del prompt sólo cuenta si ese equipo es uno de `expectedHosts` (un equipo hostil podría
    /// escribir «admin@core-01's password:» para llevarse la de core-01), salvo `trustAccount`: la pregunta la ha
    /// escrito el propio ssh (askpass) o la app.
    public func credentialCandidates(for request: PasswordRequest, route: ConnectionRoute?,
                                     defaultCredential: DefaultCredential?, trustAccount: Bool = false,
                                     typedHosts: Set<String> = [], typedTarget: Endpoint? = nil) -> [CredentialCandidate] {
        if !trustAccount, let account = request.account, let at = account.lastIndex(of: "@"),
           !expectedHosts(route: route, typed: typedHosts).contains(String(account[account.index(after: at)...]).lowercased()) {
            return []                              // (tampoco la predeterminada sale hacia otro equipo)
        }
        var out: [CredentialCandidate] = []
        func session(_ p: SessionProfile?, user: String, host: String, origin: CredentialCandidate.Origin) {
            if let n = p?.namedCredential { out.append(.init(ref: .named(n), owners: owners(ofNamed: n), origin: origin)) }
            out.append(.init(ref: .device(user, p?.endpoint.host ?? host), owners: [user], origin: origin == .sessionNamed ? .device : origin))
        }
        if let a = request.account, let at = a.lastIndex(of: "@"),
           trustAccount || expectedHosts(route: route, typed: typedHosts).contains(String(a[a.index(after: at)...]).lowercased()) {
            let host = String(a[a.index(after: at)...])
            let user = String(a[..<at])
            func matches(_ p: SessionProfile) -> Bool {
                guard p.effectiveUser == user, p.name.caseInsensitiveCompare(host) == .orderedSame
                        || p.endpoint.host.caseInsensitiveCompare(host) == .orderedSame else { return false }
                if let t = typedTarget {
                    let selected = profile(named: t.host)
                    if t.host.caseInsensitiveCompare(host) == .orderedSame
                        || selected?.endpoint.host.caseInsensitiveCompare(host) == .orderedSame {
                        return (p.port ?? 22) == (t.port ?? selected?.port ?? 22)
                    }
                }
                if let route {
                    let endpoints = ([route.target] + route.jumps).filter {
                        $0.host.caseInsensitiveCompare(p.endpoint.host) == .orderedSame && ($0.user ?? p.effectiveUser) == user
                    }
                    if !endpoints.isEmpty { return endpoints.allSatisfy { ($0.port ?? 22) == (p.port ?? 22) } }
                }
                return true
            }
            // (la orden puede nombrar el alias aunque ssh pregunte por su HostName)
            let named = typedHosts.compactMap(profile(named:)).filter(matches)
            let exact = profile(named: host).flatMap { matches($0) ? $0 : nil }
            let byHost = profiles.filter { $0.endpoint.host.caseInsensitiveCompare(host) == .orderedSame && matches($0) }
            let selected = route.flatMap { ($0.authenticationProfile ?? $0.alias ?? $0.sessionName).flatMap(profile(named:)) }.flatMap {
                matches($0) ? $0 : nil
            }
            session(selected ?? (named.count == 1 ? named.first : exact) ?? (byHost.count == 1 ? byHost.first : nil),
                    user: user, host: host, origin: .sessionNamed)
        }
        if let route {
            let p = (route.authenticationProfile ?? route.alias ?? route.sessionName).flatMap(profile(named:)).flatMap {
                $0.endpoint.host.caseInsensitiveCompare(route.target.host) == .orderedSame
                    && $0.effectiveUser == (route.target.user ?? $0.effectiveUser)
                    && ($0.port ?? 22) == (route.target.port ?? 22) ? $0 : nil
            }
            session(p, user: route.target.user ?? p?.effectiveUser ?? NSUserName(), host: route.target.host,
                    origin: .sessionNamed)
            if let j = route.jumps.last {
                let user = j.user ?? NSUserName()
                let matching = profiles.filter {
                    $0.endpoint.host.caseInsensitiveCompare(j.host) == .orderedSame && $0.effectiveUser == user
                        && ($0.port ?? 22) == (j.port ?? 22)
                }
                session(matching.count == 1 ? matching.first : nil, user: user, host: j.host, origin: .jumpSession)
            }
        }
        if let d = defaultCredential {
            out.append(.init(ref: .named(d.name), owners: [d.user], origin: .defaultCredential))
        }
        var seen = Set<CredentialRef>()
        return out.filter { seen.insert($0.ref).inserted }
    }
}
