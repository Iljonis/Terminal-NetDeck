import AppKit
import NetDeckCore
import SwiftUI

/// Ventana principal: barra superior (en la de título), sesiones a la izquierda, pestañas y terminal, barra de estado.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        if model.showSetup {
            SetupView()
                .ignoresSafeArea(.container, edges: .top)
        } else {
            main
        }
    }

    private var main: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            if model.fullScreen, model.titlebarReveal > 0 {
                // (pantalla completa con la barra de título de macOS bajada: que no tape los botones)
                SwiftUI.Color(t.bar).frame(height: model.titlebarReveal)
            }
            TopBar()
            if model.settings.buttonBar == "arriba" { ButtonBarView() }
            HStack(spacing: 0) {
                if model.settings.sidebarVisible {
                    Sidebar().frame(width: 268)
                    NeonLine(vertical: true, color: t.panel)
                }
                VStack(spacing: 0) {
                    MainArea()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.settings.buttonBar == "abajo" { ButtonBarView() }
            StatusBar()
        }
        .background(SwiftUI.Color(t.background))
        .background { if t.isTranslucent { BehindWindowBlur(material: t.blurMaterial) } }
        .background(WindowReader { model.attach($0) })
        .ignoresSafeArea(.container, edges: .top)
        .tint(SwiftUI.Color(t.accent))
        .overlay { if model.showSettings { SettingsOverlay() } }
        .onAppear(perform: snapshotAction)
        .sheet(item: $model.sheet) { sheet in
            Group {
                switch sheet {
                case .connect: ConnectSheet()
                case .paste: PasteSheet()
                case .list: ListSheet()
                case .sessions: SessionEditor()
                case .fill: ButtonFillSheet()
                case .logs: LogSearchSheet()
                }
            }
            .environment(model)
            .environment(\.theme, t)
            .tint(SwiftUI.Color(t.accent))
        }
    }
}

extension ContentView {
    /// Desarrollo (con NETDECK_SNAPSHOT): «tab:usuario@equipo» abre esa pestaña; «settings» abre Ajustes.
    private func snapshotAction() {
        guard let a = ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT_ACTION"] else { return }
        if a.hasPrefix("tab:") {
            model.quickConnect(String(a.dropFirst(4)))
            // (y el texto de la pestaña, para comprobar que la salida llega al terminal)
            if let path = ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    let text = model.current.map { $0.lines(from: 0).joined(separator: "\n") } ?? ""
                    try? text.write(toFile: path + ".txt", atomically: true, encoding: .utf8)
                }
            }
        }
        if a.hasPrefix("settings") { model.openSettings(a.split(separator: ":").dropFirst().first.map(String.init) ?? "contraseñas") }
        if a.hasPrefix("split") {                    // «split»: 3 pestañas en 1 + 2 con MultiExec
            for h in ["admin@192.0.2.11", "admin@192.0.2.12", "admin@192.0.2.21"] { model.quickConnect(h) }
            model.makeSplit(.onePlusTwo)
            model.multiExecOn = true
            if let s = model.tabs.last { model.toggleExcluded(s) }
        }
    }
}

// MARK: - barra superior

