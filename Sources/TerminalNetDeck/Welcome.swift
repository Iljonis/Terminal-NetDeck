import NetDeckCore
import SwiftUI

/// Portada (sin pestañas): rótulo, conexión rápida, sesiones y atajos.
struct Welcome: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Stored private var target = ""
    @Stored private var jump = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            RadialGradient(colors: [SwiftUI.Color(t.accent).opacity(t.neon ? 0.16 : 0.08), .clear], center: .top, startRadius: 10, endRadius: 700)
            if model.settings.crtEffect, t.neon { GridBackground() }
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        if t.neon {
                            PixelBanner(text: L("NETDECK"))
                        } else {
                            Text(L("NetDeck")).font(t.ui(52, .bold)).foregroundStyle(SwiftUI.Color(t.text))
                        }
                        Text(t.neon ? L("TERMINAL NATIVO PARA INGENIEROS DE RED") : L("Terminal nativo para ingenieros de red"))
                            .font(t.ui(t.neon ? 11 : 14, .semibold)).tracking(t.neon ? 5 : 0)
                            .foregroundStyle(SwiftUI.Color(t.neon ? t.accent2 : t.dim))
                    }
                    .padding(.top, 40)
                    quickConnect
                    if !model.lastOpen.isEmpty {
                        NeonButton(title: (model.lastOpenWindows > 1
                                           ? L("Reabrir las \(model.lastOpen.count) de la última vez, en \(model.lastOpenWindows) ventanas: ")
                                           : L("Reabrir las \(model.lastOpen.count) de la última vez: "))
                                   + model.lastOpen.prefix(4).map(\.title).joined(separator: ", ")
                                   + (model.lastOpen.count > 4 ? "…" : ""),
                                   icon: "arrow.counterclockwise", tint: t.good) { model.reopenLast() }
                    }
                    if !matches.isEmpty { sessionGrid }
                    shortcuts
                }
                .frame(maxWidth: 900)
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { focused = true }
    }

    private var quickConnect: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right").font(.system(size: 15, weight: .black)).foregroundStyle(SwiftUI.Color(t.accent))
            TextField("", text: $target,
                      prompt: Text(L("sesión · usuario@equipo[:puerto]")).foregroundStyle(SwiftUI.Color(t.dim)))
                .textFieldStyle(.plain)
                .font(t.ui(16, .medium))
                .foregroundStyle(SwiftUI.Color(t.text))
                .focused($focused)
                .onSubmit(connect)
            JumpPicker(jump: $jump)
            NeonButton(title: L("CONECTAR"), icon: "return", tint: t.accent, active: !target.isEmpty, action: connect)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 10).fill(SwiftUI.Color(t.panel).opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SwiftUI.Color(t.accent).opacity(focused ? 0.9 : 0.35), lineWidth: 1))
        .shadow(color: SwiftUI.Color(t.accent).opacity(focused ? 0.45 : 0.15), radius: t.glow(14))
    }

    private var sessionGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(target.isEmpty ? L("SESIONES") : L("COINCIDEN"))
                .font(t.ui(10, .bold)).tracking(3).foregroundStyle(SwiftUI.Color(t.dim))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(matches) { SessionCard(profile: $0) }
            }
        }
    }

    private var shortcuts: some View {
        HStack(spacing: 8) {
            ForEach([("⌘K", L("Conectar")), ("⌘T", L("Terminal local")), ("⇧⌘L", L("Listas")), ("⇧⌘V", L("Pegado seguro")), ("⇧⌘M", L("MultiExec")),
                     (L("Esc"), L("Cancelar")), ("⌘,", L("Ajustes"))], id: \.0) { k, v in
                HStack(spacing: 5) {
                    Text(k).font(t.ui(10, .bold)).foregroundStyle(SwiftUI.Color(t.accent))
                    Text(v).font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(SwiftUI.Color(t.panel)))
            }
        }
    }

    private var matches: [SessionProfile] {
        let q = target.trimmingCharacters(in: .whitespaces).lowercased()
        let all = model.sessions.profiles
        guard !q.isEmpty else { return Array(all.prefix(12)) }
        return all.filter { $0.name.lowercased().contains(q) || $0.endpoint.description.lowercased().contains(q) }.prefix(12).map { $0 }
    }

    private func connect() {
        model.quickConnect(target, via: jump)
        target = ""
    }
}

