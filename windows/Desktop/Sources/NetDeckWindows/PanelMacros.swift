import Foundation
import NetDeckCore
import WinUI

final class PanelMacros {
    let view = ScrollViewer()
    var onPlay: ((Macro) -> Void)?
    var onSave: ((Macro) -> Void)?
    var onRecord: (() -> Void)?
    var onDelete: ((Macro) -> Void)?
    var onClose: (() -> Void)?

    private let list = ComboBox()
    private let play = Button()
    private let editar = Button()
    private let borrar = Button()
    private let confirmar = CheckBox()
    private var original: Macro?
    private var stepsAreEditable = true
    private let name = TextBox()
    private let commands = TextBox()
    private var library = MacroLibrary()

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.maxWidth = 760
        form.horizontalAlignment = .left
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let title = TextBlock()
        title.text = L("Macros")
        title.fontSize = 20
        list.header = L("Macros")
        name.header = L("Nombre")
        commands.header = L("Una orden por línea")
        commands.acceptsReturn = true
        commands.minHeight = 140
        commands.fontFamily = FontFamily("Consolas")
        list.minWidth = 250
        name.minWidth = 300
        commands.minWidth = 420
        play.content = L("Reproducir")
        editar.content = L("Editar")
        borrar.content = L("Borrar")
        confirmar.content = L("Confirmar antes de reproducir")
        let nueva = Button()
        nueva.content = L("Nueva")
        nueva.click.addHandler { [weak self] _, _ in self?.clearDraft() }
        let grabar = Button()
        grabar.content = L("Grabar macro")
        grabar.click.addHandler { [weak self] _, _ in self?.onRecord?() }
        editar.click.addHandler { [weak self] _, _ in
            guard let self, let macro = self.selected() else { return }
            self.setDraft(macro)
        }
        borrar.click.addHandler { [weak self] _, _ in
            guard let self, let macro = self.selected() else { return }
            self.onDelete?(macro)
        }
        let save = Button()
        save.content = L("Guardar")
        let close = Button()
        close.content = L("Cerrar")

        AutomationProperties.setAutomationId(list, "Macros_Lista")
        AutomationProperties.setAutomationId(name, "Macros_Nombre")
        AutomationProperties.setAutomationId(commands, "Macros_Ordenes")
        AutomationProperties.setAutomationId(save, "Macros_Guardar")
        AutomationProperties.setAutomationId(play, "Macros_Reproducir")
        play.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            guard let macro = self.selected() else { return }
            self.onPlay?(macro)
        }
        save.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            let lines = self.commands.text.split(whereSeparator: \.isNewline).map(String.init)
            let name = self.name.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var macro = self.original ?? Macro(name: name)
            macro.name = name
            macro.confirm = self.confirmar.isChecked == true
            if self.stepsAreEditable { macro.steps = Macro.recorded(lines) }
            self.onSave?(macro)
        }
        close.click.addHandler { [weak self] _, _ in self?.onClose?() }
        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.spacing = 8
        for accion in [play, editar, borrar, nueva, grabar] { acciones.children.append(accion) }
        for control in [title as FrameworkElement, list, acciones, name, commands, confirmar, save, close] {
            form.children.append(control)
        }
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.visibility = .collapsed
    }

    func show(_ library: MacroLibrary, selected id: Macro.ID? = nil) {
        self.library = library
        list.items.clear()
        for macro in library.macros { list.items.append(macro.name) }
        play.isEnabled = !library.macros.isEmpty
        editar.isEnabled = play.isEnabled
        borrar.isEnabled = play.isEnabled
        list.selectedIndex = library.macros.isEmpty ? -1 : Int32(library.macros.firstIndex { $0.id == id } ?? 0)
    }

    private func selected() -> Macro? {
        let index = Int(list.selectedIndex)
        guard library.macros.indices.contains(index) else { return nil }
        return library.macros[index]
    }

    private func setDraft(_ macro: Macro) {
        original = macro
        name.text = macro.name
        confirmar.isChecked = macro.confirm
        let lines = macro.lines
        stepsAreEditable = Macro.recorded(lines) == macro.steps
        commands.isReadOnly = !stepsAreEditable
        commands.header = stepsAreEditable ? L("Una orden por línea") : L("Pasos avanzados conservados")
        commands.text = lines.joined(separator: "\n")
    }

    func recorded(_ lines: [String]) {
        clearDraft()
        commands.text = lines.joined(separator: "\n")
    }

    func clearDraft() {
        original = nil
        stepsAreEditable = true
        name.text = ""
        commands.text = ""
        commands.isReadOnly = false
        commands.header = L("Una orden por línea")
        confirmar.isChecked = false
    }
}
