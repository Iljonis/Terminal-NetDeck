import Foundation
import NetDeckCore
import struct WindowsFoundation.Point
import struct WindowsFoundation.Rect
import struct WindowsFoundation.Size
import WinUI

/// La misma superposición que ScreenFilterOverlay: se actualiza al cambiar de filtro o tamaño y deja pasar el ratón.
final class FiltroTerminal {
    let view = Grid()
    private var look: ScreenLook?

    init() {
        view.isHitTestVisible = false
        view.sizeChanged.addHandler { [weak self] _, _ in self?.dibujar() }
    }

    func apply(_ look: ScreenLook?) {
        guard look != self.look else { return }
        self.look = look
        dibujar()
    }

    private func dibujar() {
        view.children.clear()
        let ancho = view.actualWidth, alto = view.actualHeight
        guard let look, ancho > 0, alto > 0 else { return }
        if let velo = look.tint { capa(EstiloMac.pincel(velo)) }
        if let halo = look.glow { radial(ancho, alto, [(0, halo), (1, halo.alpha(0))]) }
        if let barrido = look.scan { lineas(barrido, ancho, alto, cuadricula: false) }
        if let rejilla = look.grid { lineas(rejilla, ancho, alto, cuadricula: true) }
        if look.vignette > 0 {
            radial(ancho, alto, [(0.55, RGB.black.alpha(0)), (1, RGB.black.alpha(look.vignette))])
        }
        if look.curve > 0 { esquinas(ancho, alto, radio: look.curve, alfa: look.cornerAlpha) }
    }

    private func lineas(_ lineas: ScreenLook.Lines, _ ancho: Double, _ alto: Double, cuadricula: Bool) {
        guard lineas.every > 0, lineas.width > 0 else { return }
        let dibujo = GeometryGroup()
        dibujo.fillRule = .nonzero
        for y in stride(from: 0.0, to: alto, by: lineas.every) {
            dibujo.children.append(rect(0, alto - y - min(lineas.width, alto - y), ancho, min(lineas.width, alto - y)))
        }
        if cuadricula {
            for x in stride(from: 0.0, to: ancho, by: lineas.every) {
                dibujo.children.append(rect(x, 0, min(lineas.width, ancho - x), alto))
            }
        }
        forma(dibujo, color: lineas.color)
    }

    private func radial(_ ancho: Double, _ alto: Double, _ pasos: [(Double, RGB)]) {
        let radio = hypot(ancho, alto) / 2
        let pincel = RadialGradientBrush()
        pincel.mappingMode = .relativeToBoundingBox
        pincel.center = Point(x: 0.5, y: 0.5)
        pincel.gradientOrigin = pincel.center
        pincel.radiusX = radio / ancho
        pincel.radiusY = radio / alto
        for (posicion, color) in pasos {
            let paso = GradientStop()
            paso.offset = posicion
            paso.color = EstiloMac.pincel(color).color
            pincel.gradientStops.append(paso)
        }
        capa(pincel)
    }

    private func esquinas(_ ancho: Double, _ alto: Double, radio: Double, alfa: Double) {
        let r = min(radio, ancho / 2, alto / 2)
        let hueco = PathGeometry()
        let borde = PathFigure()
        borde.isClosed = true
        borde.startPoint = punto(r, 0)
        let lados = [(ancho - r, 0, ancho, r), (ancho, alto - r, ancho - r, alto),
                     (r, alto, 0, alto - r), (0, r, r, 0)]
        for (x, y, finX, finY) in lados {
            let recta = LineSegment()
            recta.point = punto(x, y)
            borde.segments.append(recta)
            let curva = ArcSegment()
            curva.point = punto(finX, finY)
            curva.size = Size(width: Float(r), height: Float(r))
            curva.sweepDirection = .clockwise
            borde.segments.append(curva)
        }
        hueco.figures.append(borde)
        let mascara = GeometryGroup()
        mascara.fillRule = .evenOdd
        mascara.children.append(rect(0, 0, ancho, alto))
        mascara.children.append(hueco)
        forma(mascara, color: RGB.black.alpha(alfa))
    }

    private func punto(_ x: Double, _ y: Double) -> Point { Point(x: Float(x), y: Float(y)) }

    private func rect(_ x: Double, _ y: Double, _ ancho: Double, _ alto: Double) -> RectangleGeometry {
        let r = RectangleGeometry()
        r.rect = Rect(x: Float(x), y: Float(y), width: Float(ancho), height: Float(alto))
        return r
    }

    private func forma(_ geometria: Geometry, color: RGB) {
        let dibujo = WinUI.Path()
        dibujo.data = geometria
        dibujo.fill = EstiloMac.pincel(color)
        dibujo.stretch = .none
        view.children.append(dibujo)
    }

    private func capa(_ pincel: Brush) {
        let borde = Border()
        borde.background = pincel
        view.children.append(borde)
    }
}
