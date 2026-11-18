import Foundation
import NetDeckCore
import WinUI

/// Panel de tuneles SSH en el area principal: lista con estado, iniciar/detener, editar, borrar y un formulario.
/// Los datos son los de `TunnelLibrary` (tuneles.json); en la demo, solo en memoria. Arrancar y parar los ssh lo hace
/// la ventana con `TunnelManager`: el panel avisa por `onStart` y `onStop`.
final class PanelTuneles {
    let view = ScrollViewer()
    var library = TunnelLibrary()
    /// false en la demo: no se lee ni se escribe tuneles.json.
    var persist = true
    var sessionNames: () -> [String] = { [] }
    var stateOf: (Tunnel.ID) -> TunnelState = { _ in .stopped }
    var onStart: ((Tunnel) -> Void)?
    var onStop: ((Tunnel.ID) -> Void)?
    var onForget: ((Tunnel.ID) -> Void)?
    var onClose: (() -> Void)?

    private let list = StackPanel()
    private let form = StackPanel()
    private let statusText = TextBlock()
    private let formTitle = TextBlock()
    private let name = TextBox()
    private let session = ComboBox()
    private let server = TextBox()
    private let kind = ComboBox()
    private let listenPort = TextBox()
    private let targetHost = TextBox()
    private let targetPort = TextBox()
    private let exposed = ToggleSwitch()
    private var sessionChoices: [String] = []
    private var editing: Tunnel?
    private var loaded = false

