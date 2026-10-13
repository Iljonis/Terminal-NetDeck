import AppKit
import NetDeckCore
import SwiftUI

/// Sesiones del ssh_config por grupos («# @grupo»), con ★ favoritas, ↻ recientes y buscador. Clic derecho: editar,
/// duplicar, favorita… · en un grupo: abrir todas, nueva sesión, renombrar…
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Stored private var query = ""
    @Stored private var collapsed: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, prompt: "Buscar sesión, equipo o IP")
                .padding(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if query.isEmpty {
                        let favs = model.favorites.compactMap(model.sessions.profile(named:))
                        if !favs.isEmpty {
                            header("★ FAVORITAS", count: favs.count, group: nil)
                            ForEach(favs) { SessionRow(profile: $0).id("fav:" + $0.name) }
                        }
                        let recents = model.recents.filter { !model.favorites.contains($0) }.prefix(5)
                            .compactMap(model.sessions.profile(named:))
                        if !recents.isEmpty {
                            header("↻ RECIENTES", count: recents.count, group: nil)
                            ForEach(recents) { SessionRow(profile: $0).id("rec:" + $0.name) }
                        }
                    }
                    ForEach(groups, id: \.name) { g in
                        header(g.name.uppercased(), count: g.profiles.count, group: g.name)
                        if !collapsed.contains(g.name) || !query.isEmpty {
                            ForEach(g.profiles) { SessionRow(profile: $0) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            NeonLine(color: t.panel)
            HStack(spacing: 6) {
                IconButton(icon: "plus") { model.editSessions(.new(group: nil)) }
                    .help("Nueva sesión")
                IconButton(icon: "slider.horizontal.3") { model.editSessions() }
                    .help("Gestionar sesiones y grupos")
                IconButton(icon: "square.and.arrow.down") { model.editSessions(.importing) }
                    .help("Importar de SecureCRT, MobaXterm, PuTTY, CSV…")
                Text(model.sessions.source?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "sesiones de ejemplo")
                    .lineLimit(1).truncationMode(.head)
                    .foregroundStyle(SwiftUI.Color(t.dim))
                Spacer()
                IconButton(icon: "arrow.clockwise") { model.reloadSessions(); model.loadFavorites() }
                    .help("Recargar el ssh_config (⇧⌘R)")
            }
            .font(t.ui(10))
            .padding(.horizontal, 8)
            .frame(height: 38)
        }
        .background(SwiftUI.Color(t.bar))
    }

    private func header(_ title: String, count: Int, group: String?) -> some View {
        HStack(spacing: 6) {
            if let g = group {
                Image(systemName: collapsed.contains(g) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(SwiftUI.Color(t.dim)).frame(width: 9)
            }
            Text(title).font(t.ui(10, .bold)).tracking(2)
                .foregroundStyle(SwiftUI.Color(group == nil ? t.warning : t.accent2))
            Rectangle().fill(SwiftUI.Color(t.accent2).opacity(0.25)).frame(height: 1)
            Text("\(count)").font(t.ui(9.5)).foregroundStyle(SwiftUI.Color(t.dim))
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let g = group else { return }
            if collapsed.contains(g) { collapsed.remove(g) } else { collapsed.insert(g) }
        }
        .contextMenu {
            if let g = group, let ps = model.sessions.groups.first(where: { $0.name == g })?.profiles {
                Button("Abrir las \(ps.count)") { ps.forEach(model.open) }
                Button("Abrir las \(ps.count) en vista dividida") {
                    let before = Set(model.tabs.map(\.id))
                    ps.forEach(model.open)
                    let new = model.tabs.filter { !before.contains($0.id) }.map(\.id)
                    if new.count > 1 {
                        model.split = Split(layout: new.count <= 4 ? .grid4 : .grid, panes: new)
                        model.showSplit = true
                    }
                }
                Divider()
                Button("Nueva sesión en «\(g)»") { model.editSessions(.new(group: g)) }
                Button("Gestionar el grupo…") { model.editSessions(ps.first.map { .session($0.name) }) }
            }
        }
    }

    private var groups: [(name: String, profiles: [SessionProfile])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.sessions.groups }
        return model.sessions.groups.compactMap { g in
            let ps = g.profiles.filter {
                [$0.name, $0.endpoint.description, $0.summary ?? "", $0.group ?? ""].contains { $0.lowercased().contains(q) }
            }
            return ps.isEmpty ? nil : (g.name, ps)
        }
    }
}

struct SearchField: View {
    @Environment(\.theme) private var t
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(SwiftUI.Color(focused ? t.accent : t.dim))
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(SwiftUI.Color(t.dim)))
                .textFieldStyle(.plain)
                .focused($focused)
                .foregroundStyle(SwiftUI.Color(t.text))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(SwiftUI.Color(t.dim))
            }
        }
        .font(t.ui(12))
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(SwiftUI.Color(t.panel).opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(SwiftUI.Color(t.accent).opacity(focused ? 0.8 : 0.15)))
        .shadow(color: SwiftUI.Color(t.accent).opacity(focused ? 0.35 : 0), radius: t.glow(5))
    }
}

struct SessionRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let profile: SessionProfile
    @Stored private var hover = false

    var body: some View {
        Button { model.open(profile) } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color(hover ? t.accent : t.accent2))
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(SwiftUI.Color(t.panel)))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(profile.name).font(t.ui(12.5, .semibold)).foregroundStyle(SwiftUI.Color(t.text))
                        if model.tabs.contains(where: { $0.route.sessionName == profile.name }) {
                            Circle().fill(SwiftUI.Color(t.good)).frame(width: 5, height: 5).help("Abierta")
                        }
                    }
                    Text(subtitle).font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(SwiftUI.Color(t.panel).opacity(hover ? 0.55 : 0)))
            .overlay(alignment: .leading) {
                Rectangle().fill(SwiftUI.Color(t.accent)).frame(width: 2).opacity(hover ? 1 : 0)
                    .shadow(color: SwiftUI.Color(t.accent), radius: t.glow(3))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(profile.summary ?? profile.endpoint.description)
        .contextMenu {
            Button("Conectar") { model.open(profile) }
            Button("Conectar en la vista dividida") {
                if let r = try? model.sessions.route(to: profile) { model.addToSplit(model.open(r)) }
            }
            Divider()
            Button(model.favorites.contains(profile.name) ? "Quitar de ★ favoritas" : "★ Favorita") {
                model.toggleFavorite(profile.name)
            }
            Button("Editar…") { model.editSessions(.session(profile.name)) }
            Button("Duplicar…") { model.editSessions(.session(profile.name)) }
            Divider()
            Button("Copiar orden ssh") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("ssh \(profile.name)", forType: .string)
            }
        }
    }

    private var icon: String {
        if profile.transport == .telnet { return "cable.connector" }
        return profile.proxyJump.isEmpty ? "terminal.fill" : "arrow.triangle.turn.up.right.diamond.fill"
    }

    private var subtitle: String {
        var s = profile.endpoint.description
        if !profile.proxyJump.isEmpty { s += "  ⟵ " + profile.proxyJump.joined(separator: ", ") }
        if profile.transport == .telnet { s += " · telnet" }
        return s
    }
}
