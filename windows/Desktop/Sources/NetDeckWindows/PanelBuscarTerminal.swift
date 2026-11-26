import NetDeckCore
import WinUI

final class PanelBuscarTerminal {
    let view = ScrollViewer()
    var onSearch: ((String) -> Void)?
    var onClose: (() -> Void)?

    private let titulo = TextBlock()
    private let consulta = TextBox()
    private let resultado = TextBox()
    private let estado = TextBlock()
    private var enfocarTrasDiseño = false

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)
        titulo.fontSize = 20
        consulta.header = L("Texto que buscar")
        resultado.isReadOnly = true
        resultado.acceptsReturn = true
        resultado.fontFamily = FontFamily("Consolas")
        resultado.minHeight = 120
        resultado.maxHeight = 420
        let buscar = Button()
        buscar.content = L("Buscar")
        let cerrar = Button()
        cerrar.content = L("Cerrar")
        AutomationProperties.setAutomationId(consulta, "BuscarTerminal_Consulta")
        AutomationProperties.setAutomationId(resultado, "BuscarTerminal_Resultados")
        AutomationProperties.setAutomationId(buscar, "BuscarTerminal_Buscar")
        buscar.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.onSearch?(self.consulta.text)
        }
        consulta.keyDown.addHandler { [weak self] _, args in
            guard let self, let args, args.key.rawValue == 13 else { return }
            args.handled = true
            self.onSearch?(self.consulta.text)
        }
        cerrar.click.addHandler { [weak self] _, _ in self?.onClose?() }
        for control in [titulo as FrameworkElement, consulta, buscar, estado, resultado, cerrar] {
            form.children.append(control)
        }
        view.layoutUpdated.addHandler { [weak self] _, _ in
            guard let self, self.enfocarTrasDiseño, self.view.visibility == .visible,
                  self.consulta.actualWidth > 0 else { return }
            self.enfocarTrasDiseño = false
            _ = try? self.consulta.focus(.programmatic)
        }
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.visibility = .collapsed
    }

    func reset(title: String) {
        enfocarTrasDiseño = true
        titulo.text = L("Buscar en «\(title)»")
        estado.text = ""
        resultado.text = ""
    }

    func show(lines: [String], total: Int) {
        estado.text = total == 0 ? L("Sin coincidencias") : L("Mostrando \(lines.count) de \(total) coincidencias")
        resultado.text = lines.joined(separator: "\n")
    }
}
