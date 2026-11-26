import Foundation
import NetDeckCore
import WinUI

/// La misma biblioteca de listas que usa el gestor de macOS, con un borrador local.
final class PanelListas {
    let view = ScrollViewer()
    var onGuardar: ((ListLibrary) throws -> Void)?
    var onAbrir: ((SavedList) -> Void)?
    var onImportar: (() throws -> URL?)?

    private let raiz = Grid()
    private let listas = StackPanel()
    private let form = StackPanel()
    private let nombre = TextBox()
    private let salto = TextBox()
    private let usuario = TextBox()
    private let credencial = ComboBox()
    private let equipos = TextBox()
    private let resumen = TextBlock()
    private let mensaje = TextBlock()
    private let accionesPendientes = StackPanel()
    private let guardar = Button()
    private let abrir = Button()
    private var biblioteca = ListLibrary()
    private var id: SavedList.ID?
    private var valoresCredenciales: [String] = []
    private var estilo = EstiloMac(tema: nil)
    private var inicial: [String] = []
    private var cargando = false
    private var mostrada = false

    init() {
        for ancho in [GridLength(value: 236, gridUnitType: .pixel), GridLength(value: 1, gridUnitType: .star)] {
            let columna = ColumnDefinition()
            columna.width = ancho
            raiz.columnDefinitions.append(columna)
        }
        listas.spacing = 5
        listas.padding = Thickness(left: 10, top: 14, right: 10, bottom: 12)
        form.spacing = 9
        form.padding = Thickness(left: 16, top: 14, right: 16, bottom: 12)
        Grid.setColumn(form, 1)
        raiz.children.append(listas)
        raiz.children.append(form)
        view.content = raiz
        view.horizontalScrollBarVisibility = .disabled
        view.verticalScrollBarVisibility = .auto

        nombre.header = L("Nombre")
        salto.header = L("Salto")
        usuario.header = L("Usuario")
        credencial.header = L("Contraseña")
        equipos.header = L("Equipos")
        equipos.fontFamily = FontFamily("Consolas")
        equipos.minHeight = 145
        equipos.acceptsReturn = true
        equipos.textWrapping = .wrap
        for campo in [nombre, salto, usuario, equipos] {
            campo.textChanged.addHandler { [weak self] _, _ in self?.actualizar() }
        }
        for campo in [nombre, salto, usuario] { form.children.append(campo) }
        form.children.append(credencial)
        form.children.append(equipos)
        credencial.selectionChanged.addHandler { [weak self] _, _ in self?.actualizar() }
        resumen.textWrapping = .wrap
        mensaje.textWrapping = .wrap
        form.children.append(resumen)
        form.children.append(mensaje)
        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.horizontalAlignment = .right
        acciones.spacing = 8
        guardar.content = L("Guardar lista")
        guardar.click.addHandler { [weak self] _, _ in self?.guardarLista() }
        abrir.content = L("Abrir")
        abrir.click.addHandler { [weak self] _, _ in
            guard let self, let lista = actual() else { return }
            onAbrir?(lista)
        }
        acciones.children.append(guardar)
        acciones.children.append(abrir)
        form.children.append(acciones)
        accionesPendientes.orientation = .horizontal
        accionesPendientes.spacing = 8
        form.children.append(accionesPendientes)
    }

    func mostrar(biblioteca: ListLibrary, estilo: EstiloMac, credenciales: [String], saltos: [String]) {
        self.biblioteca = biblioteca
        self.estilo = estilo
        listas.background = estilo.barra
        mensaje.foreground = estilo.aviso
        resumen.foreground = estilo.apagado
        salto.placeholderText = saltos.isEmpty ? "bastion" : saltos.joined(separator: ", ")
        if mostrada, campos != inicial {
            reconstruirLista()
            return
        }
        mostrada = true
        valoresCredenciales = [""] + credenciales
        elegir(biblioteca.list(id) ?? biblioteca.lists.first)
    }

    private var campos: [String] {
        let i = Int(credencial.selectedIndex)
        return [nombre.text, salto.text, usuario.text, valoresCredenciales.indices.contains(i) ? valoresCredenciales[i] : "", equipos.text]
    }

    private func elegir(_ lista: SavedList?) {
        cargando = true
        id = lista?.id
        nombre.text = lista?.name ?? biblioteca.uniqueName("lista")
        salto.text = lista?.jump ?? ""
        usuario.text = lista?.user ?? ""
        equipos.text = lista?.devices.joined(separator: "\n") ?? ""
        let elegida = lista?.credential ?? ""
        if !valoresCredenciales.contains(elegida) { valoresCredenciales.append(elegida) }
        credencial.items.clear()
        for item in valoresCredenciales { credencial.items.append(item.isEmpty ? L("(a mano)") : item) }
        credencial.selectedIndex = Int32(valoresCredenciales.firstIndex(of: elegida) ?? 0)
        inicial = campos
        accionesPendientes.children.clear()
        mensaje.text = ""
        cargando = false
        reconstruirLista()
        actualizar()
    }

    private func boton(_ texto: String, accion: @escaping () -> Void) -> Button {
        let b = Button()
        b.content = EstiloMac.letra(texto, tamano: 12, color: estilo.texto)
        b.background = estilo.panel
        b.click.addHandler { _, _ in accion() }
        return b
    }

