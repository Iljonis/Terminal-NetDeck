import Dispatch
import Foundation
import NetDeckCore
import SwiftTerm

/// El búfer se usa en el hilo de WinUI. Las escrituras y el cierre de ConPTY se ordenan en su propia cola.
final class PestanaTerminal: TerminalDelegate {
    let title: String
    private let process: ConPTYProcess
    private let input = DispatchQueue(label: "netdeck.windows.terminal")
    private var reader: Task<Void, Never>?
    private(set) var closed = false
    private(set) lazy var terminal = Terminal(delegate: self)

    init(route: ConnectionRoute) throws {
        title = route.title
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

    func write(_ text: String) {
        guard !closed, !text.isEmpty else { return }
        terminal.sendUserInput(Array(text.utf8)[...])
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
