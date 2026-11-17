import Foundation
import NetDeckCore
import struct UWP.Color
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
    private weak var selected: PestanaTerminal?
    private var sessions: SessionManager!
    private let sidebar = StackPanel()
    private let editor = PanelEditorSesion()
    private let ajustes = PanelAjustes()
    private let pegado = PanelTexto(idPrefix: "PegarSeguro")
    private let multi = PanelTexto(idPrefix: "MultiExec")
    private let explorador = ExploradorSFTP()
    private let accesoFTP = PanelAccesoFTP()
    private let macros = PanelMacros()
    private let macroConfirm = PanelTexto(idPrefix: "MacroConfirmar")
    private var macrosDemo = MacroLibrary()
    private var automatizacionActiva: (tab: PestanaTerminal, abort: AbortSwitch)?
    private let pararAutomatizacion = Button()
    private let tuneles = PanelTuneles()
    private let asistente = AsistenteInicio()
    private let actualizacion = PanelTexto(idPrefix: "Actualizacion")
    private var pendingUpdate: UpdateInfo?
    private var tunnelManager: TunnelManager!
    private var settings = AjustesTerminal.cargar()
    private var rootView: Grid?
    /// Tamano de letra respecto a 15 pt (celda de 8,25 x 19 px): para calcular columnas y filas.
    private var fontScale = 1.0
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
        let macroButton = Button()
        macroButton.content = L("Macros")
        macroButton.click.addHandler { [weak self] _, _ in self?.showMacros() }
        pararAutomatizacion.content = L("Detener envío")
        pararAutomatizacion.visibility = .collapsed
        pararAutomatizacion.click.addHandler { [weak self] _, _ in self?.automatizacionActiva?.abort.trip() }
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
                              (macroButton, "Macros"), (pararAutomatizacion, "Macros_Parar"), (dividir, "DividirTerminal"),
                              (workspaceButton, "Espacios"), (searchButton, "BuscarTerminal"), (gear, "Ajustes")] {
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
                tab.write(bytes)
            }
            surface.characterReceived.addHandler { [weak self] _, args in
                guard let self, let args, let tab = self.terminalesVisibles[index], !tab.closed else { return }
                let text = String(args.character)
                guard text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
                args.handled = true
                if self.automatizacionActiva?.tab !== tab { tab.write(text) }
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
        for panel in [pegado, multi, actualizacion, macroConfirm] {
            Grid.setRow(panel.view, Int32(2))
            layout.children.append(panel.view)
            panel.onCancel = { [weak self] in self?.showPanel(nil) }
        }
        pegado.onConfirm = { [weak self] _ in self?.confirmPaste() }
        multi.onConfirm = { [weak self] text in self?.confirmMultiExec(text) }
        actualizacion.onConfirm = { [weak self] _ in self?.installUpdate() }
        for view in [espacios.view, buscarTerminal.view] {
            Grid.setRow(view, Int32(2))
            layout.children.append(view)
        }
        espacios.onOpen = { [weak self] in self?.restoreWorkspace($0) }
        espacios.onSave = { [weak self] in self?.saveWorkspace($0) }
        espacios.onClose = { [weak self] in self?.showPanel(nil) }
        buscarTerminal.onSearch = { [weak self] consulta in
            guard let self, let tab = self.pestañaBuscada else { return }
            let coincidencias = tab.buscarHistorial(consulta)
            self.buscarTerminal.show(lines: coincidencias.lines, total: coincidencias.total)
        }
        buscarTerminal.onClose = { [weak self] in self?.showPanel(nil) }
        Grid.setRow(macros.view, Int32(2))
        layout.children.append(macros.view)
        macros.onClose = { [weak self] in self?.showPanel(nil) }
        macros.onSave = { [weak self] in self?.saveMacro($0) }
        macros.onPlay = { [weak self] in self?.playMacro($0) }
        macroConfirm.onCancel = { [weak self] in self?.showMacros() }
        ajustes.onCheckUpdates = { [weak self] in self?.checkUpdates() }
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
        } catch {
            print(error.localizedDescription)
        }
    }

    override func onShutdown() {
        for session in terminals { session.close() }
        MainActor.assumeIsolated { tunnelManager.stopAll() }
    }

    private func buildSidebar() {
        sidebar.children.clear()
        let grupos = MainActor.assumeIsolated { sessions.groups }
        for (nombreGrupo, perfiles) in grupos {
            let header = TextBlock()
            header.text = nombreGrupo.uppercased()
            header.fontSize = 10
            header.margin = Thickness(left: 8, top: 10, right: 8, bottom: 2)
            header.opacity = 0.6
            sidebar.children.append(header)
            for perfil in perfiles {
                let fila = Grid()
                let colNombre = ColumnDefinition()
                colNombre.width = GridLength(value: 1, gridUnitType: .star)
                let colEditar = ColumnDefinition()
                colEditar.width = GridLength(value: 1, gridUnitType: .auto)
                fila.columnDefinitions.append(colNombre)
                fila.columnDefinitions.append(colEditar)
                let colSFTP = ColumnDefinition()
                colSFTP.width = GridLength(value: 1, gridUnitType: .auto)
                fila.columnDefinitions.append(colSFTP)
                let btn = Button()
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
                btn.content = etiqueta
                btn.horizontalAlignment = .stretch
                btn.margin = Thickness(left: 4, top: 1, right: 4, bottom: 1)
                AutomationProperties.setAutomationId(btn, "Sesion_\(perfil.name)")
                btn.click.addHandler { [weak self] _, _ in
                    self?.openProfile(perfil)
                }
                let editar = Button()
                editar.content = "\u{270E}"
                editar.margin = Thickness(left: 0, top: 1, right: 4, bottom: 1)
                AutomationProperties.setAutomationId(editar, "Editar_\(perfil.name)")
                editar.click.addHandler { [weak self] _, _ in self?.editSession(perfil) }
                Grid.setColumn(btn, Int32(0))
                Grid.setColumn(editar, Int32(1))
                fila.children.append(btn)
                fila.children.append(editar)
                if perfil.transport == .ssh || perfil.transport == .sftp {
                    let carpeta = Button()
                    carpeta.content = "\u{1F4C2}"
                    carpeta.margin = Thickness(left: 0, top: 1, right: 4, bottom: 1)
                    AutomationProperties.setAutomationId(carpeta, "SFTP_\(perfil.name)")
                    carpeta.click.addHandler { [weak self] _, _ in self?.openSFTPProfile(perfil) }
                    Grid.setColumn(carpeta, Int32(2))
                    fila.children.append(carpeta)
                }
                sidebar.children.append(fila)
            }
        }
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
        pegado.view.visibility = panel === pegado.view ? .visible : .collapsed
        if panel !== pegado.view { pendingPaste = nil }
        multi.view.visibility = panel === multi.view ? .visible : .collapsed
        accesoFTP.view.visibility = panel === accesoFTP.view ? .visible : .collapsed
        if panel !== accesoFTP.view { accesoFTP.clear() }
        explorador.view.visibility = panel === explorador.view ? .visible : .collapsed
        tuneles.view.visibility = panel === tuneles.view ? .visible : .collapsed
        asistente.view.visibility = panel === asistente.view ? .visible : .collapsed
        actualizacion.view.visibility = panel === actualizacion.view ? .visible : .collapsed
        espacios.view.visibility = panel === espacios.view ? .visible : .collapsed
        buscarTerminal.view.visibility = panel === buscarTerminal.view ? .visible : .collapsed
        macros.view.visibility = panel === macros.view ? .visible : .collapsed
        macroConfirm.view.visibility = panel === macroConfirm.view ? .visible : .collapsed
        if panel !== macroConfirm.view { macroConfirm.onConfirm = nil }
        if panel == nil { focusTerminal() }
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
        guard library.uniqueName(macro.name) == macro.name else {
            status.text = L("ya hay una macro con ese nombre")
            return
        }
        library.macros.append(macro)
        do {
            if isDemo { macrosDemo = library } else { try library.save() }
            macros.clearDraft()
            macros.show(library, selected: macro.id)
            status.text = L("✓ Macro «\(macro.name)» guardada")
        } catch {
            status.text = L("No se puede guardar: \(error.localizedDescription)")
        }
    }

    private func playMacro(_ macro: Macro) {
        guard let tab = selected, !tab.closed, !tab.route.isLocal,
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
        guard selected === tab, !tab.closed else { return }
        let abort = AbortSwitch()
        let prompt = MainActor.assumeIsolated {
            let profile = tab.route.transientProfile ?? tab.route.sessionName.flatMap(sessions.profile(named:))?.terminal
            return profile.flatMap { PromptRule($0.prompt) }
        }
        let io = MainActor.assumeIsolated { EntradaMacro(tab: tab, promptRule: prompt) }
        guard MainActor.assumeIsolated({ PromptRule.isPrompt(io.cursorLine, custom: prompt) }) else {
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

    /// «Buscar actualizaciones»: sólo con el clic (nada se comprueba solo). Si hay una, se enseña con sus notas y el botón
    /// «Descargar e instalar»; no se descarga nada antes.
    private func checkUpdates() {
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
        paleta = TemasTerminal.tema(id: id).map(PaletaTerminal.init(tema:))
        for vista in vistas {
            vista.invalidate()
            vista.surface.background = paleta.map { brush($0.fondo) } ?? brushTransparente
            if let paleta { vista.screen.foreground = brush(paleta.texto) }
            else { _ = try? vista.screen.clearValue(TextBlock.foregroundProperty) }
        }
        for tab in terminals { tab.apply(palette: paleta) }
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

    private func showAjustes() {
        status.text = ""
        ajustes.show(settings)
        showPanel(ajustes.view)
    }

    private func hideAjustes() { showPanel(nil) }

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
        for vista in vistas {
            vista.screen.fontFamily = FontFamily(a.fuente)
            vista.screen.fontSize = Double(a.tamano)
            vista.screen.lineHeight = alturaLinea
        }
        fontScale = Double(a.tamano) / 15
        updateSplitLayout()
        let theme: Int32 = a.tema == "Claro" ? 1 : (a.tema == "Oscuro" ? 2 : 0)
        rootView?.requestedTheme = ElementTheme(rawValue: theme)
        applyTerminalTheme(a.temaTerminal)
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
            open(ruta)
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
            select(session)
            session.observe(enqueue: { action in
                (try? queue?.tryEnqueue { action() }) == true
            }, changed: { [weak self, weak session] in
                guard let self, let session else { return }
                if session.closed, self.automatizacionActiva?.tab === session { self.automatizacionActiva?.abort.trip() }
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
            tab.groupName = "terminales"
            tab.isChecked = candidate === session
            tab.click.addHandler { [weak self, weak candidate] _, _ in self?.select(candidate) }
            tabs.children.append(tab)
        }
        closeButton.isEnabled = session != nil
        resize()
        render()
        if focus { focusTerminal() }
    }

    private func closeSelected() {
        guard let selected, let index = terminals.firstIndex(where: { $0 === selected }) else { return }
        if automatizacionActiva?.tab === selected { automatizacionActiva?.abort.trip() }
        selected.close()
        terminals.remove(at: index)
        if panelDividido {
            let otra = terminalesVisibles[1 - panelActivo]
            terminalesVisibles = [otra, nil]
            panelActivo = 0
            updateSplitLayout()
            select(otra)
        } else {
            select(terminals.isEmpty ? nil : terminals[min(index, terminals.count - 1)])
        }
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
        vistas[index].render(terminalesVisibles[index], palette: paleta, brush: brush)
    }

    private func focusTerminal() { _ = try? vistas[panelActivo].surface.focus(.programmatic) }

    private var alturaLinea: Double { (Double(settings.tamano) * 19 / 15 * settings.interlineado).rounded() }

    private func resize() {
        for index in vistas.indices { resize(index) }
    }

    private func resize(_ index: Int) {
        let surface = vistas[index].surface
        guard let tab = terminalesVisibles[index], surface.actualWidth > 20, surface.actualHeight > 16 else { return }
        tab.resize(cols: max(2, Int((surface.actualWidth - 20) / (8.25 * fontScale))),
                   rows: max(2, Int((surface.actualHeight - 16) / alturaLinea)))
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
        default: return nil
        }
    }
}