import Foundation
import NetDeckCore
import WinUI

/// Asistente de la primera vez, en el area principal: bienvenida, primera sesion (opcional) y «todo listo».
/// Sin `ContentDialog` (swift-winui 0.1.1 no tiene un camino sencillo): son tres paneles que se turnan.
final class AsistenteInicio {
    let view = ScrollViewer()
    /// Crea la sesion; true si se guardo (si no, la ventana ya ha dicho por que en la barra de estado).
    var onCreateSession: ((EditableSession) -> Bool)?
    var onDone: (() -> Void)?

    private let welcome = StackPanel()
    private let first = StackPanel()
    private let ready = StackPanel()
    private let name = TextBox()
    private let host = TextBox()
    private let user = TextBox()
    private let port = TextBox()
    private let message = TextBlock()

    init() {
        let root = StackPanel()
        root.orientation = .vertical
        root.maxWidth = 520
        root.horizontalAlignment = .left
        root.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        buildWelcome()
        buildFirst()
        buildReady()
        for step in [welcome, first, ready] { root.children.append(step) }
        view.content = root
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    /// Vuelve a la primera pantalla.
    func start() {
        name.text = ""
        host.text = ""
        user.text = ""
        port.text = ""
        message.text = ""
        go(welcome)
    }

    private func go(_ step: StackPanel) {
        welcome.visibility = step === welcome ? .visible : .collapsed
        first.visibility = step === first ? .visible : .collapsed
        ready.visibility = step === ready ? .visible : .collapsed
    }

    private func heading(_ text: String) -> TextBlock {
        let title = TextBlock()
        title.text = text
        title.fontSize = 22
        title.margin = Thickness(left: 0, top: 0, right: 0, bottom: 8)
        return title
    }

    private func paragraph(_ text: String) -> TextBlock {
        let block = TextBlock()
        block.text = text
        block.textWrapping = .wrap
        block.margin = Thickness(left: 0, top: 0, right: 0, bottom: 12)
        return block
    }

    private func button(_ title: String, id: String, _ action: @escaping () -> Void) -> Button {
        let button = Button()
        button.content = title
        button.click.addHandler { _, _ in action() }
        AutomationProperties.setAutomationId(button, id)
        return button
    }

    private func buildWelcome() {
        welcome.orientation = .vertical
        welcome.children.append(heading(L("Bienvenido a Terminal NetDeck")))
        welcome.children.append(paragraph(L("Aqu\u{00ED} tienes tus servidores y equipos de red en la barra lateral: haz clic en uno para abrir una conexi\u{00F3}n, o en + para a\u{00F1}adir otro. Puedes abrir varias pesta\u{00F1}as, usar un explorador de archivos SFTP y crear t\u{00FA}neles SSH.")))
        welcome.children.append(button(L("Siguiente") + " \u{2192}", id: "Asistente_Siguiente") { [weak self] in
            guard let self else { return }
            self.go(self.first)
        })
    }

    private func buildFirst() {
        first.orientation = .vertical
        first.spacing = 6
        first.children.append(heading(L("Tu primera sesi\u{00F3}n")))
        first.children.append(paragraph(L("Nombre y equipo son obligatorios; usuario y puerto, no. Puedes saltarte este paso y a\u{00F1}adir sesiones m\u{00E1}s tarde.")))
        let fields: [(String, TextBox, String)] = [
            (L("Nombre"), name, "Asistente_Nombre"),
            (L("Equipo"), host, "Asistente_Equipo"),
            (L("Usuario"), user, "Asistente_Usuario"),
            (L("Puerto"), port, "Asistente_Puerto"),
        ]
        for (label, box, id) in fields {
            let caption = TextBlock()
            caption.text = label
            caption.fontSize = 12
            caption.opacity = 0.7
            AutomationProperties.setAutomationId(box, id)
            let item = StackPanel()
            item.orientation = .vertical
            item.spacing = 2
            item.children.append(caption)
            item.children.append(box)
            first.children.append(item)
        }
        port.placeholderText = "22"
        message.textWrapping = .wrap
        message.margin = Thickness(left: 0, top: 4, right: 0, bottom: 0)
        AutomationProperties.setAutomationId(message, "Asistente_Mensaje")
        first.children.append(message)
        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.margin = Thickness(left: 0, top: 8, right: 0, bottom: 0)
        buttons.children.append(button(L("Crear sesi\u{00F3}n"), id: "Asistente_Crear") { [weak self] in self?.create() })
        buttons.children.append(button(L("Omitir"), id: "Asistente_Omitir") { [weak self] in self?.onDone?() })
        first.children.append(buttons)
    }

    private func buildReady() {
        ready.orientation = .vertical
        ready.children.append(paragraph(L("\u{00A1}Todo listo! Haz clic en tu sesi\u{00F3}n para conectar.")))
        ready.children.append(button(L("Empezar"), id: "Asistente_Empezar") { [weak self] in self?.onDone?() })
    }

    private func create() {
        let trimmed = { (box: TextBox) in box.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trimmed(name).isEmpty, !trimmed(host).isEmpty else {
            message.text = L("Escribe al menos un nombre y un equipo")
            return
        }
        var session = EditableSession.new(group: "General", name: trimmed(name))
        session.host = trimmed(host)
        if !trimmed(user).isEmpty { session.user = trimmed(user) }
        if !trimmed(port).isEmpty { session.port = trimmed(port) }
        message.text = ""
        if onCreateSession?(session) == true { go(ready) }
    }
}
