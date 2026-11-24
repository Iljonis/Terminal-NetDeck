import Foundation
import NetDeckCore
import struct UWP.FontWeight
import WinUI

/// Asistente de la primera vez, en el area principal (como el del Mac): bienvenida, tema, fuentes, contrasenas,
/// resaltado, primera sesion (opcional) y «todo listo». Cada eleccion se aplica y se guarda al momento por `onChange`.
/// Sin `ContentDialog` (swift-winui 0.1.1 no tiene un camino sencillo): un solo panel que se reconstruye por paso.
final class AsistenteInicio {
    let view = ScrollViewer()
    /// Crea la sesion; true si se guardo (si no, la ventana ya ha dicho por que en la barra de estado).
    var onCreateSession: ((EditableSession) -> Bool)?
    var onDone: (() -> Void)?
    /// Los ajustes de ahora, y a donde mandar los nuevos (la ventana los guarda y los aplica).
    var settings: () -> AjustesTerminal = { AjustesTerminal() }
    var onChange: ((AjustesTerminal) -> Void)?
    var estilo: () -> EstiloMac = { EstiloMac(tema: nil) }
    var reglasDeVistaPrevia: (() -> HighlightConfig)?

    private enum Paso: Int, CaseIterable {
        case bienvenida, tema, fuentes, contrasenas, resaltado, sesion, listo

        var titulo: String {
            switch self {
            case .bienvenida: L("Bienvenida")
            case .tema: L("Tema")
            case .fuentes: L("Fuentes")
            case .contrasenas: L("Contraseñas")
            case .resaltado: L("Resaltado")
            case .sesion: L("Tu primera sesión")
            case .listo: L("Listo")
            }
        }
    }

    private var paso = Paso.bienvenida
    private let indicador = TextBlock()
    private let contenido = StackPanel()
    private let navegacion = StackPanel()
    private var name = TextBox()
    private var host = TextBox()
    private var user = TextBox()
    private var port = TextBox()
    private var message = TextBlock()
    private var valores = ["", "", "", ""]
    private var botonesTema: [(id: String, boton: Button, nombre: TextBlock, titulo: String)] = []
    private var muestraResaltado: TextBlock?
    private var fondoMuestra: Border?

    init() {
        let root = StackPanel()
        root.orientation = .vertical
        root.maxWidth = 600
        root.horizontalAlignment = .left
        root.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)
        indicador.fontSize = 11
        indicador.opacity = 0.7
        indicador.margin = Thickness(left: 0, top: 0, right: 0, bottom: 6)
        AutomationProperties.setAutomationId(indicador, "Asistente_Paso")
        contenido.orientation = .vertical
        navegacion.orientation = .horizontal
        navegacion.spacing = 8
        navegacion.margin = Thickness(left: 0, top: 0, right: 0, bottom: 12)
        // (la navegacion va arriba: en los pasos largos, como el de temas, no hay que bajar hasta el final)
        for hijo in [indicador, navegacion, contenido] as [FrameworkElement] { root.children.append(hijo) }
        view.content = root
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    /// Vuelve a la primera pantalla.
    func start() {
        valores = ["", "", "", ""]
        go(.bienvenida)
    }

    // MARK: - Navegacion

    private func go(_ nuevo: Paso) {
        if paso == .sesion { valores = [name.text, host.text, user.text, port.text] }
        paso = nuevo
        indicador.text = "\(nuevo.rawValue + 1)/\(Paso.allCases.count) · \(nuevo.titulo)"
        contenido.children.clear()
        navegacion.children.clear()
        botonesTema = []
        muestraResaltado = nil
        fondoMuestra = nil
        switch nuevo {
        case .bienvenida:
            buildWelcome()
            siguiente(.tema)
            navegacion.children.append(button(L("Omitir"), id: "Asistente_OmitirTodo") { [weak self] in self?.onDone?() })
        case .tema:
            buildTema()
            atras(.bienvenida)
            siguiente(.fuentes)
        case .fuentes:
            buildFuentes()
            atras(.tema)
            siguiente(.contrasenas)
        case .contrasenas:
            buildContrasenas()
            atras(.fuentes)
            siguiente(.resaltado)
        case .resaltado:
            buildResaltado()
            atras(.contrasenas)
            siguiente(.sesion)
        case .sesion:
            buildFirst()
            atras(.resaltado)
            navegacion.children.append(button(L("Crear sesi\u{00F3}n"), id: "Asistente_Crear", principal: true) { [weak self] in self?.create() })
            navegacion.children.append(button(L("Omitir"), id: "Asistente_Omitir") { [weak self] in self?.onDone?() })
        case .listo:
            buildReady()
            navegacion.children.append(button(L("Empezar"), id: "Asistente_Empezar", principal: true) { [weak self] in self?.onDone?() })
        }
    }

