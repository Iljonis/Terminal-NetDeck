import Foundation
import NetDeckCore
import struct UWP.Color
import struct WindowsFoundation.Size
import WinSDK
import WinUI

@main
final class NetDeckWindows: SwiftApplication {
    private var window: Window?
    private let tabs = StackPanel()
    private let destination = TextBox()
    private let terminalGrid = Grid()
    private let columnas = [ColumnDefinition(), ColumnDefinition()]
    private let filas = [RowDefinition(), RowDefinition()]
    private let vistas = [VistaTerminal(id: "PantallaTerminal"), VistaTerminal(id: "PantallaTerminal2")]
    private var terminalesVisibles: [PestanaTerminal?] = [nil, nil]
    private var panelActivo = 0
    private var divisionGuardadaApilada: Bool?
    private let espacios = PanelEspacios()
    private let buscarTerminal = PanelBuscarTerminal()
    private weak var pestañaBuscada: PestanaTerminal?
    private var espaciosDemo = WorkspaceLibrary()
    private var panelDividido: Bool { terminalesVisibles[1] != nil }
    private let dividir = Button()
    private let status = TextBlock()
    private let closeButton = Button()
    private var terminals: [PestanaTerminal] = []
    private weak var pestañaArrastrada: PestanaTerminal?
    private struct VentanaPestana {
        let window: Window
        let vista: VistaTerminal
        let session: PestanaTerminal
    }
    private var ventanasPestana: [ObjectIdentifier: VentanaPestana] = [:]
    private weak var selected: PestanaTerminal?
    private var sessions: SessionManager!
    private let sidebar = StackPanel()
    private let editor = PanelEditorSesion()
    private let ajustes = PanelAjustes()
    private let reglas = PanelTexto(idPrefix: "Resaltado")
    private var resaltadoDemo: String?
    private var highlightConfig: HighlightConfig?
    private var screenLook: ScreenLook?
    private let paletaBase = PaletaTerminal(tema: Theme.builtIn)
    private let pegado = PanelTexto(idPrefix: "PegarSeguro")
    private let multi = PanelTexto(idPrefix: "MultiExec")
    private let explorador = ExploradorSFTP()
    private let accesoFTP = PanelAccesoFTP()
    private let botones = PanelBotones()
    private let confirmarBoton = PanelTexto(idPrefix: "Botones_Confirmar")
    private var archivoBotones = ButtonFile()
    private let llavero = PanelLlavero()
    private var favoritas: Set<String> = []
    private var recientes: [String] = []
    private var favoritasURL: URL { AppPaths.netdeck.appendingPathComponent("favoritas") }
    private var recientesURL: URL { AppPaths.netdeck.appendingPathComponent("recientes") }
    private let macros = PanelMacros()
    private var grabando: (tab: PestanaTerminal, recorder: MacroRecorder, io: EntradaMacro)?
    private let pararGrabacion = Button()
    private let macroConfirm = PanelTexto(idPrefix: "MacroConfirmar")
    private var macrosDemo = MacroLibrary()
    private var automatizacionActiva: (tab: PestanaTerminal, abort: AbortSwitch)?
    private let pararAutomatizacion = Button()
    private let tuneles = PanelTuneles()
    private let asistente = AsistenteInicio()
    private let actualizacion = PanelTexto(idPrefix: "Actualizacion")
    private var pendingUpdate: UpdateInfo?
    private var startupUpdate: UpdateInfo?
    private var manualUpdateRequested = false
    private var tunnelManager: TunnelManager!
    private var settings = AjustesTerminal.cargar()
    private var rootView: Grid?
    /// Ancho medido de la fuente monoespaciada para las columnas de ConPTY.
    private var anchoCelda = 8.25
    /// Colores del tema elegido para el terminal (nil: los del sistema, texto liso).
    private var paleta: PaletaTerminal?
    private var pinceles: [RGB: SolidColorBrush] = [:]
    private var pendingPaste: (tab: PestanaTerminal, text: String, dangerous: Bool)?
    /// Sesiones editables en memoria: en modo demo es la unica copia (no se escribe a disco).
    private var library = SessionFile()
    private let isDemo = ProcessInfo.processInfo.environment["NETDECK_DESKTOP_DEMO"] == "1"

