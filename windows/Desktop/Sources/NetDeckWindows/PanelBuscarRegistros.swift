import Foundation
import NetDeckCore
import WinUI

// no verificado en Windows: escrito desde el Mac contra la API de los demás paneles (CheckBox, ComboBox, Run); la
// búsqueda, el contexto, los textos y el resaltado son los de `NetDeckCore.LogSearch`, que sí se prueba en el Mac.

/// Buscar en TODOS los registros de las sesiones, como `LogSearchSheet` del Mac: una IP, una descripción, una MAC en
/// cualquier formato… y salen las líneas de todos los días y equipos, con el contexto de la elegida. Sólo pinta: la
/// lógica (patrón, lectura a trozos, tope, filtros) está en `LogSearch`. De momento sólo lee los `.log`; los
/// `.log.gz` se cuentan como «archivos comprimidos sin leer».
final class PanelBuscarRegistros {
    let view = ScrollViewer()
    var onClose: (() -> Void)?
    var onAbrir: ((URL) -> Void)?
    var onMostrar: ((URL) -> Void)?
    /// Copia un texto al portapapeles (si no se conecta, no salen «Copiar línea» ni «Copiar ruta»).
    var onCopiar: ((String) -> Void)?
    /// Lleva un bloque al hilo de WinUI.
    var enqueue: (@escaping () -> Void) -> Void = { _ in }

