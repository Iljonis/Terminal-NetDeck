import NetDeckCore
import struct UWP.FontWeight
import WinUI

/// Una superficie de texto para un terminal, con su propia caché de colores.
final class VistaTerminal {
    let surface = Border()
    let screen = TextBlock()
    let filtro = FiltroTerminal()
    private let fondos = Canvas()
    private let cursorLayer = Canvas()
    private let caret = Border()
    private var cellWidth = 8.25
    private var cellHeight = 19.0
    private var pintado: [[SegmentoColor]]?
    private var plano: String?

    init(id: String) {
        screen.isTextSelectionEnabled = true
        surface.padding = Thickness(left: 10, top: 8, right: 10, bottom: 8)
        AutomationProperties.setAutomationId(screen, id)
        let layers = Grid()
        fondos.isHitTestVisible = false
        cursorLayer.isHitTestVisible = false
        caret.width = 2
        cursorLayer.children.append(caret)
        layers.children.append(fondos)
        layers.children.append(screen)
        layers.children.append(cursorLayer)
        layers.children.append(filtro.view)
        surface.child = layers
        surface.isTabStop = true
    }

    func cellSize(width: Double, height: Double) {
        if width != cellWidth || height != cellHeight { invalidate() }
        cellWidth = width
        cellHeight = height
    }

    func invalidate() {
        pintado = nil
        plano = nil
    }

    func render(_ tab: PestanaTerminal?, palette: PaletaTerminal?, cursorActive: Bool, brush: (RGB) -> SolidColorBrush) {
        if cursorActive, let tab, !tab.closed, tab.cursorVisible, let palette {
            let punto = tab.terminal.getCursorLocation()
            Canvas.setLeft(caret, Double(min(punto.x, tab.terminal.cols - 1)) * cellWidth)
            Canvas.setTop(caret, Double(punto.y) * cellHeight)
            caret.height = cellHeight
            caret.background = brush(palette.cursor)
            caret.visibility = .visible
        } else {
            caret.visibility = .collapsed
        }
        guard let tab, let palette else {
            let texto = tab?.screen ?? ""
            guard texto != plano else { return }
            pintado = nil
            plano = texto
            fondos.children.clear()
            screen.text = texto
            return
        }
        let lines = tab.coloredLines(palette)
        guard lines != pintado else { return }
        pintado = lines
        plano = nil
        screen.text = ""
        fondos.children.clear()
        for (index, line) in lines.enumerated() {
            var columna = 0
            for segment in line {
                if let fondo = segment.fondo {
                    let background = Border()
                    background.width = Double(segment.columnas) * cellWidth
                    background.height = cellHeight
                    background.background = brush(fondo)
                    Canvas.setLeft(background, Double(columna) * cellWidth)
                    Canvas.setTop(background, Double(index) * cellHeight)
                    fondos.children.append(background)
                }
                columna += segment.columnas
                let run = Run()
                run.text = segment.texto
                if segment.bold { run.fontWeight = FontWeight(weight: 700) }
                if segment.italic { run.fontStyle = .init(rawValue: 2) }
                if segment.underline { run.textDecorations = .init(rawValue: 1) }
                if let color = segment.color { run.foreground = brush(color) }
                screen.inlines.append(run)
            }
            if index < lines.count - 1 {
                let newline = Run()
                newline.text = "\n"
                screen.inlines.append(newline)
            }
        }
    }
}