    override func onLaunched(_ args: LaunchActivatedEventArgs) {
        let window = Window()
        self.window = window
        window.title = "Terminal NetDeck"

        MainActor.assumeIsolated {
            sessions = SessionManager()
            tunnelManager = TunnelManager()
            tunnelManager.onChange = { [weak self] id, state in self?.tunnelChanged(id, state) }
            if isDemo {
                sessions.loadSamples()
                library.sessions = sessions.profiles.map(NetDeckWindows.editable(from:))
            } else if FileManager.default.fileExists(atPath: SessionFile.defaultURL.path) {
                sessions.load(from: SessionFile.defaultURL)
            } else {
                sessions.load()
            }
        }

        // Rejilla raiz: barra lateral | area principal
        let root = Grid()
        let colLateral = ColumnDefinition()
        colLateral.width = GridLength(value: 200, gridUnitType: .pixel)
        let colPrincipal = ColumnDefinition()
        colPrincipal.width = GridLength(value: 1, gridUnitType: .star)
        root.columnDefinitions.append(colLateral)
        root.columnDefinitions.append(colPrincipal)

        // Barra lateral
        sidebar.orientation = .vertical
        sidebar.spacing = 2
        sidebar.margin = Thickness(left: 0, top: 8, right: 0, bottom: 8)
        buildSidebar()
        let sideScroll = ScrollViewer()
        sideScroll.content = sidebar
        sideScroll.verticalScrollBarVisibility = .auto
        sideScroll.horizontalScrollBarVisibility = .disabled
        let addButton = Button()
        addButton.content = "+ " + L("Nueva sesi\u{00F3}n")
        addButton.horizontalAlignment = .stretch
        addButton.margin = Thickness(left: 4, top: 4, right: 4, bottom: 8)
        addButton.click.addHandler { [weak self] _, _ in self?.newSession() }
        AutomationProperties.setAutomationId(addButton, "NuevaSesion")
        let sideColumn = Grid()
        let rowList = RowDefinition()
        rowList.height = GridLength(value: 1, gridUnitType: .star)
        let rowAdd = RowDefinition()
        rowAdd.height = GridLength(value: 1, gridUnitType: .auto)
        sideColumn.rowDefinitions.append(rowList)
        sideColumn.rowDefinitions.append(rowAdd)
        Grid.setRow(sideScroll, Int32(0))
        Grid.setRow(addButton, Int32(1))
        sideColumn.children.append(sideScroll)
        sideColumn.children.append(addButton)
        Grid.setColumn(sideColumn, Int32(0))
        root.children.append(sideColumn)

        // Area principal (barra de herramientas + pestanas + terminal + estado)
        let layout = Grid()
        layout.margin = Thickness(left: 16, top: 12, right: 16, bottom: 12)
        Grid.setColumn(layout, Int32(1))

        let toolbar = StackPanel()
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        let local = Button()
        local.content = L("Terminal local")
        local.click.addHandler { [weak self] _, _ in self?.open(.local()) }
        destination.placeholderText = "SSH \u{00B7} admin@core-01"
        destination.minWidth = 220
        destination.keyDown.addHandler { [weak self] _, args in
            guard let args, args.key.rawValue == 13 else { return }
            args.handled = true
            self?.connect()
        }
        let connect = Button()
        connect.content = L("Conectar")
        connect.click.addHandler { [weak self] _, _ in self?.connect() }
        closeButton.content = L("Cerrar pesta\u{00F1}a")
        closeButton.click.addHandler { [weak self] _, _ in self?.closeSelected() }
        let paste = Button()
        paste.content = L("Pegar")
        paste.click.addHandler { [weak self] _, _ in self?.safePaste() }
        let multiButton = Button()
        multiButton.content = L("MultiExec")
        multiButton.click.addHandler { [weak self] _, _ in self?.multiExec() }
        let tunnelButton = Button()
        tunnelButton.content = L("T\u{00FA}neles")
        tunnelButton.click.addHandler { [weak self] _, _ in self?.showTuneles() }
        let commandButtons = Button()
        commandButtons.content = L("Botones")
        commandButtons.click.addHandler { [weak self] _, _ in self?.showCommandButtons() }
        let macroButton = Button()
        macroButton.content = L("Macros")
        macroButton.click.addHandler { [weak self] _, _ in self?.showMacros() }
        pararAutomatizacion.content = L("Detener envío")
        pararAutomatizacion.visibility = .collapsed
        pararAutomatizacion.click.addHandler { [weak self] _, _ in self?.automatizacionActiva?.abort.trip() }
        pararGrabacion.content = L("Parar la grabación")
        pararGrabacion.visibility = .collapsed
        pararGrabacion.click.addHandler { [weak self] _, _ in self?.finishRecording() }
        dividir.content = L("Dividir la pantalla")
        dividir.click.addHandler { [weak self] _, _ in self?.toggleSplit() }
        let workspaceButton = Button()
        workspaceButton.content = L("Espacios")
        workspaceButton.click.addHandler { [weak self] _, _ in self?.showWorkspaces() }
        let searchButton = Button()
        searchButton.content = L("Buscar")
        searchButton.click.addHandler { [weak self] _, _ in self?.showTerminalSearch() }
        let gear = Button()
        gear.content = "\u{2699}"
        gear.click.addHandler { [weak self] _, _ in self?.showAjustes() }
        for (control, id) in [(local as Control, "NuevaLocal"), (destination, "DestinoSSH"),
                              (connect, "ConectarSSH"), (closeButton, "CerrarPestana"),
                              (paste, "PegarSeguro"), (multiButton, "MultiExec"), (tunnelButton, "Tuneles"),
                              (macroButton, "Macros"), (pararAutomatizacion, "Macros_Parar"), (pararGrabacion, "Macros_PararGrabacion"), (dividir, "DividirTerminal"),
                              (workspaceButton, "Espacios"), (searchButton, "BuscarTerminal"), (commandButtons, "Botones"), (gear, "Ajustes")] {
            AutomationProperties.setAutomationId(control, id)
            toolbar.children.append(control)
        }

        let toolbarScroll = ScrollViewer()
        toolbarScroll.horizontalScrollBarVisibility = .auto
        toolbarScroll.verticalScrollBarVisibility = .disabled
        toolbarScroll.content = toolbar

        tabs.orientation = .horizontal
        tabs.spacing = 6
        let tabStrip = ScrollViewer()
        tabStrip.horizontalScrollBarVisibility = .auto
        tabStrip.verticalScrollBarVisibility = .disabled
        tabStrip.content = tabs

        AutomationProperties.setAutomationId(status, "EstadoTerminal")
        for columna in columnas { terminalGrid.columnDefinitions.append(columna) }
        for fila in filas { terminalGrid.rowDefinitions.append(fila) }
        for (index, vista) in vistas.enumerated() {
            let surface = vista.surface
            terminalGrid.children.append(surface)
            surface.pointerPressed.addHandler { [weak self] _, _ in
                guard let self, let tab = self.terminalesVisibles[index] else { return }
                if index == self.panelActivo { self.focusTerminal() } else { self.select(tab) }
            }
            surface.gotFocus.addHandler { [weak self] _, _ in
                guard let self, index != self.panelActivo, let tab = self.terminalesVisibles[index] else { return }
                self.select(tab, focus: false)
            }
            surface.sizeChanged.addHandler { [weak self] _, _ in self?.resize(index) }
            surface.keyDown.addHandler { [weak self] _, args in
                guard let self, let args, let tab = self.terminalesVisibles[index], !tab.closed,
                      let bytes = self.keySequence(args.key.rawValue, tab: tab) else { return }
                args.handled = true
                if self.automatizacionActiva?.tab === tab {
                    guard AbortKey.isAbort(bytes.utf8) else { return }
                    self.automatizacionActiva?.abort.trip()
                    if bytes == "\u{1b}" { return }
                }
                if self.dispatchButtonHotkey(bytes, tab: tab) { return }
                self.recordKeys(bytes, tab: tab)
                tab.write(bytes)
            }
            surface.characterReceived.addHandler { [weak self] _, args in
                guard let self, let args, let tab = self.terminalesVisibles[index], !tab.closed else { return }
                let text = String(args.character)
                guard text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
                args.handled = true
                if self.automatizacionActiva?.tab !== tab {
                    self.recordKeys(text, tab: tab)
                    tab.write(text)
                }
            }
        }
        updateSplitLayout()

        for (index, view) in [toolbarScroll as FrameworkElement, tabStrip, terminalGrid, status].enumerated() {
            let row = RowDefinition()
            row.height = GridLength(value: 1, gridUnitType: index == 2 ? .star : .auto)
            layout.rowDefinitions.append(row)
            Grid.setRow(view, Int32(index))
            layout.children.append(view)
        }

        Grid.setRow(editor.view, Int32(2))
        layout.children.append(editor.view)
        editor.onSave = { [weak self] session, original in self?.saveSession(session, replacing: original) ?? false }
        editor.onCancel = { [weak self] in self?.hideEditor() }
        Grid.setRow(ajustes.view, Int32(2))
        layout.children.append(ajustes.view)
        Grid.setRow(accesoFTP.view, Int32(2))
        layout.children.append(accesoFTP.view)
        accesoFTP.onCancel = { [weak self] in self?.showPanel(nil) }
        accesoFTP.onConnect = { [weak self] route, user, password in
            guard let self else { return }
            self.explorador.connectFTP(route: route, user: user, password: password)
            self.showPanel(self.explorador.view)
        }
        Grid.setRow(explorador.view, Int32(2))
        layout.children.append(explorador.view)
        explorador.onClose = { [weak self] in self?.showPanel(nil) }
        explorador.enqueue = { [weak self] action in
            _ = try? self?.window?.dispatcherQueue?.tryEnqueue { action() }
        }
        Grid.setRow(tuneles.view, Int32(2))
        layout.children.append(tuneles.view)
        tuneles.persist = !isDemo
        tuneles.onClose = { [weak self] in self?.showPanel(nil) }
        tuneles.sessionNames = { [weak self] in
            guard let self else { return [] }
            return MainActor.assumeIsolated {
                self.sessions.profiles.filter { $0.transport == .ssh || $0.transport == .sftp }.map(\.name)
            }
        }
        tuneles.stateOf = { [weak self] id in
            guard let self else { return .stopped }
            return MainActor.assumeIsolated { self.tunnelManager.state(id) }
        }
        tuneles.onStart = { [weak self] tunnel in self?.startTunnel(tunnel) }
        tuneles.onStop = { [weak self] id in self?.stopTunnel(id) }
        tuneles.onForget = { [weak self] id in
            Task { [weak self] in await self?.tunnelManager.forget(id) }
        }
        Grid.setRow(asistente.view, Int32(2))
        layout.children.append(asistente.view)
        for panel in [pegado, multi, actualizacion, macroConfirm, confirmarBoton, reglas] {
            Grid.setRow(panel.view, Int32(2))
            layout.children.append(panel.view)
            panel.onCancel = { [weak self] in self?.showPanel(nil) }
        }
        pegado.onConfirm = { [weak self] _ in self?.confirmPaste() }
        multi.onConfirm = { [weak self] text in self?.confirmMultiExec(text) }
        actualizacion.onConfirm = { [weak self] _ in self?.installUpdate() }
        for view in [espacios.view, buscarTerminal.view, botones.view] {
            Grid.setRow(view, Int32(2))
            layout.children.append(view)
        }
        botones.onUse = { [weak self] in self?.useCommandButton($0) }
        botones.onSave = { [weak self] button, replacing in self?.saveCommandButton(button, replacing: replacing) }
        botones.onClose = { [weak self] in self?.showPanel(nil) }
        confirmarBoton.onCancel = { [weak self] in self?.showCommandButtons() }
        espacios.onOpen = { [weak self] in self?.restoreWorkspace($0) }
        espacios.onSave = { [weak self] in self?.saveWorkspace($0) }
        espacios.onClose = { [weak self] in self?.showPanel(nil) }
        buscarTerminal.onSearch = { [weak self] consulta in
            guard let self, let tab = self.pestañaBuscada else { return }
            let coincidencias = tab.buscarHistorial(consulta)
            self.buscarTerminal.show(lines: coincidencias.lines, total: coincidencias.total)
        }
        buscarTerminal.onClose = { [weak self] in self?.showPanel(nil) }
        Grid.setRow(llavero.view, Int32(2))
        layout.children.append(llavero.view)
        llavero.onClose = { [weak self] in self?.showPanel(nil) }
        llavero.getArchivoBotones = { [weak self] in self?.archivoBotones ?? ButtonFile() }
        Grid.setRow(macros.view, Int32(2))
        layout.children.append(macros.view)
        macros.onClose = { [weak self] in self?.showPanel(nil) }
        macros.onSave = { [weak self] in self?.saveMacro($0) }
        macros.onPlay = { [weak self] in self?.playMacro($0) }
        macros.onRecord = { [weak self] in self?.startRecording() }
        macros.onDelete = { [weak self] in self?.confirmMacroDeletion($0) }
        macroConfirm.onCancel = { [weak self] in self?.showMacros() }
        reglas.onConfirm = { [weak self] in self?.saveHighlightRules($0) }
        reglas.onCancel = { [weak self] in self?.showAjustes() }
        ajustes.onHighlight = { [weak self] in self?.showHighlightRules() }
        ajustes.onCheckUpdates = { [weak self] in self?.checkUpdates() }
        ajustes.onManagePasswords = { [weak self] in self?.showLlavero() }
        ajustes.onSave = { [weak self] new in self?.saveAjustes(new) }
        ajustes.onCancel = { [weak self] in self?.hideAjustes() }

        root.children.append(layout)
        // Atajos: en la fase de tunel (previewKeyDown), antes de que el terminal reciba la tecla.
        root.previewKeyDown.addHandler { [weak self] _, args in
            guard let self, let args, self.shortcut(args.key.rawValue) else { return }
            args.handled = true
        }
        window.content = root
        rootView = root
        applySettings(settings)
        do {
            try window.activate()
            open(.local())
            // Primera vez: sin sesiones guardadas y sin haber visto el asistente (nunca en la demo).
            // NETDECK_ASISTENTE=1 lo fuerza para probarlo, sin marcarlo como visto.
            let forced = ProcessInfo.processInfo.environment["NETDECK_ASISTENTE"] == "1"
            let firstRun = !isDemo && !UserDefaults.standard.bool(forKey: "ndAsistenteVisto")
                && MainActor.assumeIsolated { sessions.profiles.isEmpty }
            if firstRun || forced { showAsistente(markSeen: !forced) }
            checkUpdatesOnLaunch()
        } catch {
            print(error.localizedDescription)
        }
    }

    override func onShutdown() {
        for detached in ventanasPestana.values { detached.session.close() }
        for session in terminals { session.close() }
        MainActor.assumeIsolated { tunnelManager.stopAll() }
    }

    private func buildSidebar(filter: String = "") {
        favoritas = Set((try? SessionLists.loadFavorites(favoritasURL)) ?? [])
        let recText: String
        if let t = try? SafeFile.read(recientesURL) { recText = t ?? "" } else { recText = "" }
        recientes = SessionLists.recents(recText)

        sidebar.children.clear()

        let buscar = TextBox()
        buscar.placeholderText = L("Buscar sesi\u{00F3}n\u{2026}")
        buscar.margin = Thickness(left: 4, top: 2, right: 4, bottom: 4)
        if !filter.isEmpty { buscar.text = filter }
        buscar.textChanged.addHandler { [weak self] _, _ in
            self?.buildSidebar(filter: buscar.text)
        }
        AutomationProperties.setAutomationId(buscar, "Sidebar_Buscar")
        sidebar.children.append(buscar)

        let grupos = MainActor.assumeIsolated { sessions.groups }
        let todosPerfiles = grupos.flatMap { $0.1 }

        if filter.isEmpty {
            let perfilesRecientes = recientes.compactMap { n in todosPerfiles.first { $0.name == n } }
            if !perfilesRecientes.isEmpty {
                sidebar.children.append(makeSidebarHeader("\u{21BB} " + L("Recientes")))
                for perfil in perfilesRecientes { sidebar.children.append(makeSidebarRow(perfil)) }
            }
            let perfilesFavoritas = todosPerfiles.filter { favoritas.contains($0.name) }
            if !perfilesFavoritas.isEmpty {
                sidebar.children.append(makeSidebarHeader("\u{2605} " + L("Favoritas")))
                for perfil in perfilesFavoritas { sidebar.children.append(makeSidebarRow(perfil)) }
            }
        }

        for (nombreGrupo, perfiles) in grupos {
            let filtrados = filter.isEmpty ? perfiles : perfiles.filter {
                $0.name.localizedCaseInsensitiveContains(filter)
            }
            guard !filtrados.isEmpty else { continue }
            sidebar.children.append(makeSidebarHeader(nombreGrupo.uppercased()))
            for perfil in filtrados { sidebar.children.append(makeSidebarRow(perfil)) }
        }
    }

