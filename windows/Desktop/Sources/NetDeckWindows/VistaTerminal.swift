import Foundation
import NetDeckCore
import WinSDK
import struct UWP.FontWeight
import struct WindowsFoundation.Point
import struct WindowsFoundation.Size
import WinUI

/// Una superficie de texto para un terminal, con su propia caché de colores.
final class VistaTerminal {
    let surface = Border()
    let screen = TextBlock()
    let filtro = FiltroTerminal()
    private let fondos = Canvas()
    private let cursorLayer = Canvas()
    private let contenidoTerminal = Grid()
    private let fondoSeleccion = Canvas()
    private var desde: (row: Int, col: Int)?
    private var hasta: (row: Int, col: Int)?
    private var arrastrandoSeleccion = false
    private var seleccionRectangular = false
    var alActivar: (() -> Void)?
    private let caret = Border()
    private let rec = Button()
    private var logVisible: URL?
    var estiloRegistro = EstiloMac(tema: nil) { didSet { vestirRegistro() } }
    var abrirRegistro: ((URL) -> Void)?
    var mostrarRegistro: ((URL) -> Void)?
    var pararRegistro: (() -> Void)?
    private let barraHistorial = Canvas()
    private let indicadorHistorial = Border()
    private var agarreHistorial: Double?
    private var posicionIndicador = 0.0
    private var ruedaPendiente = 0
    private weak var tab: PestanaTerminal?
    var alDesplazar: (() -> Void)?
    var copiarAlSeleccionar = false
    var tieneSeleccion: Bool {
        guard let desde, let hasta else { return false }
        return desde != hasta
    }
    private var cellWidth = 8.25
    private var cellHeight = 19.0
    private var fuenteActual = ""
    private var tamanoActual = 0.0
    private var interlineadoActual = 0.0
    private var colorSeleccion: RGB?
    var columnas: Int { max(2, Int((surface.actualWidth - 22) / cellWidth)) }
    var filas: Int { max(2, Int((surface.actualHeight - 16) / cellHeight)) }
    private var pintado: [[SegmentoColor]]?
    private var plano: String?

    init(id: String) {
        AutomationProperties.setAutomationId(screen, id)
        let layers = Grid()
        fondos.isHitTestVisible = false
        cursorLayer.isHitTestVisible = false
        caret.width = 2
        cursorLayer.children.append(caret)
        contenidoTerminal.margin = Thickness(left: 10, top: 8, right: 12, bottom: 8)
        contenidoTerminal.children.append(fondos)
        fondoSeleccion.isHitTestVisible = false
        contenidoTerminal.children.append(fondoSeleccion)
        contenidoTerminal.children.append(screen)
        contenidoTerminal.children.append(cursorLayer)
        layers.children.append(contenidoTerminal)
        layers.children.append(filtro.view)
        configurarBarra()
        layers.children.append(barraHistorial)
        surface.pointerWheelChanged.addHandler { [weak self] _, args in
            guard let self, let tab, tab.historialMaximo > 0, let args,
                  let punto = try? args.getCurrentPoint(surface) else { return }
            args.handled = true
            ruedaPendiente += Int(punto.properties.mouseWheelDelta)
            let pasos = ruedaPendiente / 120
            guard pasos != 0 else { return }
            ruedaPendiente %= 120
            desplazar(tab.historialFila - pasos * 3)
        }
        configurarSeleccion()
        rec.horizontalAlignment = .right
        rec.verticalAlignment = .top
        rec.margin = Thickness(left: 0, top: 5, right: 20, bottom: 0)
        rec.padding = Thickness(left: 8, top: 1, right: 8, bottom: 1)
        rec.minHeight = 18
        rec.cornerRadius = EstiloMac.radio(12)
        rec.visibility = .collapsed
        layers.children.append(rec)
        surface.child = layers
        surface.isTabStop = true
    }

