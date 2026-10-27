import NetDeckCore
import SwiftUI

// Túneles SSH (Herramientas → Túneles SSH… o el botón de la barra): la lista con su estado a la izquierda y el túnel
// elegido a la derecha. Guardar escribe tuneles.json; sólo «Iniciar» arranca un ssh (nunca al abrir la app) y al salir
// de la app se paran todos (`AppDelegate.applicationWillTerminate`).

extension AppModel {
    func reloadTunnels() {
        let r = TunnelLibrary.load()
        tunnels = r.library
        tunnelsError = r.error
        tunnelWarnings = r.warnings
        if let e = r.error {
            ErrorLog.error("tuneles", e)
            status = "✗ " + e
        }
        r.warnings.forEach { ErrorLog.warning("tuneles", $0) }
    }

    /// Guarda la lista (y para y olvida los que ya no están). nil si ha ido bien; si no, el motivo.
    func saveTunnels(_ lib: TunnelLibrary) -> String? {
        do {
            try lib.save(setAsideUnusable: tunnelsError != nil)
            let gone = tunnels.tunnels.map(\.id).filter { id in !lib.tunnels.contains { $0.id == id } }
            tunnels = lib
            tunnelsError = nil
            tunnelWarnings = []
            for id in gone { Task { await tunnelRunner.forget(id) } }
            status = L("Túneles guardados (\(lib.tunnels.count)) en \(AppPaths.tilde(TunnelLibrary.defaultURL.path))")
            return nil
        } catch {
            ErrorLog.error("tuneles", "no se han podido guardar: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    /// Inicia un túnel guardado (sólo desde un clic): la ruta de su sesión, con el ssh_config de Ajustes y la conexión al
    /// salto compartida como las pestañas; la contraseña, si hace falta, por el askpass (en una ventana).
    func startTunnel(_ t: Tunnel) {
        guard !core.renamingCredential else { status = "✗ " + L("Espera a que termine el renombrado de la credencial"); return }
        guard !tunnelRunner.state(t.id).isRunning else { return }
        do {
            let route = try t.route(using: sessions)
            let args = try t.arguments(route: route, sharing: AppSettings.jumpSharing, configFile: AppSettings.sshConfigFile)
            var env = TerminalEnvironment.prepare(ProcessInfo.processInfo.environment, forSSH: true, sendLocale: settings.sendLocale)
            env[Askpass.flag] = nil
            if route.usesPasswords {
                let sid = UUID()
                tunnelAskpass[t.id] = sid
                env.merge(Askpass.environment(executable: Bundle.main.executablePath ?? CommandLine.arguments[0],
                                              configPath: settings.sshConfigURL.path,
                                              session: sid, manual: !settings.sessionAutoPassword,
                                              profile: route.sessionName, route: route)) { $1 }
            }
            tunnelRunner.start(t, executable: "/usr/bin/ssh", arguments: args, environment: env)
            // (un rechazo síncrono repetido puede no emitir otro onChange)
            if !tunnelRunner.state(t.id).isRunning, let sid = tunnelAskpass.removeValue(forKey: t.id) {
                _ = Askpass.takeGiven(session: sid)
            }
        } catch {
            tunnelRunner.markFailed(t.id, error.localizedDescription)          // (y `tunnelChanged` lo avisa)
        }
    }

    func stopTunnel(_ id: Tunnel.ID) {
        Task { await tunnelRunner.stop(id) }
    }

    /// Cambio de estado: confirma la contraseña que ha dado el askpass (activo) o la descarta, y avisa de los errores.
    func tunnelChanged(_ id: Tunnel.ID, _ state: TunnelState) {
        let name = tunnels.tunnel(id)?.name ?? "?"
        switch state {
        case .active:
            if let sid = tunnelAskpass.removeValue(forKey: id) { Askpass.takeGiven(session: sid).forEach(ledger.confirmDirect) }
            status = L("Túnel «\(name)» activo")
        case .failed(let why):
            // (se confirman las que entraron, p. ej. la del salto; la que no valía no se bloquea: es de la sesión)
            if let sid = tunnelAskpass.removeValue(forKey: id) {
                Askpass.settleAfterExit(session: sid, ledger: ledger) { tunnelRunner.authenticationRejection(for: id) }
            }
            ErrorLog.warning("tuneles", "«\(name)»: \(why)")
            status = L("✗ Túnel «\(name)»: \(why)")
        case .stopped:
            if let sid = tunnelAskpass.removeValue(forKey: id) { _ = Askpass.takeGiven(session: sid) }
        case .starting:
            break
        }
    }
}

/// Si matan la app con una señal (kill, Ctrl+C en «swift run»), `applicationWillTerminate` no llega: antes de morir se
/// paran los túneles (sus ssh van en sesión propia y seguirían abiertos) y luego la señal hace lo de siempre. Con un
/// manejador vacío y no con SIG_IGN: lo ignorado lo heredarían las shells y los ssh de las pestañas.
@MainActor
enum TunnelSignals {
    private static var sources: [DispatchSourceSignal] = []

    static func install() {
        guard sources.isEmpty else { return }
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { _ in }
            sigaction(sig, &action, nil)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                MainActor.assumeIsolated { AppCore.shared.tunnelRunner.stopAll() }
                signal(sig, SIG_DFL)
                raise(sig)
            }
            src.resume()
            sources.append(src)
        }
    }
}

struct TunnelSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @Stored private var library = TunnelLibrary()
    @Stored private var selected: Tunnel.ID?
    @Stored private var draft = Tunnel(name: "tunel")
    /// Lo guardado del elegido (nil: nuevo, sin guardar).
    @Stored private var baseline: Tunnel?
    /// Por una sesión guardada (si no, usuario@equipo escrito).
    @Stored private var bySession = true
    @Stored private var message = ""
    @Stored private var loaded = false
    @Stored private var busy = false