    init() {
        let root = StackPanel()
        root.orientation = .vertical
        root.spacing = 8
        root.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let title = TextBlock()
        title.text = L("T\u{00FA}neles SSH")
        title.fontSize = 20
        let add = Button()
        add.content = "+ " + L("Nuevo t\u{00FA}nel")
        add.click.addHandler { [weak self] _, _ in self?.edit(nil) }
        let close = Button()
        close.content = L("Cerrar")
        close.click.addHandler { [weak self] _, _ in self?.onClose?() }
        AutomationProperties.setAutomationId(add, "Tuneles_Nuevo")
        AutomationProperties.setAutomationId(close, "Tuneles_Cerrar")
        let header = StackPanel()
        header.orientation = .horizontal
        header.spacing = 8
        header.children.append(add)
        header.children.append(close)

        buildForm()
        statusText.textWrapping = .wrap
        AutomationProperties.setAutomationId(statusText, "Tuneles_Estado")
        for item in [title as FrameworkElement, header, list, form, statusText] { root.children.append(item) }
        view.content = root
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    private func buildForm() {
        form.orientation = .vertical
        form.spacing = 6
        form.maxWidth = 460
        form.horizontalAlignment = .left
        form.margin = Thickness(left: 0, top: 12, right: 0, bottom: 0)
        form.visibility = .collapsed
        formTitle.fontSize = 16
        form.children.append(formTitle)

        for kindOption in Tunnel.Kind.allCases { kind.items.append(Self.label(kindOption)) }
        kind.minWidth = 200
        session.minWidth = 200
        exposed.onContent = L("S\u{00ED}")
        exposed.offContent = L("No")
        let fields: [(String, FrameworkElement, String)] = [
            (L("Nombre"), name, "Tuneles_Nombre"),
            (L("Sesi\u{00F3}n"), session, "Tuneles_Sesion"),
            (L("Equipo (usuario@equipo:puerto, si no hay sesi\u{00F3}n)"), server, "Tuneles_Equipo"),
            (L("Tipo"), kind, "Tuneles_Tipo"),
            (L("Puerto de escucha"), listenPort, "Tuneles_PuertoEscucha"),
            (L("Destino (equipo)"), targetHost, "Tuneles_Destino"),
            (L("Puerto de destino"), targetPort, "Tuneles_PuertoDestino"),
            (L("Escuchar fuera de este equipo"), exposed, "Tuneles_Abierto"),
        ]
        for (label, control, id) in fields {
            let caption = TextBlock()
            caption.text = label
            caption.fontSize = 12
            caption.opacity = 0.7
            AutomationProperties.setAutomationId(control, id)
            let box = StackPanel()
            box.orientation = .vertical
            box.spacing = 2
            box.children.append(caption)
            box.children.append(control)
            form.children.append(box)
        }
        let save = Button()
        save.content = L("Guardar")
        save.click.addHandler { [weak self] _, _ in self?.commit() }
        let cancel = Button()
        cancel.content = L("Cancelar")
        cancel.click.addHandler { [weak self] _, _ in self?.form.visibility = .collapsed }
        AutomationProperties.setAutomationId(save, "Tuneles_Guardar")
        AutomationProperties.setAutomationId(cancel, "Tuneles_Cancelar")
        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.children.append(save)
        buttons.children.append(cancel)
        form.children.append(buttons)
    }

    // MARK: - lista

    /// Al abrir el panel: lee tuneles.json (una vez) y pinta la lista.
    func show() {
        if persist, !loaded {
            let result = TunnelLibrary.load()
            library = result.library
            if let error = result.error { setStatus(error) }
            loaded = true
        }
        form.visibility = .collapsed
        refresh()
    }

    func refresh() {
        list.children.clear()
        if library.tunnels.isEmpty {
            let empty = TextBlock()
            empty.text = L("No hay t\u{00FA}neles")
            empty.opacity = 0.6
            list.children.append(empty)
        }
        for tunnel in library.tunnels { list.children.append(row(for: tunnel)) }
    }

    func setStatus(_ text: String) { statusText.text = text }

    private func row(for tunnel: Tunnel) -> FrameworkElement {
        let state = stateOf(tunnel.id)
        let grid = Grid()
        let colInfo = ColumnDefinition()
        colInfo.width = GridLength(value: 1, gridUnitType: .star)
        let colButtons = ColumnDefinition()
        colButtons.width = GridLength(value: 1, gridUnitType: .auto)
        grid.columnDefinitions.append(colInfo)
        grid.columnDefinitions.append(colButtons)

        let info = StackPanel()
        info.orientation = .vertical
        let title = TextBlock()
        title.text = "\(tunnel.name) \u{00B7} \(Self.label(tunnel.kind)) \u{00B7} \(Self.stateText(state))"
        let spec = TextBlock()
        spec.text = "\(tunnel.kind.flag) \(tunnel.forwardSpec) \u{00B7} " + (tunnel.session.isEmpty ? tunnel.server : tunnel.session)
        spec.fontSize = 11
        spec.opacity = 0.7
        spec.textWrapping = .wrap
        info.children.append(title)
        info.children.append(spec)
        Grid.setColumn(info, Int32(0))

        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 4
        let toggle = Button()
        toggle.content = state.isRunning ? "\u{25A0} " + L("Detener") : "\u{25B6} " + L("Iniciar")
        toggle.click.addHandler { [weak self] _, _ in
            if state.isRunning { self?.onStop?(tunnel.id) } else { self?.onStart?(tunnel) }
        }
        let editButton = Button()
        editButton.content = "\u{270E}"
        editButton.click.addHandler { [weak self] _, _ in self?.edit(tunnel) }
        let delete = Button()
        delete.content = "\u{2715}"
        delete.click.addHandler { [weak self] _, _ in self?.remove(tunnel) }
        AutomationProperties.setAutomationId(toggle, "Tunel_Iniciar_\(tunnel.name)")
        AutomationProperties.setAutomationId(editButton, "Tunel_Editar_\(tunnel.name)")
        AutomationProperties.setAutomationId(delete, "Tunel_Borrar_\(tunnel.name)")
        for button in [toggle, editButton, delete] { buttons.children.append(button) }
        Grid.setColumn(buttons, Int32(1))

        grid.children.append(info)
        grid.children.append(buttons)
        grid.margin = Thickness(left: 0, top: 4, right: 0, bottom: 4)
        return grid
    }

    // MARK: - formulario

    private func edit(_ tunnel: Tunnel?) {
        editing = tunnel
        let t = tunnel ?? Tunnel(name: "")
        formTitle.text = tunnel == nil ? L("Nuevo t\u{00FA}nel") : L("Editar t\u{00FA}nel")
        sessionChoices = sessionNames()
        session.items.clear()
        session.items.append(L("(ninguna)"))
        for sessionName in sessionChoices { session.items.append(sessionName) }
        session.selectedIndex = Int32((sessionChoices.firstIndex(of: t.session) ?? -1) + 1)
        name.text = t.name
        server.text = t.server
        kind.selectedIndex = Int32(Tunnel.Kind.allCases.firstIndex(of: t.kind) ?? 0)
        listenPort.text = String(t.listenPort)
        targetHost.text = t.targetHost
        targetPort.text = String(t.targetPort)
        exposed.isOn = t.exposed
        setStatus("")
        form.visibility = .visible
    }

    private func commit() {
        guard let listen = Int(listenPort.text.trimmingCharacters(in: .whitespaces)),
              let target = Int(targetPort.text.trimmingCharacters(in: .whitespaces)) else {
            setStatus(L("Los puertos tienen que ser n\u{00FA}meros"))
            return
        }
        var tunnel = editing ?? Tunnel(name: "")
        let index = Int(session.selectedIndex)
        tunnel.session = index > 0 && index <= sessionChoices.count ? sessionChoices[index - 1] : ""
        tunnel.server = server.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = Int(kind.selectedIndex)
        if Tunnel.Kind.allCases.indices.contains(k) { tunnel.kind = Tunnel.Kind.allCases[k] }
        tunnel.listenPort = listen
        tunnel.targetPort = target
        tunnel.targetHost = targetHost.text.trimmingCharacters(in: .whitespacesAndNewlines)
        tunnel.exposed = exposed.isOn
        let typed = name.text.trimmingCharacters(in: .whitespacesAndNewlines)
        tunnel.name = library.uniqueName(typed.isEmpty ? L("T\u{00FA}nel") : typed, except: tunnel.id)
        if let problem = tunnel.problem {
            setStatus(problem)
            return
        }
        var updated = library
        if let i = updated.tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            updated.tunnels[i] = tunnel
        } else {
            updated.tunnels.append(tunnel)
        }
        guard store(updated) else { return }
        form.visibility = .collapsed
        refresh()
        setStatus(L("T\u{00FA}nel \u{00AB}\(tunnel.name)\u{00BB} guardado"))
    }

    private func remove(_ tunnel: Tunnel) {
        var updated = library
        updated.tunnels.removeAll { $0.id == tunnel.id }
        onStop?(tunnel.id)
        guard store(updated) else { return }
        onForget?(tunnel.id)
        form.visibility = .collapsed
        refresh()
    }

    /// Deja `new` como la biblioteca (y, fuera de la demo, en tuneles.json). false si no se pudo guardar.
    private func store(_ new: TunnelLibrary) -> Bool {
        if persist {
            do { try new.save() } catch {
                setStatus(L("No se pueden guardar los t\u{00FA}neles: \(error.localizedDescription)"))
                return false
            }
        }
        library = new
        return true
    }

    // MARK: - textos

    static func label(_ kind: Tunnel.Kind) -> String {
        switch kind {
        case .local: L("Local")
        case .remote: L("Remoto")
        case .dynamic: "SOCKS"
        }
    }

    static func stateText(_ state: TunnelState) -> String {
        switch state {
        case .stopped: L("Parado")
        case .starting: L("Iniciando\u{2026}")
        case .active: L("Activo")
        case .failed(let why): L("Error: \(why)")
        }
    }
}
