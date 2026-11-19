import Foundation
import NetDeckCore
import WinUI

final class HojaConexion {
    let view = ScrollViewer()
    var onClose: (() -> Void)?
    var onConectar: ((String, String?, String, SessionProfile.Transport) -> Void)?

    private let hostBox = TextBox()
    private let saltoBox = TextBox()
    private let usuarioBox = TextBox()
    private let transporteCombo = ComboBox()
    private let estadoLabel = TextBlock()

    private static let transportes: [(String, SessionProfile.Transport)] = [
        ("SSH", .ssh), ("Telnet", .telnet), ("SFTP", .sftp),
        ("FTP", .ftp), ("Serial", .serial), ("Local", .local)
    ]

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.maxWidth = 480
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let titulo = TextBlock()
        titulo.text = L("Conexión rápida")
        titulo.fontSize = 20

        hostBox.header = L("Equipo / host")
        hostBox.placeholderText = "admin@equipo.local"
        hostBox.minWidth = 280
        AutomationProperties.setAutomationId(hostBox, "Hoja_Host")

        saltoBox.header = L("Salto SSH (opcional)")
        saltoBox.minWidth = 280
        AutomationProperties.setAutomationId(saltoBox, "Hoja_Salto")

        usuarioBox.header = L("Usuario")
        usuarioBox.minWidth = 280
        AutomationProperties.setAutomationId(usuarioBox, "Hoja_Usuario")

        transporteCombo.header = L("Transporte")
        transporteCombo.minWidth = 160
        for (label, _) in Self.transportes { transporteCombo.items.append(label) }
        transporteCombo.selectedIndex = 0
        AutomationProperties.setAutomationId(transporteCombo, "Hoja_Transporte")

        estadoLabel.opacity = 0.6
        estadoLabel.textWrapping = .wrap

        let conectarBtn = Button()
        conectarBtn.content = L("Conectar")
        AutomationProperties.setAutomationId(conectarBtn, "Hoja_Conectar")
        conectarBtn.click.addHandler { [weak self] _, _ in self?.conectar() }

        let cancelarBtn = Button()
        cancelarBtn.content = L("Cancelar")
        AutomationProperties.setAutomationId(cancelarBtn, "Hoja_Cancelar")
        cancelarBtn.click.addHandler { [weak self] _, _ in self?.onClose?() }

        hostBox.keyDown.addHandler { [weak self] _, args in
            guard let args, args.key.rawValue == 13 else { return }
            args.handled = true
            self?.conectar()
        }

        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.spacing = 8
        acciones.margin = Thickness(left: 0, top: 8, right: 0, bottom: 0)
        acciones.children.append(conectarBtn)
        acciones.children.append(cancelarBtn)

        form.children.append(titulo)
        form.children.append(hostBox)
        form.children.append(saltoBox)
        form.children.append(usuarioBox)
        form.children.append(transporteCombo)
        form.children.append(estadoLabel)
        form.children.append(acciones)

        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    func show() {
        hostBox.text = ""
        saltoBox.text = ""
        usuarioBox.text = ""
        transporteCombo.selectedIndex = 0
        estadoLabel.text = ""
        view.visibility = .visible
        _ = try? hostBox.focus(.programmatic)
    }

    private func conectar() {
        let host = hostBox.text.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else {
            estadoLabel.text = L("Escribe el equipo o dirección IP")
            return
        }
        let salto = saltoBox.text.trimmingCharacters(in: .whitespaces)
        let usuario = usuarioBox.text.trimmingCharacters(in: .whitespaces)
        let idx = Int(transporteCombo.selectedIndex)
        let transport = idx >= 0 && idx < Self.transportes.count ? Self.transportes[idx].1 : .ssh
        estadoLabel.text = ""
        onConectar?(host, salto.isEmpty ? nil : salto, usuario, transport)
    }
}
