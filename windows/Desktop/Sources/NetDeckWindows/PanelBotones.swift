import Foundation
import NetDeckCore
import WinUI

final class PanelBotones {
    static let modos: [CommandButton.Mode] = [.run, .type, .pass, .clave, .login, .session]
    let view = ScrollViewer()
    var onUse: ((CommandButton) -> Void)?
    var onSave: ((CommandButton, CommandButton.ID?) -> Void)?
    var onClose: (() -> Void)?

    private let lista = ComboBox()
    private let aplicar = Button()
    private let editar = Button()
    private let grupo = TextBox()
    private let nombre = TextBox()
    private let orden = TextBox()
    private let hotkey = TextBox()
    private let modo = ComboBox()
    private var botones: [CommandButton] = []
    private var original: CommandButton?

    private static func editorTitle(_ mode: CommandButton.Mode) -> String {
        switch mode {
        case .pass:  return L("Contraseña (Llavero)")
        case .clave: return L("Contraseña (literal)")
        default:     return mode.title
        }
    }

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.maxWidth = 680
        form.horizontalAlignment = .left
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let titulo = TextBlock()
        titulo.text = L("Botones de órdenes")
        titulo.fontSize = 20
        lista.minWidth = 300
        grupo.header = L("Grupo")
        nombre.header = L("Nombre")
        orden.minWidth = 420
        hotkey.header = L("Atajo (F5, S-F5, M-F5, C-F5)")
        hotkey.minWidth = 300
        for m in Self.modos { modo.items.append(Self.editorTitle(m)) }
        modo.selectedIndex = 0
        updateOrdenHeader()
        aplicar.content = L("Usar botón")
        editar.content = L("Editar")
        let nuevo = Button()
        nuevo.content = L("Nuevo")
        let guardar = Button()
        guardar.content = L("Guardar")
        let cerrar = Button()
        cerrar.content = L("Cerrar")
        AutomationProperties.setAutomationId(lista, "Botones_Lista")
        AutomationProperties.setAutomationId(aplicar, "Botones_Usar")
        AutomationProperties.setAutomationId(guardar, "Botones_Guardar")
        aplicar.click.addHandler { [weak self] _, _ in
            guard let self, let button = self.selected() else { return }
            self.onUse?(button)
        }
        editar.click.addHandler { [weak self] _, _ in
            guard let self, let button = self.selected() else { return }
            self.draft(button)
        }
        nuevo.click.addHandler { [weak self] _, _ in self?.draft(nil) }
        modo.selectionChanged.addHandler { [weak self] _, _ in self?.updateOrdenHeader() }
        guardar.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            let idx = Int(self.modo.selectedIndex)
            guard Self.modos.indices.contains(idx) else { return }
            let g = self.grupo.text.trimmingCharacters(in: .whitespaces)
            let n = self.nombre.text.trimmingCharacters(in: .whitespaces)
            let o = self.orden.text.trimmingCharacters(in: .whitespaces)
            let h = self.hotkey.text.trimmingCharacters(in: .whitespaces)
            self.onSave?(CommandButton(group: g, mode: Self.modos[idx], name: n, command: o,
                                       hotkey: h.isEmpty ? nil : h), self.original?.id)
        }
        cerrar.click.addHandler { [weak self] _, _ in self?.onClose?() }
        let fila = StackPanel()
        fila.orientation = .horizontal
        fila.spacing = 8
        for control in [aplicar, editar, nuevo] { fila.children.append(control) }
        for control in [titulo as FrameworkElement, lista, fila, grupo, nombre, modo, orden, hotkey, guardar, cerrar] {
            form.children.append(control)
        }
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.visibility = .collapsed
    }

    func show(_ file: ButtonFile, select: CommandButton? = nil) {
        botones = file.buttons.filter { Self.modos.contains($0.mode) }
        lista.items.clear()
        for button in botones { lista.items.append(button.group + " · " + button.name) }
        aplicar.isEnabled = !botones.isEmpty
        editar.isEnabled = aplicar.isEnabled
        lista.selectedIndex = botones.isEmpty ? -1 : Int32(botones.firstIndex { $0 == select } ?? 0)
        if let select { draft(select) }
    }

    private func selected() -> CommandButton? {
        let index = Int(lista.selectedIndex)
        return botones.indices.contains(index) ? botones[index] : nil
    }

    private func updateOrdenHeader() {
        let idx = Int(modo.selectedIndex)
        guard Self.modos.indices.contains(idx) else { return }
        switch Self.modos[idx] {
        case .run:     orden.header = L("Orden (varias con « ;; »)")
        case .type:    orden.header = L("Texto a escribir")
        case .pass:    orden.header = L("Nombre de la contraseña del Llavero")
        case .clave:   orden.header = L("Contraseña del botón")
        case .login:   orden.header = L("usuario / nombre-de-la-contraseña")
        case .session: orden.header = L("Sesión del ssh_config")
        }
    }

    private func draft(_ button: CommandButton?) {
        original = button
        grupo.text = button?.group ?? ""
        nombre.text = button?.name ?? ""
        orden.text = button?.command ?? ""
        hotkey.text = button?.hotkey ?? ""
        modo.selectedIndex = Int32(button.flatMap { Self.modos.firstIndex(of: $0.mode) } ?? 0)
        updateOrdenHeader()
    }
}