    private var dirty: Bool { baseline != draft }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                list.frame(width: 260)
                NeonLine(vertical: true, color: t.panel)
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            NeonLine(color: t.panel)
            footer
        }
        .frame(width: 860, height: 560)
        .background(SwiftUI.Color(t.background))
        .onAppear(perform: load)
    }

    // MARK: lista

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("TÚNELES")).font(t.ui(13, .heavy)).tracking(3).foregroundStyle(SwiftUI.Color(t.accent))
                Text("\(library.tunnels.count)").font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim))
                Spacer()
                if dirty { Text(L("● sin guardar")).font(t.ui(10, .bold)).foregroundStyle(SwiftUI.Color(t.warning)) }
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(library.tunnels) { tu in row(tu, on: selected == tu.id) { choose(tu.id) } }
                    if baseline == nil {
                        row(draft, on: true, unsaved: true) {}
                    }
                }
                .padding(.horizontal, 8)
            }
            NeonLine(color: t.panel)
            HStack(spacing: 6) {
                IconButton(icon: "plus") { choose(nil) }.help(L("Nuevo")).disabled(busy)
                IconButton(icon: "plus.square.on.square") { duplicate() }.help(L("Duplicar")).disabled(busy)
                IconButton(icon: "trash") { act { await remove() } }.help(L("Borrar…")).disabled(busy || baseline == nil)
                Spacer()
            }
            .padding(8)
        }
        .background(SwiftUI.Color(t.bar))
    }

    private func color(_ s: TunnelState) -> RGB {
        switch s {
        case .stopped: t.dim
        case .starting: t.accent                  // (el «warning» de algunos temas se confunde con el apagado)
        case .active: t.good
        case .failed: t.bad
        }
    }

    private func stateText(_ s: TunnelState) -> String {
        switch s {
        case .stopped: L("detenido")
        case .starting: L("iniciando…")
        case .active: L("activo")
        case .failed(let why): L("error: \(why)")
        }
    }

    /// «L 127.0.0.1:8080 → 192.0.2.10:80 · core-01»
    private func summary(_ tu: Tunnel) -> String {
        let via = tu.session.trimmingCharacters(in: .whitespaces).isEmpty ? tu.server : tu.session
        let fwd = tu.kind == .dynamic ? "SOCKS \(tu.listen):\(tu.listenPort)"
            : "\(tu.kind.flag.dropFirst()) \(tu.listen):\(tu.listenPort) → \(tu.targetHost):\(tu.targetPort)"
        return "\(fwd) · \(via)"
    }

    private func row(_ tu: Tunnel, on: Bool, unsaved: Bool = false, tap: @escaping () -> Void) -> some View {
        let s = unsaved ? TunnelState.stopped : model.tunnelRunner.state(tu.id)
        return HStack(spacing: 8) {
            Circle().fill(SwiftUI.Color(color(s))).frame(width: 9, height: 9)
                .shadow(color: SwiftUI.Color(color(s)).opacity(s == .active ? 0.8 : 0), radius: t.glow(4))
            VStack(alignment: .leading, spacing: 1) {
                Text(tu.name).font(t.ui(12, .semibold)).lineLimit(1)
                Text(unsaved ? L("(nuevo, sin guardar)") : summary(tu)).font(t.ui(9.5)).opacity(0.7).lineLimit(1).truncationMode(.middle)
                if case .failed(let why) = s {
                    Text(why).font(t.ui(9.5)).foregroundStyle(SwiftUI.Color(t.bad)).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if !unsaved {
                IconButton(icon: s.isRunning ? "stop.fill" : "play.fill", tint: s.isRunning ? t.bad : t.good) {
                    if s.isRunning { model.stopTunnel(tu.id) } else { model.startTunnel(tu) }
                }
                .help(s.isRunning ? L("Parar") : L("Iniciar"))
                .disabled(busy)
            }
        }
        .foregroundStyle(SwiftUI.Color(on ? t.onTab : t.text))
        .padding(.vertical, 5).padding(.horizontal, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? SwiftUI.Color(t.tab) : SwiftUI.Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
    }

    // MARK: editor

    private var sessionNames: [String] {
        model.sessions.profiles.filter { $0.transport == .ssh || $0.transport == .sftp }.map(\.name)
    }

    private var editor: some View {
        let state = baseline == nil ? TunnelState.stopped : model.tunnelRunner.state(draft.id)
        return VStack(alignment: .leading, spacing: 0) {
            Form {
                LabeledContent(L("Nombre")) { TextField("", text: $draft.name, prompt: Text(L("Nombre"))).frame(maxWidth: 320) }
                ThemedSegmented(L("Tipo"), selection: $draft.kind) { o in
                    for k in Tunnel.Kind.allCases { o.append((k, k.title)) }
                }
                ThemedSegmented(L("Por"), selection: Binding(get: { bySession }, set: { setBySession($0) })) { o in
                    o.append((true, L("Sesión guardada")))
                    o.append((false, L("Equipo")))
                }
                if bySession {
                    ThemedPicker(L("Sesión"), selection: $draft.session) { o in
                        o.append(("", L("(elige una)")))
                        for x in sessionNames { o.append((x, x)) }
                        if !draft.session.isEmpty, !sessionNames.contains(draft.session) {
                            o.append((draft.session, L("\(draft.session) (no está en tus sesiones)")))
                        }
                    }
                } else {
                    LabeledContent(L("Equipo")) {
                        TextField("", text: $draft.server, prompt: Text("tu.usuario@192.0.2.10:22")).frame(maxWidth: 320)
                    }
                    LabeledContent(L("Saltos")) {
                        TextField("", text: $draft.jump, prompt: Text(L("bastion (opcional; varios, con comas)"))).frame(maxWidth: 320)
                    }
                }
                LabeledContent(draft.kind == .remote ? L("Escucha en el servidor") : L("Escucha en este Mac")) {
                    HStack(spacing: 6) {
                        TextField("", text: $draft.listenAddress, prompt: Text(draft.defaultListen)).frame(width: 150)
                        Text(":").foregroundStyle(SwiftUI.Color(t.dim))
                        TextField("", value: $draft.listenPort, format: .number.grouping(.never)).frame(width: 70)
                    }
                }
                if draft.kind != .dynamic {
                    LabeledContent(draft.kind == .remote ? L("Destino (desde este Mac)") : L("Destino (desde el servidor)")) {
                        HStack(spacing: 6) {
                            TextField("", text: $draft.targetHost, prompt: Text("192.0.2.10")).frame(width: 150)
                            Text(":").foregroundStyle(SwiftUI.Color(t.dim))
                            TextField("", value: $draft.targetPort, format: .number.grouping(.never)).frame(width: 70)
                        }
                    }
                }
                Toggle(L("Permitir conexiones de otros equipos (escuchar fuera de loopback)"), isOn: $draft.exposed)
            }
            .formStyle(.themed)
            .scrollContentBackground(.hidden)
            VStack(alignment: .leading, spacing: 6) {
                if let p = problem {
                    Text("✗ " + p).font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.bad)).lineLimit(2)
                }
                ForEach(draft.warnings, id: \.self) { w in
                    Text(w.hasPrefix("⚠") ? w : "⚠ " + w).font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.warning)).lineLimit(2)
                }
                HStack(spacing: 8) {
                    Circle().fill(SwiftUI.Color(color(state))).frame(width: 9, height: 9)
                    Text(stateText(state)).font(t.ui(11, .semibold))
                        .foregroundStyle(SwiftUI.Color(state == .stopped ? t.dim : color(state))).lineLimit(3)
                        .textSelection(.enabled)
                }
                Text(help).font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim))
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
    }

    private var help: String {
        switch draft.kind {
        case .local: L("-L: lo que llega a la escucha de este Mac sale desde el servidor hacia el destino.")
        case .remote: L("-R: lo que llega a la escucha del servidor viene a este Mac y sale hacia el destino.")
        case .dynamic: L("-D: proxy SOCKS en este Mac; las conexiones salen desde el servidor.")
        }
    }

    private var footer: some View {
        let state = baseline == nil ? TunnelState.stopped : model.tunnelRunner.state(draft.id)
        return HStack(spacing: 10) {
            Text(message.isEmpty ? AppPaths.tilde(TunnelLibrary.defaultURL.path) : message)
                .font(t.ui(11)).foregroundStyle(SwiftUI.Color(message.hasPrefix("✗") ? t.bad : t.dim)).lineLimit(2)
            Spacer()
            NeonButton(title: L("Cerrar"), icon: "xmark") { act { if await confirmLeave() { dismiss() } } }
                .disabled(busy)
            NeonButton(title: L("Guardar"), icon: "checkmark", active: dirty) { _ = save() }
                .disabled(busy || !dirty)
                .keyboardShortcut("s")
            if state.isRunning {
                NeonButton(title: L("Parar"), icon: "stop.fill", tint: t.bad) { model.stopTunnel(draft.id) }
                    .disabled(busy)
            } else {
                NeonButton(title: L("Iniciar"), icon: "play.fill", tint: t.good) {
                    if !dirty || save() { model.startTunnel(draft) }
                }
                .disabled(busy || problem != nil)
                .help(dirty ? L("Guarda los cambios y lo inicia") : L("Inicia el túnel"))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(SwiftUI.Color(t.bar))
    }

    // MARK: acciones

    private var problem: String? {
        if let p = draft.problem { return p }
        let n = draft.name.trimmingCharacters(in: .whitespaces).lowercased()
        if library.tunnels.contains(where: { $0.id != draft.id && $0.name.lowercased() == n }) {
            return L("ya hay un túnel con ese nombre")
        }
        return nil
    }

    private func setBySession(_ on: Bool) {
        bySession = on
        if on { draft.server = ""; draft.jump = "" } else { draft.session = "" }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        library = model.tunnels
        if let e = model.tunnelsError {
            message = "✗ " + e
        } else if !model.tunnelWarnings.isEmpty {
            message = "✗ " + L("\(model.tunnelWarnings.count) ignorados: ") + model.tunnelWarnings.prefix(2).joined(separator: " · ")
        }
        pick(library.tunnels.first?.id)
    }

    private func pick(_ id: Tunnel.ID?) {
        selected = id
        if let tu = library.tunnel(id) {
            draft = tu
            baseline = tu
            bySession = !tu.session.isEmpty
        } else {
            draft = Tunnel(name: library.uniqueName(L("túnel")), session: sessionNames.first ?? "", targetHost: "192.0.2.10")
            baseline = nil
            bySession = true
        }
    }

    private func choose(_ id: Tunnel.ID?) {
        guard id != selected || id == nil else { return }
        act { if await confirmLeave() { pick(id) } }
    }

    private func act(_ action: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            await action()
            busy = false
        }
    }

    /// Con cambios sin guardar: guardar, descartar o quedarse (`false`).
    private func confirmLeave() async -> Bool {
        guard dirty else { return true }
        switch await ThemedAlert.run(L("El túnel «\(draft.name)» tiene cambios sin guardar"),
                                     buttons: [L("Guardar"), L("Descartar"), L("Cancelar")]).button {
        case 0: return save()
        case 1: return true
        default: return false
        }
    }

    /// Guarda la lista con el túnel del editor. Un túnel en marcha sigue con lo de antes hasta pararlo e iniciarlo.
    @discardableResult private func save() -> Bool {
        if let p = problem { message = "✗ " + p; return false }
        var lib = library
        var tu = draft
        tu.name = tu.name.trimmingCharacters(in: .whitespaces)
        if let i = lib.tunnels.firstIndex(where: { $0.id == tu.id }) { lib.tunnels[i] = tu } else { lib.tunnels.append(tu) }
        if let e = model.saveTunnels(lib) { message = "✗ " + e; return false }
        library = lib
        selected = tu.id
        draft = tu
        baseline = tu
        message = model.tunnelRunner.state(tu.id).isRunning ? L("✓ Guardado: los cambios valen al pararlo e iniciarlo de nuevo")
                                                              : L("✓ Túnel «\(tu.name)» guardado")
        return true
    }

    private func duplicate() {
        act {
            guard await confirmLeave() else { return }
            var c = draft
            c.id = UUID()
            c.name = library.uniqueName(c.name)
            selected = nil
            draft = c
            baseline = nil
        }
    }

    private func remove() async {
        guard let tu = baseline else { return }
        let running = model.tunnelRunner.state(tu.id).isRunning
        guard await ThemedAlert.confirm(L("¿Borrar el túnel «\(tu.name)»?"),
                                        message: running ? L("Está en marcha: se para. Queda una copia en tuneles.json.anterior.")
                                                         : L("Queda una copia en tuneles.json.anterior."),
                                        ok: L("Borrar"), destructive: true) else { return }
        var lib = library
        lib.tunnels.removeAll { $0.id == tu.id }
        if let e = model.saveTunnels(lib) { message = "✗ " + e; return }
        library = lib
        pick(lib.tunnels.first?.id)
        message = L("✓ Borrado")
    }
}

extension Tunnel.Kind {
    var title: String {
        switch self {
        case .local: L("Local (-L)")
        case .remote: L("Remoto (-R)")
        case .dynamic: L("SOCKS (-D)")
        }
    }
}
