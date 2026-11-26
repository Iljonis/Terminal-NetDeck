import Dispatch
import Foundation
import NetDeckCore
import SwiftTerm

/// El búfer se usa en el hilo de WinUI. Las escrituras y el cierre de ConPTY se ordenan en su propia cola.
final class PestanaTerminal: TerminalDelegate {
    let title: String
    let route: ConnectionRoute
    private let id = UUID()
    private let process: ConPTYProcess?
    private let puertoSerie: SerialPort?
    private let salida: AsyncStream<Data>
    private let finSerie: AsyncStream<Data>.Continuation?
    let perfil: TerminalProfile
    var temaPantalla: Theme?
    var paletaPantalla: PaletaTerminal?
    var filtroPantalla: ScreenLook?
    private let input = DispatchQueue(label: "netdeck.windows.terminal")
    private let colaRegistro = DispatchQueue(label: "netdeck.windows.registro")
    private var registro: SessionLogger?
    var archivoRegistro: URL? { registro?.url }
    private var resaltador: Highlighter?
    private var reader: Task<Void, Never>?
    private(set) var revision = 0
    private(set) var closed = false
    private(set) var cursorVisible = true
    // Fila absoluta anclada mientras el usuario lee el historial. nil sigue la salida en vivo.
    private var historialAncla: Int?
    private var historialLimite = 0

    var historialMaximo: Int { terminal.getTopVisibleRow() }
    var historialFila: Int {
        guard !terminal.isCurrentBufferAlternate, let historialAncla else { return historialMaximo }
        return min(historialMaximo, max(0, historialAncla - terminal.buffer.totalLinesTrimmed))
    }
    var viendoHistorial: Bool { historialFila < historialMaximo }

    func irAlHistorial(_ fila: Int) {
        historialAncla = fila >= historialMaximo ? nil : terminal.buffer.totalLinesTrimmed + max(0, fila)
    }

    func aplicarHistorial(_ lineas: Int) {
        guard historialLimite != lineas else { return }
        historialLimite = lineas
        terminal.changeScrollback(lineas)
    }
    private(set) lazy var terminal = Terminal(delegate: self)

    init(route: ConnectionRoute, config: URL?, perfil: TerminalProfile = .init(),
         contrasenaAutomatica: Bool = true, ofrecerGuardar: Bool = true, enviarIdioma: Bool = false) throws {
        title = route.title
        self.route = route
        self.perfil = perfil
        if let linea = route.serial {
            let (salida, fin) = AsyncStream<Data>.makeStream()
            process = nil
            self.salida = salida
            finSerie = fin
            puertoSerie = try SerialPort(linea, queue: DispatchQueue(label: "netdeck.windows.serie"),
                onData: { fin.yield(Data($0)) }, onClose: { motivo in
                    fin.yield(Data("\r\n[NetDeck] \(motivo)\r\n".utf8))
                    fin.finish()
                })
            let aviso = L("\(linea.device) a \(String(linea.speed)) \(linea.frame) · para salir, cierra la pestaña")
            fin.yield(Data("\u{1b}[38;5;51m[NetDeck] \(aviso)\u{1b}[0m\r\n".utf8))
            return
        }
        puertoSerie = nil
        finSerie = nil
        let inherited = ProcessInfo.processInfo.environment
        let demo = inherited["NETDECK_DESKTOP_DEMO"] == "1"
        let isolated = !(inherited["NETDECK_HOME"] ?? "").isEmpty
        let configFile = demo || isolated ? config?.path ?? "NUL" : nil
        var command = route.command(sharing: nil, configFile: configFile)
        if demo, route.isLocal, command.executable.lowercased().hasSuffix("powershell.exe") {
            command.arguments += ["-NoLogo", "-NoProfile", "-NoExit", "-Command", "function prompt { 'PS-DEMO> ' }"]
        }
        // (Ajustes → General → Conexiones: «Enviar el idioma de Windows a los servidores»)
        var environment = TerminalEnvironment.prepare(inherited, forSSH: !route.isLocal,
                                                      sendLocale: enviarIdioma)
        let helper = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .appendingPathComponent("NetDeckAskpass.exe")
        if !demo, (route.transport == .ssh || (route.transport == .telnet && !route.jumps.isEmpty)),
           FileManager.default.fileExists(atPath: helper.path) {
            var askpass = Askpass.environment(executable: helper.path, configPath: config?.path, session: id,
                                              manual: !contrasenaAutomatica, profile: route.sessionName, route: route)
            if !ofrecerGuardar { askpass[Askpass.noOfferSaveFlag] = "1" }
            environment.merge(askpass) { _, value in value }
        }
        let process = try ConPTYProcess(executable: command.executable, arguments: command.arguments,
                                        environment: environment)
        self.process = process
        salida = process.output
    }