/// Una sola fila en la barra de título: pestañas y, a la derecha, los accesos directos (pegado, dividir, Llavero,
/// MultiExec, cortar, sesiones, ajustes). El menú de la app solo guarda las órdenes con atajo.
struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if let sp = model.split { SplitChip(split: sp) }
                    ForEach(model.tabs) { TabChip(session: $0) }
                }
                .padding(.vertical, 4)
            }
            .fixedSize(horizontal: model.tabs.count < 6, vertical: false)
            IconButton(icon: "plus") { model.sheet = .connect }
                .help(L("Conexión rápida o por un salto (⌘K)"))
            Spacer(minLength: 12)
            IconButton(icon: "doc.on.clipboard.fill") { model.sheet = .paste }
                .help(L("Pegado seguro: revisa líneas peligrosas antes de enviarlas (⇧⌘V)"))
            IconMenu(icon: "rectangle.split.3x1.fill", active: model.split != nil) {
                ForEach(Split.Layout.allCases) { l in Button(l.title) { model.makeSplit(l) } }
                Divider()
                Button(L("Volver a pestañas sueltas")) { model.unsplit() }.disabled(model.split == nil)
            }
            .help(L("Dividir la pantalla"))
            IconMenu(icon: "key.fill") {
                if let s = model.current {
                    Section(L("Escribir en «\(s.title)»")) {
                        ForEach(model.keychainAccounts, id: \.self) { ref in
                            Button(ref.account) { model.typePassword(ref, in: s) }
                        }
                    }
                    Divider()
                }
                Button(L("Contraseñas y Llavero…")) { model.openSettings("contraseñas") }
            }
            .help(L("Escribir una contraseña del Llavero en la pestaña actual"))
            IconButton(icon: "square.stack.3d.forward.dottedline.fill", tint: t.warning, active: model.multiExecOn,
                       badge: model.multiExecOn ? "\(model.multiExecTargets.count)" : nil) { model.multiExecOn.toggle() }
                .help(L("MultiExec: lo que escribes va a la vez a los paneles (⇧⌘M). Clic derecho en un panel → excluirlo"))
            IconButton(icon: "stop.circle.fill", tint: t.bad) { model.abortAll() }
                .help(L("Corta cualquier secuencia automática (Esc o Ctrl+C en el terminal, ⌘.)"))
            IconButton(icon: "sidebar.left", active: model.settings.sidebarVisible) { model.settings.sidebarVisible.toggle() }
                .help(L("Mostrar/ocultar sesiones (⌃⌘S)"))
            IconButton(icon: "gearshape.fill") { model.openSettings() }
                .help(L("Ajustes (⌘,)"))
        }
        .padding(.leading, model.fullScreen ? 10 : 80)
        .padding(.trailing, 10)
        .frame(height: 38)
        .background(SwiftUI.Color(t.bar)
            .gesture(WindowDragGesture())
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.toggleFill() }))
        .overlay(alignment: .bottom) { Rectangle().fill(SwiftUI.Color(t.tab)).frame(height: 2) }
    }
}

struct Brand: View {
    @Environment(\.theme) private var t

    var body: some View {
        if t.neon { neon } else {
            HStack(spacing: 7) {
                Image(systemName: t.style == .fluent ? "terminal" : "apple.terminal.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(SwiftUI.Color(t.accent))
                Text(L("NetDeck")).font(t.ui(15, .bold)).foregroundStyle(SwiftUI.Color(t.text))
                Text(L("Terminal")).font(t.ui(13)).foregroundStyle(SwiftUI.Color(t.dim))
            }
            .allowsHitTesting(false)
        }
    }

    private var neon: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("▚").font(.system(size: 15, weight: .black)).foregroundStyle(SwiftUI.Color(t.accent2))
            Text(L("NETDECK"))
                .font(t.ui(16, .heavy)).tracking(3)
                .foregroundStyle(SwiftUI.Color(t.accent))
                .shadow(color: SwiftUI.Color(t.accent).opacity(0.8), radius: t.glow(6))
            Text("//").font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            Text(L("TERMINAL")).font(t.ui(10, .bold)).tracking(2.5).foregroundStyle(SwiftUI.Color(t.accent2))
        }
        .allowsHitTesting(false)
    }
}

struct IconButton: View {
    @Environment(\.theme) private var t
    let icon: String
    var tint: RGB?
    var active = false
    var badge: String?
    var action: () -> Void
    @Stored private var hover = false

