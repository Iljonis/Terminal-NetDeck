import Foundation
import NetDeckCore
import WinUI

/// Panel con un texto multilinea y dos botones: sirve de vista previa del pegado seguro y de editor del MultiExec.
/// (swift-winui 0.1.1 no tiene un ContentDialog sencillo: el panel ocupa el area principal, como el editor.)
final class PanelTexto {
    let view = ScrollViewer()
    var onConfirm: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let title = TextBlock()
    private let hint = TextBlock()
    private let box = TextBox()
    private let confirmButton = Button()
    private let cancelButton = Button()
    private let idPrefix: String

    init(idPrefix: String) {
        self.idPrefix = idPrefix
        let form = StackPanel()
        form.orientation = .vertical
        form.spacing = 8
        form.maxWidth = 760
        form.horizontalAlignment = .left
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        title.fontSize = 20
        hint.opacity = 0.7
        hint.textWrapping = .wrap
        box.acceptsReturn = true
        box.textWrapping = .noWrap
        box.minHeight = 220
        box.maxHeight = 420
        box.fontFamily = FontFamily("Consolas")
        AutomationProperties.setAutomationId(box, idPrefix + "_Texto")

        confirmButton.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.onConfirm?(self.box.text)
        }
        cancelButton.content = L("Cancelar")
        cancelButton.click.addHandler { [weak self] _, _ in self?.onCancel?() }
        AutomationProperties.setAutomationId(confirmButton, idPrefix + "_Enviar")
        AutomationProperties.setAutomationId(cancelButton, idPrefix + "_Cancelar")
        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.children.append(confirmButton)
        buttons.children.append(cancelButton)

        form.children.append(title)
        form.children.append(hint)
        form.children.append(box)
        form.children.append(buttons)
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    /// `editable`: el texto se puede cambiar (MultiExec); si no, es solo una vista previa (pegado).
    func show(title: String, hint: String, text: String, editable: Bool, confirmTitle: String? = nil) {
        self.title.text = title
        self.hint.text = hint
        box.text = text
        box.isReadOnly = !editable
        confirmButton.content = confirmTitle ?? L("Enviar")
    }
}
