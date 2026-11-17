import Foundation
import WinUI
import NetDeckCore

/// Ajustes del terminal que se guardan en UserDefaults (ndFuente, ndTamano, ndTema).
struct AjustesTerminal: Equatable {
    static let fuentes = ["Consolas", "Courier New", "Cascadia Code", "Cascadia Mono"]
    /// Valores guardados (en castellano); en pantalla van con L().
    static let temas = ["Sistema (Mica)", "Claro", "Oscuro"]
    static let tamanos = 10...20

    var fuente = "Consolas"
    var tamano = 15
    var tema = "Sistema (Mica)"
    /// Id del tema de colores del terminal (los de NetDeckCore); vacio = sin tema. Clave ndTemaNombre.
    var temaTerminal = ""

    static func cargar(_ defaults: UserDefaults = .standard) -> AjustesTerminal {
        var a = AjustesTerminal()
        if let f = defaults.string(forKey: "ndFuente"), fuentes.contains(f) { a.fuente = f }
        let t = defaults.integer(forKey: "ndTamano")
        if tamanos.contains(t) { a.tamano = t }
        if let m = defaults.string(forKey: "ndTema"), temas.contains(m) { a.tema = m }
        a.temaTerminal = defaults.string(forKey: TemasTerminal.clave) ?? ""
        return a
    }

    func guardar(_ defaults: UserDefaults = .standard) {
        defaults.set(fuente, forKey: "ndFuente")
        defaults.set(tamano, forKey: "ndTamano")
        defaults.set(tema, forKey: "ndTema")
        defaults.set(temaTerminal, forKey: TemasTerminal.clave)
        defaults.synchronize()   // (en Windows no se vuelca solo: sin esto se pierde si la app se cierra a la fuerza)
    }
}

/// Panel de Ajustes: sustituye al terminal en el area principal, como el editor de sesion.
final class PanelAjustes {
    let view = ScrollViewer()
    var onSave: ((AjustesTerminal) -> Void)?
    var onCancel: (() -> Void)?
    /// «Buscar actualizaciones»: la ventana hace la consulta y avisa con `setUpdateStatus`.
    var onCheckUpdates: (() -> Void)?
    private let updateText = TextBlock()

    private let fuente = ComboBox()
    private let tamano = Slider()
    private let tamanoTexto = TextBlock()
    private let tema = ComboBox()
    private let temaTerminal = ComboBox()
    /// Los ids de los temas del combo (el primero, «», es «Predeterminado»).
    private var temaIds: [String] = [""]
    private let saveButton = Button()
    private let cancelButton = Button()
    private var loading = false

    init() {
        let form = StackPanel()
        form.orientation = .vertical
        form.spacing = 8
        form.maxWidth = 460
        form.horizontalAlignment = .left
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let title = TextBlock()
        title.text = L("Ajustes")
        title.fontSize = 20
        form.children.append(title)

        for name in AjustesTerminal.fuentes { fuente.items.append(name) }
        for name in AjustesTerminal.temas { tema.items.append(L(nombre: name)) }
        fuente.minWidth = 200
        tema.minWidth = 200
        temaTerminal.minWidth = 260
        tamano.minimum = Double(AjustesTerminal.tamanos.lowerBound)
        tamano.maximum = Double(AjustesTerminal.tamanos.upperBound)
        tamano.minWidth = 200
        tamano.valueChanged.addHandler { [weak self] _, _ in self?.showSize() }

        let sizeRow = StackPanel()
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 12
        sizeRow.children.append(tamano)
        sizeRow.children.append(tamanoTexto)

        let fields: [(String, FrameworkElement, String)] = [
            (L("Fuente del terminal"), fuente, "Ajustes_Fuente"),
            (L("Tama\u{00F1}o de fuente"), sizeRow, ""),
            (L("Tema"), tema, "Ajustes_Tema"),
            (L("Colores del terminal"), temaTerminal, "Ajustes_TemaTerminal"),
        ]
        for (label, control, id) in fields {
            let caption = TextBlock()
            caption.text = label
            caption.fontSize = 12
            caption.opacity = 0.7
            if !id.isEmpty { AutomationProperties.setAutomationId(control, id) }
            let box = StackPanel()
            box.orientation = .vertical
            box.spacing = 2
            box.children.append(caption)
            box.children.append(control)
            form.children.append(box)
        }
        AutomationProperties.setAutomationId(tamano, "Ajustes_Tamano")

        saveButton.content = L("Guardar")
        saveButton.click.addHandler { [weak self] _, _ in self?.commit() }
        cancelButton.content = L("Cancelar")
        cancelButton.click.addHandler { [weak self] _, _ in self?.onCancel?() }
        AutomationProperties.setAutomationId(saveButton, "Ajustes_Guardar")
        AutomationProperties.setAutomationId(cancelButton, "Ajustes_Cancelar")
        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.margin = Thickness(left: 0, top: 8, right: 0, bottom: 0)
        buttons.children.append(saveButton)
        buttons.children.append(cancelButton)
        form.children.append(buttons)

        let updates = StackPanel()
        updates.orientation = .vertical
        updates.spacing = 4
        updates.margin = Thickness(left: 0, top: 16, right: 0, bottom: 0)
        let checkButton = Button()
        checkButton.content = L("Buscar actualizaciones")
        checkButton.click.addHandler { [weak self] _, _ in self?.onCheckUpdates?() }
        AutomationProperties.setAutomationId(checkButton, "Ajustes_Actualizaciones")
        AutomationProperties.setAutomationId(updateText, "Ajustes_EstadoActualizacion")
        updateText.textWrapping = .wrap
        updates.children.append(checkButton)
        updates.children.append(updateText)
        form.children.append(updates)

        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    func show(_ settings: AjustesTerminal) {
        loading = true
        fuente.selectedIndex = Int32(AjustesTerminal.fuentes.firstIndex(of: settings.fuente) ?? 0)
        tema.selectedIndex = Int32(AjustesTerminal.temas.firstIndex(of: settings.tema) ?? 0)
        tamano.value = Double(settings.tamano)
        // (los temas se leen al abrir el panel: por si se ha importado alguno)
        let themes = TemasTerminal.disponibles()
        temaTerminal.items.clear()
        temaTerminal.items.append(L("(Predeterminado)"))
        temaIds = [""]
        for theme in themes {
            temaTerminal.items.append(theme.name)
            temaIds.append(theme.id)
        }
        temaTerminal.selectedIndex = Int32(temaIds.firstIndex(of: settings.temaTerminal) ?? 0)
        loading = false
        showSize()
    }

    func setUpdateStatus(_ text: String) { updateText.text = text }

    private var currentSize: Int {
        min(AjustesTerminal.tamanos.upperBound, max(AjustesTerminal.tamanos.lowerBound, Int(tamano.value.rounded())))
    }

    private func showSize() {
        tamanoTexto.text = "\(currentSize) pt"
    }

    private func commit() {
        var settings = AjustesTerminal()
        let f = Int(fuente.selectedIndex)
        if AjustesTerminal.fuentes.indices.contains(f) { settings.fuente = AjustesTerminal.fuentes[f] }
        let t = Int(tema.selectedIndex)
        if AjustesTerminal.temas.indices.contains(t) { settings.tema = AjustesTerminal.temas[t] }
        settings.tamano = currentSize
        let c = Int(temaTerminal.selectedIndex)
        if temaIds.indices.contains(c) { settings.temaTerminal = temaIds[c] }
        onSave?(settings)
    }
}
