import AppKit
import NetDeckCore
import Observation

/// El explorador de archivos de una pestaña SFTP/FTP (tipo Cyberduck): su conexión propia (ssh -s sftp o FTP), la
/// carpeta en la que está, lo desplegado en árbol y lo elegido. La consola sftp de la pestaña va aparte.
@MainActor @Observable
final class RemoteBrowser {
    enum State: Equatable {
        case idle, connecting, connected
        /// FTP: hace falta la contraseña (con el motivo, si la guardada no ha valido).
        case needsPassword(String?)
        case failed(String)
    }

    enum SortKey: String { case name, size, permissions, modified }

    /// Para el askpass (contraseñas que ha dado) y el ledger: distinto del de la consola.
    let id = UUID()
    let route: ConnectionRoute
    private(set) var state = State.idle
    private(set) var fs: (any RemoteFileSystem)?
    private(set) var path = ""
    private(set) var home = "/"
    private(set) var entries: [RemoteEntry] = []
    /// Árbol: carpetas desplegadas y lo que hay dentro.
    var expanded: Set<String> = []
    private(set) var children: [String: [RemoteEntry]] = [:]
    private(set) var loading: Set<String> = []
    var selection: Set<String> = []
    var filter = ""
    var showHidden = false
    var sortKey = SortKey.name
    var ascending = true
    private(set) var back: [String] = []
    private(set) var forward: [String] = []
    /// Lo último que ha fallado (se ve abajo, en rojo).
    var message: String?
    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    /// La contraseña FTP que se está probando (y si vino del Llavero).
    @ObservationIgnored private var probing: CredentialRef?

    init(route: ConnectionRoute, model: AppModel) {
        self.route = route
        self.model = model
    }

    var isFTP: Bool { route.transport == .ftp }
    var user: String { route.target.user ?? model?.sessions.profile(named: route.sessionName ?? "")?.effectiveUser ?? NSUserName() }
    var label: String { "\(route.transport.label) \(user)@\(route.target.host)" }

    // MARK: conexión

    func connect() {
        guard state != .connecting, state != .connected else { return }
        if isFTP { connectFTP(password: nil, save: nil) } else { connectSFTP() }
    }

