import Foundation
import NetDeckCore
import struct UWP.FontWeight
import WinUI

/// Ajustes que se guardan en UserDefaults (ndFuente, ndTamano, ndTemaNombre…). Los mismos que los del Mac que tienen
/// sentido en Windows; los nombres de las claves, los de siempre.
struct AjustesTerminal: Equatable {
    static var fuentes: [String] {
        var vistas = Set<String>()
        return (["Cascadia Code", "Cascadia Mono", "Consolas"] + TemasTerminal.disponibles().flatMap(\.fonts))
            .filter { vistas.insert($0).inserted }.sorted()
    }
    /// Valores antiguos (en castellano); ya no se eligen: la apariencia la decide el tema, como en el Mac.
    static let temas = ["Sistema (Mica)", "Claro", "Oscuro"]
    static let tamanos = 8...36
    static let posiciones = ["arriba", "abajo", "oculta"]

    var fuente = "Consolas"
    /// El tamaño con el que se dibuja; con `tamanoAuto`, el del tema (lo pone `conTamanoDelTema`).
    var tamano = 13
    var tamanoAuto = true
    var tema = "Sistema (Mica)"
    /// Id del tema (los de NetDeckCore); vacio = sin tema. Clave ndTemaNombre. Sin nada guardado, Liquid Glass.
    var temaTerminal = EstiloMac.idPorDefecto
    var temaAuto = false
    var temaClaro = "liquid-glass-claro"
    var temaOscuro = EstiloMac.idPorDefecto
    var windowsClaro = false
    var coloresTema: [String: [String: String]] = [:]
    var fuenteInterfaz = ""
    var idTemaActual: String { temaAuto ? (windowsClaro ? temaClaro : temaOscuro) : temaTerminal }

    func temaPersonalizado(_ id: String? = nil) -> Theme? {
        let id = id ?? idTemaActual
        guard let t = TemasTerminal.tema(id: id) else { return nil }
        return ThemeOverrides(coloresTema[id] ?? [:]).apply(to: t)
    }

    func fuenteInterfazActual(tema: Theme) -> String {
        if fuenteInterfaz == "system" { return "Cascadia Mono, Consolas" }
        if !fuenteInterfaz.isEmpty { return fuenteInterfaz }
        return (tema.uiFonts + ["Segoe UI Variable", "Segoe UI"]).joined(separator: ", ")
    }
    var divisionApilada = false
    var interlineado = 1.0
    var filtroActivo = true
    var filtro = ScreenFilter.automatic
    var intensidad = ScreenFilter.defaultIntensity
    var resaltado = true
    var origenResaltado = "auto"
    var coloresResaltadoDelTema = true
    var coloresResaltado: [String: [String: String]] = [:]
    var pegarClicDerecho = false
    var scrollback = TerminalHistory.defaultLines
    var copiarAlSeleccionar = false
    var contrasenaAutomatica = true
    var ofrecerGuardar = true
    var modoClaveEquipo = PasswordAutomation.Mode.suggest
    var clavePorDefecto = ""
    var usuarioClavePorDefecto = ""
    var credencialPorDefecto: DefaultCredential? {
        let u = usuarioClavePorDefecto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !clavePorDefecto.isEmpty else { return nil }
        return .init(name: clavePorDefecto, user: u)
    }
    var grabarSesiones = true
    var carpetaRegistros = SessionLogger.defaultDirectory.path
    var depuracion = true
    var urlRegistro: URL { URL(fileURLWithPath: AppPaths.expand(carpetaRegistros), isDirectory: true) }
    var revisarPegado = true
    var umbralPegado = PasteReview.defaultThreshold
    var posicionBotones = "arriba"
    var botonesPorGrupos = true
    var listaSesiones = true
    var sesionInicio = ""
    var terminalLocalInicio = true
    var buscarActualizaciones = true
    var enviarIdioma = false
    var toolbarOcultos: Set<String> = []

    /// Con «Automático», el del tema menos uno (como el Mac: `TerminalFont.size(0, themeSize:)`).
    func conTamanoDelTema() -> AjustesTerminal {
        guard tamanoAuto else { return self }
        var a = self
        let base = (temaPersonalizado() ?? TemasTerminal.tema(id: EstiloMac.idPorDefecto))?.size ?? 14
        a.tamano = min(Self.tamanos.upperBound, max(Self.tamanos.lowerBound, base - 1))
        return a
    }

    static func cargar(_ defaults: UserDefaults = .standard) -> AjustesTerminal {
        var a = AjustesTerminal()
        func bool(_ clave: String, _ porDefecto: Bool) -> Bool { defaults.object(forKey: clave) as? Bool ?? porDefecto }
        if let f = defaults.string(forKey: "ndFuente"), fuentes.contains(f) { a.fuente = f }
        let t = defaults.integer(forKey: "ndTamano")
        if tamanos.contains(t) { a.tamano = t }
        a.tamanoAuto = bool("ndTamanoAuto", !tamanos.contains(t))
        if let m = defaults.string(forKey: "ndTema"), temas.contains(m) { a.tema = m }
        a.temaTerminal = defaults.string(forKey: TemasTerminal.clave) ?? EstiloMac.idPorDefecto
        a.temaAuto = bool("themeAuto", false)
        a.temaClaro = defaults.string(forKey: "themeLight") ?? a.temaClaro
        a.temaOscuro = defaults.string(forKey: "themeDark") ?? a.temaOscuro
        a.coloresTema = (defaults.dictionary(forKey: "themeOverrides") as? [String: [String: String]]) ?? [:]
        a.fuenteInterfaz = defaults.string(forKey: "uiFontFamily") ?? ""
        a.divisionApilada = defaults.bool(forKey: "ndDivisionApilada")
        let interlineado = defaults.double(forKey: "ndInterlineado")
        if (1...1.5).contains(interlineado) { a.interlineado = interlineado }
        a.filtroActivo = bool("ndFiltroActivo", true)
        a.filtro = defaults.string(forKey: "ndFiltroTerminal") ?? ScreenFilter.automatic
        if let value = defaults.object(forKey: "ndFiltroIntensidad") as? Double { a.intensidad = ScreenFilter.intensity(value) }
        a.resaltado = bool("ndResaltadoTerminal", true)
        a.origenResaltado = defaults.string(forKey: "highlightSource") ?? "auto"
        a.coloresResaltadoDelTema = bool("highlightThemeColors", true)
        a.coloresResaltado = (defaults.dictionary(forKey: "highlightColors") as? [String: [String: String]]) ?? [:]
        a.pegarClicDerecho = bool("ndPegarClicDerecho", false)
        a.scrollback = TerminalHistory.lines(defaults.object(forKey: TerminalHistory.key))
        a.copiarAlSeleccionar = bool("copyOnSelect", false)
        a.contrasenaAutomatica = bool("sessionAutoPassword", true)
        a.ofrecerGuardar = bool("offerSaveTyped", true)
        a.modoClaveEquipo = defaults.string(forKey: "devicePasswordMode").flatMap(PasswordAutomation.Mode.init(rawValue:)) ?? .suggest
        a.clavePorDefecto = defaults.string(forKey: "defaultCredentialName") ?? ""
        a.usuarioClavePorDefecto = defaults.string(forKey: "defaultCredentialUser") ?? ""
        a.grabarSesiones = bool("logEnabled", true)
        if ProcessInfo.processInfo.environment["NETDECK_DESKTOP_DEMO"] != "1" {
            a.carpetaRegistros = defaults.string(forKey: "logPath") ?? a.carpetaRegistros
        }
        a.depuracion = bool("debugLog", true)
        a.revisarPegado = bool("ndRevisarPegado", true)
        let umbral = defaults.integer(forKey: "ndUmbralPegado")
        if umbral > 0 { a.umbralPegado = umbral }
        if let p = defaults.string(forKey: "ndPosicionBotones"), posiciones.contains(p) { a.posicionBotones = p }
        a.botonesPorGrupos = bool("ndBotonesPorGrupos", true)
        a.listaSesiones = bool("ndListaSesiones", true)
        a.sesionInicio = defaults.string(forKey: "ndSesionInicio") ?? ""
        a.terminalLocalInicio = bool("ndTerminalLocalInicio", true)
        a.buscarActualizaciones = bool("ndBuscarActualizaciones", true)
        a.enviarIdioma = bool("ndEnviarIdioma", false)
        a.toolbarOcultos = Set(defaults.stringArray(forKey: "ndToolbarOcultos") ?? [])
        return a.conTamanoDelTema()
    }

