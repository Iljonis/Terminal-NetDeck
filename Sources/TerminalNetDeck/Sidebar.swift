import AppKit
import NetDeckCore
import SwiftUI

/// Sesiones del ssh_config por grupos («# @grupo»; con «/», carpetas dentro de carpetas), con ★ favoritas, ↻ recientes
/// y buscador. Clic derecho: editar, duplicar, borrar, favorita… · en una carpeta: abrir todas, nueva sesión…
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Stored private var query = ""
    @Stored private var collapsed: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, prompt: L("Buscar sesión, equipo, IP, usuario o tipo"))
                .padding(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if query.isEmpty {
                        let favs = model.favorites.compactMap(model.sessions.profile(named:))
                        if !favs.isEmpty {
                            header(L("★ FAVORITAS"), count: favs.count, group: nil)
                            ForEach(favs) { SessionRow(profile: $0).id("fav:" + $0.name) }
                        }
                        let recents = model.recents.filter { !model.favorites.contains($0) }.prefix(5)
                            .compactMap(model.sessions.profile(named:))
                        if !recents.isEmpty {
                            header(L("↻ RECIENTES"), count: recents.count, group: nil)
                            ForEach(recents) { SessionRow(profile: $0).id("rec:" + $0.name) }
                        }
                    }
                    ForEach(rows) { r in
                        switch r.row {
                        case .folder(let path, let name, let depth, let count):
                            header(L(nombre: name).uppercased(), count: count, group: path, depth: depth)
                        case .item(let p, let depth):
                            SessionRow(profile: p, depth: depth)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            NeonLine(color: t.panel)
            HStack(spacing: 6) {
                IconButton(icon: "plus") { model.editSessions(.new(group: nil)) }
                    .help(L("Nueva sesión"))
                IconButton(icon: "slider.horizontal.3") { model.editSessions() }
                    .help(L("Gestionar sesiones y grupos"))
                IconButton(icon: "square.and.arrow.down") { model.editSessions(.importing) }
                    .help(L("Importar de SecureCRT, MobaXterm, PuTTY, CSV…"))
                IconButton(icon: "list.bullet.rectangle") { model.sheet = .list }
                    .help(L("Listas de equipos: la misma orden en muchos equipos por un salto (⇧⌘L)"))
                Text(model.sessions.source?.path.replacingOccurrences(of: AppPaths.home.path, with: "~") ?? L("sesiones de ejemplo"))
                    .lineLimit(1).truncationMode(.head)
                    .foregroundStyle(SwiftUI.Color(t.dim))
                Spacer()
                IconButton(icon: "arrow.clockwise") { model.reloadSessions(); model.loadFavorites() }
                    .help(L("Recargar el ssh_config (⇧⌘R)"))
            }
            .font(t.ui(10))
            .padding(.horizontal, 8)
            .frame(height: 38)
        }
        .background(SwiftUI.Color(t.bar))
    }

    private func header(_ title: String, count: Int, group: String?, depth: Int = 0) -> some View {
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
        .padding(.leading, CGFloat(depth) * 12)
        .padding(.top, depth == 0 ? 12 : 6)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let g = group else { return }
            if collapsed.contains(g) { collapsed.remove(g) } else { collapsed.insert(g) }
        }
        .contextMenu {
            if let g = group, case let ps = profiles(under: g), !ps.isEmpty {
                Button(L("Abrir las \(ps.count)")) { ps.forEach(model.open) }
                Button(L("Abrir las \(ps.count) en vista dividida")) {
                    let before = Set(model.tabs.map(\.id))
                    ps.forEach(model.open)
                    let new = model.tabs.filter { !before.contains($0.id) }.map(\.id)
                    if new.count > 1 {
                        model.split = Split(layout: new.count <= 4 ? .grid4 : .grid, panes: new)
                        model.showSplit = true
                    }
                }
                Divider()
                Button(L("Nueva sesión en «\(g)»")) { model.editSessions(.new(group: g)) }
                Button(L("Gestionar el grupo…")) { model.editSessions(ps.first.map { .session($0.name) }) }
            }
        }
    }

    /// Las sesiones de una carpeta y de sus subcarpetas (para «Abrir las N»).
    private func profiles(under path: String) -> [SessionProfile] {
        model.sessions.groups.filter { $0.name == path || GroupTree.contains(path, $0.name) }.flatMap(\.profiles)
    }

    private struct Row: Identifiable {
        let id: String
        let row: GroupTree.Row<SessionProfile>
    }

    /// Carpetas (anidadas con «/») y sesiones; buscando, todo abierto y sólo lo que encaja (nombre, equipo, usuario,
    /// descripción, grupo, tipo o puerto serie).
    private var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let groups: [(name: String, items: [SessionProfile])] = model.sessions.groups.compactMap { g in
            let ps = q.isEmpty ? g.profiles : g.profiles.filter { p in
                [p.name, p.endpoint.description, p.user ?? "", p.summary ?? "", p.group ?? "", p.transport.label,
                 p.transport.rawValue, p.serial?.device ?? ""].contains { $0.lowercased().contains(q) }
            }
            return ps.isEmpty ? nil : (g.name, ps)
        }
        return GroupTree.rows(groups, collapsed: q.isEmpty ? collapsed : []).map { r in
            switch r {
            case .folder(let path, _, _, _): Row(id: "g:" + path, row: r)
            case .item(let p, _): Row(id: "s:" + p.name, row: r)
            }
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
    /// Sangría dentro de las carpetas anidadas (1 = en una carpeta de primer nivel).
    var depth = 1
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
                        if model.settings.startupSession == profile.name {
                            Image(systemName: "power").font(.system(size: 8, weight: .bold))
                                .foregroundStyle(SwiftUI.Color(t.warning)).help(L("Se abre al arrancar (⌥⌘K)"))
                        }
                        if model.tabs.contains(where: { $0.route.sessionName == profile.name }) {
                            Circle().fill(SwiftUI.Color(t.good)).frame(width: 5, height: 5).help(L("Abierta"))
                        }
                    }
                    Text(subtitle).font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .padding(.leading, CGFloat(max(0, depth - 1)) * 12)
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
            Button(L("Conectar")) { model.open(profile) }
            if profile.transport != .ftp {
                Button(L("Conectar en la vista dividida")) {
                    if let r = try? model.sessions.route(to: profile) { model.addToSplit(model.open(r)) }
                }
            }
            Divider()
            Button(model.favorites.contains(profile.name) ? L("Quitar de ★ favoritas") : L("★ Favorita")) {
                model.toggleFavorite(profile.name)
            }
            Button(model.settings.startupSession == profile.name ? L("No abrir al arrancar") : L("⏻ Abrir al arrancar")) {
                model.toggleStartup(profile.name)
            }
            Divider()
            Button(L("Editar…")) { model.editSessions(.session(profile.name)) }
            Button(L("Duplicar…")) { model.editSessions(.duplicate(profile.name)) }
            Button(L("Nueva sesión en este grupo…")) { model.editSessions(.new(group: profile.group)) }
            Button(L("Borrar…")) { model.deleteSession(profile.name) }
            if profile.transport == .ssh || profile.transport == .sftp {
                Divider()
                Button(profile.transport == .ssh ? L("Copiar orden ssh") : L("Copiar orden sftp")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(profile.transport.rawValue) \(profile.name)", forType: .string)
                }
            }
        }
    }

    private var icon: String { profile.transport.icon(jump: !profile.proxyJump.isEmpty) }

    private var subtitle: String {
        switch profile.transport {
        case .serial: return profile.serial.map { "\($0.device) · \($0.speed) \($0.frame)" } ?? L("Serie")
        case .local: return L("Este Mac")
        case .ssh, .telnet, .sftp, .ftp:
            var s = profile.endpoint.description
            if !profile.proxyJump.isEmpty { s += "  ⟵ " + profile.proxyJump.joined(separator: ", ") }
            if profile.transport != .ssh { s += " · " + profile.transport.label }
            return s
        }
    }
}