    func reconnect() {
        disconnect()
        connect()
    }

    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        if let fs { Task { await fs.close() } }
        fs = nil
        if let p = probing { model?.ledger.release(p) }
        probing = nil
        state = .idle
    }

    /// «Cancelar» mientras conecta: corta ya (FTP cierra el socket; SFTP termina ssh) y lo deja en «no conectado».
    func cancelConnect() {
        guard state == .connecting else { return }
        disconnect()
        state = .failed(L("Conexión cancelada"))
    }

    private func connectSFTP() {
        guard let model else { return }
        state = .connecting
        message = nil
        let r = route
        // (desarrollo y capturas: NETDECK_SFTP_SERVER habla SFTP directamente, sin ssh ni red)
        let dev = ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] != nil
            ? ProcessInfo.processInfo.environment["NETDECK_SFTP_SERVER"] : nil
        guard let cmd = dev.map({ ($0, [String]()) }) ?? r.sftpSubsystemCommand else {
            state = .failed(L("Equipo no válido: «\(r.target.host)»"))
            return
        }
        var env = TerminalEnvironment.prepare(ProcessInfo.processInfo.environment, forSSH: true,
                                              sendLocale: UserDefaults.standard.bool(forKey: AppSettings.sendLocaleKey))
        env[Askpass.flag] = nil
        env.merge(Askpass.environment(executable: Bundle.main.executablePath ?? CommandLine.arguments[0],
                                      configPath: model.settings.sshConfigURL.path,
                                      defaultCredential: model.settings.defaultCredential, session: id,
                                      manual: !model.settings.sessionAutoPassword)) { $1 }
        let label = label, sid = id, ledger = model.ledger
        DebugLog.log("explorador", "«\(r.title)» conecta: \(cmd.0) \(cmd.1.joined(separator: " "))")
        connectTask = Task {
            do {
                let fs = try await SFTPFileSystem.connect(label: label, executable: cmd.0, arguments: cmd.1, environment: env)
                Askpass.takeGiven(session: sid).forEach(ledger.confirm)       // (la del askpass ha valido)
                try await self.connected(fs)
            } catch {
                _ = Askpass.takeGiven(session: sid)
                self.fail(error)
            }
        }
    }

    /// FTP: la contraseña del Llavero si la regla de usuario lo permite (y no ha fallado hace poco); si no, se pide.
    func connectFTP(password typed: String?, save: CredentialRef?) {
        guard let model else { return }
        state = .connecting
        message = nil
        let r = route, user = user, label = label
        let request = PasswordRequest(line: "", account: "\(user)@\(r.target.host)")
        // FTP va sin cifrar: sólo la de usuario@equipo o la «# @clave» de esta sesión; nunca la por defecto (cuenta
        // AD) ni la de un salto, que acabarían viajando en claro.
        let own = model.sessions.profile(named: r.sessionName ?? "")?.namedCredential.map(CredentialRef.named)
        let candidates = model.sessions.credentialCandidates(for: request, route: r, defaultCredential: nil, trustAccount: true)
            .filter { $0.ref == .device(user, r.target.host) || ($0.ref == own && $0.origin == .sessionNamed) }
        let store = model.store, ledger = model.ledger, policy = model.policy, auto = model.settings.sessionAutoPassword
        connectTask = Task {
            var ref: CredentialRef?
            var password = typed
            if password == nil, auto {
                // (Llavero fuera del hilo principal)
                let found: (CredentialRef, String)? = await Task.detached {
                    let have = candidates.filter { store.contains($0.ref) }
                    guard case .inject(let c) = policy.decide(request, commandUser: nil, candidates: have, isBlocked: ledger.isBlocked),
                          ledger.beginProbe(c) == .go else { return nil }
                    guard let pw = try? store.password(for: c) else { ledger.release(c); return nil }
                    return (c, pw)
                }.value
                if let found { (ref, password) = (found.0, found.1) }
            }
            guard !Task.isCancelled else { if let ref { ledger.release(ref) }; return }     // («Cancelar» mientras se leía)
            guard let password else { self.state = .needsPassword(nil); return }
            self.probing = ref
            do {
                // (si más tarde una transferencia recibe 530, la contraseña ha cambiado: bloqueada como en las pestañas)
                let used = ref
                let rejected: @Sendable () -> Void = { if let used { ledger.markFailed(used) } }
                let fs = try await FTPFileSystem.connect(label: label, host: r.target.host, port: r.target.port,
                                                         user: user, password: password, rejected: rejected)
                if let ref { ledger.confirm(ref) }
                self.probing = nil
                if let save {
                    let saved: String? = await Task.detached {
                        do { try store.save(password, for: save); ledger.reset(save); ledger.confirm(save); return nil } catch {
                            return error.localizedDescription
                        }
                    }.value
                    model.keychainRevision += 1
                    if let saved { model.status = "✗ \(saved)" } else { model.status = L("🔑 «\(save.account)» guardada en el Llavero") }
                }
                try await self.connected(fs)
            } catch is FTPLoginError {
                self.probing = nil
                // (el servidor ya ha dicho 530: aunque se haya cancelado, esa contraseña no vale y queda bloqueada)
                if let ref { ledger.markFailed(ref) }
                guard !Task.isCancelled else { return }         // (cancelada: sin aviso)
                if let ref {
                    self.state = .needsPassword(L("«\(ref.account)» no ha valido: bloqueada 15 min en todas las pestañas"))
                    model.status = L("🔑 «\(ref.account)» no ha valido: bloqueada 15 min en todas las pestañas")
                } else {
                    self.state = .needsPassword(L("Usuario o contraseña no válidos"))
                }
            } catch {
                if let ref { ledger.release(ref) }
                self.probing = nil
                self.fail(error)
            }
        }
    }

    /// Dónde guardar la contraseña FTP que se escribe: la con nombre de la sesión o la de usuario@equipo.
    var saveTarget: CredentialRef {
        if let n = model?.sessions.profile(named: route.sessionName ?? "")?.namedCredential { return .named(n) }
        return .device(user, route.target.host)
    }

    private func connected(_ fs: any RemoteFileSystem) async throws {
        guard !Task.isCancelled else { await fs.close(); return }
        self.fs = fs
        home = (try? await fs.home()) ?? "/"
        if ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] != nil,
           let d = ProcessInfo.processInfo.environment["NETDECK_SFTP_DIR"] { home = d }    // (capturas)
        state = .connected
        DebugLog.log("explorador", "«\(route.title)» conectado en \(home)")
        await go(home, record: false)
    }

    private func fail(_ e: Error) {
        guard !Task.isCancelled else { return }
        let text = e.localizedDescription
        state = .failed(text)
        ErrorLog.error("explorador", "«\(route.title)»: \(text)")
    }

    // MARK: navegar

    func open(_ p: String) { Task { await go(p) } }

    func go(_ p: String, record: Bool = true) async {
        guard let fs else { return }
        do {
            let list = try await fs.list(p)
            if record, !path.isEmpty, path != p { back.append(path); forward = [] }
            path = p
            entries = list
            selection = []
            expanded = []
            children = [:]
            message = nil
        } catch {
            message = "✗ \(error.localizedDescription)"
            if isConnectionLost(error) { state = .failed(error.localizedDescription) }
        }
    }

    func goBack() {
        guard let p = back.popLast() else { return }
        forward.append(path)
        Task { await go(p, record: false) }
    }

    func goForward() {
        guard let p = forward.popLast() else { return }
        back.append(path)
        Task { await go(p, record: false) }
    }

    func goUp() { if path != "/" { open(RemotePath.parent(path)) } }

    func refresh() {
        let open = expanded
        Task {
            await go(path, record: false)
            for p in open.sorted() { await expand(p) }
        }
    }

    func toggle(_ e: RemoteEntry) {
        if expanded.contains(e.path) {
            expanded.remove(e.path)
        } else {
            Task { await expand(e.path) }
        }
    }

    private func expand(_ p: String) async {
        guard let fs else { return }
        loading.insert(p)
        defer { loading.remove(p) }
        do {
            children[p] = try await fs.list(p)
            expanded.insert(p)
        } catch {
            message = "✗ \(RemotePath.name(p)): \(error.localizedDescription)"
        }
    }

    private func isConnectionLost(_ e: Error) -> Bool {
        let t = e.localizedDescription
        return t == L("Se ha perdido la conexión") || t == L("Se ha cerrado la conexión") || t == L("Conexión cerrada")
    }

    // MARK: lo que se ve

    /// Filas del árbol: (entrada, nivel), en orden, con el filtro y lo oculto.
    var rows: [(entry: RemoteEntry, depth: Int)] {
        var out: [(RemoteEntry, Int)] = []
        func add(_ list: [RemoteEntry], _ depth: Int) {
            for e in sorted(list) where visible(e) {
                out.append((e, depth))
                if e.isDirectory, expanded.contains(e.path), let c = children[e.path] { add(c, depth + 1) }
            }
        }
        add(entries, 0)
        return out
    }

    private func visible(_ e: RemoteEntry) -> Bool {
        if !showHidden, e.name.hasPrefix(".") { return false }
        let q = filter.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || e.isDirectory || e.name.localizedCaseInsensitiveContains(q)
    }

    private func sorted(_ list: [RemoteEntry]) -> [RemoteEntry] {
        list.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let r: Bool = switch sortKey {
            case .name: a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size: (a.size ?? 0) < (b.size ?? 0)
            case .permissions: (a.permissions ?? 0) < (b.permissions ?? 0)
            case .modified: (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
            }
            return ascending ? r : !r
        }
    }

    func sort(by k: SortKey) {
        if sortKey == k { ascending.toggle() } else { sortKey = k; ascending = true }
    }

    var selectedEntries: [RemoteEntry] { rows.map(\.entry).filter { selection.contains($0.path) } }

    /// Lo que hay en una carpeta (de lo ya leído): para avisar antes de pisar algo.
    func known(in dir: String) -> [RemoteEntry]? { dir == path ? entries : children[dir] }

    // MARK: cambios

    func makeFolder(_ name: String) {
        guard let fs, RemotePath.isValidName(name) else { message = L("✗ Nombre no válido"); return }
        let p = RemotePath.join(path, name)
        Task {
            do { try await RemoteOps.withTimeout(RemoteOps.callTimeout) { try await fs.makeDirectory(p) }; refresh() } catch {
                message = "✗ \(error.localizedDescription)"
            }
        }
    }

    func rename(_ e: RemoteEntry, to name: String) {
        guard let fs, RemotePath.isValidName(name), name != e.name else { if name != e.name { message = L("✗ Nombre no válido") }; return }
        let to = RemotePath.join(RemotePath.parent(e.path), name)
        Task {
            do { try await RemoteOps.withTimeout(RemoteOps.callTimeout) { try await fs.rename(e.path, to: to) }; refresh() } catch {
                message = "✗ \(error.localizedDescription)"
            }
        }
    }

    /// Borra en segundo plano (la ventana sigue respondiendo), con tope por petición; se ve «Borrando…» mientras dura.
    func delete(_ list: [RemoteEntry]) {
        guard let fs else { return }
        message = list.count == 1 ? L("Borrando «\(list[0].name)»…") : L("Borrando \(list.count) elementos…")
        Task {
            var failed = false
            for e in list {
                do { try await RemoteOps.removeRecursively(fs, e, timeout: RemoteOps.callTimeout) } catch {
                    message = "✗ \(e.name): \(error.localizedDescription)"
                    ErrorLog.error("explorador", "«\(route.title)»: no se ha podido borrar \(e.name): \(error.localizedDescription)")
                    failed = true
                    break
                }
            }
            if !failed { message = nil }
            refresh()
        }
    }
}