    func guardar(_ defaults: UserDefaults = .standard) {
        defaults.set(fuente, forKey: "ndFuente")
        defaults.set(tamano, forKey: "ndTamano")
        defaults.set(tamanoAuto, forKey: "ndTamanoAuto")
        defaults.set(tema, forKey: "ndTema")
        defaults.set(temaTerminal, forKey: TemasTerminal.clave)
        defaults.set(temaAuto, forKey: "themeAuto")
        defaults.set(temaClaro, forKey: "themeLight")
        defaults.set(temaOscuro, forKey: "themeDark")
        defaults.set(coloresTema, forKey: "themeOverrides")
        defaults.set(fuenteInterfaz, forKey: "uiFontFamily")
        defaults.set(divisionApilada, forKey: "ndDivisionApilada")
        defaults.set(interlineado, forKey: "ndInterlineado")
        defaults.set(filtroActivo, forKey: "ndFiltroActivo")
        defaults.set(filtro, forKey: "ndFiltroTerminal")
        defaults.set(intensidad, forKey: "ndFiltroIntensidad")
        defaults.set(resaltado, forKey: "ndResaltadoTerminal")
        defaults.set(origenResaltado, forKey: "highlightSource")
        defaults.set(coloresResaltadoDelTema, forKey: "highlightThemeColors")
        defaults.set(coloresResaltado, forKey: "highlightColors")
        defaults.set(pegarClicDerecho, forKey: "ndPegarClicDerecho")
        defaults.set(scrollback, forKey: TerminalHistory.key)
        defaults.set(copiarAlSeleccionar, forKey: "copyOnSelect")
        defaults.set(contrasenaAutomatica, forKey: "sessionAutoPassword")
        defaults.set(ofrecerGuardar, forKey: "offerSaveTyped")
        defaults.set(modoClaveEquipo.rawValue, forKey: "devicePasswordMode")
        defaults.set(clavePorDefecto, forKey: "defaultCredentialName")
        defaults.set(usuarioClavePorDefecto, forKey: "defaultCredentialUser")
        defaults.set(grabarSesiones, forKey: "logEnabled")
        defaults.set(carpetaRegistros, forKey: "logPath")
        defaults.set(depuracion, forKey: "debugLog")
        defaults.set(revisarPegado, forKey: "ndRevisarPegado")
        defaults.set(umbralPegado, forKey: "ndUmbralPegado")
        defaults.set(posicionBotones, forKey: "ndPosicionBotones")
        defaults.set(botonesPorGrupos, forKey: "ndBotonesPorGrupos")
        defaults.set(listaSesiones, forKey: "ndListaSesiones")
        defaults.set(sesionInicio, forKey: "ndSesionInicio")
        defaults.set(terminalLocalInicio, forKey: "ndTerminalLocalInicio")
        defaults.set(buscarActualizaciones, forKey: "ndBuscarActualizaciones")
        defaults.set(enviarIdioma, forKey: "ndEnviarIdioma")
        defaults.set(Array(toolbarOcultos).sorted(), forKey: "ndToolbarOcultos")
        defaults.synchronize()   // (en Windows no se vuelca solo: sin esto se pierde si la app se cierra a la fuerza)
    }
}

/// Ajustes como los del Mac (`SettingsOverlay`): a la izquierda las secciones (200 de ancho, la elegida con el color
/// de la pestaña y «Cerrar» abajo); a la derecha su formulario con tarjetas del tema (`ThemedFormStyle`: título en
/// acento2, filas separadas por una raya y el pie en pequeño). Todo se aplica al momento (`onChange`).
final class PanelAjustes {
    let view = ScrollViewer()
    var onChange: ((AjustesTerminal) -> Void)?
    var onClose: (() -> Void)?
    var onHighlight: (() -> Void)?
    var onReloadHighlight: (() -> Void)?
    var onCustomizeHighlight: (() -> Void)?
    var rutaResaltado: (() -> String)?
    var reglasDeVistaPrevia: (() -> HighlightConfig)?
    /// «Buscar ahora»: la ventana hace la consulta y avisa con `setUpdateStatus`.
    var onCheckUpdates: (() -> Void)?
    var onManagePasswords: (() -> Void)?
    var onEditButtons: (() -> Void)?
    var onReloadSessions: (() -> Void)?
    // Sesiones
    var grupos: (() -> [(String, [SessionProfile])])?
    var rutaSesiones: (() -> String)?
    var onNewSession: (() -> Void)?
    var onImportSessions: (() -> Void)?
    var onEditSession: ((SessionProfile) -> Void)?
    var onDuplicateSession: ((SessionProfile) -> Void)?
    var onDeleteSession: ((SessionProfile) -> Void)?
    var editorListas: (() -> FrameworkElement?)?
    private weak var formularioAnterior: StackPanel?
    var credencialesConNombre: (() -> [String])?
    var onEditarCredencial: ((String?) -> Void)?
    var onTemaImportar: (() throws -> Theme?)?
    var onTemaElegirColor: ((RGB, @escaping (RGB?) -> Void) -> Void)?
    private var personalizarTema = false
    private var mensajeTema = ""
    var onElegirCarpetaRegistro: (() -> URL?)?
    var onAbrirRegistro: ((URL) -> Void)?
    var registrosActivos: (() -> [(String, URL, () -> Void)])?

    private static var secciones: [(id: String, titulo: String, glifo: String)] { [
        ("contrasenas", L("Contrase\u{00F1}as"), Glifo.llave), ("sesiones", L("Sesiones"), "\u{E977}"),
        ("listas", L("Listas"), Glifo.lista),
        ("temas", L("Temas"), "\u{E790}"), ("fuentes", L("Fuentes"), "\u{E8D2}"),
        ("resaltado", L("Resaltado"), "\u{E7E6}"), ("botones", L("Botones"), "\u{E8A9}"),
        ("registro", L("Registro"), Glifo.grabar),
        ("terminal", L("Terminal"), Glifo.terminal), ("general", L("General"), Glifo.ajustes),
    ] }

    private var settings = AjustesTerminal()
    private var estilo = EstiloMac(tema: nil)
    private var seccion = "contrasenas"
    var seccionActual: String { seccion }
    private let raiz = Grid()
    private let nav = Grid()
    private let menu = StackPanel()
    private let contenido = ScrollViewer()
    private let cerrar = Button()
    /// (se crea con cada página: un elemento de WinUI no puede estar en dos a la vez, y la anterior aún lo tendría)
    private weak var updateText: TextBlock?
    private var estadoActualizacion = ""
    private var cargando = false
    private var vista: Border?

