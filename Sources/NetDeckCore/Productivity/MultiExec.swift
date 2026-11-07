import Foundation

/// MultiExec: lo que se teclea en un panel del grupo va a todos (como «synchronize-panes» de tmux), y el pegado
/// seguro puede ir a todos a la vez (cada uno a su ritmo; un Esc los para todos).
/// Lo que se teclea en uno que se está autenticando (contraseña, passphrase, OTP…) sólo va a ése, y a los que se están
/// autenticando no les llega lo de los demás. Además, una línea sólo se reparte si empieza en el prompt del equipo
/// (`PromptRule.isPrompt`), y sólo a los que en ese momento están en el suyo: una petición que la app no conoce
/// («Enter secret:», «Key:», «Community:»…) nunca es un prompt, así que lo tecleado ahí se queda en su pestaña.
@MainActor
public final class MultiExecGroup {
    private struct Member { weak var io: (any TerminalIO)? }

    /// El teclado no se mezcla con secuencias reservadas (macros/pegados). Se comprueba en CADA destino y byte.
    public var canReceiveKeystrokes: (any TerminalIO) -> Bool = { _ in true }
    public var isActive = false
    private var members: [ObjectIdentifier: Member] = [:]
    /// Sacados un momento (p. ej. uno pidiendo contraseña: lo tecleado no debe ir a los demás).
    /// ¿Se está autenticando? Por defecto, si la línea del cursor pide un secreto (`SecretPrompt`); la app añade «aún
    /// no ha llegado a su primer prompt» (lo tecleado lo leería el askpass como contraseña).
    public var awaitingAuth: (any TerminalIO) -> Bool = { SecretPrompt.asks($0.cursorLine) }
    /// Donde se está tecleando un secreto: hasta el Intro (o Ctrl+C / Esc), aunque el equipo pinte asteriscos y la
    /// línea ya no parezca una petición.
    private var typingSecret: Set<ObjectIdentifier> = []
    /// La línea que se está repartiendo desde cada pestaña: a quién va (decidido con su primera tecla, en el prompt).
    private var lineTargets: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
    /// De esa línea: el prompt en el que empezó (para quitarlo de la línea del cursor) y lo tecleado (por si el eco del
    /// equipo aún no ha llegado al pulsar Intro; `exact` = sin teclas de edición que no se puedan seguir).
    private var lineStarts: [ObjectIdentifier: (prompt: String, typed: [UInt8], exact: Bool)] = [:]

    public init() {}

    public var terminals: [any TerminalIO] {
        members = members.filter { $0.value.io != nil }
        return members.values.compactMap(\.io)
    }

    public func contains(_ io: TerminalIO) -> Bool { members[ObjectIdentifier(io)] != nil }
    public func join(_ io: TerminalIO) { members[ObjectIdentifier(io)] = Member(io: io) }
    public func leave(_ io: TerminalIO) {
        members[ObjectIdentifier(io)] = nil
        typingSecret.remove(ObjectIdentifier(io))
        lineTargets[ObjectIdentifier(io)] = nil
        lineStarts[ObjectIdentifier(io)] = nil
    }

    /// Le llega lo repartido: está en el grupo, sin pausar y no se está autenticando.
    public func accepts(_ io: TerminalIO) -> Bool {
        let id = ObjectIdentifier(io)
        return members[id] != nil && !typingSecret.contains(id) && !awaitingAuth(io)
    }

    /// Tecla del usuario en `origin`. true = repartida a todos (incluido `origin`); false = la vista la envía sólo ahí.
    public func broadcast(_ bytes: [UInt8], from origin: TerminalIO) -> Bool {
        let id = ObjectIdentifier(origin)
        guard isActive, members[id] != nil else { return false }
        guard canReceiveKeystrokes(origin) else { return true }
        if typingSecret.contains(id) || awaitingAuth(origin) {
            if Self.endsInput(bytes) { typingSecret.remove(id) } else { typingSecret.insert(id) }
            lineTargets[id] = nil
            lineStarts[id] = nil
            return false
        }
        if lineTargets[id] == nil {
            // (primera tecla de la línea: fuera del prompt —una petición que no se conoce, un paginador, un sí/no—
            // se queda en su pestaña; en el prompt, va a los que estén ahora en el suyo, hasta el Intro)
            guard Self.atPrompt(origin) else { return false }
            lineTargets[id] = Set(terminals.filter { accepts($0) && canReceiveKeystrokes($0) && Self.atPrompt($0) }.map(ObjectIdentifier.init))
            lineStarts[id] = (origin.cursorLine, [], true)
        }
        if !Self.endsInput(bytes) { follow(bytes, in: id) }
        // Si un destino pierde bytes, no puede reincorporarse al sufijo de esta misma orden.
        let eligible = Set(terminals.filter { accepts($0) && canReceiveKeystrokes($0) }.map(ObjectIdentifier.init))
        let targets = (lineTargets[id] ?? []).intersection(eligible)
        lineTargets[id] = targets
        for io in terminals where targets.contains(ObjectIdentifier(io)) {
            io.send(bytes: bytes)
        }
        if Self.endsInput(bytes) { lineTargets[id] = nil; lineStarts[id] = nil }
        return true
    }