    private func makeSidebarHeader(_ text: String) -> TextBlock {
        let header = TextBlock()
        header.text = text
        header.fontSize = 10
        header.margin = Thickness(left: 8, top: 10, right: 8, bottom: 2)
        header.opacity = 0.6
        return header
    }

    private func makeSidebarRow(_ perfil: SessionProfile) -> Grid {
        let fila = Grid()
        let colNombre = ColumnDefinition()
        colNombre.width = GridLength(value: 1, gridUnitType: .star)
        let colFav = ColumnDefinition()
        colFav.width = GridLength(value: 1, gridUnitType: .auto)
        let colEditar = ColumnDefinition()
        colEditar.width = GridLength(value: 1, gridUnitType: .auto)
        let colSFTP = ColumnDefinition()
        colSFTP.width = GridLength(value: 1, gridUnitType: .auto)
        fila.columnDefinitions.append(colNombre)
        fila.columnDefinitions.append(colFav)
        fila.columnDefinitions.append(colEditar)
        fila.columnDefinitions.append(colSFTP)

        let icono: String
        switch perfil.transport {
        case .ssh:    icono = "SSH"
        case .telnet: icono = "Tel"
        case .sftp:   icono = "SFTP"
        case .ftp:    icono = "FTP"
        case .serial: icono = "COM"
        case .local:  icono = "Loc"
        }
        let etiqueta = StackPanel()
        etiqueta.orientation = .horizontal
        etiqueta.spacing = 6
        let tipo = TextBlock()
        tipo.text = icono
        tipo.fontSize = 9
        tipo.opacity = 0.5
        tipo.minWidth = 24
        let nombre = TextBlock()
        nombre.text = perfil.name
        etiqueta.children.append(tipo)
        etiqueta.children.append(nombre)
        let btn = Button()
        btn.content = etiqueta
        btn.horizontalAlignment = .stretch
        btn.margin = Thickness(left: 4, top: 1, right: 4, bottom: 1)
        AutomationProperties.setAutomationId(btn, "Sesion_\(perfil.name)")
        AutomationProperties.setName(btn, perfil.name)
        btn.click.addHandler { [weak self] _, _ in self?.openProfile(perfil) }

        let esFav = favoritas.contains(perfil.name)
        let fav = Button()
        fav.content = esFav ? "\u{2605}" : "\u{2606}"
        fav.margin = Thickness(left: 0, top: 1, right: 2, bottom: 1)
        AutomationProperties.setAutomationId(fav, "Fav_\(perfil.name)")
        AutomationProperties.setName(fav, esFav ? L("Quitar de favoritas") : L("A\u{00F1}adir a favoritas"))
        fav.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            if self.favoritas.contains(perfil.name) {
                self.favoritas.remove(perfil.name)
            } else {
                self.favoritas.insert(perfil.name)
            }
            try? SessionLists.saveFavorites(Array(self.favoritas).sorted(), to: self.favoritasURL)
            self.buildSidebar()
        }

        let editar = Button()
        editar.content = "\u{270E}"
        editar.margin = Thickness(left: 0, top: 1, right: 4, bottom: 1)
        AutomationProperties.setAutomationId(editar, "Editar_\(perfil.name)")
        editar.click.addHandler { [weak self] _, _ in self?.editSession(perfil) }

