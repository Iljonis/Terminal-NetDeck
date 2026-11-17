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
    private let surface = Border()
    private let screen = TextBlock()
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
    private var settings = AjustesTerminal.cargar()
    private var rootView: Grid?
    /// Tamano de letra respecto a 15 pt (celda de 8,25 x 19 px): para calcular columnas y filas.
    private var fontScale = 1.0
    private var pasteFull = ""
    /// Sesiones editables en memoria: en modo demo es la unica copia (no se escribe a disco).
    private var library = SessionFile()
    private let isDemo = ProcessInfo.processInfo.environment["NETDECK_DESKTOP_DEMO"] == "1"

    override func onLaunched(_ args: LaunchActivatedEventArgs) {
        let window = Window()
        self.window = window
        window.title = "Terminal NetDeck"

        MainActor.assumeIsolated {
            sessions = SessionManager()
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
        let gear = Button()
        gear.content = "\u{2699}"
        gear.click.addHandler { [weak self] _, _ in self?.showAjustes() }
        for (control, id) in [(local as Control, "NuevaLocal"), (destination, "DestinoSSH"),
                              (connect, "ConectarSSH"), (closeButton, "CerrarPestana"),
                              (paste, "PegarSeguro"), (multiButton, "MultiExec"),
                              (gear, "Ajustes")] {
            AutomationProperties.setAutomationId(control, id)
            toolbar.children.append(control)
        }

        tabs.orientation = .horizontal
        tabs.spacing = 6
        let tabStrip = ScrollViewer()
        tabStrip.horizontalScrollBarVisibility = .auto
        tabStrip.verticalScrollBarVisibility = .disabled
        tabStrip.content = tabs

        screen.fontFamily = FontFamily("Consolas")
        screen.fontSize = 15
        screen.lineHeight = 19
        screen.isTextSelectionEnabled = true
        surface.padding = Thickness(left: 10, top: 8, right: 10, bottom: 8)
        AutomationProperties.setAutomationId(screen, "PantallaTerminal")
        AutomationProperties.setAutomationId(status, "EstadoTerminal")
        surface.child = screen
        surface.isTabStop = true
        surface.pointerPressed.addHandler { [weak self] _, _ in self?.focusTerminal() }
        surface.sizeChanged.addHandler { [weak self] _, _ in self?.resize() }
        surface.keyDown.addHandler { [weak self] _, args in
            guard let self, let args, let bytes = self.keySequence(args.key.rawValue),
                  let selected = self.selected, !selected.closed else { return }
            args.handled = true
            selected.write(bytes)
        }
        surface.characterReceived.addHandler { [weak self] _, args in
            guard let args, let selected = self?.selected, !selected.closed else { return }
            let text = String(args.character)
            guard text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
            args.handled = true
            selected.write(text)
        }

        for (index, view) in [toolbar as FrameworkElement, tabStrip, surface, status].enumerated() {
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
        Grid.setRow(explorador.view, Int32(2))
        layout.children.append(explorador.view)
        explorador.onClose = { [weak self] in self?.showPanel(nil) }
        explorador.enqueue = { [weak self] action in
            _ = try? self?.window?.dispatcherQueue?.tryEnqueue { action() }
        }
        for panel in [pegado, multi] {
            Grid.setRow(panel.view, Int32(2))
            layout.children.append(panel.view)
            panel.onCancel = { [weak self] in self?.showPanel(nil) }
        }
        pegado.onConfirm = { [weak self] text in self?.confirmPaste(text) }
        multi.onConfirm = { [weak self] text in self?.confirmMultiExec(text) }
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
        } catch {
            print(error.localizedDescription)
        }
    }

    override func onShutdown() {
        for session in terminals { session.close() }
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
        surface.visibility = panel == nil ? .visible : .collapsed
        editor.view.visibility = panel === editor.view ? .visible : .collapsed
        ajustes.view.visibility = panel === ajustes.view ? .visible : .collapsed
        pegado.view.visibility = panel === pegado.view ? .visible : .collapsed
        multi.view.visibility = panel === multi.view ? .visible : .collapsed
        explorador.view.visibility = panel === explorador.view ? .visible : .collapsed
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

    /// Una linea se pega directamente; varias, tras una vista previa (un pegado con saltos ejecutaria cada linea).
    private func safePaste() {
        guard let selected, !selected.closed else {
            status.text = L("No hay ning\u{00FA}n terminal abierto")
            return
        }
        guard let text = pasteboardText(), !text.isEmpty else {
            status.text = L("El portapapeles no tiene texto")
            return
        }
        let trimmed = text.trimmingCharacters(in: .newlines)
        guard trimmed.contains(where: \.isNewline) else {
            selected.paste(trimmed)
            return
        }
        let lines = trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        let preview = trimmed.count > 2000 ? String(trimmed.prefix(2000)) + "\n\u{2026}" : trimmed
        status.text = ""
        pasteFull = trimmed
        pegado.show(title: L("Pegar varias l\u{00ED}neas"),
                    hint: L("Se van a pegar \(lines) l\u{00ED}neas (\(trimmed.count) caracteres). Rev\u{00ED}salas antes de enviarlas.")
                        + (trimmed.count > 2000 ? " " + L("Se ven los primeros 2000 caracteres; se pega todo.") : ""),
                    text: preview, editable: false)
        showPanel(pegado.view)
    }

    private func confirmPaste(_ preview: String) {
        showPanel(nil)
        guard let selected, !selected.closed else { return }
        selected.paste(pasteFull)
        pasteFull = ""
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
        let targets = terminals.filter { !$0.closed && !$0.route.isLocal && [.ssh, .telnet].contains($0.route.transport) }
        showPanel(nil)
        guard !targets.isEmpty else {
            status.text = L("No hay pesta\u{00F1}as SSH o Telnet abiertas")
            return
        }
        for tab in targets { tab.write(command.replacingOccurrences(of: "\n", with: "\r") + "\r") }
        status.text = L("Comando enviado a \(targets.count) pesta\u{00F1}as")
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

    // MARK: - ajustes

    private func showAjustes() {
        status.text = ""
        ajustes.show(settings)
        showPanel(ajustes.view)
    }

    private func hideAjustes() { showPanel(nil) }

    private func saveAjustes(_ new: AjustesTerminal) {
        settings = new
        new.guardar()
        applySettings(new)
        hideAjustes()
        status.text = L("Ajustes guardados")
    }

    /// Fuente y tamano al terminal; el tema, a la ventana (Sistema = el de Windows).
    private func applySettings(_ a: AjustesTerminal) {
        screen.fontFamily = FontFamily(a.fuente)
        screen.fontSize = Double(a.tamano)
        screen.lineHeight = (Double(a.tamano) * 19 / 15).rounded()
        fontScale = Double(a.tamano) / 15
        let theme: Int32 = a.tema == "Claro" ? 1 : (a.tema == "Oscuro" ? 2 : 0)
        rootView?.requestedTheme = ElementTheme(rawValue: theme)
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

    private func open(_ route: ConnectionRoute) {
        if route.transport == .sftp {
            openSFTP(route)
            return
        }
        if route.transport == .ftp {
            status.text = L("FTP no disponible a\u{00FA}n en la versi\u{00F3}n de Windows")
            return
        }
        do {
            if let problem = route.launchProblem() { throw RemoteError(problem) }
            let session = try PestanaTerminal(route: route)
            let queue = window?.dispatcherQueue
            terminals.append(session)
            select(session)
            session.observe(enqueue: { action in
                (try? queue?.tryEnqueue { action() }) == true
            }, changed: { [weak self, weak session] in
                guard let self, self.selected === session else { return }
                self.render()
            })
        } catch {
            status.text = L("No se puede abrir \u{00AB}\(route.title)\u{00BB}: \(error.localizedDescription)")
        }
    }

    private func select(_ session: PestanaTerminal?) {
        selected = session
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
        focusTerminal()
    }

    private func closeSelected() {
        guard let selected, let index = terminals.firstIndex(where: { $0 === selected }) else { return }
        selected.close()
        terminals.remove(at: index)
        select(terminals.isEmpty ? nil : terminals[min(index, terminals.count - 1)])
    }

    private func render() {
        screen.text = selected?.screen ?? ""
        status.text = selected?.closed == true ? L("Conexi\u{00F3}n cerrada") : ""
    }

    private func focusTerminal() { _ = try? surface.focus(.programmatic) }

    private func resize() {
        guard surface.actualWidth > 20, surface.actualHeight > 16 else { return }
        selected?.resize(cols: max(2, Int((surface.actualWidth - 20) / (8.25 * fontScale))),
                         rows: max(2, Int((surface.actualHeight - 16) / (19 * fontScale))))
        render()
    }

    private func keySequence(_ key: Int32) -> String? {
        if GetKeyState(Int32(VK_CONTROL)) < 0, GetKeyState(Int32(VK_MENU)) >= 0, (65...90).contains(key),
           let scalar = UnicodeScalar(Int(key - 64)) {
            return String(scalar)
        }
        let arrowPrefix = selected?.terminal.applicationCursor == true ? "\u{1b}O" : "\u{1b}["
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