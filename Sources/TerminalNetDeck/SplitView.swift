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
            case .side2: part("root", count: 2) { pane($0) }
            case .stack2: part("root", count: 2, vertical: true) { pane($0) }
            case .cols3: part("root", count: 3) { pane($0) }
            case .onePlusTwo:
                part("root", count: 2) { i in
                    if i == 0 { pane(0) } else { part("right", count: 2, vertical: true) { pane($0 + 1) } }
                }
            case .grid4:
                part("root", count: 2, vertical: true) { row in part("row-\(row)", count: 2) { pane(row * 2 + $0) } }
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
        return part("root", count: rows, vertical: true) { r in
            part("row-\(r)", count: min(cols, n - r * cols)) { c in pane(r * cols + c) }
        }
    }

    private func part<C: View>(_ key: String, count: Int, vertical: Bool = false,
                              @ViewBuilder content: @escaping (Int) -> C) -> some View {
        WeightedSplit(key: key, count: count, vertical: vertical, content: content)
    }

    @ViewBuilder private func pane(_ i: Int) -> some View {
        if i < split.panes.count, let s = model.tab(split.panes[i]) {
            SplitPane(session: s).frame(minWidth: 0, minHeight: 0)
        } else {
            EmptyPane(index: i).frame(minWidth: 0, minHeight: 0)
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
            SessionContent(session: session, focused: selected, inset: 6)
                .overlay(alignment: .topTrailing) {
                    if let e = model.notices[session.id] { PasswordNotice(session: session, event: e).padding(10) }
                    else if let o = model.typedOffers[session.id] { TypedOfferNotice(session: session, offer: o).padding(10) }
                }
        }
        .background(SwiftUI.Color(t.layer))
        .overlay(Rectangle().strokeBorder(SwiftUI.Color(edge).opacity(selected || multi ? 0.9 : 0.5), lineWidth: selected ? 2 : 1))
        .shadow(color: SwiftUI.Color(edge).opacity(selected ? 0.35 : 0), radius: t.glow(6))
    }

    private func header(selected: Bool, excluded: Bool, multi: Bool) -> some View {
        HStack(spacing: 7) {
            Circle().fill(SwiftUI.Color(session.statusColor(t)))
                .frame(width: 7, height: 7)
            Text(session.title).font(t.ui(11.5, .bold)).lineLimit(1)
            if let d = session.device, d != session.title {
                Text("› \(d)").font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim)).lineLimit(1)
            }
            Spacer(minLength: 4)
            RecBadge(session: session, compact: true)
            if model.multiExecOn {
                Button { model.toggleExcluded(session) } label: {
                    Text(excluded ? L("EXCLUIDA") : L("⧉ MULTIEXEC"))
                        .font(t.ui(9, .bold)).tracking(1)
                        .foregroundStyle(SwiftUI.Color(excluded ? t.dim : t.warning))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SwiftUI.Color(excluded ? t.dim : t.warning).opacity(0.7)))
                }
                .buttonStyle(.plain)
                .help(excluded ? L("Incluir en MultiExec") : L("Excluir de MultiExec (lo que escribas no le llegará)"))
            }
            Button { model.showSplit = false; model.selection = session.id } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .help(L("Ver sola (la vista sigue en «⊞ VISTA»)"))
            Button { model.removeFromSplit(session) } label: {
                Image(systemName: "rectangle.badge.minus").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .help(L("Sacar de la vista (sigue abierta en su pestaña)"))
            Button { model.close(session) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .help(L("Cerrar esta sesión"))
        }
        .foregroundStyle(SwiftUI.Color(selected ? t.onTab : t.text))
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(SwiftUI.Color(selected ? t.tab : t.panel).opacity(selected ? 1 : 0.8))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.showSplit = false; model.selection = session.id }
        .onTapGesture { model.selection = session.id }
        .themedContextMenu { SessionTabMenu(session: session) }
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
            Text(L("PANEL LIBRE")).font(t.ui(11, .bold)).tracking(3).foregroundStyle(SwiftUI.Color(t.dim))
            HStack(spacing: 8) {
                if !others.isEmpty {
                    ThemedMenu {
                        ForEach(others) { s in Button(s.title) { model.addToSplit(s, at: index) } }
                    } label: { NeonLabel(title: L("Pestaña abierta"), icon: "rectangle.stack") }
                }
                ThemedMenu {
                    if let cur = model.current {
                        Button(L("Clonar «\(cur.title)»")) { model.openInSplit(cur.route, at: index) }
                        MenuDivider()
                    }
                    ForEach(model.sessions.groups, id: \.name) { g in
                        MenuHeader(title: L(nombre: g.name))
                        ForEach(g.profiles) { p in
                            Button(p.name) {
                                if let r = try? model.sessions.route(to: p) { model.openInSplit(r, at: index) }
                            }
                        }
                    }
                } label: { NeonLabel(title: L("Abrir sesión"), icon: "bolt.horizontal.fill") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SwiftUI.Color(t.panel).opacity(0.25))
        .overlay(Rectangle().strokeBorder(SwiftUI.Color(t.panel), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}


/// Los tamaños se expresan como proporciones: la misma disposición sirve en otra pantalla.
private struct WeightedSplit<Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let key: String
    let count: Int
    let vertical: Bool
    @ViewBuilder let content: (Int) -> Content
    @Stored private var initial: [Double]?
    var body: some View {
        GeometryReader { g in
            let length = max(1, (vertical ? g.size.height : g.size.width) - CGFloat(max(0, count - 1)) * 6)
            let weights = model.splitWeights(key, count: count)
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ForEach(0..<count, id: \.self) { i in
                    content(i).frame(width: vertical ? nil : length * weights[i], height: vertical ? length * weights[i] : nil)
                        .frame(maxWidth: vertical ? .infinity : nil, maxHeight: vertical ? nil : .infinity).clipped()
                    if i + 1 < count {
                        Rectangle().fill(SwiftUI.Color(t.panel)).frame(width: vertical ? nil : 6, height: vertical ? 6 : nil)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                                let start = initial ?? weights; initial = start
                                let delta = Double(vertical ? v.translation.height : v.translation.width) / Double(length)
                                let pair = start[i] + start[i + 1], minimum = min(0.12, pair / 3)
                                var next = start
                                next[i] = min(max(start[i] + delta, minimum), pair - minimum)
                                next[i + 1] = pair - next[i]
                                model.setSplitWeights(next, key: key)
                            }.onEnded { _ in initial = nil })
                            .accessibilityLabel(L("Separador de paneles"))
                    }
                }
            }
        }
    }
}
