import AppKit
import NetDeckCore
import SwiftUI

/// Desarrollo (con NETDECK_SNAPSHOT y NETDECK_SNAPSHOT_DRAGS=/ruta.txt): arrastres y clics de mentira en la barra de
/// pestañas, por la cola de eventos como los de verdad (pasan por el monitor de `AppModel.attach`, la ventana y los
/// gestos de SwiftUI). Apunta en la ruta, caso a caso, si la ventana se podía mover al pulsar, si se ha movido, el
/// orden de las pestañas y cuántas quedan; y sale de la app. El ratón de verdad no se mueve.
@MainActor
enum SnapshotDrags {
    static let enabled = ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] != nil
        && ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT_DRAGS"] != nil
    /// Marcos en la ventana (de arriba a la izquierda, como `.global`) de lo que se prueba.
    static var frames: [String: CGRect] = [:]

    /// Veces que ha llegado un cambio al gesto de reordenar (`RowDrag.changed`).
    static var gestureEvents = 0
    private static var lines: [String] = []
    private static var failures = 0
    private static var moves = 0
    private static var checks = 0

    static func run(_ model: AppModel, report path: String) async {
        try? await Task.sleep(for: .seconds(2))
        guard let w = model.window, !model.tabs.isEmpty else {
            check(false, "sin ventana o pestañas: no se ejecutó la prueba")
            finish(path)
            return
        }
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        let watch = NotificationCenter.default.addObserver(forName: NSWindow.willMoveNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { moves += 1 }
        }
        try? await Task.sleep(for: .milliseconds(500))
        say("app activa=\(NSApp.isActive) · ventana \(w.frame) · escala \(w.backingScaleFactor) · pestañas \(model.tabs.count)")
        // (qué vista encuentra la ventana bajo el ratón: en una pestaña, en la barra de título, y en un botón)
        if let root = w.contentView?.superview {
            for key in ["tab:\(model.tabs[0].id)", "boton:0"] {
                guard let f = frames[key] else { continue }
                let p = root.convert(NSPoint(x: f.midX, y: (w.contentView?.bounds.height ?? 0) - f.midY), from: w.contentView)
                let v = root.hitTest(p)
                say("· vista bajo el ratón en \(key.prefix(5)): \(v.map { String(describing: type(of: $0)) } ?? "ninguna")"
                    + " · mueve la ventana=\(v?.mouseDownCanMoveWindow ?? false)")
            }
        }
        // (control: la barra de botones, fuera de la barra de título, con el mismo gesto de reordenar)
        if let b = frames["boton:0"] {
            let g = gestureEvents
            await drag(w, from: CGPoint(x: b.midX, y: b.midY), dx: 40)
            say("· control: arrastre en la barra de botones → \(gestureEvents - g) cambios del gesto")
        }
        await suite(model, w, label: "pantalla \(Int(w.backingScaleFactor))x")
        // (la misma tanda en una pantalla con la otra escala, si hay)
        if let other = NSScreen.screens.first(where: { $0.backingScaleFactor != w.backingScaleFactor }) {
            let f = other.visibleFrame
            w.setFrame(NSRect(x: f.minX + 20, y: f.maxY - min(f.height, 860) - 20, width: min(f.width - 40, 1512),
                              height: min(f.height - 40, 860)), display: true)
            try? await Task.sleep(for: .milliseconds(800))
            say("— otra pantalla: ventana \(w.frame) · escala \(w.backingScaleFactor)")
            await suite(model, w, label: "pantalla \(Int(w.backingScaleFactor))x")
        }
        w.toggleFullScreen(nil)
        for _ in 0..<50 {
            if w.styleMask.contains(.fullScreen) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .seconds(1))
        check(w.styleMask.contains(.fullScreen), "pantalla completa: activada")
        await suite(model, w, label: "pantalla completa")
        w.toggleFullScreen(nil)
        for _ in 0..<50 {
            if !w.styleMask.contains(.fullScreen) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .seconds(1))
        check(!w.styleMask.contains(.fullScreen), "pantalla completa: vuelta a ventana")
        // (muchas pestañas: estrechas y con la tira desplazada hasta la última)
        let wide = model.tabs.count
        for i in 0..<24 { model.open(ConnectionRoute(title: "sw-\(i)", target: Endpoint(user: "tu.usuario", host: "192.0.2.\(100 + i)"))) }
        try? await Task.sleep(for: .milliseconds(900))
        say("— \(model.tabs.count) pestañas (antes \(wide)): estrechas y con desplazamiento")
        await suite(model, w, label: "estrechas")
        NotificationCenter.default.removeObserver(watch)
        check(checks >= 120, "cobertura: \(checks) comprobaciones (mínimo 120)")
        finish(path)
    }

    private static func finish(_ path: String) {
        say("RESULTADO: comprobaciones=\(checks) fallos=\(failures)")
        do {
            try lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            // El proceso de QA debe fallar también si no puede entregar el informe.
            fputs("No se puede guardar el informe de pestañas\n", stderr)
            exit(1)
        }
        NSApp.terminate(nil)
    }

    private static func say(_ s: String) { lines.append(s) }

    private static func check(_ ok: Bool, _ s: String) {
        checks += 1
        if !ok { failures += 1 }
        say((ok ? "✓ " : "✗ ") + s)
    }

    /// Arrastres desde cada parte de una pestaña inactiva y de la activa, el hueco libre de la barra y la ✕.
    private static func suite(_ model: AppModel, _ w: NSWindow, label: String) async {
        while model.tabs.count < 6 {                                       // (las que han cerrado las ✕ de antes)
            model.open(ConnectionRoute(title: "lab-\(model.tabs.count)", target: Endpoint(user: "tu.usuario", host: "198.51.100.\(model.tabs.count + 1)")))
        }
        try? await Task.sleep(for: .milliseconds(600))
        // la activa, la penúltima; la inactiva, la de su izquierda
        let active = model.tabs[model.tabs.count - 2]
        model.show(active)
        try? await Task.sleep(for: .milliseconds(600))
        let controls = frames["controles"], create = frames["crear"]
        check(controls.map { abs($0.maxX - ((w.contentView?.bounds.width ?? 0) - 10)) <= 1 } == true,
              "\(label) · controles anclados a la derecha")
        for (name, s) in [("activa", active), ("inactiva", model.tabs[model.tabs.count - 3])] {
            guard let f = frames["tab:\(s.id)"] else { check(false, "\(label) \(name): sin marco"); continue }
            say("· \(label) \(name): marco \(f) · barra \(model.stillZones["pestañas"] ?? .zero)")
            let mid = f.midY
            let points: [(String, CGPoint)] = [
                ("borde izquierdo", CGPoint(x: f.minX + 1, y: mid)),
                ("punto de estado", CGPoint(x: f.minX + (f.width < 130 ? 12 : 15), y: mid)),
                ("texto", CGPoint(x: f.minX + 40, y: mid)),
                ("hueco interior", CGPoint(x: f.maxX - (name == "activa" ? 40 : 20), y: mid)),
                ("borde derecho", CGPoint(x: f.maxX - 1, y: mid)),
                ("borde de arriba", CGPoint(x: f.midX, y: f.minY + 1)),
                ("borde de abajo", CGPoint(x: f.midX, y: f.maxY - 1)),
                ("esquina", CGPoint(x: f.minX + 1, y: f.minY + 1)),
            ]
            for (part, p) in points {
                for dir in [-1, 1] {
                    // (hasta pasar el centro de la de al lado: el sitio cambia al pasar su mitad)
                    guard let i = model.tabs.firstIndex(where: { $0 === s }), model.tabs.indices.contains(i + dir),
                          let n = frames["tab:\(model.tabs[i + dir].id)"] else { check(false, "\(label): sin pestaña vecina o marco"); continue }
                    await reorder(model, w, s, from: p, dx: n.midX + CGFloat(dir) * 15 - p.x,
                                  what: "\(label) · \(name) · \(part) · \(dir < 0 ? "←" : "→")")
                }
            }
        }
        // un clic (sin mover) en otra pestaña la elige, también en su borde; la ventana no se mueve
        for (part, dx) in [("texto", 40.0), ("borde derecho", -1.0)] {
            let other = model.tabs[model.tabs.count - 3]
            guard let f = frames["tab:\(other.id)"] else { check(false, "\(label): sin marco para el clic"); continue }
            await click(w, CGPoint(x: dx > 0 ? f.minX + dx : f.maxX + dx, y: f.midY))
            check(model.selection == other.id, "\(label) · clic en otra pestaña (\(part)): elegida=\(model.selection == other.id)")
            model.show(active)
            try? await Task.sleep(for: .milliseconds(300))
        }
        // el hueco libre de la barra: la ventana se puede mover (no se reordena nada)
        if let g = frames["hueco"], g.width > 20 {
            let order = model.tabs.map(\.id)
            let r = await drag(w, from: CGPoint(x: g.midX, y: g.midY), dx: 60)
            check(r.movable && order == model.tabs.map(\.id),
                  "\(label) · hueco libre de la barra: ventana movible=\(r.movable), orden igual=\(order == model.tabs.map(\.id))")
        }
        // la ✕: pulsar y arrastrar no reordena ni cierra; un clic en cualquier punto de sus 24×24 cierra
        if let x = frames["x:\(active.id)"] {
            let order = model.tabs.map(\.id), n = model.tabs.count
            let r = await drag(w, from: CGPoint(x: x.midX, y: x.midY), dx: 70)
            check(order == model.tabs.map(\.id) && n == model.tabs.count && !r.windowMoved,
                  "\(label) · arrastrar desde la ✕: orden igual=\(order == model.tabs.map(\.id)), cerradas=\(n - model.tabs.count), ventana movida=\(r.windowMoved)")
            say("· \(label) · ✕ \(Int(x.width))×\(Int(x.height)) en \(x)")
            for (part, dx, dy) in [("centro", 0.0, 0.0), ("esquina arriba izq.", -10.5, -10.5), ("esquina abajo dcha.", 10.5, 10.5),
                                   ("izquierda", -11.0, 0.0), ("abajo", 0.0, 11.0)] {
                guard let s = model.current, let xf = frames["x:\(s.id)"] else { check(false, "\(label): sin ✕ en la activa"); break }
                let n = model.tabs.count
                await click(w, CGPoint(x: xf.midX + dx, y: xf.midY + dy))
                check(model.tabs.count == n - 1 && !model.tabs.contains { $0 === s },
                      "\(label) · clic en la ✕ (\(part)): \(n) → \(model.tabs.count) pestañas")
                try? await Task.sleep(for: .milliseconds(400))
            }
        } else {
            check(false, "\(label): la activa no enseña la ✕")
        }
        check(controls.map { before in frames["controles"].map { abs($0.minX - before.minX) <= 1 && abs($0.maxX - before.maxX) <= 1 } ?? false } == true,
              "\(label) · herramientas fijas tras reordenar y cerrar pestañas")
        check(create.map { before in frames["crear"].map { abs($0.minX - before.minX) <= 1 && abs($0.maxX - before.maxX) <= 1 } ?? false } == true,
              "\(label) · botones de crear fijos tras reordenar y cerrar pestañas")
    }

    private static func reorder(_ model: AppModel, _ w: NSWindow, _ s: TerminalSession, from p: CGPoint, dx: CGFloat,
                                what: String) async {
        let before = model.tabs.map(\.id)
        guard let i = before.firstIndex(of: s.id) else { return }
        let expected = min(max(i + (dx > 0 ? 1 : -1), 0), before.count - 1)
        let g = gestureEvents
        let r = await drag(w, from: p, dx: dx)
        let j = model.tabs.firstIndex { $0 === s } ?? -1
        check(j == expected && !r.windowMoved && !r.movable && model.tabs.count == before.count,
              "\(what): \(i)→\(j) (esperado \(expected)) · ventana movible=\(r.movable) movida=\(r.windowMoved) · gesto \(gestureEvents - g)")
        if j != i, j >= 0 { model.moveTab(s.id, to: model.tabs[i].id) }    // (como estaba, para el siguiente)
        try? await Task.sleep(for: .milliseconds(400))                     // (y que se recoloquen los marcos)
    }

    @discardableResult
    private static func drag(_ w: NSWindow, from p: CGPoint, dx: CGFloat) async -> (movable: Bool, windowMoved: Bool) {
        let frame = w.frame, m = moves
        post(.leftMouseDown, p, w)
        try? await Task.sleep(for: .milliseconds(60))
        let movable = w.isMovable
        for k in 1...10 {
            post(.leftMouseDragged, CGPoint(x: p.x + dx * CGFloat(k) / 10, y: p.y), w)
            try? await Task.sleep(for: .milliseconds(25))
        }
        post(.leftMouseUp, CGPoint(x: p.x + dx, y: p.y), w)
        try? await Task.sleep(for: .milliseconds(350))
        return (movable, w.frame.origin != frame.origin || moves != m)
    }

    private static func click(_ w: NSWindow, _ p: CGPoint) async {
        post(.leftMouseDown, p, w)
        try? await Task.sleep(for: .milliseconds(60))
        post(.leftMouseUp, p, w)
        try? await Task.sleep(for: .milliseconds(350))
    }

    private static func post(_ type: NSEvent.EventType, _ p: CGPoint, _ w: NSWindow) {
        let h = w.contentView?.bounds.height ?? w.frame.height
        guard let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: p.x, y: h - p.y), modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                         context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
        else { return }
        NSApp.postEvent(e, atStart: false)
    }
}

extension View {
    /// (sólo con NETDECK_SNAPSHOT_DRAGS) apunta el marco de esta vista para `SnapshotDrags`.
    func snapshotFrame(_ key: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if SnapshotDrags.enabled { SnapshotDrags.frames[key] = frame }
        }
    }
}