        Grid.setColumn(btn, Int32(0))
        Grid.setColumn(fav, Int32(1))
        Grid.setColumn(editar, Int32(2))
        fila.children.append(btn)
        fila.children.append(fav)
        fila.children.append(editar)
        if perfil.transport == .ssh || perfil.transport == .sftp {
            let carpeta = Button()
            carpeta.content = "\u{1F4C2}"
            carpeta.margin = Thickness(left: 0, top: 1, right: 4, bottom: 1)
            AutomationProperties.setAutomationId(carpeta, "SFTP_\(perfil.name)")
            carpeta.click.addHandler { [weak self] _, _ in self?.openSFTPProfile(perfil) }
            Grid.setColumn(carpeta, Int32(3))
            fila.children.append(carpeta)
        }
        return fila
    }

    // MARK: - editor de sesion

    private func newSession() {
        var session = EditableSession.new(group: "General", name: "")
        if let group = MainActor.assumeIsolated({ sessions.groups.first?.name }), group != "Sin grupo" {
            session.group = group
        }
        showEditor(session, original: nil)
    }

    private func editSession(_ perfil: SessionProfile) {
        let saved: EditableSession? = isDemo ? library.sessions.first { $0.name == perfil.name }
            : (try? SessionFile(contentsOf: SessionFile.defaultURL))?.sessions.first { $0.name == perfil.name }
        showEditor(saved ?? NetDeckWindows.editable(from: perfil), original: perfil.name)
    }

    private func showEditor(_ session: EditableSession, original: String?) {
        status.text = ""
        editor.show(session, original: original)
        showPanel(editor.view)
        _ = try? window?.dispatcherQueue?.tryEnqueue { [weak self] in self?.editor.focusName() }
    }

    private func hideEditor() { showPanel(nil) }

    /// El area principal muestra el terminal o uno de los paneles (editor, ajustes), nunca varios a la vez.
    private func showPanel(_ panel: ScrollViewer?) {
        terminalGrid.visibility = panel == nil ? .visible : .collapsed
        editor.view.visibility = panel === editor.view ? .visible : .collapsed
        ajustes.view.visibility = panel === ajustes.view ? .visible : .collapsed
        reglas.view.visibility = panel === reglas.view ? .visible : .collapsed
        pegado.view.visibility = panel === pegado.view ? .visible : .collapsed
        if panel !== pegado.view { pendingPaste = nil }
        multi.view.visibility = panel === multi.view ? .visible : .collapsed
        accesoFTP.view.visibility = panel === accesoFTP.view ? .visible : .collapsed
        if panel !== accesoFTP.view { accesoFTP.clear() }
        explorador.view.visibility = panel === explorador.view ? .visible : .collapsed
        tuneles.view.visibility = panel === tuneles.view ? .visible : .collapsed
        asistente.view.visibility = panel === asistente.view ? .visible : .collapsed
        actualizacion.view.visibility = panel === actualizacion.view ? .visible : .collapsed
        botones.view.visibility = panel === botones.view ? .visible : .collapsed
        confirmarBoton.view.visibility = panel === confirmarBoton.view ? .visible : .collapsed
        if panel !== confirmarBoton.view { confirmarBoton.onConfirm = nil }
        espacios.view.visibility = panel === espacios.view ? .visible : .collapsed
        buscarTerminal.view.visibility = panel === buscarTerminal.view ? .visible : .collapsed
        llavero.view.visibility = panel === llavero.view ? .visible : .collapsed
        macros.view.visibility = panel === macros.view ? .visible : .collapsed
        macroConfirm.view.visibility = panel === macroConfirm.view ? .visible : .collapsed
        if panel !== macroConfirm.view { macroConfirm.onConfirm = nil }
        if panel == nil {
            focusTerminal()
            if startupUpdate != nil { onUI { $0.offerStartupUpdateIfIdle() } }
        }
    }

    // MARK: - pegado seguro y MultiExec

    /// Texto del portapapeles (Win32: el WinRT es asincrono y no merece la pena aqui).
    private func pasteboardText() -> String? {
        guard OpenClipboard(nil) else { return nil }
        defer { CloseClipboard() }
        guard let handle = GetClipboardData(UINT(CF_UNICODETEXT)), let pointer = GlobalLock(handle) else { return nil }
        defer { GlobalUnlock(handle) }
        return String(decodingCString: pointer.assumingMemoryBound(to: UInt16.self), as: UTF16.self)
    }

    /// Una línea se pega sin Intro. Las órdenes remotas multilínea esperan al equipo una a una.
    private func safePaste() {
        guard let selected, !selected.closed else {
            status.text = L("No hay ningún terminal abierto")
            return
        }
        guard automatizacionActiva?.tab !== selected else { return }
        guard let text = pasteboardText(), !text.isEmpty else {
            status.text = L("El portapapeles no tiene texto")
            return
        }
        let clean = String(text.unicodeScalars.filter {
            $0 == "\t" || $0 == "\r" || $0 == "\n" || ($0.value >= 32 && !(127...159).contains($0.value))
        }).trimmingCharacters(in: .newlines)
        guard clean.contains(where: \.isNewline) else {
            selected.paste(clean)
            return
        }
        guard clean.utf8.count <= 100_000 else {
            status.text = L("El texto supera el límite de pegado de 100 KB")
            return
        }
        let lines = PasteRules.lines(of: clean)
        guard !lines.isEmpty else { return }
        let dangerous = !selected.route.isLocal && !PasteRules.dangerousLines(in: clean).isEmpty
        status.text = ""
        pendingPaste = (selected, clean, dangerous)
        let hint = dangerous ? L("El texto contiene órdenes peligrosas. Revísalas antes de continuar.")
            : L("\(lines.count) órdenes en \(selected.title)")
        pegado.show(title: L("Pegar varias líneas"), hint: hint,
                    text: clean, editable: false, confirmTitle: dangerous ? L("Enviar órdenes peligrosas") : nil)
        showPanel(pegado.view)
    }

    private func confirmPaste() {
        guard let pending = pendingPaste, selected === pending.tab, !pending.tab.closed,
              automatizacionActiva?.tab !== pending.tab else {
            showPanel(nil)
            return
        }
        let tab = pending.tab
        if tab.route.isLocal {
            showPanel(nil)
            tab.paste(pending.text)
            return
        }
        guard [.ssh, .telnet].contains(tab.route.transport) else { return }
        let text = pending.text
        let player = SafePaster(allowDangerous: pending.dangerous)
        startAutomation(on: tab, title: L("Pegado seguro")) { io, abort in
            let report = await player.paste(text, into: io, abort: abort)
            switch report.outcome {
            case .completed: return L("✓ \(report.sent)/\(report.total) órdenes")
            case .aborted: return L("⎋ parada en \(report.sent)/\(report.total)")
            case .deviceError(let step, let output): return L("✗ error en el paso \(step): \(output)")
            case .pager(let step): return L("✗ paginador en el paso \(step) (falta «terminal length 0»)")
            case .timeout(let step): return L("✗ sin respuesta a tiempo en el paso \(step)")
            case .dangerousNotConfirmed(let step, let command): return L("✗ paso \(step) peligroso sin confirmar: \(command)")
            case .passwordPrompt(let step): return L("🔑 piden contraseña en el paso \(step): paro (no escribo nada ahí)")
            }
        }
    }

    /// Un mismo comando a todas las pestanas SSH y Telnet abiertas.
    private func multiExec() {
        status.text = ""
        multi.show(title: L("MultiExec"),
                   hint: L("El comando se env\u{00ED}a a todas las pesta\u{00F1}as SSH y Telnet abiertas."),
                   text: "", editable: true)
        showPanel(multi.view)
    }

    private func confirmMultiExec(_ text: String) {
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            status.text = L("Escribe un comando")
            return
        }
        let targets = terminals.filter { !$0.closed && $0 !== automatizacionActiva?.tab && !$0.route.isLocal && [.ssh, .telnet].contains($0.route.transport) }
        showPanel(nil)
        guard !targets.isEmpty else {
            status.text = L("No hay pesta\u{00F1}as SSH o Telnet abiertas")
            return
        }
        for tab in targets { tab.write(command.replacingOccurrences(of: "\n", with: "\r") + "\r") }
        status.text = L("Comando enviado a \(targets.count) pesta\u{00F1}as")
    }

    // MARK: - botones de órdenes

    private func readCommandButtons() throws -> ButtonFile {
        if isDemo { return archivoBotones }
        guard let text = try SafeFile.read(ButtonFile.defaultURL) else { return ButtonFile() }
        return ButtonFile(text: text)
    }

    private func showCommandButtons() {
        do {
            archivoBotones = try readCommandButtons()
            botones.show(archivoBotones)
            status.text = archivoBotones.problems.first ?? ""
            showPanel(botones.view)
        } catch {
            status.text = error.localizedDescription
        }
    }

    private func saveCommandButton(_ button: CommandButton, replacing id: CommandButton.ID?) {
        let fields = [button.group, button.name, button.command]
        guard fields.allSatisfy(Self.esUnaLinea),
              !button.group.contains(" :: "), !button.name.contains(" :: ") else {
            status.text = L("Completa el grupo, el nombre y la orden en una sola línea")
            return
        }
        do {
            // Los UUID se generan al leer botones.txt. Se resuelve la edición por el valor original.
            let original = id.flatMap { key in archivoBotones.buttons.first { $0.id == key } }
            var file = try readCommandButtons()
            guard file.problems.isEmpty else { throw RemoteError(file.problems[0]) }
            if let original {
                let indices = file.buttons.indices.filter { file.buttons[$0] == original }
                guard indices.count == 1, let index = indices.first else {
                    throw RemoteError(L("El archivo de botones cambió. Vuelve a abrir el panel."))
                }
                file.buttons[index] = button
            } else {
                file.buttons.append(button)
            }
            if !isDemo { try file.save() }
            archivoBotones = file
            botones.show(file, select: button)
            status.text = L("Botón «\(button.name)» guardado")
        } catch {
            status.text = L("No se puede guardar: \(error.localizedDescription)")
        }
    }

    private func dispatchButtonHotkey(_ sequence: String, tab: PestanaTerminal) -> Bool {
        guard let key = FunctionKey.name(Array(sequence.utf8)),
              let button = archivoBotones.button(forKey: key) else { return false }
        useCommandButton(button, on: tab)
        return true
    }

    private func useCommandButton(_ button: CommandButton, on target: PestanaTerminal? = nil) {
        if button.mode == .session {
            guard let profile = MainActor.assumeIsolated({ sessions.profile(named: button.command) }) else {
                status.text = L("No existe la sesión «\(button.command)»")
                return
            }
            showPanel(nil)
            openProfile(profile)
            return
        }

        if button.mode == .clave {
            guard let tab = target ?? selected, !tab.closed, !tab.route.isLocal,
                  [.ssh, .telnet].contains(tab.route.transport) else {
                status.text = L("No hay pestañas SSH o Telnet abiertas")
                return
            }
            let io = makeTerminalInput(tab)
            guard MainActor.assumeIsolated({ SecretPrompt.asks(io.cursorLine) }) else {
                status.text = L("Espera a que la sesión pida «Password:»")
                return
            }
            showPanel(nil)
            tab.write(button.command + "\r")
            status.text = L("Contraseña enviada")
            return
        }

        if button.mode == .pass {
            guard let tab = target ?? selected, !tab.closed, !tab.route.isLocal,
                  [.ssh, .telnet].contains(tab.route.transport) else {
                status.text = L("No hay pestañas SSH o Telnet abiertas")
                return
            }
            let io = makeTerminalInput(tab)
            guard MainActor.assumeIsolated({ SecretPrompt.asks(io.cursorLine) }) else {
                status.text = L("Espera a que la sesión pida «Password:»")
                return
            }
            let credName = button.command
            let ref = CredentialRef(service: .named, account: credName)
            Task { @MainActor [weak self, weak tab] in
                guard let self, let tab, !tab.closed else { return }
                do {
                    guard let password = try KeychainStore().password(for: ref) else {
                        self.status.text = L("🔑 «%@» no está en el Llavero").replacingOccurrences(of: "%@", with: credName)
                        return
                    }
                    self.showPanel(nil)
                    tab.write(password + "\r")
                    self.status.text = L("Contraseña enviada")
                } catch {
                    self.status.text = L("Llavero: %@").replacingOccurrences(of: "%@", with: error.localizedDescription)
                }
            }
            return
        }

        if button.mode == .login {
            guard let tab = target ?? selected, !tab.closed, !tab.route.isLocal,
                  [.ssh, .telnet].contains(tab.route.transport) else {
                status.text = L("No hay pestañas SSH o Telnet abiertas")
                return
            }
            guard let (user, credName) = CommandButton.loginParts(button.command) else {
                status.text = L("El botón login necesita «usuario / nombre-de-la-contraseña»")
                return
            }
            guard automatizacionActiva == nil else {
                status.text = L("Ya hay un envío en curso")
                return
            }
            let ref = CredentialRef(service: .named, account: credName)
            let bname = button.name
            Task { @MainActor [weak self, weak tab] in
                guard let self, let tab, !tab.closed else { return }
                do {
                    guard let password = try KeychainStore().password(for: ref) else {
                        self.status.text = L("🔑 «%@» no está en el Llavero").replacingOccurrences(of: "%@", with: credName)
                        return
                    }
                    let abort = AbortSwitch()
                    self.automatizacionActiva = (tab, abort)
                    self.pararAutomatizacion.visibility = .visible
                    self.showPanel(nil)
                    self.status.text = L("Login «%@»").replacingOccurrences(of: "%@", with: bname) + L(" · Esc para cortar")
                    let io = self.makeTerminalInput(tab)
                    let result = await self.loginSequence(user: user, password: password, io: io, abort: abort)
                    self.automatizacionActiva = nil
                    self.pararAutomatizacion.visibility = .collapsed
                    self.status.text = result
                } catch {
                    self.status.text = L("Llavero: %@").replacingOccurrences(of: "%@", with: error.localizedDescription)
                }
            }
            return
        }

        guard let tab = target ?? selected, !tab.closed, !tab.route.isLocal,
              [.ssh, .telnet].contains(tab.route.transport) else {
            status.text = L("No hay pestañas SSH o Telnet abiertas")
            return
        }
        let values = Dictionary(uniqueKeysWithValues: button.holes.map { ($0.name, $0.value) })
        let preview = button.filled(values)
        confirmarBoton.show(title: button.name, hint: tab.title, text: preview, editable: true,
                           confirmTitle: button.mode == .type ? L("Escribir") : L("Revisar"))
        confirmarBoton.onConfirm = { [weak self, weak tab] command in
            guard let self, let tab, !tab.closed,
                  self.selected === tab || self.ventanasPestana[ObjectIdentifier(tab)] != nil else { return }
            self.applyCommandButton(button, text: command, to: tab)
        }
        showPanel(confirmarBoton.view)
        if ventanasPestana[ObjectIdentifier(tab)] != nil { try? window?.activate() }
    }

    @MainActor
    private func loginSequence(user: String, password: String, io: EntradaMacro, abort: AbortSwitch) async -> String {
        let start = Date()
        while !PasswordPrompt.isLoginLine(io.cursorLine) {
            if abort.isTripped { return L("⎋ Cancelado: no se envía nada más") }
            if Date().timeIntervalSince(start) > 30 { return L("✗ sin prompt de usuario en 30s") }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        io.send(bytes: Array((user + "\r").utf8))
        let start2 = Date()
        while !SecretPrompt.asks(io.cursorLine) {
            if abort.isTripped { return L("⎋ Cancelado: no se envía nada más") }
            if Date().timeIntervalSince(start2) > 30 { return L("✗ sin prompt de contraseña en 30s") }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        io.send(bytes: Array((password + "\r").utf8))
        return L("✓ login completado")
    }

    private static func esUnaLinea(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespaces).isEmpty
            && !value.contains(where: \.isNewline)
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private func applyCommandButton(_ button: CommandButton, text: String, to tab: PestanaTerminal) {
        guard Self.esUnaLinea(text) else {
            status.text = L("Escribe un comando válido de una línea")
            return
        }
        if button.mode == .type {
            let io = makeTerminalInput(tab)
            guard automatizacionActiva?.tab !== tab, grabando?.tab !== tab,
                  MainActor.assumeIsolated({ PromptRule.isPrompt(io.cursorLine, custom: io.promptRule) }) else {
                status.text = L("Espera al prompt de la sesión antes de enviar órdenes")
                return
            }
            showPanel(nil)
            tab.paste(text)
        } else {
            let command = CommandButton(group: button.group, mode: .run, name: button.name, command: text)
            playMacro(Macro(name: button.name, steps: Macro.recorded(command.lines)), on: tab)
        }
    }

    // MARK: - macros

    private func showMacros() {
        let loaded = isDemo ? nil : MacroLibrary.load()
        macros.show(loaded?.library ?? macrosDemo)
        status.text = loaded?.error ?? loaded?.warnings.first ?? ""
        showPanel(macros.view)
    }

    private func saveMacro(_ macro: Macro) {
        if let problem = macro.problem {
            status.text = L("✗ macro no válida: \(problem)")
            return
        }
        let loaded = isDemo ? nil : MacroLibrary.load()
        if let error = loaded?.error {
            status.text = error
            return
        }
        var library = loaded?.library ?? macrosDemo
        guard library.uniqueName(macro.name, except: macro.id) == macro.name else {
            status.text = L("ya hay una macro con ese nombre")
            return
        }
        if let index = library.macros.firstIndex(where: { $0.id == macro.id }) {
            library.macros[index] = macro
        } else {
            library.macros.append(macro)
        }
        do {
            if isDemo { macrosDemo = library } else { try library.save() }
            macros.clearDraft()
            macros.show(library, selected: macro.id)
            status.text = L("✓ Macro «\(macro.name)» guardada")
        } catch {
            status.text = L("No se puede guardar: \(error.localizedDescription)")
        }
    }

    private func confirmMacroDeletion(_ macro: Macro) {
        macroConfirm.show(title: L("¿Borrar la macro «\(macro.name)»?"),
                          hint: L("Queda una copia en macros.json.anterior."), text: "",
                          editable: false, confirmTitle: L("Borrar"))
        macroConfirm.onConfirm = { [weak self] _ in self?.deleteMacro(macro.id) }
        showPanel(macroConfirm.view)
    }

    private func deleteMacro(_ id: Macro.ID) {
        let loaded = isDemo ? nil : MacroLibrary.load()
        if let error = loaded?.error {
            status.text = error
            return
        }
        var library = loaded?.library ?? macrosDemo
        library.macros.removeAll { $0.id == id }
        do {
            if isDemo { macrosDemo = library } else { try library.save() }
            macros.clearDraft()
            showMacros()
        } catch {
            status.text = error.localizedDescription
        }
    }

    private func makeTerminalInput(_ tab: PestanaTerminal) -> EntradaMacro {
        MainActor.assumeIsolated {
            let profile = tab.route.transientProfile ?? tab.route.sessionName.flatMap(sessions.profile(named:))?.terminal
            return EntradaMacro(tab: tab, promptRule: profile.flatMap { PromptRule($0.prompt) })
        }
    }

    private func startRecording() {
        guard grabando == nil, let tab = selected, !tab.closed, !tab.route.isLocal,
              [.ssh, .telnet].contains(tab.route.transport), automatizacionActiva?.tab !== tab else { return }
        let io = makeTerminalInput(tab)
        guard MainActor.assumeIsolated({ PromptRule.isPrompt(io.cursorLine, custom: io.promptRule) }) else {
            status.text = L("Espera al prompt de la sesión antes de grabar")
            return
        }
        let recorder = MainActor.assumeIsolated { MacroRecorder(allowScreenFallback: false, soloConexiones: true) }
        grabando = (tab, recorder, io)
        showPanel(nil)
        pararGrabacion.visibility = .visible
        status.text = L("● Grabando una macro en «\(tab.title)»: escribe las órdenes (las contraseñas no se graban)")
    }

    private func recordKeys(_ text: String, tab: PestanaTerminal) {
        guard let recording = grabando, recording.tab === tab else { return }
        MainActor.assumeIsolated { recording.recorder.feed(Array(text.utf8), from: recording.io) }
    }

    private func finishRecording() {
        guard let recording = grabando else { return }
        grabando = nil
        pararGrabacion.visibility = .collapsed
        let lines = MainActor.assumeIsolated { recording.recorder.lines }
        showMacros()
        if lines.isEmpty {
            status.text = L("Grabación parada: no hay órdenes que guardar")
        } else {
            macros.recorded(lines)
            status.text = L("■ Grabadas \(lines.count) órdenes")
        }
    }

    private func playMacro(_ macro: Macro, on target: PestanaTerminal? = nil) {
        guard let tab = target ?? selected, !tab.closed, !tab.route.isLocal,
              [.ssh, .telnet].contains(tab.route.transport) else {
            status.text = L("No hay pestañas SSH o Telnet abiertas")
            return
        }
        if macro.confirm || !macro.dangerousLines.isEmpty {
            macroConfirm.show(title: L("¿Reproducir «\(macro.name)»?"),
                              hint: L("\(macro.lines.count) órdenes en \(tab.title)"),
                              text: macro.lines.joined(separator: "\n"), editable: false,
                              confirmTitle: L("Reproducir"))
            macroConfirm.onConfirm = { [weak self, weak tab] _ in
                guard let self, let tab else { return }
                self.runMacro(macro, on: tab, allowDangerous: true)
            }
            showPanel(macroConfirm.view)
        } else {
            runMacro(macro, on: tab, allowDangerous: false)
        }
    }

    private func runMacro(_ macro: Macro, on tab: PestanaTerminal, allowDangerous: Bool) {
        startAutomation(on: tab, title: L("▶ «\(macro.name)»")) { [weak self] io, abort in
            let report = await MacroPlayer(allowDangerous: allowDangerous).run(macro, on: io, abort: abort)
            return self?.macroResult(report) ?? ""
        }
    }

    private func startAutomation(on tab: PestanaTerminal, title: String,
                                 run: @escaping @MainActor (EntradaMacro, AbortSwitch) async -> String) {
        guard automatizacionActiva == nil else {
            status.text = L("Ya hay un envío en curso")
            return
        }
        guard !tab.closed, selected === tab || ventanasPestana[ObjectIdentifier(tab)] != nil else { return }
        let abort = AbortSwitch()
        guard grabando?.tab !== tab else {
            status.text = L("Para la grabación antes de enviar órdenes en esa pestaña")
            return
        }
        let io = makeTerminalInput(tab)
        guard MainActor.assumeIsolated({ PromptRule.isPrompt(io.cursorLine, custom: io.promptRule) }) else {
            status.text = L("Espera al prompt de la sesión antes de enviar órdenes")
            return
        }
        automatizacionActiva = (tab, abort)
        showPanel(nil)
        pararAutomatizacion.visibility = .visible
        status.text = title + L(" · Esc para cortar")
        Task { @MainActor [weak self] in
            let result = await run(io, abort)
            self?.onUI { app in
                app.automatizacionActiva = nil
                app.pararAutomatizacion.visibility = .collapsed
                app.status.text = result
            }
        }
    }

    private func macroResult(_ report: MacroReport) -> String {
        switch report.outcome {
        case .completed: return L("✓ \(report.sent)/\(report.total) órdenes")
        case .aborted: return L("⎋ parada en \(report.sent)/\(report.total)")
        case .deviceError(let step, let output): return L("✗ error en el paso \(step): \(output)")
        case .pager(let step): return L("✗ paginador en el paso \(step) (falta «terminal length 0»)")
        case .timeout(let step): return L("✗ sin respuesta a tiempo en el paso \(step)")
        case .dangerousNotConfirmed(let step, let command): return L("✗ paso \(step) peligroso sin confirmar: \(command)")
        case .secretPrompt(let step): return L("🔑 piden contraseña en el paso \(step): paro (no escribo nada ahí)")
        case .invalid(let problem): return L("✗ macro no válida: \(problem)")
        }
    }

    // MARK: - espacios e historial

    private func showTerminalSearch() {
        guard let selected else { return }
        pestañaBuscada = selected
        buscarTerminal.reset(title: selected.title)
        status.text = ""
        showPanel(buscarTerminal.view)
    }

    private func showWorkspaces() {
        do {
            espacios.show(isDemo ? espaciosDemo : try WorkspaceLibrary.load())
            status.text = ""
            showPanel(espacios.view)
        } catch {
            status.text = error.localizedDescription
        }
    }

    private func saveWorkspace(_ nombre: String) {
        do {
            let current = terminals.filter { !$0.closed }
            let entries = current.map { WorkspaceTab(route: $0.route) }
            let ids = Dictionary(uniqueKeysWithValues: zip(current.map(ObjectIdentifier.init), entries.map(\.id)))
            let active = selected.flatMap { ids[ObjectIdentifier($0)] }
            let panes = terminalesVisibles.compactMap { $0.flatMap { ids[ObjectIdentifier($0)] } }
            let apilada = divisionGuardadaApilada ?? settings.divisionApilada
            let layout = panes.count == 2 ? (apilada ? "stack2" : "side2") : nil
            let workspace = Workspace(name: nombre.trimmingCharacters(in: .whitespacesAndNewlines),
                                      tabs: entries, selected: active, layout: layout, panes: panes)
            var lib = isDemo ? espaciosDemo : try WorkspaceLibrary.load()
            lib.workspaces.append(workspace)
            if let problem = lib.problem { throw WorkspaceError(problem) }
            if isDemo { espaciosDemo = lib } else { try lib.save() }
            espacios.show(lib, selected: workspace.id)
            status.text = L("Espacio «\(workspace.name)» guardado")
        } catch {
            status.text = L("No se puede guardar: \(error.localizedDescription)")
        }
    }

    private func restoreWorkspace(_ workspace: Workspace) {
        do {
            let resolved = try MainActor.assumeIsolated { try workspace.resolve(using: sessions) }
            var restored: [WorkspaceTab.ID: PestanaTerminal] = [:]
            for entry in resolved.tabs where entry.route.isLocal || entry.route.transport == .ssh {
                restored[entry.id] = open(entry.route)
            }
            guard let selected = workspace.selected.flatMap({ restored[$0] })
                ?? resolved.tabs.lazy.compactMap({ restored[$0.id] }).first else {
                status.text = L("No se ha podido abrir ninguna pestaña del espacio")
                return
            }
            let panes = workspace.panes.compactMap { restored[$0] }
            if panes.count >= 2, let i = panes.prefix(2).firstIndex(where: { $0 === selected }) {
                terminalesVisibles = [panes[0], panes[1]]
                panelActivo = i
                divisionGuardadaApilada = workspace.layout == "stack2"
            } else {
                terminalesVisibles = [selected, nil]
                panelActivo = 0
                divisionGuardadaApilada = nil
            }
            updateSplitLayout()
            showPanel(nil)
            select(selected)
            status.text = L("Pestañas restauradas: \(restored.count) de \(workspace.tabs.count)")
        } catch {
            status.text = error.localizedDescription
        }
    }

    // MARK: - actualizaciones

    /// Lleva `body` al hilo de WinUI (las tareas de la red acaban en otro).
    private func onUI(_ body: @escaping (NetDeckWindows) -> Void) {
        _ = try? window?.dispatcherQueue?.tryEnqueue { [weak self] in
            if let self { body(self) }
        }
    }

    private func checkUpdatesOnLaunch() {
        guard !isDemo else { return }
        let defaults = UserDefaults.standard
        let key = "lastUpdateCheck"
        let now = Date()
        if let last = defaults.object(forKey: key) as? Date,
           now.timeIntervalSince(last) >= 0, now.timeIntervalSince(last) < 24 * 60 * 60 { return }
        defaults.set(now, forKey: key)
        Task { [weak self] in
            guard let found = try? await UpdateChecker.shared.check() else { return }
            self?.onUI { app in
                guard !app.manualUpdateRequested else { return }
                app.startupUpdate = found
                app.offerStartupUpdateIfIdle()
            }
        }
    }

    private func offerStartupUpdateIfIdle() {
        guard terminalGrid.visibility == .visible, let info = startupUpdate else { return }
        startupUpdate = nil
        offerUpdate(info)
    }

    /// La búsqueda manual muestra el resultado o el motivo del fallo en Ajustes.
    private func checkUpdates() {
        manualUpdateRequested = true
        startupUpdate = nil
        ajustes.setUpdateStatus(L("Buscando actualizaciones\u{2026}"))
        // (solo para probar la interfaz: NETDECK_UPDATE_FAKE=1 en la demo enseña una actualizacion inventada, sin red)
        if isDemo, ProcessInfo.processInfo.environment["NETDECK_UPDATE_FAKE"] == "1",
           let url = URL(string: "https://github.com/Iljonis/Terminal-NetDeck/releases/download/v9.9.9/Terminal-NetDeck-9.9.9.msi") {
            offerUpdate(UpdateInfo(version: "9.9.9", downloadURL: url, sha256: String(repeating: "0", count: 64),
                                   releaseNotes: "Notas de prueba de la 9.9.9"))
            return
        }
        Task { [weak self] in
            do {
                let found = try await UpdateChecker.shared.check()
                self?.onUI { me in
                    if let found { me.offerUpdate(found) }
                    else { me.ajustes.setUpdateStatus(L("Est\u{00E1}s al d\u{00ED}a (versi\u{00F3}n \(UpdateChecker.currentVersion))")) }
                }
            } catch {
                let reason = error.localizedDescription
                self?.onUI { $0.ajustes.setUpdateStatus(L("No se puede comprobar: \(reason)")) }
            }
        }
    }

    private func offerUpdate(_ info: UpdateInfo) {
        pendingUpdate = info
        ajustes.setUpdateStatus("")
        actualizacion.show(title: L("Actualizaci\u{00F3}n disponible: \(info.version)"),
                           hint: L("Se descargar\u{00E1} de github.com, se comprobar\u{00E1}n el sha256 y la firma y Windows pedir\u{00E1} permisos de administrador. No se instala nada sin tu clic."),
                           text: info.releaseNotes.isEmpty ? L("Sin notas de la versi\u{00F3}n") : info.releaseNotes,
                           editable: false, confirmTitle: L("Descargar e instalar"))
        showPanel(actualizacion.view)
    }

    private func installUpdate() {
        guard let info = pendingUpdate else { return }
        showPanel(nil)
        status.text = L("Descargando la actualizaci\u{00F3}n\u{2026}")
        Task { [weak self] in
            do {
                let installer = try await UpdateChecker.shared.downloadAndVerify(info)
                let launched = UpdateChecker.shared.launchInstaller(at: installer)
                self?.onUI { me in
                    me.pendingUpdate = nil
                    me.status.text = launched ? L("Instalador lanzado: cierra Terminal NetDeck para completar la actualizaci\u{00F3}n")
                                              : L("No se ha podido lanzar el instalador")
                }
            } catch {
                let reason = error.localizedDescription
                self?.onUI { $0.status.text = L("No se puede actualizar: \(reason)") }
            }
        }
    }

    // MARK: - asistente de inicio

    private func showAsistente(markSeen: Bool) {
        asistente.onCreateSession = { [weak self] session in
            guard let self else { return false }
            let saved = self.saveSession(session, replacing: nil)
            if saved { self.showPanel(self.asistente.view) }     // (guardar cierra los paneles: vuelve a «Todo listo»)
            return saved
        }
        asistente.onDone = { [weak self] in
            if markSeen {
                UserDefaults.standard.set(true, forKey: "ndAsistenteVisto")
                UserDefaults.standard.synchronize()
            }
            self?.showPanel(nil)
        }
        asistente.start()
        showPanel(asistente.view)
    }

    // MARK: - tuneles

    private func showTuneles() {
        status.text = ""
        tuneles.show()
        showPanel(tuneles.view)
    }

    /// Inicia un tunel guardado (solo desde un clic): ruta de su sesion o del equipo escrito, y ssh sin shell.
    private func startTunnel(_ tunnel: Tunnel) {
        do {
            let route = try MainActor.assumeIsolated { try tunnel.route(using: sessions) }
            let arguments = try tunnel.arguments(route: route, sharing: nil, configFile: isDemo ? "NUL" : nil)
            let environment = TerminalEnvironment.prepare(ProcessInfo.processInfo.environment, forSSH: true, sendLocale: false)
            MainActor.assumeIsolated {
                tunnelManager.start(tunnel, executable: SystemTools.ssh, arguments: arguments, environment: environment)
            }
        } catch {
            MainActor.assumeIsolated { tunnelManager.markFailed(tunnel.id, error.localizedDescription) }
        }
        tuneles.refresh()
    }

    private func stopTunnel(_ id: Tunnel.ID) {
        Task { [weak self] in
            await self?.tunnelManager.stop(id)
            _ = try? self?.window?.dispatcherQueue?.tryEnqueue { self?.tuneles.refresh() }
        }
    }

    /// Cambio de estado de un tunel: repinta la lista (en el hilo de WinUI) y avisa en el panel.
    private func tunnelChanged(_ id: Tunnel.ID, _ state: TunnelState) {
        _ = try? window?.dispatcherQueue?.tryEnqueue { [weak self] in
            guard let self else { return }
            let name = self.tuneles.library.tunnel(id)?.name ?? "?"
            switch state {
            case .active: self.tuneles.setStatus(L("T\u{00FA}nel \u{00AB}\(name)\u{00BB} activo"))
            case .failed(let why): self.tuneles.setStatus(L("No se puede iniciar el t\u{00FA}nel \u{00AB}\(name)\u{00BB}: \(why)"))
            default: break
            }
            self.tuneles.refresh()
        }
    }

    // MARK: - atajos

    /// Ctrl+N terminal local, Ctrl+Mayus+N sesion nueva, Ctrl+W cierra la pestana, Ctrl+Tab / Ctrl+Mayus+Tab
    /// cambian de pestana, Ctrl+, abre Ajustes. Devuelve true si la tecla era un atajo.
    private func shortcut(_ key: Int32) -> Bool {
        guard GetKeyState(Int32(VK_CONTROL)) < 0, GetKeyState(Int32(VK_MENU)) >= 0 else { return false }
        let shift = GetKeyState(Int32(VK_SHIFT)) < 0
        switch key {
        case 78:
            if shift { newSession() } else { showPanel(nil); open(.local()) }
        case 87:
            showPanel(nil)
            closeSelected()
        case 9:
            showPanel(nil)
            cycleTab(shift ? -1 : 1)
        case 66 where shift:
            showCommandButtons()
        case 68 where shift:
            toggleSplit()
        case 69 where shift:
            showWorkspaces()
        case 70 where terminalGrid.visibility == .visible:
            showTerminalSearch()
        case 77:
            showMacros()
        case 84:
            showTuneles()
        case 75 where shift:
            showLlavero()
        case 86 where shift:
            safePaste()
        case 188:
            showAjustes()
        default:
            return false
        }
        return true
    }

    private func cycleTab(_ step: Int) {
        guard terminals.count > 1, let selected,
              let index = terminals.firstIndex(where: { $0 === selected }) else { return }
        select(terminals[(index + step + terminals.count) % terminals.count])
    }

    // MARK: - tema de colores del terminal

    /// Los colores del tema (de NetDeckCore) en la superficie del terminal, en su paleta y en el texto, por trozos de color.
    private func applyTerminalTheme(_ id: String) {
        let theme = TemasTerminal.tema(id: id)
        paleta = theme.map(PaletaTerminal.init(tema:))
        var contraste = HIGHCONTRASTW()
        contraste.cbSize = UINT(MemoryLayout<HIGHCONTRASTW>.size)
        let contrasteActivo = SystemParametersInfoW(UINT(SPI_GETHIGHCONTRAST), contraste.cbSize, &contraste, 0)
            && contraste.dwFlags & DWORD(HCF_HIGHCONTRASTON) != 0
        let choice = ScreenFilter.resolve(choice: settings.filtro, on: true, theme: theme?.screenFilter,
                                          calm: contrasteActivo)
        screenLook = choice.look(intensity: settings.intensidad, text: paleta?.texto ?? paletaBase.texto)
        for vista in vistas {
            vista.invalidate()
            vista.filtro.apply(screenLook)
            vista.surface.background = paleta.map { brush($0.fondo) } ?? brushTransparente
            if let paleta { vista.screen.foreground = brush(paleta.texto) }
            else { _ = try? vista.screen.clearValue(TextBlock.foregroundProperty) }
        }
        for tab in terminals { tab.apply(palette: paleta) }
        for tab in ventanasPestana.values {
            styleDetached(tab)
            tab.session.apply(palette: paleta)
            renderDetached(tab)
        }
        render()
    }

    private func brush(_ c: RGB) -> SolidColorBrush {
        if let known = pinceles[c] { return known }
        func channel(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        let made = SolidColorBrush(Color(a: 255, r: channel(c.r), g: channel(c.g), b: channel(c.b)))
        pinceles[c] = made
        return made
    }

    // MARK: - ajustes

    private var highlightURL: URL { AppPaths.support.appendingPathComponent("resaltado.yml") }

    private func highlightText() throws -> String {
        if let resaltadoDemo { return resaltadoDemo }
        if !isDemo, let custom = try SafeFile.read(highlightURL) { return custom }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let bundled = exe.appendingPathComponent("Resaltado/netdeck.yml")
        return try SafeFile.read(bundled) ?? "rules:\n"
    }

    private func reloadHighlight() {
        do {
            highlightConfig = settings.resaltado ? try HighlightConfig(text: highlightText()) : nil
        } catch {
            highlightConfig = nil
            status.text = error.localizedDescription
        }
        for tab in terminals { tab.resaltar(highlightConfig) }
        for detached in ventanasPestana.values { detached.session.resaltar(highlightConfig) }
    }

    private func showHighlightRules() {
        do {
            reglas.show(title: L("Editar reglas de resaltado"), hint: L("Reglas en formato ChromaTerm YAML"),
                        text: try highlightText(), editable: true, confirmTitle: L("Guardar"))
            showPanel(reglas.view)
        } catch {
            status.text = error.localizedDescription
        }
    }

    private func saveHighlightRules(_ text: String) {
        do {
            let source = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            guard source.split(whereSeparator: \.isNewline).contains(where: { $0.trimmingCharacters(in: .whitespaces) == "rules:" }) else {
                throw RemoteError(L("El archivo de resaltado necesita una sección rules"))
            }
            let parsed = try HighlightConfig(text: source)
            if let problem = parsed.problems.first { throw RemoteError(problem) }
            if isDemo { resaltadoDemo = source } else {
                _ = AppPaths.ensure(highlightURL.deletingLastPathComponent())
                try SafeFile.backup(highlightURL)
                try SafeFile.write(source, to: highlightURL)
            }
            settings.resaltado = true
            if !isDemo { settings.guardar() }
            reloadHighlight()
            render()
            showAjustes()
            status.text = L("Reglas de resaltado guardadas")
        } catch {
            status.text = L("No se puede guardar: \(error.localizedDescription)")
        }
    }

    private func showAjustes() {
        status.text = ""
        ajustes.show(settings)
        showPanel(ajustes.view)
    }

    private func hideAjustes() { showPanel(nil) }

    private func showLlavero() {
        llavero.reload()
        showPanel(llavero.view)
    }

    private func saveAjustes(_ new: AjustesTerminal) {
        settings = new
        if !isDemo { new.guardar() }
        divisionGuardadaApilada = nil
        applySettings(new)
        hideAjustes()
        status.text = L("Ajustes guardados")
    }

    /// Fuente y tamano al terminal; el tema, a la ventana (Sistema = el de Windows).
    private func applySettings(_ a: AjustesTerminal) {
        let medidor = TextBlock()
        medidor.fontFamily = FontFamily(a.fuente)
        medidor.fontSize = Double(a.tamano)
        medidor.text = String(repeating: "M", count: 16)
        _ = try? medidor.measure(Size(width: 1000, height: 200))
        let medida = Double(medidor.desiredSize.width) / 16
        anchoCelda = medida > 0 ? medida : 8.25 * Double(a.tamano) / 15
        for vista in vistas {
            vista.cellSize(width: anchoCelda, height: alturaLinea)
            vista.screen.fontFamily = FontFamily(a.fuente)
            vista.screen.fontSize = Double(a.tamano)
            vista.screen.lineHeight = alturaLinea
        }
        updateSplitLayout()
        let theme: Int32 = a.tema == "Claro" ? 1 : (a.tema == "Oscuro" ? 2 : 0)
        rootView?.requestedTheme = ElementTheme(rawValue: theme)
        reloadHighlight()
        applyTerminalTheme(a.temaTerminal)
        for tab in ventanasPestana.values { resizeDetached(tab) }
        // Mica solo con «Sistema»; con Claro u Oscuro, fondo liso. (Mica pide Windows 11.)
        window?.systemBackdrop = a.tema == "Sistema (Mica)" ? MicaBackdrop() : nil
        // Sin Mica la ventana no pinta fondo propio: Claro y Oscuro lo ponen a mano.
        switch a.tema {
        case "Claro": rootView?.background = SolidColorBrush(Color(a: 255, r: 243, g: 243, b: 243))
        case "Oscuro": rootView?.background = SolidColorBrush(Color(a: 255, r: 32, g: 32, b: 32))
        default: rootView?.background = nil
        }
        resize()
    }

    /// Guarda la sesion: en demo solo en memoria; en real, en el ssh_config de NetDeck. Devuelve true si se guardo.
    private func saveSession(_ session: EditableSession, replacing original: String?) -> Bool {
        guard EditableSession.isValidName(session.name) else {
            status.text = L("El nombre es obligatorio y no puede llevar espacios ni * ? !")
            return false
        }
        var file = SessionFile()
        if isDemo {
            file = library
        } else if FileManager.default.fileExists(atPath: SessionFile.defaultURL.path) {
            do { file = try SessionFile(contentsOf: SessionFile.defaultURL) } catch {
                status.text = L("No se puede leer el archivo de sesiones: \(error.localizedDescription)")
                return false
            }
        }
        if let original, let index = file.sessions.firstIndex(where: { $0.name == original }) {
            file.sessions[index] = session
        } else {
            file.sessions.append(session)
        }
        if let problem = file.problems().first {
            status.text = problem
            return false
        }
        if isDemo {
            library = file
            MainActor.assumeIsolated {
                sessions = SessionManager(profiles: SSHConfigParser().parse(file.render()))
            }
        } else {
            if let error = file.save() {
                status.text = L("No se puede guardar: \(error)")
                return false
            }
            MainActor.assumeIsolated { sessions.load(from: SessionFile.defaultURL) }
        }
        buildSidebar()
        hideEditor()
        status.text = L("Sesi\u{00F3}n \u{00AB}\(session.name)\u{00BB} guardada")
        return true
    }

    /// Una sesion del ssh_config leido (sidebar) como sesion editable, para el modo demo o si no esta en el archivo.
    private static func editable(from perfil: SessionProfile) -> EditableSession {
        var session = EditableSession(group: perfil.group ?? "General", name: perfil.name)
        session.kind = perfil.transport
        session.host = perfil.hostName ?? ""
        session.user = perfil.user ?? ""
        session.port = perfil.port.map(String.init) ?? EditableSession.defaultPort(perfil.transport)
        session.jump = perfil.proxyJump.joined(separator: ",")
        session.summary = perfil.summary ?? ""
        session.legacy = perfil.legacy
        session.serial = perfil.serial ?? SerialLine()
        return session
    }

    private func openProfile(_ perfil: SessionProfile) {
        do {
            let ruta = try MainActor.assumeIsolated { try sessions.route(to: perfil) }
            try? SessionLists.noteRecent(perfil.name, in: recientesURL)
            open(ruta)
            buildSidebar()
        } catch {
            status.text = L("No se puede abrir \u{00AB}\(perfil.name)\u{00BB}: \(error.localizedDescription)")
        }
    }

    /// El explorador de una sesion SSH o SFTP del ssh_config.
    private func openSFTPProfile(_ perfil: SessionProfile) {
        do {
            var ruta = try MainActor.assumeIsolated { try sessions.route(to: perfil) }
            if ruta.transport == .ssh { ruta = try SFTPPanel.route(for: ruta) }
            openSFTP(ruta)
        } catch {
            status.text = L("No se puede abrir \u{00AB}\(perfil.name)\u{00BB}: \(error.localizedDescription)")
        }
    }

    /// Abre el explorador SFTP (ssh con el subsistema sftp) en el area principal.
    private func openSFTP(_ route: ConnectionRoute) {
        // (como en el terminal, la demo no lee el ssh_config del usuario; NETDECK_SFTP_SERVER habla SFTP sin ssh ni red,
        // para probar el explorador con un sftp-server local)
        let dev = isDemo ? ProcessInfo.processInfo.environment["NETDECK_SFTP_SERVER"] : nil
        guard let command = dev.map({ ($0, [String]()) })
                ?? route.sftpSubsystemCommand(sharing: nil, configFile: isDemo ? "NUL" : nil) else {
            status.text = L("Equipo no v\u{00E1}lido: \u{00AB}\(route.target.host)\u{00BB}")
            return
        }
        let environment = TerminalEnvironment.prepare(ProcessInfo.processInfo.environment, forSSH: true, sendLocale: false)
        status.text = ""
        explorador.connect(label: route.title, executable: command.0, arguments: command.1, environment: environment)
        showPanel(explorador.view)
    }

    private func connect() {
        guard let target = Endpoint(parsing: destination.text), target.isShellSafe else {
            status.text = L("Destino no v\u{00E1}lido: \u{00AB}\(destination.text)\u{00BB}")
            return
        }
        open(ConnectionRoute(title: target.description, target: target))
    }

    @discardableResult
    private func open(_ route: ConnectionRoute) -> PestanaTerminal? {
        if route.transport == .sftp {
            openSFTP(route)
            return nil
        }
        if route.transport == .ftp {
            guard route.jumps.isEmpty else {
                status.text = L("FTP requiere una conexión directa")
                return nil
            }
            status.text = ""
            accesoFTP.show(route)
            showPanel(accesoFTP.view)
            return nil
        }
        do {
            if let problem = route.launchProblem() { throw RemoteError(problem) }
            let config = MainActor.assumeIsolated { sessions.source }
            let session = try PestanaTerminal(route: route, config: config)
            let queue = window?.dispatcherQueue
            terminals.append(session)
            session.apply(palette: paleta)
            session.resaltar(highlightConfig)
            select(session)
            session.observe(enqueue: { action in
                (try? queue?.tryEnqueue { action() }) == true
            }, changed: { [weak self, weak session] in
                guard let self, let session else { return }
                if session.closed, self.automatizacionActiva?.tab === session { self.automatizacionActiva?.abort.trip() }
                if session.closed, self.grabando?.tab === session { self.finishRecording() }
                if let detached = self.ventanasPestana[ObjectIdentifier(session)] {
                    self.renderDetached(detached)
                    return
                }
                guard let index = self.terminalesVisibles.firstIndex(where: { $0 === session }) else { return }
                self.render(index)
                if self.selected === session, session.closed { self.status.text = L("Conexión cerrada") }
            })
            return session
        } catch {
            status.text = L("No se puede abrir \u{00AB}\(route.title)\u{00BB}: \(error.localizedDescription)")
            return nil
        }
    }

    private func select(_ session: PestanaTerminal?, focus: Bool = true) {
        if let session, let index = terminalesVisibles.firstIndex(where: { $0 === session }) {
            panelActivo = index
        } else {
            terminalesVisibles[panelActivo] = session
        }
        selected = session
        status.text = session?.closed == true ? L("Conexión cerrada") : ""
        tabs.children.clear()
        for candidate in terminals {
            let tab = RadioButton()
            tab.content = candidate.title
            AutomationProperties.setName(tab, candidate.title)
            tab.groupName = "terminales"
            tab.isChecked = candidate === session
            tab.click.addHandler { [weak self, weak candidate] _, _ in
                guard let candidate else { return }
                self?.select(candidate)
            }
            tab.canDrag = true
            tab.allowDrop = true
            tab.dragStarting.addHandler { [weak self, weak candidate] _, args in
                self?.pestañaArrastrada = candidate
                args?.allowedOperations = .move
                try? args?.data.setText("NetDeck")
            }
            tab.dragOver.addHandler { [weak self, weak candidate] _, args in
                guard let source = self?.pestañaArrastrada, let candidate, source !== candidate else { return }
                args?.acceptedOperation = .move
                args?.handled = true
            }
            tab.drop.addHandler { [weak self, weak candidate] _, args in
                guard let self, let source = self.pestañaArrastrada, let candidate else { return }
                self.reorder(source, at: candidate)
                args?.handled = true
            }
            tab.dropCompleted.addHandler { [weak self] _, _ in self?.pestañaArrastrada = nil }
            let menu = MenuFlyout()
            let detach = MenuFlyoutItem()
            detach.text = L("Mover pestaña a otra ventana")
            detach.isEnabled = !candidate.closed
            detach.click.addHandler { [weak self, weak candidate] _, _ in
                guard let candidate else { return }
                self?.detach(candidate)
            }
            menu.items.append(detach)
            tab.contextFlyout = menu
            tabs.children.append(tab)
        }
        closeButton.isEnabled = session != nil
        resize()
        render()
        if focus { focusTerminal() }
    }

    private func reorder(_ tab: PestanaTerminal, at destination: PestanaTerminal) {
        pestañaArrastrada = nil
        guard tab !== destination, let from = terminals.firstIndex(where: { $0 === tab }),
              let to = terminals.firstIndex(where: { $0 === destination }) else { return }
        terminals.remove(at: from)
        terminals.insert(tab, at: to)
        select(selected)
    }

    private func closeSelected() {
        guard let selected else { return }
        if automatizacionActiva?.tab === selected { automatizacionActiva?.abort.trip() }
        let acabaGrabacion = grabando?.tab === selected
        selected.close()
        removeFromMain(selected)
        if acabaGrabacion { finishRecording() }
    }

    private func removeFromMain(_ tab: PestanaTerminal) {
        guard let index = terminals.firstIndex(where: { $0 === tab }) else { return }
        terminals.remove(at: index)
        if panelDividido, let pane = terminalesVisibles.firstIndex(where: { $0 === tab }) {
            let otra = terminalesVisibles[1 - pane]
            terminalesVisibles = [otra, nil]
            panelActivo = 0
            updateSplitLayout()
            select(otra)
        } else if selected !== tab {
            select(selected)
        } else {
            select(terminals.isEmpty ? nil : terminals[min(index, terminals.count - 1)])
        }
    }

    private func detach(_ tab: PestanaTerminal) {
        guard !tab.closed, automatizacionActiva?.tab !== tab, grabando?.tab !== tab else { return }
        let id = ObjectIdentifier(tab)
        let window = Window()
        let vista = VistaTerminal(id: "PantallaTerminalSeparada")
        let detached = VentanaPestana(window: window, vista: vista, session: tab)
        let root = StackPanel()
        root.orientation = .horizontal
        let volver = Button()
        volver.content = L("Devolver pestaña")
        volver.margin = Thickness(left: 8, top: 4, right: 8, bottom: 4)
        volver.click.addHandler { [weak self] _, _ in self?.returnToMain(id) }
        root.children.append(volver)
        let grid = Grid()
        let menuRow = RowDefinition()
        menuRow.height = GridLength(value: 1, gridUnitType: .auto)
        let bodyRow = RowDefinition()
        bodyRow.height = GridLength(value: 1, gridUnitType: .star)
        grid.rowDefinitions.append(menuRow)
        grid.rowDefinitions.append(bodyRow)
        Grid.setRow(vista.surface, 1)
        grid.children.append(root)
        grid.children.append(vista.surface)
        window.title = "Terminal NetDeck · " + tab.title
        window.content = grid

        vista.surface.pointerPressed.addHandler { [weak vista] _, _ in _ = try? vista?.surface.focus(.programmatic) }
        vista.surface.sizeChanged.addHandler { [weak self] _, _ in
            if let detached = self?.ventanasPestana[id] { self?.resizeDetached(detached) }
        }
        vista.surface.keyDown.addHandler { [weak self, weak tab] _, args in
            guard let self, let tab, !tab.closed, let args, let keys = self.keySequence(args.key.rawValue, tab: tab) else { return }
            args.handled = true
            if self.automatizacionActiva?.tab === tab {
                guard AbortKey.isAbort(keys.utf8) else { return }
                self.automatizacionActiva?.abort.trip()
                if keys == "\u{1b}" { return }
            }
            if self.dispatchButtonHotkey(keys, tab: tab) { return }
            tab.write(keys)
        }
        vista.surface.characterReceived.addHandler { [weak self, weak tab] _, args in
            guard let self, let tab, !tab.closed, let args else { return }
            let text = String(args.character)
            guard text.rangeOfCharacter(from: .controlCharacters) == nil else { return }
            args.handled = true
            if self.automatizacionActiva?.tab !== tab { tab.write(text) }
        }
        window.closed.addHandler { [weak self] _, _ in
            self?.ventanasPestana.removeValue(forKey: id)?.session.close()
        }
        ventanasPestana[id] = detached
        styleDetached(detached)
        renderDetached(detached)
        do {
            try window.activate()
            removeFromMain(tab)
            _ = try? vista.surface.focus(.programmatic)
        } catch {
            ventanasPestana[id] = nil
            status.text = error.localizedDescription
        }
    }

    private func returnToMain(_ id: ObjectIdentifier) {
        guard let detached = ventanasPestana.removeValue(forKey: id) else { return }
        terminals.append(detached.session)
        try? detached.window.close()
        try? window?.activate()
        showPanel(nil)
        select(detached.session)
    }

    private func styleDetached(_ detached: VentanaPestana) {
        let vista = detached.vista
        vista.invalidate()
        vista.filtro.apply(screenLook)
        vista.cellSize(width: anchoCelda, height: alturaLinea)
        vista.screen.fontFamily = FontFamily(settings.fuente)
        vista.screen.fontSize = Double(settings.tamano)
        vista.screen.lineHeight = alturaLinea
        vista.surface.background = paleta.map { brush($0.fondo) } ?? brushTransparente
        if let paleta { vista.screen.foreground = brush(paleta.texto) }
        else { _ = try? vista.screen.clearValue(TextBlock.foregroundProperty) }
    }

    private func renderDetached(_ detached: VentanaPestana) {
        detached.vista.render(detached.session, palette: paleta ?? paletaBase, cursorActive: true, brush: brush)
    }

    private func resizeDetached(_ detached: VentanaPestana) {
        let surface = detached.vista.surface
        guard surface.actualWidth > 20, surface.actualHeight > 16 else { return }
        detached.session.resize(cols: max(2, Int((surface.actualWidth - 20) / anchoCelda)),
                                rows: max(2, Int((surface.actualHeight - 16) / alturaLinea)))
        renderDetached(detached)
    }

    private func toggleSplit() {
        guard let selected else { return }
        divisionGuardadaApilada = nil
        if panelDividido {
            terminalesVisibles = [selected, nil]
            panelActivo = 0
        } else {
            guard let otra = terminals.first(where: { $0 !== selected && !$0.closed }) else {
                status.text = L("Abre otra pestaña para dividir la pantalla")
                return
            }
            terminalesVisibles = [selected, otra]
            panelActivo = 0
        }
        updateSplitLayout()
        showPanel(nil)
        select(selected)
    }

    private func updateSplitLayout() {
        let apilada = divisionGuardadaApilada ?? settings.divisionApilada
        filas[0].height = GridLength(value: 1, gridUnitType: .star)
        columnas[0].width = GridLength(value: 1, gridUnitType: .star)
        filas[1].height = GridLength(value: panelDividido && apilada ? 1 : 0, gridUnitType: .star)
        columnas[1].width = GridLength(value: panelDividido && !apilada ? 1 : 0, gridUnitType: .star)
        let otra = vistas[1].surface
        Grid.setRow(otra, apilada ? 1 : 0)
        Grid.setColumn(otra, apilada ? 0 : 1)
        otra.margin = Thickness(left: apilada ? 0 : 4, top: apilada ? 4 : 0, right: 0, bottom: 0)
        otra.visibility = panelDividido ? .visible : .collapsed
        dividir.content = panelDividido ? L("Cerrar división") : L("Dividir la pantalla")
    }

    private let brushTransparente = SolidColorBrush(Color(a: 0, r: 0, g: 0, b: 0))

    private func render() {
        for index in vistas.indices { render(index) }
    }

    private func render(_ index: Int) {
        vistas[index].render(terminalesVisibles[index], palette: paleta ?? paletaBase, cursorActive: index == panelActivo, brush: brush)
    }

    private func focusTerminal() { _ = try? vistas[panelActivo].surface.focus(.programmatic) }

    private var alturaLinea: Double { (Double(settings.tamano) * 19 / 15 * settings.interlineado).rounded() }

    private func resize() {
        for index in vistas.indices { resize(index) }
    }

    private func resize(_ index: Int) {
        let surface = vistas[index].surface
        guard let tab = terminalesVisibles[index], surface.actualWidth > 20, surface.actualHeight > 16 else { return }
        let cols = max(2, Int((surface.actualWidth - 20) / anchoCelda))
        let rows = max(2, Int((surface.actualHeight - 16) / alturaLinea))
        if let grabando, grabando.tab === tab, (cols, rows) != (tab.terminal.cols, tab.terminal.rows) {
            MainActor.assumeIsolated { grabando.recorder.bufferRealigned() }
        }
        tab.resize(cols: cols, rows: rows)
        render(index)
    }

    private func keySequence(_ key: Int32, tab: PestanaTerminal) -> String? {
        if GetKeyState(Int32(VK_CONTROL)) < 0, GetKeyState(Int32(VK_MENU)) >= 0, (65...90).contains(key),
           let scalar = UnicodeScalar(Int(key - 64)) {
            return String(scalar)
        }
        let arrowPrefix = tab.terminal.applicationCursor ? "\u{1b}O" : "\u{1b}["
        switch key {
        case 8: return "\u{7f}"
        case 9: return "\t"
        case 13: return "\r"
        case 27: return "\u{1b}"
        case 33: return "\u{1b}[5~"
        case 34: return "\u{1b}[6~"
        case 35: return arrowPrefix + "F"
        case 36: return arrowPrefix + "H"
        case 37: return arrowPrefix + "D"
        case 38: return arrowPrefix + "A"
        case 39: return arrowPrefix + "C"
        case 40: return arrowPrefix + "B"
        case 46: return "\u{1b}[3~"
        case 112...123:
            let index = Int(key) - 112
            let shift = GetKeyState(Int32(VK_SHIFT)) < 0
            let alt = GetKeyState(Int32(VK_MENU)) < 0
            let ctrl = GetKeyState(Int32(VK_CONTROL)) < 0
            let modifier = 1 + (shift ? 1 : 0) + (alt ? 2 : 0) + (ctrl ? 4 : 0)
            if index < 4 {
                let suffix = ["P", "Q", "R", "S"][index]
                return modifier == 1 ? "\u{1b}O\(suffix)" : "\u{1b}[1;\(modifier)\(suffix)"
            }
            let code = [15, 17, 18, 19, 20, 21, 23, 24][index - 4]
            return modifier == 1 ? "\u{1b}[\(code)~" : "\u{1b}[\(code);\(modifier)~"
        default: return nil
        }
    }
}