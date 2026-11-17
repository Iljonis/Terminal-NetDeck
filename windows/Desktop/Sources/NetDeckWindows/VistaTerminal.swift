import NetDeckCore
import WinUI

/// Una superficie de texto para un terminal, con su propia caché de colores.
final class VistaTerminal {
    let surface = Border()
    let screen = TextBlock()
    private var pintado: [[SegmentoColor]]?
    private var plano: String?

    init(id: String) {
        screen.isTextSelectionEnabled = true
        surface.padding = Thickness(left: 10, top: 8, right: 10, bottom: 8)
        AutomationProperties.setAutomationId(screen, id)
        surface.child = screen
        surface.isTabStop = true
    }

    func invalidate() {
        pintado = nil
        plano = nil
    }

    func render(_ tab: PestanaTerminal?, palette: PaletaTerminal?, brush: (RGB) -> SolidColorBrush) {
        guard let tab, let palette else {
            let texto = tab?.screen ?? ""
            guard texto != plano else { return }
            pintado = nil
            plano = texto
            screen.text = texto
            return
        }
        let lines = tab.coloredLines(palette)
        guard lines != pintado else { return }
        pintado = lines
        plano = nil
        screen.text = ""
        for (index, line) in lines.enumerated() {
            for segment in line {
                let run = Run()
                run.text = segment.texto
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