    func aplicarFuente(_ familia: String, tamano: Double, interlineado: Double) {
        guard (familia, tamano, interlineado) != (fuenteActual, tamanoActual, interlineadoActual) else { return }
        (fuenteActual, tamanoActual, interlineadoActual) = (familia, tamano, interlineado)
        let fuente = FontFamily(familia)
        let medidor = TextBlock()
        medidor.fontFamily = fuente
        medidor.fontSize = tamano
        medidor.text = String(repeating: "M", count: 16)
        try? medidor.measure(Size(width: 1000, height: 200))
        let medida = Double(medidor.desiredSize.width) / 16
        let alto = (tamano * 19 / 15 * interlineado).rounded()
        cellSize(width: medida > 0 ? medida : 8.25 * tamano / 15, height: alto)
        screen.fontFamily = fuente
        screen.fontSize = tamano
        screen.lineHeight = alto
    }

    func aplicarSeleccion(_ color: RGB?) {
        guard color != colorSeleccion else { return }
        colorSeleccion = color
        pintarSeleccion()
    }

    func cellSize(width: Double, height: Double) {
        if width != cellWidth || height != cellHeight {
            invalidate()
            limpiarSeleccion()
        }
        cellWidth = width
        cellHeight = height
    }

    func invalidate() {
        pintado = nil
        plano = nil
    }

    func render(_ tab: PestanaTerminal?, palette: PaletaTerminal?, cursorActive: Bool, brush: (RGB) -> SolidColorBrush) {
        if self.tab !== tab {
            self.tab = tab
            ruedaPendiente = 0
            limpiarSeleccion()
            invalidate()
        }
        actualizarBarra()
        marcarRegistro(tab?.archivoRegistro)
        if cursorActive, let tab, !tab.closed, !tab.viendoHistorial, tab.cursorVisible, let palette {
            let punto = tab.terminal.getCursorLocation()
            Canvas.setLeft(caret, Double(min(punto.x, tab.terminal.cols - 1)) * cellWidth)
            Canvas.setTop(caret, Double(punto.y) * cellHeight)
            caret.height = cellHeight
            caret.background = brush(palette.cursor)
            caret.visibility = .visible
        } else {
            caret.visibility = .collapsed
        }
        guard let tab, let palette else {
            let texto = tab?.screen ?? ""
            guard texto != plano else { return }
            pintado = nil
            plano = texto
            fondos.children.clear()
            screen.text = texto
            return
        }
        let lines = tab.coloredLines(palette)
        guard lines != pintado else { return }
        pintado = lines
        plano = nil
        screen.text = ""
        fondos.children.clear()
        for (index, line) in lines.enumerated() {
            var columna = 0
            for segment in line {
                if let fondo = segment.fondo {
                    let background = Border()
                    background.width = Double(segment.columnas) * cellWidth
                    background.height = cellHeight
                    background.background = brush(fondo)
                    Canvas.setLeft(background, Double(columna) * cellWidth)
                    Canvas.setTop(background, Double(index) * cellHeight)
                    fondos.children.append(background)
                }
                columna += segment.columnas
                let run = Run()
                run.text = segment.texto
                if segment.bold { run.fontWeight = FontWeight(weight: 700) }
                if segment.italic { run.fontStyle = .init(rawValue: 2) }
                if segment.underline { run.textDecorations = .init(rawValue: 1) }
                if let color = segment.color { run.foreground = brush(color) }
                screen.inlines.append(run)
            }
            if index < lines.count - 1 {
                let newline = Run()
                newline.text = "\n"
                screen.inlines.append(newline)
            }
        }
    }
    private func vestirRegistro() {
        indicadorHistorial.background = estiloRegistro.apagado
        rec.content = EstiloMac.letra("● " + L("REC"), tamano: 10, peso: 800, color: estiloRegistro.mal)
        rec.background = estiloRegistro.fondo
        rec.borderBrush = estiloRegistro.mal
        rec.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
    }