    init() {
        let colMenu = ColumnDefinition()
        colMenu.width = GridLength(value: 200, gridUnitType: .pixel)
        let colContenido = ColumnDefinition()
        colContenido.width = GridLength(value: 1, gridUnitType: .star)
        raiz.columnDefinitions.append(colMenu)
        raiz.columnDefinitions.append(colContenido)

        for alto in [GridUnitType.star, .auto] {
            let fila = RowDefinition()
            fila.height = GridLength(value: 1, gridUnitType: alto)
            nav.rowDefinitions.append(fila)
        }
        menu.orientation = .vertical
        menu.spacing = 3
        menu.margin = Thickness(left: 8, top: 0, right: 8, bottom: 0)
        cerrar.margin = Thickness(left: 18, top: 10, right: 18, bottom: 18)
        cerrar.horizontalAlignment = .stretch
        cerrar.click.addHandler { [weak self] _, _ in self?.onClose?() }
        AutomationProperties.setAutomationId(cerrar, "Ajustes_Cerrar")
        Grid.setRow(menu, Int32(0))
        Grid.setRow(cerrar, Int32(1))
        nav.children.append(menu)
        nav.children.append(cerrar)
        Grid.setColumn(nav, Int32(0))
        contenido.verticalScrollBarVisibility = .auto
        contenido.horizontalScrollBarVisibility = .disabled
        Grid.setColumn(contenido, Int32(1))
        raiz.children.append(nav)
        raiz.children.append(contenido)

        view.content = raiz
        view.verticalScrollBarVisibility = .disabled
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    /// Alto de la tarjeta: hasta 720, como el Mac, o lo que deje la ventana.
    func ajustarAlto(_ disponible: Double) { raiz.height = max(320, min(720, disponible)) }

    func show(_ settings: AjustesTerminal, estilo: EstiloMac, seccion: String? = nil) {
        self.settings = settings
        self.estilo = estilo
        if let seccion { self.seccion = seccion }
        construirMenu()
        construirSeccion()
    }

    /// Tras aplicar un cambio que cambia los colores (el tema): se redibuja la sección abierta donde estaba.
    func refrescar(_ settings: AjustesTerminal, estilo: EstiloMac) {
        guard view.visibility == .visible else { return }
        let desplazamiento = contenido.verticalOffset
        show(settings, estilo: estilo)
        _ = try? contenido.changeView(nil, desplazamiento, nil, true)
    }

    func setUpdateStatus(_ text: String) {
        estadoActualizacion = text
        updateText?.text = text
    }

    private func cambiar(_ cambio: (inout AjustesTerminal) -> Void) {
        guard !cargando else { return }
        cambio(&settings)
        settings = settings.conTamanoDelTema()
        onChange?(settings)
    }

    // MARK: - navegación

    private func construirMenu() {
        let e = estilo
        nav.background = e.barra
        menu.children.clear()
        let titulo = EstiloMac.letra(L("Ajustes"), tamano: 18, peso: 800, color: e.texto)
        titulo.margin = Thickness(left: 10, top: 18, right: 0, bottom: 14)
        menu.children.append(titulo)
        for (id, texto, glifo) in Self.secciones {
            let elegida = id == seccion
            let fila = StackPanel()
            fila.orientation = .horizontal
            fila.spacing = 10
            let icono = EstiloMac.icono(glifo, tamano: 13, color: elegida ? e.sobrePestana : e.acento2)
            icono.width = 18
            fila.children.append(icono)
            fila.children.append(EstiloMac.letra(texto, tamano: 12.5, peso: elegida ? 700 : 400,
                                                 color: elegida ? e.sobrePestana : e.texto))
            let b = Button()
            e.plano(b)
            b.content = fila
            b.padding = Thickness(left: 10, top: 7, right: 10, bottom: 7)
            b.cornerRadius = EstiloMac.radio(8)
            if elegida { b.background = e.pestana }
            AutomationProperties.setAutomationId(b, "Ajustes_Seccion_\(id)")
            AutomationProperties.setName(b, texto)
            b.click.addHandler { [weak self] _, _ in
                guard let self, self.seccion != id else { return }
                self.seccion = id
                self.construirMenu()
                self.construirSeccion()
                _ = try? self.contenido.changeView(nil, 0, nil, true)
            }
            menu.children.append(b)
        }
        let cierre = StackPanel()
        cierre.orientation = .horizontal
        cierre.spacing = 6
        cierre.horizontalAlignment = .center
        cierre.children.append(EstiloMac.icono(Glifo.cerrar, tamano: 10, color: e.texto))
        cierre.children.append(EstiloMac.letra(L("Cerrar"), tamano: 12, peso: 500, color: e.texto))
        cerrar.content = cierre
        vestir(cerrar)
    }

    private func construirSeccion() {
        cargando = true
        defer { cargando = false }
        formularioAnterior?.children.clear()
        let formulario = StackPanel()
        formularioAnterior = formulario
        formulario.orientation = .vertical
        formulario.spacing = 18
        formulario.padding = Thickness(left: 18, top: 18, right: 18, bottom: 18)
        vista = nil
        switch seccion {
        case "sesiones": seccionSesiones(formulario)
        case "listas":
            if let gestor = editorListas?() { formulario.children.append(gestor) }
        case "temas": seccionTemas(formulario)
        case "fuentes": seccionFuentes(formulario)
        case "resaltado": seccionResaltado(formulario)
        case "botones": seccionBotones(formulario)
        case "registro": seccionRegistro(formulario)
        case "terminal": seccionTerminal(formulario)
        case "general": seccionGeneral(formulario)
        default: seccionContrasenas(formulario)
        }
        contenido.content = formulario
    }

    // MARK: - formulario con el tema (ThemedFormStyle del Mac)

    /// Un apartado: su título (11 negrita, acento2), la tarjeta con las filas y el pie (10,5, apagado).
    private func apartado(_ titulo: String?, _ filas: [FrameworkElement], pie: String? = nil, en formulario: StackPanel) {
        let e = estilo
        let caja = StackPanel()
        caja.orientation = .vertical
        caja.spacing = 6
        if let titulo, !titulo.isEmpty {
            let t = EstiloMac.letra(titulo, tamano: 11, peso: 700, color: e.acento2)
            t.margin = Thickness(left: 4, top: 0, right: 0, bottom: 0)
            caja.children.append(t)
        }
        let lista = StackPanel()
        lista.orientation = .vertical
        for (i, fila) in filas.enumerated() {
            if i > 0 {
                let raya = Border()
                raya.height = 1
                raya.background = e.panel
                lista.children.append(raya)
            }
            fila.margin = Thickness(left: 12, top: 7, right: 12, bottom: 7)
            lista.children.append(fila)
        }
        let tarjeta = Border()
        tarjeta.child = lista
        tarjeta.background = e.panel(alfa: 0.45)
        tarjeta.borderBrush = e.acento(alfa: 0.35)
        tarjeta.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        tarjeta.cornerRadius = EstiloMac.radio(6)
        caja.children.append(tarjeta)
        if let pie, !pie.isEmpty {
            let p = TextBlock()
            p.text = pie
            p.fontSize = 10.5
            p.foreground = e.apagado
            p.textWrapping = .wrap
            p.margin = Thickness(left: 4, top: 0, right: 0, bottom: 0)
            caja.children.append(p)
        }
        formulario.children.append(caja)
    }

    /// Etiqueta a la izquierda y el control a la derecha (`ThemedLabeledStyle`).
    private func fila(_ etiqueta: String, _ control: FrameworkElement, id: String? = nil) -> Grid {
        let g = Grid()
        let c0 = ColumnDefinition()
        c0.width = GridLength(value: 1, gridUnitType: .star)
        let c1 = ColumnDefinition()
        c1.width = GridLength(value: 1, gridUnitType: .auto)
        g.columnDefinitions.append(c0)
        g.columnDefinitions.append(c1)
        let t = texto(etiqueta)
        t.verticalAlignment = .center
        t.margin = Thickness(left: 0, top: 0, right: 10, bottom: 0)
        control.verticalAlignment = .center
        Grid.setColumn(t, Int32(0))
        Grid.setColumn(control, Int32(1))
        g.children.append(t)
        g.children.append(control)
        AutomationProperties.setName(control, etiqueta)
        if let id { AutomationProperties.setAutomationId(control, id) }
        return g
    }

    private func texto(_ s: String, tamano: Double = 12, apagado: Bool = false) -> TextBlock {
        let t = TextBlock()
        t.text = s
        t.fontSize = tamano
        t.fontFamily = EstiloMac.fuenteInterfaz
        t.textWrapping = .wrap
        t.foreground = apagado ? estilo.apagado : estilo.texto
        return t
    }

    private func nota(_ s: String) -> TextBlock { texto(s, tamano: 11, apagado: true) }

    /// Interruptor del tema (`ThemedSwitchStyle`): la etiqueta y el interruptor a la derecha.
    private func interruptor(_ etiqueta: String, _ valor: Bool, id: String,
                             _ alCambiar: @escaping (inout AjustesTerminal, Bool) -> Void) -> Grid {
        let s = ToggleSwitch()
        s.isOn = valor
        s.onContent = ""
        s.offContent = ""
        s.minWidth = 0
        s.toggled.addHandler { [weak self] origen, _ in
            guard let s = origen as? ToggleSwitch else { return }
            let on = s.isOn
            self?.cambiar { alCambiar(&$0, on) }
        }
        return fila(etiqueta, s, id: id)
    }

    private func selector(_ opciones: [(valor: String, texto: String)], _ actual: String, ancho: Double = 240,
                          _ alCambiar: @escaping (inout AjustesTerminal, String) -> Void) -> ComboBox {
        let c = ComboBox()
        c.minWidth = ancho
        for o in opciones { c.items.append(o.texto) }
        c.selectedIndex = Int32(opciones.firstIndex { $0.valor == actual } ?? 0)
        c.selectionChanged.addHandler { [weak self] origen, _ in
            guard let c = origen as? ComboBox, opciones.indices.contains(Int(c.selectedIndex)) else { return }
            let valor = opciones[Int(c.selectedIndex)].valor
            self?.cambiar { alCambiar(&$0, valor) }
        }
        return c
    }

    /// Botones de una sola elección, juntos (`ThemedSegmented`).
    private func segmentos(_ opciones: [(valor: String, texto: String)], _ actual: String, id: String,
                           _ elegir: @escaping (String) -> Void) -> StackPanel {
        let e = estilo
        let s = StackPanel()
        s.orientation = .horizontal
        s.spacing = 2
        for o in opciones {
            let b = Button()
            let on = o.valor == actual
            b.content = EstiloMac.letra(o.texto, tamano: 12, peso: on ? 600 : 400, color: on ? e.sobrePestana : e.texto)
            b.background = on ? e.pestana : e.panel(alfa: 0.6)
            b.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
            b.cornerRadius = EstiloMac.radio(5)
            b.padding = Thickness(left: 12, top: 4, right: 12, bottom: 4)
            AutomationProperties.setAutomationId(b, "\(id)_\(o.valor)")
            b.click.addHandler { [weak self] _, _ in
                guard let self, !self.cargando else { return }
                elegir(o.valor)
                self.construirSeccion()
            }
            s.children.append(b)
        }
        return s
    }

    private func vestir(_ b: Button) {
        let e = estilo
        b.background = e.panel(alfa: 0.6)
        b.borderBrush = e.acento(alfa: 0.6)
        b.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        b.cornerRadius = EstiloMac.radio(5)
        b.minHeight = 24
        b.padding = Thickness(left: 10, top: 2, right: 10, bottom: 2)
    }

    private func boton(_ titulo: String, id: String, _ accion: @escaping () -> Void) -> Button {
        let b = Button()
        b.content = EstiloMac.letra(titulo, tamano: 12, peso: 500, color: estilo.texto)
        vestir(b)
        AutomationProperties.setAutomationId(b, id)
        AutomationProperties.setName(b, titulo)
        b.click.addHandler { _, _ in accion() }
        return b
    }

    private func enLinea(_ elementos: [FrameworkElement], separacion: Double = 8) -> StackPanel {
        let s = StackPanel()
        s.orientation = .horizontal
        s.spacing = separacion
        for x in elementos {
            x.verticalAlignment = .center
            s.children.append(x)
        }
        return s
    }

    /// Etiqueta, deslizador que ocupa lo que quede y el valor a la derecha (50 de ancho).
    private func deslizador(_ etiqueta: String, rango: ClosedRange<Double>, paso: Double, valor: Double, id: String,
                            formato: @escaping (Double) -> String,
                            _ alCambiar: @escaping (inout AjustesTerminal, Double) -> Void) -> Grid {
        let g = Grid()
        for tipo in [GridUnitType.auto, .star, .auto] {
            let c = ColumnDefinition()
            c.width = GridLength(value: 1, gridUnitType: tipo)
            g.columnDefinitions.append(c)
        }
        let t = texto(etiqueta)
        t.verticalAlignment = .center
        t.margin = Thickness(left: 0, top: 0, right: 12, bottom: 0)
        let s = Slider()
        s.minimum = rango.lowerBound
        s.maximum = rango.upperBound
        s.stepFrequency = paso
        s.value = valor
        s.verticalAlignment = .center
        AutomationProperties.setAutomationId(s, id)
        AutomationProperties.setName(s, etiqueta)
        let v = texto(formato(valor))
        v.width = 50
        v.textAlignment = .right
        v.verticalAlignment = .center
        s.valueChanged.addHandler { [weak self] _, args in
            guard let x = args?.newValue else { return }
            v.text = formato(x)
            self?.cambiar { alCambiar(&$0, x) }
        }
        Grid.setColumn(t, Int32(0))
        Grid.setColumn(s, Int32(1))
        Grid.setColumn(v, Int32(2))
        g.children.append(t)
        g.children.append(s)
        g.children.append(v)
        return g
    }

    // MARK: - Contraseñas

    private func seccionContrasenas(_ f: StackPanel) {
        apartado(L("Contrase\u{00F1}as"), [
            fila(L("Las del Administrador de credenciales"),
                 boton(L("Gestionar contrase\u{00F1}as\u{2026}"), id: "Ajustes_GestionarContrasenas") { [weak self] in
                     self?.onManagePasswords?()
                 }),
        ], pie: L("Se guardan s\u{00F3}lo en el Administrador de credenciales de Windows. El\u{00ED}gelas por su nombre en sesiones, grupos, botones y listas."),
           en: f)
        let modos: [(PasswordAutomation.Mode, String)] = [(.autoType, L("Escribirla sola")), (.suggest, L("Sugerirla (un clic)")),
                                                         (.off, L("Nada"))]
        apartado(L("Al conectar"), [
            interruptor(L("Escribir sola la contraseña al abrir una sesión"), settings.contrasenaAutomatica,
                        id: "Contrasenas_Automatica") { $0.contrasenaAutomatica = $1 },
            interruptor(L("Ofrecer guardar la que escribo yo"), settings.ofrecerGuardar,
                        id: "Contrasenas_OfrecerGuardar") { $0.ofrecerGuardar = $1 },
            fila(L("Cuando un equipo pide contraseña"), selector(modos.map { ($0.0.rawValue, $0.1) }, settings.modoClaveEquipo.rawValue) {
                $0.modoClaveEquipo = PasswordAutomation.Mode(rawValue: $1) ?? .suggest
            }),
        ], pie: L("Sólo la del mismo usuario que piden. Los códigos de un solo uso, siempre a mano."), en: f)
        let disponibles = credencialesConNombre?() ?? []
        var opciones = [("", L("Ninguna (preguntar)"))] + disponibles.map { ($0, "🔑 \($0)") }
        let actual = settings.clavePorDefecto
        if !actual.isEmpty, !disponibles.contains(actual) {
            opciones.append((actual, L("\(actual) (no está en el Llavero)")))
        }
        var filas: [FrameworkElement] = [
            fila(L("Credencial predeterminada"), selector(opciones, actual) { [weak self] ajustes, valor in
                ajustes.clavePorDefecto = valor
                self?.reconstruirContrasenas()
            }),
            boton(L("Nueva…"), id: "Contrasenas_Nueva") { [weak self] in self?.onEditarCredencial?(nil) },
        ]
        if !actual.isEmpty {
            let usuario = TextBox()
            usuario.text = settings.usuarioClavePorDefecto
            usuario.placeholderText = L("tu.usuario")
            usuario.minWidth = 240
            usuario.textChanged.addHandler { [weak self] origen, _ in
                guard let campo = origen as? TextBox else { return }
                self?.cambiar { $0.usuarioClavePorDefecto = campo.text }
            }
            filas.append(fila(L("Usuario exacto"), usuario))
            let editar = boton(L("Editar credencial…"), id: "Contrasenas_Editar") { [weak self] in self?.onEditarCredencial?(actual) }
            editar.isEnabled = disponibles.contains(actual)
            filas.append(editar)
        }
        apartado(L("Por defecto"), filas,
                 pie: L("Se usa si el equipo no tiene otra asignada y pide exactamente ese usuario. Las sesiones guardadas usan su propia asignación."), en: f)
    }

    private func reconstruirContrasenas() {
        _ = try? raiz.dispatcherQueue?.tryEnqueue { [weak self] in
            guard let self, seccion == "contrasenas" else { return }
            construirSeccion()
        }
    }

    // MARK: - Sesiones (el gestor de la lista)

    private func seccionSesiones(_ f: StackPanel) {
        let grupos = self.grupos?() ?? []
        let total = grupos.reduce(0) { $0 + $1.1.count }
        apartado(L("Sesiones"), [
            enLinea([
                boton(L("Nueva sesi\u{00F3}n"), id: "Ajustes_NuevaSesion") { [weak self] in self?.onNewSession?() },
                boton(L("Importar\u{2026}"), id: "Ajustes_ImportarSesiones") { [weak self] in self?.onImportSessions?() },
                boton(L("Recargar"), id: "Ajustes_RecargarLista") { [weak self] in self?.onReloadSessions?() },
            ]),
        ], pie: L("\(total) sesiones \u{00B7} anotaciones: # @grupo, # @clave, # @clave-grupo, # @desc, # @telnet"), en: f)
        for (grupo, perfiles) in grupos {
            let filas: [FrameworkElement] = perfiles.map { perfil in
                let g = Grid()
                for tipo in [GridUnitType.auto, .star, .auto] {
                    let c = ColumnDefinition()
                    c.width = GridLength(value: 1, gridUnitType: tipo)
                    g.columnDefinitions.append(c)
                }
                let nombre = EstiloMac.letra(perfil.name, tamano: 12, peso: 600, color: estilo.texto)
                nombre.margin = Thickness(left: 0, top: 0, right: 8, bottom: 0)
                let detalle = EstiloMac.letra("\(perfil.transport.label) \u{00B7} \(perfil.endpoint.description)",
                                              tamano: 11, color: estilo.apagado)
                let acciones = enLinea([
                    boton(L("Editar\u{2026}"), id: "Ajustes_Editar_\(perfil.name)") { [weak self] in self?.onEditSession?(perfil) },
                    boton(L("Duplicar"), id: "Ajustes_Duplicar_\(perfil.name)") { [weak self] in self?.onDuplicateSession?(perfil) },
                    boton(L("Borrar\u{2026}"), id: "Ajustes_Borrar_\(perfil.name)") { [weak self] in self?.onDeleteSession?(perfil) },
                ], separacion: 6)
                Grid.setColumn(nombre, Int32(0))
                Grid.setColumn(detalle, Int32(1))
                Grid.setColumn(acciones, Int32(2))
                detalle.verticalAlignment = .center
                nombre.verticalAlignment = .center
                g.children.append(nombre)
                g.children.append(detalle)
                g.children.append(acciones)
                return g
            }
            apartado(grupo, filas, en: f)
        }
        if let ruta = rutaSesiones?() {
            apartado(nil, [nota(L("Archivo: \(ruta)"))], en: f)
        }
    }

    // MARK: - Temas

    private func seccionTemas(_ f: StackPanel) {
        let temas = TemasTerminal.disponibles()
        let actual = settings.temaPersonalizado() ?? estilo.tema
        let vista = Border()
        vista.height = 190
        self.vista = vista
        pintarVista(actual)
        f.children.append(vista)
        var controles: [FrameworkElement] = [
            interruptor(L("Seguir a Windows (claro / oscuro)"), settings.temaAuto, id: "Temas_SeguirSistema") {
                $0.temaAuto = $1
            },
        ]
        if settings.temaAuto {
            let opciones = temas.map { ($0.id, $0.name) }
            controles.append(fila(L("Claro"), selector(opciones, settings.temaClaro) { $0.temaClaro = $1 }))
            controles.append(fila(L("Oscuro"), selector(opciones, settings.temaOscuro) { $0.temaOscuro = $1 }))
        }
        controles.append(enLinea([
            boton(L("Personalizar colores…"), id: "Temas_Personalizar") { [weak self] in
                guard let self else { return }
                personalizarTema.toggle()
                construirSeccion()
            },
            boton(L("Importar .tema…"), id: "Temas_Importar") { [weak self] in self?.importarTema() },
        ]))
        if !mensajeTema.isEmpty { controles.append(nota(mensajeTema)) }
        apartado(nil, controles, en: f)
        if personalizarTema { colores(actual, en: f) }
        f.children.append(nota(L("Pasa el rat\u{00F3}n por un tema para verlo arriba; p\u{00FA}lsalo y se aplica al momento a toda la app.")))

        var grupos = Theme.groups.map { g in (g, temas.filter { $0.group == g }) }
        let otros = temas.filter { !Theme.groups.contains($0.group) }
        if !otros.isEmpty { grupos.append((L("Otros"), otros)) }
        for (grupo, lista) in grupos where !lista.isEmpty {
            let cabecera = Grid()
            for tipo in [GridUnitType.auto, .star, .auto] {
                let c = ColumnDefinition()
                c.width = GridLength(value: 1, gridUnitType: tipo)
                cabecera.columnDefinitions.append(c)
            }
            let nombre = EstiloMac.letra(L(nombre: grupo).uppercased(), tamano: 11, peso: 700, color: estilo.acento2)
            nombre.characterSpacing = 100
            let raya = Border()
            raya.height = 1
            raya.background = estilo.panel
            raya.margin = Thickness(left: 10, top: 0, right: 10, bottom: 0)
            raya.verticalAlignment = .center
            let cuenta = EstiloMac.letra("\(lista.count)", tamano: 11, color: estilo.apagado)
            Grid.setColumn(nombre, Int32(0))
            Grid.setColumn(raya, Int32(1))
            Grid.setColumn(cuenta, Int32(2))
            cabecera.children.append(nombre)
            cabecera.children.append(raya)
            cabecera.children.append(cuenta)
            cabecera.margin = Thickness(left: 0, top: 6, right: 0, bottom: -6)
            f.children.append(cabecera)
            var filaActual: StackPanel?
            for (i, tema) in lista.enumerated() {
                if i % 3 == 0 {
                    let nueva = StackPanel()
                    nueva.orientation = .horizontal
                    nueva.spacing = 12
                    nueva.margin = Thickness(left: 0, top: 0, right: 0, bottom: -6)
                    f.children.append(nueva)
                    filaActual = nueva
                }
                filaActual?.children.append(tarjetaTema(tema))
            }
        }
    }

    private func importarTema() {
        do {
            guard let tema = try onTemaImportar?() else { return }
            mensajeTema = L("Tema «\(tema.name)» importado")
            cambiar { $0.temaAuto = false; $0.temaTerminal = tema.id }
            construirSeccion()
        } catch {
            mensajeTema = error.localizedDescription
            construirSeccion()
        }
    }

    private func colores(_ tema: Theme, en f: StackPanel) {
        let campos: [(String, String, RGB)] = [
            ("fondo", L("Fondo"), tema.background), ("texto", L("Texto"), tema.text),
            ("acento", L("Acento"), tema.accent), ("acento2", L("Acento 2"), tema.accent2),
            ("pestaña", L("Pestaña activa"), tema.tab), ("selección", L("Selección"), tema.selection),
            ("cursor", L("Cursor"), tema.cursor),
        ]
        let cambios = settings.coloresTema[tema.id] ?? [:]
        var filas: [FrameworkElement] = campos.map { clave, nombre, actual in
            fila(nombre, elegirColor(clave, nombre, actual, tema: tema.id))
        }
        filas.append(nota(L("Colores ANSI del terminal")))
        for inicio in [0, 8] {
            filas.append(enLinea((inicio..<inicio + 8).map { i in
                elegirColor("ansi\(i)", "\(i)", tema.ansi[i], tema: tema.id)
            }, separacion: 4))
        }
        if !ThemeOverrides.contrastWarnings(tema).isEmpty {
            filas.append(nota(L("Algunos colores se leen mal sobre el fondo (⚠). Puedes dejarlos así.")))
        }
        let restaurar = boton(L("Restablecer todo"), id: "Temas_Restablecer") { [weak self] in
            self?.cambiar { $0.coloresTema[tema.id] = nil }
        }
        restaurar.isEnabled = !cambios.isEmpty
        filas.append(restaurar)
        apartado(L("Personalizar colores (tema «\(tema.name)»)"), filas,
                 pie: L("Sólo cambian este tema y no tocan su archivo .tema: los demás temas siguen igual."), en: f)
    }

    private func elegirColor(_ clave: String, _ nombre: String, _ actual: RGB, tema: String) -> Button {
        let muestra = Button()
        vestir(muestra)
        muestra.background = EstiloMac.pincel(actual.opaque)
        muestra.content = EstiloMac.letra(clave.hasPrefix("ansi") ? nombre : actual.description,
                                        tamano: 11, peso: 600, color: EstiloMac.pincel(actual.readable))
        let ayuda = L("Elegir el color de «\(nombre)»")
        AutomationProperties.setName(muestra, ayuda)
        ToolTipService.setToolTip(muestra, ayuda)
        muestra.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            onTemaElegirColor?(actual) { nuevo in
                guard let nuevo else { return }
                self.cambiar {
                    var capa = ThemeOverrides($0.coloresTema[tema] ?? [:])
                    capa[clave] = nuevo
                    $0.coloresTema[tema] = capa.dictionary
                }
            }
        }
        return muestra
    }