    func observe(enqueue: @escaping (@escaping () -> Void) -> Bool, changed: @escaping () -> Void) {
        let output = salida
        reader = Task.detached { [weak self] in
            for await data in output {
                guard !Task.isCancelled, enqueue({ [weak self] in
                    guard let self, !self.closed else { return }
                    if let registro = self.registro {
                        self.colaRegistro.async { registro.feed(Array(data)[...]) }
                    }
                    let anterior = self.terminal.isCurrentBufferAlternate
                    self.terminal.feed(byteArray: self.resaltador?.process(data) ?? Array(data))
                    if self.terminal.isCurrentBufferAlternate != anterior { self.historialAncla = nil }
                    self.revision &+= 1
                    changed()
                }) else { return }
            }
            if !Task.isCancelled {
                _ = enqueue { [weak self] in
                    guard let self, !self.closed else { return }
                    self.close()
                    changed()
                }
            }
        }
    }

    var screen: String {
        (0..<terminal.rows).map {
            lineaVisible($0)?.textoWindows ?? ""
        }.joined(separator: "\n")
    }

    func buscarHistorial(_ consulta: String) -> (lines: [String], total: Int) {
        let texto = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return ([], 0) }
        let primera = terminal.buffer.totalLinesTrimmed
        let fin = primera + terminal.getTopVisibleRow() + terminal.rows
        var lineas: [String] = []
        var total = 0
        // Primero las coincidencias recientes, incluidas las que ya han salido de la pantalla.
        for fila in (primera..<fin).reversed() {
            guard let linea = terminal.getScrollInvariantLine(row: fila)?.textoWindows, linea.localizedCaseInsensitiveContains(texto) else { continue }
            total += 1
            if lineas.count < 200 { lineas.append("\(fila + 1)  \(linea)") }
        }
        return (Array(lineas.reversed()), total)
    }

    /// Pone los colores de un tema en el terminal (paleta ANSI, texto, fondo y cursor). nil: no toca nada.
    func apply(palette: PaletaTerminal) {
        terminal.installPalette(colors: palette.ansi.map(PaletaTerminal.swiftTerm))
        terminal.foregroundColor = PaletaTerminal.swiftTerm(palette.texto)
        terminal.backgroundColor = PaletaTerminal.swiftTerm(palette.fondo)
        terminal.cursorColor = PaletaTerminal.swiftTerm(palette.cursor)
    }

    func resaltar(_ config: HighlightConfig?) {
        guard let config else {
            resaltador = nil
            return
        }
        if let resaltador {
            resaltador.rules = config.rules
            resaltador.palette = config.palette
        } else {
            resaltador = Highlighter(rules: config.rules, palette: config.palette)
        }
    }

    private func lineaVisible(_ fila: Int) -> BufferLine? {
        terminal.getScrollInvariantLine(row: terminal.buffer.totalLinesTrimmed + historialFila + fila)
    }

    func textoSeleccion(desde: (row: Int, col: Int), hasta: (row: Int, col: Int), rectangular: Bool) -> String {
        if rectangular {
            let bloque = BlockSelection(from: desde, to: hasta)
            let pantalla = (0..<terminal.rows).map { row -> (text: String, cellWidths: [Int]) in
                guard let linea = lineaVisible(row) else { return ("", []) }
                return (linea.textoWindows, (0..<terminal.cols).map { Int(linea[$0].width) })
            }
            return bloque.text(of: pantalla)
        }
        let (a, b) = desde <= hasta ? (desde, hasta) : (hasta, desde)
        return terminal.getText(start: Position(col: a.col, row: historialFila + a.row),
                                end: Position(col: b.col, row: historialFila + b.row))
    }

    /// Agrupa celdas contiguas con el mismo estilo de texto.
    func coloredLines(_ palette: PaletaTerminal) -> [[SegmentoColor]] {
        (0..<terminal.rows).map { row in
            guard let linea = lineaVisible(row) else { return [] }
            var segments: [SegmentoColor] = []
            for col in 0..<terminal.cols {
                let cell = linea[col]
                guard cell.width != 0 else { continue }   // (0: la mitad de un ancho doble)
                let letter = cell.getCharacter()
                let character = letter == "\u{0}" ? " " : String(letter)
                let style = cell.attribute.style
                let color = palette.color(cell.attribute.fg)
                let fondo = cell.attribute.bg == .defaultInvertedColor ? nil : palette.color(cell.attribute.bg)
                let inverso = style.contains(.inverse)
                let segment = SegmentoColor(texto: character, color: inverso ? fondo ?? palette.fondo : color,
                                            fondo: inverso ? color ?? palette.texto : fondo,
                                            columnas: Int(cell.width), bold: style.contains(.bold),
                                            italic: style.contains(.italic), underline: style.contains(.underline))
                if let last = segments.last, last.mismoEstilo(segment) {
                    segments[segments.count - 1].texto += character
                    segments[segments.count - 1].columnas += segment.columnas
                } else {
                    segments.append(segment)
                }
            }
            while let last = segments.last, last.fondo == nil {
                let trimmed = String(last.texto.reversed().drop { $0 == " " }.reversed())
                if trimmed.isEmpty {
                    segments.removeLast()
                } else {
                    segments[segments.count - 1].texto = trimmed
                    segments[segments.count - 1].columnas -= last.texto.count - trimmed.count
                    break
                }
            }
            return segments
        }
    }

    func empezarRegistro(en carpeta: URL, encolar: @escaping (@escaping () -> Void) -> Void,
                         alFallar: @escaping (String) -> Void) throws {
        guard registro == nil, !closed else { return }
        let nuevo = try SessionLogger(directory: carpeta, name: route.sessionName ?? title, host: route.target.description)
        registro = nuevo
        nuevo.onFailure = { [weak self, weak nuevo] motivo in
            encolar {
                guard let self, let nuevo, self.registro === nuevo else { return }
                self.pararRegistro()
                alFallar(motivo)
            }
        }
    }

    func pararRegistro() {
        guard let registro else { return }
        self.registro = nil
        colaRegistro.async { registro.close() }
    }

    func write(_ text: String) {
        guard !closed, !text.isEmpty else { return }
        historialAncla = nil
        terminal.sendUserInput(Array(text.utf8)[...])
    }

    /// Pega texto como lo haria un teclado: saltos de linea como Intro y, si el programa lo pide, entre marcas de
    /// «pegado entre corchetes». Se quitan los ESC para que el texto no pueda cerrar la marca antes de tiempo.
    func paste(_ text: String) {
        let plain = text.replacingOccurrences(of: "\u{1b}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        write(terminal.bracketedPasteMode ? "\u{1b}[200~" + plain + "\u{1b}[201~" : plain)
    }

    func showCursor(source: Terminal) { cursorVisible = true }
    func hideCursor(source: Terminal) { cursorVisible = false }

    func send(source: Terminal, data: ArraySlice<UInt8>) {
        guard !closed, !data.isEmpty else { return }
        if let puertoSerie {
            puertoSerie.write(data)
        } else if let process {
            let bytes = Data(data)
            input.async { try? process.write(bytes) }
        }
    }

    func resize(cols: Int, rows: Int) {
        guard !closed, (cols, rows) != (terminal.cols, terminal.rows) else { return }
        terminal.resize(cols: cols, rows: rows)
        if let process { input.async { process.resize(cols: cols, rows: rows) } }
    }

    func enviarBreak() { puertoSerie?.sendBreak() }

    func close() {
        guard !closed else { return }
        closed = true
        pararRegistro()
        reader?.cancel()
        reader = nil
        puertoSerie?.close()
        finSerie?.finish()
        input.async { [process, id] in
            process?.terminate()
            _ = Askpass.takeAttempts(session: id)
        }
    }
}

/// Búfer de SwiftTerm leído en el mismo hilo que recibe la salida de ConPTY.
@MainActor
final class EntradaMacro: TerminalIO {
    let tab: PestanaTerminal
    let promptRule: PromptRule?

    init(tab: PestanaTerminal, promptRule: PromptRule?) {
        self.tab = tab
        self.promptRule = promptRule
    }

    var revision: Int { tab.revision }
    var cursorRow: Int {
        let terminal = tab.terminal
        return terminal.buffer.totalLinesTrimmed + terminal.getTopVisibleRow() + terminal.getCursorLocation().y
    }

    var cursorLine: String { lines(from: cursorRow).last ?? "" }

    func lines(from row: Int) -> [String] {
        let last = cursorRow
        let first = max(row, tab.terminal.buffer.totalLinesTrimmed)
        guard first <= last else { return [] }
        return (first...last).compactMap {
            tab.terminal.getScrollInvariantLine(row: $0)?.textoWindows
        }
    }

    func send(bytes: [UInt8]) {
        tab.write(String(decoding: bytes, as: UTF8.self))
    }
}

private extension BufferLine {
    var textoWindows: String {
        // SwiftTerm puede dejar NUL al redistribuir líneas. WinUI cortaría todo el TextBlock en ese carácter.
        translateToString(trimRight: true, skipNullCellsFollowingWide: true)
            .replacingOccurrences(of: "\0", with: " ")
    }
}
