import Foundation

/// Secuencia de teclas automática (botones login/pass de NetDeck): cada paso comprueba Esc justo antes de enviar.
public struct InputScript: Sendable {
    public enum Step: Sendable {
        case text(String)
        case line(String)
        /// La contraseña del Llavero + Intro (nunca se registra ni se muestra).
        case secret(CredentialRef)
        /// Espera a que la línea del cursor encaje (p. ej. «Password:»).
        case waitFor(Pattern, timeout: Duration)
        case pause(Duration)
    }

    public enum Outcome: Equatable, Sendable {
        case done
        case aborted
        case timedOut(step: Int)
        case missingCredential(CredentialRef)
        /// El equipo ya no pide contraseña (la escribiste tú, cambió la pantalla…): no se envía.
        case promptGone(step: Int)
    }

    public var steps: [Step]
    public var poll: Duration = .milliseconds(100)

    public init(_ steps: [Step]) {
        self.steps = steps
    }

    /// Botón «login»: usuario en «Username:/login:» y su contraseña cuando la pidan. (Si ya piden la contraseña, la
    /// app la escribe con `PasswordAutomation.typeManually`, tras `PasswordPrompt.otherUser`.)
    public static func login(user: String, credential: CredentialRef, timeout: Duration = .seconds(15)) -> InputScript {
        InputScript([
            .waitFor(Pattern(#"(?:user\s*name|login|user|usuario)\s*:\s*$"#), timeout: timeout),
            .line(user),
            .waitFor(PasswordPrompt.asks, timeout: timeout),
            .secret(credential),
        ])
    }

    @MainActor
    public func run(on io: TerminalIO, store: CredentialStore, abort: AbortSwitch) async -> Outcome {
        do {
            for (i, step) in steps.enumerated() {
                try abort.check()
                switch step {
                case .text(let t):
                    io.send(t)
                case .line(let t):
                    io.sendLine(t)
                case .secret(let ref):
                    guard let pw = await store.passwordInBackground(for: ref) else { return .missingCredential(ref) }
                    // (justo antes: ni Esc ni una pantalla que ya no pide contraseña)
                    try abort.check()
                    guard PasswordPrompt.acceptsManual(io.cursorLine) else { return .promptGone(step: i) }
                    io.sendLine(pw)
                case .waitFor(let p, let timeout):
                    let hit = try await Poll.until(every: poll, timeout: timeout, abort: abort) {
                        p.matches(io.cursorLine.trimmed) ? true : nil
                    }
                    if hit == nil { return .timedOut(step: i) }
                case .pause(let d):
                    try await Task.sleep(for: d)
                }
            }
            return .done
        } catch {
            return .aborted                             // Esc / Ctrl+C (o la tarea cancelada)
        }
    }
}
