import NetDeckCore
import SwiftUI

/// Pantalla dividida (⊞ Split de NetDeck): varias pestañas a la vista, cada una con su cabecera. Los bordes se
/// arrastran para cambiar el tamaño. Con MultiExec, lo que escribes en una va a todas las que no estén excluidas.
struct SplitArea: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let split: Split

    var body: some View {
        Group {
            switch split.layout {
            case .side2: HSplitView { pane(0); pane(1) }
            case .stack2: VSplitView { pane(0); pane(1) }
            case .cols3: HSplitView { pane(0); pane(1); pane(2) }
            case .onePlusTwo: HSplitView { pane(0); VSplitView { pane(1); pane(2) } }
            case .grid4: VSplitView { HSplitView { pane(0); pane(1) }; HSplitView { pane(2); pane(3) } }
            case .grid: grid
            }
        }
        .background(SwiftUI.Color(t.layer))
    }

    /// Todas: filas de √n columnas.
    private var grid: some View {
        let n = max(split.panes.count, 1)
        let cols = Int(Double(n).squareRoot().rounded(.up))
        let rows = (n + cols - 1) / cols
        return VSplitView {
            ForEach(0..<rows, id: \.self) { r in
                HSplitView {
                    ForEach(0..<cols, id: \.self) { c in
                        if r * cols + c < n { pane(r * cols + c) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func pane(_ i: Int) -> some View {
        if i < split.panes.count, let s = model.tab(split.panes[i]) {
            SplitPane(session: s).frame(minWidth: 220, minHeight: 120)
        } else {
            EmptyPane(index: i).frame(minWidth: 220, minHeight: 120)
        }
    }
}

struct SplitPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let session: TerminalSession

    var body: some View {
        let selected = model.selection == session.id
        let excluded = model.excluded.contains(session.id)
        let multi = model.multiExecOn && !excluded
        let edge = multi ? t.warning : (selected ? t.accent : t.panel)
        VStack(spacing: 0) {
            header(selected: selected, excluded: excluded, multi: multi)
            if let e = model.notices[session.id] { PasswordNotice(session: session, event: e) }
            TerminalHost(session: session, focused: selected)
                .padding(.leading, 6)
                .padding(.top, 4)
        }
        .background(SwiftUI.Color(t.layer))
        .overlay(Rectangle().strokeBorder(SwiftUI.Color(edge).opacity(selected || multi ? 0.9 : 0.5), lineWidth: selected ? 2 : 1))
        .shadow(color: SwiftUI.Color(edge).opacity(selected ? 0.35 : 0), radius: t.glow(6))
    }

    private func header(selected: Bool, excluded: Bool, multi: Bool) -> some View {
        HStack(spacing: 7) {
            Circle().fill(SwiftUI.Color(session.exited ? t.bad : (session.state == .connected ? t.good : t.warning)))
                .frame(width: 7, height: 7)
            Text(session.title).font(t.ui(11.5, .bold)).lineLimit(1)
            if let d = session.device, d != session.title {
                Text("› \(d)").font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim)).lineLimit(1)
            }
            Spacer(minLength: 4)
            RecBadge(session: session, compact: true)
            if model.multiExecOn {
                Button { model.toggleExcluded(session) } label: {
                    Text(excluded ? "EXCLUIDA" : "⧉ MULTIEXEC")
                        .font(t.ui(9, .bold)).tracking(1)
                        .foregroundStyle(SwiftUI.Color(excluded ? t.dim : t.warning))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SwiftUI.Color(excluded ? t.dim : t.warning).opacity(0.7)))
                }
                .buttonStyle(.plain)
                .help(excluded ? "Incluir en MultiExec" : "Excluir de MultiExec (lo que escribas no le llegará)")
            }
            Button { model.showSplit = false; model.selection = session.id } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Ver sola (la vista sigue en «⊞ VISTA»)")
            Button { model.removeFromSplit(session) } label: {
                Image(systemName: "rectangle.badge.minus").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Sacar de la vista (sigue abierta en su pestaña)")
            Button { model.close(session) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .help("Cerrar esta sesión")
        }
        .foregroundStyle(SwiftUI.Color(selected ? t.onTab : t.text))
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(SwiftUI.Color(selected ? t.tab : t.panel).opacity(selected ? 1 : 0.8))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.showSplit = false; model.selection = session.id }
        .onTapGesture { model.selection = session.id }
        .contextMenu { SessionTabMenu(session: session) }
    }
}

/// Hueco de la vista: elegir una pestaña abierta o abrir una sesión ahí.
struct EmptyPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let index: Int

    var body: some View {
        let others = model.tabs.filter { model.split?.panes.contains($0.id) != true }
        VStack(spacing: 12) {
            Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 26)).foregroundStyle(SwiftUI.Color(t.accent2))
            Text("PANEL LIBRE").font(t.ui(11, .bold)).tracking(3).foregroundStyle(SwiftUI.Color(t.dim))
            HStack(spacing: 8) {
                if !others.isEmpty {
                    Menu {
                        ForEach(others) { s in Button(s.title) { model.addToSplit(s, at: index) } }
                    } label: { NeonLabel(title: "Pestaña abierta", icon: "rectangle.stack") }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                Menu {
                    if let cur = model.current {
                        Button("Clonar «\(cur.title)»") { model.openInSplit(cur.route, at: index) }
                        Divider()
                    }
                    ForEach(model.sessions.groups, id: \.name) { g in
                        Section(g.name) {
                            ForEach(g.profiles) { p in
                                Button(p.name) {
                                    if let r = try? model.sessions.route(to: p) { model.openInSplit(r, at: index) }
                                }
                            }
                        }
                    }
                } label: { NeonLabel(title: "Abrir sesión", icon: "bolt.horizontal.fill") }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SwiftUI.Color(t.panel).opacity(0.25))
        .overlay(Rectangle().strokeBorder(SwiftUI.Color(t.panel), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}