    private func atras(_ destino: Paso) {
        navegacion.children.append(button("\u{2190} " + L("Atrás"), id: "Asistente_Atras") { [weak self] in self?.go(destino) })
    }

    private func siguiente(_ destino: Paso) {
        navegacion.children.append(button(L("Siguiente") + " \u{2192}", id: "Asistente_Siguiente", principal: true) { [weak self] in self?.go(destino) })
    }

    // MARK: - Piezas

    private func heading(_ text: String) -> TextBlock {
        let title = TextBlock()
        title.text = text
        title.fontSize = 22
        title.margin = Thickness(left: 0, top: 0, right: 0, bottom: 8)
        return title
    }

    private func paragraph(_ text: String) -> TextBlock {
        let block = TextBlock()
        block.text = text
        block.textWrapping = .wrap
        block.margin = Thickness(left: 0, top: 0, right: 0, bottom: 12)
        return block
    }

    private func small(_ text: String) -> TextBlock {
        let block = TextBlock()
        block.text = text
        block.textWrapping = .wrap
        block.fontSize = 11
        block.opacity = 0.7
        block.margin = Thickness(left: 0, top: 2, right: 0, bottom: 8)
        return block
    }

    private func sectionTitle(_ text: String) -> TextBlock {
        let block = TextBlock()
        block.text = text.uppercased()
        block.fontSize = 11
        block.opacity = 0.7
        block.margin = Thickness(left: 0, top: 10, right: 0, bottom: 4)
        return block
    }

    /// Boton con el estilo del tema: el principal relleno con el color de la pestana, el resto con borde de acento.
    private func button(_ title: String, id: String, principal: Bool = false, _ action: @escaping () -> Void) -> Button {
        let e = estilo()
        let button = Button()
        button.content = EstiloMac.letra(title, tamano: 12, peso: principal ? 700 : 500, color: principal ? e.sobrePestana : e.texto)
        let borde = e.acento(alfa: principal ? 1 : 0.6)
        button.background = principal ? e.pestana : e.panel(alfa: 0.6)
        button.borderBrush = borde
        button.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        // (con el raton encima o pulsado, la plantilla de WinUI pone su gris: se sustituye por los colores del tema)
        EstiloMac.conservarColores(button, encima: principal ? e.pestana : e.acento(alfa: 0.18),
                                   pulsado: principal ? e.pestana : e.acento(alfa: 0.3), borde: borde)
        button.cornerRadius = EstiloMac.radio(5)
        button.minHeight = 28
        button.padding = Thickness(left: 14, top: 3, right: 14, bottom: 3)
        button.click.addHandler { _, _ in action() }
        AutomationProperties.setAutomationId(button, id)
        AutomationProperties.setName(button, title)
        return button
    }

    private func aplicar(_ cambio: (inout AjustesTerminal) -> Void) {
        var ajustes = settings()
        cambio(&ajustes)
        onChange?(ajustes)
    }

    /// Etiqueta a la izquierda y el interruptor a la derecha.
    private func interruptor(_ etiqueta: String, _ valor: Bool, id: String,
                             _ cambio: @escaping (inout AjustesTerminal, Bool) -> Void,
                             despues: (() -> Void)? = nil) -> Grid {
        let fila = Grid()
        let c0 = ColumnDefinition()
        c0.width = GridLength(value: 1, gridUnitType: .star)
        let c1 = ColumnDefinition()
        c1.width = GridLength(value: 1, gridUnitType: .auto)
        fila.columnDefinitions.append(c0)
        fila.columnDefinitions.append(c1)
        let texto = TextBlock()
        texto.text = etiqueta
        texto.textWrapping = .wrap
        texto.verticalAlignment = .center
        let interruptor = ToggleSwitch()
        interruptor.isOn = valor
        interruptor.onContent = ""
        interruptor.offContent = ""
        interruptor.minWidth = 0
        AutomationProperties.setAutomationId(interruptor, id)
        AutomationProperties.setName(interruptor, etiqueta)
        interruptor.toggled.addHandler { [weak self] origen, _ in
            guard let interruptor = origen as? ToggleSwitch else { return }
            let encendido = interruptor.isOn
            self?.aplicar { cambio(&$0, encendido) }
            despues?()
        }
        Grid.setColumn(texto, Int32(0))
        Grid.setColumn(interruptor, Int32(1))
        fila.children.append(texto)
        fila.children.append(interruptor)
        fila.margin = Thickness(left: 0, top: 4, right: 0, bottom: 4)
        return fila
    }