// MARK: - transferencias

/// Una copia en curso (o acabada): de un servidor a otro (en memoria), del servidor al Mac o del Mac al servidor.
@MainActor @Observable
final class TransferJob: Identifiable {
    enum State: Equatable { case queued, running, done, failed(String), cancelled }

    let id = UUID()
    let title: String
    let from: String
    let to: String
    var state = State.queued
    var done: Int64 = 0
    var total: Int64?
    var files = 0
    /// Archivos cuyo MD5 se ha comprobado en el destino.
    var verified = 0
    var started = Date()
    @ObservationIgnored var task: Task<Void, Never>?

    init(title: String, from: String, to: String) {
        self.title = title
        self.from = from
        self.to = to
    }

    var fraction: Double? { total.map { $0 > 0 ? min(1, Double(done) / Double($0)) : 1 } }
    var finished: Bool { if case .running = state { false } else if case .queued = state { false } else { true } }

    /// Bytes por segundo (para «12,3 MB/s»).
    var speed: Double { let s = Date().timeIntervalSince(started); return s > 0.5 ? Double(done) / s : 0 }

    func cancel() { task?.cancel() }

    /// Un archivo más copiado (el progreso, a su tamaño: no retrocede si llega tarde un aviso anterior).
    func finishedFile(base: Int64, size: Int64?, verified: Bool) {
        files += 1
        if verified { self.verified += 1 }
        done = max(done, base + (size ?? 0))
    }
}

