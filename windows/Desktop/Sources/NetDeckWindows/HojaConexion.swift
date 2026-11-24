import Foundation
import NetDeckCore
import WinUI

/// Conexión rápida o acceso directo de salto, como la del Mac: «equipo» (alias o usuario@equipo[:puerto]) por «salto»
/// (una sesión, opcional).
final class HojaConexion {
    let view = ScrollViewer()
    var onClose: (() -> Void)?
    /// equipo, salto ("" = directo), usuario (nil = el del equipo o el de la sesión), protocolo.
    var onConectar: ((String, String, String?, SessionProfile.Transport) -> Void)?

    private let hostBox = TextBox()
    private let saltoCombo = ComboBox()
    private let usuarioBox = TextBox()
    private let protocoloCombo = ComboBox()
    private let conectarBtn = Button()
    private var saltos: [String] = []
    private var enfocar = false

    private static let protocolos: [SessionProfile.Transport] = [.ssh, .telnet]

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.maxWidth = 480
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let titulo = TextBlock()
        titulo.text = L("Conexión rápida")
        titulo.fontSize = 20

        hostBox.header = L("Equipo")
        hostBox.placeholderText = L("192.0.2.5 · admin@core-01 · core-01:2222")
        hostBox.minWidth = 380
        AutomationProperties.setAutomationId(hostBox, "Hoja_Host")
        hostBox.textChanged.addHandler { [weak self] _, _ in self?.actualizarConectar() }

        saltoCombo.header = L("Salto")
        saltoCombo.minWidth = 380
        AutomationProperties.setAutomationId(saltoCombo, "Hoja_Salto")

        usuarioBox.header = L("Usuario")
        usuarioBox.placeholderText = L("(el del equipo o el de la sesión)")
        usuarioBox.minWidth = 380
        AutomationProperties.setAutomationId(usuarioBox, "Hoja_Usuario")

        protocoloCombo.header = L("Protocolo")
        protocoloCombo.minWidth = 160
        for p in Self.protocolos { protocoloCombo.items.append(p.rawValue) }
        protocoloCombo.selectedIndex = 0
        AutomationProperties.setAutomationId(protocoloCombo, "Hoja_Transporte")

        conectarBtn.content = L("Conectar")
        AutomationProperties.setAutomationId(conectarBtn, "Hoja_Conectar")
        conectarBtn.click.addHandler { [weak self] _, _ in self?.conectar() }

        let cancelarBtn = Button()
        cancelarBtn.content = L("Cancelar")
        AutomationProperties.setAutomationId(cancelarBtn, "Hoja_Cancelar")
        cancelarBtn.click.addHandler { [weak self] _, _ in self?.onClose?() }

        for campo in [hostBox, usuarioBox] {
            campo.keyDown.addHandler { [weak self] _, args in
                guard let args, args.key.rawValue == 13 else { return }
                args.handled = true
                self?.conectar()
            }
        }

        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.horizontalAlignment = .right
        acciones.spacing = 8
        acciones.margin = Thickness(left: 0, top: 8, right: 0, bottom: 0)
        acciones.children.append(cancelarBtn)
        acciones.children.append(conectarBtn)

        form.children.append(titulo)
        form.children.append(hostBox)
        form.children.append(saltoCombo)
        form.children.append(usuarioBox)
        form.children.append(protocoloCombo)
        form.children.append(acciones)

        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
        // El TextBox no acepta el foco hasta tener tamaño (se hace visible en la misma pasada).
        view.layoutUpdated.addHandler { [weak self] _, _ in
            guard let self, enfocar, view.visibility == .visible, hostBox.actualWidth > 0 else { return }
            if (try? hostBox.focus(.keyboard)) == true { enfocar = false }
        }
    }

    /// `sesiones`: los nombres para «Salto», además de «Directo».
    func show(sesiones: [String]) {
        hostBox.text = ""
        usuarioBox.text = ""
        saltos = [""] + sesiones
        saltoCombo.items.clear()
        saltoCombo.items.append(L("Directo"))
        for s in sesiones { saltoCombo.items.append(s) }
        saltoCombo.selectedIndex = 0
        protocoloCombo.selectedIndex = 0
        actualizarConectar()
        enfocar = true
        view.visibility = .visible
    }

    private func actualizarConectar() {
        conectarBtn.isEnabled = Endpoint(parsing: hostBox.text.trimmingCharacters(in: .whitespaces)) != nil
    }

    private func conectar() {
        let equipo = hostBox.text.trimmingCharacters(in: .whitespaces)
        guard Endpoint(parsing: equipo) != nil else { return }
        let usuario = usuarioBox.text.trimmingCharacters(in: .whitespaces)
        let i = Int(saltoCombo.selectedIndex)
        let salto = saltos.indices.contains(i) ? saltos[i] : ""
        let p = Int(protocoloCombo.selectedIndex)
        let protocolo = Self.protocolos.indices.contains(p) ? Self.protocolos[p] : .ssh
        onConectar?(equipo, salto, usuario.isEmpty ? nil : usuario, protocolo)
    }
}
