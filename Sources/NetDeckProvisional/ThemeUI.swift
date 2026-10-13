import AppKit
import NetDeckCore
import SwiftTerm
import SwiftUI

// MARK: - colores

extension SwiftUI.Color {
    init(_ c: RGB) { self.init(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: c.a) }
}

extension NSColor {
    convenience init(_ c: RGB) { self.init(srgbRed: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: c.a) }
}

extension SwiftTerm.Color {
    convenience init(_ c: RGB) {
        self.init(red: UInt16(c.r.rounded()) * 257, green: UInt16(c.g.rounded()) * 257, blue: UInt16(c.b.rounded()) * 257)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.builtIn
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - fuentes

enum Fonts {
    static func isInstalled(_ family: String) -> Bool {
        NSFontManager.shared.availableMembers(ofFontFamily: family) != nil
    }

    /// La primera instalada de la lista (la oficial del tema primero), o nil.
    static func firstInstalled(_ families: [String]) -> String? { families.first(where: isInstalled) }

    static func terminal(family: String?, size: CGFloat) -> NSFont {
        if let family, isInstalled(family),
           let f = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) { return f }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Las monoespaciadas instaladas (para elegir otra).
    static func monospacedFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies.filter { fam in
            !fam.hasPrefix(".") && (NSFont(name: fam, size: 12)?.isFixedPitch ?? false)
        }
    }

    /// Como NetDeck: la fuente con Homebrew («font-m-plus-1-code»). false si no hay Homebrew o no existe.
    static func install(_ family: String) async -> Bool {
        if isInstalled(family) { return true }
        let cask = "font-" + family.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: FileManager.default.fileExists)
        else { return false }
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: brew)
            p.arguments = ["install", "--cask", cask]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }.value
        return isInstalled(family)
    }
}

extension Theme {
    /// Letra de la interfaz: la del tema («fuente_interfaz», o si no la del terminal) si está instalada; «sistema» = la
    /// del Mac (SF Pro); si no, la monoespaciada del sistema.
    func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        for f in uiFonts {
            if f.lowercased() == "sistema" || f == "SF Pro" { return .system(size: size, weight: weight) }
            if Fonts.isInstalled(f) { return .custom(f, size: size).weight(weight) }
        }
        if !uiFonts.isEmpty { return .system(size: size, weight: weight) }
        if let f = Fonts.firstInstalled(fonts) { return .custom(f, size: size).weight(weight) }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    var neon: Bool { style == .neon }
    /// Brillo de neón (sólo en el estilo de NetDeck).
    func glow(_ r: CGFloat) -> CGFloat { neon ? r : 0 }
    /// Esquinas: chaflán cyberpunk o redondeadas (cristal: más; fluent: 6).
    var corner: CGFloat? {
        switch style {
        case .neon: nil
        case .glass: 10
        case .fluent: 6
        }
    }
    /// Seguimiento de las mayúsculas de los títulos (el neón las espacia).
    var tracking: CGFloat { neon ? 2.5 : 0.6 }
}

// MARK: - temas

@MainActor @Observable
final class ThemeStore {
    let library = ThemeLibrary(appDirectory: ThemeStore.appDirectory())
    private(set) var current = Theme.builtIn
    /// Todos (los de la app ya están: no se instalan).
    private(set) var all: [(theme: Theme, source: ThemeLibrary.Source)] = []
    var busy: String?

    init(selected id: String) {
        refresh()
        current = library.theme(id: id) ?? .builtIn
    }

    func refresh() { all = library.all() }

    func theme(id: String) -> Theme? { all.first { $0.theme.id == id }?.theme }

    func select(_ id: String) { current = theme(id: id) ?? .builtIn }

    func importTheme(file: URL) -> String {
        do {
            let t = try library.importTheme(file: file)
            refresh()
            return "Tema «\(t.name)» importado"
        } catch {
            return "\(file.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func remove(_ id: String) {
        try? library.remove(id)
        refresh()
        if current.id == id { current = .builtIn }
    }

    nonisolated static func appDirectory() -> URL? { AppResources.directory("Temas") }
}

/// Lo que trae la app: dentro del .app (Contents/Resources/…) o, con «swift run», la carpeta del proyecto.
enum AppResources {
    static func directory(_ name: String) -> URL? {
        let fm = FileManager.default
        if let r = Bundle.main.resourceURL?.appendingPathComponent(name), fm.fileExists(atPath: r.path) { return r }
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { u.deleteLastPathComponent() }
        u.appendPathComponent(name)
        return fm.fileExists(atPath: u.path) ? u : nil
    }
}

// MARK: - piezas con la estética del tema

/// Aspecto de los botones de la barra: borde de neón que se enciende al pasar por encima.
struct NeonLabel: View {
    @Environment(\.theme) private var t
    let title: String
    let icon: String
    var tint: RGB?
    var active = false
    @Stored private var hover = false

