import Foundation
import NetDeckCore
import WinUI

/// Buscar en TODOS los registros de las sesiones, como `LogSearchSheet` del Mac: una IP, una descripción, una MAC en
/// cualquier formato… y salen las líneas de todos los días y equipos, con el contexto de la elegida.
final class PanelBuscarRegistros {
    let view = ScrollViewer()
    var onClose: (() -> Void)?
    var onAbrir: ((URL) -> Void)?
    var onMostrar: ((URL) -> Void)?
    /// Lleva un bloque al hilo de WinUI.
    var enqueue: (@escaping () -> Void) -> Void = { _ in }

    struct Acierto: Equatable {
        let archivo: URL
        let linea: Int
        let texto: String
    }

    static let maxAciertos = 500
    static let maxLinea = 4096

    private let consulta = TextBox()
    private let estado = TextBlock()
    private let lista = StackPanel()
    private let contexto = TextBlock()
    private let abrir = Button()
    private let mostrar = Button()
    private var carpeta = URL(fileURLWithPath: ".")
    private var aciertos: [Acierto] = []
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

        estado.opacity = 0.7
        estado.fontSize = 12
        estado.textWrapping = .wrap

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
        let cerrar = Button()
        cerrar.content = L("Cerrar")
        AutomationProperties.setAutomationId(cerrar, "BuscarRegistros_Cerrar")
        abrir.click.addHandler { [weak self] _, _ in self?.elegidoActual.map { self?.onAbrir?($0.archivo) } }
        mostrar.click.addHandler { [weak self] _, _ in self?.elegidoActual.map { self?.onMostrar?($0.archivo) } }
        cerrar.click.addHandler { [weak self] _, _ in
            self?.tarea?.cancel()
            self?.onClose?()
        }
        let acciones = Grid()
        for unidad in [GridUnitType.auto, .auto, .star, .auto] {
            let c = ColumnDefinition()
            c.width = GridLength(value: 1, gridUnitType: unidad)
            acciones.columnDefinitions.append(c)
        }
        mostrar.margin = Thickness(left: 8, top: 0, right: 0, bottom: 0)
        Grid.setColumn(mostrar, 1)
        Grid.setColumn(cerrar, 3)
        for b in [abrir, mostrar, cerrar] { acciones.children.append(b) }

        for item in [titulo as FrameworkElement, filaConsulta, estado, columnas, acciones] { form.children.append(item) }
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
        if aciertos.isEmpty { estado.text = L("\(0)\("") líneas en \(AppPaths.tilde(carpeta.path))") }
        actualizarBotones()
        enfocar = true
    }

    private var elegidoActual: Acierto? { elegido.flatMap { aciertos.indices.contains($0) ? aciertos[$0] : nil } }

    private func actualizarBotones() {
        abrir.isEnabled = elegidoActual != nil
        mostrar.isEnabled = elegidoActual != nil
    }

    private func buscar() {
        let q = consulta.text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        tarea?.cancel()
        turno += 1
        let pedido = turno, dir = carpeta
        aciertos = []
        elegido = nil
        lista.children.clear()
        contexto.text = ""
        actualizarBotones()
        estado.text = L("Buscando…")
        tarea = Task.detached { [weak self] in
            let encontrados = Self.grep(q, in: dir)
            self?.enqueue { [weak self] in
                guard let self, self.turno == pedido else { return }
                self.mostrarAciertos(encontrados)
            }
        }
    }

    private func mostrarAciertos(_ encontrados: [Acierto]) {
        aciertos = encontrados
        let mas = encontrados.count >= Self.maxAciertos ? "+" : ""
        estado.text = L("\(encontrados.count)\(mas) líneas en \(AppPaths.tilde(carpeta.path))")
        for (i, a) in encontrados.enumerated() {
            let boton = Button()
            estilo.plano(boton)
            boton.horizontalAlignment = .stretch
            boton.horizontalContentAlignment = .left
            boton.padding = Thickness(left: 8, top: 3, right: 8, bottom: 3)
            let celdas = StackPanel()
            let texto = EstiloMac.letra(a.texto, tamano: 12, color: estilo.texto)
            texto.fontFamily = FontFamily("Cascadia Mono, Consolas")
            texto.textTrimming = .characterEllipsis
            let origen = EstiloMac.letra("\(a.archivo.deletingLastPathComponent().lastPathComponent) · \(a.archivo.lastPathComponent):\(a.linea)",
                                         tamano: 10.5, color: estilo.apagado)
            celdas.children.append(texto)
            celdas.children.append(origen)
            boton.content = celdas
            boton.click.addHandler { [weak self] _, _ in self?.elegir(i) }
            lista.children.append(boton)
        }
        if !encontrados.isEmpty { elegir(0) }
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
            // (fuera del hilo de la interfaz: un registro grande no congela la ventana)
            let lineas = Self.leerLineas(a.archivo)
            let lo = max(0, a.linea - 13), hi = min(lineas.count, a.linea + 12)
            let texto = lo < hi ? (lo..<hi).map { ($0 + 1 == a.linea ? "\u{25B6} " : "  ") + lineas[$0] }.joined(separator: "\n") : ""
            self?.enqueue { [weak self] in
                guard let self, self.turno == pedido, self.elegido == i else { return }
                self.contexto.text = texto
            }
        }
    }

    // MARK: - búsqueda (como grep -n -i -E en los .log)

    static func grep(_ q: String, in dir: URL) -> [Acierto] {
        let patron = macPattern(q) ?? NSRegularExpression.escapedPattern(for: q)
        guard let regex = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { return [] }
        var archivos: [URL] = []
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        while !Task.isCancelled, let f = e?.nextObject() as? URL {
            if f.pathExtension.lowercased() == "log" { archivos.append(f) }
        }
        archivos.sort { $0.path > $1.path }                     // lo más reciente primero
        var out: [Acierto] = []
        for f in archivos {
            if out.count >= maxAciertos || Task.isCancelled { break }
            for (n, linea) in leerLineas(f).enumerated() {
                let corta = linea.utf8.count > maxLinea ? String(decoding: linea.utf8.prefix(maxLinea), as: UTF8.self) : linea
                let rango = NSRange(corta.startIndex..., in: corta)
                guard regex.firstMatch(in: corta, range: rango) != nil else { continue }
                out.append(Acierto(archivo: f, linea: n + 1, texto: corta))
                if out.count >= maxAciertos { break }
            }
        }
        return out
    }

    /// Una MAC en cualquier formato → la expresión que encaja con todos (la misma regla que el Mac).
    static func macPattern(_ q: String) -> String? {
        let hex = q.lowercased().filter { $0.isHexDigit }
        guard hex.count == 12, q.count <= 17, q.allSatisfy({ $0.isHexDigit || ":-. ".contains($0) }) else { return nil }
        let c = Array(hex)
        let pairs = stride(from: 0, to: 12, by: 2).map { String(c[$0...$0 + 1]) }
        let quads = stride(from: 0, to: 12, by: 4).map { String(c[$0..<$0 + 4]) }
        return "(" + [pairs.joined(separator: "[:-]"), quads.joined(separator: "[.-]"), hex].joined(separator: "|") + ")"
    }

    static func leerLineas(_ archivo: URL) -> [String] {
        guard let datos = try? Data(contentsOf: archivo, options: .mappedIfSafe) else { return [] }
        return String(decoding: datos, as: UTF8.self).components(separatedBy: "\n")
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }
}