    private func selector(_ opciones: [(valor: String, texto: String)], _ actual: String, id: String,
                          _ elegir: @escaping (String) -> Void) -> ComboBox {
        let combo = ComboBox()
        combo.minWidth = 260
        for opcion in opciones { combo.items.append(opcion.texto) }
        combo.selectedIndex = Int32(opciones.firstIndex { $0.valor == actual } ?? 0)
        AutomationProperties.setAutomationId(combo, id)
        combo.selectionChanged.addHandler { origen, _ in
            guard let combo = origen as? ComboBox, opciones.indices.contains(Int(combo.selectedIndex)) else { return }
            elegir(opciones[Int(combo.selectedIndex)].valor)
        }
        return combo
    }

    /// Botones de una sola eleccion, juntos; al elegir se reconstruye el paso para marcar el nuevo.
    private func segmentos(_ opciones: [(valor: String, texto: String)], _ actual: String, id: String,
                           _ elegir: @escaping (String) -> Void) -> StackPanel {
        let e = estilo()
        let fila = StackPanel()
        fila.orientation = .horizontal
        fila.spacing = 2
        for opcion in opciones {
            let boton = Button()
            let elegido = opcion.valor == actual
            boton.content = EstiloMac.letra(opcion.texto, tamano: 12, peso: elegido ? 600 : 400,
                                            color: elegido ? e.sobrePestana : e.texto)
            boton.background = elegido ? e.pestana : e.panel(alfa: 0.6)
            boton.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
            boton.cornerRadius = EstiloMac.radio(5)
            boton.padding = Thickness(left: 12, top: 4, right: 12, bottom: 4)
            AutomationProperties.setAutomationId(boton, "\(id)_\(opcion.valor)")
            AutomationProperties.setName(boton, opcion.texto)
            boton.click.addHandler { [weak self] _, _ in
                guard let self else { return }
                elegir(opcion.valor)
                self.go(self.paso)
            }
            fila.children.append(boton)
        }
        return fila
    }

    // MARK: - Pasos

    private func buildWelcome() {
        contenido.children.append(heading(L("Bienvenido a Terminal NetDeck")))
        contenido.children.append(paragraph(L("Aqu\u{00ED} tienes tus servidores y equipos de red en la barra lateral: haz clic en uno para abrir una conexi\u{00F3}n, o en + para a\u{00F1}adir otro. Puedes abrir varias pesta\u{00F1}as, usar un explorador de archivos SFTP y crear t\u{00FA}neles SSH.")))
        contenido.children.append(paragraph(L("En unos pasos eliges el tema, las fuentes, c\u{00F3}mo se tratan las contrase\u{00F1}as y el resaltado de la salida. Todo se aplica al momento y se puede cambiar despu\u{00E9}s en Ajustes.")))
    }

    private func buildTema() {
        contenido.children.append(heading(L("Tema")))
        contenido.children.append(paragraph(L("Haz clic en uno para usarlo: toda la app lo adopta al momento. Puedes cambiarlo cuando quieras en Ajustes.")))
        let actual = settings().idTemaActual
        let temas = TemasTerminal.disponibles()
        var grupos: [String] = []
        for tema in temas where !grupos.contains(tema.group) { grupos.append(tema.group) }
        for grupo in grupos {
            contenido.children.append(sectionTitle(grupo))
            for tema in temas where tema.group == grupo {
                let (boton, nombre) = filaTema(tema, elegido: tema.id == actual)
                botonesTema.append((tema.id, boton, nombre, tema.name))
                contenido.children.append(boton)
            }
        }
    }

