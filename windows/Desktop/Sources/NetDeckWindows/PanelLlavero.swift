import Foundation
import NetDeckCore
import WinUI

final class PanelLlavero {
    let view = ScrollViewer()
    var onClose: (() -> Void)?
    var enqueue: (@escaping () -> Void) -> Void = { $0() }
    var onNombres: (([String]) -> Void)?
    var demo = false
    private var nombresDemo: Set<String> = []
    private var turno = 0
    var getArchivoBotones: (() -> ButtonFile)?

    private let lista = ComboBox()
    private let nombre = TextBox()
    private let clave = PasswordBox()
    private let uso = TextBlock()
    private var accounts: [String] = []
    private var pendingDelete: String?

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.maxWidth = 580
        form.horizontalAlignment = .left
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let titulo = TextBlock()
        titulo.text = L("Llavero de Windows")
        titulo.fontSize = 20

        lista.minWidth = 300
        lista.header = L("Credencial")

        nombre.header = L("Nombre de la credencial")
        nombre.minWidth = 300

        clave.header = L("Contrase\u{00F1}a")
        clave.minWidth = 300

        uso.opacity = 0.6
        uso.textWrapping = .wrap

        let guardar = Button()
        guardar.content = L("Guardar credencial")
        let borrar = Button()
        borrar.content = L("Borrar credencial")
        let recargar = Button()
        recargar.content = L("Recargar lista")
        let cerrar = Button()
        cerrar.content = L("Cerrar")

        AutomationProperties.setAutomationId(lista, "Llavero_Lista")
        AutomationProperties.setAutomationId(nombre, "Llavero_Nombre")
        AutomationProperties.setAutomationId(guardar, "Llavero_Guardar")
        AutomationProperties.setAutomationId(borrar, "Llavero_Borrar")

        lista.selectionChanged.addHandler { [weak self] _, _ in self?.loadSelected() }
        recargar.click.addHandler { [weak self] _, _ in self?.reload() }
        cerrar.click.addHandler { [weak self] _, _ in self?.onClose?() }

        guardar.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            let n = self.nombre.text.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else {
                self.uso.text = L("El nombre no puede estar vac\u{00ED}o")
                return
            }
            let valor = self.clave.password
            self.clave.password = ""
            guard !valor.isEmpty else { self.uso.text = L("Escribe la contraseña"); return }
            if demo {
                nombresDemo.insert(n)
                reload(cuenta: n, mensaje: L("Credencial guardada"))
                return
            }
            Task { [weak self] in
                do {
                    try await KeychainStore().saveInBackground(valor, for: .named(n))
                    self?.enqueue { [weak self] in self?.reload(cuenta: n, mensaje: L("Credencial guardada")) }
                } catch {
                    let mensaje = error.localizedDescription
                    self?.enqueue { [weak self] in self?.uso.text = mensaje }
                }
            }
        }

        borrar.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            let n = self.nombre.text.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return }
            if self.pendingDelete == n {
                self.pendingDelete = nil
                if demo {
                    nombresDemo.remove(n)
                    reload(mensaje: L("Credencial borrada"))
                    return
                }
                Task { [weak self] in
                    do {
                        try await KeychainStore().deleteInBackground(.named(n))
                        self?.enqueue { [weak self] in self?.reload(mensaje: L("Credencial borrada")) }
                    } catch {
                        let mensaje = error.localizedDescription
                        self?.enqueue { [weak self] in self?.uso.text = mensaje }
                    }
                }
            } else {
                self.pendingDelete = n
                self.uso.text = L("\u{00BF}Borrar \u{00AB}%@\u{00BB} del Llavero de Windows?").replacingOccurrences(of: "%@", with: n)
            }
        }

        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.spacing = 8
        acciones.margin = Thickness(left: 0, top: 8, right: 0, bottom: 0)
        acciones.children.append(guardar)
        acciones.children.append(borrar)
        acciones.children.append(recargar)
        acciones.children.append(cerrar)

        form.children.append(titulo)
        form.children.append(lista)
        form.children.append(nombre)
        form.children.append(clave)
        form.children.append(uso)
        form.children.append(acciones)

        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    func mostrar(cuenta: String?, nueva: Bool) {
        clave.password = ""
        reload(cuenta: cuenta, nueva: nueva)
    }

    func reload(cuenta: String? = nil, nueva: Bool = false, mensaje: String? = nil) {
        pendingDelete = nil
        turno += 1
        let pedido = turno
        if demo {
            cargar(nombresDemo.sorted(), cuenta: cuenta, nueva: nueva, mensaje: mensaje)
            return
        }
        Task { [weak self] in
            do {
                let nombres = try await KeychainStore().accountsInBackground()
                    .filter { $0.service == .named }.map(\.account)
                self?.enqueue { [weak self] in
                    guard let self, self.turno == pedido else { return }
                    self.cargar(nombres, cuenta: cuenta, nueva: nueva, mensaje: mensaje)
                }
            } catch {
                let motivo = error.localizedDescription
                self?.enqueue { [weak self] in
                    guard let self, self.turno == pedido else { return }
                    self.uso.text = motivo
                }
            }
        }
    }

    private func cargar(_ nombres: [String], cuenta: String?, nueva: Bool, mensaje: String?) {
        accounts = nombres
        lista.items.clear()
        for a in accounts { lista.items.append(a) }
        let indice = cuenta.flatMap { accounts.firstIndex(of: $0) } ?? 0
        lista.selectedIndex = nueva || accounts.isEmpty ? -1 : Int32(indice)
        loadSelected()
        if let mensaje { uso.text = mensaje }
        onNombres?(accounts)
    }

    private func loadSelected() {
        let index = Int(lista.selectedIndex)
        guard accounts.indices.contains(index) else {
            nombre.text = ""
            clave.password = ""
            uso.text = ""
            return
        }
        let cuenta = accounts[index]
        nombre.text = cuenta
        clave.password = ""
        pendingDelete = nil
        updateUsage(for: cuenta)
    }

    private func updateUsage(for cuenta: String) {
        let bots = getArchivoBotones?().buttons ?? []
        let enUso = bots.filter { btn in
            switch btn.mode {
            case .pass: return btn.command == cuenta
            case .login:
                let parts = btn.command.components(separatedBy: " / ")
                return parts.count >= 2 && parts.dropFirst().joined(separator: " / ") == cuenta
            default: return false
            }
        }
        if enUso.isEmpty {
            uso.text = L("Sin botones que la usen")
        } else {
            let n = enUso.count
            let nombres = enUso.map(\.name).joined(separator: ", ")
            uso.text = L("Usada por %d bot\u{00F3}n(es)").replacingOccurrences(of: "%d", with: "\(n)") + ": " + nombres
        }
    }
}