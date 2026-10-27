@testable import NetDeckCore

/// Terminal de mentira: cada línea enviada (con Intro) se «teclea» en la fila del cursor (salvo contraseñas) y el
/// «equipo» contesta con `respond`: líneas nuevas, la última es la nueva fila del cursor.
@MainActor
final class FakeTerminal: TerminalIO {
    var screen: [String]
    var revision = 0
    var sent: [String] = []
    var respond: (String) -> [String]

    init(_ screen: [String], respond: @escaping (String) -> [String] = { _ in [] }) {
        self.screen = screen
        self.respond = respond
    }

    func send(bytes: [UInt8]) {
        let text = String(decoding: bytes, as: UTF8.self)
        sent.append(text)
        guard text.hasSuffix("\r") else { return }
        let cmd = String(text.dropLast())
        if !PasswordPrompt.acceptsManual(cursorLine) { screen[screen.count - 1] += cmd }
        screen += respond(cmd)
        revision += 1
    }

    var cursorRow: Int { screen.count - 1 }
    var cursorLine: String { screen.last ?? "" }
    func lines(from row: Int) -> [String] { row <= cursorRow ? Array(screen[max(0, row)...]) : [] }
}
