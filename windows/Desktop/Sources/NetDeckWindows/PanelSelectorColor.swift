import Foundation
import NetDeckCore
import WinUI

/// Selector de color propio de NetDeck para Windows; evita el diálogo nativo del sistema.
final class PanelSelectorColor {
    let view = ScrollViewer()
    var onClose: (() -> Void)?
    private let raiz = StackPanel()
    private let entrada = TextBox()
    private let muestra = Border()
    private var actual = RGB.white
    private var estilo = EstiloMac(tema: nil)
    private var terminar: ((RGB?) -> Void)?

    init() {
        raiz.spacing = 12
        raiz.padding = Thickness(left: 24, top: 20, right: 24, bottom: 24)
        view.content = raiz
        view.horizontalScrollBarVisibility = .disabled
        view.verticalScrollBarVisibility = .auto
    }

    func mostrar(_ color: RGB, estilo: EstiloMac, terminar: @escaping (RGB?) -> Void) {
        self.estilo = estilo
        self.actual = color.opaque
        self.terminar = terminar
        construir()
    }

    func abandonar() { terminar?(nil); terminar = nil }

    private func construir() {
        raiz.children.clear()
        let encabezado = EstiloMac.letra(L("Personalizar color"), tamano: 20, peso: 750, color: estilo.texto)
        encabezado.margin = Thickness(left: 0, top: 0, right: 0, bottom: 4)
        raiz.children.append(encabezado)
        raiz.children.append(EstiloMac.letra(L("Elige un color o escribe su código hexadecimal."), tamano: 12, color: estilo.apagado))

        let colores: [RGB] = [
            RGB(0, 0, 0), RGB(32, 32, 32), RGB(72, 72, 72), RGB(128, 128, 128), RGB(192, 192, 192), RGB(240, 240, 240), RGB.white,
            RGB(96, 20, 20), RGB(160, 32, 32), RGB(224, 48, 48), RGB(255, 96, 96), RGB(255, 160, 160),
            RGB(112, 56, 0), RGB(176, 88, 0), RGB(240, 128, 0), RGB(255, 176, 64), RGB(255, 216, 128),
            RGB(112, 96, 0), RGB(176, 152, 0), RGB(232, 208, 0), RGB(255, 232, 96), RGB(255, 248, 168),
            RGB(16, 80, 32), RGB(24, 136, 56), RGB(32, 192, 80), RGB(96, 224, 128), RGB(168, 248, 184),
            RGB(0, 80, 80), RGB(0, 136, 144), RGB(0, 192, 208), RGB(88, 224, 232), RGB(168, 248, 248),
            RGB(16, 48, 112), RGB(24, 88, 184), RGB(40, 136, 240), RGB(104, 176, 255), RGB(176, 216, 255),
            RGB(56, 24, 112), RGB(96, 48, 176), RGB(144, 72, 232), RGB(184, 128, 255), RGB(216, 184, 255),
            RGB(104, 16, 80), RGB(168, 24, 128), RGB(224, 48, 176), RGB(248, 112, 208), RGB(255, 184, 232),
        ]
        let rejilla = Grid()
        for _ in 0..<7 {
            let columna = ColumnDefinition()
            columna.width = GridLength(value: 1, gridUnitType: .star)
            rejilla.columnDefinitions.append(columna)
        }
        for fila in 0..<7 {
            let definicion = RowDefinition()
            definicion.height = GridLength(value: 34, gridUnitType: .pixel)
            rejilla.rowDefinitions.append(definicion)
        }
        for (i, color) in colores.enumerated() {
            let boton = Button()
            boton.width = 29
            boton.height = 27
            boton.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
            boton.cornerRadius = EstiloMac.radio(5)
            boton.background = pincel(color)
            AutomationProperties.setName(boton, color.description)
            Grid.setColumn(boton, Int32(i % 7))
            Grid.setRow(boton, Int32(i / 7))
            boton.click.addHandler { [weak self] _, _ in self?.seleccionar(color) }
            rejilla.children.append(boton)
        }
        raiz.children.append(rejilla)

        entrada.header = L("Código hexadecimal")
        entrada.placeholderText = "#RRGGBB"
        entrada.text = actual.description
        entrada.maxLength = 7
        entrada.textChanged.addHandler { [weak self] _, _ in
            guard let self, let color = RGB(hex: entrada.text) else { return }
            actual = color.opaque
            muestra.background = pincel(actual)
        }
        raiz.children.append(entrada)
        muestra.height = 46
        muestra.cornerRadius = EstiloMac.radio(8)
        muestra.background = pincel(actual)
        raiz.children.append(muestra)

        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.spacing = 8
        acciones.horizontalAlignment = .right
        let cancelar = Button()
        cancelar.content = L("Cancelar")
        cancelar.click.addHandler { [weak self] _, _ in self?.cerrar(nil) }
        let aplicar = Button()
        aplicar.content = L("Aplicar")
        aplicar.click.addHandler { [weak self] _, _ in
            guard let self, let color = RGB(hex: entrada.text) else { return }
            cerrar(color.opaque)
        }
        acciones.children.append(cancelar)
        acciones.children.append(aplicar)
        raiz.children.append(acciones)
    }

    private func seleccionar(_ color: RGB) {
        actual = color
        entrada.text = color.description
        muestra.background = pincel(color)
    }

    private func pincel(_ c: RGB) -> SolidColorBrush {
        func canal(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        return EstiloMac.pincel(RGB(Double(canal(c.r)), Double(canal(c.g)), Double(canal(c.b))))
    }

    private func cerrar(_ color: RGB?) {
        let callback = terminar
        terminar = nil
        callback?(color)
        onClose?()
    }
}