    private let consulta = TextBox()
    private let regex = CheckBox()
    private let mayusculas = CheckBox()
    private let palabra = CheckBox()
    private let equipo = ComboBox()
    private let periodo = ComboBox()
    private let estado = TextBlock()
    private let porEquipo = TextBlock()
    private let lista = StackPanel()
    private let contexto = TextBlock()
    private let abrir = Button()
    private let mostrar = Button()
    private let copiarLinea = Button()
    private let copiarRuta = Button()
    private var carpeta = URL(fileURLWithPath: ".")
    private var aciertos: [LogHit] = []
    private var comparador: LogMatcher?
    /// Los equipos del selector (sin «Todos»: el índice 0 del ComboBox).
    private var equipos: [String] = []
    private var rellenando = false
    private var buscado = false
    private var elegido: Int?
    private var turno = 0
    private var tarea: Task<Void, Never>?
    private var enfocar = false
    private var estilo = EstiloMac(tema: nil)

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)
        let titulo = TextBlock()
        titulo.text = L("Buscar en todos los registros…")
        titulo.fontSize = 20

        consulta.placeholderText = L("IP, MAC (cualquier formato), interfaz, texto…")
        consulta.minWidth = 420
        AutomationProperties.setAutomationId(consulta, "BuscarRegistros_Consulta")
        consulta.keyDown.addHandler { [weak self] _, args in
            guard let args, args.key.rawValue == 13 else { return }
            args.handled = true
            self?.buscar()
        }
        let buscarBoton = Button()
        buscarBoton.content = L("Buscar")
        AutomationProperties.setAutomationId(buscarBoton, "BuscarRegistros_Buscar")
        buscarBoton.click.addHandler { [weak self] _, _ in self?.buscar() }
        let filaConsulta = StackPanel()
        filaConsulta.orientation = .horizontal
        filaConsulta.spacing = 8
        filaConsulta.children.append(consulta)
        filaConsulta.children.append(buscarBoton)

        // (las mismas opciones que la hoja del Mac; cambiar una repite la búsqueda ya hecha)
        let filaOpciones = StackPanel()
        filaOpciones.orientation = .horizontal
        filaOpciones.spacing = 12
        for (casilla, texto, ayuda, id) in [
            (regex, L("Regex"), L("Interpretar como expresión regular"), "BuscarRegistros_Regex"),
            (mayusculas, L("Mayúsculas"), L("Distinguir mayúsculas de minúsculas"), "BuscarRegistros_Mayusculas"),
            (palabra, L("Palabra"), L("Sólo palabras completas"), "BuscarRegistros_Palabra")
        ] {
            casilla.content = texto
            ToolTipService.setToolTip(casilla, ayuda)
            AutomationProperties.setAutomationId(casilla, id)
            casilla.checked.addHandler { [weak self] _, _ in self?.repetir() }
            casilla.unchecked.addHandler { [weak self] _, _ in self?.repetir() }
            filaOpciones.children.append(casilla)
        }
        equipo.minWidth = 170
        equipo.items.append(L("Todos los equipos"))
        equipo.selectedIndex = 0
        AutomationProperties.setName(equipo, L("Equipo"))
        AutomationProperties.setAutomationId(equipo, "BuscarRegistros_Equipo")
        equipo.selectionChanged.addHandler { [weak self] _, _ in
            guard let self, !self.rellenando else { return }
            self.repetir()
        }
        for p in LogPeriod.allCases { periodo.items.append(p.title) }
        periodo.selectedIndex = Int32(LogPeriod.allCases.firstIndex(of: .all) ?? 0)
        periodo.minWidth = 150
        AutomationProperties.setName(periodo, L("Periodo"))
        AutomationProperties.setAutomationId(periodo, "BuscarRegistros_Periodo")
        periodo.selectionChanged.addHandler { [weak self] _, _ in self?.repetir() }
        filaOpciones.children.append(equipo)
        filaOpciones.children.append(periodo)

        for texto in [estado, porEquipo] {
            texto.opacity = 0.7
            texto.fontSize = 12
            texto.textWrapping = .wrap
        }

        let columnas = Grid()
        columnas.columnSpacing = 10
        for ancho in [1.2, 1.0] {
            let c = ColumnDefinition()
            c.width = GridLength(value: ancho, gridUnitType: .star)
            columnas.columnDefinitions.append(c)
        }
        let visorLista = ScrollViewer()
        visorLista.height = 380
        visorLista.content = lista
        lista.spacing = 1
        let visorContexto = ScrollViewer()
        visorContexto.height = 380
        visorContexto.horizontalScrollBarVisibility = .auto
        contexto.fontFamily = FontFamily("Cascadia Mono, Consolas")
        contexto.fontSize = 12
        contexto.isTextSelectionEnabled = true
        contexto.verticalAlignment = .top
        contexto.padding = Thickness(left: 8, top: 8, right: 8, bottom: 8)
        visorContexto.content = contexto
        Grid.setColumn(visorContexto, 1)
        columnas.children.append(visorLista)
        columnas.children.append(visorContexto)

        abrir.content = L("Abrir el registro")
        mostrar.content = L("Mostrar en el Explorador")
        copiarLinea.content = L("Copiar línea")
        copiarRuta.content = L("Copiar ruta")
        let cerrar = Button()
        cerrar.content = L("Cerrar")
        AutomationProperties.setAutomationId(cerrar, "BuscarRegistros_Cerrar")
        abrir.click.addHandler { [weak self] _, _ in self?.elegidoActual.map { self?.onAbrir?($0.file) } }
        mostrar.click.addHandler { [weak self] _, _ in self?.elegidoActual.map { self?.onMostrar?($0.file) } }
        copiarLinea.click.addHandler { [weak self] _, _ in self?.elegidoActual.map { self?.onCopiar?($0.text) } }
        copiarRuta.click.addHandler { [weak self] _, _ in self?.elegidoActual.map { self?.onCopiar?($0.file.path) } }
        cerrar.click.addHandler { [weak self] _, _ in
            self?.tarea?.cancel()
            self?.onClose?()
        }
        let izquierda = StackPanel()
        izquierda.orientation = .horizontal
        izquierda.spacing = 8
        for b in [abrir, mostrar, copiarLinea, copiarRuta] { izquierda.children.append(b) }
        let acciones = Grid()
        for unidad in [GridUnitType.star, .auto] {
            let c = ColumnDefinition()
            c.width = GridLength(value: 1, gridUnitType: unidad)
            acciones.columnDefinitions.append(c)
        }
        Grid.setColumn(cerrar, 1)
        acciones.children.append(izquierda)
        acciones.children.append(cerrar)

        for item in [titulo as FrameworkElement, filaConsulta, filaOpciones, estado, porEquipo, columnas, acciones] {
            form.children.append(item)
        }
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
        view.layoutUpdated.addHandler { [weak self] _, _ in
            guard let self, enfocar, view.visibility == .visible, consulta.actualWidth > 0 else { return }
            if (try? consulta.focus(.keyboard)) == true { enfocar = false }
        }
    }

    func show(carpeta: URL, estilo: EstiloMac) {
        self.carpeta = carpeta
        self.estilo = estilo
        if aciertos.isEmpty { estado.text = L("Se busca en \(AppPaths.tilde(carpeta.path))") }
        porEquipo.visibility = .collapsed
        copiarLinea.visibility = onCopiar == nil ? .collapsed : .visible
        copiarRuta.visibility = onCopiar == nil ? .collapsed : .visible
        actualizarBotones()
        cargarEquipos()
        enfocar = true
    }

    private var elegidoActual: LogHit? { elegido.flatMap { aciertos.indices.contains($0) ? aciertos[$0] : nil } }

    private func actualizarBotones() {
        for b in [abrir, mostrar, copiarLinea, copiarRuta] { b.isEnabled = elegidoActual != nil }
    }

    /// Los equipos con registros, para el selector (conservando el elegido, si sigue ahí).
    private func cargarEquipos() {
        let dir = carpeta
        Task.detached { [weak self] in
            let nombres = LogSearch.hosts(in: dir)
            self?.enqueue { [weak self] in self?.rellenarEquipos(nombres) }
        }
    }

    private func rellenarEquipos(_ nombres: [String]) {
        let antes = equipoElegido
        rellenando = true
        equipo.items.clear()
        equipo.items.append(L("Todos los equipos"))
        for n in nombres { equipo.items.append(n) }
        equipos = nombres
        equipo.selectedIndex = Int32((antes.flatMap { nombres.firstIndex(of: $0) }.map { $0 + 1 }) ?? 0)
        rellenando = false
    }

    private var equipoElegido: String? {
        let i = Int(equipo.selectedIndex) - 1
        return equipos.indices.contains(i) ? equipos[i] : nil
    }

    private func consultaActual() -> LogQuery {
        let p = Int(periodo.selectedIndex)
        return LogQuery(text: consulta.text, isRegex: regex.isChecked == true, caseSensitive: mayusculas.isChecked == true,
                        wholeWord: palabra.isChecked == true, host: equipoElegido,
                        period: LogPeriod.allCases.indices.contains(p) ? LogPeriod.allCases[p] : .all)
    }

    /// Cambiar una opción repite la búsqueda ya hecha.
    private func repetir() { if buscado { buscar() } }

    private func buscar() {
        let q = consultaActual()
        guard !q.trimmed.isEmpty else { return }
        buscado = true
        tarea?.cancel()
        turno += 1
        let pedido = turno, dir = carpeta
        aciertos = []
        elegido = nil
        lista.children.clear()
        contexto.inlines.clear()
        porEquipo.visibility = .collapsed
        actualizarBotones()
        estado.text = L("Buscando…")
        tarea = Task.detached { [weak self] in
            let compilado = try? q.matcher()
            let resultado: Result<LogSearchResult, any Error> = Result {
                try LogSearch.search(q, in: dir, isCancelled: { Task.isCancelled })
            }
            self?.enqueue { [weak self] in
                guard let self, self.turno == pedido else { return }
                switch resultado {
                case .success(let r): self.mostrarAciertos(r, comparador: compilado)
                case .failure(let e): self.estado.text = (e as? LogSearchError)?.errorDescription ?? e.localizedDescription
                }
            }
        }
    }

    private func mostrarAciertos(_ r: LogSearchResult, comparador: LogMatcher?) {
        aciertos = r.hits
        self.comparador = comparador
        estado.text = ([r.summary] + r.warnings).joined(separator: " · ")
        porEquipo.text = r.hostSummary() ?? ""
        porEquipo.visibility = r.hostSummary() == nil ? .collapsed : .visible
        for (i, a) in r.hits.enumerated() {
            let boton = Button()
            estilo.plano(boton)
            boton.horizontalAlignment = .stretch
            boton.horizontalContentAlignment = .left
            boton.padding = Thickness(left: 8, top: 3, right: 8, bottom: 3)
            let celdas = StackPanel()
            let texto = EstiloMac.letra("", tamano: 12, color: estilo.texto)
            texto.fontFamily = FontFamily("Cascadia Mono, Consolas")
            let vista = a.preview()
            anadir(LogSegment.split(vista.text, ranges: vista.ranges), a: texto)
            let origen = EstiloMac.letra("\(a.file.deletingLastPathComponent().lastPathComponent) · \(a.file.lastPathComponent):\(a.line)",
                                         tamano: 10.5, color: estilo.apagado)
            celdas.children.append(texto)
            celdas.children.append(origen)
            boton.content = celdas
            boton.click.addHandler { [weak self] _, _ in self?.elegir(i) }
            lista.children.append(boton)
        }
        if !r.hits.isEmpty { elegir(0) }
    }

    /// Los trozos de una línea como `Run`: los que aciertan, en el color de acento y en negrita.
    private func anadir(_ trozos: [LogSegment], a texto: TextBlock) {
        for t in trozos {
            let run = Run()
            run.text = t.text
            if t.isMatch {
                run.foreground = estilo.acento(alfa: 1)
                run.fontWeight = FontWeight(weight: 700)
            }
            texto.inlines.append(run)
        }
    }

    private func elegir(_ i: Int) {
        guard aciertos.indices.contains(i) else { return }
        elegido = i
        for (n, hijo) in lista.children.enumerated() {
            (hijo as? Button)?.background = n == i ? estilo.acento(alfa: 0.18) : estilo.transparente
        }
        actualizarBotones()
        let a = aciertos[i], pedido = turno
        Task.detached { [weak self] in
            // (fuera del hilo de la interfaz y por trozos: un registro grande no congela la ventana)
            let lineas = LogSearch.context(file: a.file, line: a.line, isCancelled: { Task.isCancelled })
            self?.enqueue { [weak self] in
                guard let self, self.turno == pedido, self.elegido == i else { return }
                self.mostrarContexto(lineas)
            }
        }
    }

    private func mostrarContexto(_ lineas: [LogContextLine]) {
        contexto.inlines.clear()
        for (n, l) in lineas.enumerated() {
            let marca = Run()
            marca.text = (l.isHit ? "\u{25B6} " : "  ")
            contexto.inlines.append(marca)
            anadir(LogSegment.split(l.text, ranges: comparador?.ranges(in: l.text) ?? []), a: contexto)
            if n < lineas.count - 1 {
                let salto = Run()
                salto.text = "\n"
                contexto.inlines.append(salto)
            }
        }
    }
}