    /// La vista previa de arriba (`ThemePreview`): una app en pequeño con los colores del tema.
    private func pintarVista(_ original: Theme) {
        guard let vista else { return }
        let t = original.solid
        func p(_ c: RGB, _ a: Double = 1) -> SolidColorBrush { EstiloMac.pincel(c, alfa: a) }
        let pila = StackPanel()
        pila.orientation = .vertical
        let barra = Grid()
        barra.background = p(t.bar)
        barra.height = 34
        for tipo in [GridUnitType.auto, .auto, .star, .auto] {
            let c = ColumnDefinition()
            c.width = GridLength(value: 1, gridUnitType: tipo)
            barra.columnDefinitions.append(c)
        }
        func pestana(_ texto: String, _ activa: Bool) -> Border {
            let b = Border()
            b.background = activa ? p(t.tab) : p(t.panel, 0.6)
            b.cornerRadius = EstiloMac.radio(8)
            b.padding = Thickness(left: 10, top: 3, right: 10, bottom: 3)
            b.margin = Thickness(left: 8, top: 0, right: 0, bottom: 0)
            b.verticalAlignment = .center
            b.child = EstiloMac.letra("\u{25CF} " + texto, tamano: 11, peso: 600, color: activa ? p(t.onTab) : p(t.accent2))
            return b
        }
        let p1 = pestana("core-01", true)
        let p2 = pestana("bastion", false)
        let nombre = EstiloMac.letra(original.name.uppercased(), tamano: 10, peso: 600, color: p(t.dim))
        nombre.characterSpacing = 150
        nombre.margin = Thickness(left: 0, top: 0, right: 12, bottom: 0)
        let hora = EstiloMac.letra("23:18", tamano: 10, peso: 600, color: p(t.accent))
        hora.margin = Thickness(left: 0, top: 0, right: 12, bottom: 0)
        let derecha = enLinea([nombre, hora], separacion: 0)
        Grid.setColumn(p1, Int32(0))
        Grid.setColumn(p2, Int32(1))
        Grid.setColumn(derecha, Int32(3))
        barra.children.append(p1)
        barra.children.append(p2)
        barra.children.append(derecha)
        let linea = Border()
        linea.height = 2
        linea.background = p(t.tab)
        let salida = TextBlock()
        salida.fontFamily = FontFamily("Consolas")
        salida.fontSize = 12
        salida.lineHeight = 18
        salida.margin = Thickness(left: 12, top: 8, right: 12, bottom: 8)
        let trozos: [(String, RGB)] = [
            ("core-01", t.accent), ("#show ip interface brief\n", t.text),
            ("GigabitEthernet0/0/0   ", t.accent2), ("192.0.2.11    ", t.special), ("up          ", t.good), ("up\n", t.good),
            ("TenGigabitEthernet0/1  ", t.accent2), ("203.0.113.5   ", t.special), ("down        ", t.bad), ("down\n", t.bad),
            ("%LINK-3-UPDOWN", t.bad), (": Interface Gi0/0/1, changed state to ", t.text), ("up", t.good),
        ]
        for (texto, color) in trozos {
            let r = Run()
            r.text = texto
            r.foreground = p(color)
            salida.inlines.append(r)
        }
        pila.children.append(barra)
        pila.children.append(linea)
        pila.children.append(salida)
        vista.child = pila
        vista.background = p(t.background)
        vista.cornerRadius = EstiloMac.radio(10)
        vista.borderBrush = p(t.accent, 0.4)
        vista.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
    }

