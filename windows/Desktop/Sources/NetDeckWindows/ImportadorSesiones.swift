import Foundation
import NetDeckCore
import WinSDK
import WinUI

/// Vista previa y selección de sesiones antes de añadirlas al gestor.
final class PanelImportador {
    let view = ScrollViewer()
    var onClose: (() -> Void)?
    var onImportar: (([EditableSession]) -> Void)?
    var owner: HWND?

    private var existentes: [EditableSession] = []
    private var resultado: SessionImporter.Result?
    private var elegidas: Set<Foundation.UUID> = []
    private var casillas: [Foundation.UUID: CheckBox] = [:]
    private var estilo = EstiloMac(tema: nil)
    private let form = StackPanel()
    private let resumen = TextBlock()
    private let selector = Button()
    private let lista = StackPanel()
    private let importar = Button()
    private let error = TextBlock()

    init() {
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
        selector.click.addHandler { [weak self] _, _ in self?.alternarTodas() }
        importar.click.addHandler { [weak self] _, _ in
            guard let self, let resultado else { return }
            onImportar?(resultado.sessions.filter { self.elegidas.contains($0.id) })
        }
        AutomationProperties.setAutomationId(importar, "Importador_Importar")
        form.spacing = 14
        form.padding = Thickness(left: 20, top: 20, right: 20, bottom: 20)
        lista.spacing = 1
    }

    func show(existentes: [EditableSession], estilo: EstiloMac) {
        self.existentes = existentes
        self.estilo = estilo
        resultado = nil
        elegidas.removeAll()
        casillas.removeAll()
        lista.children.clear()
        form.children.clear()
        error.text = ""
        form.children.append(EstiloMac.letra(L("IMPORTAR SESIONES"), tamano: 16, peso: 800, color: estilo.acento))
        let ayuda = EstiloMac.letra(
            L("SecureCRT (la carpeta Sessions o un .ini), MobaXterm (.mxtsessions/.mobaconf), PuTTY (.reg), electerm (.json), ")
                + L("CSV del inventario, un ssh_config o un JSON exportado desde aquí. Las carpetas pasan a ser grupos. Nunca se importa ninguna contraseña."),
            tamano: 11, color: estilo.apagado)
        ayuda.textWrapping = .wrap
        form.children.append(ayuda)

        let opciones = StackPanel()
        opciones.orientation = .horizontal
        opciones.spacing = 8
        let elegir = Button()
        elegir.content = L("Elegir archivo…")
        AutomationProperties.setAutomationId(elegir, "Importador_ElegirArchivo")
        elegir.click.addHandler { [weak self] _, _ in self?.elegirArchivo() }
        opciones.children.append(elegir)
        let carpeta = Button()
        carpeta.content = L("Elegir carpeta…")
        carpeta.click.addHandler { [weak self] _, _ in
            guard let self, let owner,
                  let url = SelectorArchivos.carpeta(titulo: L("Elegir carpeta…"), owner: owner) else { return }
            leer(url)
        }
        opciones.children.append(carpeta)
        form.children.append(opciones)
        error.foreground = estilo.mal
        error.textWrapping = .wrap
        form.children.append(error)

        let cabecera = StackPanel()
        cabecera.orientation = .horizontal
        cabecera.spacing = 12
        resumen.fontSize = 12
        resumen.foreground = estilo.texto
        resumen.verticalAlignment = .center
        cabecera.children.append(resumen)
        cabecera.children.append(selector)
        form.children.append(cabecera)
        form.children.append(lista)
        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.spacing = 8
        acciones.horizontalAlignment = .right
        acciones.children.append(importar)
        let cancelar = Button()
        cancelar.content = L("Cancelar")
        cancelar.click.addHandler { [weak self] _, _ in self?.onClose?() }
        acciones.children.append(cancelar)
        form.children.append(acciones)
        resumen.text = ""
        selector.visibility = .collapsed
        importar.visibility = .collapsed
    }

    private func elegirArchivo() {
        guard let owner else { return }
        do {
            if let url = try SelectorArchivos.abrir(titulo: L("Importar sesiones"), tipo: L("Archivos de sesión"),
                                                    patron: "*.ini;*.mxtsessions;*.mobaconf;*.reg;*.json;*.csv;ssh_config;config",
                                                    owner: owner) { leer(url) }
        } catch let fallo {
            error.text = fallo.localizedDescription
        }
    }

    private func leer(_ url: URL) {
        error.text = ""
        let leido = SessionImporter.read(url, existing: existentes)
        resultado = leido
        elegidas = Set(leido.sessions.map(\.id))
        casillas.removeAll()
        lista.children.clear()
        resumen.text = L("\(leido.format): \(leido.sessions.count) nuevas")
        if !leido.skipped.isEmpty { resumen.text += " " + L("· \(leido.skipped.count) saltadas") }
        for s in leido.sessions {
            let fila = CheckBox()
            let contenido = StackPanel()
            contenido.orientation = .horizontal
            contenido.spacing = 10
            let destino = "\(s.user.isEmpty ? "" : s.user + "@")\(s.host):\(s.port)\(s.jump.isEmpty ? "" : " ⟵ " + s.jump)\(s.kind == .ssh ? "" : " · " + s.kind.label)"
            contenido.children.append(EstiloMac.letra(s.name, tamano: 12, peso: 600, color: estilo.texto))
            contenido.children.append(EstiloMac.letra(destino, tamano: 10.5, color: estilo.apagado))
            contenido.children.append(EstiloMac.letra(L(nombre: s.group), tamano: 10, peso: 700, color: estilo.acento2))
            fila.content = contenido
            fila.isChecked = true
            fila.checked.addHandler { [weak self] _, _ in self?.seleccionar(s.id, true) }
            fila.unchecked.addHandler { [weak self] _, _ in self?.seleccionar(s.id, false) }
            casillas[s.id] = fila
            lista.children.append(fila)
        }
        if !leido.skipped.isEmpty {
            lista.children.append(EstiloMac.letra(L("Saltadas"), tamano: 11, peso: 700, color: estilo.apagado))
            for (nombre, motivo) in leido.skipped {
                lista.children.append(EstiloMac.letra("\(nombre): \(motivo)", tamano: 10.5, color: estilo.apagado))
            }
        }
        selector.visibility = leido.sessions.isEmpty ? .collapsed : .visible
        importar.visibility = .visible
        actualizarAcciones()
    }

    private func alternarTodas() {
        let seleccionar = elegidas.count != casillas.count
        for fila in casillas.values { fila.isChecked = seleccionar }
    }

    private func seleccionar(_ id: Foundation.UUID, _ activo: Bool) {
        if activo { elegidas.insert(id) } else { elegidas.remove(id) }
        actualizarAcciones()
    }

    private func actualizarAcciones() {
        selector.content = elegidas.count == casillas.count ? L("Ninguna") : L("Todas")
        importar.content = L("Añadir \(elegidas.count) al gestor")
        importar.isEnabled = !elegidas.isEmpty
    }
}
