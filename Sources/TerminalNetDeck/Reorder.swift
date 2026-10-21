import AppKit
import SwiftUI

/// Reordenar una fila arrastrando (pestañas, botones): un gesto propio de la app, sin el arrastre del sistema (no
/// sale de la ventana, no lleva texto a la terminal, no lo puede soltar otra app). El elemento sigue al ratón y, al
/// pasar la mitad de otro, ocupa su sitio en vivo y con animación; al soltar se guarda (`end`).
@MainActor @Observable
final class RowDrag<ID: Hashable> {
    /// El espacio de coordenadas de la fila (el `HStack` lleva `.coordinateSpace(.named(space))`).
    let space = UUID()
    @ObservationIgnored var frames: [ID: CGRect] = [:]
    /// Dónde no empieza el arrastre de cada uno (la ✕ de una pestaña: pulsarla y mover no la cambia de sitio).
    @ObservationIgnored var blocked: [ID: CGRect] = [:]
    private(set) var dragging: ID?
    private(set) var offset: CGFloat = 0
    @ObservationIgnored private var grab: CGFloat = 0

    /// `order`: la fila tal como está ahora; `move(id, target)`: `id` ocupa el sitio de `target`.
    func changed(_ id: ID, _ v: DragGesture.Value, order: [ID], move: (ID, ID) -> Void) {
        changed(id, start: v.startLocation, location: v.location, order: order, move: move)
    }

    func changed(_ id: ID, start: CGPoint, location: CGPoint, order: [ID], move: (ID, ID) -> Void) {
        if SnapshotDrags.enabled { SnapshotDrags.gestureEvents += 1 }      // (pruebas de la barra)
        guard let f = frames[id] else { return }
        if dragging == nil, blocked[id]?.contains(start) == true { return }
        if dragging == nil {
            frames = frames.filter { order.contains($0.key) }      // (los de vistas que ya no están)
            dragging = id
            grab = start.x - f.midX
        }
        guard dragging == id, let i = order.firstIndex(of: id) else { return }
        let x = location.x
        // (se decide con el orden de verdad, no con los marcos: tras mover, los marcos llegan un instante después
        // y así no rebota entre dos)
        let target = order.enumerated().first { j, o in
            guard o != id, let r = frames[o], r.minX <= x, x <= r.maxX else { return false }
            return j > i ? x > r.midX : x < r.midX
        }?.element
        if let target { withAnimation(.easeInOut(duration: 0.15)) { move(id, target) } }
        offset = x - grab - (frames[id]?.midX ?? f.midX)
    }

    func ended(_ end: () -> Void) {
        guard dragging != nil else { return }
        withAnimation(.easeOut(duration: 0.15)) { dragging = nil; offset = 0 }
        end()
    }
}

extension View {
    /// Un elemento de una fila que se reordena arrastrando (ver `RowDrag`). Un clic sin mover sigue siendo un clic.
    @ViewBuilder func reorderable<ID: Hashable>(_ id: ID, in row: RowDrag<ID>, order: @escaping () -> [ID],
                                   move: @escaping (ID, ID) -> Void, end: @escaping () -> Void, tap: (() -> Void)? = nil) -> some View {
        let space = row.space
        let dragging = row.dragging == id
        let decorated = offset(x: dragging ? row.offset : 0)
            // (el marco, el de su sitio en la fila: sin el desplazamiento del arrastre, que si no se realimenta)
            .reportFrame(in: .named(space)) { row.frames[id] = $0 }
            .onDisappear { row.frames[id] = nil }
            .zIndex(dragging ? 1 : 0)
            .shadow(color: .black.opacity(dragging ? 0.35 : 0), radius: 6, y: 2)

        if let tap {
            decorated.overlay(RowPointer(frame: { row.frames[id] }, blocked: { row.blocked[id]?.contains($0) == true },
                changed: { row.changed(id, start: $0, location: $1, order: order(), move: move) },
                finished: { moved in if moved { row.ended(end) } else { tap() } }))
        } else {
            decorated.contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(space))
                    .onChanged { row.changed(id, $0, order: order(), move: move) }
                    .onEnded { _ in row.ended(end) })
        }
    }

    /// La zona donde se arrastra para reordenar: ahí un clic y arrastre no mueve la ventana (la barra de pestañas
    /// está en la de título, y macOS movería la ventana en vez de dejar arrastrar la pestaña).
    func keepsWindowStill(_ model: AppModel, _ key: String) -> some View {
        reportFrame(in: .global) { model.stillZones[key] = $0 }
            .onDisappear { model.stillZones[key] = nil }
    }

    /// El marco al aparecer y cada vez que cambia.
    fileprivate func reportFrame(in space: some CoordinateSpaceProtocol, _ report: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: space) } action: { report($0) }
    }
}

/// El cuerpo de la pestaña recibe clics y arrastres por AppKit; la X y el menú siguen en SwiftUI.
private struct RowPointer: NSViewRepresentable {
    let frame: () -> CGRect?
    let blocked: (CGPoint) -> Bool
    let changed: (CGPoint, CGPoint) -> Void
    let finished: (Bool) -> Void

    func makeNSView(context: Context) -> TabPointerView { TabPointerView() }
    func updateNSView(_ view: TabPointerView, context: Context) {
        view.rowFrame = frame; view.blocked = blocked; view.changed = changed; view.finished = finished
    }
}

private final class TabPointerView: NSView {
    var rowFrame: (() -> CGRect?)?
    var blocked: ((CGPoint) -> Bool)?
    var changed: ((CGPoint, CGPoint) -> Void)?
    var finished: ((Bool) -> Void)?
    private var down: (window: CGPoint, row: CGPoint)?
    private var moved = false
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown, !event.modifierFlags.contains(.control),
              super.hitTest(point) != nil, let frame = rowFrame?() else { return nil }
        let local = convert(point, from: superview)
        guard blocked?(CGPoint(x: frame.minX + local.x, y: frame.minY + local.y)) != true else { return nil }
        return self
    }
    override func mouseDown(with event: NSEvent) {
        guard let frame = rowFrame?() else { return }
        let local = convert(event.locationInWindow, from: nil)
        down = (event.locationInWindow, CGPoint(x: frame.minX + local.x, y: frame.minY + local.y))
        moved = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let dx = event.locationInWindow.x - down.window.x, dy = event.locationInWindow.y - down.window.y
        guard moved || hypot(dx, dy) >= 4 else { return }
        moved = true
        changed?(down.row, CGPoint(x: down.row.x + dx, y: down.row.y - dy))
    }
    override func mouseUp(with event: NSEvent) {
        guard down != nil else { return }
        down = nil
        finished?(moved)
        moved = false
    }
}