    /// Una tarjeta de la galería (`ThemeGallery`): muestra con sus colores arriba y el pie del color de la pestaña.
    private func tarjetaTema(_ original: Theme) -> Button {
        let t = original.solid
        let activo = original.id == settings.idTemaActual
        func p(_ c: RGB, _ a: Double = 1) -> SolidColorBrush { EstiloMac.pincel(c, alfa: a) }

        let muestra = TextBlock()
        muestra.fontFamily = FontFamily("Consolas")
        muestra.fontSize = 10
        muestra.lineHeight = 15
        for (texto, color) in [("admin@core-01", t.accent), ("> show int\n", t.text), ("xe-0/0/1 ", t.text), ("up ", t.good),
                               ("192.0.2.1 ", t.accent2), ("down", t.bad)] {
            let r = Run()
            r.text = texto
            r.foreground = p(color)
            muestra.inlines.append(r)
        }
        let arriba = Border()
        arriba.background = p(t.background)
        arriba.padding = Thickness(left: 10, top: 10, right: 10, bottom: 10)
        arriba.child = muestra

        let pie = Grid()
        let c0 = ColumnDefinition()
        c0.width = GridLength(value: 1, gridUnitType: .star)
        let c1 = ColumnDefinition()
        c1.width = GridLength(value: 1, gridUnitType: .auto)
        pie.columnDefinitions.append(c0)
        pie.columnDefinitions.append(c1)
        let textos = StackPanel()
        textos.orientation = .vertical
        textos.children.append(EstiloMac.letra(original.name, tamano: 12, peso: 700, color: p(t.onTab)))
        textos.children.append(EstiloMac.letra(original.fonts.first ?? original.group, tamano: 10, color: p(t.onTab, 0.75)))
        Grid.setColumn(textos, Int32(0))
        pie.children.append(textos)
        if activo {
            let marca = EstiloMac.icono("\u{E73E}", tamano: 14, color: p(t.onTab))
            Grid.setColumn(marca, Int32(1))
            pie.children.append(marca)
        }
        let abajo = Border()
        abajo.background = p(t.tab)
        abajo.padding = Thickness(left: 10, top: 6, right: 10, bottom: 7)
        abajo.child = pie

        let pila = StackPanel()
        pila.orientation = .vertical
        pila.children.append(arriba)
        pila.children.append(abajo)
        let marco = Border()
        marco.child = pila
        marco.cornerRadius = EstiloMac.radio(10)
        marco.borderBrush = p(t.accent, activo ? 1 : 0.5)
        marco.borderThickness = activo ? Thickness(left: 2, top: 2, right: 2, bottom: 2)
                                       : Thickness(left: 1, top: 1, right: 1, bottom: 1)

        let b = Button()
        b.content = marco
        b.width = 196
        b.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        b.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        b.background = estilo.transparente
        b.cornerRadius = EstiloMac.radio(10)
        b.horizontalContentAlignment = .stretch
        if !original.summary.isEmpty { ToolTipService.setToolTip(b, original.summary) }
        AutomationProperties.setAutomationId(b, "Tema_\(original.id)")
        AutomationProperties.setName(b, original.name)
        b.pointerEntered.addHandler { [weak self] _, _ in self?.pintarVista(original) }
        b.pointerExited.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.pintarVista(self.settings.temaPersonalizado() ?? self.estilo.tema)
        }
        b.click.addHandler { [weak self] _, _ in
            self?.cambiar { $0.temaAuto = false; $0.temaTerminal = original.id }
        }
        return b
    }

    // MARK: - Fuentes

    private func seccionFuentes(_ f: StackPanel) {
        let tema = settings.temaPersonalizado() ?? estilo.tema
        let automatico = min(AjustesTerminal.tamanos.upperBound, max(AjustesTerminal.tamanos.lowerBound, tema.size - 1))
        let muestra = TextBlock()
        muestra.text = "core-01(config)# interface xe-0/0/1\nadmin@core-01> show bgp summary | match Estab"
        muestra.fontFamily = FontFamily(settings.fuente)
        muestra.fontSize = Double(settings.tamano)
        muestra.foreground = EstiloMac.pincel(tema.solid.text)
        let caja = Border()
        caja.child = muestra
        caja.background = EstiloMac.pincel(tema.solid.background)
        caja.padding = Thickness(left: 10, top: 10, right: 10, bottom: 10)
        apartado(L("Terminal"), [
            fila(L("Fuente"), selector(AjustesTerminal.fuentes.map { ($0, $0) }, settings.fuente) { $0.fuente = $1 },
                 id: "Ajustes_Fuente"),
            deslizador(L("Tama\u{00F1}o"), rango: Double(AjustesTerminal.tamanos.lowerBound)...Double(AjustesTerminal.tamanos.upperBound),
                       paso: 1, valor: Double(settings.tamano), id: "Ajustes_Tamano",
                       formato: { L("\(Int($0.rounded())) pt") }) {
                $0.tamano = Int($1.rounded())
                $0.tamanoAuto = false
            },
            interruptor(L("Autom\u{00E1}tico: el del tema (\(automatico) pt)"), settings.tamanoAuto, id: "Ajustes_TamanoAuto") {
                $0.tamanoAuto = $1
            },
            deslizador(L("Interlineado"), rango: 1...1.5, paso: 0.05, valor: settings.interlineado, id: "Ajustes_Interlineado",
                       formato: { String(format: "%.2f", $0) }) { $0.interlineado = $1 },
            caja,
        ], en: f)
        let fuentes = ["Segoe UI Variable", "Segoe UI", "Arial", "Tahoma", "Verdana"] + AjustesTerminal.fuentes
        let opciones = [("", L("La del tema (\(tema.uiFonts.first ?? "Segoe UI"))")), ("system", L("Monoespaciada del sistema"))]
            + fuentes.map { ($0, $0) }
        apartado(L("Interfaz"), [
            fila(L("Fuente"), selector(opciones, settings.fuenteInterfaz) { $0.fuenteInterfaz = $1 },
                 id: "Ajustes_FuenteInterfaz"),
        ], en: f)
    }

    // MARK: - Resaltado

    private func seccionResaltado(_ f: StackPanel) {
        let ruta = rutaResaltado?() ?? "—"
        let cfg = reglasDeVistaPrevia?() ?? HighlightConfig()
        let abrirEnEditor = boton(L("Abrir en el editor…"), id: "Ajustes_ReglasEnEditor") { [weak self] in
            self?.onCustomizeHighlight?()
        }
        ToolTipService.setToolTip(abrirEnEditor, L("Crea una copia personalizada (si no la hay) y la abre en tu editor de texto"))
        let origenes = [("auto", L("Automático")), ("netdeck", L("Reglas incluidas (chromaterm.yml)")),
                        ("app", L("Las de la app")), ("custom", L("Personalizadas"))]
        var opciones: [FrameworkElement] = [
            interruptor(L("Resaltar la salida de los equipos"), settings.resaltado, id: "Ajustes_Resaltado") {
                $0.resaltado = $1
            },
            fila(L("Reglas"), selector(origenes, settings.origenResaltado) { $0.origenResaltado = $1 }),
            interruptor(L("Con los colores del tema"), settings.coloresResaltadoDelTema,
                        id: "Resaltado_ColoresDelTema") { $0.coloresResaltadoDelTema = $1 },
            fila(ruta, enLinea([
                boton(L("Editar las reglas…"), id: "Ajustes_Reglas") { [weak self] in self?.onHighlight?() },
                abrirEnEditor,
                boton(L("Recargar"), id: "Ajustes_RecargarResaltado") { [weak self] in self?.onReloadHighlight?() },
            ], separacion: 6)),
        ]
        if !cfg.problems.isEmpty { opciones.append(nota(L("No se han podido leer: ") + cfg.problems.joined(separator: " · "))) }
        apartado(L("Resaltado tipo ChromaTerm"), opciones,
                 pie: L("Mismo formato que ChromaTerm (description, regex, color «f.cyan bold», exclusive). ")
                    + L("No toca los colores que ya pone el equipo ni las pantallas completas (vi, less, top)."), en: f)

        let muestra = TextBlock()
        muestra.fontFamily = FontFamily(settings.fuente)
        muestra.fontSize = Double(settings.tamano)
        muestra.isTextSelectionEnabled = true
        muestra.textWrapping = .wrap
        let tema = settings.temaPersonalizado() ?? estilo.tema
        muestra.foreground = EstiloMac.pincel(tema.text)
        let h = Highlighter(rules: cfg.rules, palette: cfg.palette)
        let ejemplo = """
            admin@core-01> show interfaces terse | match "xe-|ae"
            xe-0/0/0   up   up     inet 192.0.2.1/30
            xe-0/0/1   up   down
            ae0        up   up     inet 192.0.2.5/30   2001:db8::1/64
            core-01#show ip bgp summary
            192.0.2.2   4  65001   1234   1200   Established
            Rx power: -27.80 dBm   Tx power: -2.10 dBm
            CRC errors 15, input errors 3, 0 drops
            2026-10-13 14:51:02 %LINK-3-UPDOWN: Interface GigabitEthernet0/1, changed state to down
            tu.usuario@bastion:~$ ping -c1 192.0.2.1
            64 bytes from 192.0.2.1: icmp_seq=1 ttl=64 time=1.23 ms --- 0% packet loss
            A:admin@PE-MAD-01# show port 1/1/c1/1
            Admin State       : Up                Oper State        : Down
            12 2026/10/17 10:12:01 CEST MAJOR: PORT #2004 Base Port 1/1/c1/1 lag-10 · CLEARED
            """
        func incluir(_ texto: Substring, _ estilo: HighlightStyle? = nil) {
            guard !texto.isEmpty else { return }
            let run = Run()
            run.text = String(texto)
            if let color = estilo?.foreground.flatMap({ cfg.palette[$0] ?? RGB(hex: $0) }) {
                run.foreground = EstiloMac.pincel(color)
            }
            if estilo?.bold == true { run.fontWeight = FontWeight(weight: 700) }
            if estilo?.italic == true { run.fontStyle = .init(rawValue: 2) }
            if estilo?.underline == true { run.textDecorations = .init(rawValue: 1) }
            muestra.inlines.append(run)
        }
        for linea in ejemplo.components(separatedBy: "\n") {
            var cursor = linea.startIndex
            for (rango, estilo) in settings.resaltado ? h.styledRuns(linea) : [] {
                incluir(linea[cursor..<rango.lowerBound])
                incluir(linea[rango], estilo)
                cursor = rango.upperBound
            }
            incluir(linea[cursor...])
            incluir("\n"[...])
        }
        let fondo = Border()
        fondo.background = EstiloMac.pincel(tema.solid.background)
        fondo.padding = Thickness(left: 12, top: 12, right: 12, bottom: 12)
        fondo.child = muestra
        apartado(L("Vista previa"), [fondo], en: f)

        var colores: [FrameworkElement] = []
        for nombre in HighlightStyle.colorNames {
            let color = cfg.palette[nombre] ?? tema.text
            let swatch = Button()
            vestir(swatch)
            swatch.background = EstiloMac.pincel(color.opaque)
            swatch.content = EstiloMac.letra(color.description, tamano: 11, color: EstiloMac.pincel(color.readable))
            AutomationProperties.setName(swatch, L("Elegir el color de «f.\(nombre)»"))
            swatch.click.addHandler { [weak self] _, _ in
                guard let self else { return }
                onTemaElegirColor?(color) { nuevo in
                    guard let nuevo else { return }
                    self.cambiar { $0.coloresResaltado[tema.id, default: [:]][nombre] = nuevo.description }
                }
            }
            colores.append(fila("f.\(nombre)", swatch))
        }
        let restablecer = boton(L("Volver a los del tema"), id: "Resaltado_Restablecer") { [weak self] in
            self?.cambiar { $0.coloresResaltado[tema.id] = nil }
        }
        restablecer.isEnabled = !(settings.coloresResaltado[tema.id] ?? [:]).isEmpty
        colores.append(restablecer)
        apartado(L("Colores del resaltado (tema «\(tema.name)»)"), colores, en: f)
    }

    // MARK: - Botones

    private func seccionBotones(_ f: StackPanel) {
        apartado(L("Barra"), [
            fila(L("Barra"), segmentos([("arriba", L("Arriba")), ("abajo", L("Abajo")), ("oculta", L("Oculta"))],
                                        settings.posicionBotones, id: "Ajustes_PosicionBotones") { [weak self] valor in
                self?.cambiar { $0.posicionBotones = valor }
            }),
            interruptor(L("Por grupos (\u{2630})"), settings.botonesPorGrupos, id: "Ajustes_BotonesPorGrupos") {
                $0.botonesPorGrupos = $1
            },
        ], pie: L("Con \u{00AB}Por grupos\u{00BB}, un desplegable elige el grupo y s\u{00F3}lo salen sus botones; si no, todos seguidos."), en: f)
        apartado(L("Botones"), [
            fila(L("botones.txt: grupo, modo, nombre, tecla y orden de cada bot\u{00F3}n"),
                 boton(L("Editar los botones\u{2026}"), id: "Ajustes_EditarBotones") { [weak self] in self?.onEditButtons?() }),
        ], en: f)
    }

    // MARK: - Registro

    private func seccionRegistro(_ f: StackPanel) {
        let carpeta = settings.urlRegistro
        let porDefecto = SessionLogger.defaultDirectory.path
        let restaurar = boton(L("Volver a la predeterminada (~/Documents/netdeck-logs)"), id: "Registro_Restaurar") { [weak self] in
            guard let self else { return }
            cambiar { $0.carpetaRegistros = porDefecto }
            construirSeccion()
        }
        restaurar.isEnabled = settings.carpetaRegistros != porDefecto
        apartado(L("Registro de las sesiones"), [
            interruptor(L("Grabar todas las sesiones a un archivo"), settings.grabarSesiones, id: "Registro_Auto") { $0.grabarSesiones = $1 },
            fila(AppPaths.tilde(carpeta.path), enLinea([
                boton(L("Elegir carpeta…"), id: "Registro_Elegir") { [weak self] in
                    guard let self, let carpeta = onElegirCarpetaRegistro?() else { return }
                    cambiar { $0.carpetaRegistros = carpeta.path }
                    construirSeccion()
                },
                boton(L("Abrir"), id: "Registro_AbrirCarpeta") { [weak self] in
                    AppPaths.ensure(carpeta)
                    self?.onAbrirRegistro?(carpeta)
                },
            ])),
            restaurar,
        ], pie: L("Texto limpio: sin colores y con los paginadores borrados, en CARPETA/AAAA-MM-DD/sesión_HH-MM-SS.log. ")
            + L("Mientras graba sale ● REC en la esquina; clic derecho en una pestaña para grabar o parar sólo esa."), en: f)
        let activos = registrosActivos?() ?? []
        var filas: [FrameworkElement] = []
        if activos.isEmpty { filas.append(nota(L("Ninguna pestaña grabando"))) }
        for (titulo, archivo, parar) in activos {
            filas.append(fila("● \(titulo)", enLinea([
                boton(L("Abrir"), id: "Registro_Abrir") { [weak self] in self?.onAbrirRegistro?(archivo) },
                boton(L("Parar"), id: "Registro_Parar") { [weak self] in
                    parar()
                    self?.construirSeccion()
                },
            ])))
        }
        apartado(L("Ahora"), filas, en: f)
        apartado(L("Depuración"), [
            interruptor(L("Registro de depuración"), settings.depuracion, id: "Registro_Depuracion") { $0.depuracion = $1 },
            fila(AppPaths.tilde(DebugLog.file.path), boton(L("Abrir"), id: "Registro_AbrirDepuracion") { [weak self] in
                DebugLog.flush()
                self?.onAbrirRegistro?(DebugLog.file)
            }),
        ], pie: L("Qué hace la app (pestañas, saltos, MultiExec, decisiones de contraseña…), nunca contraseñas."), en: f)
    }

    // MARK: - Terminal

    private func seccionTerminal(_ f: StackPanel) {
        let cantidades = TerminalHistory.options.contains(settings.scrollback)
            ? TerminalHistory.options : [settings.scrollback] + TerminalHistory.options
        apartado(L("Historial"), [
            fila(L("Líneas guardadas por pestaña"),
                 selector(cantidades.map { (String($0), TerminalHistory.label($0)) }, String(settings.scrollback)) {
                     $0.scrollback = TerminalHistory.lines($1)
                 }, id: "Ajustes_Historial"),
        ], pie: L("Las que puedes volver a ver subiendo con la rueda o la barra. Se aplica también a las pestañas abiertas: si bajas el número, se pierden las más antiguas que no quepan."), en: f)
        apartado(L("Ratón"), [
            interruptor(L("Copiar al seleccionar"), settings.copiarAlSeleccionar, id: "Ajustes_CopiarSeleccion") {
                $0.copiarAlSeleccionar = $1
            },
            interruptor(L("Pegar con clic derecho"), settings.pegarClicDerecho, id: "Ajustes_PegarClicDerecho") {
                $0.pegarClicDerecho = $1
            },
            nota(L("Como en PuTTY o SecureCRT. El clic derecho pega igual que Ctrl+May\u{00FA}s+V.")),
        ], en: f)
        apartado(L("Vista dividida"), [
            fila(L("Orientaci\u{00F3}n"), selector([("lado", L("Lado a lado")), ("apilada", L("Arriba y abajo"))],
                                                  settings.divisionApilada ? "apilada" : "lado") { $0.divisionApilada = $1 == "apilada" },
                 id: "Ajustes_Orientacion"),
        ], en: f)
        let tema = settings.temaPersonalizado() ?? estilo.tema
        var opciones: [(valor: String, texto: String)] = [
            (ScreenFilter.automatic, L("Autom\u{00E1}tico: el del tema (\((tema.screenFilter ?? .none).name))")),
        ]
        opciones += ScreenFilter.allCases.map { ($0.rawValue, $0.name) }
        apartado(L("Filtro de pantalla"), [
            interruptor(L("Filtro encima del terminal"), settings.filtroActivo, id: "Ajustes_FiltroActivo") { $0.filtroActivo = $1 },
            fila(L("Filtro"), selector(opciones, settings.filtro) { $0.filtro = $1 }, id: "Ajustes_Filtro"),
            deslizador(L("Intensidad"), rango: ScreenFilter.intensityRange, paso: 0.05, valor: settings.intensidad,
                       id: "Ajustes_Intensidad", formato: { L("\(Int(($0 * 100).rounded())) %") }) { $0.intensidad = $1 },
            nota(L("L\u{00ED}neas de barrido, rejilla de p\u{00ED}xeles o resplandor encima del texto, como en una pantalla antigua. \u{00AB}Autom\u{00E1}tico\u{00BB} usa el del tema.")),
        ], en: f)
        let umbrales: [(valor: String, texto: String)] = PasteReview.thresholds.map {
            (String($0), $0 == 1 ? L("1 l\u{00ED}nea") : L("\(String($0)) l\u{00ED}neas"))
        }
        apartado(L("Pegar"), [
            interruptor(L("Revisar antes de pegar"), settings.revisarPegado, id: "Ajustes_RevisarPegado") { $0.revisarPegado = $1 },
            fila(L("Si tiene m\u{00E1}s de"), selector(umbrales, String(settings.umbralPegado), ancho: 140) {
                $0.umbralPegado = Int($1) ?? PasteReview.defaultThreshold
            }, id: "Ajustes_UmbralPegado"),
            nota(L("Con Ctrl+May\u{00FA}s+V, \u{00AB}Pegar\u{00BB} o el clic derecho, sale una ventana con el texto si pasa de ese n\u{00FA}mero de l\u{00ED}neas o lleva \u{00F3}rdenes peligrosas (reload, clear ip bgp\u{2026}). S\u{00F3}lo pregunta: al aceptar se pega entero y de golpe. Apagado, nunca sale, ni con \u{00F3}rdenes peligrosas.")),
        ], en: f)
    }

    // MARK: - General

    private func seccionGeneral(_ f: StackPanel) {
        let accesos: [(String, String)] = [
            ("NuevaLocal", L("Nueva terminal local")), ("PegarSeguro", L("Pegado seguro")),
            ("Macros", L("Macros")), ("Tuneles", L("Túneles SSH")), ("DividirTerminal", L("Pantalla dividida")),
            ("Llavero", L("Contraseñas y Llavero")), ("MultiExec", L("MultiExec")), ("BuscarTerminal", L("Buscar")),
            ("Espacios", L("Espacios de trabajo")), ("EditarRemoto", L("Editar remoto")),
            ("MostrarSesiones", L("Mostrar/ocultar sesiones")),
        ]
        apartado(L("Barra superior"), accesos.map { id, texto in
            interruptor(texto, !settings.toolbarOcultos.contains(id), id: "Barra_\(id)") { ajustes, mostrar in
                if mostrar { ajustes.toolbarOcultos.remove(id) } else { ajustes.toolbarOcultos.insert(id) }
            }
        } + [nota(L("El botón «+», Ajustes y los controles de acciones activas siempre permanecen visibles."))], en: f)
        apartado(L("Idioma"), [
            fila(L("Idioma de la interfaz"), segmentos(Idioma.allCases.map { ($0.rawValue, $0.nombre) }, Idioma.actual.rawValue,
                                                        id: "Ajustes_Idioma") { valor in
                guard let elegido = Idioma(rawValue: valor) else { return }
                Idioma.actual = elegido
                UserDefaults.standard.set(elegido.rawValue, forKey: Idioma.clave)
                UserDefaults.standard.synchronize()
            }),
            nota(L("El idioma se aplica del todo al volver a abrir la app.")),
        ], en: f)
        let perfiles = (grupos?() ?? []).flatMap { $0.1 }
        let ruta = rutaSesiones?() ?? ""
        apartado(L("Sesiones"), [
            fila(L("ssh_config: \(ruta)"), boton(L("Recargar"), id: "Ajustes_RecargarSesiones") { [weak self] in
                self?.onReloadSessions?()
            }),
            nota(L("\(perfiles.count) sesiones \u{00B7} anotaciones: # @grupo, # @clave, # @clave-grupo, # @desc, # @telnet")),
        ], en: f)
        var inicio: [(valor: String, texto: String)] = [("", L("(ninguna)"))]
        if !settings.sesionInicio.isEmpty, !perfiles.contains(where: { $0.name == settings.sesionInicio }) {
            inicio.append((settings.sesionInicio, L("\(settings.sesionInicio) (ya no existe)")))
        }
        inicio += perfiles.map { ($0.name, $0.name) }
        apartado(L("Al arrancar"), [
            fila(L("Sesi\u{00F3}n de inicio"), selector(inicio, settings.sesionInicio) { $0.sesionInicio = $1 }, id: "Ajustes_SesionInicio"),
            interruptor(L("Abrir una terminal local al arrancar si no hay otras pesta\u{00F1}as"), settings.terminalLocalInicio,
                        id: "Ajustes_TerminalLocalInicio") { $0.terminalLocalInicio = $1 },
            nota(L("La terminal local también se abre con Ctrl+Mayús+T o con el botón de terminal de la barra.")),
        ], en: f)
        let estado = nota(estadoActualizacion)
        AutomationProperties.setAutomationId(estado, "Ajustes_EstadoActualizacion")
        updateText = estado
        apartado(L("Actualizaciones"), [
            interruptor(L("Buscar versiones nuevas autom\u{00E1}ticamente (una vez al d\u{00ED}a)"), settings.buscarActualizaciones,
                        id: "Ajustes_BuscarActualizaciones") { $0.buscarActualizaciones = $1 },
            fila(L("Versi\u{00F3}n \(UpdateChecker.currentVersion)"),
                 boton(L("Buscar ahora"), id: "Ajustes_Actualizaciones") { [weak self] in self?.onCheckUpdates?() }),
            estado,
        ], en: f)
        apartado(L("Conexiones"), [
            interruptor(L("Enviar el idioma de Windows a los servidores (LANG, LC_*)"), settings.enviarIdioma,
                        id: "Ajustes_EnviarIdioma") { $0.enviarIdioma = $1 },
            nota(L("Desactivado, los servidores usan su propio idioma y no salen avisos como \u{00AB}setlocale: LC_CTYPE\u{00BB}. Se aplica a las conexiones nuevas.")),
        ], en: f)
        apartado(L("Ventana"), [
            interruptor(L("Mostrar la lista de sesiones"), settings.listaSesiones, id: "Ajustes_ListaSesiones") { $0.listaSesiones = $1 },
        ], en: f)
    }
}