    var body: some View {
        let color = tint ?? t.accent
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                if let badge { Text(badge).font(t.ui(11, .bold)) }
            }
            .foregroundStyle(SwiftUI.Color(active ? t.background : (hover ? color : (tint ?? t.text))))
            .padding(.horizontal, 7)
            .frame(minWidth: 30, minHeight: 26)
            .background(RoundedRectangle(cornerRadius: t.corner ?? 6)
                .fill(SwiftUI.Color(active ? color : t.panel).opacity(active ? 1 : (hover ? 0.9 : 0.4))))
            .shadow(color: SwiftUI.Color(color).opacity(active ? 0.6 : 0), radius: t.glow(6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Como `IconButton`, pero abre un menú.
struct IconMenu<Content: View>: View {
    @Environment(\.theme) private var t
    let icon: String
    var active = false
    @ViewBuilder var content: () -> Content
    @Stored private var hover = false

    var body: some View {
        Menu(content: content) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SwiftUI.Color(active ? t.background : (hover ? t.accent : t.text)))
                .padding(.horizontal, 7)
                .frame(minWidth: 30, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: t.corner ?? 6)
                    .fill(SwiftUI.Color(active ? t.accent : t.panel).opacity(active ? 1 : (hover ? 0.9 : 0.4))))
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .onHover { hover = $0 }
    }
}

// MARK: - pestañas

struct TabChip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let session: TerminalSession
    @Stored private var hover = false

    var body: some View {
        let inSplit = model.split?.panes.contains(session.id) == true
        let selected = model.selection == session.id && (!model.showSplit || inSplit)
        let notice = model.notices[session.id] != nil
        HStack(spacing: 7) {
            Circle()
                .fill(SwiftUI.Color(dotColor(notice)))
                .frame(width: 7, height: 7)
                .shadow(color: SwiftUI.Color(dotColor(notice)).opacity(0.8), radius: t.glow(3))
            if inSplit { Image(systemName: "square.split.2x1").font(.system(size: 9)) }
            Text(session.title).font(t.ui(12, .semibold)).lineLimit(1)
            if let d = session.device, !session.title.hasPrefix(d), d != session.route.sessionName {
                Text("› \(d)").font(t.ui(11)).opacity(0.75).lineLimit(1)
            }
            if session.activity { Text("•").font(t.ui(13, .black)).foregroundStyle(SwiftUI.Color(t.warning)) }
            if notice { Image(systemName: "key.fill").font(.system(size: 10)).foregroundStyle(SwiftUI.Color(t.warning)) }
            Button { model.close(session) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(selected || hover ? 1 : 0)
        }
        .foregroundStyle(SwiftUI.Color(selected ? t.onTab : t.accent2))
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: 29)
        .background(ChamferShape(radius: t.corner).fill(SwiftUI.Color(selected ? t.tab : t.panel).opacity(selected ? 1 : (hover ? 0.95 : 0.6))))
        .shadow(color: SwiftUI.Color(t.tab).opacity(selected ? 0.6 : 0), radius: t.glow(8))
        .contentShape(Rectangle())
        .onTapGesture { model.show(session) }
        .onHover { hover = $0 }
        .help(session.route.thenCommand.map { L("\(session.title) · en el salto: \($0)") } ?? session.title)
        .contextMenu { SessionTabMenu(session: session) }
    }

    private func dotColor(_ notice: Bool) -> RGB {
        switch session.state {
        case .exited: t.bad
        case .connecting: t.warning
        case .connected: notice ? t.warning : t.good
        }
    }
}

/// Clic derecho en una pestaña o en la cabecera de un panel.
struct SessionTabMenu: View {
    @Environment(AppModel.self) private var model
    let session: TerminalSession

    var body: some View {
        Button(L("Reconectar")) { model.reconnect(session) }
        Button(L("Clonar (otra pestaña igual)")) { model.duplicate(session) }
        Divider()
        if model.split?.panes.contains(session.id) == true {
            Button(L("Quitar de la vista dividida")) { model.removeFromSplit(session) }
        } else {
            Button(L("Añadir a la vista dividida")) { model.addToSplit(session) }
        }
        if model.multiExecOn || model.split != nil {
            Button(model.excluded.contains(session.id) ? L("Incluir en MultiExec") : L("Excluir de MultiExec")) {
                model.toggleExcluded(session)
            }
        }
        Divider()
        Button(L("Buscar… (⌘F)")) { session.view.showFind() }
        Button(session.logFile == nil ? L("● Grabar registro") : L("■ Parar el registro")) { model.toggleLog(session) }
        if let f = session.logFile {
            Button(L("Abrir el registro")) { NSWorkspace.shared.open(f) }
        }
        Divider()
        Button(L("Cerrar")) { model.close(session) }
    }
}

