import NetDeckCore
import WinUI

/// Un desplegable de órdenes con el aspecto del menú «+»: lo que en el Mac va en la barra de menús (Ayuda, la app,
/// Herramientas) cuelga aquí de un icono de la barra.
final class MenuLista {
    enum Entrada {
        case orden(String, String, tecla: String?, () -> Void)
        case separador
    }

    let flyout = Flyout()
    private let panel = StackPanel()

    init() {
        flyout.placement = .bottomEdgeAlignedRight
        panel.minWidth = 270
        panel.padding = Thickness(left: 6, top: 6, right: 6, bottom: 6)
        panel.spacing = 1
        flyout.content = panel
    }

    func preparar(estilo: EstiloMac, _ entradas: [Entrada]) {
        panel.background = estilo.barra
        panel.children.clear()
        for entrada in entradas {
            switch entrada {
            case .orden(let texto, let glifo, let tecla, let accion):
                panel.children.append(fila(texto, glifo, tecla: tecla, estilo: estilo, accion: accion))
            case .separador:
                let barra = Border()
                barra.background = estilo.panel
                barra.height = 1
                barra.margin = Thickness(left: 6, top: 4, right: 6, bottom: 4)
                panel.children.append(barra)
            }
        }
    }

    private func fila(_ texto: String, _ glifo: String, tecla: String?, estilo: EstiloMac,
                      accion: @escaping () -> Void) -> Button {
        let boton = Button()
        estilo.plano(boton)
        boton.height = 26
        boton.horizontalAlignment = .stretch
        boton.horizontalContentAlignment = .stretch
        boton.padding = Thickness(left: 10, top: 0, right: 10, bottom: 0)
        let fila = Grid()
        for unidad in [GridUnitType.auto, .star, .auto] {
            let columna = ColumnDefinition()
            columna.width = GridLength(value: 1, gridUnitType: unidad)
            fila.columnDefinitions.append(columna)
        }
        let icono = EstiloMac.icono(glifo, tamano: 11, color: estilo.acento2)
        icono.width = 16
        fila.children.append(icono)
        let nombre = EstiloMac.letra(texto, tamano: 12, color: estilo.texto)
        nombre.margin = Thickness(left: 9, top: 0, right: 16, bottom: 0)
        Grid.setColumn(nombre, 1)
        fila.children.append(nombre)
        if let tecla {
            let etiqueta = EstiloMac.letra(tecla, tamano: 10.5, color: estilo.apagado)
            Grid.setColumn(etiqueta, 2)
            fila.children.append(etiqueta)
        }
        boton.content = fila
        AutomationProperties.setName(boton, texto)
        let normal = estilo.transparente
        let resaltado = estilo.acento(alfa: 0.14)
        boton.pointerEntered.addHandler { origen, _ in (origen as? Button)?.background = resaltado }
        boton.pointerExited.addHandler { origen, _ in (origen as? Button)?.background = normal }
        boton.click.addHandler { [weak self] _, _ in
            try? self?.flyout.hide()
            accion()
        }
        return boton
    }
}
