import Foundation

/// MultiExec: lo que se teclea en un panel del grupo va a todos (como «synchronize-panes» de tmux), y el pegado
/// seguro puede ir a todos a la vez (cada uno a su ritmo; un Esc los para todos).
@MainActor
public final class MultiExecGroup {
    private struct Member { weak var io: (any TerminalIO)? }

    public var isActive = false
    private var members: [ObjectIdentifier: Member] = [:]
    /// Sacados un momento (p. ej. uno pidiendo contraseña: lo tecleado no debe ir a los demás).
    private var paused: Set<ObjectIdentifier> = []

    public init() {}

    public var terminals: [any TerminalIO] {
        members = members.filter { $0.value.io != nil }
        return members.values.compactMap(\.io)
    }

    public func contains(_ io: TerminalIO) -> Bool { members[ObjectIdentifier(io)] != nil }
    public func join(_ io: TerminalIO) { members[ObjectIdentifier(io)] = Member(io: io) }
    public func leave(_ io: TerminalIO) {
        members[ObjectIdentifier(io)] = nil
        paused.remove(ObjectIdentifier(io))
    }

    public func setPaused(_ io: TerminalIO, _ p: Bool) {
        if p { paused.insert(ObjectIdentifier(io)) } else { paused.remove(ObjectIdentifier(io)) }
    }

    /// Tecla del usuario en `origin`. true = repartida a todos (incluido `origin`); false = la vista la envía sólo ahí.
    public func broadcast(_ bytes: [UInt8], from origin: TerminalIO) -> Bool {
        let id = ObjectIdentifier(origin)
        guard isActive, members[id] != nil, !paused.contains(id) else { return false }
        for io in terminals where !paused.contains(ObjectIdentifier(io)) {
            io.send(bytes: bytes)
        }
        return true
    }

    /// Pegado seguro en todos los paneles activos a la vez.
    public func paste(_ text: String, paster: SafePaster, abort: AbortSwitch) async -> [PasteReport] {
        let targets = terminals.filter { !paused.contains(ObjectIdentifier($0)) }
        let tasks = targets.map { io in Task { @MainActor in await paster.paste(text, into: io, abort: abort) } }
        var out: [PasteReport] = []
        for t in tasks { out.append(await t.value) }
        return out
    }
}
