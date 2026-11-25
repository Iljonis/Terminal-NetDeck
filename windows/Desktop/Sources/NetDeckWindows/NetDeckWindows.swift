import Foundation
import NetDeckCore
import struct UWP.Color
import class UWP.UISettings
import struct UWP.FontWeight
import struct WindowsFoundation.Point
import WinSDK
import WinUI

final class NetDeckWindows: SwiftApplication {
    private var window: Window?
    private let tabs = StackPanel()
    private let destination = TextBox()
    private let terminalGrid = Grid()
    private var vistas: [VistaTerminal] = []
    private var marcosTerminal: [Border] = []
    private var cabecerasTerminal: [Grid] = []
    private var filasTerminal: [Grid] = []
    private var separadoresTerminal: [Border] = []
    private var pesosDivision: [String: [Double]] = [:]
    private var terminalesVisibles: [PestanaTerminal?] = [nil]
    private var disposicionMostrada: DisposicionTerminal?
    private var panelesMostrados = 0
    private var vistaGuardada: (modo: DisposicionTerminal, paneles: [PestanaTerminal])?
    private var panelActivo = 0
    private var modoDivision: DisposicionTerminal?
    private let espacios = PanelEspacios()
    private let buscarTerminal = PanelBuscarTerminal()
    private weak var pestañaBuscada: PestanaTerminal?
    private var espaciosDemo = WorkspaceLibrary()
    private var panelDividido: Bool { modoDivision != nil }
    private let dividir = Button()
    private let status = TextBlock()
    private let sugerirClave = Button()
    private var clavesTerminal: [ObjectIdentifier: ContrasenasTerminal] = [:]
    private lazy var ledgerClaves = CredentialLedger.shared()
    private var volverAContrasenas = false
    private var credencialesDisponibles: [String] = []
    private let closeButton = Button()
    private var terminals: [PestanaTerminal] = []
    private var arrastrePestana: (sesion: PestanaTerminal, x: Double, y: Double, activo: Bool)?
    private var botonIzquierdoAbajo = false
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
    private let listas = PanelListas()
    private let listasAjustes = PanelListas()
    private var listasDemo = ListLibrary()
    private var loteListas: AbortSwitch?
    private let ajustes = PanelAjustes()
    private let selectorColor = PanelSelectorColor()
    private let reglas = PanelTexto(idPrefix: "Resaltado")
    private var resaltadoDemo: String?
    private var highlightConfig: HighlightConfig?
    private var screenLook: ScreenLook?
    private var contrasteActivo = false
    private var temaGlobal: Theme?
    private let paletaBase = PaletaTerminal(tema: Theme.builtIn)
    private let pegado = PanelTexto(idPrefix: "PegarSeguro")
    private let multi = PanelTexto(idPrefix: "MultiExec")
    private let confirmarMulti = PanelTexto(idPrefix: "MultiExec_Confirmar")
    private let botonMulti = Button()
    private var multiActivo = false
    private var excluidasMulti: Set<ObjectIdentifier> = []
    private var entrandoPorLista: Set<ObjectIdentifier> = []
    private lazy var grupoMulti = MainActor.assumeIsolated { MultiExecGroup() }
    private let explorador = ExploradorSFTP()
    private let marcoSFTPLateral = Grid()
    private let zonaSFTPLateral = Border()
    private let asaSFTP = Border()
    private var arrastreSFTP: (x: Double, ancho: Double)?
    private let esperaSFTP = StackPanel()
    private let textoEsperaSFTP = TextBlock()
    private let conectarLateral = Button()
    private final class ExploradorLateral {
        let explorador = ExploradorSFTP()
        let ruta: ConnectionRoute
        var iniciado = false
        var visible = true
        init(_ ruta: ConnectionRoute) { self.ruta = ruta }
    }
    private var panelesSFTP: [ObjectIdentifier: ExploradorLateral] = [:]
    private lazy var ajustesSFTP = SFTPPanelStore()
    private let accesoFTP = PanelAccesoFTP()
    private let botones = PanelBotones()
    private let confirmarBoton = PanelTexto(idPrefix: "Botones_Confirmar")
    private var archivoBotones = ButtonFile()
    private let llavero = PanelLlavero()
    private let borrarSesion = PanelTexto(idPrefix: "BorrarSesion")
    private let hojaConexion = HojaConexion()
    private let buscarRegistros = PanelBuscarRegistros()
    private let menuBuscar = MenuLista()
    private let menuAjustes = MenuLista()
    private let edicionRemota = PanelEdicionRemota()
    private let panelImportador = PanelImportador()
    private var favoritas: Set<String> = []
    private var recientes: [String] = []
    private var favoritasURL: URL { AppPaths.netdeck.appendingPathComponent("favoritas") }
    private var recientesURL: URL { AppPaths.netdeck.appendingPathComponent("recientes") }
    private var plegadosDemo: Set<String> = []
    private var plegados: Set<String> {
        get { isDemo ? plegadosDemo : Set(UserDefaults.standard.stringArray(forKey: "ndGruposPlegados") ?? []) }
        set {
            if isDemo { plegadosDemo = newValue }
            else { UserDefaults.standard.set(Array(newValue), forKey: "ndGruposPlegados") }
        }
    }
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
    private var settings = ProcessInfo.processInfo.environment["NETDECK_DESKTOP_DEMO"] == "1"
        ? AjustesTerminal() : AjustesTerminal.cargar()
    private var rootView: Grid?
    /// Ancho medido de la fuente monoespaciada para las columnas de ConPTY.
    /// Colores del tema elegido para el terminal (nil: los del sistema, texto liso).
    private var paleta: PaletaTerminal?
    private var pinceles: [RGB: SolidColorBrush] = [:]
    private var pendingPaste: (tab: PestanaTerminal, text: String, dangerous: Bool)?
    /// Sesiones editables en memoria: en modo demo es la unica copia (no se escribe a disco).
    private var library = SessionFile()
    private let isDemo = ProcessInfo.processInfo.environment["NETDECK_DESKTOP_DEMO"] == "1"

