import Dispatch
import Foundation
import NetDeckCore
import SwiftTerm

/// El búfer se usa en el hilo de WinUI. Las escrituras y el cierre de ConPTY se ordenan en su propia cola.
final class PestanaTerminal: TerminalDelegate {
    let title: String
    let route: ConnectionRoute
    private let process: ConPTYProcess
    private let input = DispatchQueue(label: "netdeck.windows.terminal")
    private var reader: Task<Void, Never>?
    private(set) var closed = false
    private(set) lazy var terminal = Terminal(delegate: self)

    init(route: ConnectionRoute) throws {
        title = route.title
        self.route = route
        let demo = ProcessInfo.processInfo.environment["NETDECK_DESKTOP_DEMO"] == "1"
        let configFile = demo && !route.isLocal ? "NUL" : nil
        var command = route.command(sharing: nil, configFile: configFile)
        if demo, route.isLocal, command.executable.lowercased().hasSuffix("powershell.exe") {
            command.arguments += ["-NoLogo", "-NoProfile"]
        }
        let environment = TerminalEnvironment.prepare(ProcessInfo.processInfo.environment,
                                                      forSSH: !route.isLocal, sendLocale: false)
        process = try ConPTYProcess(executable: command.executable, arguments: command.arguments,
                                    environment: environment)
    }

    func observe(enqueue: @escaping (@escaping () -> Void) -> Bool, changed: @escaping () -> Void) {
        let output = process.output
        reader = Task.detached { [weak self] in
            for await data in output {
                guard !Task.isCancelled, enqueue({ [weak self] in
                    guard let self, !self.closed else { return }
                    self.terminal.feed(byteArray: Array(data))
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
            terminal.getLine(row: $0)?.translateToString(trimRight: true,
                                                        skipNullCellsFollowingWide: true) ?? ""
        }.joined(separator: "\n")
    }

    /// Pone los colores de un tema en el terminal (paleta ANSI, texto, fondo y cursor). nil: no toca nada.
    func apply(palette: PaletaTerminal?) {
        guard let palette else { return }
        terminal.installPalette(colors: palette.ansi.map(PaletaTerminal.swiftTerm))
        terminal.foregroundColor = PaletaTerminal.swiftTerm(palette.texto)
        terminal.backgroundColor = PaletaTerminal.swiftTerm(palette.fondo)
        terminal.cursorColor = PaletaTerminal.swiftTerm(palette.cursor)
    }

    /// La pantalla por lineas y trozos del mismo color de texto (sin los espacios del final de cada linea). Los trozos de color por
    /// defecto llevan color nil. Solo cuenta el color del TEXTO: ni el fondo de cada celda ni negrita, subrayado o inversa.
    func coloredLines(_ palette: PaletaTerminal) -> [[SegmentoColor]] {
        (0..<terminal.rows).map { row in
            var segments: [SegmentoColor] = []
            for col in 0..<terminal.cols {
                guard let cell = terminal.getCharData(col: col, row: row), cell.width != 0 else { continue }   // (0: la mitad de un ancho doble)
                let letter = cell.getCharacter()
                let character = letter == "\u{0}" ? " " : String(letter)
                let color = palette.color(cell.attribute.fg)
                if let last = segments.last, last.color == color {
                    segments[segments.count - 1].texto += character
                } else {
                    segments.append(SegmentoColor(texto: character, color: color))
                }
            }
            while let last = segments.last {
                let trimmed = String(last.texto.reversed().drop { $0 == " " }.reversed())
                if trimmed.isEmpty { segments.removeLast() } else { segments[segments.count - 1].texto = trimmed; break }
            }
            return segments
        }
    }

    func write(_ text: String) {
        guard !closed, !text.isEmpty else { return }
        terminal.sendUserInput(Array(text.utf8)[...])
    }

    /// Pega texto como lo haria un teclado: saltos de linea como Intro y, si el programa lo pide, entre marcas de
    /// «pegado entre corchetes». Se quitan los ESC para que el texto no pueda cerrar la marca antes de tiempo.
    func paste(_ text: String) {
        let plain = text.replacingOccurrences(of: "\u{1b}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        write(terminal.bracketedPasteMode ? "\u{1b}[200~" + plain + "\u{1b}[201~" : plain)
    }

    func send(source: Terminal, data: ArraySlice<UInt8>) {
        guard !closed, !data.isEmpty else { return }
        let bytes = Data(data)
        input.async { [process] in try? process.write(bytes) }
    }

    func resize(cols: Int, rows: Int) {
        guard !closed, (cols, rows) != (terminal.cols, terminal.rows) else { return }
        terminal.resize(cols: cols, rows: rows)
        input.async { [process] in process.resize(cols: cols, rows: rows) }
    }

    func close() {
        guard !closed else { return }
        closed = true
        reader?.cancel()
        reader = nil
        input.async { [process] in process.terminate() }
    }
}
