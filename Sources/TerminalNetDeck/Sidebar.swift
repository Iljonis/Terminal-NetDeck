import AppKit
import NetDeckCore
import SwiftUI

/// Sesiones del ssh_config como un gestor de sesiones (SecureCRT/Royal TSX): árbol de carpetas («# @grupo»; con «/»,
/// carpetas dentro de carpetas) con su estado plegado recordado, ★ favoritas y ↻ recientes arriba, y buscador (filtra
/// y despliega lo que encaja). Clic: elegir · doble clic: conectar · clic derecho: editar, duplicar, borrar,
/// favorita… · en una carpeta: abrir todas, nueva sesión…
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Stored private var query = ""
    @Stored private var selected: String?
    /// Carpetas plegadas (rutas, una por línea): se recuerdan entre arranques.
    @AppStorage("sidebarCollapsed") private var collapsedList = ""

    /// Las secciones de arriba también se pliegan (claves que no pueden ser un grupo: los grupos no empiezan por «\t»).
    private static let favKey = "\t★", recentKey = "\t↻"

    private var collapsed: Set<String> { Set(collapsedList.split(separator: "\n").map(String.init)) }

    private func toggle(_ path: String) {
        var c = collapsed
        if c.contains(path) { c.remove(path) } else { c.insert(path) }
        collapsedList = c.sorted().joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, prompt: L("Buscar sesión, equipo, IP, usuario o tipo"))
                .padding(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if query.isEmpty {
                        let favs = model.favorites.compactMap(model.sessions.profile(named:))
                        if !favs.isEmpty {
                            folder(L("Favoritas"), icon: "star.fill", tint: t.warning, key: Self.favKey, count: favs.count)
                            if !collapsed.contains(Self.favKey) {
                                ForEach(favs) { row($0, depth: 1).id("fav:" + $0.name) }
                            }
                        }
                        let recents = model.recents.filter { !model.favorites.contains($0) }.prefix(5)
                            .compactMap(model.sessions.profile(named:))
                        if !recents.isEmpty {
                            folder(L("Recientes"), icon: "clock.arrow.circlepath", tint: t.accent2, key: Self.recentKey,
                                   count: recents.count)
                            if !collapsed.contains(Self.recentKey) {
                                ForEach(recents) { row($0, depth: 1).id("rec:" + $0.name) }
                            }
                        }
                        if !favs.isEmpty || !recents.isEmpty {
                            Rectangle().fill(SwiftUI.Color(t.panel)).frame(height: 1).padding(.vertical, 6).padding(.horizontal, 4)
                        }
                    }
                    ForEach(rows) { r in
                        switch r.row {
                        case .folder(let path, let name, let depth, let count):
                            folder(L(nombre: name), icon: nil, tint: t.accent2, key: path, count: count, depth: depth,
                                   searching: !query.isEmpty)
                        case .item(let p, let depth):
                            row(p, depth: depth)
                        }
                    }
                    if !query.isEmpty, rows.isEmpty {
                        Text(L("Nada coincide con «\(query)»")).font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
                            .padding(.horizontal, 8).padding(.top, 8)
                    }
                }
                .padding(.horizontal, 6)
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
                Text(model.sessions.source.map { AppPaths.tilde($0.path) }
                     ?? (model.sessions.profiles.isEmpty ? L("sin sesiones todavía") : L("sesiones de ejemplo")))
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

    private func row(_ p: SessionProfile, depth: Int) -> some View {
        SessionRow(profile: p, depth: depth, selected: selected == p.name) { selected = p.name }
    }

    /// Carpeta (o sección de arriba): chevron, icono, nombre y cuántas lleva. Buscando, todas abiertas.
    private func folder(_ title: String, icon: String?, tint: RGB, key: String, count: Int, depth: Int = 0,
                        searching: Bool = false) -> some View {
        let open = searching || !collapsed.contains(key)
        let group = key.hasPrefix("\t") ? nil : key
        return FolderRow(title: title, icon: icon ?? (open ? "folder" : "folder.fill"), tint: tint, count: count,
                         depth: depth, open: open) { if !searching { toggle(key) } }
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

/// Sangría por nivel del árbol de sesiones.
private let treeIndent: CGFloat = 14

private struct FolderRow: View {
    @Environment(\.theme) private var t
    let title: String
    let icon: String
    let tint: RGB
    let count: Int
    let depth: Int
    let open: Bool
    let action: () -> Void
    @Stored private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8.5, weight: .bold))
                .rotationEffect(.degrees(open ? 90 : 0))
                .foregroundStyle(SwiftUI.Color(hover ? t.accent : t.dim))
                .frame(width: 10)
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SwiftUI.Color(tint))
                .frame(width: 16)
            Text(title).font(t.ui(12, .semibold)).foregroundStyle(SwiftUI.Color(t.text)).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)").font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim))
        }
        .padding(.leading, 4 + CGFloat(depth) * treeIndent)
        .padding(.trailing, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: t.corner ?? 4).fill(SwiftUI.Color(t.panel).opacity(hover ? 0.55 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { action() } }
        .onHover { hover = $0 }
    }
}