    /// A cuántas pestañas iría ahora lo que se teclea o pega en `origin` (ella incluida; 1 = sólo a ella).
    public func reach(from origin: TerminalIO) -> Int {
        let id = ObjectIdentifier(origin)
        guard isActive, members[id] != nil, canReceiveKeystrokes(origin), !typingSecret.contains(id), !awaitingAuth(origin) else { return 1 }
        let eligible = terminals.filter { accepts($0) && canReceiveKeystrokes($0) }
        if let t = lineTargets[id] { return max(1, eligible.filter { t.contains(ObjectIdentifier($0)) }.count) }
        guard Self.atPrompt(origin) else { return 1 }
        return max(1, eligible.filter(Self.atPrompt).count)
    }

    /// Este Intro repartiría una orden peligrosa (`PasteRules.dangerous`) a varias pestañas: cuál y a cuántas, para
    /// confirmarlo antes; nil si no. La orden es la línea del cursor de `origin` sin el prompt en el que empezó (con lo
    /// que haya dejado el historial o el tabulador) o, si el eco aún no ha llegado, lo tecleado.
    public func dangerousEnter(_ bytes: [UInt8], from origin: TerminalIO) -> (command: String, tabs: Int)? {
        let id = ObjectIdentifier(origin)
        guard bytes == [13] || bytes == [10] || bytes == [13, 10], lineTargets[id] != nil, let start = lineStarts[id] else { return nil }
        let tabs = reach(from: origin)
        guard tabs > 1 else { return nil }
        let line = origin.cursorLine, prompt = start.prompt.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        var candidates = [!prompt.isEmpty && line.hasPrefix(prompt) ? String(line.dropFirst(prompt.count)) : line]
        if start.exact { candidates.append(String(decoding: start.typed, as: UTF8.self)) }
        for c in candidates {
            if let cmd = DangerousCommands.command(in: c) { return (cmd, tabs) }
        }
        return nil
    }

    /// Lo tecleado en la línea: letras, borrar y Ctrl+U se siguen; flechas, tabulador o un pegado, no (la línea del
    /// cursor manda).
    private func follow(_ bytes: [UInt8], in id: ObjectIdentifier) {
        guard var s = lineStarts[id] else { return }
        for b in bytes {
            switch b {
            case 0x7F, 0x08: if !s.typed.isEmpty { s.typed.removeLast() }
            case 0x15: s.typed.removeAll()
            case 0x20...0x7E, 0x80...: s.typed.append(b)
            default: s.exact = false
            }
        }
        if s.typed.count > 4096 { s.exact = false; s.typed.removeAll() }
        lineStarts[id] = s
    }

    /// En el prompt del equipo (el suyo de la sesión o el genérico; nunca una petición de secreto).
    static func atPrompt(_ io: TerminalIO) -> Bool { PromptRule.isPrompt(io.cursorLine, custom: io.promptRule) }

    /// Intro, Ctrl+C o una Esc sola: se acaba lo que se estaba tecleando.
    static func endsInput(_ bytes: [UInt8]) -> Bool {
        bytes.contains { $0 == 13 || $0 == 10 || $0 == 3 } || bytes == [0x1B]
    }

    /// Pegado seguro en todos los paneles activos a la vez (menos los que se están autenticando).
    public func paste(_ text: String, paster: SafePaster, abort: AbortSwitch) async -> [PasteReport] {
        let targets = terminals.filter(accepts)
        let tasks = targets.map { io in Task { @MainActor in await paster.paste(text, into: io, abort: abort) } }
        var out: [PasteReport] = []
        for t in tasks { out.append(await t.value) }
        return out
    }
}