/// Las copias de todas las pestañas (se ven en la parte de abajo de cualquier explorador).
@MainActor @Observable
final class TransferCenter {
    private(set) var jobs: [TransferJob] = []
    /// ¿Comprobar el MD5 de cada archivo al acabar? (lo pone la app con el ajuste)
    @ObservationIgnored var verify: () -> Bool = { true }
    /// Al acabar una copia: refrescar el explorador de destino.
    @ObservationIgnored var onFinish: ((TransferJob) -> Void)?

    var active: Int { jobs.filter { !$0.finished }.count }

    func clearFinished() { jobs.removeAll { $0.finished } }

    /// Entre dos servidores (o el mismo): lectura y escritura a la vez, en memoria; nada pasa por el disco del Mac.
    func bridge(_ entries: [RemoteEntry], from src: any RemoteFileSystem, to dst: any RemoteFileSystem, dir: String,
                refresh: @escaping @MainActor () -> Void) {
        let job = TransferJob(title: entries.count == 1 ? entries[0].name : L("\(entries.count) elementos"),
                              from: src.label, to: "\(dst.label):\(dir)")
        let verify = verify()
        run(job, refresh: refresh) { job in
            let items = try await Self.plan(entries, in: src)
            await MainActor.run { job.total = items.compactMap(\.size).reduce(0, +) }
            for it in items {
                try Task.checkCancellation()
                guard RemoteOps.isSafeRelative(it.relative) else { continue }  // (nombres del origen que saldrían de `dir`)
                let target = RemotePath.join(dir, it.relative)
                if it.isDirectory {
                    try? await dst.makeDirectory(target)                       // (si ya existe, se sigue)
                    continue
                }
                let base = await MainActor.run { job.done }
                try await Self.copy(from: { try await src.openRead(it.source) },
                                    to: { try await AtomicRemoteWriter.open(dst, target, verify: verify) }) { n in
                    Task { @MainActor in job.done = max(job.done, base + n) }
                }
                await MainActor.run { job.finishedFile(base: base, size: it.size, verified: verify) }
            }
        }
    }

