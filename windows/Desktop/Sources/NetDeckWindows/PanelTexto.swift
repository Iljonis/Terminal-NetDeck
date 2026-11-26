import Foundation
import NetDeckCore
import struct UWP.FontWeight
import WinUI

/// Avisos y confirmaciones como el `ThemedAlert` del Mac (G2 de PENDIENTE): icono y título arriba, la explicación en
/// pequeño, el texto sólo si lo hay (de una línea para renombrar, de varias para el pegado, el MultiExec o las notas
/// de una versión) y «Cancelar» y el botón de confirmar a la derecha; el de confirmar, relleno de acento o rojo si
/// lo que hace no se deshace. Sirve también de editor (MultiExec, reglas, archivos remotos).
final class PanelTexto {
    let view = ScrollViewer()
    var onConfirm: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let form = Grid()
    private let icon = TextBlock()
    private let title = TextBlock()
    private let hint = TextBlock()
    private let box = TextBox()
    private let confirmButton = Button()
    private let cancelButton = Button()
    private let idPrefix: String

    init(idPrefix: String) {
        self.idPrefix = idPrefix
        form.margin = Thickness(left: 14, top: 10, right: 14, bottom: 12)
        form.horizontalAlignment = .stretch
        for _ in 0..<3 {
            let fila = RowDefinition()
            fila.height = GridLength(value: 1, gridUnitType: .auto)
            form.rowDefinitions.append(fila)
        }

        // (cabecera: icono a la izquierda; título y explicación a su derecha)
        let cabecera = Grid()
        let c0 = ColumnDefinition()
        c0.width = GridLength(value: 1, gridUnitType: .auto)
        let c1 = ColumnDefinition()
        c1.width = GridLength(value: 1, gridUnitType: .star)
        cabecera.columnDefinitions.append(c0)
        cabecera.columnDefinitions.append(c1)
        icon.fontFamily = EstiloMac.fuenteIconos
        icon.fontSize = 22
        icon.verticalAlignment = .top
        icon.margin = Thickness(left: 0, top: 2, right: 12, bottom: 0)
        let textos = StackPanel()
        textos.spacing = 4
        title.fontSize = 15
        title.fontWeight = FontWeight(weight: 700)
        title.textWrapping = .wrap
        hint.fontSize = 12
        hint.textWrapping = .wrap
        textos.children.append(title)
        textos.children.append(hint)
        Grid.setColumn(icon, Int32(0))
        Grid.setColumn(textos, Int32(1))
        cabecera.children.append(icon)
        cabecera.children.append(textos)
        cabecera.margin = Thickness(left: 0, top: 0, right: 28, bottom: 0)   // (sitio para la ✕ de la tarjeta)

        box.textWrapping = .noWrap
        box.fontFamily = FontFamily("Cascadia Mono, Consolas")
        box.fontSize = 12.5
        box.margin = Thickness(left: 0, top: 12, right: 0, bottom: 0)
        AutomationProperties.setAutomationId(box, idPrefix + "_Texto")
        box.keyDown.addHandler { [weak self] _, args in
            guard let self, let args, args.key == .enter, !self.box.acceptsReturn else { return }
            args.handled = true
            self.onConfirm?(self.box.text)
        }

        confirmButton.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.onConfirm?(self.box.text)
        }
        cancelButton.content = L("Cancelar")
        cancelButton.click.addHandler { [weak self] _, _ in self?.onCancel?() }
        AutomationProperties.setAutomationId(confirmButton, idPrefix + "_Enviar")
        AutomationProperties.setAutomationId(cancelButton, idPrefix + "_Cancelar")
        for b in [confirmButton, cancelButton] {
            b.minWidth = 92
            b.minHeight = 28
            b.padding = Thickness(left: 14, top: 3, right: 14, bottom: 3)
            b.cornerRadius = EstiloMac.radio(6)
        }
        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.horizontalAlignment = .right
        buttons.margin = Thickness(left: 0, top: 16, right: 0, bottom: 0)
        buttons.children.append(cancelButton)
        buttons.children.append(confirmButton)

        Grid.setRow(cabecera, Int32(0))
        Grid.setRow(box, Int32(1))
        Grid.setRow(buttons, Int32(2))
        form.children.append(cabecera)
        form.children.append(box)
        form.children.append(buttons)
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    /// `editable`: el texto se puede cambiar (MultiExec, renombrar); si no, es sólo para leer (pegado, notas). Sin texto
    /// y sin poder escribir, no hay caja: es un aviso. `destructivo`: el botón de confirmar va en rojo (borrar, órdenes
    /// peligrosas). `unaLinea`: caja de una línea donde Intro confirma (renombrar).
    func show(title: String, hint: String, text: String, editable: Bool, confirmTitle: String? = nil,
              destructivo: Bool = false, unaLinea: Bool = false, icono: String? = nil) {
        let e = EstiloMac.actual
        self.title.text = title
        self.title.foreground = e.texto
        self.hint.text = hint
        self.hint.foreground = e.apagado
        self.hint.visibility = hint.isEmpty ? .collapsed : .visible
        let glifo = icono ?? (destructivo ? Glifo.aviso : nil)
        icon.text = glifo ?? ""
        icon.foreground = destructivo ? e.mal : e.acento
        icon.visibility = glifo == nil ? .collapsed : .visible
        box.text = text
        box.isReadOnly = !editable
        box.acceptsReturn = !unaLinea
        box.minHeight = unaLinea ? 0 : 180
        box.maxHeight = unaLinea ? 40 : 420
        box.visibility = text.isEmpty && !editable ? .collapsed : .visible
        // (aviso: del ancho de lo que dice, entre 380 y 480; con texto de varias líneas, 720 fijos para que una línea
        // larga no ensanche la tarjeta)
        let aviso = box.visibility == .collapsed || unaLinea
        form.maxWidth = aviso ? 480 : 720
        form.minWidth = 380
        form.width = aviso ? Double.nan : 720

        confirmButton.content = EstiloMac.letra(confirmTitle ?? L("Enviar"), tamano: 12.5, peso: 600,
                                                color: EstiloMac.pincel(destructivo ? e.tema.bad.readable : e.tema.accent.readable))
        let relleno = destructivo ? e.mal : e.acento
        confirmButton.background = relleno
        confirmButton.borderBrush = relleno
        EstiloMac.conservarColores(confirmButton, encima: EstiloMac.pincel(destructivo ? e.tema.bad : e.tema.accent, alfa: 0.85),
                                   pulsado: EstiloMac.pincel(destructivo ? e.tema.bad : e.tema.accent, alfa: 0.7), borde: relleno)
        // (pendiente: llevar el foco a la caja al abrir; pedirlo aquí o en la vuelta siguiente no basta, algo lo recoge
        // después; hoy hay que hacer clic en ella, como antes)
    }
}
