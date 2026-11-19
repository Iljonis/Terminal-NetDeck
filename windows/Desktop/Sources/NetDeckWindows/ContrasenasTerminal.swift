import Foundation
import NetDeckCore

/// Seguimiento de órdenes ssh/telnet realmente tecleadas, separado del askpass del login inicial.
@MainActor
final class ContrasenasTerminal {
    let io: EntradaMacro
    let automatizacion: PasswordAutomation
    let gate = AutomationGate()
    private var entrada = MacroRecorder(allowScreenFallback: true, soloConexiones: true)
    private var pendiente = false
    private(set) var conectado = false

    init(io: EntradaMacro, ledger: CredentialLedger, modo: PasswordAutomation.Mode) {
        self.io = io
        automatizacion = PasswordAutomation(mode: modo, store: KeychainStore(), ledger: ledger)
        automatizacion.onlySuggestDevices = io.tab.route.manualHop == true
    }

    func tecleado(_ bytes: [UInt8]) {
        if AbortKey.isAbort(bytes) { automatizacion.cancelCommand() }
        guard conectado, automatizacion.mode != .off else { return }
        let omitidos = entrada.skipped
        entrada.feed(bytes, from: io)
        let ordenes = entrada.takeLines()
        for orden in ordenes { automatizacion.beginCommand(orden, after: io.cursorRow) }
        if ordenes.isEmpty, entrada.skipped > omitidos, !SecretPrompt.asks(io.cursorLine),
           !PasswordPrompt.isLoginLine(io.cursorLine) { automatizacion.cancelCommand() }
    }

    func salida() {
        guard !pendiente else { return }
        pendiente = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(65))
            guard let self else { return }
            pendiente = false
            guard !io.tab.closed else { return }
            if !conectado, PromptRule.isPrompt(io.cursorLine, custom: io.promptRule) { conectado = true }
            guard conectado, automatizacion.mode != .off else { return }
            _ = await automatizacion.observe(io, gate: gate)
        }
    }

    func cambiarModo(_ modo: PasswordAutomation.Mode) {
        guard modo != automatizacion.mode else { return }
        entrada.resetLine()
        automatizacion.cancelCommand()
        automatizacion.mode = modo
    }

    func cancelar() {
        gate.abortAll()
        entrada.resetLine()
        automatizacion.cancelCommand()
    }

    func cerrar() {
        gate.abortAll()
        automatizacion.connectionEnded()
    }
}