    var body: some View {
        let c = SwiftUI.Color(tint ?? t.accent)
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(title).font(t.ui(11.5, .semibold)).lineLimit(1)
        }
        .foregroundStyle(active ? SwiftUI.Color((tint ?? t.accent).readable) : (hover && t.neon ? c : SwiftUI.Color(t.text)))
        .padding(.horizontal, t.style == .glass ? 12 : 10)
        .frame(height: t.style == .glass ? 28 : 26)
        .background { background(c) }
        .overlay(shape.strokeBorder(border(c), lineWidth: 1))
        .shadow(color: c.opacity(hover || active ? 0.55 : 0), radius: t.glow(6))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    /// Neón: rectángulo con borde encendido · cristal: cápsula de vidrio · fluent: rectángulo de 4 px.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: t.style == .glass ? 14 : (t.style == .fluent ? 4 : 6), style: .continuous)
    }

    @ViewBuilder private func background(_ c: SwiftUI.Color) -> some View {
        switch t.style {
        case .neon:
            shape.fill(active ? c : SwiftUI.Color(t.panel).opacity(hover ? 0.9 : 0.55))
        case .glass:
            if active { shape.fill(c) } else {
                shape.fill(.ultraThinMaterial).overlay(shape.fill(SwiftUI.Color.white.opacity(hover ? 0.14 : 0.06)))
            }
        case .fluent:
            shape.fill(active ? c : SwiftUI.Color(t.panel).opacity(hover ? 1 : 0.75))
        }
    }

    private func border(_ c: SwiftUI.Color) -> SwiftUI.Color {
        switch t.style {
        case .neon: c.opacity(hover || active ? 0.95 : 0.3)
        case .glass: SwiftUI.Color.white.opacity(t.isLight ? 0.5 : (hover ? 0.35 : 0.18))
        case .fluent: SwiftUI.Color(t.text).opacity(active ? 0 : 0.09)
        }
    }
}

/// Desenfoque de lo que hay detrás de la ventana (temas de cristal / mica).
struct BehindWindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = material
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

extension Theme {
    var blurMaterial: NSVisualEffectView.Material {
        material == "mica" ? .underWindowBackground : (isLight ? .popover : .hudWindow)
    }
}

struct NeonButton: View {
    let title: String
    let icon: String
    var tint: RGB?
    var active = false
    var action: () -> Void

    var body: some View {
        Button(action: action) { NeonLabel(title: title, icon: icon, tint: tint, active: active) }
            .buttonStyle(.plain)
    }
}

/// Línea fina de neón.
struct NeonLine: View {
    @Environment(\.theme) private var t
    var vertical = false
    var color: RGB?

    var body: some View {
        let c = SwiftUI.Color(color ?? t.accent)
        Rectangle()
            .fill(c.opacity(0.35))
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .shadow(color: c.opacity(0.6), radius: t.glow(3))
    }
}

/// Pestaña con la esquina superior derecha cortada (chaflán) o, en los temas de sistema, redondeada.
struct ChamferShape: Shape {
    var cut: CGFloat = 9
    var radius: CGFloat?

    func path(in r: CGRect) -> Path {
        if let radius { return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: r) }
        return Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// Rejilla en perspectiva y líneas de barrido (portada).
struct GridBackground: View {
    @Environment(\.theme) private var t
    var scanlines = true

    var body: some View {
        Canvas { ctx, size in
            let accent = SwiftUI.Color(t.accent2)
            let horizon = size.height * 0.55
            for i in 0..<14 {                                         // horizontales, cada vez más juntas
                let y = horizon + pow(Double(i) / 13, 1.8) * (size.height - horizon)
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(accent.opacity(0.05 + 0.10 * Double(i) / 13)), lineWidth: 1)
            }
            for i in -12...12 {                                       // hacia el punto de fuga
                let x = size.width / 2 + Double(i) * size.width / 10
                ctx.stroke(Path { $0.move(to: CGPoint(x: size.width / 2 + Double(i) * 18, y: horizon))
                                  $0.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(accent.opacity(0.10)), lineWidth: 1)
            }
            if scanlines {
                var y = 0.0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.18)))
                    y += 3
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Muestra de colores de un tema (Ajustes → Temas).
struct ThemeSwatch: View {
    let theme: Theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array([theme.background, theme.panel, theme.accent, theme.accent2, theme.good, theme.bad,
                           theme.special, theme.text].enumerated()), id: \.offset) { _, c in
                Rectangle().fill(SwiftUI.Color(c))
            }
        }
        .frame(width: 120, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.15)))
    }
}
