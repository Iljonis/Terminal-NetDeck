import NetDeckCore
import struct UWP.Color
import struct WindowsFoundation.Point
import WinUI

/// Capas visuales estáticas que dejan pasar el ratón y el teclado al terminal.
final class FiltroTerminal {
    let view = Grid()
    private var dibujado: ScreenLook?

    init() { view.isHitTestVisible = false }

    func apply(_ look: ScreenLook?) {
        guard look != dibujado else { return }
        dibujado = look
        view.children.clear()
        guard let look else { return }
        if let tint = look.tint { layer(SolidColorBrush(color(tint))) }
        if let glow = look.glow {
            let center = RadialGradientBrush()
            center.gradientStops.append(stop(0, glow))
            center.gradientStops.append(stop(1, glow.alpha(0)))
            layer(center)
        }
        if let scan = look.scan { stripes(scan, vertical: false) }
        if let grid = look.grid {
            stripes(grid, vertical: false)
            stripes(grid, vertical: true)
        }
        if look.vignette > 0 {
            let shadow = RGB(0, 0, 0, look.vignette / 2)
            for vertical in [false, true] {
                let edge = gradient(vertical: vertical, extent: 1)
                edge.gradientStops.append(stop(0, shadow))
                edge.gradientStops.append(stop(0.18, shadow.alpha(0)))
                edge.gradientStops.append(stop(0.82, shadow.alpha(0)))
                edge.gradientStops.append(stop(1, shadow))
                layer(edge)
            }
        }
    }

    private func stripes(_ lines: ScreenLook.Lines, vertical: Bool) {
        let brush = gradient(vertical: vertical, extent: lines.every)
        brush.mappingMode = BrushMappingMode(rawValue: 0)  // Absolute
        brush.spreadMethod = GradientSpreadMethod(rawValue: 2)  // Repeat
        let end = lines.width / lines.every
        brush.gradientStops.append(stop(0, lines.color))
        brush.gradientStops.append(stop(end, lines.color))
        brush.gradientStops.append(stop(end, lines.color.alpha(0)))
        brush.gradientStops.append(stop(1, lines.color.alpha(0)))
        layer(brush)
    }

    private func gradient(vertical: Bool, extent: Double) -> LinearGradientBrush {
        let brush = LinearGradientBrush()
        brush.startPoint = Point(x: 0, y: 0)
        brush.endPoint = Point(x: vertical ? Float(extent) : 0, y: vertical ? 0 : Float(extent))
        return brush
    }

    private func layer(_ brush: Brush) {
        let overlay = Border()
        overlay.background = brush
        view.children.append(overlay)
    }

    private func stop(_ offset: Double, _ rgb: RGB) -> GradientStop {
        let stop = GradientStop()
        stop.offset = offset
        stop.color = color(rgb)
        return stop
    }

    private func color(_ rgb: RGB) -> Color {
        func channel(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        return Color(a: channel(rgb.a * 255), r: channel(rgb.r), g: channel(rgb.g), b: channel(rgb.b))
    }
}
