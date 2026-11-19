import Foundation
import NetDeckCore
import WinUI

// MARK: - EdicionPendiente

struct EdicionPendiente {
    let id: UUID
    let sessionName: String
    let remotePath: String
    let localURL: URL
    var estado: String
    var lastMod: Date?
    var watchTask: Task<Void, Never>?
}

// MARK: - PanelEdicionRemota

final class PanelEdicionRemota {
    let view = ScrollViewer()
    var onClose: (() -> Void)?
    var onDescargar: ((String, String, URL, @escaping (String) -> Void) async throws -> Void)?
    var onSubir: ((URL, String, String, @escaping (String) -> Void) async throws -> Void)?

    private var ediciones: [EdicionPendiente] = []
    private let form = StackPanel()
    private let listaPanel = StackPanel()
    private let sesionBox = TextBox()
    private let rutaBox = TextBox()
    private let estadoLabel = TextBlock()

    init() {
        form.spacing = 8
        form.maxWidth = 600
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let titulo = TextBlock()
        titulo.text = L("Edici\u{00F3}n de ficheros remotos")
        titulo.fontSize = 20

        sesionBox.header = L("Nombre de sesi\u{00F3}n")
        sesionBox.minWidth = 300
        AutomationProperties.setAutomationId(sesionBox, "Edicion_Sesion")

        rutaBox.header = L("Ruta remota")
        rutaBox.placeholderText = "/etc/hosts"
        rutaBox.minWidth = 300
        AutomationProperties.setAutomationId(rutaBox, "Edicion_Ruta")

        estadoLabel.opacity = 0.6
        estadoLabel.textWrapping = .wrap

        let abrirBtn = Button()
        abrirBtn.content = L("Abrir para editar")
        AutomationProperties.setAutomationId(abrirBtn, "Edicion_Abrir")
        abrirBtn.click.addHandler { [weak self] _, _ in self?.iniciarEdicion() }

        let cerrarBtn = Button()
        cerrarBtn.content = L("Cerrar")
        cerrarBtn.click.addHandler { [weak self] _, _ in self?.onClose?() }

        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.spacing = 8
        acciones.children.append(abrirBtn)
        acciones.children.append(cerrarBtn)

        let sep = TextBlock()
        sep.text = L("Ediciones activas:")
        sep.fontSize = 12
        sep.margin = Thickness(left: 0, top: 12, right: 0, bottom: 4)
        sep.opacity = 0.7

        listaPanel.spacing = 4

        form.children.append(titulo)
        form.children.append(sesionBox)
        form.children.append(rutaBox)
        form.children.append(estadoLabel)
        form.children.append(acciones)
        form.children.append(sep)
        form.children.append(listaPanel)

        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    func show() {
        sesionBox.text = ""
        rutaBox.text = ""
        estadoLabel.text = ""
        view.visibility = .visible
    }

    private func iniciarEdicion() {
        let sesion = sesionBox.text.trimmingCharacters(in: .whitespaces)
        let ruta = rutaBox.text.trimmingCharacters(in: .whitespaces)
        guard !sesion.isEmpty else { estadoLabel.text = L("Escribe el nombre de la sesi\u{00F3}n"); return }
        guard !ruta.isEmpty else { estadoLabel.text = L("Escribe la ruta remota"); return }

        let nombre = (ruta as NSString).lastPathComponent
        let tempDir = AppPaths.support.appendingPathComponent("edicion-remota")
        _ = AppPaths.ensure(tempDir)
        let localURL = tempDir.appendingPathComponent("\(sesion)_\(nombre)")

        estadoLabel.text = L("Descargando\u{2026}")
        let edit = EdicionPendiente(id: UUID(), sessionName: sesion, remotePath: ruta,
                              localURL: localURL, estado: L("Descargando\u{2026}"), lastMod: nil)
        ediciones.append(edit)
        reloadLista()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.onDescargar?(sesion, ruta, localURL) { msg in
                    self.setEstado(localURL, msg)
                }
                let mod = (try? FileManager.default.attributesOfItem(atPath: localURL.path))?[.modificationDate] as? Date
                self.setEstado(localURL, L("Listo \u{2014} vigilando cambios"))
                self.setLastMod(localURL, mod)
                self.startWatching(localURL: localURL, sesion: sesion, ruta: ruta)
            } catch {
                self.setEstado(localURL, L("Error: \(error.localizedDescription)"))
            }
        }
    }

    private func startWatching(localURL: URL, sesion: String, ruta: String) {
        guard let idx = ediciones.firstIndex(where: { $0.localURL == localURL }) else { return }
        ediciones[idx].watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self else { break }
                let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path)
                let mod = attrs?[.modificationDate] as? Date
                guard let mod,
                      let prev = self.ediciones.first(where: { $0.localURL == localURL })?.lastMod,
                      mod > prev else { continue }
                self.setLastMod(localURL, mod)
                self.setEstado(localURL, L("Subiendo\u{2026}"))
                do {
                    try await self.onSubir?(localURL, sesion, ruta) { msg in self.setEstado(localURL, msg) }
                    self.setEstado(localURL, L("Sincronizado"))
                } catch {
                    self.setEstado(localURL, L("Error al subir: \(error.localizedDescription)"))
                }
            }
        }
        reloadLista()
    }

    func stop(_ id: UUID) {
        guard let idx = ediciones.firstIndex(where: { $0.id == id }) else { return }
        ediciones[idx].watchTask?.cancel()
        ediciones.remove(at: idx)
        reloadLista()
    }

    private func setEstado(_ url: URL, _ estado: String) {
        guard let idx = ediciones.firstIndex(where: { $0.localURL == url }) else { return }
        ediciones[idx].estado = estado
        reloadLista()
    }

    private func setLastMod(_ url: URL, _ date: Date?) {
        guard let idx = ediciones.firstIndex(where: { $0.localURL == url }) else { return }
        ediciones[idx].lastMod = date
    }

    private func reloadLista() {
        listaPanel.children.clear()
        for edit in ediciones {
            let fila = Grid()
            let colInfo = ColumnDefinition()
            colInfo.width = GridLength(value: 1, gridUnitType: .star)
            let colBtn = ColumnDefinition()
            colBtn.width = GridLength(value: 1, gridUnitType: .auto)
            fila.columnDefinitions.append(colInfo)
            fila.columnDefinitions.append(colBtn)

            let info = StackPanel()
            info.spacing = 2
            let rutaLbl = TextBlock()
            rutaLbl.text = edit.remotePath
            rutaLbl.textWrapping = .wrap
            let estadoLbl = TextBlock()
            estadoLbl.text = edit.estado
            estadoLbl.fontSize = 11
            estadoLbl.opacity = 0.6
            info.children.append(rutaLbl)
            info.children.append(estadoLbl)

            let pararBtn = Button()
            pararBtn.content = L("Parar")
            pararBtn.margin = Thickness(left: 8, top: 0, right: 0, bottom: 0)
            let editId = edit.id
            AutomationProperties.setAutomationId(pararBtn, "Edicion_Parar_\(editId)")
            pararBtn.click.addHandler { [weak self] _, _ in self?.stop(editId) }

            Grid.setColumn(info, Int32(0))
            Grid.setColumn(pararBtn, Int32(1))
            fila.children.append(info)
            fila.children.append(pararBtn)
            fila.margin = Thickness(left: 0, top: 2, right: 0, bottom: 2)
            listaPanel.children.append(fila)
        }
    }
}