    private func marcarRegistro(_ archivo: URL?) {
        guard archivo != logVisible else { return }
        logVisible = archivo
        rec.visibility = archivo == nil ? .collapsed : .visible
        guard let archivo else { rec.flyout = nil; return }
        ToolTipService.setToolTip(rec, L("Grabando en \(AppPaths.tilde(archivo.path))"))
        let opciones = MenuFlyout()
        let acciones: [(String, () -> Void)] = [
            (L("Abrir el registro"), { [weak self] in self?.abrirRegistro?(archivo) }),
            (L("Mostrar en el Explorador"), { [weak self] in self?.mostrarRegistro?(archivo) }),
            (L("Parar el registro"), { [weak self] in self?.pararRegistro?() }),
        ]
        for (titulo, accion) in acciones {
            let opcion = MenuFlyoutItem()
            opcion.text = titulo
            opcion.click.addHandler { _, _ in accion() }
            opciones.items.append(opcion)
        }
        rec.flyout = opciones
    }

    private func configurarBarra() {
        barraHistorial.width = 11
        barraHistorial.horizontalAlignment = .right
        barraHistorial.margin = Thickness(left: 0, top: 3, right: 2, bottom: 3)
        barraHistorial.background = estiloRegistro.transparente
        barraHistorial.visibility = .collapsed
        indicadorHistorial.width = 6
        indicadorHistorial.cornerRadius = EstiloMac.radio(3)
        indicadorHistorial.isHitTestVisible = false
        Canvas.setLeft(indicadorHistorial, 3)
        barraHistorial.children.append(indicadorHistorial)
        AutomationProperties.setName(barraHistorial, L("Historial"))
        barraHistorial.sizeChanged.addHandler { [weak self] _, _ in self?.actualizarBarra() }
        barraHistorial.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args, let punto = try? args.getCurrentPoint(barraHistorial),
                  punto.properties.isLeftButtonPressed else { return }
            args.handled = true
            let y = Double(punto.position.y)
            let alto = indicadorHistorial.height
            agarreHistorial = (posicionIndicador...(posicionIndicador + alto)).contains(y) ? y - posicionIndicador : alto / 2
            _ = try? barraHistorial.capturePointer(args.pointer)
            moverBarra(y)
        }
        barraHistorial.pointerMoved.addHandler { [weak self] _, args in
            guard let self, agarreHistorial != nil, let args,
                  let punto = try? args.getCurrentPoint(barraHistorial) else { return }
            args.handled = true
            moverBarra(Double(punto.position.y))
        }
        barraHistorial.pointerReleased.addHandler { [weak self] _, args in
            guard let self, let args, agarreHistorial != nil else { return }
            agarreHistorial = nil
            args.handled = true
            try? barraHistorial.releasePointerCapture(args.pointer)
        }
        barraHistorial.pointerCaptureLost.addHandler { [weak self] _, _ in self?.agarreHistorial = nil }
    }

    private func actualizarBarra() {
        let maximo = tab?.historialMaximo ?? 0
        barraHistorial.visibility = maximo > 0 ? .visible : .collapsed
        guard let tab, maximo > 0, barraHistorial.actualHeight > 0 else { return }
        let alto = barraHistorial.actualHeight
        let visibles = Double(tab.terminal.rows)
        indicadorHistorial.height = min(alto, max(18, alto * visibles / (visibles + Double(maximo))))
        posicionIndicador = (alto - indicadorHistorial.height) * Double(tab.historialFila) / Double(maximo)
        Canvas.setTop(indicadorHistorial, posicionIndicador)
    }

    private func moverBarra(_ y: Double) {
        let recorrido = barraHistorial.actualHeight - indicadorHistorial.height
        guard let tab, let agarreHistorial, recorrido > 0 else { return }
        let fraccion = min(1, max(0, (y - agarreHistorial) / recorrido))
        desplazar(Int((fraccion * Double(tab.historialMaximo)).rounded()))
    }

    private func desplazar(_ fila: Int) {
        limpiarSeleccion()
        tab?.irAlHistorial(fila)
        alDesplazar?()
    }

    private func configurarSeleccion() {
        surface.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args, let punto = try? args.getCurrentPoint(contenidoTerminal),
                  punto.properties.isLeftButtonPressed else { return }
            alActivar?()
            limpiarSeleccion()
            seleccionRectangular = GetKeyState(Int32(VK_MENU)) < 0
            guard let celda = celda(en: punto.position) else { return }
            desde = celda
            hasta = celda
            arrastrandoSeleccion = true
            _ = try? surface.capturePointer(args.pointer)
            args.handled = true
        }
        surface.pointerMoved.addHandler { [weak self] _, args in
            guard let self, arrastrandoSeleccion, let args,
                  let punto = try? args.getCurrentPoint(contenidoTerminal) else { return }
            hasta = celda(en: punto.position)
            pintarSeleccion()
        }
        surface.pointerReleased.addHandler { [weak self] _, args in
            guard let self, arrastrandoSeleccion, let args else { return }
            arrastrandoSeleccion = false
            try? surface.releasePointerCapture(args.pointer)
            if copiarAlSeleccionar { copiarSeleccion() }
            args.handled = true
        }
        surface.pointerCaptureLost.addHandler { [weak self] _, _ in self?.arrastrandoSeleccion = false }
    }

    private func celda(en punto: Point) -> (row: Int, col: Int)? {
        guard let tab else { return nil }
        let y = Int((Double(punto.y) / cellHeight).rounded(.down))
        let x = Double(punto.x) / cellWidth
        let col = Int(seleccionRectangular ? x.rounded(.down) : x.rounded())
        let limite = tab.terminal.cols - (seleccionRectangular ? 1 : 0)
        return (min(max(0, y), tab.terminal.rows - 1), min(max(0, col), limite))
    }

    private func limpiarSeleccion() {
        desde = nil
        hasta = nil
        arrastrandoSeleccion = false
        fondoSeleccion.children.clear()
    }

    private func pintarSeleccion() {
        fondoSeleccion.children.clear()
        guard tieneSeleccion, let desde, let hasta, let tab else { return }
        let (a, b) = desde <= hasta ? (desde, hasta) : (hasta, desde)
        let bloque = BlockSelection(from: a, to: b)
        let pincel = EstiloMac.pincel(colorSeleccion ?? estiloRegistro.tema.selection, alfa: 0.7)
        for fila in a.row...b.row {
            let inicio = seleccionRectangular ? bloque.cols.lowerBound : (fila == a.row ? a.col : 0)
            let fin = seleccionRectangular ? bloque.cols.upperBound + 1 : (fila == b.row ? b.col : tab.terminal.cols)
            guard fin > inicio else { continue }
            let marca = Border()
            marca.width = Double(fin - inicio) * cellWidth
            marca.height = cellHeight
            marca.background = pincel
            Canvas.setLeft(marca, Double(inicio) * cellWidth)
            Canvas.setTop(marca, Double(fila) * cellHeight)
            fondoSeleccion.children.append(marca)
        }
    }

    @discardableResult
    func copiarSeleccion() -> Bool {
        guard tieneSeleccion, let desde, let hasta, let tab else { return false }
        let texto = tab.textoSeleccion(desde: desde, hasta: hasta, rectangular: seleccionRectangular)
        return Self.escribirPortapapeles(texto)
    }

    @discardableResult
    static func escribirPortapapeles(_ texto: String) -> Bool {
        guard !texto.isEmpty else { return false }
        let datos = Array(texto.utf16) + [0]
        guard OpenClipboard(GetActiveWindow()) else { return false }
        defer { CloseClipboard() }
        guard let memoria = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(datos.count * MemoryLayout<WCHAR>.stride)) else { return false }
        guard let puntero = GlobalLock(memoria) else {
            _ = GlobalFree(memoria)
            return false
        }
        datos.withUnsafeBytes { bytes in
            puntero.copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
        _ = GlobalUnlock(memoria)
        guard EmptyClipboard(), SetClipboardData(UINT(CF_UNICODETEXT), memoria) != nil else {
            _ = GlobalFree(memoria)
            return false
        }
        return true
    }

}