    // Marco como el del Mac (EstiloMac): los colores salen del tema del terminal.
    private var estilo = EstiloMac(tema: nil)
    private let marco = Grid()
    private let bordeSuperior = Border()
    private let barraSuperior = Grid()
    private let tabsScroll = ScrollViewer()
    private var iconosConOcultosAplicados: Set<String> = []
    private let iconos = StackPanel()
    private let barraBotonesFondo = Border()
    private let barraBotonesGrid = Grid()
    private var grupoBotones: String?
    private let colLateral = ColumnDefinition()
    private let ladoBorde = Border()
    private let buscarSesion = TextBox()
    private let pieBorde = Border()
    private let pieLateral = Grid()
    private let origenSesiones = TextBlock()
    private var sesionLateral: String?
    private var botonesSesion: [(String, Button)] = []
    private static let clavesSeccionesLaterales = ["\t★", "\t↻"]
    private let barraEstadoBorde = Border()
    private let temaEtiqueta = TextBlock()
    private let reloj = TextBlock()
    /// El tema con el que se dibujó el marco (nil: aún no): sólo se rehace al cambiarlo.
    private var temaMarco: Theme?
    private var fuenteMarco: String?
    private let aparienciaWindows = UISettings()
    private var botonesPorGruposAplicado: Bool?
    /// Nombres puestos a mano a las pestañas («Renombrar»).
    private var nombresPestana: [ObjectIdentifier: String] = [:]
    private let renombrar = PanelTexto(idPrefix: "RenombrarPestana")
    private let menuNuevo = MenuNuevo()
    private let confirmarGrupo = PanelTexto(idPrefix: "AbrirGrupo")
    /// Ventanas emergentes (Ajustes, Botones, Macros…): una tarjeta encima de la ventana, como las hojas del Mac.
    private let capaEmergente = Grid()
    private let tarjeta = Border()
    private let contenidoTarjeta = Grid()
    private let cerrarTarjeta = Button()
    private var hayEmergente: Bool { capaEmergente.visibility == .visible }

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
                SessionFile.repairPermissions()
                sessions.load(from: SessionFile.defaultURL)
            } else {
                sessions.load()
            }
        }

        // Marco como el del Mac: arriba las pestañas y los iconos (en la barra de título), debajo los botones de
        // órdenes, en medio la barra lateral y el terminal, y abajo la barra de estado.
        window.extendsContentIntoTitleBar = true
        // (filas: barra superior, botones «arriba», centro, botones «abajo», estado)
        for alto in [GridUnitType.auto, .auto, .star, .auto, .auto] {
            let fila = RowDefinition()
            fila.height = GridLength(value: 1, gridUnitType: alto)
            marco.rowDefinitions.append(fila)
        }

        // Barra superior: pestañas | zona para arrastrar la ventana | iconos | sitio para los botones de Windows
        barraSuperior.height = 40
        for ancho in [GridLength(value: 1, gridUnitType: .auto), GridLength(value: 1, gridUnitType: .star),
                      GridLength(value: 1, gridUnitType: .auto), GridLength(value: 140, gridUnitType: .pixel)] {
            let columna = ColumnDefinition()
            columna.width = ancho
            barraSuperior.columnDefinitions.append(columna)
        }
        tabs.orientation = .horizontal
        tabs.spacing = 4
        tabs.verticalAlignment = .center
        tabsScroll.content = tabs
        tabsScroll.horizontalScrollBarVisibility = .auto
        tabsScroll.verticalScrollBarVisibility = .disabled
        tabsScroll.verticalAlignment = .center
        tabsScroll.margin = Thickness(left: 10, top: 0, right: 6, bottom: 0)
        tabsScroll.horizontalScrollMode = .enabled
        tabsScroll.pointerWheelChanged.addHandler { [weak self] _, args in
            guard let self, let args, tabsScroll.scrollableWidth > 0,
                  let punto = try? args.getCurrentPoint(tabsScroll) else { return }
            let delta = Double(punto.properties.mouseWheelDelta)
            guard delta != 0 else { return }
            let destino = min(tabsScroll.scrollableWidth,
                              max(0, tabsScroll.horizontalOffset - delta * 0.75))
            _ = try? tabsScroll.changeView(destino, nil, nil, true)
            args.handled = true
        }
        configurarArrastrePestanas()
        let arrastre = Grid()
        arrastre.background = estilo.transparente
        iconos.orientation = .horizontal
        iconos.spacing = 6
        iconos.verticalAlignment = .center
        iconos.margin = Thickness(left: 6, top: 0, right: 10, bottom: 0)
        Grid.setColumn(tabsScroll, Int32(0))
        Grid.setColumn(arrastre, Int32(1))
        Grid.setColumn(iconos, Int32(2))
        barraSuperior.children.append(tabsScroll)
        barraSuperior.children.append(arrastre)
        barraSuperior.children.append(iconos)
        barraSuperior.sizeChanged.addHandler { [weak self] _, _ in self?.ajustarAnchoPestanas() }
        iconos.sizeChanged.addHandler { [weak self] _, _ in self?.ajustarAnchoPestanas() }
        try? window.setTitleBar(arrastre)
        bordeSuperior.child = barraSuperior
        bordeSuperior.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 2)

        // Botones de órdenes (botones.txt): desplegable del grupo, sus botones y el lápiz para editarlos.
        let colChips = ColumnDefinition()
        colChips.width = GridLength(value: 1, gridUnitType: .star)
        let colLapiz = ColumnDefinition()
        colLapiz.width = GridLength(value: 1, gridUnitType: .auto)
        barraBotonesGrid.columnDefinitions.append(colChips)
        barraBotonesGrid.columnDefinitions.append(colLapiz)
        barraBotonesGrid.height = 34
        barraBotonesGrid.margin = Thickness(left: 10, top: 0, right: 10, bottom: 0)
        barraBotonesFondo.child = barraBotonesGrid
        barraBotonesFondo.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 1)
        archivoBotones = isDemo ? ButtonFile.samples : ((try? readCommandButtons()) ?? ButtonFile())

        // Rejilla central: barra lateral | area principal
        let root = Grid()
        colLateral.width = GridLength(value: 268, gridUnitType: .pixel)
        let colPrincipal = ColumnDefinition()
        colPrincipal.width = GridLength(value: 1, gridUnitType: .star)
        root.columnDefinitions.append(colLateral)
        root.columnDefinitions.append(colPrincipal)

        // Barra lateral: buscador, sesiones por carpetas y pie de iconos
        buscarSesion.placeholderText = L("Buscar sesi\u{00F3}n, equipo, IP, usuario o tipo")
        buscarSesion.margin = Thickness(left: 10, top: 10, right: 10, bottom: 6)
        buscarSesion.cornerRadius = EstiloMac.radio(7)
        buscarSesion.textChanged.addHandler { [weak self] _, _ in self?.buildSidebar() }
        AutomationProperties.setAutomationId(buscarSesion, "Sidebar_Buscar")
        sidebar.orientation = .vertical
        sidebar.spacing = 1
        sidebar.margin = Thickness(left: 6, top: 0, right: 6, bottom: 8)
        let sideScroll = ScrollViewer()
        sideScroll.content = sidebar
        sideScroll.verticalScrollBarVisibility = .auto
        sideScroll.horizontalScrollBarVisibility = .disabled
        pieLateral.columnSpacing = 6
        pieLateral.margin = Thickness(left: 8, top: 5, right: 8, bottom: 5)
        pieBorde.child = pieLateral
        pieBorde.borderThickness = Thickness(left: 0, top: 1, right: 0, bottom: 0)
        let sideColumn = Grid()
        for alto in [GridUnitType.auto, .star, .auto] {
            let fila = RowDefinition()
            fila.height = GridLength(value: 1, gridUnitType: alto)
            sideColumn.rowDefinitions.append(fila)
        }
        Grid.setRow(buscarSesion, Int32(0))
        Grid.setRow(sideScroll, Int32(1))
        Grid.setRow(pieBorde, Int32(2))
        sideColumn.children.append(buscarSesion)
        sideColumn.children.append(sideScroll)
        sideColumn.children.append(pieBorde)
        ladoBorde.child = sideColumn
        ladoBorde.borderThickness = Thickness(left: 0, top: 0, right: 1, bottom: 0)
        Grid.setColumn(ladoBorde, Int32(0))
        root.children.append(ladoBorde)

        // Area principal: el terminal (y los paneles, que lo tapan)
        let layout = Grid()
        layout.margin = Thickness(left: 6, top: 4, right: 4, bottom: 2)
        Grid.setColumn(layout, Int32(1))

        destination.placeholderText = "SSH \u{00B7} admin@core-01"
        destination.keyDown.addHandler { [weak self] _, args in
            guard let args, args.key.rawValue == 13 else { return }
            args.handled = true
            self?.connect()
        }
        closeButton.click.addHandler { [weak self] _, _ in self?.closeSelected() }
        pararAutomatizacion.visibility = .collapsed
        pararAutomatizacion.click.addHandler { [weak self] _, _ in self?.automatizacionActiva?.abort.trip() }
        pararGrabacion.visibility = .collapsed
        pararGrabacion.click.addHandler { [weak self] _, _ in self?.finishRecording() }

        // Barra de estado: mensajes a la izquierda; el tema y la hora a la derecha, como en el Mac.
        let barraEstado = Grid()
        barraEstado.height = 26
        for ancho in [GridUnitType.star, .auto, .auto, .auto] {
            let columna = ColumnDefinition()
            columna.width = GridLength(value: 1, gridUnitType: ancho)
            barraEstado.columnDefinitions.append(columna)
        }
        status.fontSize = 10.5
        status.verticalAlignment = .center
        status.textTrimming = .characterEllipsis
        status.margin = Thickness(left: 12, top: 0, right: 14, bottom: 0)
        temaEtiqueta.fontSize = 10.5
        temaEtiqueta.characterSpacing = 150
        temaEtiqueta.verticalAlignment = .center
        temaEtiqueta.margin = Thickness(left: 0, top: 0, right: 14, bottom: 0)
        reloj.fontSize = 10.5
        reloj.fontWeight = FontWeight(weight: 500)
        reloj.verticalAlignment = .center
        reloj.margin = Thickness(left: 0, top: 0, right: 12, bottom: 0)
        Grid.setColumn(status, Int32(0))
        sugerirClave.visibility = .collapsed
        sugerirClave.click.addHandler { [weak self] _, _ in self?.usarSugerenciaClave() }
        Grid.setColumn(sugerirClave, 1)
        Grid.setColumn(temaEtiqueta, 2)
        Grid.setColumn(reloj, 3)
        barraEstado.children.append(status)
        barraEstado.children.append(sugerirClave)
        barraEstado.children.append(temaEtiqueta)
        barraEstado.children.append(reloj)
        barraEstadoBorde.child = barraEstado
        barraEstadoBorde.borderThickness = Thickness(left: 0, top: 1, right: 0, bottom: 0)
        arrancarReloj()

        Grid.setRow(bordeSuperior, Int32(0))
        Grid.setRow(barraBotonesFondo, Int32(1))
        Grid.setRow(root, Int32(2))
        Grid.setRow(barraEstadoBorde, Int32(4))
        marco.children.append(bordeSuperior)
        marco.children.append(barraBotonesFondo)
        marco.children.append(root)
        marco.children.append(barraEstadoBorde)

        // Capa de ventanas emergentes: el terminal sigue detrás (oscurecido); se cierra con la ✕ o con Esc, no al
        // pulsar fuera, para no perder lo escrito en un formulario.
        capaEmergente.background = SolidColorBrush(Color(a: 120, r: 0, g: 0, b: 0))
        capaEmergente.visibility = .collapsed
        cerrarTarjeta.click.addHandler { [weak self] _, _ in self?.showPanel(nil) }
        cerrarTarjeta.horizontalAlignment = .right
        cerrarTarjeta.verticalAlignment = .top
        cerrarTarjeta.margin = Thickness(left: 0, top: 6, right: 6, bottom: 0)
        let interior = Grid()
        interior.children.append(contenidoTarjeta)
        interior.children.append(cerrarTarjeta)
        tarjeta.child = interior
        tarjeta.maxWidth = 900
        tarjeta.margin = Thickness(left: 40, top: 20, right: 40, bottom: 20)
        tarjeta.padding = Thickness(left: 8, top: 8, right: 8, bottom: 8)
        tarjeta.cornerRadius = EstiloMac.radio(12)
        tarjeta.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        tarjeta.verticalAlignment = .center
        capaEmergente.children.append(tarjeta)
        capaEmergente.sizeChanged.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.tarjeta.maxHeight = max(200, self.capaEmergente.actualHeight - 40)
            self.ajustes.ajustarAlto(self.capaEmergente.actualHeight - 60)
        }
        Grid.setRow(capaEmergente, Int32(1))
        Grid.setRowSpan(capaEmergente, Int32(4))
        marco.children.append(capaEmergente)
        // Pulsar fuera de los Ajustes los cierra, como en el Mac; los demás paneles no (se perdería lo escrito).
        tarjeta.pointerPressed.addHandler { _, args in args?.handled = true }
        capaEmergente.pointerPressed.addHandler { [weak self] _, _ in
            guard let self, self.ajustes.view.visibility == .visible else { return }
            self.showPanel(nil)
        }
        AutomationProperties.setAutomationId(status, "EstadoTerminal")
        updateSplitLayout()

        // (las filas 0, 1 y 3 quedan vacías: los paneles siguen yendo en la 2, encima del terminal)
        for index in 0..<4 {
            let row = RowDefinition()
            row.height = GridLength(value: 1, gridUnitType: index == 2 ? .star : .auto)
            layout.rowDefinitions.append(row)
        }
        let columnaTerminal = ColumnDefinition()
        columnaTerminal.width = GridLength(value: 1, gridUnitType: .star)
        layout.columnDefinitions.append(columnaTerminal)
        let columnaExplorador = ColumnDefinition()
        columnaExplorador.width = GridLength(value: 1, gridUnitType: .auto)
        layout.columnDefinitions.append(columnaExplorador)
        configurarLateralSFTP()
        Grid.setColumn(marcoSFTPLateral, 1)
        Grid.setRow(marcoSFTPLateral, 2)
        layout.children.append(marcoSFTPLateral)

        Grid.setRow(terminalGrid, Int32(2))
        layout.children.append(terminalGrid)

        Grid.setRow(editor.view, Int32(2))
        contenidoTarjeta.children.append(editor.view)
        editor.onElegirClave = {
            guard let owner = GetActiveWindow() else { return nil }
            return try? SelectorArchivos.abrir(titulo: L("Clave privada"), tipo: L("Todos los archivos"),
                                             patron: "*.*", owner: owner)
        }
        editor.onConnect = { [weak self] session, guardada in
            guard let self else { return }
            if guardada, let perfil = MainActor.assumeIsolated({ self.sessions.profile(named: session.name) }) {
                openProfile(perfil)
                return
            }
            do {
                let ruta = try MainActor.assumeIsolated { try self.sessions.route(unsaved: session) }
                showPanel(nil)
                open(ruta, perfil: session.terminal)
            } catch {
                status.text = error.localizedDescription
            }
        }
        editor.onSave = { [weak self] session, original in self?.saveSession(session, replacing: original) ?? false }
        editor.onCancel = { [weak self] in self?.hideEditor() }
        Grid.setRow(ajustes.view, Int32(2))
        contenidoTarjeta.children.append(ajustes.view)
        Grid.setRow(selectorColor.view, Int32(2))
        contenidoTarjeta.children.append(selectorColor.view)
        selectorColor.onClose = { [weak self] in self?.showAjustes() }
        Grid.setRow(accesoFTP.view, Int32(2))
        contenidoTarjeta.children.append(accesoFTP.view)
        accesoFTP.onCancel = { [weak self] in self?.showPanel(nil) }
        accesoFTP.onConnect = { [weak self] route, user, password in
            guard let self else { return }
            self.explorador.connectFTP(route: route, user: user, password: password)
            self.showPanel(self.explorador.view)
        }
        Grid.setRow(explorador.view, Int32(2))
        contenidoTarjeta.children.append(explorador.view)
        explorador.onClose = { [weak self] in self?.showPanel(nil) }
        explorador.enqueue = { [weak self] action in
            _ = try? self?.window?.dispatcherQueue?.tryEnqueue { action() }
        }
        Grid.setRow(tuneles.view, Int32(2))
        contenidoTarjeta.children.append(tuneles.view)
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
        contenidoTarjeta.children.append(asistente.view)
        for panel in [pegado, multi, actualizacion, macroConfirm, confirmarBoton, reglas, borrarSesion, renombrar] {
            Grid.setRow(panel.view, Int32(2))
            contenidoTarjeta.children.append(panel.view)
            panel.onCancel = { [weak self] in self?.showPanel(nil) }
        }
        pegado.onConfirm = { [weak self] _ in self?.confirmPaste() }
        Grid.setRow(confirmarMulti.view, 2)
        contenidoTarjeta.children.append(confirmarMulti.view)
        confirmarMulti.onCancel = { [weak self] in self?.showPanel(nil) }
        MainActor.assumeIsolated {
            grupoMulti.awaitingAuth = { [weak self] io in
                guard let self, let io = io as? EntradaMacro else { return true }
                let id = ObjectIdentifier(io.tab)
                return self.clavesTerminal[id]?.conectado != true || self.entrandoPorLista.contains(id) || SecretPrompt.asks(io.cursorLine)
            }
            grupoMulti.canReceiveKeystrokes = { [weak self] io in
                guard let self, let io = io as? EntradaMacro else { return false }
                return !io.tab.closed && io.tab !== self.automatizacionActiva?.tab
            }
        }
        botonMulti.click.addHandler { [weak self] _, _ in self?.multiExec() }
        let masOpciones = MenuFlyout()
        let enviarVarias = MenuFlyoutItem()
        enviarVarias.text = L("Enviar a todas (MultiExec)")
        enviarVarias.click.addHandler { [weak self] _, _ in self?.mostrarEnvioMultiple() }
        masOpciones.items.append(enviarVarias)
        botonMulti.contextFlyout = masOpciones
        multi.onConfirm = { [weak self] text in self?.confirmMultiExec(text) }
        actualizacion.onConfirm = { [weak self] _ in self?.installUpdate() }
        for view in [espacios.view, buscarTerminal.view, botones.view] {
            Grid.setRow(view, Int32(2))
            contenidoTarjeta.children.append(view)
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
        contenidoTarjeta.children.append(llavero.view)
        llavero.demo = isDemo
        llavero.enqueue = { [weak self] accion in self?.onUI { _ in accion() } }
        llavero.onNombres = { [weak self] cuentas in self?.credencialesDisponibles = cuentas.filter { $0 != "-" } }
        llavero.onClose = { [weak self] in
            guard let self else { return }
            if volverAContrasenas { volverAContrasenas = false; showAjustes() } else { showPanel(nil) }
        }
        llavero.ledger = ledgerClaves
        llavero.usoDe = { [weak self] ref in self?.usoCredencial(ref) }
        llavero.onEstado = { [weak self] texto in self?.status.text = texto }
        llavero.onRenombrada = { [weak self] anterior, nueva in
            guard let self else { return }
            if anterior.service == .named, settings.clavePorDefecto == anterior.account {
                var cambios = settings
                cambios.clavePorDefecto = nueva.account
                saveAjustes(cambios)
            }
            recargarSesiones()
            if let leidos = try? readCommandButtons() { archivoBotones = leidos }
            construirBarraBotones()
        }
        // (un ssh_config que no se pudo leer o una sesión que sigue apuntando a la antigua: se conserva)
        llavero.sigueEnUso = { [weak self] ref in
            guard let self else { return true }
            return MainActor.assumeIsolated {
                self.sessions.loadError != nil || self.sessions.profiles.contains { perfil in
                    ref.service == .named ? perfil.namedCredential == ref.account
                        : CredentialRef.device(perfil.effectiveUser, perfil.endpoint.host) == ref
                }
            }
        }
        Grid.setRow(macros.view, Int32(2))
        contenidoTarjeta.children.append(macros.view)
        macros.onClose = { [weak self] in self?.showPanel(nil) }
        macros.onSave = { [weak self] in self?.saveMacro($0) }
        macros.onPlay = { [weak self] in self?.playMacro($0) }
        macros.onRecord = { [weak self] in self?.startRecording() }
        macros.onDelete = { [weak self] in self?.confirmMacroDeletion($0) }
        macroConfirm.onCancel = { [weak self] in self?.showMacros() }
        Grid.setRow(hojaConexion.view, Int32(2))
        contenidoTarjeta.children.append(hojaConexion.view)
        hojaConexion.onClose = { [weak self] in self?.showPanel(nil) }
        // Como quickConnect del Mac: por un salto, una sesión por su nombre o usuario@equipo[:puerto].
        hojaConexion.onConectar = { [weak self] equipo, salto, usuario, transport in
            guard let self else { return }
            self.showPanel(nil)
            if !salto.isEmpty {
                do {
                    let ruta = try MainActor.assumeIsolated {
                        try self.sessions.jumpShortcut(to: equipo, via: salto, user: usuario, transport: transport)
                    }
                    self.open(ruta)
                } catch {
                    self.status.text = "\u{2717} \(error.localizedDescription)"
                }
            } else if let perfil = MainActor.assumeIsolated({ self.sessions.profile(named: equipo) }) {
                self.openProfile(perfil)
            } else if var destino = Endpoint(parsing: equipo) {
                if destino.user == nil { destino.user = usuario }
                self.open(ConnectionRoute(title: destino.host, target: destino, transport: transport))
            }
        }
        Grid.setRow(buscarRegistros.view, Int32(2))
        contenidoTarjeta.children.append(buscarRegistros.view)
        buscarRegistros.onClose = { [weak self] in self?.showPanel(nil) }
        buscarRegistros.onAbrir = { [weak self] in self?.abrirRuta($0) }
        buscarRegistros.onMostrar = { [weak self] in self?.mostrarEnExplorador($0) }
        buscarRegistros.enqueue = { [weak self] accion in _ = try? self?.window?.dispatcherQueue?.tryEnqueue { accion() } }
        Grid.setRow(edicionRemota.view, Int32(2))
        contenidoTarjeta.children.append(edicionRemota.view)
        edicionRemota.onClose = { [weak self] in self?.showPanel(nil) }
        edicionRemota.enqueue = { [weak self] accion in _ = try? self?.window?.dispatcherQueue?.tryEnqueue { accion() } }
        edicionRemota.onDescargar = { [weak self] sesion, remotePath, localURL, progress in
            guard let self else { return }
            try await self.sftpDescargar(sesion: sesion, remotePath: remotePath, to: localURL, progress: progress)
        }
        edicionRemota.onSubir = { [weak self] localURL, sesion, remotePath, progress in
            guard let self else { return }
            try await self.sftpSubir(from: localURL, sesion: sesion, remotePath: remotePath, progress: progress)
        }
        for panel in [listas, listasAjustes] {
            panel.onGuardar = { [weak self] archivo in
                guard let self else { return }
                if isDemo { listasDemo = archivo } else { try archivo.save() }
            }
            panel.onAbrir = { [weak self] lista in self?.ejecutarLista(lista) }
            panel.onImportar = {
                guard let owner = GetActiveWindow() else { return nil }
                return try SelectorArchivos.abrir(titulo: L("Importar equipos de un .txt/.csv…"), tipo: L("Archivos de texto y CSV"),
                                                  patron: "*.txt;*.csv;*.tsv", owner: owner)
            }
        }
        Grid.setRow(listas.view, 2)
        listas.view.visibility = .collapsed
        contenidoTarjeta.children.append(listas.view)
        ajustes.editorListas = { [weak self] in
            guard let self else { return nil }
            prepararListas(listasAjustes)
            return listasAjustes.view
        }
        Grid.setRow(confirmarGrupo.view, 2)
        contenidoTarjeta.children.append(confirmarGrupo.view)
        confirmarGrupo.onCancel = { [weak self] in self?.showPanel(nil) }
        Grid.setRow(panelImportador.view, Int32(2))
        contenidoTarjeta.children.append(panelImportador.view)
        panelImportador.onClose = { [weak self] in self?.showPanel(nil) }
        panelImportador.onImportar = { [weak self] nuevas in
            guard let self, !nuevas.isEmpty, var file = self.archivoEditable() else { return }
            file.sessions += nuevas
            guard self.persistirSesiones(file) else { return }
            self.showPanel(nil)
            self.status.text = L("Importadas \(nuevas.count) sesiones")
        }
        reglas.onConfirm = { [weak self] in self?.saveHighlightRules($0) }
        reglas.onCancel = { [weak self] in self?.showAjustes() }
        ajustes.onTemaElegirColor = { [weak self] actual, terminar in
            guard let self else { terminar(nil); return }
            self.selectorColor.mostrar(actual, estilo: self.estilo, terminar: terminar)
            self.showPanel(self.selectorColor.view)
        }
        ajustes.onTemaImportar = {
            guard let owner = GetActiveWindow(),
                  let archivo = try SelectorArchivos.abrir(titulo: L("Importar .tema…"), tipo: L("Temas (.tema)"),
                                                            patron: "*.tema", owner: owner) else { return nil }
            return try TemasTerminal.biblioteca().importTheme(file: archivo)
        }
        ajustes.onElegirCarpetaRegistro = {
            guard let owner = GetActiveWindow() else { return nil }
            return SelectorArchivos.carpeta(titulo: L("Elegir carpeta…"), owner: owner)
        }
        ajustes.onAbrirRegistro = { [weak self] in self?.abrirRuta($0) }
        ajustes.registrosActivos = { [weak self] in
            guard let self else { return [] }
            return (terminals + ventanasPestana.values.map(\.session)).compactMap { tab in
                guard let archivo = tab.archivoRegistro else { return nil }
                return (self.titulo(tab), archivo, { [weak self, weak tab] in
                    guard let tab else { return }
                    self?.alternarRegistro(tab)
                })
            }
        }
        ajustes.onHighlight = { [weak self] in self?.showHighlightRules() }
        ajustes.onCheckUpdates = { [weak self] in self?.checkUpdates() }
        ajustes.credencialesConNombre = { [weak self] in self?.nombresCredenciales() ?? [] }
        ajustes.onManagePasswords = { [weak self] in self?.showLlavero(volverAAjustes: true) }
        ajustes.onEditarCredencial = { [weak self] cuenta in
            self?.showLlavero(cuenta: cuenta, nueva: cuenta == nil, volverAAjustes: true)
        }
        ajustes.onEditButtons = { [weak self] in self?.showCommandButtons() }
        ajustes.onReloadSessions = { [weak self] in
            self?.recargarSesiones()
            self?.ajustes.refrescar(self?.settings ?? AjustesTerminal(), estilo: self?.estilo ?? EstiloMac(tema: nil))
        }
        ajustes.onReloadHighlight = { [weak self] in
            self?.reloadHighlight()
            self?.status.text = L("Reglas de resaltado recargadas")
        }
        ajustes.onCustomizeHighlight = { [weak self] in self?.personalizarResaltado() }
        ajustes.rutaResaltado = { [weak self] in
            self.map { AppPaths.tilde($0.urlReglasActivas().path) } ?? "—"
        }
        ajustes.reglasDeVistaPrevia = { [weak self] in
            guard let self else { return HighlightConfig() }
            return configResaltado(para: temaGlobal ?? estilo.tema)
        }
        ajustes.grupos = { [weak self] in
            guard let self else { return [] }
            return MainActor.assumeIsolated { self.sessions.groups }
        }
        ajustes.rutaSesiones = { [weak self] in
            guard let self else { return "" }
            return self.isDemo ? L("(demo: s\u{00F3}lo en memoria)") : AppPaths.tilde(SessionFile.defaultURL.path)
        }
        ajustes.onNewSession = { [weak self] in self?.newSession() }
        ajustes.onImportSessions = { [weak self] in self?.showImportador() }
        ajustes.onEditSession = { [weak self] in self?.editSession($0) }
        ajustes.onDuplicateSession = { [weak self] in self?.duplicateProfile($0) }
        ajustes.onDeleteSession = { [weak self] in self?.confirmDeleteProfile($0) }
        ajustes.onChange = { [weak self] new in self?.saveAjustes(new) }
        ajustes.onClose = { [weak self] in self?.hideAjustes() }

        root.children.append(layout)
        // Atajos: en la fase de tunel (previewKeyDown), antes de que el terminal reciba la tecla.
        marco.previewKeyDown.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            if args.key.rawValue == 27, self.hayEmergente {
                self.showPanel(nil)
                args.handled = true
                return
            }
            if args.key.rawValue == 27, let lote = self.loteListas {
                lote.trip()
                args.handled = true
                return
            }
            guard self.shortcut(args.key.rawValue) else { return }
            args.handled = true
        }
        window.content = marco
        rootView = marco
        settings.windowsClaro = windowsEnClaro()
        settings = settings.conTamanoDelTema()
        aparienciaWindows.colorValuesChanged.addHandler { [weak self] _, _ in
            self?.onUI { app in
                let claro = app.windowsEnClaro()
                guard app.settings.windowsClaro != claro else { return }
                var nuevos = app.settings
                nuevos.windowsClaro = claro
                app.saveAjustes(nuevos.conTamanoDelTema())
            }
        }
        applySettings(settings)
        do {
            try window.activate()
            panelImportador.owner = GetActiveWindow()
            llavero.reload()
            // Al arrancar (Ajustes → General): la sesión de inicio y, si no hay otras pestañas, la terminal local.
            if !settings.sesionInicio.isEmpty,
               let inicio = MainActor.assumeIsolated({ sessions.profiles.first { $0.name == settings.sesionInicio } }) {
                openProfile(inicio)
            }
            if terminals.isEmpty, settings.terminalLocalInicio { open(.local()) }
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
        loteListas?.trip()
        for detached in ventanasPestana.values { detached.session.close() }
        for session in terminals { session.close() }
        for panel in panelesSFTP.values { panel.explorador.disconnect() }
        MainActor.assumeIsolated { clavesTerminal.values.forEach { $0.cerrar() } }
        MainActor.assumeIsolated { tunnelManager.stopAll() }
    }

    // MARK: - marco como el del Mac

    /// Colores del tema en el marco y todo lo que se dibuja con ellos (iconos, pestañas, barra lateral, botones).
    private func aplicarMarco(_ tema: Theme, fuente: String) {
        estilo = EstiloMac(tema: tema)
        EstiloMac.fuenteInterfaz = FontFamily(fuente)
        let e = estilo
        marco.background = e.fondo
        marco.requestedTheme = ElementTheme(rawValue: e.tema.isLight ? 1 : 2)
        // Interruptores, deslizadores, casillas y el foco de los campos con el acento del tema (como los controles
        // «themed» del Mac), no con el color de acento de Windows: se cambian los recursos de WinUI en el marco.
        if let recursos = marco.resources {
            let sobreAcento = EstiloMac.pincel(e.tema.accent.readable)
            for clave in ["AccentFillColorDefaultBrush", "AccentFillColorSecondaryBrush", "AccentFillColorTertiaryBrush",
                          "ToggleSwitchFillOn", "ToggleSwitchFillOnPointerOver", "ToggleSwitchFillOnPressed",
                          "SliderTrackValueFill", "SliderTrackValueFillPointerOver", "SliderTrackValueFillPressed",
                          "SliderThumbBackground", "SliderThumbBackgroundPointerOver", "SliderThumbBackgroundPressed",
                          "CheckBoxCheckBackgroundFillChecked", "CheckBoxCheckBackgroundFillCheckedPointerOver",
                          "TextControlBorderBrushFocused", "ComboBoxItemPillFillBrush"] {
                _ = recursos.insert(clave, e.acento)
            }
            for clave in ["ToggleSwitchKnobFillOn", "ToggleSwitchKnobFillOnPointerOver", "ToggleSwitchKnobFillOnPressed",
                          "CheckBoxCheckGlyphForegroundChecked"] {
                _ = recursos.insert(clave, sobreAcento)
            }
        }
        bordeSuperior.background = e.barra
        bordeSuperior.borderBrush = e.pestana
        barraBotonesFondo.background = e.barra
        barraBotonesFondo.borderBrush = e.panel(alfa: 0.6)
        ladoBorde.background = e.barra
        zonaSFTPLateral.background = e.barra
        zonaSFTPLateral.borderBrush = e.linea
        asaSFTP.background = e.transparente
        textoEsperaSFTP.foreground = e.apagado
        ladoBorde.borderBrush = e.linea
        pieBorde.borderBrush = e.linea
        buscarSesion.background = e.panel(alfa: 0.6)
        barraEstadoBorde.background = e.barra
        barraEstadoBorde.borderBrush = EstiloMac.pincel(e.tema.accent2, alfa: 0.6)
        status.foreground = e.apagado
        temaEtiqueta.foreground = e.apagado
        temaEtiqueta.text = e.tema.name.uppercased()
        reloj.foreground = e.acento
        tarjeta.background = e.fondo
        tarjeta.borderBrush = e.acento(alfa: 0.5)
        e.vestirIcono(cerrarTarjeta, Glifo.cerrar, ayuda: L("Cerrar (Esc)"), id: "CerrarVentana")
        cerrarTarjeta.verticalAlignment = .top
        if let barra = window?.appWindow?.titleBar {
            barra.buttonForegroundColor = EstiloMac.color(e.tema.text)
            barra.buttonInactiveForegroundColor = EstiloMac.color(e.tema.dim)
            barra.buttonBackgroundColor = Color(a: 0, r: 0, g: 0, b: 0)
            barra.buttonHoverBackgroundColor = EstiloMac.color(e.tema.panel)
        }
        construirIconos()
        construirPie()
        construirBarraBotones()
        construirPestanas()
        buildSidebar()
    }

    private func construirIconos() {
        let e = estilo
        iconos.children.clear()
        let nuevo = Button()
        e.vestirIcono(nuevo, Glifo.mas, ayuda: L("Conectar, terminal local, sesión nueva o una favorita"), id: "Nuevo")
        nuevo.flyout = menuNuevo.flyout
        // Al cerrarse el menú (con la pestaña nueva ya elegida) el foco vuelve al botón «+»: se lleva al terminal.
        // no verificado en Windows
        menuNuevo.alCerrar = { [weak self] in
            guard let self, !hayEmergente, selected != nil else { return }
            focusTerminal()
        }
        iconos.children.append(nuevo)
        let separacion = Border()
        separacion.width = 4
        iconos.children.append(separacion)
        let botones: [(String, String, String, SolidColorBrush?, () -> Void)] = [
            (Glifo.terminal, L("Nueva terminal local"), "NuevaLocal", nil, { [weak self] in self?.open(.local()) }),
            (Glifo.pegar, L("Pegado seguro: revisa l\u{00ED}neas peligrosas antes de enviarlas"), "PegarSeguro", nil,
             { [weak self] in self?.safePaste() }),
            (Glifo.grabar, L("Macros: grabar, reproducir y editar"), "Macros", nil, { [weak self] in self?.showMacros() }),
        ]
        for (glifo, ayuda, id, tinte, accion) in botones {
            if !settings.toolbarOcultos.contains(id) {
                iconos.children.append(e.botonIcono(glifo, ayuda: ayuda, id: id, tinte: tinte, accion: accion))
            }
        }
        e.vestirIcono(pararGrabacion, Glifo.grabar, ayuda: L("Parar la grabaci\u{00F3}n"), id: "Macros_PararGrabacion", tinte: e.mal)
        iconos.children.append(pararGrabacion)
        if !settings.toolbarOcultos.contains("Tuneles") {
            iconos.children.append(e.botonIcono(Glifo.tuneles, ayuda: L("T\u{00FA}neles SSH: locales, remotos y SOCKS"),
                                                id: "Tuneles") { [weak self] in self?.showTuneles() })
        }
        e.vestirIcono(dividir, Glifo.dividir, ayuda: L("Pantalla dividida"), id: "DividirTerminal")
        prepararMenuDivision()
        if !settings.toolbarOcultos.contains("DividirTerminal") { iconos.children.append(dividir) }
        if !settings.toolbarOcultos.contains("Llavero") {
            iconos.children.append(e.botonIcono(Glifo.llave, ayuda: L("Contraseñas y Llavero"), id: "Llavero") {
                [weak self] in self?.showLlavero()
            })
        }
        e.vestirIcono(botonMulti, Glifo.multiExec,
                      ayuda: L("MultiExec: lo que escribes va a la vez a los paneles (Ctrl+Mayús+M). Clic derecho en un panel → excluirlo"),
                      id: "MultiExec", tinte: e.aviso)
        if !settings.toolbarOcultos.contains("MultiExec") { iconos.children.append(botonMulti) }
        actualizarMultiExec()
        e.vestirIcono(pararAutomatizacion, Glifo.parar, ayuda: L("Detener env\u{00ED}o"), id: "Macros_Parar", tinte: e.mal)
        iconos.children.append(pararAutomatizacion)
        // (lo que en el Mac va en Edición y Herramientas: buscar en la pestaña o en todos los registros)
        let buscar = Button()
        e.vestirIcono(buscar, Glifo.buscar, ayuda: L("Buscar"), id: "BuscarTerminal")
        menuBuscar.preparar(estilo: e, [
            .orden(L("Buscar en la salida…"), Glifo.buscar, tecla: L("Ctrl+Mayús+F")) { [weak self] in self?.showTerminalSearch() },
            .orden(L("Buscar en todos los registros…"), Glifo.lista, tecla: L("Ctrl+Alt+Mayús+F")) { [weak self] in
                self?.showBuscarRegistros()
            },
        ])
        buscar.flyout = menuBuscar.flyout
        if !settings.toolbarOcultos.contains("BuscarTerminal") { iconos.children.append(buscar) }
        let resto: [(String, String, String, () -> Void)] = [
            (Glifo.espacios, L("Espacios de trabajo"), "Espacios", { [weak self] in self?.showWorkspaces() }),
            (Glifo.editar, L("Editar remoto"), "EditarRemoto", { [weak self] in self?.showEdicionRemota() }),
            (Glifo.barraLateral, L("Mostrar/ocultar sesiones"), "MostrarSesiones", { [weak self] in self?.alternarLateral() }),
        ]
        for (glifo, ayuda, id, accion) in resto {
            if !settings.toolbarOcultos.contains(id) {
                iconos.children.append(e.botonIcono(glifo, ayuda: ayuda, id: id, accion: accion))
            }
        }
        // (lo del menú de la app y el de Ayuda del Mac)
        let ajustesBoton = Button()
        e.vestirIcono(ajustesBoton, Glifo.ajustes, ayuda: L("Ajustes"), id: "Ajustes")
        menuAjustes.preparar(estilo: e, [
            .orden(L("Ajustes…"), Glifo.ajustes, tecla: "Ctrl+,") { [weak self] in self?.showAjustes() },
            .orden(L("Asistente de instalación…"), Glifo.estrella, tecla: nil) { [weak self] in
                self?.showAsistente(markSeen: true)
            },
            .orden(L("Buscar actualizaciones…"), Glifo.recargar, tecla: nil) { [weak self] in self?.checkUpdates() },
            .orden(L("Nueva ventana"), Glifo.mas, tecla: L("Ctrl+Mayús+N")) { [weak self] in self?.nuevaVentana() },
            .separador,
            .orden(L("Abrir el registro de depuración"), Glifo.lista, tecla: nil) { [weak self] in
                DebugLog.flush()
                AppPaths.ensure(DebugLog.directory)
                if !FileManager.default.fileExists(atPath: DebugLog.file.path) { ErrorLog.append("", to: DebugLog.file) }
                self?.abrirRuta(DebugLog.file)
            },
            .orden(L("Abrir el registro de errores"), Glifo.lista, tecla: nil) { [weak self] in
                ErrorLog.flush()
                if !FileManager.default.fileExists(atPath: ErrorLog.file.path) { ErrorLog.append("", to: ErrorLog.file) }
                self?.abrirRuta(ErrorLog.file)
            },
            .orden(L("Carpeta de registros"), Glifo.carpeta, tecla: nil) { [weak self] in
                self?.abrirRuta(AppPaths.ensure(DebugLog.directory))
            },
        ])
        ajustesBoton.flyout = menuAjustes.flyout
        iconos.children.append(ajustesBoton)
    }

    /// «Se usa en: …» de una credencial, como en Ajustes → Contraseñas del Mac.
    private func usoCredencial(_ ref: CredentialRef) -> String? {
        let archivo = (isDemo ? library : (try? SessionFile(contentsOf: SessionFile.defaultURL))) ?? SessionFile()
        var partes: [String] = []
        if ref.service == .named {
            let uso = archivo.usage(ofNamed: ref.account)
            if !uso.sessions.isEmpty { partes.append(L("sesiones: \(nombresUso(uso.sessions))\(masUso(uso.sessions))")) }
            if !uso.groups.isEmpty { partes.append(L("grupos: \(uso.groups.joined(separator: ", "))")) }
            let botones = archivoBotones.buttons.filter {
                ($0.mode == .pass && $0.command == ref.account)
                    || ($0.mode == .login && CommandButton.loginParts($0.command)?.credential == ref.account)
            }.map(\.name)
            if !botones.isEmpty { partes.append(L("botones: \(nombresUso(botones))\(masUso(botones))")) }
            if settings.clavePorDefecto == ref.account { partes.append(L("por defecto")) }
        } else {
            let nombres = archivo.sessions.filter {
                "\($0.user.isEmpty ? AppPaths.userName : $0.user)@\($0.host.isEmpty ? $0.name : $0.host)" == ref.account
            }.map(\.name)
            if !nombres.isEmpty { partes.append(L("sesiones: \(nombresUso(nombres))\(masUso(nombres))")) }
        }
        return partes.isEmpty ? nil : L("Se usa en: ") + partes.joined(separator: " \u{00B7} ")
    }

    private func nombresUso(_ nombres: [String]) -> String { nombres.prefix(6).joined(separator: ", ") }
    private func masUso(_ nombres: [String]) -> String { nombres.count > 6 ? "\u{2026}" : "" }

    private func showBuscarRegistros() {
        buscarRegistros.show(carpeta: settings.urlRegistro, estilo: estilo)
        status.text = ""
        showPanel(buscarRegistros.view)
    }

    /// Como «Nueva ventana» (⌘N) del Mac: otra ventana con sus propias pestañas (otra instancia; los ajustes y las
    /// sesiones son los mismos archivos).
    private func nuevaVentana() {
        let exe = Array(CommandLine.arguments[0].utf16) + [0]
        let verbo = Array("open".utf16) + [0]
        _ = exe.withUnsafeBufferPointer { exe in
            verbo.withUnsafeBufferPointer { verbo in
                ShellExecuteW(nil, verbo.baseAddress, exe.baseAddress, nil, nil, SW_SHOWNORMAL)
            }
        }
    }

    /// «Mostrar en Finder» del Mac: el Explorador con el archivo elegido.
    private func mostrarEnExplorador(_ url: URL) {
        let ruta = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
        let parametros = Array("/select,\"\(ruta)\"".utf16) + [0]
        let explorador = Array("explorer.exe".utf16) + [0]
        _ = parametros.withUnsafeBufferPointer { parametros in
            explorador.withUnsafeBufferPointer { explorador in
                ShellExecuteW(nil, nil, explorador.baseAddress, parametros.baseAddress, nil, SW_SHOWNORMAL)
            }
        }
    }

    private func prepararMenuNuevo() {
        let perfiles = MainActor.assumeIsolated { sessions.profiles }
        let grupos = MainActor.assumeIsolated { sessions.groups }
        let orden = (try? SessionLists.loadFavorites(favoritasURL)) ?? []
        menuNuevo.preparar(estilo: estilo, perfiles: perfiles, favoritas: orden,
                          inicio: settings.sesionInicio, grupos: grupos,
                          conectar: { [weak self] in self?.showHojaConexion() },
                          local: { [weak self] in self?.open(.local()) },
                          nueva: { [weak self] in self?.newSession(kind: $0) },
                          listas: { [weak self] in self?.mostrarListas() },
                          abrir: { [weak self] in self?.openProfile($0) },
                          abrirGrupo: { [weak self] in self?.abrirGrupo($0, perfiles: $1) })
    }

    private func abrirGrupo(_ path: String, perfiles: [SessionProfile], dividir: Bool = true) {
        let abrir = { [weak self] in
            guard let self else { return }
            let antes = terminals.count
            for perfil in perfiles { openProfile(perfil) }
            guard dividir, terminals.count - antes > 1 else { return }
            let abiertas = Array(terminals.dropFirst(antes))
            mostrarDivision(abiertas, modo: abiertas.count <= 4 ? .grid4 : .grid, activa: abiertas[0])
        }
        if perfiles.count > 8 {
            confirmarGrupo.show(title: L("¿Abrir las \(perfiles.count) sesiones de «\(L(nombre: path))»?"),
                               hint: L("Cada una en su pestaña (también las de sus subcarpetas)."),
                               text: perfiles.map(\.name).joined(separator: "\n"),
                               editable: false, confirmTitle: L("Abrir las \(perfiles.count)"))
            showPanel(confirmarGrupo.view)
            confirmarGrupo.onConfirm = { [weak self] _ in
                self?.showPanel(nil)
                abrir()
            }
        } else {
            abrir()
        }
    }

    private func construirPie() {
        let e = estilo
        pieLateral.children.clear()
        pieLateral.columnDefinitions.clear()
        for unidad in [GridUnitType.auto, .auto, .auto, .auto, .star, .auto] {
            let columna = ColumnDefinition()
            columna.width = GridLength(value: 1, gridUnitType: unidad)
            pieLateral.columnDefinitions.append(columna)
        }
        let botones: [(String, String, String, () -> Void)] = [
            (Glifo.mas, L("Nueva sesión"), "NuevaSesion", { [weak self] in self?.newSession() }),
            (Glifo.ajustes, L("Gestionar sesiones y grupos"), "GestionarSesiones", { [weak self] in self?.showGestorSesiones() }),
            (Glifo.importar, L("Importar de SecureCRT, MobaXterm, PuTTY, CSV…"), "ImportarSesiones",
             { [weak self] in self?.showImportador() }),
            (Glifo.lista, L("Listas de equipos: la misma orden en muchos equipos por un salto (Ctrl+Mayús+L)"), "ListasEquipos",
             { [weak self] in self?.mostrarListas() }),
            (Glifo.recargar, L("Recargar el ssh_config (Ctrl+Alt+Mayús+R)"), "RecargarSesiones",
             { [weak self] in self?.recargarSesiones() }),
        ]
        origenSesiones.fontFamily = EstiloMac.fuenteInterfaz
        origenSesiones.fontSize = 10
        origenSesiones.foreground = e.apagado
        origenSesiones.verticalAlignment = .center
        origenSesiones.textTrimming = .characterEllipsis
        var elementos: [FrameworkElement] = botones.map { glifo, ayuda, id, accion in
            let boton = e.botonIcono(glifo, ayuda: ayuda, id: id, accion: accion)
            boton.background = e.transparente
            return boton
        }
        elementos.insert(origenSesiones, at: 4)
        colocar(elementos, en: pieLateral)
        actualizarOrigenSesiones()
    }

    /// Botones de órdenes del grupo elegido, como la barra del Mac (el desplegable cambia de grupo).
    private func construirBarraBotones() {
        let e = estilo
        barraBotonesGrid.children.clear()
        let fila = StackPanel()
        fila.orientation = .horizontal
        fila.spacing = 6
        fila.verticalAlignment = .center
        let grupos = archivoBotones.groups
        if let actual = grupoBotones.flatMap({ grupos.contains($0) ? $0 : nil }) ?? grupos.first {
            grupoBotones = actual
            let selector = Button()
            let contenido = StackPanel()
            contenido.orientation = .horizontal
            contenido.spacing = 6
            contenido.children.append(EstiloMac.icono(Glifo.lista, tamano: 11, color: e.sobrePestana))
            contenido.children.append(EstiloMac.letra(actual, tamano: 11, peso: 700, color: e.sobrePestana))
            contenido.children.append(EstiloMac.icono(Glifo.flechaAbajo, tamano: 8, color: e.sobrePestana))
            selector.content = contenido
            selector.background = e.pestana
            selector.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
            selector.cornerRadius = EstiloMac.radio(6)
            selector.height = 24
            selector.padding = Thickness(left: 8, top: 0, right: 8, bottom: 0)
            AutomationProperties.setAutomationId(selector, "Botones_Grupo")
            AutomationProperties.setName(selector, actual)
            let menu = MenuFlyout()
            for grupo in grupos {
                let item = MenuFlyoutItem()
                item.text = grupo
                item.click.addHandler { [weak self] _, _ in
                    self?.grupoBotones = grupo
                    self?.construirBarraBotones()
                }
                menu.items.append(item)
            }
            selector.flyout = menu
            // (sin «Por grupos», todos los botones seguidos y sin desplegable)
            if settings.botonesPorGrupos { fila.children.append(selector) }
            for boton in archivoBotones.buttons where !settings.botonesPorGrupos || boton.group == actual {
                let tono = colorModo(boton.mode)
                let chip = Button()
                chip.content = EstiloMac.letra(boton.name, tamano: 11, peso: 600, color: EstiloMac.pincel(tono))
                chip.background = e.panel(alfa: 0.55)
                chip.borderBrush = EstiloMac.pincel(tono, alfa: 0.75)
                chip.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
                chip.cornerRadius = EstiloMac.radio(6)
                chip.height = 24
                chip.padding = Thickness(left: 9, top: 0, right: 9, bottom: 0)
                // (sólo el modo: el comando de un botón «clave» lleva la contraseña)
                ToolTipService.setToolTip(chip, boton.hotkey.map { "\(boton.mode.title) \u{00B7} \($0)" } ?? boton.mode.title)
                AutomationProperties.setName(chip, boton.name)
                chip.click.addHandler { [weak self] _, _ in self?.useCommandButton(boton) }
                fila.children.append(chip)
            }
        } else {
            fila.children.append(EstiloMac.letra(L("Sin botones de \u{00F3}rdenes: cr\u{00E9}alos con el l\u{00E1}piz"),
                                                 tamano: 11, color: e.apagado))
        }
        let desliza = ScrollViewer()
        desliza.content = fila
        desliza.horizontalScrollBarVisibility = .hidden
        desliza.verticalScrollBarVisibility = .disabled
        desliza.verticalAlignment = .center
        let lapiz = e.botonIcono(Glifo.editar, ayuda: L("Editar los botones"), id: "Botones") { [weak self] in
            self?.showCommandButtons()
        }
        lapiz.height = 24
        lapiz.background = e.transparente
        Grid.setColumn(desliza, Int32(0))
        Grid.setColumn(lapiz, Int32(1))
        barraBotonesGrid.children.append(desliza)
        barraBotonesGrid.children.append(lapiz)
    }

    private func colorModo(_ modo: CommandButton.Mode) -> RGB {
        let t = estilo.tema
        switch modo {
        case .run: return t.accent2
        case .type: return t.accent
        case .pass, .clave: return t.bad
        case .login: return t.special
        case .session: return t.good
        }
    }

    /// Las pestañas no pasan de lo que dejan los iconos y los botones de la ventana (el resto, desplazando).
    private func ajustarAnchoPestanas() {
        let libre = barraSuperior.actualWidth - iconos.actualWidth - 140 - 80
        tabsScroll.maxWidth = max(120, libre)
    }

    private func alternarLateral() {
        settings.listaSesiones.toggle()
        if !isDemo { settings.guardar() }
        mostrarLateral(settings.listaSesiones)
        resize()
    }

    private func mostrarLateral(_ visible: Bool) {
        colLateral.width = GridLength(value: visible ? 268 : 0, gridUnitType: .pixel)
        ladoBorde.visibility = visible ? .visible : .collapsed
    }

    private func arrancarReloj() {
        actualizarReloj()
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self else { return }
                _ = try? self.window?.dispatcherQueue?.tryEnqueue { [weak self] in self?.actualizarReloj() }
            }
        }
    }

    private func actualizarReloj() {
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm"
        reloj.text = formato.string(from: Date())
    }

    // MARK: - barra lateral

    private func buildSidebar() {
        let filter = buscarSesion.text.trimmingCharacters(in: .whitespaces)
        favoritas = Set((try? SessionLists.loadFavorites(favoritasURL)) ?? [])
        recientes = SessionLists.recents((try? SafeFile.read(recientesURL)) ?? "")
        prepararMenuNuevo()

        sidebar.children.clear()
        botonesSesion.removeAll()
        actualizarOrigenSesiones()

        let grupos = MainActor.assumeIsolated { sessions.groups }
        let todosPerfiles = grupos.flatMap { $0.1 }

        if filter.isEmpty {
            let perfilesFavoritas = todosPerfiles.filter { favoritas.contains($0.name) }
            let perfilesRecientes = recientes.filter { !favoritas.contains($0) }.prefix(5)
                .compactMap { nombre in todosPerfiles.first { $0.name == nombre } }
            let secciones = [(Glifo.estrella, L("Favoritas"), estilo.aviso, perfilesFavoritas),
                             (Glifo.recientes, L("Recientes"), estilo.acento2, perfilesRecientes)]
            for (index, seccion) in secciones.enumerated() where !seccion.3.isEmpty {
                let clave = Self.clavesSeccionesLaterales[index]
                sidebar.children.append(makeSidebarSeccion(seccion.0, seccion.1, seccion.2, seccion.3.count, clave: clave))
                if !plegados.contains(clave) {
                    for perfil in seccion.3 { sidebar.children.append(makeSidebarRow(perfil)) }
                }
            }
            if !perfilesFavoritas.isEmpty || !perfilesRecientes.isEmpty {
                let separador = Border()
                separador.height = 1
                separador.margin = Thickness(left: 4, top: 6, right: 4, bottom: 6)
                separador.background = estilo.panel
                sidebar.children.append(separador)
            }
        }

        func coincide(_ p: SessionProfile) -> Bool {
            guard !filter.isEmpty else { return true }
            return [p.name, p.endpoint.description, p.user ?? "", p.summary ?? "", p.group ?? "",
                    p.transport.label, p.transport.rawValue, p.serial?.device ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(filter) }
        }

        let arbol = grupos.map { grupo in
            (name: grupo.name, items: grupo.profiles.filter(coincide))
        }.filter { !$0.items.isEmpty }
        if arbol.isEmpty, !filter.isEmpty {
            let mensaje = EstiloMac.letra(L("Nada coincide con «\(filter)»"), tamano: 11, color: estilo.apagado)
            mensaje.margin = Thickness(left: 8, top: 8, right: 8, bottom: 0)
            sidebar.children.append(mensaje)
        }
        let todas = grupos.map { (name: $0.name, items: $0.profiles) }
        for fila in GroupTree.rows(arbol, collapsed: filter.isEmpty ? plegados : []) {
            switch fila {
            case .folder(let path, let nombre, let depth, let cantidad):
                let perfiles = GroupTree.items(under: path, in: todas)
                sidebar.children.append(makeSidebarGrupoHeader(path, nombre: nombre, profundidad: depth, cuenta: cantidad,
                                                               perfiles: perfiles, buscando: !filter.isEmpty))
            case .item(let perfil, let depth):
                sidebar.children.append(makeSidebarRow(perfil, profundidad: max(0, depth - 1)))
            }
        }
    }

    private func actualizarOrigenSesiones() {
        origenSesiones.text = MainActor.assumeIsolated {
            sessions.source.map { AppPaths.tilde($0.path) }
                ?? (sessions.profiles.isEmpty ? L("sin sesiones todavía") : L("sesiones de ejemplo"))
        }
        ToolTipService.setToolTip(origenSesiones, origenSesiones.text)
    }

    private func plegarGrupo(_ clave: String) {
        var actual = plegados
        if actual.contains(clave) { actual.remove(clave) } else { actual.insert(clave) }
        plegados = actual
        buildSidebar()
    }

    private func makeSidebarSeccion(_ glifo: String, _ titulo: String, _ color: SolidColorBrush, _ cuenta: Int,
                                     clave: String) -> Button {
        let fila = filaLateral(columnas: [.auto, .auto, .star, .auto])
        let plegada = plegados.contains(clave)
        let flecha = EstiloMac.icono(plegada ? Glifo.flechaDerecha : Glifo.flechaAbajo, tamano: 8, color: estilo.apagado)
        flecha.width = 12
        let icono = EstiloMac.icono(glifo, tamano: 11, color: color)
        icono.margin = Thickness(left: 4, top: 0, right: 6, bottom: 0)
        let nombre = EstiloMac.letra(titulo, tamano: 12, peso: 600, color: estilo.texto)
        let numero = EstiloMac.letra("\(cuenta)", tamano: 10, color: estilo.apagado)
        colocar([flecha, icono, nombre, numero], en: fila)
        let boton = Button()
        estilo.plano(boton)
        boton.content = fila
        boton.height = 26
        boton.padding = Thickness(left: 4, top: 0, right: 8, bottom: 0)
        AutomationProperties.setName(boton, titulo)
        boton.click.addHandler { [weak self] _, _ in self?.plegarGrupo(clave) }
        return boton
    }

    private func makeSidebarGrupoHeader(_ grupo: String, nombre visible: String, profundidad: Int, cuenta: Int,
                                        perfiles: [SessionProfile], buscando: Bool) -> Button {
        let plegado = !buscando && plegados.contains(grupo)
        let e = estilo
        let fila = filaLateral(columnas: [.auto, .auto, .star, .auto])
        let flecha = EstiloMac.icono(plegado ? Glifo.flechaDerecha : Glifo.flechaAbajo, tamano: 8, color: e.apagado)
        flecha.width = 12
        let carpeta = EstiloMac.icono(plegado ? Glifo.carpeta : Glifo.carpetaAbierta, tamano: 12, color: e.acento2)
        carpeta.margin = Thickness(left: 4, top: 0, right: 6, bottom: 0)
        let nombre = EstiloMac.letra(L(nombre: visible), tamano: 12, peso: 600, color: e.texto)
        let numero = EstiloMac.letra("\(cuenta)", tamano: 10, color: e.apagado)
        colocar([flecha, carpeta, nombre, numero], en: fila)
        let boton = Button()
        e.plano(boton)
        boton.content = fila
        boton.height = 26
        boton.padding = Thickness(left: 4 + 14 * Double(profundidad), top: 0, right: 8, bottom: 0)
        boton.margin = Thickness(left: 0, top: 4, right: 0, bottom: 0)
        AutomationProperties.setAutomationId(boton, "Grupo_\(grupo)")
        let menu = MenuFlyout()
        accionMenu(menu, L("Abrir las \(perfiles.count)")) { [weak self] in
            self?.abrirGrupo(grupo, perfiles: perfiles, dividir: false)
        }
        accionMenu(menu, L("Abrir las \(perfiles.count) en vista dividida")) { [weak self] in
            self?.abrirGrupo(grupo, perfiles: perfiles)
        }
        menu.items.append(MenuFlyoutSeparator())
        accionMenu(menu, L("Nueva sesión en «\(L(nombre: grupo))»")) { [weak self] in self?.newSession(grupo: grupo) }
        accionMenu(menu, L("Gestionar el grupo…")) { [weak self] in
            if let primero = perfiles.first { self?.editSession(primero) }
        }
        boton.contextFlyout = menu
        AutomationProperties.setName(boton, L(nombre: visible))
        boton.click.addHandler { [weak self] _, _ in
            guard let self, !buscando else { return }
            self.plegarGrupo(grupo)
        }
        return boton
    }

    /// Columnas de una fila de la barra lateral; `.pixel` es la del icono (22).
    private func filaLateral(columnas: [GridUnitType]) -> Grid {
        let fila = Grid()
        for tipo in columnas {
            let columna = ColumnDefinition()
            columna.width = GridLength(value: tipo == .pixel ? 22 : 1, gridUnitType: tipo)
            fila.columnDefinitions.append(columna)
        }
        return fila
    }

    private func colocar(_ elementos: [FrameworkElement], en fila: Grid) {
        for (indice, elemento) in elementos.enumerated() {
            Grid.setColumn(elemento, Int32(indice))
            fila.children.append(elemento)
        }
    }

    /// Icono y color de cada tipo de sesión, como en el Mac (ssh acento2, telnet aviso, sftp/ftp bien, serie acento).
    private func iconoTransporte(_ perfil: SessionProfile) -> (String, SolidColorBrush) {
        let e = estilo
        switch perfil.transport {
        case .ssh: return (perfil.proxyJump.isEmpty ? Glifo.terminal : Glifo.salto, e.acento2)
        case .telnet: return (Glifo.red, e.aviso)
        case .sftp: return (Glifo.carpeta, e.bien)
        case .ftp: return (Glifo.disco, e.bien)
        case .serial: return (Glifo.serie, e.acento)
        case .local: return (Glifo.terminal, e.texto)
        }
    }

    private func subtitulo(_ perfil: SessionProfile) -> String {
        switch perfil.transport {
        case .serial: return perfil.serial?.device ?? L("Serie")
        case .local: return L("Este equipo")
        default: return perfil.endpoint.description
        }
    }

    private func makeSidebarRow(_ perfil: SessionProfile, profundidad: Int = 0) -> Button {
        let e = estilo
        let abierto = terminals.contains { !$0.closed && $0.route.sessionName == perfil.name }
        let elegido = (sesionLateral ?? selected?.route.sessionName) == perfil.name
        let (glifo, tono) = iconoTransporte(perfil)
        let fila = filaLateral(columnas: [.pixel, .auto, .star, .auto])
        let icono = EstiloMac.icono(glifo, tamano: 11, color: elegido ? e.acento : tono)
        let nombre = EstiloMac.letra(perfil.name, tamano: 12, peso: 500, color: e.texto)
        let detalle = EstiloMac.letra(subtitulo(perfil), tamano: 10, color: e.apagado)
        detalle.margin = Thickness(left: 6, top: 1, right: 4, bottom: 0)
        let marcas = StackPanel()
        marcas.orientation = .horizontal
        marcas.spacing = 4
        marcas.verticalAlignment = .center
        if abierto {
            let punto = EstiloMac.letra("\u{25CF}", tamano: 8, color: e.bien)
            AutomationProperties.setName(punto, L("Sesi\u{00F3}n abierta"))
            marcas.children.append(punto)
        }
        if favoritas.contains(perfil.name) {
            marcas.children.append(EstiloMac.icono(Glifo.estrella, tamano: 9, color: e.aviso))
        }
        colocar([icono, nombre, detalle, marcas], en: fila)

        let btn = Button()
        e.plano(btn)
        btn.content = fila
        btn.height = 26
        btn.padding = Thickness(left: 10 + 14 * Double(profundidad), top: 0, right: 8, bottom: 0)
        if elegido {
            btn.background = e.acento(alfa: 0.2)
            btn.borderBrush = e.acento
            btn.borderThickness = Thickness(left: 2, top: 0, right: 0, bottom: 0)
        }
        ToolTipService.setToolTip(btn, "\(perfil.name) \u{00B7} \(subtitulo(perfil))")
        AutomationProperties.setAutomationId(btn, "Sesion_\(perfil.name)")
        AutomationProperties.setName(btn, perfil.name)
        botonesSesion.append((perfil.name, btn))
        btn.click.addHandler { [weak self] _, _ in self?.seleccionarFilaSesion(perfil.name) }
        btn.doubleTapped.addHandler { [weak self] _, args in
            args?.handled = true
            self?.openProfile(perfil)
        }
        btn.keyDown.addHandler { [weak self] _, args in
            guard let args, args.key.rawValue == 13 else { return }
            args.handled = true
            self?.openProfile(perfil)
        }
        let menu = MenuFlyout()
        accionMenu(menu, L("Conectar")) { [weak self] in self?.openProfile(perfil) }
        if perfil.transport != .sftp, perfil.transport != .ftp {
            accionMenu(menu, L("Conectar en la vista dividida")) { [weak self] in
                guard let self else { return }
                if let nueva = openProfile(perfil) { añadirAVista(nueva) }
            }
        }
        menu.items.append(MenuFlyoutSeparator())
        accionMenu(menu, favoritas.contains(perfil.name) ? L("Quitar de ★ favoritas") : L("★ Favorita")) { [weak self] in
            self?.alternarFavorita(perfil.name)
        }
        accionMenu(menu, settings.sesionInicio == perfil.name ? L("No abrir al arrancar") : L("⏻ Abrir al arrancar")) { [weak self] in
            guard let self else { return }
            var cambios = settings
            cambios.sesionInicio = cambios.sesionInicio == perfil.name ? "" : perfil.name
            saveAjustes(cambios)
            buildSidebar()
        }
        menu.items.append(MenuFlyoutSeparator())
        accionMenu(menu, L("Editar…")) { [weak self] in self?.editSession(perfil) }
        accionMenu(menu, L("Duplicar…")) { [weak self] in self?.duplicateProfile(perfil) }
        accionMenu(menu, L("Nueva sesión en este grupo…")) { [weak self] in self?.newSession(grupo: perfil.group) }
        accionMenu(menu, L("Borrar…")) { [weak self] in self?.confirmDeleteProfile(perfil) }
        if perfil.transport == .ssh || perfil.transport == .sftp {
            menu.items.append(MenuFlyoutSeparator())
            accionMenu(menu, perfil.transport == .ssh ? L("Copiar orden ssh") : L("Copiar orden sftp")) {
                VistaTerminal.escribirPortapapeles("\(perfil.transport.rawValue) \(perfil.name)")
            }
            accionMenu(menu, L("Explorador SFTP")) { [weak self] in self?.openSFTPProfile(perfil) }
        }
        btn.contextFlyout = menu
        return btn
    }

    private func seleccionarFilaSesion(_ nombre: String) {
        sesionLateral = nombre
        for (sesion, boton) in botonesSesion {
            let activa = sesion == nombre
            boton.background = activa ? estilo.acento(alfa: 0.2) : estilo.transparente
            boton.borderBrush = activa ? estilo.acento : estilo.transparente
            boton.borderThickness = Thickness(left: activa ? 2 : 0, top: 0, right: 0, bottom: 0)
        }
    }

    private func accionMenu(_ menu: MenuFlyout, _ titulo: String, accion: @escaping () -> Void) {
        let item = MenuFlyoutItem()
        item.text = titulo
        item.click.addHandler { _, _ in accion() }
        menu.items.append(item)
    }

    private func alternarFavorita(_ nombre: String) {
        do {
            var orden = try SessionLists.loadFavorites(favoritasURL)
            if orden.contains(nombre) { orden.removeAll { $0 == nombre } } else { orden.append(nombre) }
            try SessionLists.saveFavorites(orden, to: favoritasURL)
            buildSidebar()
        } catch {
            status.text = error.localizedDescription
        }
    }

    // MARK: - editor de sesion
    private func newSession(grupo: String? = nil, kind: SessionProfile.Transport = .ssh) {
        let nombre = archivoEditable()?.uniqueName("nueva") ?? "nueva"
        var session = EditableSession.new(group: "General", name: nombre, kind: kind)
        if let grupo, grupo != "Sin grupo" {
            session.group = grupo
        } else if let group = MainActor.assumeIsolated({ sessions.groups.first?.name }), group != "Sin grupo" {
            session.group = group
        }
        showEditor(session, original: nil)
    }

    // MARK: - acciones de pestaña (como el menú de la pestaña del Mac)

    /// Vuelve a abrir la conexión en el mismo sitio de la barra (y con el mismo nombre, si se le puso).
    private func reconectar(_ tab: PestanaTerminal) {
        guard let indice = terminals.firstIndex(where: { $0 === tab }) else { return }
        let nombre = nombresPestana[ObjectIdentifier(tab)]
        select(tab, focus: false)
        closeSelected()
        guard let nueva = open(tab.route, perfil: tab.perfil) else { return }
        if let nombre { nombresPestana[ObjectIdentifier(nueva)] = nombre }
        if let ahora = terminals.firstIndex(where: { $0 === nueva }) {
            terminals.remove(at: ahora)
            terminals.insert(nueva, at: min(indice, terminals.count))
        }
        select(nueva)
    }

    private func cerrarPestana(_ tab: PestanaTerminal) {
        select(tab, focus: false)
        closeSelected()
    }

    private func renombrarPestana(_ tab: PestanaTerminal) {
        renombrar.show(title: L("Renombrar la pesta\u{00F1}a"), hint: L("Vac\u{00ED}o: vuelve a su nombre."),
                       text: nombresPestana[ObjectIdentifier(tab)] ?? tab.title, editable: true, confirmTitle: L("Renombrar"))
        renombrar.onConfirm = { [weak self, weak tab] texto in
            guard let self, let tab else { return }
            let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            self.nombresPestana[ObjectIdentifier(tab)] = limpio.isEmpty || limpio == tab.title ? nil : limpio
            self.showPanel(nil)
            self.construirPestanas()
        }
        showPanel(renombrar.view)
    }

    private func titulo(_ tab: PestanaTerminal) -> String { nombresPestana[ObjectIdentifier(tab)] ?? tab.title }

    /// Ctrl+= / Ctrl+- / Ctrl+0: la letra del terminal más grande, más pequeña o la de siempre.
    private func zoomLetra(_ paso: Int?) {
        // (Ctrl+0: vuelve a «Automático: el del tema», como ⌘0 en el Mac)
        var nuevo = settings
        if let paso {
            nuevo.tamanoAuto = false
            nuevo.tamano = min(AjustesTerminal.tamanos.upperBound, max(AjustesTerminal.tamanos.lowerBound, settings.tamano + paso))
        } else {
            nuevo.tamanoAuto = true
            nuevo = nuevo.conTamanoDelTema()
        }
        guard nuevo != settings else { return }
        saveAjustes(nuevo)
        status.text = L("Letra: \(nuevo.tamano) pt")
    }

    private func irAPestana(_ numero: Int) {
        guard !terminals.isEmpty else { return }
        select(terminals[min(numero, terminals.count) - 1])
    }

    private func editSession(_ perfil: SessionProfile) {
        let saved: EditableSession? = isDemo ? library.sessions.first { $0.name == perfil.name }
            : (try? SessionFile(contentsOf: SessionFile.defaultURL))?.sessions.first { $0.name == perfil.name }
        showEditor(saved ?? NetDeckWindows.editable(from: perfil), original: perfil.name)
    }

    private func showEditor(_ session: EditableSession, original: String?) {
        status.text = ""
        let credenciales = nombresCredenciales()
        let saltos = MainActor.assumeIsolated { sessions.profiles.filter { $0.name != session.name }.map(\.name) }
        editor.show(session, original: original, estilo: estilo, credenciales: credenciales, saltos: saltos)
        editor.focusName()
        showPanel(editor.view)
    }

    private func hideEditor() { showPanel(nil) }

    private func duplicateProfile(_ perfil: SessionProfile) {
        let saved: EditableSession? = isDemo ? library.sessions.first { $0.name == perfil.name }
            : (try? SessionFile(contentsOf: SessionFile.defaultURL))?.sessions.first { $0.name == perfil.name }
        var copy = saved ?? NetDeckWindows.editable(from: perfil)
        copy.name = archivoEditable()?.uniqueName(perfil.name) ?? (perfil.name + "-2")
        showEditor(copy, original: nil)
    }

    private func confirmDeleteProfile(_ perfil: SessionProfile) {
        borrarSesion.show(title: L("\u{00BF}Borrar \u{00AB}\(perfil.name)\u{00BB}?"),
                          hint: L("Esta acci\u{00F3}n no se puede deshacer."),
                          text: "", editable: false, confirmTitle: L("Borrar"))
        borrarSesion.onConfirm = { [weak self] _ in self?.deleteProfile(perfil) }
        showPanel(borrarSesion.view)
    }

    private func deleteProfile(_ perfil: SessionProfile) {
        // (si el archivo no se puede leer, no se sigue: guardar uno vacío borraría todas las sesiones)
        guard var file = archivoEditable() else { return }
        file.sessions.removeAll { $0.name == perfil.name }
        favoritas.remove(perfil.name)
        try? SessionLists.saveFavorites(Array(favoritas).sorted(), to: favoritasURL)
        if isDemo {
            library = file
            MainActor.assumeIsolated { sessions = SessionManager(profiles: SSHConfigParser().parse(file.render())) }
        } else {
            if let error = file.save() { status.text = L("No se puede borrar: \(error)"); return }
            MainActor.assumeIsolated { sessions.load(from: SessionFile.defaultURL) }
        }
        buildSidebar()
        showPanel(nil)
        status.text = L("Sesi\u{00F3}n \u{00AB}\(perfil.name)\u{00BB} borrada")
    }

    private func recargarSesiones() {
        guard !isDemo else { return }
        if FileManager.default.fileExists(atPath: SessionFile.defaultURL.path) {
            MainActor.assumeIsolated { sessions.load(from: SessionFile.defaultURL) }
        } else {
            MainActor.assumeIsolated { sessions.load() }
        }
        buildSidebar()
        status.text = L("Sesiones recargadas")
    }

    /// El area principal muestra el terminal o uno de los paneles (editor, ajustes), nunca varios a la vez.
    private func showPanel(_ panel: ScrollViewer?) {
        if panel !== selectorColor.view { selectorColor.abandonar() }
        capaEmergente.visibility = panel == nil ? .collapsed : .visible
        // Ajustes, como en el Mac: hasta 1000×720, sin márgenes y con su propio «Cerrar».
        let sonAjustes = panel === ajustes.view
        tarjeta.maxWidth = sonAjustes ? 1000 : 900
        tarjeta.padding = sonAjustes ? Thickness(left: 0, top: 0, right: 0, bottom: 0)
                                     : Thickness(left: 8, top: 8, right: 8, bottom: 8)
        tarjeta.cornerRadius = EstiloMac.radio(sonAjustes ? 14 : 12)
        cerrarTarjeta.visibility = sonAjustes ? .collapsed : .visible
        if sonAjustes { ajustes.ajustarAlto(capaEmergente.actualHeight - 60) }
        editor.view.visibility = panel === editor.view ? .visible : .collapsed
        listas.view.visibility = panel === listas.view ? .visible : .collapsed
        ajustes.view.visibility = panel === ajustes.view ? .visible : .collapsed
        selectorColor.view.visibility = panel === selectorColor.view ? .visible : .collapsed
        reglas.view.visibility = panel === reglas.view ? .visible : .collapsed
        pegado.view.visibility = panel === pegado.view ? .visible : .collapsed
        if panel !== pegado.view { pendingPaste = nil }
        multi.view.visibility = panel === multi.view ? .visible : .collapsed
        confirmarMulti.view.visibility = panel === confirmarMulti.view ? .visible : .collapsed
        if panel !== confirmarMulti.view { confirmarMulti.onConfirm = nil }
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
        borrarSesion.view.visibility = panel === borrarSesion.view ? .visible : .collapsed
        if panel !== borrarSesion.view { borrarSesion.onConfirm = nil }
        hojaConexion.view.visibility = panel === hojaConexion.view ? .visible : .collapsed
        buscarRegistros.view.visibility = panel === buscarRegistros.view ? .visible : .collapsed
        renombrar.view.visibility = panel === renombrar.view ? .visible : .collapsed
        if panel !== renombrar.view { renombrar.onConfirm = nil }
        edicionRemota.view.visibility = panel === edicionRemota.view ? .visible : .collapsed
        panelImportador.view.visibility = panel === panelImportador.view ? .visible : .collapsed
        confirmarGrupo.view.visibility = panel === confirmarGrupo.view ? .visible : .collapsed
        if panel !== confirmarGrupo.view { confirmarGrupo.onConfirm = nil }
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
        // Como el Mac (Ajustes → Terminal → Pegar): sólo pregunta si pasa del umbral o lleva órdenes peligrosas; con la
        // revisión apagada, nunca.
        guard PasteReview.needed(clean, enabled: settings.revisarPegado, threshold: settings.umbralPegado) else {
            selected.paste(clean)
            return
        }
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

    // MARK: - MultiExec en vivo

    private func multiExec() {
        multiActivo.toggle()
        actualizarMultiExec()
        construirPestanas()
        focusTerminal()
    }

    private func actualizarMultiExec() {
        actualizarCabecerasDivision()
        let visibles = panelDividido ? terminalesVisibles.compactMap { $0 } : terminals
        let ids = Set(visibles.filter { !$0.closed && $0.route.acceptsMultiExec }.map(ObjectIdentifier.init))
            .subtracting(excluidasMulti)
        MainActor.assumeIsolated {
            grupoMulti.isActive = multiActivo
            for (id, control) in clavesTerminal {
                if multiActivo && ids.contains(id) {
                    if !grupoMulti.contains(control.io) { grupoMulti.join(control.io) }
                } else if grupoMulti.contains(control.io) {
                    grupoMulti.leave(control.io)
                }
            }
        }
        botonMulti.background = multiActivo ? estilo.acento(alfa: 0.24) : estilo.panel(alfa: 0.4)
        if multiActivo {
            botonMulti.content = EstiloMac.letra(L("MULTIEXEC ×\(ids.count)"), tamano: 10, peso: 700, color: estilo.aviso)
        } else {
            botonMulti.content = EstiloMac.icono(Glifo.multiExec, color: estilo.aviso)
        }
    }

    private func confirmarIntroMulti(_ orden: String, pestañas: Int, bytes: [UInt8], de tab: PestanaTerminal) {
        let comando = SecretMask.masked(orden)
        confirmarMulti.show(title: L("¿Enviar «\(comando)» a \(pestañas) pestañas a la vez?"),
                            hint: L("Es una orden peligrosa y MultiExec la escribe en todas las pestañas en las que estás tecleando."),
                            text: comando, editable: false, confirmTitle: L("Enviar a todas"))
        showPanel(confirmarMulti.view)
        confirmarMulti.onConfirm = { [weak self, weak tab] _ in
            guard let self, let tab, !tab.closed, multiActivo, selected === tab else { return }
            showPanel(nil)
            MainActor.assumeIsolated {
                guard let io = self.clavesTerminal[ObjectIdentifier(tab)]?.io,
                      self.grupoMulti.reach(from: io) == pestañas else { return }
                _ = self.grupoMulti.broadcast(bytes, from: io)
            }
        }
    }

    /// Un mismo comando a todas las pestanas SSH y Telnet abiertas.
    private func mostrarEnvioMultiple() {
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
        let targets = MainActor.assumeIsolated {
            terminals.filter { tab in
                let id = ObjectIdentifier(tab)
                guard tab.route.acceptsMultiExec, !tab.closed, tab !== automatizacionActiva?.tab,
                      !entrandoPorLista.contains(id), !excluidasMulti.contains(id),
                      let control = clavesTerminal[id], control.conectado else { return false }
                return PromptRule.isPrompt(control.io.cursorLine, custom: control.io.promptRule)
            }
        }
        showPanel(nil)
        guard !targets.isEmpty else {
            status.text = L("No hay pesta\u{00F1}as SSH o Telnet abiertas")
            return
        }
        // (como el pegado en macOS: «\r\n» es un solo Intro, y las órdenes peligrosas se confirman ANTES de enviarlas a todas)
        let payload = PasteRules.lines(of: command).joined(separator: "\r") + "\r"
        let count = targets.count
        let enviar = { [weak self] in
            guard let self else { return }
            for tab in targets where !tab.closed { tab.write(payload) }
            self.status.text = L("Comando enviado a \(count) pesta\u{00F1}as")
        }
        let peligrosas = PasteRules.dangerousLines(in: command)
        guard !peligrosas.isEmpty else { enviar(); return }
        let visible = SecretMask.masked(PasteRules.visible(command))
        confirmarMulti.show(title: L("¿Enviar «\(visible)» a \(count) pestañas a la vez?"),
                            hint: L("Es una orden peligrosa y MultiExec la escribe en todas las pestañas en las que estás tecleando."),
                            text: visible, editable: false, confirmTitle: L("Enviar a todas"))
        showPanel(confirmarMulti.view)
        confirmarMulti.onConfirm = { [weak self] _ in
            self?.showPanel(nil)
            enviar()
        }
    }

    // MARK: - listas de equipos

    private func prepararListas(_ panel: PanelListas) {
        do {
            let archivo = isDemo ? listasDemo : try ListLibrary(contentsOf: ListLibrary.defaultURL)
            let saltos = MainActor.assumeIsolated { sessions.profiles.filter { $0.transport == .ssh }.map(\.name) }
            panel.mostrar(biblioteca: archivo, estilo: estilo, credenciales: nombresCredenciales(), saltos: saltos)
        } catch {
            status.text = error.localizedDescription
        }
    }

    private func mostrarListas() {
        prepararListas(listas)
        showPanel(listas.view)
    }

    private func ejecutarLista(_ guardada: SavedList) {
        guard loteListas == nil, !guardada.endpoints.isEmpty, !guardada.jump.isEmpty else { return }
        let abort = AbortSwitch()
        loteListas = abort
        showPanel(nil)
        Task { @MainActor [weak self] in
            guard let self else { return }
            var abiertas: [Endpoint: PestanaTerminal] = [:]
            let usuario = guardada.user.isEmpty ? nil : guardada.user
            let ref: CredentialRef? = !isDemo && nombresCredenciales().contains(guardada.credential) ? .named(guardada.credential) : nil
            let dueños = ref.map { self.sessions.owners(ofNamed: $0.account).union(usuario.map { [$0] } ?? []) } ?? []
            let lista = JumpList(name: guardada.name, jump: guardada.jump, user: usuario, devices: guardada.endpoints,
                                 credential: ref.map { CredentialCandidate(ref: $0, owners: dueños, origin: .sessionNamed) })
            let runner = JumpBatchRunner(list: lista, store: KeychainStore(), ledger: ledgerClaves, abort: abort) { [weak self] equipo in
                guard let self,
                      let perfil = sessions.profile(named: lista.jump) ?? (Endpoint(parsing: lista.jump).map { SessionProfile(name: $0.host, user: $0.user, port: $0.port) }),
                      var ruta = try? sessions.route(to: perfil),
                      ruta.transport == .ssh else { return nil }
                ruta.title = equipo.host
                guard let tab = open(ruta) else { return nil }
                let id = ObjectIdentifier(tab)
                entrandoPorLista.insert(id)
                actualizarMultiExec()
                abiertas[equipo] = tab
                return makeTerminalInput(tab)
            }
            runner.onChange = { [weak self] equipo, estado in self?.status.text = "\(lista.name) · \(equipo.host): \(estado.texto)" }
            await runner.run()
            for _ in 0..<runner.settings.maxRetries where !abort.isTripped { await runner.retryFailed() }
            loteListas = nil
            for (equipo, tab) in abiertas {
                entrandoPorLista.remove(ObjectIdentifier(tab))
                if runner.status[equipo] != .connected { excluidasMulti.insert(ObjectIdentifier(tab)) }
            }
            actualizarMultiExec()
            let conectados = runner.status.values.filter { $0 == .connected }.count
            let tabs = lista.devices.compactMap { abiertas[$0] }.filter { tab in !tab.closed && self.terminals.contains(where: { $0 === tab }) }
            if let primero = tabs.first, tabs.count > 1 {
                mostrarDivision(tabs, modo: tabs.count <= 4 ? .grid4 : .grid, activa: primero)
            }
            status.text = L("\(lista.name): \(conectados)/\(lista.devices.count) dentro")
        }
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
            construirBarraBotones()
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
            construirBarraBotones()
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
            EntradaMacro(tab: tab, promptRule: PromptRule(tab.perfil.prompt))
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
            let panes = panelDividido ? terminalesVisibles.compactMap { $0.flatMap { ids[ObjectIdentifier($0)] } } : []
            let layout = modoDivision?.rawValue
            let workspace = Workspace(name: nombre.trimmingCharacters(in: .whitespacesAndNewlines),
                                      tabs: entries, selected: active, layout: layout, panes: panes,
                                      fractions: panelDividido ? pesosDivision : [:])
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
        multiActivo = false

        do {
            let resolved = try MainActor.assumeIsolated { try workspace.resolve(using: sessions) }
            var restored: [WorkspaceTab.ID: PestanaTerminal] = [:]
            for entry in resolved.tabs where entry.route.transport != .sftp && entry.route.transport != .ftp {
                restored[entry.id] = open(entry.route)
            }
            guard let selected = workspace.selected.flatMap({ restored[$0] })
                ?? resolved.tabs.lazy.compactMap({ restored[$0.id] }).first else {
                status.text = L("No se ha podido abrir ninguna pestaña del espacio")
                return
            }
            let panes = workspace.panes.compactMap { restored[$0] }
            showPanel(nil)
            if !panes.isEmpty, let modo = workspace.layout.flatMap(DisposicionTerminal.init(rawValue:)),
               panes.contains(where: { $0 === selected }) {
                pesosDivision = workspace.fractions
                mostrarDivision(panes, modo: modo, activa: selected)
            } else {
                vistaGuardada = nil
                vistaIndividual(selected)
            }
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
        guard !isDemo, settings.buscarActualizaciones else { return }
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
        guard !hayEmergente, let info = startupUpdate else { return }
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
        asistente.settings = { [weak self] in self?.settings ?? AjustesTerminal() }
        asistente.onChange = { [weak self] nuevo in self?.saveAjustes(nuevo) }
        asistente.estilo = { [weak self] in self?.estilo ?? EstiloMac(tema: nil) }
        asistente.reglasDeVistaPrevia = { [weak self] in
            guard let self else { return HighlightConfig() }
            return configResaltado(para: temaGlobal ?? estilo.tema)
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
            let arguments = try tunnel.arguments(route: route, sharing: nil, configFile: isDemo ? try configDemoSSH().path : nil)
            let environment = TerminalEnvironment.prepare(ProcessInfo.processInfo.environment, forSSH: true, sendLocale: settings.enviarIdioma)
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

    /// Los atajos del Mac reciben Mayús cuando Ctrl forma parte de la entrada de la consola.
    private func shortcut(_ key: Int32) -> Bool {
        guard !hayEmergente, GetKeyState(Int32(VK_CONTROL)) < 0 else { return false }
        if GetKeyState(Int32(VK_MENU)) < 0 {
            switch key {
            case 68:
                toggleSplit()
                return true
            case 69:
                showWorkspaces()
                return true
            case 77:
                showMacros()
                return true
            case 84:
                showTuneles()
                return true
            case 82 where GetKeyState(Int32(VK_SHIFT)) < 0:
                recargarSesiones()
                return true
            case 70 where GetKeyState(Int32(VK_SHIFT)) < 0:   // (⌘⇧F del Mac)
                showPanel(nil)
                showBuscarRegistros()
                return true
            case 70:
                var cambios = settings
                cambios.filtroActivo.toggle()
                saveAjustes(cambios)
                return true
            case 75:
                guard let perfil = MainActor.assumeIsolated({ sessions.profile(named: settings.sesionInicio) }) else { return false }
                openProfile(perfil)
                return true
            default: return false
            }
        }
        let shift = GetKeyState(Int32(VK_SHIFT)) < 0
        switch key {
        case 78 where shift:                    // (⌘N del Mac)
            nuevaVentana()
        case 87 where shift:
            showPanel(nil)
            closeSelected()
        case 9:
            cycleTab(shift ? -1 : 1)
        case 219 where shift:
            cycleTab(-1)
        case 221 where shift:
            cycleTab(1)
        case 66 where shift:
            if let selected, SFTPPanel.offers(selected.route) { alternarLateralSFTP(selected) }
            else { showCommandButtons() }
        case 67 where shift || vistas[panelActivo].tieneSeleccion:
            if vistas[panelActivo].copiarSeleccion() { return true }
            return shift
        case 68 where shift:
            if let selected { open(selected.route, perfil: selected.perfil) }
        case 69 where shift:
            showGestorSesiones()
        case 70 where shift:
            showTerminalSearch()
        case 72 where shift:
            var cambios = settings
            cambios.resaltado.toggle()
            saveAjustes(cambios)
        case 76 where shift:
            mostrarListas()
        case 77 where shift:
            multiExec()
        case 84 where shift:
            showPanel(nil)
            open(.local())
        case 75 where shift:
            showHojaConexion()
        case 80 where shift:
            showLlavero()
        case 86 where shift:
            safePaste()
        case 188:
            showAjustes()
        case 190:
            automatizacionActiva?.abort.trip()
            loteListas?.trip()
            MainActor.assumeIsolated {
                for control in clavesTerminal.values { control.cancelar() }
            }
        case 82 where shift:
            if let selected { reconectar(selected) }
        case 83 where shift:
            alternarLateral()
        case 49...57 where !shift:
            showPanel(nil)
            irAPestana(Int(key) - 48)
        case 187, 107:
            zoomLetra(1)
        case 189, 109:
            zoomLetra(-1)
        case 48, 96:
            zoomLetra(nil)
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

    // MARK: - registro de sesiones

    private func vincularRegistro(_ vista: VistaTerminal, tab: @escaping () -> PestanaTerminal?) {
        vista.abrirRegistro = { [weak self] in self?.abrirRuta($0) }
        vista.mostrarRegistro = { [weak self] in self?.abrirRuta($0.deletingLastPathComponent()) }
        vista.pararRegistro = { [weak self] in
            if let tab = tab(), tab.archivoRegistro != nil { self?.alternarRegistro(tab) }
        }
    }

    private func abrirRuta(_ url: URL) {
        let ruta = Array(url.path.utf16) + [0]
        let verbo = Array("open".utf16) + [0]
        _ = ruta.withUnsafeBufferPointer { ruta in
            verbo.withUnsafeBufferPointer { verbo in
                ShellExecuteW(GetActiveWindow(), verbo.baseAddress, ruta.baseAddress, nil, nil, SW_SHOWNORMAL)
            }
        }
    }

    private func empezarRegistro(_ tab: PestanaTerminal) {
        let carpeta = settings.urlRegistro
        do {
            try tab.empezarRegistro(en: carpeta, encolar: { [weak self] accion in
                self?.onUI { _ in accion() }
            }, alFallar: { [weak self, weak tab] motivo in
                guard let self, let tab else { return }
                status.text = L("✗ Se ha dejado de grabar «\(tab.title)»: \(motivo)")
                actualizarRegistro(tab)
            })
        } catch {
            status.text = L("✗ No se graba «\(tab.title)»: no se puede escribir en \(AppPaths.tilde(carpeta.path)) (\(error.localizedDescription))")
        }
    }

    private func alternarRegistro(_ tab: PestanaTerminal) {
        if tab.archivoRegistro != nil { tab.pararRegistro() } else { empezarRegistro(tab) }
        actualizarRegistro(tab)
    }

    private func actualizarRegistro(_ tab: PestanaTerminal) {
        if let separada = ventanasPestana[ObjectIdentifier(tab)] { renderDetached(separada) }
        construirPestanas()
        render()
    }

    // MARK: - tema de colores del terminal

    /// Los colores del tema (de NetDeckCore) en la superficie del terminal, en su paleta y en el texto, por trozos de color.
    private func applyTerminalTheme(_ theme: Theme?) {
        temaGlobal = theme
        paleta = theme.map(PaletaTerminal.init(tema:))
        var contraste = HIGHCONTRASTW()
        contraste.cbSize = UINT(MemoryLayout<HIGHCONTRASTW>.size)
        contrasteActivo = SystemParametersInfoW(UINT(SPI_GETHIGHCONTRAST), contraste.cbSize, &contraste, 0)
            && contraste.dwFlags & DWORD(HCF_HIGHCONTRASTON) != 0
        screenLook = look(tema: theme, texto: paleta?.texto ?? paletaBase.texto)
        for tab in terminals { aplicarPerfil(tab) }
        for separada in ventanasPestana.values {
            aplicarPerfil(separada.session)
            styleDetached(separada)
            renderDetached(separada)
        }
        for vista in vistas { vista.invalidate() }
        render()
    }

    private func look(tema: Theme?, texto: RGB) -> ScreenLook? {
        let filtro = ScreenFilter.resolve(choice: settings.filtro, on: settings.filtroActivo,
                                          theme: tema?.screenFilter, calm: contrasteActivo)
        return filtro.look(intensity: settings.intensidad, text: texto)
    }

    private func aplicarPerfil(_ tab: PestanaTerminal) {
        let perfil = tab.perfil
        tab.temaPantalla = perfil.theme.isEmpty ? temaGlobal : (settings.temaPersonalizado(perfil.theme) ?? temaGlobal)
        tab.paletaPantalla = tab.temaPantalla.map(PaletaTerminal.init(tema:))
        tab.filtroPantalla = look(tema: tab.temaPantalla, texto: tab.paletaPantalla?.texto ?? paletaBase.texto)
        tab.apply(palette: tab.paletaPantalla ?? paletaBase)
        tab.aplicarHistorial(perfil.scrollback ?? settings.scrollback)
    }

    private func vestirTerminal(_ vista: VistaTerminal, _ tab: PestanaTerminal?) {
        let perfil = tab?.perfil ?? TerminalProfile()
        let tema = tab?.temaPantalla ?? temaGlobal
        let colores = tab?.paletaPantalla ?? paleta
        let fuente = perfil.fontFamily.isEmpty ? settings.fuente : perfil.fontFamily
        let tamano: Double
        if perfil.fontSize > 0 {
            tamano = perfil.fontSize
        } else if settings.tamanoAuto, let tema {
            tamano = min(Double(AjustesTerminal.tamanos.upperBound), max(Double(AjustesTerminal.tamanos.lowerBound), Double(tema.size - 1)))
        } else {
            tamano = Double(settings.tamano)
        }
        vista.aplicarFuente(fuente, tamano: tamano, interlineado: perfil.lineSpacing > 0 ? perfil.lineSpacing : settings.interlineado)
        vista.copiarAlSeleccionar = settings.copiarAlSeleccionar
        vista.filtro.apply(tab == nil ? screenLook : tab?.filtroPantalla)
        vista.surface.background = colores.map { brush($0.fondo) } ?? brushTransparente
        if let colores { vista.screen.foreground = brush(colores.texto) }
        else { _ = try? vista.screen.clearValue(TextBlock.foregroundProperty) }
        vista.aplicarSeleccion(tema?.selection)
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

    private func urlReglasActivas() -> URL {
        let netdeck = AppPaths.netdeck.appendingPathComponent("chromaterm.yml")
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let app = exe.appendingPathComponent("Resaltado/netdeck.yml")
        switch settings.origenResaltado {
        case "custom": return highlightURL
        case "netdeck": return netdeck
        case "app": return app
        default:
            if isDemo, resaltadoDemo != nil { return highlightURL }
            return [highlightURL, netdeck].first { FileManager.default.fileExists(atPath: $0.path) } ?? app
        }
    }

    private func highlightText() throws -> String {
        let archivo = urlReglasActivas()
        if archivo == highlightURL, let resaltadoDemo { return resaltadoDemo }
        return try SafeFile.read(archivo) ?? "rules:\n"
    }

    private func configResaltado(para tema: Theme) -> HighlightConfig {
        var cfg = highlightConfig ?? HighlightConfig()
        let base = settings.coloresResaltadoDelTema ? tema.highlightPalette : tema.highlightPalette.merging(cfg.palette) { $1 }
        let personalizados = (settings.coloresResaltado[tema.id] ?? [:]).compactMapValues(RGB.init(hex:))
        cfg.palette = base.merging(personalizados) { $1 }
        return cfg
    }

    private func aplicarResaltado(_ tab: PestanaTerminal) {
        tab.resaltar(settings.resaltado ? configResaltado(para: tab.temaPantalla ?? estilo.tema) : nil)
    }

    private func reloadHighlight() {
        do {
            highlightConfig = try HighlightConfig(text: highlightText())
        } catch {
            highlightConfig = nil
            status.text = error.localizedDescription
        }
        for tab in terminals { aplicarResaltado(tab) }
        for detached in ventanasPestana.values { aplicarResaltado(detached.session) }
    }

    /// «Abrir en el editor…» del Mac: una copia personalizada de las reglas activas (si no la hay), elegida, en tu editor.
    private func personalizarResaltado() {
        let destino = highlightURL
        if !FileManager.default.fileExists(atPath: destino.path) {
            do {
                let texto = try highlightText()
                _ = AppPaths.ensure(destino.deletingLastPathComponent())
                try SafeFile.write(texto, to: destino)
            } catch {
                status.text = L("No se puede guardar: \(error.localizedDescription)")
                return
            }
        }
        var cambios = settings
        cambios.origenResaltado = "custom"
        saveAjustes(cambios)
        reloadHighlight()
        abrirRuta(destino)
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
            settings.origenResaltado = "custom"
            if !isDemo { settings.guardar() }
            reloadHighlight()
            render()
            showAjustes()
            status.text = L("Reglas de resaltado guardadas")
        } catch {
            status.text = L("No se puede guardar: \(error.localizedDescription)")
        }
    }

    private func showGestorSesiones() {
        ajustes.show(settings, estilo: estilo, seccion: "sesiones")
        showPanel(ajustes.view)
    }

    private func showAjustes() {
        status.text = ""
        ajustes.show(settings, estilo: estilo)
        showPanel(ajustes.view)
    }

    private func hideAjustes() { showPanel(nil) }

    private func nombresCredenciales() -> [String] {
        credencialesDisponibles
    }

    private func showLlavero(cuenta: String? = nil, nueva: Bool = false, volverAAjustes: Bool = false) {
        volverAContrasenas = volverAAjustes
        llavero.mostrar(cuenta: cuenta, nueva: nueva)
        showPanel(llavero.view)
    }

    private func prepararClaves(_ tab: PestanaTerminal) {
        guard tab.route.acceptsMultiExec else { return }
        MainActor.assumeIsolated {
            let control = ContrasenasTerminal(io: makeTerminalInput(tab), ledger: ledgerClaves, modo: isDemo ? .off : settings.modoClaveEquipo)
            control.automatizacion.candidates = { [weak self, weak control] peticion in
                guard let self, let pw = control?.automatizacion, let destino = pw.commandTarget else { return [] }
                var solicitud = peticion
                if solicitud.account == nil, let usuario = solicitud.user ?? pw.commandUser {
                    solicitud.account = "\(usuario)@\(destino.host)"
                }
                if let cuenta = solicitud.account, let i = cuenta.lastIndex(of: "@"),
                   !self.sessions.expectedHosts(route: nil, typed: pw.commandHosts)
                    .contains(String(cuenta[cuenta.index(after: i)...]).lowercased()) { return [] }
                return self.sessions.credentialCandidates(for: solicitud, route: nil,
                    defaultCredential: self.settings.credencialPorDefecto, typedHosts: pw.commandHosts, typedTarget: destino)
            }
            control.automatizacion.onOfferChange = { [weak self] _ in self?.actualizarSugerenciaClave() }
            clavesTerminal[ObjectIdentifier(tab)] = control
        }
    }

    private func retirarClaves(_ tab: PestanaTerminal) {
        let control = clavesTerminal.removeValue(forKey: ObjectIdentifier(tab))
        MainActor.assumeIsolated {
            if let control {
                grupoMulti.leave(control.io)
                control.cerrar()
            }
        }
        actualizarSugerenciaClave()
        actualizarMultiExec()
    }

    private func salidaClaves(_ tab: PestanaTerminal) {
        if tab.closed { retirarClaves(tab); return }
        MainActor.assumeIsolated { clavesTerminal[ObjectIdentifier(tab)]?.salida() }
    }

    private func emitirTecleo(_ texto: String, a tab: PestanaTerminal) {
        let meta = tab.perfil.optionAsMeta == true && GetKeyState(Int32(VK_MENU)) < 0
            && GetKeyState(Int32(VK_CONTROL)) >= 0 && texto.unicodeScalars.allSatisfy { $0.value >= 32 }
        let texto = meta ? "\u{1b}" + texto : texto
        let bytes = Array(texto.utf8)
        let control = clavesTerminal[ObjectIdentifier(tab)]
        let riesgo = MainActor.assumeIsolated {
            multiActivo ? control.flatMap { grupoMulti.dangerousEnter(bytes, from: $0.io) } : nil
        }
        if let riesgo {
            confirmarIntroMulti(riesgo.command, pestañas: riesgo.tabs, bytes: bytes, de: tab)
            return
        }
        recordKeys(texto, tab: tab)
        let circulada = MainActor.assumeIsolated {
            guard let control else { return false }
            if multiActivo, grupoMulti.broadcast(bytes, from: control.io) { return true }
            if !entrandoPorLista.contains(ObjectIdentifier(tab)) { control.tecleado(bytes) }
            return false
        }
        if !circulada { tab.write(texto) }
    }

    private func actualizarSugerenciaClave() {
        let cuenta = MainActor.assumeIsolated {
            selected.flatMap { clavesTerminal[ObjectIdentifier($0)]?.automatizacion.offer?.refs.first?.account }
        }
        sugerirClave.visibility = cuenta == nil ? .collapsed : .visible
        if let cuenta {
            sugerirClave.content = EstiloMac.letra(L("Escribir «\(cuenta)»"), tamano: 10, peso: 600, color: estilo.aviso)
            sugerirClave.padding = Thickness(left: 8, top: 0, right: 8, bottom: 0)
            sugerirClave.cornerRadius = EstiloMac.radio(5)
            sugerirClave.background = estilo.panel
        }
    }

    private func usarSugerenciaClave() {
        guard let selected, let control = clavesTerminal[ObjectIdentifier(selected)] else { return }
        Task { @MainActor [weak self, weak control] in
            guard let self, let control, let oferta = control.automatizacion.offer, let ref = oferta.refs.first else { return }
            let resultado = await control.automatizacion.choose(ref, offer: oferta.id, into: control.io)
            if resultado == .typed { self.status.text = L("Contraseña enviada") }
            self.actualizarSugerenciaClave()
        }
    }

    private func showHojaConexion() {
        hojaConexion.show(sesiones: MainActor.assumeIsolated { sessions.profiles.map(\.name) })
        showPanel(hojaConexion.view)
    }

    private func showEdicionRemota() {
        edicionRemota.show()
        showPanel(edicionRemota.view)
    }

    private func showImportador() {
        let existentes = MainActor.assumeIsolated {
            isDemo ? library.sessions : ((try? SessionFile(contentsOf: SessionFile.defaultURL))?.sessions ?? [])
        }
        panelImportador.owner = GetActiveWindow() ?? panelImportador.owner
        panelImportador.show(existentes: existentes, estilo: estilo)
        showPanel(panelImportador.view)
    }

    /// El mismo transporte, ruta y credenciales que en el explorador de la sesión.
    @MainActor
    private func abrirSFTPParaEditar(_ sesion: String) async throws -> SFTPFileSystem {
        guard let perfil = sessions.profile(named: sesion) else { throw CocoaError(.fileNoSuchFile) }
        let ruta = try sessions.route(to: perfil)
        let sftp = ruta.transport == .ssh ? try SFTPPanel.route(for: ruta) : ruta
        let (comando, entorno) = try procesoSFTP(sftp)
        return try await SFTPFileSystem.connect(label: sesion, executable: comando.0,
                                                arguments: comando.1, environment: entorno)
    }

    private func sftpDescargar(sesion: String, remotePath: String, to localURL: URL,
                               progress: @escaping (String) -> Void) async throws {
        progress(L("Conectando\u{2026}"))
        let fs = try await abrirSFTPParaEditar(sesion)
        defer { Task { await fs.close() } }
        let size = await fs.size(of: remotePath) ?? 0
        progress(L("Descargando\u{2026}"))
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let reader = try await fs.openRead(remotePath)
        let writer = try LocalFileWriter(url: localURL)
        try await Transfer.copy(from: reader, to: writer) { sent in
            if size > 0 { progress("\(min(100, sent * 100 / size)) %") }
        }
        await reader.close()
    }

    private func sftpSubir(from localURL: URL, sesion: String, remotePath: String,
                           progress: @escaping (String) -> Void) async throws {
        progress(L("Conectando\u{2026}"))
        let fs = try await abrirSFTPParaEditar(sesion)
        defer { Task { await fs.close() } }
        let size = ((try? FileManager.default.attributesOfItem(atPath: localURL.path))?[.size] as? NSNumber)?.int64Value ?? 0
        progress(L("Subiendo\u{2026}"))
        let source = try LocalFileReader(url: localURL)
        let writer = try await AtomicRemoteWriter.open(fs, remotePath, verify: false, createOnly: false)
        try await Transfer.copy(from: source, to: writer) { sent in
            if size > 0 { progress("\(min(100, sent * 100 / size)) %") }
        }
        await source.close()
    }

    /// Cada cambio de Ajustes se aplica y se guarda al momento, como en el Mac.
    private func windowsEnClaro() -> Bool {
        guard let fondo = try? aparienciaWindows.getColorValue(.background) else { return false }
        return RGB(Double(fondo.r), Double(fondo.g), Double(fondo.b)).luminance > 0.5
    }

    private func saveAjustes(_ new: AjustesTerminal) {
        let otroTema = new.idTemaActual != settings.idTemaActual || new.temaAuto != settings.temaAuto
            || new.coloresTema != settings.coloresTema || new.fuenteInterfaz != settings.fuenteInterfaz
        let otroResaltado = new.origenResaltado != settings.origenResaltado || new.resaltado != settings.resaltado
            || new.coloresResaltadoDelTema != settings.coloresResaltadoDelTema || new.coloresResaltado != settings.coloresResaltado
        let otroInicio = new.sesionInicio != settings.sesionInicio
        if new.divisionApilada != settings.divisionApilada, modoDivision == .side2 || modoDivision == .stack2 {
            modoDivision = new.divisionApilada ? .stack2 : .side2
        }
        settings = new
        MainActor.assumeIsolated {
            for control in clavesTerminal.values { control.cambiarModo(isDemo ? .off : new.modoClaveEquipo) }
        }
        if !isDemo { new.guardar() }
        applySettings(new)
        if otroInicio { prepararMenuNuevo() }
        if otroTema || otroResaltado { ajustes.refrescar(new, estilo: estilo) }
    }

    /// Fuente y tamano al terminal; el tema, a la ventana (Sistema = el de Windows).
    private func applySettings(_ a: AjustesTerminal) {
        DebugLog.enabled = a.depuracion
        updateSplitLayout()
        let temaTerminal = a.temaPersonalizado()
        applyTerminalTheme(temaTerminal)
        for (i, vista) in vistas.enumerated() {
            vestirTerminal(vista, terminalesVisibles.indices.contains(i) ? terminalesVisibles[i] : nil)
        }
        for detached in ventanasPestana.values { vestirTerminal(detached.vista, detached.session) }
        reloadHighlight()
        for tab in ventanasPestana.values { resizeDetached(tab) }
        // El fondo, las barras y claro/oscuro salen del tema (como en el Mac); el marco sólo se rehace si cambia.
        window?.systemBackdrop = nil
        let temaInterfaz = temaTerminal ?? EstiloMac(tema: nil).tema
        let fuente = a.fuenteInterfazActual(tema: temaInterfaz)
        if temaMarco != temaInterfaz || fuenteMarco != fuente {
            temaMarco = temaInterfaz
            fuenteMarco = fuente
            aplicarMarco(temaInterfaz, fuente: fuente)
            for vista in vistas { vista.estiloRegistro = estilo }
            actualizarCabecerasDivision()
        }
        // Botones de órdenes: arriba (bajo las pestañas), abajo (sobre la barra de estado) u ocultos.
        barraBotonesFondo.visibility = a.posicionBotones == "oculta" ? .collapsed : .visible
        Grid.setRow(barraBotonesFondo, Int32(a.posicionBotones == "abajo" ? 3 : 1))
        barraBotonesFondo.borderThickness = a.posicionBotones == "abajo"
            ? Thickness(left: 0, top: 1, right: 0, bottom: 0) : Thickness(left: 0, top: 0, right: 0, bottom: 1)
        if botonesPorGruposAplicado != a.botonesPorGrupos {
            botonesPorGruposAplicado = a.botonesPorGrupos
            construirBarraBotones()
        }
        if iconosConOcultosAplicados != a.toolbarOcultos {
            iconosConOcultosAplicados = a.toolbarOcultos
            construirIconos()
        }
        mostrarLateral(a.listaSesiones)
        resize()
    }

    /// Guarda la sesion: en demo solo en memoria; en real, en el ssh_config de NetDeck. Devuelve true si se guardo.
    private func saveSession(_ session: EditableSession, replacing original: String?) -> Bool {
        guard EditableSession.isValidName(session.name) else {
            status.text = L("El nombre es obligatorio y no puede llevar espacios ni * ? !")
            return false
        }
        guard var file = archivoEditable() else { return false }
        if let original, let index = file.sessions.firstIndex(where: { $0.name == original }) {
            file.sessions[index] = session
        } else {
            file.sessions.append(session)
        }
        guard persistirSesiones(file) else { return false }
        hideEditor()
        status.text = L("Sesión «\(session.name)» guardada")
        return true
    }

    private func archivoEditable() -> SessionFile? {
        if isDemo { return library }
        do {
            let url = SessionFile.defaultURL
            return FileManager.default.fileExists(atPath: url.path) ? try SessionFile(contentsOf: url) : SessionFile()
        } catch {
            status.text = L("No se puede leer el archivo de sesiones: \(error.localizedDescription)")
            return nil
        }
    }

    private func persistirSesiones(_ file: SessionFile) -> Bool {
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
            let config = MainActor.assumeIsolated { SessionManager.defaultConfigURL }
            if let error = file.save(including: config, backup: .standard) {
                status.text = L("No se puede guardar: \(error)")
                return false
            }
            MainActor.assumeIsolated { sessions.load(from: SessionFile.defaultURL) }
        }
        buildSidebar()
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
        session.credential = perfil.namedCredential ?? ""
        session.terminal = perfil.terminal
        return session
    }

    @discardableResult
    private func openProfile(_ perfil: SessionProfile) -> PestanaTerminal? {
        do {
            let ruta = try MainActor.assumeIsolated { try sessions.route(to: perfil) }
            try? SessionLists.noteRecent(perfil.name, in: recientesURL)
            sesionLateral = perfil.name
            let tab = open(ruta)
            buildSidebar()
            return tab
        } catch {
            status.text = L("No se puede abrir \u{00AB}\(perfil.name)\u{00BB}: \(error.localizedDescription)")
            return nil
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

    // MARK: - SFTP junto al terminal

    private func configurarLateralSFTP() {
        marcoSFTPLateral.visibility = .collapsed
        marcoSFTPLateral.children.append(zonaSFTPLateral)
        asaSFTP.width = 6
        asaSFTP.horizontalAlignment = .left
        asaSFTP.background = estilo.transparente
        ToolTipService.setToolTip(asaSFTP, L("Arrastra para cambiar el ancho del explorador"))
        asaSFTP.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args, let punto = try? args.getCurrentPoint(marco),
                  punto.properties.isLeftButtonPressed else { return }
            arrastreSFTP = (Double(punto.position.x), zonaSFTPLateral.width)
            _ = try? asaSFTP.capturePointer(args.pointer)
            args.handled = true
        }
        asaSFTP.pointerMoved.addHandler { [weak self] _, args in
            guard let self, let inicio = arrastreSFTP, let args,
                  let punto = try? args.getCurrentPoint(marco) else { return }
            let ancho = inicio.ancho + inicio.x - Double(punto.position.x)
            zonaSFTPLateral.width = SFTPPanelLayout.clamp(ancho, available: rootView?.actualWidth)
            args.handled = true
        }
        asaSFTP.pointerReleased.addHandler { [weak self] _, args in
            guard let self, arrastreSFTP != nil, let args else { return }
            arrastreSFTP = nil
            try? asaSFTP.releasePointerCapture(args.pointer)
            if let selected {
                let actual = SFTPPanelLayout(visible: true, width: zonaSFTPLateral.width)
                try? ajustesSFTP.set(actual, for: SFTPPanel.key(for: selected.route))
            }
            args.handled = true
        }
        asaSFTP.pointerCaptureLost.addHandler { [weak self] _, _ in self?.arrastreSFTP = nil }
        marcoSFTPLateral.children.append(asaSFTP)
        zonaSFTPLateral.borderThickness = Thickness(left: 1, top: 0, right: 0, bottom: 0)
        esperaSFTP.padding = Thickness(left: 14, top: 14, right: 14, bottom: 14)
        esperaSFTP.spacing = 8
        textoEsperaSFTP.text = L("El explorador se conecta cuando entre el terminal")
        textoEsperaSFTP.textWrapping = .wrap
        esperaSFTP.children.append(textoEsperaSFTP)
        conectarLateral.content = L("Conectar ya")
        conectarLateral.click.addHandler { [weak self] _, _ in
            guard let self, let selected else { return }
            intentarLateralSFTP(selected, forzar: true)
        }
        esperaSFTP.children.append(conectarLateral)
    }

    private func prepararLateralSFTP(_ tab: PestanaTerminal) {
        do {
            let panel = ExploradorLateral(try SFTPPanel.route(for: tab.route))
            panel.explorador.enqueue = { [weak self] accion in self?.onUI { _ in accion() } }
            panel.explorador.onClose = { [weak self, weak tab] in
                if let tab { self?.alternarLateralSFTP(tab, cerrarConexion: true) }
            }
            panelesSFTP[ObjectIdentifier(tab)] = panel
        } catch {
            status.text = error.localizedDescription
        }
    }

    private func alternarLateralSFTP(_ tab: PestanaTerminal, cerrarConexion: Bool = false) {
        let id = ObjectIdentifier(tab)
        if let panel = panelesSFTP[id] {
            panel.visible.toggle()
            if cerrarConexion { panel.iniciado = false }
        } else {
            prepararLateralSFTP(tab)
        }
        let clave = SFTPPanel.key(for: tab.route)
        var disposicion = ajustesSFTP.layout(for: clave)
        disposicion.visible = panelesSFTP[id]?.visible == true
        try? ajustesSFTP.set(disposicion, for: clave)
        if selected !== tab { select(tab) }
        intentarLateralSFTP(tab, forzar: false)
        mostrarLateralSFTP()
        construirPestanas()
    }

    private func mostrarLateralSFTP() {
        guard !panelDividido, let selected, let panel = panelesSFTP[ObjectIdentifier(selected)], panel.visible else {
            zonaSFTPLateral.child = nil
            marcoSFTPLateral.visibility = .collapsed
            return
        }
        let disposicion = ajustesSFTP.layout(for: SFTPPanel.key(for: selected.route))
        zonaSFTPLateral.width = SFTPPanelLayout.clamp(disposicion.width, available: rootView?.actualWidth)
        let contenido = panel.iniciado ? (panel.explorador.view as UIElement) : esperaSFTP
        if zonaSFTPLateral.child != contenido { zonaSFTPLateral.child = contenido }
        marcoSFTPLateral.visibility = .visible
    }

    private func intentarLateralSFTP(_ tab: PestanaTerminal, forzar: Bool) {
        guard let panel = panelesSFTP[ObjectIdentifier(tab)], panel.visible, !panel.iniciado, !tab.closed else { return }
        let conectado = MainActor.assumeIsolated { clavesTerminal[ObjectIdentifier(tab)]?.conectado == true }
        guard forzar || conectado else { return }
        guard conectarExplorador(panel.explorador, ruta: panel.ruta) else { return }
        panel.iniciado = true
        if selected === tab { mostrarLateralSFTP() }
    }

    private func cerrarLateralSFTP(_ tab: PestanaTerminal) {
        guard let panel = panelesSFTP.removeValue(forKey: ObjectIdentifier(tab)) else { return }
        panel.explorador.disconnect()
        mostrarLateralSFTP()
    }

    private func configDemoSSH() throws -> URL {
        let url = AppPaths.home.appendingPathComponent("ssh_config")
        let conocidos = AppPaths.home.appendingPathComponent("known_hosts").path.replacingOccurrences(of: "\\", with: "/")
        let ajustes = """
        UserKnownHostsFile "\(conocidos)"
        GlobalKnownHostsFile none
        IdentityAgent none
        IdentityFile none
        ConnectTimeout 8

        """
        try SafeFile.write(ajustes + "\n" + library.render(), to: url)
        return url
    }

    private func procesoSFTP(_ ruta: ConnectionRoute) throws -> ((String, [String]), [String: String]) {
        let dev = isDemo ? ProcessInfo.processInfo.environment["NETDECK_SFTP_SERVER"] : nil
        let config = isDemo ? try configDemoSSH().path : MainActor.assumeIsolated { sessions.source?.path }
        guard let command = dev.map({ ($0, [String]()) }) ?? ruta.sftpSubsystemCommand(sharing: nil, configFile: config) else {
            throw RouteError.badDevice(ruta.target.host)
        }
        var env = TerminalEnvironment.prepare(ProcessInfo.processInfo.environment, forSSH: true, sendLocale: settings.enviarIdioma)
        let helper = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("NetDeckAskpass.exe")
        if !isDemo, FileManager.default.fileExists(atPath: helper.path) {
            var askpass = Askpass.environment(executable: helper.path, configPath: config, session: Foundation.UUID(),
                                              manual: !settings.contrasenaAutomatica, profile: ruta.sessionName, route: ruta)
            if !settings.ofrecerGuardar { askpass[Askpass.noOfferSaveFlag] = "1" }
            env.merge(askpass) { _, valor in valor }
        }
        return (command, env)
    }

    private func conectarExplorador(_ explorador: ExploradorSFTP, ruta: ConnectionRoute) -> Bool {
        do {
            let (command, env) = try procesoSFTP(ruta)
            explorador.connect(label: ruta.title, executable: command.0, arguments: command.1, environment: env)
            return true
        } catch {
            status.text = error.localizedDescription
            return false
        }
    }

    /// Abre el explorador SFTP (ssh con el subsistema sftp) en el area principal.
    private func openSFTP(_ route: ConnectionRoute) {
        guard conectarExplorador(explorador, ruta: route) else { return }
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
    private func open(_ route: ConnectionRoute, perfil: TerminalProfile? = nil) -> PestanaTerminal? {
        if !isDemo { SessionFile.repairPermissions() }
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
            let config = isDemo && !route.isLocal && route.transport != .serial
                ? try configDemoSSH() : MainActor.assumeIsolated { sessions.source }
            let perfil = perfil ?? route.transientProfile ?? MainActor.assumeIsolated { route.sessionName.flatMap { sessions.profile(named: $0)?.terminal } }
                ?? TerminalProfile()
            let session = try PestanaTerminal(route: route, config: config, perfil: perfil,
                                              contrasenaAutomatica: settings.contrasenaAutomatica, ofrecerGuardar: settings.ofrecerGuardar,
                                              enviarIdioma: settings.enviarIdioma)
            let queue = window?.dispatcherQueue
            aplicarPerfil(session)
            terminals.append(session)
            prepararClaves(session)
            aplicarResaltado(session)
            if settings.grabarSesiones { empezarRegistro(session) }
            if SFTPPanel.offers(route), ajustesSFTP.layout(for: SFTPPanel.key(for: route)).visible {
                prepararLateralSFTP(session)
            }
            select(session)
            session.observe(enqueue: { action in
                (try? queue?.tryEnqueue { action() }) == true
            }, changed: { [weak self, weak session] in
                guard let self, let session else { return }
                self.salidaClaves(session)
                if session.closed { self.cerrarLateralSFTP(session) }
                else if self.panelesSFTP[ObjectIdentifier(session)]?.iniciado == false {
                    self.intentarLateralSFTP(session, forzar: false)
                }
                if session.closed, self.automatizacionActiva?.tab === session { self.automatizacionActiva?.abort.trip() }
                if session.closed, self.grabando?.tab === session { self.finishRecording() }
                if let detached = self.ventanasPestana[ObjectIdentifier(session)] {
                    self.renderDetached(detached)
                    return
                }
                guard let index = self.terminalesVisibles.firstIndex(where: { $0 === session }) else { return }
                self.render(index)
                if session.closed {
                    self.construirPestanas()
                    self.actualizarMultiExec()
                    if self.selected === session { self.status.text = L("Conexión cerrada") }
                }
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
        } else if let modo = modoDivision {
            vistaGuardada = (modo, terminalesVisibles.compactMap { $0 })
            modoDivision = nil
            terminalesVisibles = [session]
            panelActivo = 0
            updateSplitLayout()
        } else {
            terminalesVisibles = [session]
        }
        selected = session
        status.text = session?.closed == true ? L("Conexión cerrada") : ""
        construirPestanas()
        actualizarSugerenciaClave()
        actualizarMultiExec()
        mostrarLateralSFTP()
        buildSidebar()
        closeButton.isEnabled = session != nil
        resize()
        render()
        if focus { focusTerminal() }
    }

    /// Pestañas como las del Mac: píldoras de 29 de alto (96 a 200 de ancho) con el punto de estado, el título y la ✕
    /// en la elegida; la elegida, del color de la pestaña del tema; las demás, del panel.
    private func construirPestanas() {
        let e = estilo
        tabs.children.clear()
        if panelDividido || vistaGuardada != nil {
            let cuenta = panelDividido ? terminalesVisibles.compactMap { $0 }.count : (vistaGuardada?.paneles.count ?? 0)
            let chip = Button()
            e.vestirIcono(chip, Glifo.dividir, ayuda: L("Pantalla dividida"), id: "MostrarVista")
            chip.content = EstiloMac.letra(L("VISTA ×\(cuenta)"), tamano: 11, peso: 700,
                                           color: panelDividido ? e.fondo : e.acento)
            chip.height = 29
            chip.background = panelDividido ? e.acento : e.panel(alfa: 0.7)
            chip.click.addHandler { [weak self] _, _ in
                guard let self, !panelDividido else { return }
                toggleSplit()
            }
            let menu = MenuFlyout()
            accionMenu(menu, L("Volver a pestañas sueltas")) { [weak self] in
                guard let self else { return }
                vistaGuardada = nil
                vistaIndividual(selected)
            }
            chip.contextFlyout = menu
            tabs.children.append(chip)
        }
        for candidate in terminals {
            let elegida = candidate === selected
            let contenido = filaLateral(columnas: [.auto, .star, .auto])
            let punto = EstiloMac.letra("\u{25CF}", tamano: 9, color: candidate.closed ? e.mal : e.bien)
            punto.margin = Thickness(left: 0, top: 0, right: 7, bottom: 0)
            let titulo = EstiloMac.letra(self.titulo(candidate), tamano: 12, peso: 600,
                                         color: elegida ? e.sobrePestana : e.acento2)
            var partes: [FrameworkElement] = [punto, titulo]
            if elegida {
                let cerrar = Button()
                cerrar.content = EstiloMac.icono(Glifo.cerrar, tamano: 9, color: e.sobrePestana)
                cerrar.background = e.transparente
                cerrar.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
                cerrar.cornerRadius = EstiloMac.radio(5)
                cerrar.width = 22
                cerrar.height = 22
                cerrar.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
                cerrar.margin = Thickness(left: 6, top: 0, right: 0, bottom: 0)
                AutomationProperties.setAutomationId(cerrar, "CerrarPestana")
                AutomationProperties.setName(cerrar, L("Cerrar pesta\u{00F1}a"))
                ToolTipService.setToolTip(cerrar, L("Cerrar pesta\u{00F1}a"))
                cerrar.click.addHandler { [weak self] _, _ in self?.closeSelected() }
                partes.append(cerrar)
            }
            colocar(partes, en: contenido)
            let tab = Button()
            tab.content = contenido
            tab.height = 29
            tab.minWidth = 96
            tab.maxWidth = 200
            tab.padding = Thickness(left: 12, top: 0, right: elegida ? 4 : 12, bottom: 0)
            tab.cornerRadius = EstiloMac.radio(10)
            tab.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
            tab.background = elegida ? e.pestana : e.panel(alfa: 0.6)
            EstiloMac.conservarColores(tab, encima: elegida ? e.pestana : e.acento(alfa: 0.25),
                                       pulsado: elegida ? e.pestana : e.acento(alfa: 0.4))
            tab.horizontalContentAlignment = .stretch
            tab.verticalAlignment = .center
            AutomationProperties.setName(tab, self.titulo(candidate))
            tab.click.addHandler { [weak self, weak candidate] _, _ in
                guard let candidate else { return }
                self?.select(candidate)
            }
            let menu = MenuFlyout()
            var acciones: [(String, Bool, (PestanaTerminal) -> Void)] = [
                (L("Reconectar"), candidate.route.transport != .local, { [weak self] in self?.reconectar($0) }),
                (L("Clonar (otra pestaña igual)"), true, { [weak self] in _ = self?.open($0.route, perfil: $0.perfil) }),
                (L("Renombrar la pestaña…"), true, { [weak self] in self?.renombrarPestana($0) }),
                (L("Mover a una ventana nueva"), !candidate.closed && terminals.count > 1, { [weak self] in self?.detach($0) }),
            ]
            if nombresPestana[ObjectIdentifier(candidate)] != nil {
                acciones.insert((L("Volver al nombre del equipo"), true, { [weak self] tab in
                    self?.nombresPestana[ObjectIdentifier(tab)] = nil
                    self?.construirPestanas()
                }), at: 3)
            }
            let enVista = panelDividido && terminalesVisibles.contains { $0 === candidate }
            acciones.append((enVista ? L("Quitar de la vista dividida") : L("Añadir a la vista dividida"),
                             terminals.count > 1, { [weak self] in self?.cambiarVistaDividida($0) }))
            if (multiActivo || panelDividido) && candidate.route.acceptsMultiExec {
                let incluida = !excluidasMulti.contains(ObjectIdentifier(candidate))
                acciones.append((incluida ? L("Excluir de MultiExec") : L("Incluir en MultiExec"),
                                 !candidate.closed, { [weak self] tab in
                    guard let self else { return }
                    let id = ObjectIdentifier(tab)
                    if !excluidasMulti.insert(id).inserted { excluidasMulti.remove(id) }
                    actualizarMultiExec()
                    construirPestanas()
                }))
            }
            if SFTPPanel.offers(candidate.route) {
                let visible = panelesSFTP[ObjectIdentifier(candidate)]?.visible == true
                acciones.append((visible ? L("Ocultar el explorador SFTP") : L("Explorador SFTP al lado (Ctrl+Mayús+B)"),
                                 !candidate.closed, { [weak self] in self?.alternarLateralSFTP($0) }))
            }
            acciones.append((L("Buscar en el terminal"), true, { [weak self] tab in
                self?.select(tab)
                self?.showTerminalSearch()
            }))
            if candidate.route.transport == .serial {
                acciones.append((L("Enviar BREAK (consola serie)"), !candidate.closed, { $0.enviarBreak() }))
            }
            acciones.append((candidate.archivoRegistro == nil ? L("● Grabar registro") : L("■ Parar el registro"),
                             !candidate.closed || candidate.archivoRegistro != nil, { [weak self] in self?.alternarRegistro($0) }))
            if let archivo = candidate.archivoRegistro {
                acciones.append((L("Abrir el registro"), true, { [weak self] _ in self?.abrirRuta(archivo) }))
            }
            for (texto, activa, accion) in acciones {
                let item = MenuFlyoutItem()
                item.text = texto
                item.isEnabled = activa
                item.click.addHandler { [weak candidate] _, _ in
                    guard let candidate else { return }
                    accion(candidate)
                }
                menu.items.append(item)
            }
            menu.items.append(MenuFlyoutSeparator())
            let cerrarItem = MenuFlyoutItem()
            cerrarItem.text = L("Cerrar pestaña (Ctrl+Mayús+W)")
            cerrarItem.click.addHandler { [weak self, weak candidate] _, _ in
                guard let candidate else { return }
                self?.cerrarPestana(candidate)
            }
            menu.items.append(cerrarItem)
            tab.contextFlyout = menu
            tabs.children.append(tab)
        }
    }

    private func reordenar(_ tab: PestanaTerminal, en destino: Int) {
        guard let origen = terminals.firstIndex(where: { $0 === tab }), !terminals.isEmpty else { return }
        let objetivo = min(terminals.count - 1, max(0, destino))
        guard origen != objetivo else { return }
        terminals.remove(at: origen)
        terminals.insert(tab, at: objetivo)
        construirPestanas()
    }

    private func punteroFueraDeVentana() -> Bool {
        guard let appWindow = window?.appWindow else { return false }
        var punto = POINT(x: 0, y: 0)
        guard GetCursorPos(&punto) else { return false }
        let origen = appWindow.position
        let tamano = appWindow.size
        return punto.x < origen.x || punto.y < origen.y
            || punto.x >= origen.x + tamano.width || punto.y >= origen.y + tamano.height
    }

    // Button marca PointerPressed/Released como manejados y WinUI no los entrega a handlers normales, así que el
    // arrastre no se apoya en eventos: se sondea el ratón con Win32 y se localiza la pestaña por geometría.
    private func configurarArrastrePestanas() {
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard let self else { return }
                _ = try? self.window?.dispatcherQueue?.tryEnqueue { [weak self] in self?.sondearArrastre() }
            }
        }
    }

    private func puntoEnVentana(_ cursor: POINT) -> (x: Double, y: Double)? {
        // (la ventana bajo el cursor, no la activa: si la ventana está en segundo plano, el clic que la activa también arranca el arrastre)
        guard let sobre = WindowFromPoint(cursor), let hwnd = GetAncestor(sobre, UINT(GA_ROOT)),
              let appWindow = window?.appWindow else { return nil }
        var proceso: DWORD = 0
        GetWindowThreadProcessId(hwnd, &proceso)
        var marco = RECT()
        guard proceso == GetCurrentProcessId(), GetWindowRect(hwnd, &marco),
              abs(Int(marco.left) - Int(appWindow.position.x)) <= 24,
              abs(Int(marco.top) - Int(appWindow.position.y)) <= 24 else { return nil }
        var punto = cursor
        guard ScreenToClient(hwnd, &punto) else { return nil }
        let escala = window?.content?.xamlRoot?.rasterizationScale ?? 1
        return (Double(punto.x) / escala, Double(punto.y) / escala)
    }

    private func origenEnVentana(_ elemento: UIElement) -> (x: Double, y: Double)? {
        guard let p = try? elemento.transformToVisual(nil)?.transformPoint(Point(x: 0, y: 0)) else { return nil }
        return (Double(p.x), Double(p.y))
    }

    private func pestana(en cursor: POINT) -> PestanaTerminal? {
        guard let punto = puntoEnVentana(cursor) else { return nil }
        let desfase = panelDividido || vistaGuardada != nil ? 1 : 0
        for (indice, hijo) in tabs.children.enumerated() {
            let posicion = indice - desfase
            guard posicion >= 0, posicion < terminals.count, let elemento = hijo as? FrameworkElement,
                  let origen = origenEnVentana(elemento) else { continue }
            let ancho = elemento.actualWidth, alto = elemento.actualHeight
            guard punto.x >= origen.x, punto.x < origen.x + ancho, punto.y >= origen.y, punto.y < origen.y + alto else { continue }
            let candidata = terminals[posicion]
            if candidata === selected && punto.x > origen.x + ancho - 30 { return nil }
            return candidata
        }
        return nil
    }

    private struct AnimacionArrastre {
        let sesion: PestanaTerminal
        var elementos: [FrameworkElement]
        var transformaciones: [TranslateTransform]
        var x: [Double]
        var ancho: [Double]
        var actual: [Double]
        var objetivo: [Double]
        var origen: Int
        var destino: Int
        var desplazamiento = 0.0
        var metaSoltar = 0.0
        var fuera = false
        var soltando = false
        var cuadros = 0
    }
    private var animacionArrastre: AnimacionArrastre?

    private func iniciarArrastre(_ sesion: PestanaTerminal) {
        if selected !== sesion { select(sesion, focus: false) }
        try? tabs.updateLayout()
        guard let panel = origenEnVentana(tabs), let origen = terminals.firstIndex(where: { $0 === sesion }) else { return }
        let desfase = panelDividido || vistaGuardada != nil ? 1 : 0
        var elementos: [FrameworkElement] = []
        var transformaciones: [TranslateTransform] = []
        var xs: [Double] = [], anchos: [Double] = []
        for (indice, hijo) in tabs.children.enumerated() where indice >= desfase {
            guard let elemento = hijo as? FrameworkElement, let punto = origenEnVentana(elemento) else { return }
            let transformacion = TranslateTransform()
            elemento.renderTransform = transformacion
            elementos.append(elemento)
            transformaciones.append(transformacion)
            xs.append(punto.x - panel.x)
            anchos.append(elemento.actualWidth)
        }
        guard elementos.count == terminals.count else { return }
        Canvas.setZIndex(elementos[origen], 10)
        let ceros = Array(repeating: 0.0, count: elementos.count)
        animacionArrastre = AnimacionArrastre(sesion: sesion, elementos: elementos, transformaciones: transformaciones,
                                              x: xs, ancho: anchos, actual: ceros, objetivo: ceros,
                                              origen: origen, destino: origen)
    }

    private func aplicarArrastre(_ a: inout AnimacionArrastre, congelar: Bool) {
        let n = a.elementos.count, d = a.origen
        if !congelar {
            let hueco = a.ancho[d] + tabs.spacing
            let borde = a.x[d] + a.desplazamiento
            var destino = d
            for k in 0..<n where k != d {
                var meta = 0.0
                if !a.fuera {
                    let medio = a.x[k] + a.ancho[k] / 2
                    // (por el borde de avance, no por el centro: la elegida es más ancha por la ✕ y con el centro no llegaba a la primera)
                    if k > d && medio <= borde + a.ancho[d] { meta = -hueco; destino += 1 }
                    else if k < d && medio >= borde { meta = hueco; destino -= 1 }
                }
                a.objetivo[k] = meta
            }
            a.destino = destino
        }
        for k in 0..<n where k != d {
            a.actual[k] += (a.objetivo[k] - a.actual[k]) * 0.35
            if abs(a.objetivo[k] - a.actual[k]) < 0.3 { a.actual[k] = a.objetivo[k] }
            a.transformaciones[k].x = a.actual[k]
        }
        a.transformaciones[d].x = a.desplazamiento
        a.elementos[d].opacity = a.fuera ? 0.4 : 1
    }

    private func animarArrastre(cursor: POINT, inicioX: Double) {
        guard var a = animacionArrastre, let ultimo = a.x.indices.last else { return }
        let escala = window?.content?.xamlRoot?.rasterizationScale ?? 1
        let d = a.origen
        let bruto = (Double(cursor.x) - inicioX) / escala
        a.desplazamiento = min(max(bruto, a.x[0] - a.x[d]), a.x[ultimo] + a.ancho[ultimo] - a.ancho[d] - a.x[d])
        a.fuera = punteroFueraDeVentana()
        aplicarArrastre(&a, congelar: false)
        animacionArrastre = a
    }

    private func terminarArrastre(_ sesion: PestanaTerminal) {
        guard var a = animacionArrastre else { construirPestanas(); return }
        if a.fuera && terminals.count > 1 {
            animacionArrastre = nil
            detach(sesion)
            return
        }
        if a.fuera {
            a.fuera = false
            a.destino = a.origen
            a.objetivo = Array(repeating: 0.0, count: a.objetivo.count)
        }
        let d = a.origen, t = a.destino
        var meta = 0.0
        if t > d { for k in (d + 1)...t { meta += a.ancho[k] + tabs.spacing } }
        else if t < d { for k in t..<d { meta -= a.ancho[k] + tabs.spacing } }
        a.metaSoltar = meta
        a.soltando = true
        a.cuadros = 0
        animacionArrastre = a
    }

    private func avanzarSoltado() {
        guard var a = animacionArrastre else { return }
        a.cuadros += 1
        a.desplazamiento += (a.metaSoltar - a.desplazamiento) * 0.4
        let listo = abs(a.metaSoltar - a.desplazamiento) < 0.5 || a.cuadros > 14
        if listo { a.desplazamiento = a.metaSoltar }
        aplicarArrastre(&a, congelar: true)
        animacionArrastre = a
        guard listo else { return }
        animacionArrastre = nil
        if a.destino != a.origen {
            reordenar(a.sesion, en: a.destino)
        } else {
            Canvas.setZIndex(a.elementos[a.origen], 0)
        }
    }

    private func sondearArrastre() {
        let abajo = (GetAsyncKeyState(Int32(VK_LBUTTON)) & Int16(bitPattern: 0x8000)) != 0
        defer { botonIzquierdoAbajo = abajo }
        if animacionArrastre?.soltando == true { avanzarSoltado(); return }
        var cursor = POINT(x: 0, y: 0)
        guard GetCursorPos(&cursor) else { return }
        if !abajo {
            guard let arrastre = arrastrePestana else { return }
            arrastrePestana = nil
            if arrastre.activo { terminarArrastre(arrastre.sesion) }
            return
        }
        if !botonIzquierdoAbajo {
            arrastrePestana = nil
            if let sesion = pestana(en: cursor) {
                arrastrePestana = (sesion, Double(cursor.x), Double(cursor.y), false)
            }
            return
        }
        guard var arrastre = arrastrePestana else { return }
        guard terminals.contains(where: { $0 === arrastre.sesion }) else { arrastrePestana = nil; return }
        if !arrastre.activo {
            guard hypot(Double(cursor.x) - arrastre.x, Double(cursor.y) - arrastre.y) >= 8 else { return }
            arrastre.activo = true
            arrastrePestana = arrastre
            iniciarArrastre(arrastre.sesion)
        }
        animarArrastre(cursor: cursor, inicioX: arrastre.x)
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
        nombresPestana[ObjectIdentifier(tab)] = nil
        excluidasMulti.remove(ObjectIdentifier(tab))
        if tab.closed {
            retirarClaves(tab)
            cerrarLateralSFTP(tab)
        }
        if let guardada = vistaGuardada {
            let paneles = guardada.paneles.filter { $0 !== tab }
            vistaGuardada = paneles.isEmpty ? nil : (guardada.modo, paneles)
        }
        if panelDividido, terminalesVisibles.contains(where: { $0 === tab }) {
            sacarDeVista(tab)
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
        let e = estilo
        let root = StackPanel()
        root.orientation = .horizontal
        root.background = e.barra
        let volver = Button()
        volver.content = EstiloMac.letra(L("Devolver pestaña"), tamano: 12, peso: 500, color: e.texto)
        volver.background = e.panel(alfa: 0.6)
        volver.borderBrush = e.acento(alfa: 0.6)
        volver.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        volver.cornerRadius = EstiloMac.radio(5)
        EstiloMac.conservarColores(volver, encima: e.acento(alfa: 0.18), pulsado: e.acento(alfa: 0.3), borde: e.acento(alfa: 0.6))
        volver.margin = Thickness(left: 8, top: 4, right: 8, bottom: 4)
        AutomationProperties.setAutomationId(volver, "DevolverPestana")
        volver.click.addHandler { [weak self] _, _ in self?.returnToMain(id) }
        root.children.append(volver)
        let grid = Grid()
        grid.background = e.fondo
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

        vincularRegistro(vista) { [weak tab] in tab }
        vista.alDesplazar = { [weak self] in
            if let detached = self?.ventanasPestana[id] { self?.renderDetached(detached) }
        }
        vista.alActivar = { [weak vista] in _ = try? vista?.surface.focus(.programmatic) }
        vista.surface.sizeChanged.addHandler { [weak self] _, _ in
            if let detached = self?.ventanasPestana[id] { self?.resizeDetached(detached) }
        }
        vista.surface.keyDown.addHandler { [weak self, weak tab, weak vista] _, args in
            guard let self, let tab, let vista, let args else { return }
            if args.key.rawValue == 67, GetKeyState(Int32(VK_CONTROL)) < 0,
               vista.copiarSeleccion() {
                args.handled = true
                return
            }
            guard !tab.closed, let keys = self.keySequence(args.key.rawValue, tab: tab) else { return }
            args.handled = true
            if self.automatizacionActiva?.tab === tab {
                guard AbortKey.isAbort(keys.utf8) else { return }
                self.automatizacionActiva?.abort.trip()
                if keys == "\u{1b}" { return }
            }
            if self.dispatchButtonHotkey(keys, tab: tab) { return }
            self.emitirTecleo(keys, a: tab)
        }
        vista.surface.characterReceived.addHandler { [weak self, weak tab] _, args in
            guard let self, let tab, !tab.closed, let args else { return }
            let text = String(args.character)
            guard text.rangeOfCharacter(from: .controlCharacters) == nil else { return }
            args.handled = true
            if self.automatizacionActiva?.tab !== tab { self.emitirTecleo(text, a: tab) }
        }
        window.closed.addHandler { [weak self] _, _ in
            if let self, let tab = ventanasPestana.removeValue(forKey: id)?.session {
                tab.close()
                retirarClaves(tab)
                cerrarLateralSFTP(tab)
            }
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
        let e = estilo
        if let barra = detached.window.appWindow?.titleBar {
            let fondo = EstiloMac.color(e.tema.bar)
            barra.backgroundColor = fondo
            barra.inactiveBackgroundColor = fondo
            barra.foregroundColor = EstiloMac.color(e.tema.text)
            barra.inactiveForegroundColor = EstiloMac.color(e.tema.dim)
            barra.buttonBackgroundColor = fondo
            barra.buttonInactiveBackgroundColor = fondo
            barra.buttonForegroundColor = EstiloMac.color(e.tema.text)
            barra.buttonInactiveForegroundColor = EstiloMac.color(e.tema.dim)
            barra.buttonHoverBackgroundColor = EstiloMac.color(e.tema.panel)
        }
        detached.vista.invalidate()
        detached.vista.estiloRegistro = estilo
        vestirTerminal(detached.vista, detached.session)
    }

    private func renderDetached(_ detached: VentanaPestana) {
        detached.vista.render(detached.session, palette: detached.session.paletaPantalla ?? paletaBase,
                              cursorActive: true, brush: brush)
    }

    private func resizeDetached(_ detached: VentanaPestana) {
        let vista = detached.vista
        guard vista.surface.actualWidth > 22, vista.surface.actualHeight > 16 else { return }
        detached.session.resize(cols: vista.columnas, rows: vista.filas)
        renderDetached(detached)
    }

    private enum DisposicionTerminal: String, CaseIterable {
        case side2, stack2, cols3, onePlusTwo, grid4, grid

        var titulo: String {
            switch self {
            case .side2: L("2 lado a lado")
            case .stack2: L("2 arriba y abajo")
            case .cols3: L("3 columnas")
            case .onePlusTwo: L("1 + 2")
            case .grid4: L("4 (2 × 2)")
            case .grid: L("Todas (cuadrícula)")
            }
        }

        var capacidad: Int {
            switch self {
            case .side2, .stack2: 2
            case .cols3, .onePlusTwo: 3
            case .grid4: 4
            case .grid: .max
            }
        }
    }

    private var divisionPorDefecto: DisposicionTerminal { settings.divisionApilada ? .stack2 : .side2 }

    private func prepararMenuDivision() {
        let menu = MenuFlyout()
        for modo in DisposicionTerminal.allCases {
            accionMenu(menu, modo.titulo) { [weak self] in self?.dividirEn(modo) }
        }
        menu.items.append(MenuFlyoutSeparator())
        let sueltas = MenuFlyoutItem()
        sueltas.text = L("Volver a pestañas sueltas")
        sueltas.isEnabled = panelDividido || vistaGuardada != nil
        sueltas.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            vistaGuardada = nil
            vistaIndividual(selected)
        }
        menu.items.append(sueltas)
        dividir.flyout = menu
    }

    private func dividirEn(_ modo: DisposicionTerminal) {
        if terminals.isEmpty { open(.local()) }
        guard let selected else { return }
        pesosDivision = [:]
        mostrarDivision([selected] + terminals.filter { $0 !== selected }, modo: modo, activa: selected, forzar: true)
    }

    private func mostrarDivision(_ tabs: [PestanaTerminal], modo: DisposicionTerminal, activa: PestanaTerminal,
                                 forzar: Bool = false) {
        terminalesVisibles = tabs.prefix(modo.capacidad).map(Optional.some)
        while terminalesVisibles.count < (modo == .grid ? 1 : modo.capacidad) { terminalesVisibles.append(nil) }
        panelActivo = terminalesVisibles.firstIndex(where: { $0 === activa }) ?? 0
        modoDivision = modo
        vistaGuardada = nil
        updateSplitLayout(forzar: forzar)
        showPanel(nil)
        select(terminalEn(panelActivo))
    }

    private func vistaIndividual(_ tab: PestanaTerminal?) {
        terminalesVisibles = [tab]
        panelActivo = 0
        modoDivision = nil
        updateSplitLayout()
        select(tab)
    }

    private func añadirAVista(_ tab: PestanaTerminal) {
        let modo = modoDivision ?? vistaGuardada?.modo ?? divisionPorDefecto
        let otras = (vistaGuardada?.paneles ?? terminalesVisibles.compactMap { $0 }).filter { $0 !== tab }
        let paneles = otras + [tab]
        mostrarDivision(paneles, modo: paneles.count > modo.capacidad
                        ? (paneles.count <= 4 ? .grid4 : .grid) : modo, activa: tab)
    }

    private func sacarDeVista(_ tab: PestanaTerminal) {
        guard let modo = modoDivision else { return }
        let otras = terminalesVisibles.compactMap { $0 }.filter { $0 !== tab }
        if let primera = otras.first {
            mostrarDivision(otras, modo: modo, activa: otras.first { $0 === selected } ?? primera)
        } else {
            vistaIndividual(terminals.first)
        }
    }

    private func cambiarVistaDividida(_ tab: PestanaTerminal) {
        if panelDividido, terminalesVisibles.contains(where: { $0 === tab }) {
            sacarDeVista(tab)
        } else {
            añadirAVista(tab)
        }
    }

    private func toggleSplit() {
        if panelDividido {
            vistaGuardada = nil
            vistaIndividual(selected)
        } else if let guardada = vistaGuardada, let primera = guardada.paneles.first {
            mostrarDivision(guardada.paneles, modo: guardada.modo,
                            activa: guardada.paneles.first { $0 === selected } ?? primera)
        } else {
            dividirEn(divisionPorDefecto)
        }
    }

    private func terminalEn(_ index: Int) -> PestanaTerminal? {
        terminalesVisibles.indices.contains(index) ? terminalesVisibles[index] : nil
    }

    private func crearPanelTerminal(_ index: Int) {
        let vista = VistaTerminal(id: index == 0 ? "PantallaTerminal" : "PantallaTerminal\(index + 1)")
        vista.estiloRegistro = estilo
        vistas.append(vista)
        let cabecera = Grid()
        cabecera.height = 24
        let contenido = Grid()
        for tipo: GridUnitType in [.auto, .star] {
            let fila = RowDefinition()
            fila.height = GridLength(value: 1, gridUnitType: tipo)
            contenido.rowDefinitions.append(fila)
        }
        contenido.children.append(cabecera)
        Grid.setRow(vista.surface, 1)
        contenido.children.append(vista.surface)
        let borde = Border()
        borde.child = contenido
        marcosTerminal.append(borde)
        cabecerasTerminal.append(cabecera)
        let surface = vista.surface
        vista.alDesplazar = { [weak self] in self?.render(index) }
        vincularRegistro(vista) { [weak self] in self?.terminalEn(index) }
        vista.alActivar = { [weak self] in
            guard let self, let tab = self.terminalEn(index) else { return }
            if index != self.panelActivo { self.select(tab, focus: false) }
            self.focusTerminal()
        }
        // Ajustes → Terminal → «Pegar con clic derecho» (como PuTTY o SecureCRT): pega como Ctrl+Mayús+V.
        surface.rightTapped.addHandler { [weak self] _, args in
            guard let self, self.settings.pegarClicDerecho, let tab = self.terminalEn(index) else { return }
            args?.handled = true
            if tab !== self.selected { self.select(tab) }
            self.safePaste()
        }
        surface.gotFocus.addHandler { [weak self] _, _ in
            guard let self, index != self.panelActivo, let tab = self.terminalEn(index) else { return }
            self.select(tab, focus: false)
        }
        surface.sizeChanged.addHandler { [weak self] _, _ in self?.resize(index) }
        surface.keyDown.addHandler { [weak self] _, args in
            guard let self, let args, let tab = self.terminalEn(index), !tab.closed,
                  let bytes = self.keySequence(args.key.rawValue, tab: tab) else { return }
            args.handled = true
            if self.automatizacionActiva?.tab === tab {
                guard AbortKey.isAbort(bytes.utf8) else { return }
                self.automatizacionActiva?.abort.trip()
                if bytes == "\u{1b}" { return }
            }
            if self.dispatchButtonHotkey(bytes, tab: tab) { return }
            self.emitirTecleo(bytes, a: tab)
        }
        surface.characterReceived.addHandler { [weak self] _, args in
            guard let self, let args, let tab = self.terminalEn(index), !tab.closed else { return }
            let text = String(args.character)
            guard text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
            args.handled = true
            if self.automatizacionActiva?.tab !== tab {
                self.emitirTecleo(text, a: tab)
            }
        }
    }

    private func updateSplitLayout(forzar: Bool = false) {
        let cantidad = terminalesVisibles.count
        guard forzar || panelesMostrados != cantidad || disposicionMostrada != modoDivision else {
            prepararMenuDivision()
            return
        }
        panelesMostrados = cantidad
        disposicionMostrada = modoDivision
        while vistas.count < cantidad { crearPanelTerminal(vistas.count) }
        for fila in filasTerminal { fila.children.clear() }
        filasTerminal.removeAll()
        separadoresTerminal.removeAll()
        terminalGrid.children.clear()
        terminalGrid.rowDefinitions.clear()
        terminalGrid.columnDefinitions.clear()

        let paneles = Array(marcosTerminal.prefix(cantidad))
        switch modoDivision {
        case .onePlusTwo:
            let derecha = Grid()
            filasTerminal.append(derecha)
            distribuirPaneles(Array(paneles.dropFirst()), en: derecha, vertical: true, clave: "right")
            let mitad = Border()
            mitad.child = derecha
            distribuirPaneles([paneles[0], mitad], en: terminalGrid, vertical: false, clave: "root")
        case .grid4, .grid:
            let columnas = modoDivision == .grid4 ? 2 : Int(ceil(sqrt(Double(cantidad))))
            let filas = stride(from: 0, to: cantidad, by: columnas).map { inicio in
                let fila = Grid()
                filasTerminal.append(fila)
                distribuirPaneles(Array(paneles[inicio..<min(inicio + columnas, cantidad)]), en: fila,
                                   vertical: false, clave: "row-\(inicio / columnas)")
                let borde = Border()
                borde.child = fila
                return borde
            }
            distribuirPaneles(filas, en: terminalGrid, vertical: true, clave: "root")
        default:
            distribuirPaneles(paneles, en: terminalGrid, vertical: modoDivision == .stack2, clave: "root")
        }
        prepararMenuDivision()
        actualizarCabecerasDivision()
    }

    private func distribuirPaneles(_ paneles: [Border], en grid: Grid, vertical: Bool, clave: String) {
        let cantidad = paneles.count
        let pesos = Workspace.weights(pesosDivision[clave], count: cantidad)
        var aplicar: [(Double) -> Void] = []
        for (i, panel) in paneles.enumerated() {
            panel.margin = Thickness(left: vertical || i == 0 ? 0 : 6, top: vertical && i != 0 ? 6 : 0, right: 0, bottom: 0)
            let medida = GridLength(value: pesos[i], gridUnitType: .star)
            if vertical {
                let fila = RowDefinition()
                fila.height = medida
                grid.rowDefinitions.append(fila)
                aplicar.append { fila.height = GridLength(value: $0, gridUnitType: .star) }
            } else {
                let columna = ColumnDefinition()
                columna.width = medida
                grid.columnDefinitions.append(columna)
                aplicar.append { columna.width = GridLength(value: $0, gridUnitType: .star) }
            }
            Grid.setRow(panel, vertical ? Int32(i) : 0)
            Grid.setColumn(panel, vertical ? 0 : Int32(i))
            grid.children.append(panel)
        }
        for i in paneles.indices.dropFirst() {
            let borde = Border()
            borde.background = estilo.panel
            if vertical {
                borde.verticalAlignment = .top
                borde.height = 6
            } else {
                borde.horizontalAlignment = .left
                borde.width = 6
            }
            separadoresTerminal.append(borde)
            Grid.setRow(borde, vertical ? Int32(i) : 0)
            Grid.setColumn(borde, vertical ? 0 : Int32(i))
            ToolTipService.setToolTip(borde, L("Separador de paneles"))
            AutomationProperties.setName(borde, L("Separador de paneles"))
            grid.children.append(borde)
            var inicio: (coord: Double, pesos: [Double])?
            borde.pointerPressed.addHandler { [weak self, weak grid] sender, args in
                guard let self, let grid, let borde = sender as? Border, let args,
                      let p = try? args.getCurrentPoint(grid), p.properties.isLeftButtonPressed else { return }
                inicio = (Double(vertical ? p.position.y : p.position.x),
                          Workspace.weights(pesosDivision[clave], count: cantidad))
                borde.background = estilo.acento
                _ = try? borde.capturePointer(args.pointer)
                args.handled = true
            }
            borde.pointerMoved.addHandler { [weak self, weak grid] _, args in
                guard let self, let grid, let inicio, let args, let p = try? args.getCurrentPoint(grid) else { return }
                let longitud = max(1, (vertical ? grid.actualHeight : grid.actualWidth) - Double(cantidad - 1) * 6)
                let d = (Double(vertical ? p.position.y : p.position.x) - inicio.coord) / longitud
                let par = inicio.pesos[i - 1] + inicio.pesos[i]
                let minimo = min(0.12, par / 3)
                var ajuste = inicio.pesos
                ajuste[i - 1] = min(max(ajuste[i - 1] + d, minimo), par - minimo)
                ajuste[i] = par - ajuste[i - 1]
                pesosDivision[clave] = ajuste
                aplicar[i - 1](ajuste[i - 1])
                aplicar[i](ajuste[i])
                args.handled = true
            }
            borde.pointerReleased.addHandler { [weak self] sender, args in
                guard inicio != nil, let borde = sender as? Border, let args else { return }
                inicio = nil
                borde.background = self?.estilo.panel
                try? borde.releasePointerCapture(args.pointer)
                args.handled = true
            }
            borde.pointerCaptureLost.addHandler { [weak self] sender, _ in
                inicio = nil
                (sender as? Border)?.background = self?.estilo.panel
            }
        }
    }

    private func actualizarCabecerasDivision() {
        let e = estilo
        for separador in separadoresTerminal { separador.background = e.panel }
        for index in terminalesVisibles.indices where cabecerasTerminal.indices.contains(index) {
            let cabecera = cabecerasTerminal[index]
            let borde = marcosTerminal[index]
            let superficie = vistas[index].surface
            cabecera.children.clear()
            cabecera.columnDefinitions.clear()
            cabecera.visibility = panelDividido ? .visible : .collapsed
            borde.borderThickness = panelDividido ? Thickness(left: 1, top: 1, right: 1, bottom: 1) : Thickness()
            guard panelDividido else { superficie.visibility = .visible; continue }
            guard let tab = terminalEn(index) else {
                cabecera.background = e.panel
                borde.borderBrush = e.linea
                superficie.visibility = .collapsed
                let hueco = Button()
                e.plano(hueco)
                hueco.content = EstiloMac.letra(L("PANEL LIBRE"), tamano: 11, peso: 700, color: e.apagado)
                let menu = MenuFlyout()
                for otra in terminals where !terminalesVisibles.contains(where: { $0 === otra }) {
                    accionMenu(menu, titulo(otra)) { [weak self, weak otra] in
                        if let otra { self?.añadirAVista(otra) }
                    }
                }
                if let selected {
                    accionMenu(menu, L("Clonar «\(titulo(selected))»")) { [weak self, weak selected] in
                        guard let self, let selected, let nueva = open(selected.route, perfil: selected.perfil) else { return }
                        añadirAVista(nueva)
                    }
                }
                hueco.flyout = menu
                cabecera.children.append(hueco)
                continue
            }
            superficie.visibility = .visible
            let activo = index == panelActivo
            let multi = multiActivo && tab.route.acceptsMultiExec && !tab.closed
            let excluida = excluidasMulti.contains(ObjectIdentifier(tab))
            borde.borderBrush = multi && !excluida ? e.aviso : (activo ? e.acento : e.panel)
            cabecera.background = activo ? e.pestana : e.panel(alfa: 0.8)
            let color = activo ? e.sobrePestana : e.texto
            let selector = Button()
            e.plano(selector)
            selector.height = 24
            selector.padding = Thickness(left: 9, top: 0, right: 4, bottom: 0)
            let etiqueta = filaLateral(columnas: [.auto, .star])
            let punto = EstiloMac.letra("●", tamano: 9, color: tab.closed ? e.mal : e.bien)
            punto.margin = Thickness(left: 0, top: 0, right: 7, bottom: 0)
            colocar([punto, EstiloMac.letra(titulo(tab), tamano: 11.5, peso: 700, color: color)], en: etiqueta)
            selector.content = etiqueta
            selector.click.addHandler { [weak self, weak tab] _, _ in
                if let tab { self?.select(tab) }
            }
            var elementos: [FrameworkElement] = [selector]
            if multi {
                let boton = Button()
                e.plano(boton)
                boton.content = EstiloMac.letra(excluida ? L("EXCLUIDA") : L("⧉ MULTIEXEC"), tamano: 9, peso: 700,
                                               color: excluida ? e.apagado : e.aviso)
                boton.click.addHandler { [weak self, weak tab] _, _ in
                    guard let self, let tab else { return }
                    let id = ObjectIdentifier(tab)
                    if excluidasMulti.contains(id) { excluidasMulti.remove(id) } else { excluidasMulti.insert(id) }
                    actualizarMultiExec()
                    focusTerminal()
                }
                elementos.append(boton)
            }
            let acciones: [(String, String, (NetDeckWindows, PestanaTerminal) -> Void)] = [
                ("\u{E740}", L("Ver sola (la vista sigue en «⊞ VISTA»)"), { app, tab in
                    if let modo = app.modoDivision { app.vistaGuardada = (modo, app.terminalesVisibles.compactMap { $0 }) }
                    app.vistaIndividual(tab)
                }),
                ("\u{E738}", L("Sacar de la vista (sigue abierta en su pestaña)"), { $0.sacarDeVista($1) }),
                (Glifo.cerrar, L("Cerrar esta sesión"), { app, tab in
                    app.select(tab, focus: false)
                    app.closeSelected()
                }),
            ]
            for (glifo, ayuda, accion) in acciones {
                let b = Button()
                e.plano(b)
                b.height = 24
                b.width = 23
                b.padding = Thickness()
                b.horizontalContentAlignment = .center
                b.content = EstiloMac.icono(glifo, tamano: 10, color: color)
                ToolTipService.setToolTip(b, ayuda)
                AutomationProperties.setName(b, ayuda)
                b.click.addHandler { [weak self, weak tab] _, _ in
                    if let self, let tab { accion(self, tab) }
                }
                elementos.append(b)
            }
            for i in elementos.indices {
                let columna = ColumnDefinition()
                columna.width = GridLength(value: 1, gridUnitType: i == 0 ? .star : .auto)
                cabecera.columnDefinitions.append(columna)
            }
            colocar(elementos, en: cabecera)
        }
    }

    private let brushTransparente = SolidColorBrush(Color(a: 0, r: 0, g: 0, b: 0))

    private func render() {
        for index in terminalesVisibles.indices { render(index) }
    }

    private func render(_ index: Int) {
        guard terminalesVisibles.indices.contains(index) else { return }
        let tab = terminalEn(index)
        vestirTerminal(vistas[index], tab)
        vistas[index].render(tab, palette: tab?.paletaPantalla ?? paleta ?? paletaBase,
                             cursorActive: index == panelActivo, brush: brush)
    }

    /// El teclado, al terminal activo: el único camino de «abrir o elegir pestaña ⇒ foco en ella» (`select`, cerrar un
    /// panel, el menú «+»). Se repite en la vuelta siguiente porque un Flyout o MenuFlyout devuelve el foco a lo que lo
    /// tenía antes (el botón «+», la fila de la barra lateral) al terminar de cerrarse, después de nuestro manejador del
    /// clic (ya lo avisa `EditorSesion`: «el menú “+” lo devuelve al botón al cerrarse»). Con un panel abierto no se
    /// repite: el foco es de sus campos.
    // no verificado en Windows
    private func focusTerminal() {
        guard vistas.indices.contains(panelActivo) else { return }
        _ = try? vistas[panelActivo].surface.focus(.programmatic)
        _ = try? window?.dispatcherQueue?.tryEnqueue { [weak self] in
            guard let self, !hayEmergente, vistas.indices.contains(panelActivo) else { return }
            _ = try? vistas[panelActivo].surface.focus(.programmatic)
        }
    }

    private func resize() {
        for index in terminalesVisibles.indices { resize(index) }
    }

    private func resize(_ index: Int) {
        let surface = vistas[index].surface
        guard let tab = terminalEn(index), surface.actualWidth > 20, surface.actualHeight > 16 else { return }
        vestirTerminal(vistas[index], tab)
        let cols = vistas[index].columnas
        let rows = vistas[index].filas
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
        case 8: return tab.perfil.backspaceSendsCtrlH == true ? "\u{8}" : "\u{7f}"
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
