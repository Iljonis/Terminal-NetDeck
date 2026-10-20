import Foundation

/// Una sola secuencia de órdenes por terminal. Soltar una reserva sólo libera las pestañas que le pertenecen.
@MainActor public final class AutomationReservation {
    public struct Ticket: Sendable { fileprivate let id: UUID; fileprivate let tabs: Set<UUID> }
    private var owners: [UUID: UUID] = [:]
    public init() {}
    public func contains(_ tab: UUID) -> Bool { owners[tab] != nil }
    public func reserve(_ tabs: Set<UUID>) -> Ticket? {
        guard !tabs.isEmpty, tabs.allSatisfy({ owners[$0] == nil }) else { return nil }
        let ticket = Ticket(id: UUID(), tabs: tabs)
        for tab in tabs { owners[tab] = ticket.id }
        return ticket
    }
    public func release(_ ticket: Ticket) {
        for tab in ticket.tabs where owners[tab] == ticket.id { owners[tab] = nil }
    }
}