    private func reconstruirLista() {
        listas.children.clear()
        listas.children.append(EstiloMac.letra(L("LISTAS"), tamano: 13, peso: 800, color: estilo.acento))
        for lista in biblioteca.lists {
            let item = Button()
            estilo.plano(item)
            let texto = StackPanel()
            let activa = lista.id == id
            let color = activa ? estilo.sobrePestana : estilo.texto
            texto.children.append(EstiloMac.letra(lista.name, tamano: 12, peso: 600, color: color))
            let pista = L("\(lista.devices.count) equipos") + (lista.jump.isEmpty ? "" : "  ⟵ \(lista.jump)")
            texto.children.append(EstiloMac.letra(pista, tamano: 9.5, color: activa ? color : estilo.apagado))
            item.content = texto
            item.background = activa ? estilo.pestana : estilo.transparente
            item.click.addHandler { [weak self] _, _ in self?.pedirCambio { [weak self] in self?.elegir(lista) } }
            let menu = MenuFlyout()
            let duplicar = MenuFlyoutItem()
            duplicar.text = L("Duplicar")
            duplicar.click.addHandler { [weak self] _, _ in
                self?.pedirCambio { [weak self] in
                    guard let self else { return }
                    var copia = biblioteca
                    guard let nueva = copia.duplicate(lista.id) else { return }
                    persistir(copia, elegir: nueva, mensaje: L("✓ Copia «\(nueva.name)»"))
                }
            }
            let renombrar = MenuFlyoutItem()
            renombrar.text = L("Renombrar…")
            renombrar.click.addHandler { [weak self] _, _ in
                self?.pedirCambio { [weak self] in
                    guard let self else { return }
                    elegir(lista)
                    _ = try? nombre.focus(.programmatic)
                    try? nombre.selectAll()
                }
            }
            let borrar = MenuFlyoutItem()
            borrar.text = L("Borrar…")
            borrar.click.addHandler { [weak self] _, _ in self?.confirmarBorrar(lista) }
            menu.items.append(duplicar)
            menu.items.append(renombrar)
            menu.items.append(MenuFlyoutSeparator())
            menu.items.append(borrar)
            item.contextFlyout = menu
            listas.children.append(item)
        }
        listas.children.append(boton(L("Nueva")) { [weak self] in self?.pedirCambio { [weak self] in self?.elegir(nil) } })
        listas.children.append(boton(L("Importar equipos de un .txt/.csv…")) { [weak self] in self?.importar() })
    }

    private func pedirCambio(_ accion: @escaping () -> Void) {
        guard campos != inicial else { accion(); return }
        confirmar(L("Hay cambios sin guardar"), aceptar: L("Descartar"), accion)
    }

    private func confirmarBorrar(_ lista: SavedList) {
        confirmar(L("¿Borrar la lista «\(lista.name)»?"), aceptar: L("Borrar")) { [weak self] in
            guard let self else { return }
            var copia = biblioteca
            copia.remove(lista.id)
            persistir(copia, elegir: copia.list(id) ?? copia.lists.first, mensaje: L("✓ Borrada"))
        }
    }

    private func confirmar(_ titulo: String, aceptar: String, _ accion: @escaping () -> Void) {
        mensaje.text = titulo
        accionesPendientes.children.clear()
        accionesPendientes.children.append(boton(aceptar) { [weak self] in
            self?.accionesPendientes.children.clear()
            accion()
        })
        accionesPendientes.children.append(boton(L("Cancelar")) { [weak self] in
            self?.accionesPendientes.children.clear()
            self?.mensaje.text = ""
        })
    }

    private func actualizar() {
        guard !cargando else { return }
        let r = DeviceListText.parse(equipos.text)
        resumen.text = L("\(r.devices.count) equipos · una sola pestaña prueba la contraseña a la vez; si falla, no se escribe en las demás")
        if !r.rejected.isEmpty { resumen.text += "\n" + L("No valen (se ignoran): \(r.rejected.prefix(5).joined(separator: " · "))") }
        guardar.isEnabled = campos != inicial && !nombre.text.trimmingCharacters(in: .whitespaces).isEmpty
        abrir.isEnabled = !salto.text.trimmingCharacters(in: .whitespaces).isEmpty && !r.devices.isEmpty
    }

    private func actual() -> SavedList? {
        let c = campos.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !c[0].isEmpty else { return nil }
        return SavedList(id: id ?? Foundation.UUID(), name: c[0], jump: c[1], user: c[2], credential: c[3],
                         devices: DeviceListText.parse(c[4]).devices.map(\.description))
    }

    private func guardarLista() {
        guard let lista = actual() else { return }
        var copia = biblioteca
        let guardada = copia.upsert(lista)
        persistir(copia, elegir: guardada, mensaje: L("✓ Lista «\(guardada.name)» guardada"))
    }

    private func persistir(_ copia: ListLibrary, elegir lista: SavedList?, mensaje ok: String) {
        do {
            try onGuardar?(copia)
            biblioteca = copia
            elegir(lista)
            mensaje.text = ok
        } catch {
            mensaje.text = error.localizedDescription
        }
    }

    private func importar() {
        do {
            guard let archivo = try onImportar?(), let texto = try SafeFile.read(archivo) else { return }
            let lista = DeviceListText.parse(DeviceListText.importing(texto))
            equipos.text = ([equipos.text] + lista.devices.map(\.description)).filter { !$0.isEmpty }.joined(separator: "\n")
            mensaje.text = L("\(lista.devices.count) equipos importados de \(archivo.lastPathComponent)")
        } catch {
            mensaje.text = error.localizedDescription
        }
    }
}
