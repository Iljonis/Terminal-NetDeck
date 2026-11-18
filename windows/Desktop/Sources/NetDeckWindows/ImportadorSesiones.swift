import Foundation
import NetDeckCore
import WinUI

// PanelImportador — importa sesiones de SecureCRT, MobaXterm, PuTTY, electerm, SSH config y CSV.
// Usa SessionImporter (NetDeckCore) para el parsing; esta clase solo aporta la UI de Windows.

final class PanelImportador {
    let view = ScrollViewer()
    var onClose: (() -> Void)?
    var onImportar: (([EditableSession]) -> Void)?
    /// Sesiones ya existentes para que SessionImporter detecte duplicados.
    var existingSessions: [EditableSession] = []

    private var sesionesLeidas: [EditableSession] = []
    private let rutaBox = TextBox()
    private let estadoLabel = TextBlock()
    private let listaPanel = StackPanel()
    private let importarBtn = Button()

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.maxWidth = 560
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let titulo = TextBlock()
        titulo.text = L("Importar sesiones")
        titulo.fontSize = 20

        let hint = TextBlock()
        hint.text = L("SecureCRT (.ini), MobaXterm (.ini/.mxtsessions), PuTTY (.reg), electerm (.json) o CSV (.csv).")
        hint.textWrapping = .wrap
        hint.opacity = 0.6

        rutaBox.header = L("Ruta del fichero o carpeta")
        rutaBox.placeholderText = L("Pega aquí la ruta completa al fichero")
        AutomationProperties.setAutomationId(rutaBox, "Importador_Ruta")

        let leerBtn = Button()
        leerBtn.content = L("Leer fichero")
        AutomationProperties.setAutomationId(leerBtn, "Importador_Leer")
        leerBtn.click.addHandler { [weak self] _, _ in self?.leerFichero() }

        estadoLabel.textWrapping = .wrap
        estadoLabel.opacity = 0.6

        listaPanel.spacing = 2

        importarBtn.content = L("Importar")
        importarBtn.isEnabled = false
        AutomationProperties.setAutomationId(importarBtn, "Importador_Importar")
        importarBtn.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.onImportar?(self.sesionesLeidas)
        }

        let cancelarBtn = Button()
        cancelarBtn.content = L("Cancelar")
        cancelarBtn.click.addHandler { [weak self] _, _ in self?.onClose?() }

        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.spacing = 8
        acciones.children.append(importarBtn)
        acciones.children.append(cancelarBtn)

        form.children.append(titulo)
        form.children.append(hint)
        form.children.append(rutaBox)
        form.children.append(leerBtn)
        form.children.append(estadoLabel)
        form.children.append(listaPanel)
        form.children.append(acciones)

        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    func show() {
        rutaBox.text = ""
        sesionesLeidas = []
        estadoLabel.text = ""
        listaPanel.children.clear()
        importarBtn.content = L("Importar")
        importarBtn.isEnabled = false
        view.visibility = .visible
    }

    private func leerFichero() {
        let ruta = rutaBox.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ruta.isEmpty else {
            estadoLabel.text = L("Escribe la ruta del fichero")
            return
        }
        let url = URL(fileURLWithPath: ruta)
        guard FileManager.default.fileExists(atPath: url.path) else {
            estadoLabel.text = L("Fichero no encontrado")
            return
        }
        let result = SessionImporter.read(url, existing: existingSessions)
        sesionesLeidas = result.sessions
        mostrar(result)
    }

    private func mostrar(_ result: SessionImporter.Result) {
        listaPanel.children.clear()
        let n = result.sessions.count
        let omitidas = result.skipped.count
        var resumen = L("Formato: \(result.format) · \(n) sesiones")
        if omitidas > 0 { resumen += L(" · \(omitidas) omitidas (ya existen o no válidas)") }
        estadoLabel.text = resumen
        importarBtn.content = L("Importar \(n) sesiones")
        importarBtn.isEnabled = n > 0
        for s in result.sessions.prefix(25) {
            let fila = TextBlock()
            let host = s.host.isEmpty ? "" : "  — \(s.host)"
            fila.text = "• \(s.name)\(host)"
            fila.textWrapping = .wrap
            listaPanel.children.append(fila)
        }
        if n > 25 {
            let mas = TextBlock()
            mas.text = L("… y \(n - 25) más")
            mas.opacity = 0.6
            listaPanel.children.append(mas)
        }
    }
}
