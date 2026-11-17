import Foundation
import NetDeckCore
import WinUI

/// Panel que sustituye al terminal para crear o editar una sesion (nombre, grupo, equipo, usuario, puerto, tipo).
final class PanelEditorSesion {
    let view = ScrollViewer()
    /// Recibe la sesion editada y el nombre que tenia (nil: nueva). Devuelve true si se ha guardado.
    var onSave: ((EditableSession, String?) -> Bool)?
    var onCancel: (() -> Void)?

    private let title = TextBlock()
    private let name = TextBox()
    private let group = TextBox()
    private let host = TextBox()
    private let user = TextBox()
    private let port = TextBox()
    private let kind = ComboBox()
    private let summary = TextBox()
    private let saveButton = Button()
    private let cancelButton = Button()
    private var draft = EditableSession(name: "")
    private var original: String?
    private var loading = false
    private static let kinds: [SessionProfile.Transport] = [.ssh, .telnet, .sftp, .ftp, .serial, .local]

    init() {
        let form = StackPanel()
        form.orientation = .vertical
        form.spacing = 8
        form.maxWidth = 460
        form.horizontalAlignment = .left
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        title.fontSize = 20
        form.children.append(title)

        for kindOption in Self.kinds { kind.items.append(kindOption.label) }
        kind.minWidth = 200
        kind.selectionChanged.addHandler { [weak self] _, _ in self?.kindChanged() }

        let fields: [(String, Control, String)] = [
            (L("Nombre"), name, "Editor_Nombre"),
            (L("Grupo"), group, "Editor_Grupo"),
            (L("Equipo"), host, "Editor_Equipo"),
            (L("Usuario"), user, "Editor_Usuario"),
            (L("Puerto"), port, "Editor_Puerto"),
            (L("Tipo"), kind, "Editor_Tipo"),
            (L("Descripci\u{00F3}n"), summary, "Editor_Descripcion"),
        ]
        for (label, control, id) in fields {
            let caption = TextBlock()
            caption.text = label
            caption.fontSize = 12
            caption.opacity = 0.7
            AutomationProperties.setAutomationId(control, id)
            let box = StackPanel()
            box.orientation = .vertical
            box.spacing = 2
            box.children.append(caption)
            box.children.append(control)
            form.children.append(box)
        }

        saveButton.content = L("Guardar")
        saveButton.click.addHandler { [weak self] _, _ in self?.commit() }
        cancelButton.content = L("Cancelar")
        cancelButton.click.addHandler { [weak self] _, _ in self?.onCancel?() }
        AutomationProperties.setAutomationId(saveButton, "Editor_Guardar")
        AutomationProperties.setAutomationId(cancelButton, "Editor_Cancelar")
        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.margin = Thickness(left: 0, top: 8, right: 0, bottom: 0)
        buttons.children.append(saveButton)
        buttons.children.append(cancelButton)
        form.children.append(buttons)

        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    /// Carga una sesion en el formulario. `original`: nombre de la que se edita; nil si es nueva.
    func show(_ session: EditableSession, original: String?) {
        loading = true
        draft = session
        self.original = original
        title.text = original == nil ? L("Nueva sesi\u{00F3}n") : L("Editar sesi\u{00F3}n")
        name.text = session.name
        group.text = session.group
        host.text = session.host
        user.text = session.user
        port.text = session.port
        summary.text = session.summary
        kind.selectedIndex = Int32(Self.kinds.firstIndex(of: session.kind) ?? 0)
        loading = false
        _ = try? name.focus(.programmatic)
    }

    private func kindChanged() {
        guard !loading else { return }
        let index = Int(kind.selectedIndex)
        guard Self.kinds.indices.contains(index) else { return }
        draft.port = port.text
        draft.setKind(Self.kinds[index])
        port.text = draft.port
    }

    private func commit() {
        var session = draft
        session.name = name.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupName = group.text.trimmingCharacters(in: .whitespacesAndNewlines)
        session.group = groupName.isEmpty ? "General" : groupName
        session.host = host.text.trimmingCharacters(in: .whitespacesAndNewlines)
        session.user = user.text.trimmingCharacters(in: .whitespacesAndNewlines)
        session.port = port.text.trimmingCharacters(in: .whitespacesAndNewlines)
        session.summary = summary.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = Int(kind.selectedIndex)
        if Self.kinds.indices.contains(index) { session.kind = Self.kinds[index] }
        _ = onSave?(session, original)
    }
}