struct SessionCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let profile: SessionProfile
    @Stored private var hover = false

    var body: some View {
        Button { model.open(profile) } label: {
            // (como una fila de la lista de sesiones: icono y color del tipo, ★, usuario@equipo y su carpeta)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: profile.transport.icon(jump: !profile.proxyJump.isEmpty))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SwiftUI.Color(profile.transport.tint(t)))
                        .frame(width: 16)
                    Text(profile.name).font(t.ui(13, .bold)).foregroundStyle(SwiftUI.Color(t.text)).lineLimit(1)
                    Spacer(minLength: 0)
                    if model.favorites.contains(profile.name) {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(SwiftUI.Color(t.warning))
                    }
                }
                Text(destination).font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim)).lineLimit(1)
                if let g = profile.group {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill").font(.system(size: 8.5))
                        Text(GroupTree.components(g).map { L(nombre: $0) }.joined(separator: " › "))
                            .font(t.ui(9.5, .semibold)).lineLimit(1)
                    }
                    .foregroundStyle(SwiftUI.Color(t.accent))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChamferShape(cut: 12, radius: t.corner).fill(SwiftUI.Color(t.panel).opacity(hover ? 0.95 : 0.55)))
            .overlay(ChamferShape(cut: 12, radius: t.corner).stroke(SwiftUI.Color(t.accent).opacity(hover ? 0.9 : 0.2), lineWidth: 1))
            .shadow(color: SwiftUI.Color(t.accent).opacity(hover ? 0.4 : 0), radius: t.glow(10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(profile.summary ?? profile.endpoint.description)
    }

    private var destination: String {
        switch profile.transport {
        case .serial: profile.serial?.device ?? L("Serie")
        case .local: L("Este Mac")
        case .ssh, .telnet, .sftp, .ftp: profile.endpoint.description
        }
    }
}

/// Rótulo de bloques de NetDeck (5×5) dibujado como píxeles de neón, con un leve desfase cromático.
struct PixelBanner: View {
    @Environment(\.theme) private var t
    let text: String
    var cell: CGFloat = 11

    var body: some View {
        let grid = Banner.grid(text)
        let cols = grid.first?.count ?? 0
        Canvas { ctx, _ in
            func draw(_ color: SwiftUI.Color, dx: CGFloat) {
                for (y, row) in grid.enumerated() {
                    for (x, on) in row.enumerated() where on {
                        ctx.fill(Path(CGRect(x: CGFloat(x) * cell + dx, y: CGFloat(y) * cell, width: cell - 2, height: cell - 2)),
                                 with: .color(color))
                    }
                }
            }
            draw(SwiftUI.Color(t.accent2).opacity(0.55), dx: -3)
            draw(SwiftUI.Color(t.accent), dx: 0)
        }
        .frame(width: CGFloat(cols) * cell + 3, height: 5 * cell)
        .shadow(color: SwiftUI.Color(t.accent).opacity(0.75), radius: t.glow(12))
    }
}

/// Salto para la conexión rápida, con la estética del tema.
struct JumpPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Binding var jump: String

    var body: some View {
        ThemedMenu {
            Button(L("Directo")) { jump = "" }
            MenuDivider()
            ForEach(model.sessions.profiles) { p in Button("⟵ \(p.name)") { jump = p.name } }
        } label: {
            NeonLabel(title: jump.isEmpty ? L("directo") : "⟵ \(jump)", icon: "arrow.triangle.branch", tint: t.accent2)
        }
        .fixedSize()
    }
}