    private func filaTema(_ tema: Theme, elegido: Bool) -> (Button, TextBlock) {
        let e = estilo()
        let boton = Button()
        let fila = StackPanel()
        fila.orientation = .horizontal
        fila.spacing = 10
        let muestras = StackPanel()
        muestras.orientation = .horizontal
        muestras.spacing = 2
        muestras.verticalAlignment = .center
        for color in [tema.bar, tema.panel, tema.accent, tema.accent2, tema.good, tema.bad] {
            let muestra = Border()
            muestra.width = 14
            muestra.height = 14
            muestra.cornerRadius = EstiloMac.radio(3)
            muestra.background = EstiloMac.pincel(color)
            muestras.children.append(muestra)
        }
        let textos = StackPanel()
        textos.orientation = .vertical
        let nombre = EstiloMac.letra(tema.name + (elegido ? "  \u{2713}" : ""), tamano: 13, peso: 600, color: e.texto)
        textos.children.append(nombre)
        if !tema.summary.isEmpty {
            let resumen = EstiloMac.letra(tema.summary, tamano: 11, color: e.apagado)
            resumen.textWrapping = .wrap
            textos.children.append(resumen)
        }
        fila.children.append(muestras)
        fila.children.append(textos)
        boton.content = fila
        boton.horizontalAlignment = .stretch
        boton.horizontalContentAlignment = .left
        boton.background = e.panel(alfa: 0.6)
        boton.cornerRadius = EstiloMac.radio(8)
        boton.padding = Thickness(left: 10, top: 6, right: 10, bottom: 6)
        boton.margin = Thickness(left: 0, top: 0, right: 0, bottom: 3)
        boton.borderBrush = e.acento
        boton.borderThickness = elegido ? Thickness(left: 2, top: 2, right: 2, bottom: 2)
                                        : Thickness(left: 0, top: 0, right: 0, bottom: 0)
        AutomationProperties.setAutomationId(boton, "Asistente_Tema_\(tema.id)")
        AutomationProperties.setName(boton, tema.name)
        boton.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.aplicar { $0.temaAuto = false; $0.temaTerminal = tema.id }
            self.marcarTema(tema.id)
        }
        return (boton, nombre)
    }

    /// Marca el tema elegido sin reconstruir la lista (no pierde la posicion de desplazamiento).
    private func marcarTema(_ id: String) {
        let e = estilo()
        for (otro, boton, nombre, titulo) in botonesTema {
            boton.borderBrush = e.acento
            boton.borderThickness = otro == id ? Thickness(left: 2, top: 2, right: 2, bottom: 2)
                                                : Thickness(left: 0, top: 0, right: 0, bottom: 0)
            nombre.text = titulo + (otro == id ? "  \u{2713}" : "")
        }
    }

    private func buildFuentes() {
        let ajustes = settings()
        contenido.children.append(heading(L("Fuentes")))
        contenido.children.append(paragraph(L("La del terminal y la de la interfaz. Se pueden cambiar cuando quieras en Ajustes \u{2192} Fuentes.")))
        let terminales = AjustesTerminal.fuentes
        var opcionesTerminal = terminales.map { (valor: $0, texto: $0) }
        if !terminales.contains(ajustes.fuente) { opcionesTerminal.insert((ajustes.fuente, ajustes.fuente), at: 0) }
        contenido.children.append(sectionTitle(L("Terminal")))
        contenido.children.append(selector(opcionesTerminal, ajustes.fuente, id: "Asistente_FuenteTerminal") { [weak self] fuente in
            self?.aplicar { $0.fuente = fuente }
        })
        var opcionesInterfaz: [(valor: String, texto: String)] = [
            ("", L("La del tema")), ("system", L("Monoespaciada del sistema")),
        ]
        for nombre in ["Segoe UI Variable", "Segoe UI", "Arial", "Tahoma", "Verdana"] + terminales
        where !opcionesInterfaz.contains(where: { $0.valor == nombre }) {
            opcionesInterfaz.append((nombre, nombre))
        }
        contenido.children.append(sectionTitle(L("Interfaz")))
        contenido.children.append(selector(opcionesInterfaz, ajustes.fuenteInterfaz, id: "Asistente_FuenteInterfaz") { [weak self] fuente in
            self?.aplicar { $0.fuenteInterfaz = fuente }
        })
        let recomendadas = fuentesRecomendadas(para: ajustes.idTemaActual)
        if !recomendadas.isEmpty {
            contenido.children.append(sectionTitle(L("Recomendadas por tus temas")))
            for nombre in recomendadas {
                let boton = button(nombre + (nombre == ajustes.fuente ? "  \u{2713}" : ""), id: "Asistente_Recomendada_\(nombre)") { [weak self] in
                    guard let self else { return }
                    self.aplicar { $0.fuente = nombre }
                    self.go(.fuentes)
                }
                boton.margin = Thickness(left: 0, top: 0, right: 0, bottom: 3)
                contenido.children.append(boton)
            }
        }
    }

    /// La fuente oficial del tema y la de los de su grupo (8 como mucho): lo mismo que recomienda el asistente del Mac.
    private func fuentesRecomendadas(para id: String) -> [String] {
        var lista: [String] = []
        if let tema = TemasTerminal.tema(id: id) {
            if let fuente = tema.fonts.first { lista.append(fuente) }
            for hermano in TemasTerminal.disponibles() where hermano.group == tema.group {
                if let fuente = hermano.fonts.first, !lista.contains(fuente) { lista.append(fuente) }
            }
        }
        return Array(lista.prefix(8))
    }

    private func buildContrasenas() {
        let ajustes = settings()
        contenido.children.append(heading(L("Contraseñas")))
        contenido.children.append(paragraph(L("Siempre en el llavero de la app. Se pueden cambiar cuando quieras en Ajustes \u{2192} Contraseñas.")))
        contenido.children.append(interruptor(L("Escribir sola la contraseña al abrir una sesión"), ajustes.contrasenaAutomatica,
                                              id: "Asistente_ContrasenaAutomatica") { $0.contrasenaAutomatica = $1 })
        contenido.children.append(small(L("Al abrir SSH o SFTP usa solo la contraseña asignada a esa sesión y a cada salto. Si falta, te la pide; Telnet se inicia a mano. Si no vale, te la pide a ti (no se bloquea).")))
        contenido.children.append(sectionTitle(L("Equipos (ssh / telnet desde una sesión)")))
        let opciones: [(valor: String, texto: String)] = [
            (PasswordAutomation.Mode.autoType.rawValue, L("Escribirla sola")),
            (PasswordAutomation.Mode.suggest.rawValue, L("Sugerirla")),
            (PasswordAutomation.Mode.off.rawValue, L("Nada")),
        ]
        contenido.children.append(segmentos(opciones, ajustes.modoClaveEquipo.rawValue, id: "Asistente_ModoClave") { [weak self] valor in
            guard let modo = PasswordAutomation.Mode(rawValue: valor) else { return }
            self?.aplicar { $0.modoClaveEquipo = modo }
        })
        contenido.children.append(small(L("Nunca la de otro usuario: con «ssh root@…» o «Username: pepe», solo una guardada de ese usuario.")))
    }

    private func buildResaltado() {
        let ajustes = settings()
        contenido.children.append(heading(L("Resaltado")))
        contenido.children.append(paragraph(L("Colores en la salida de los equipos, como ChromaTerm: interfaces, IPs, estados, dBm, errores, prompts…")))
        contenido.children.append(interruptor(L("Resaltar la salida de los equipos"), ajustes.resaltado, id: "Asistente_Resaltado",
                                              { $0.resaltado = $1 }, despues: { [weak self] in self?.pintarMuestra() }))
        contenido.children.append(sectionTitle(L("Vista previa")))
        let muestra = TextBlock()
        muestra.isTextSelectionEnabled = true
        muestra.textWrapping = .wrap
        let fondo = Border()
        fondo.padding = Thickness(left: 12, top: 12, right: 12, bottom: 12)
        fondo.child = muestra
        muestraResaltado = muestra
        fondoMuestra = fondo
        contenido.children.append(fondo)
        pintarMuestra()
    }

    private func pintarMuestra() {
        guard let muestra = muestraResaltado, let fondo = fondoMuestra else { return }
        let ajustes = settings()
        let cfg = reglasDeVistaPrevia?() ?? HighlightConfig()
        let tema = ajustes.temaPersonalizado() ?? estilo().tema
        muestra.fontFamily = FontFamily(ajustes.fuente)
        muestra.fontSize = Double(ajustes.tamano)
        muestra.foreground = EstiloMac.pincel(tema.text)
        fondo.background = EstiloMac.pincel(tema.solid.background)
        muestra.inlines.clear()
        let h = Highlighter(rules: cfg.rules, palette: cfg.palette)
        let ejemplo = """
            admin@core-01> show interfaces terse | match "xe-|ae"
            xe-0/0/0   up   up     inet 192.0.2.1/30
            xe-0/0/1   up   down
            core-01#show ip bgp summary
            192.0.2.2   4  65001   1234   1200   Established
            Rx power: -27.80 dBm   Tx power: -2.10 dBm
            CRC errors 15, input errors 3, 0 drops
            2026-10-13 14:51:02 %LINK-3-UPDOWN: Interface GigabitEthernet0/1, changed state to down
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
            for (rango, estilo) in ajustes.resaltado ? h.styledRuns(linea) : [] {
                incluir(linea[cursor..<rango.lowerBound])
                incluir(linea[rango], estilo)
                cursor = rango.upperBound
            }
            incluir(linea[cursor...])
            incluir("\n"[...])
        }
    }

    private func buildFirst() {
        contenido.children.append(heading(L("Tu primera sesi\u{00F3}n")))
        contenido.children.append(paragraph(L("Nombre y equipo son obligatorios; usuario y puerto, no. Puedes saltarte este paso y a\u{00F1}adir sesiones m\u{00E1}s tarde.")))
        name = TextBox()
        host = TextBox()
        user = TextBox()
        port = TextBox()
        name.text = valores[0]
        host.text = valores[1]
        user.text = valores[2]
        port.text = valores[3]
        let fields: [(String, TextBox, String)] = [
            (L("Nombre"), name, "Asistente_Nombre"),
            (L("Equipo"), host, "Asistente_Equipo"),
            (L("Usuario"), user, "Asistente_Usuario"),
            (L("Puerto"), port, "Asistente_Puerto"),
        ]
        for (label, box, id) in fields {
            let caption = TextBlock()
            caption.text = label
            caption.fontSize = 12
            caption.opacity = 0.7
            AutomationProperties.setAutomationId(box, id)
            let item = StackPanel()
            item.orientation = .vertical
            item.spacing = 2
            item.margin = Thickness(left: 0, top: 0, right: 0, bottom: 6)
            item.children.append(caption)
            item.children.append(box)
            contenido.children.append(item)
        }
        port.placeholderText = "22"
        message = TextBlock()
        message.textWrapping = .wrap
        message.margin = Thickness(left: 0, top: 4, right: 0, bottom: 0)
        AutomationProperties.setAutomationId(message, "Asistente_Mensaje")
        contenido.children.append(message)
    }

    private func buildReady() {
        let ajustes = settings()
        contenido.children.append(heading(L("¡Todo listo!")))
        let tema = TemasTerminal.tema(id: ajustes.idTemaActual)?.name ?? ajustes.idTemaActual
        let modo: String
        switch ajustes.modoClaveEquipo {
        case .autoType: modo = L("escribirla sola")
        case .suggest: modo = L("sugerirla")
        case .off: modo = L("nada")
        }
        contenido.children.append(small(L("Tema") + ": \(tema)"))
        contenido.children.append(small(L("Fuente del terminal") + ": \(ajustes.fuente)"))
        contenido.children.append(small(L("Contraseñas") + ": " + (ajustes.contrasenaAutomatica ? L("sesión automática") : L("sesión a mano"))
                                        + " · " + L("equipos") + ": \(modo)"))
        contenido.children.append(small(L("Resaltado") + ": " + (ajustes.resaltado ? L("sí") : L("no"))))
        contenido.children.append(paragraph(L("Todo se ha aplicado ya. Haz clic en tu sesi\u{00F3}n para conectar.")))
    }

    private func create() {
        let trimmed = { (box: TextBox) in box.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trimmed(name).isEmpty, !trimmed(host).isEmpty else {
            message.text = L("Escribe al menos un nombre y un equipo")
            return
        }
        var session = EditableSession.new(group: "General", name: trimmed(name))
        session.host = trimmed(host)
        if !trimmed(user).isEmpty { session.user = trimmed(user) }
        if !trimmed(port).isEmpty { session.port = trimmed(port) }
        message.text = ""
        if onCreateSession?(session) == true { go(.listo) }
    }
}
