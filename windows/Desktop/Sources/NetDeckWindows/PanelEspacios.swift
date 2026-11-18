import NetDeckCore
import WinUI

final class PanelEspacios {
    let view = ScrollViewer()
    var onOpen: ((Workspace) -> Void)?
    var onSave: ((String) -> Void)?
    var onClose: (() -> Void)?

    private let lista = ComboBox()
    private let abrir = Button()
    private let nombre = TextBox()
    private var biblioteca = WorkspaceLibrary()

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.maxWidth = 460
        form.horizontalAlignment = .left
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let titulo = TextBlock()
        titulo.text = L("Espacios de trabajo")
        titulo.fontSize = 20
        lista.minWidth = 260
        nombre.header = L("Nombre del espacio")
        abrir.content = L("Abrir")
        let guardar = Button()
        guardar.content = L("Guardar pestañas actuales")
        let cerrar = Button()
        cerrar.content = L("Cerrar")
        AutomationProperties.setAutomationId(lista, "Espacios_Lista")
        AutomationProperties.setAutomationId(abrir, "Espacios_Abrir")
        AutomationProperties.setAutomationId(nombre, "Espacios_Nombre")
        AutomationProperties.setAutomationId(guardar, "Espacios_Guardar")

        abrir.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            let index = Int(self.lista.selectedIndex)
            guard self.biblioteca.workspaces.indices.contains(index) else { return }
            self.onOpen?(self.biblioteca.workspaces[index])
        }
        guardar.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.onSave?(self.nombre.text)
        }
        cerrar.click.addHandler { [weak self] _, _ in self?.onClose?() }

        for control in [titulo as FrameworkElement, lista, abrir, nombre, guardar, cerrar] {
            form.children.append(control)
        }
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.visibility = .collapsed
    }

    func show(_ lib: WorkspaceLibrary, selected: Workspace.ID? = nil) {
        biblioteca = lib
        lista.items.clear()
        for espacio in lib.workspaces { lista.items.append(espacio.name) }
        abrir.isEnabled = !lib.workspaces.isEmpty
        lista.selectedIndex = lib.workspaces.isEmpty ? -1 : Int32(lib.workspaces.firstIndex { $0.id == selected } ?? 0)
        if selected != nil { nombre.text = "" }
    }
}