extension SessionProfile.Transport {
    /// Color del icono según el tipo (el mismo en la lista y en la portada).
    func tint(_ t: Theme) -> RGB {
        switch self {
        case .ssh: t.accent2
        case .telnet: t.warning
        case .sftp, .ftp: t.good
        case .serial: t.accent
        case .local: t.text
        }
    }
}

struct SessionRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let profile: SessionProfile
    /// Nivel en el árbol (1 = dentro de una carpeta de primer nivel).
    var depth = 1
    var selected = false
    var select: () -> Void = {}
    @Stored private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(SwiftUI.Color(hover || selected ? t.accent : profile.transport.tint(t)))
                .frame(width: 16)
            Text(profile.name).font(t.ui(12, .medium)).foregroundStyle(SwiftUI.Color(t.text)).lineLimit(1)
                .layoutPriority(1)
            Text(subtitle).font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 2)
            if model.settings.startupSession == profile.name {
                Image(systemName: "power").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(SwiftUI.Color(t.warning)).help(L("Se abre al arrancar (⌥⌘K)"))
            }
            if model.tabs.contains(where: { $0.route.sessionName == profile.name }) {
                Circle().fill(SwiftUI.Color(t.good)).frame(width: 6, height: 6).help(L("Abierta"))
            }
            if model.favorites.contains(profile.name) {
                Image(systemName: "star.fill").font(.system(size: 8.5)).foregroundStyle(SwiftUI.Color(t.warning))
            }
        }
        // (debajo del nombre de su carpeta: chevron + hueco)
        .padding(.leading, 4 + CGFloat(max(0, depth - 1)) * treeIndent + 15)
        .padding(.trailing, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: t.corner ?? 4)
            .fill(SwiftUI.Color(selected ? t.accent : t.panel).opacity(selected ? 0.2 : (hover ? 0.55 : 0))))
        .overlay(alignment: .leading) {
            Rectangle().fill(SwiftUI.Color(t.accent)).frame(width: 2).opacity(selected ? 1 : 0)
                .shadow(color: SwiftUI.Color(t.accent), radius: t.glow(3))
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { select(); model.open(profile) }
        .simultaneousGesture(TapGesture().onEnded { select() })
        .onHover { hover = $0 }
        .help(help)
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

    /// En gris junto al nombre: usuario@equipo (o el puerto serie / «Este Mac»).
    private var subtitle: String {
        switch profile.transport {
        case .serial: return profile.serial?.device ?? L("Serie")
        case .local: return L("Este Mac")
        case .ssh, .telnet, .sftp, .ftp: return profile.endpoint.description
        }
    }

    /// Al pasar el ratón: la descripción, el destino entero, los saltos y el tipo.
    private var help: String {
        var s = profile.endpoint.description
        switch profile.transport {
        case .serial: s = profile.serial.map { "\($0.device) · \($0.speed) \($0.frame)" } ?? L("Serie")
        case .local: s = L("Este Mac")
        case .ssh, .telnet, .sftp, .ftp:
            if !profile.proxyJump.isEmpty { s += "  ⟵ " + profile.proxyJump.joined(separator: ", ") }
            if profile.transport != .ssh { s += " · " + profile.transport.label }
        }
        return [profile.summary, s].compactMap { $0 }.joined(separator: "\n")
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