    /// Del servidor a una carpeta del Mac (sin pisar nada: «nombre 2.ext» si ya existe).
    func download(_ entries: [RemoteEntry], from src: any RemoteFileSystem, to folder: URL) {
        let job = TransferJob(title: entries.count == 1 ? entries[0].name : L("\(entries.count) elementos"),
                              from: src.label, to: AppPaths.tilde(folder.path))
        let verify = verify()
        run(job, refresh: {}) { job in
            let items = try await Self.plan(entries, in: src)
            await MainActor.run { job.total = items.compactMap(\.size).reduce(0, +) }
            var roots: [String: URL] = [:]                                     // (raíz pedida → nombre libre en el Mac)
            for it in items {
                try Task.checkCancellation()
                let parts = it.relative.split(separator: "/").map(String.init)
                guard let first = parts.first, parts.allSatisfy(RemotePath.isValidName) else { continue }
                let root = roots[first] ?? Self.freeName(folder.appendingPathComponent(first))
                roots[first] = root
                let url = parts.dropFirst().reduce(root) { $0.appendingPathComponent($1) }
                if it.isDirectory {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    continue
                }
                let base = await MainActor.run { job.done }
                try await Self.copy(from: { try await src.openRead(it.source) },
                                    to: { try LocalFileWriter(url: url, verify: verify) }) { n in
                    Task { @MainActor in job.done = max(job.done, base + n) }
                }
                await MainActor.run { job.finishedFile(base: base, size: it.size, verified: verify) }
            }
        }
    }

    /// Del Mac al servidor (archivos o carpetas enteras).
    func upload(_ urls: [URL], to dst: any RemoteFileSystem, dir: String, refresh: @escaping @MainActor () -> Void) {
        let job = TransferJob(title: urls.count == 1 ? urls[0].lastPathComponent : L("\(urls.count) elementos"),
                              from: L("Este Mac"), to: "\(dst.label):\(dir)")
        let verify = verify()
        run(job, refresh: refresh) { job in
            let items = try Self.localPlan(urls)
            await MainActor.run { job.total = items.compactMap(\.size).reduce(0, +) }
            for it in items {
                try Task.checkCancellation()
                guard RemoteOps.isSafeRelative(it.relative) else { continue }
                let target = RemotePath.join(dir, it.relative)
                if it.isDirectory { try? await dst.makeDirectory(target); continue }
                let base = await MainActor.run { job.done }
                try await Self.copy(from: { try LocalFileReader(url: URL(fileURLWithPath: it.source)) },
                                    to: { try await AtomicRemoteWriter.open(dst, target, verify: verify) }) { n in
                    Task { @MainActor in job.done = max(job.done, base + n) }
                }
                await MainActor.run { job.finishedFile(base: base, size: it.size, verified: verify) }
            }
        }
    }