/// ● REC en una esquina mientras se graba la sesión (como NetDeck). Clic: abrir, mostrar en Finder o parar.
struct RecBadge: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let session: TerminalSession
    var compact = false

    var body: some View {
        if let f = session.logFile {
            Menu {
                Button(L("Abrir el registro")) { NSWorkspace.shared.open(f) }
                Button(L("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([f]) }
                Divider()
                Button(L("Parar el registro")) { model.toggleLog(session) }
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let on = Int(ctx.date.timeIntervalSince1970) % 2 == 0
                    HStack(spacing: 5) {
                        Circle().fill(SwiftUI.Color(t.bad)).frame(width: 8, height: 8).opacity(on ? 1 : 0.35)
                            .shadow(color: SwiftUI.Color(t.bad), radius: t.glow(4))
                        if !compact { Text(L("REC")).font(t.ui(10, .heavy)).tracking(1.5).foregroundStyle(SwiftUI.Color(t.bad)) }
                    }
                    .padding(.horizontal, compact ? 4 : 8).padding(.vertical, 3)
                    .background(Capsule().fill(SwiftUI.Color(t.background.opaque).opacity(0.85)))
                    .overlay(Capsule().strokeBorder(SwiftUI.Color(t.bad).opacity(0.6)))
                }
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help(L("Grabando en \(f.path.replacingOccurrences(of: AppPaths.home.path, with: "~"))"))
        }
    }
}

/// «⊞ Vista»: la pantalla dividida (las pestañas siguen arriba, cada una por su cuenta).
struct SplitChip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let split: Split

    var body: some View {
        let on = model.showSplit
        HStack(spacing: 6) {
            Image(systemName: split.layout.icon).font(.system(size: 11, weight: .bold))
            Text(L("VISTA ×\(split.panes.count)")).font(t.ui(11, .bold)).tracking(1)
        }
        .foregroundStyle(SwiftUI.Color(on ? t.background : t.accent))
        .padding(.horizontal, 11)
        .frame(height: 29)
        .background(ChamferShape(radius: t.corner).fill(SwiftUI.Color(on ? t.accent : t.panel).opacity(on ? 1 : 0.7)))
        .shadow(color: SwiftUI.Color(t.accent).opacity(on ? 0.6 : 0), radius: t.glow(8))
        .contentShape(Rectangle())
        .onTapGesture {
            model.showSplit = true
            if let f = split.panes.first, !split.panes.contains(model.selection ?? UUID()) { model.selection = f }
        }
        .contextMenu {
            Button(L("Volver a pestañas sueltas")) { model.unsplit() }
        }
        .help(L("Pantalla dividida · clic derecho: volver a pestañas sueltas"))
    }
}


// MARK: - terminal

struct MainArea: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        if model.showSplit, let sp = model.split {
            SplitArea(split: sp)
        } else if let s = model.current {
            VStack(spacing: 0) {
                if let e = model.notices[s.id] { PasswordNotice(session: s, event: e) }
                TerminalHost(session: s, focused: true)
                    .id(s.id)
                    .padding(.leading, 8)
                    .padding(.top, 6)
                    .overlay(alignment: .topTrailing) { RecBadge(session: s).padding(.top, 8).padding(.trailing, 18) }
            }
            .background(SwiftUI.Color(t.layer))
        } else {
            Welcome()
        }
    }
}

