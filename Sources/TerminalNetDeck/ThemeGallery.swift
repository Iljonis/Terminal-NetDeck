import NetDeckCore
import SwiftUI

/// Todos los temas por grupos, en tarjetas con su muestra. Pasar por encima = vista previa; clic = usarlo.
struct ThemeGallery: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let active: String
    let select: (String) -> Void
    var hover: (String?) -> Void = { _ in }
    var remove: ((String) -> Void)?

    var body: some View {
        let all = model.themes.all
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Theme.groups + [""], id: \.self) { g in
                let items = all.filter { $0.theme.group == g || (g.isEmpty && !Theme.groups.contains($0.theme.group)) }
                if !items.isEmpty {
                    HStack {
                        Text(g.isEmpty ? L("OTROS") : L(nombre: g).uppercased()).font(t.ui(10, .bold)).tracking(2.5)
                            .foregroundStyle(SwiftUI.Color(t.accent2))
                        Rectangle().fill(SwiftUI.Color(t.accent2).opacity(0.25)).frame(height: 1)
                        Text("\(items.count)").font(t.ui(9.5)).foregroundStyle(SwiftUI.Color(t.dim))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 186), spacing: 12)], spacing: 12) {
                        ForEach(items, id: \.theme.id) { item in
                            ThemeCard(theme: item.theme, active: item.theme.id == active, badge: badge(item.source))
                                .onTapGesture { select(item.theme.id) }
                                .onHover { hover($0 ? item.theme.id : nil) }
                                .contextMenu {
                                    Button(L("Usar «\(item.theme.name)»")) { select(item.theme.id) }
                                    if item.source == .imported, let remove {
                                        Button(L("Quitar (importado)")) { remove(item.theme.id) }
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private func badge(_ s: ThemeLibrary.Source) -> String? {
        switch s {
        case .imported: L("importado")
        case .netdeck: L("de NetDeck")
        default: nil
        }
    }
}

/// Tarjeta de un tema: en pequeño, cómo se ve (prompt y salida) con sus colores.
struct ThemeCard: View {
    let theme: Theme
    let active: Bool
    var badge: String?
    @Stored private var hover = false

    var body: some View {
        let th = theme
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("admin").foregroundStyle(SwiftUI.Color(th.accent2))
                    Text("@").foregroundStyle(SwiftUI.Color(th.dim))
                    Text("core-01").foregroundStyle(SwiftUI.Color(th.accent))
                    Text("> ").foregroundStyle(SwiftUI.Color(th.bad))
                    Text("show int").foregroundStyle(SwiftUI.Color(th.text))
                }
                HStack(spacing: 0) {
                    Text("xe-0/0/1 ").foregroundStyle(SwiftUI.Color(th.accent))
                    Text("up ").foregroundStyle(SwiftUI.Color(th.good))
                    Text("192.0.2.1 ").foregroundStyle(SwiftUI.Color(th.accent2))
                    Text("down").foregroundStyle(SwiftUI.Color(th.bad))
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SwiftUI.Color(th.background))
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(th.name).font(th.ui(12, .bold)).foregroundStyle(SwiftUI.Color(th.onTab)).lineLimit(1)
                    Text(badge ?? (th.fonts.first ?? "")).font(.system(size: 9.5))
                        .foregroundStyle(SwiftUI.Color(th.onTab).opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 0)
                if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(SwiftUI.Color(th.onTab)) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(SwiftUI.Color(th.tab))
        }
        .clipShape(ChamferShape(cut: 12, radius: th.corner))
        .overlay(ChamferShape(cut: 12, radius: th.corner).stroke(SwiftUI.Color(th.accent).opacity(active ? 1 : (hover ? 0.7 : 0.15)),
                                              lineWidth: active ? 2 : 1))
        .shadow(color: SwiftUI.Color(th.accent).opacity(active ? 0.6 : (hover ? 0.35 : 0)), radius: th.glow(10))
        .scaleEffect(hover ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: hover)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .help(th.summary.isEmpty ? th.name : th.summary)
    }
}

/// La app en pequeño con ese tema: barra, botones, pestaña y salida resaltada.
struct ThemePreview: View {
    let theme: Theme

    var body: some View {
        let t = theme
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Brand()
                Spacer().frame(width: 6)
                NeonLabel(title: L("Conectar"), icon: "bolt.horizontal.fill")
                NeonLabel(title: L("Contraseña"), icon: "key.fill")
                NeonLabel(title: L("MultiExec"), icon: "square.stack.3d.forward.dottedline.fill", tint: t.warning, active: true)
                Spacer()
                Text(t.clockText()).font(t.ui(11, .bold)).foregroundStyle(SwiftUI.Color(t.accent))
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(SwiftUI.Color(t.bar))
            .overlay(alignment: .bottom) { NeonLine() }
            HStack(spacing: 4) {
                Text("core-01").font(t.ui(11, .semibold)).foregroundStyle(SwiftUI.Color(t.onTab))
                    .padding(.horizontal, 12).frame(height: 24)
                    .background(ChamferShape(radius: t.corner).fill(SwiftUI.Color(t.tab)))
                Text("bastion").font(t.ui(11, .semibold)).foregroundStyle(SwiftUI.Color(t.accent2))
                    .padding(.horizontal, 12).frame(height: 24)
                    .background(ChamferShape(radius: t.corner).fill(SwiftUI.Color(t.panel).opacity(0.6)))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .background(SwiftUI.Color(t.bar))
            .overlay(alignment: .bottom) { Rectangle().fill(SwiftUI.Color(t.tab)).frame(height: 2) }
            HighlightPreview()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .background(SwiftUI.Color(t.background))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SwiftUI.Color(t.accent).opacity(0.5)))
        .shadow(color: SwiftUI.Color(t.accent).opacity(0.25), radius: t.glow(12))
        .environment(\.theme, t)
        .animation(.easeOut(duration: 0.15), value: t.id)
    }
}
