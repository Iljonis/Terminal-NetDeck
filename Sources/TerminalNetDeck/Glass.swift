import NetDeckCore
import SwiftUI

// Liquid Glass de macOS 26 en las piezas que flotan sobre la barra (botones de icono, pestañas, «VISTA», el aviso y el
// menú «+»), sólo con los temas de cristal. El terminal nunca: su fondo sigue siendo el del tema. En macOS 15, con
// otro tema o con «Reducir transparencia» / «Aumentar contraste», todo queda como antes (el fondo de siempre).

extension Theme {
    /// Cristal de verdad: macOS 26, un tema «cristal» y transparente (con Accesibilidad, `ThemeStore` ya lo da opaco).
    var liquidGlass: Bool {
        guard style == .glass, isTranslucent else { return false }
        if #available(macOS 26, *) { return true }
        return false
    }
}

private struct GlassOnKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Dentro de un `GlassGroup` con cristal: `netdeckGlass` lo pinta.
    fileprivate(set) var glassOn: Bool {
        get { self[GlassOnKey.self] }
        set { self[GlassOnKey.self] = newValue }
    }
}

/// Un grupo de piezas de cristal (se pintan juntas, como pide macOS: `GlassEffectContainer`). Sin cristal, el contenido
/// tal cual. `spacing`: a menos de esa distancia se funden; por debajo del hueco entre ellas, cada una va por su lado.
struct GlassGroup<Content: View>: View {
    @Environment(\.theme) private var t
    @Environment(\.accessibilityReduceTransparency) private var reduce
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26, *), t.liquidGlass, !reduce {
            GlassEffectContainer(spacing: spacing) { content() }
                .environment(\.glassOn, true)
        } else {
            content()
        }
    }
}

extension View {
    /// El fondo de una pieza: cristal dentro de un `GlassGroup` (`tint`, el color de la activa; `interactive`, que
    /// responda al ratón) o, si no, `shape` relleno con `fallback`, el de siempre.
    func netdeckGlass<S: Shape, F: ShapeStyle>(_ shape: S, tint: RGB? = nil, interactive: Bool = false, fallback: F) -> some View {
        modifier(NetDeckGlass(shape: shape, tint: tint, interactive: interactive, fallback: fallback))
    }

    /// El fondo de un menú en un panel: con cristal, el del propio panel de macOS 26 (que ya es de cristal); si no,
    /// la barra del tema, opaca.
    func menuBackground() -> some View { modifier(MenuBackground()) }
}

private struct NetDeckGlass<S: Shape, F: ShapeStyle>: ViewModifier {
    @Environment(\.glassOn) private var on
    let shape: S
    let tint: RGB?
    let interactive: Bool
    let fallback: F

    func body(content: Content) -> some View {
        if #available(macOS 26, *), on {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(shape.fill(fallback))
        }
    }

    @available(macOS 26, *)
    private var glass: Glass {
        let g = tint.map { Glass.regular.tint(SwiftUI.Color($0)) } ?? .regular
        return interactive ? g.interactive() : g
    }
}

private struct MenuBackground: ViewModifier {
    @Environment(\.theme) private var t
    @Environment(\.accessibilityReduceTransparency) private var reduce

    func body(content: Content) -> some View {
        if t.liquidGlass, !reduce {
            content
        } else {
            content
                .background(SwiftUI.Color(t.bar.opaque))
                .presentationBackground(SwiftUI.Color(t.bar.opaque))
        }
    }
}