    private func run(_ job: TransferJob, refresh: @escaping @MainActor () -> Void,
                     _ body: @escaping @Sendable (TransferJob) async throws -> Void) {
        jobs.insert(job, at: 0)
        // (como mucho 30: fuera las acabadas más antiguas; sin leer `jobs` mientras se cambia)
        var extra = jobs.count - 30
        if extra > 0 {
            let old = jobs.reversed().filter { $0.finished }.prefix(extra).map(\.id)
            extra = 0
            jobs.removeAll { old.contains($0.id) }
        }
        DebugLog.log("transferencia", "«\(job.title)»: \(job.from) → \(job.to)")
        job.state = .running
        job.started = Date()
        job.task = Task {
            do {
                try await body(job)
                job.state = .done
                DebugLog.log("transferencia", "«\(job.title)» acabada (\(job.files) archivos, \(job.done) bytes)")
            } catch {
                job.state = Task.isCancelled ? .cancelled : .failed(error.localizedDescription)
                if !Task.isCancelled { ErrorLog.error("transferencia", "«\(job.title)» \(job.from) → \(job.to): \(error.localizedDescription)") }
            }
            refresh()
            onFinish?(job)
        }
    }

    /// Abre origen y destino; si el destino no se puede abrir, el origen se cierra (no deja conexiones colgadas).
    nonisolated private static func copy(from open: @Sendable () async throws -> any RemoteReader,
                                         to create: @Sendable () async throws -> any RemoteWriter,
                                         progress: @escaping @Sendable (Int64) -> Void) async throws {
        let reader = try await open()
        let writer: any RemoteWriter
        do { writer = try await create() } catch {
            await reader.close()
            throw error
        }
        try await Transfer.copy(from: reader, to: writer, progress: progress)
    }

    nonisolated private static func plan(_ entries: [RemoteEntry], in fs: any RemoteFileSystem) async throws -> [TransferItem] {
        var out: [TransferItem] = []
        for e in entries {
            var items = try await RemoteOps.plan(fs, e)
            if !e.isDirectory, items.first?.size == nil, let n = await fs.size(of: e.path) { items[0].size = n }
            out += items
        }
        return out
    }

    /// Lo que cuelga de unas rutas del Mac (sin seguir enlaces).
    nonisolated static func localPlan(_ urls: [URL]) throws -> [TransferItem] {
        var out: [TransferItem] = []
        let fm = FileManager.default
        for u in urls {
            let name = u.lastPathComponent
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                let size = (try? fm.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.int64Value
                out.append(TransferItem(source: u.path, relative: name, isDirectory: false, size: size))
                continue
            }
            out.append(TransferItem(source: u.path, relative: name, isDirectory: true))
            guard let walk = fm.enumerator(at: u, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]) else { continue }
            for case let f as URL in walk {
                let v = try? f.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey])
                if v?.isSymbolicLink == true { continue }
                let rel = name + "/" + f.path.dropFirst(u.path.count + 1)
                out.append(TransferItem(source: f.path, relative: rel, isDirectory: v?.isDirectory == true,
                                        size: v?.fileSize.map(Int64.init)))
                if out.count > RemoteOps.maxItems { throw RemoteError(L("Más de \(RemoteOps.maxItems) archivos: cópialos por partes")) }
            }
        }
        return out
    }

    /// «informe.txt» → «informe 2.txt» si ya existe en el Mac.
    nonisolated static func freeName(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let ext = url.pathExtension, base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        for i in 2...999 {
            let u = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            if !fm.fileExists(atPath: u.path) { return u }
        }
        return dir.appendingPathComponent("\(base) \(UUID().uuidString.prefix(6))" + (ext.isEmpty ? "" : ".\(ext)"))
    }
}
