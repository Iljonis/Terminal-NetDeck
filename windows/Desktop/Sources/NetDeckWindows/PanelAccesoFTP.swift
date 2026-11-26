import NetDeckCore
import WinUI

final class PanelAccesoFTP {
    let view = ScrollViewer()
    var onConnect: ((ConnectionRoute, String, String) -> Void)?
    var onCancel: (() -> Void)?

    private let title = TextBlock()
    private let user = TextBox()
    private let password = PasswordBox()
    private var route: ConnectionRoute?

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.maxWidth = 460
        form.horizontalAlignment = .left
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        title.fontSize = 20
        let warning = TextBlock()
        warning.text = L("FTP no va cifrado: la contraseña viaja tal cual por la red.")
        warning.textWrapping = .wrap
        user.header = L("Usuario")
        password.header = L("Contraseña")
        let connect = Button()
        connect.content = L("Conectar por FTP")
        let cancel = Button()
        cancel.content = L("Cancelar")
        AutomationProperties.setAutomationId(user, "FTP_Usuario")
        AutomationProperties.setAutomationId(password, "FTP_Contraseña")
        AutomationProperties.setAutomationId(connect, "FTP_Conectar")
        connect.click.addHandler { [weak self] _, _ in
            guard let self, let route = self.route else { return }
            let typed = self.user.text.isEmpty ? "anonymous" : self.user.text
            let secret = self.password.password
            self.clear()
            self.onConnect?(route, typed, secret)
        }
        cancel.click.addHandler { [weak self] _, _ in self?.onCancel?() }
        for control in [title as FrameworkElement, warning, user, password, connect, cancel] {
            form.children.append(control)
        }
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.visibility = .collapsed
    }

    func show(_ route: ConnectionRoute) {
        self.route = route
        title.text = L("Explorador FTP") + " · " + route.title
        user.text = route.target.user ?? "anonymous"
        password.password = ""
    }

    func clear() {
        route = nil
        password.password = ""
    }
}
