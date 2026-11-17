import Foundation
import NetDeckCore
import WinUI

final class PanelMacros {
    let view = ScrollViewer()
    var onPlay: ((Macro) -> Void)?
    var onSave: ((Macro) -> Void)?
    var onClose: (() -> Void)?

    private let list = ComboBox()
    private let play = Button()
    private let name = TextBox()
    private let commands = TextBox()
    private var library = MacroLibrary()

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.maxWidth = 760
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
        play.content = L("Reproducir")
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
            let index = Int(self.list.selectedIndex)
            guard self.library.macros.indices.contains(index) else { return }
            self.onPlay?(self.library.macros[index])
        }
        save.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            let lines = self.commands.text.split(whereSeparator: \.isNewline).map(String.init)
            let name = self.name.text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.onSave?(Macro(name: name, steps: Macro.recorded(lines)))
        }
        close.click.addHandler { [weak self] _, _ in self?.onClose?() }
        for control in [title as FrameworkElement, list, play, name, commands, save, close] {
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
        list.selectedIndex = library.macros.isEmpty ? -1 : Int32(library.macros.firstIndex { $0.id == id } ?? 0)
    }

    func clearDraft() {
        name.text = ""
        commands.text = ""
    }
}