/// Aviso encima del terminal: la regla de usuario no deja escribirla sola, o la sugerida (un clic).
struct PasswordNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let session: TerminalSession
    let event: PasswordAutomation.Event

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(SwiftUI.Color(t.warning)).frame(width: 3)
            Image(systemName: "key.fill").foregroundStyle(SwiftUI.Color(t.warning))
            Text(text).font(t.ui(12)).foregroundStyle(SwiftUI.Color(t.text)).lineLimit(2)
            Spacer()
            if case .suggested(let ref) = event {
                NeonButton(title: L("Escribir «\(ref.account)»"), icon: "return", tint: t.good) { model.typePassword(ref, in: session) }
            }
            IconButton(icon: "xmark") { model.notices[session.id] = nil }
        }
        .padding(.trailing, 10)
        .frame(height: 40)
        .background(SwiftUI.Color(t.warning).opacity(0.12))
    }

    private var text: String {
        switch event {
        case .suggested(let r): L("Piden contraseña: «\(r.account)» es de ese usuario")
        case .manual(let why): L("Piden contraseña: \(Askpass.explain(why)) · o elígela en 🔑")
        case .failed(let r): L("«\(r.account)» no ha valido: bloqueada 15 min en todas las pestañas (cuenta AD)")
        default: ""
        }
    }
}

/// La vista de SwiftTerm de la pestaña (vive en la sesión: cambiar de pestaña o de vista no la recrea). Va dentro de
/// un contenedor: el último que se crea se la queda (pestaña sola ↔ panel de la vista dividida).
struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession
    var focused = false

    func makeNSView(context: Context) -> NSView {
        let box = NSView()
        session.host = box
        adopt(into: box)
        return box
    }

    func updateNSView(_ box: NSView, context: Context) {
        if session.host === box { adopt(into: box) }
        guard focused else { return }
        DispatchQueue.main.async {
            let v = session.view
            if v.superview === box, v.window?.firstResponder !== v { v.window?.makeFirstResponder(v) }
        }
    }

    private func adopt(into box: NSView) {
        let v = session.view
        guard v.superview !== box else { return }
        v.removeFromSuperview()
        v.frame = box.bounds
        v.autoresizingMask = [.width, .height]
        box.addSubview(v)
    }
}

/// Lee la ventana de SwiftUI (pantalla completa, color de fondo, llenar la pantalla).
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { found(w) } }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        if let w = v.window { DispatchQueue.main.async { found(w) } }
    }
}

// MARK: - barra de estado

struct StatusBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "chevron.right.2").foregroundStyle(SwiftUI.Color(t.accent))
            Text(model.themes.busy ?? (model.status.isEmpty ? L("Listo") : model.status))
                .foregroundStyle(SwiftUI.Color(t.text))
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if let u = model.availableUpdate {
                Button { model.offerUpdate(u) } label: {
                    Tag(text: L("⬆ Versión \(u.version) disponible"), color: t.good)
                }
                .buttonStyle(.plain)
                .help(L("Hay una versión nueva de Terminal NetDeck: clic para verla"))
            }
            if model.multiExecOn {
                Tag(text: L("MULTIEXEC ×\(model.multiExecTargets.count)"), color: t.warning)
            }
            Tag(text: L("🔑 SESIÓN \(model.settings.sessionAutoPassword ? "AUTO" : "MANUAL") · EQUIPOS \(modeText)"), color: t.accent2)
            Text(model.themes.current.name.uppercased()).tracking(1.5).foregroundStyle(SwiftUI.Color(t.dim))
            TimelineView(.everyMinute) { ctx in
                Text(t.clockText(ctx.date)).foregroundStyle(SwiftUI.Color(t.accent))
            }
        }
        .font(t.ui(10.5, .medium))
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(SwiftUI.Color(t.bar))
        .overlay(alignment: .top) { NeonLine(color: t.accent2) }
    }

    private var modeText: String {
        switch model.settings.devicePasswordMode {
        case .autoType: L("AUTO")
        case .suggest: L("SUGERIR")
        case .off: L("NO")
        }
    }
}

struct Tag: View {
    @Environment(\.theme) private var t
    let text: String
    let color: RGB

    var body: some View {
        Text(text)
            .font(t.ui(9.5, .bold)).tracking(1)
            .foregroundStyle(SwiftUI.Color(color))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SwiftUI.Color(color).opacity(0.6)))
    }
}
