import AppKit
import NetDeckCore
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
    /// `tearOff`: además se puede sacar de la ventana (una pestaña, a otra ventana o a otra pantalla).
    @ViewBuilder func reorderable<ID: Hashable>(_ id: ID, in row: RowDrag<ID>, order: @escaping () -> [ID],
                                   move: @escaping (ID, ID) -> Void, end: @escaping () -> Void, tap: (() -> Void)? = nil,
                                   tearOff: TearOff? = nil) -> some View {
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
                finished: { moved in if moved { row.ended(end) } else { tap() } }, tearOff: tearOff))
        } else {
            decorated.contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(space))
                    .onChanged { row.changed(id, $0, order: order(), move: move) }
                    .onEnded { _ in row.ended(end) })
        }
    }

    /// La zona donde se arrastra para reordenar: ahí un clic y arrastre no mueve la ventana (la barra de pestañas
    /// está en la de título, y macOS movería la ventana en vez de dejar arrastrar la pestaña).
    /// Con el ratón de verdad no basta con decidirlo al pulsar: el WindowServer arrastra la ventana (y en «Rellenar» la
    /// suelta de la pantalla) antes de que llegue el clic. Por eso deja de ser movible en cuanto el puntero entra.
    func keepsWindowStill(_ model: AppModel, _ key: String) -> some View {
        reportFrame(in: .global) { model.stillZones[key] = $0 }
            .background(StillZoneTracker { model.pointerInStillZone(key, $0) })
            .onDisappear { model.stillZones[key] = nil; model.pointerInStillZone(key, false) }
    }

    /// El marco al aparecer y cada vez que cambia.
    fileprivate func reportFrame(in space: some CoordinateSpaceProtocol, _ report: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: space) } action: { report($0) }
    }
}

/// Avisa cuando el puntero entra o sale de una zona que no mueve la ventana (también con la app en segundo plano).
/// No recibe clics: los deja pasar a lo que haya encima.
private struct StillZoneTracker: NSViewRepresentable {
    let inside: (Bool) -> Void

    func makeNSView(context: Context) -> StillZoneView { StillZoneView() }
    func updateNSView(_ view: StillZoneView, context: Context) { view.inside = inside }
}

private final class StillZoneView: NSView {
    var inside: ((Bool) -> Void)?
    private var entered = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { set(true) }
    override func mouseExited(with event: NSEvent) { set(false) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { set(false) }
        super.viewWillMove(toWindow: newWindow)
    }
    private func set(_ v: Bool) {
        guard v != entered else { return }
        entered = v
        inside?(v)
    }
}

/// Sacar una pestaña de su ventana arrastrándola: mientras va fuera, la sigue un fantasma con su nombre; al soltarla
/// fuera, `drop(punto en pantalla, dónde se cogió desde arriba a la izquierda de la ventana)` (true: se ha movido).
struct TearOff {
    let title: String
    let theme: Theme
    let drop: (CGPoint, CGPoint) -> Bool
}

/// El cuerpo de la pestaña recibe clics y arrastres por AppKit; la X y el menú siguen en SwiftUI.
private struct RowPointer: NSViewRepresentable {
    let frame: () -> CGRect?
    let blocked: (CGPoint) -> Bool
    let changed: (CGPoint, CGPoint) -> Void
    let finished: (Bool) -> Void
    let tearOff: TearOff?

    func makeNSView(context: Context) -> TabPointerView { TabPointerView() }
    func updateNSView(_ view: TabPointerView, context: Context) {
        view.rowFrame = frame; view.blocked = blocked; view.changed = changed; view.finished = finished
        view.tearOff = tearOff
    }
}

private final class TabPointerView: NSView {
    var rowFrame: (() -> CGRect?)?
    var blocked: ((CGPoint) -> Bool)?
    var changed: ((CGPoint, CGPoint) -> Void)?
    var finished: ((Bool) -> Void)?
    var tearOff: TearOff?
    private var down: (window: CGPoint, row: CGPoint)?
    private var moved = false
    /// El puntero ha salido de la ventana (la fila se queda como estaba y le sigue el fantasma).
    private var outside = false
    private let ghost = TearOffGhost()
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// (la pestaña desaparece a mitad de arrastre —se cierra, pasa a otra ventana—: el fantasma no se queda)
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { ghost.hide(); down = nil; outside = false; moved = false }
        super.viewWillMove(toWindow: newWindow)
    }

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
        // (fuera de la ventana —otra pantalla, otra ventana—: el orden no cambia y el fantasma enseña adónde va)
        if let t = tearOff, let w = window {
            let p = w.convertPoint(toScreen: event.locationInWindow)
            outside = !w.frame.contains(p)
            if outside { ghost.show(t.title, theme: t.theme, at: p); return }
            ghost.hide()
        }
        changed?(down.row, CGPoint(x: down.row.x + dx, y: down.row.y - dy))
    }
    override func mouseUp(with event: NSEvent) {
        guard let start = down else { return }
        down = nil
        ghost.hide()
        let wasOutside = outside, wasMoved = moved
        outside = false
        moved = false
        finished?(wasMoved)
        guard wasMoved, wasOutside, let t = tearOff, let w = window else { return }
        let h = w.contentView?.bounds.height ?? w.frame.height
        _ = t.drop(w.convertPoint(toScreen: event.locationInWindow), CGPoint(x: start.window.x, y: h - start.window.y))
    }
}

/// Lo que sigue al puntero mientras una pestaña va fuera de su ventana: su nombre, como una pestaña suelta (también
/// sobre otra pantalla o una ventana a pantalla completa).
@MainActor
private final class TearOffGhost {
    private var panel: NSPanel?

    func show(_ title: String, theme: Theme, at p: CGPoint) {
        let panel = self.panel ?? make(title, theme)
        self.panel = panel
        panel.setFrameOrigin(NSPoint(x: p.x - 18, y: p.y - panel.frame.height + 10))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func make(_ title: String, _ theme: Theme) -> NSPanel {
        let host = NSHostingView(rootView: GhostTab(title: title).environment(\.theme, theme))
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.contentView = host
        return p
    }

    private struct GhostTab: View {
        @Environment(\.theme) private var t
        let title: String

        var body: some View {
            HStack(spacing: 7) {
                Image(systemName: "macwindow.badge.plus").font(.system(size: 11, weight: .semibold))
                Text(title).font(t.ui(12, .semibold)).lineLimit(1)
            }
            .foregroundStyle(SwiftUI.Color(t.onTab))
            .padding(.horizontal, 12)
            .frame(height: 29)
            .background(ChamferShape(radius: t.corner).fill(SwiftUI.Color(t.tab)))
            .opacity(0.92)
            .fixedSize()
        }
    }
}
