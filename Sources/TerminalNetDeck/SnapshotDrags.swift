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
        // (rellenar: la ventana ocupa la pantalla sin ser pantalla completa, como el doble clic o Ventana → Rellenar)
        if let vf = w.screen?.visibleFrame {
            let before = w.frame
            model.toggleFill()
            try? await Task.sleep(for: .milliseconds(900))
            say("— rellenar: ventana \(w.frame) · pantalla \(vf)")
            check(w.frame.insetBy(dx: -2, dy: -2).contains(vf), "rellenar: la ventana ocupa la pantalla")
            await suite(model, w, label: "rellenar")
            model.toggleFill()
            try? await Task.sleep(for: .milliseconds(900))
            check(abs(w.frame.width - before.width) <= 2, "rellenar: vuelta al tamaño de antes")
        }
        w.toggleFullScreen(nil)
        for _ in 0..<50 {
            if w.styleMask.contains(.fullScreen) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .seconds(1))
        check(w.styleMask.contains(.fullScreen), "pantalla completa: activada")
        await suite(model, w, label: "pantalla completa")
        // (los marcos SwiftUI parten de arriba; los de AppKit en la ventana, de abajo: se comparan en ese espacio)
        if let s = model.current, let content = w.contentView, let bar = frames["barra-superior"] {
            let topBar = CGRect(x: bar.minX, y: content.bounds.height - bar.maxY, width: bar.width, height: bar.height)
            let terminal = s.view.convert(s.view.bounds, to: nil)
            let available = content.convert(content.safeAreaRect, to: nil)
            check(abs(topBar.maxY - available.maxY) <= 2 && topBar.minY >= available.minY - 1,
                  "pantalla completa: barra superior junto al borde disponible; barra \(topBar), área \(available)")
            check(terminal.maxY <= topBar.minY + 1,
                  "pantalla completa: terminal sin solape con la barra; terminal \(terminal), barra \(topBar)")
            if model.settings.sidebarVisible {
                check(frames["sesiones"].map { $0.minY >= bar.maxY - 1 } == true,
                      "pantalla completa: sesiones y buscador debajo de la barra")
            }
        } else {
            check(false, "pantalla completa: faltan marcos para comprobar barra y terminal")
        }
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
        await windowsSuite(model, w)
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

    /// Varias ventanas (al final: las claves de `frames` son de una sola ventana): una nueva desde el menú, pasar
    /// pestañas de una a otra (menú y arrastre, sin reconectar), soltar una fuera (ventana nueva donde se suelta, también
    /// en otra pantalla), cerrar ventanas, los menús, lo que se guarda de cada una y reabrirlas en sus ventanas.
    private static func windowsSuite(_ model: AppModel, _ w: NSWindow) async {
        let core = model.core
        say("— ventanas")
        guard let screen = w.screen?.visibleFrame else { check(false, "ventanas: sin pantalla"); return }
        // (la de prueba, a la izquierda y no muy alta: la nueva va a su derecha y arriba queda hueco libre)
        let left = CGRect(x: screen.minX, y: screen.minY, width: max(960, (screen.width * 0.48).rounded()),
                          height: min(640, screen.height - 160))
        w.setFrame(left, display: true)
        while model.tabs.count < 5 {
            model.open(ConnectionRoute(title: "lab-\(model.tabs.count)", target: Endpoint(user: "tu.usuario", host: "198.51.100.\(model.tabs.count + 1)")))
        }
        try? await Task.sleep(for: .milliseconds(600))
        check(w.tabbingMode == .disallowed && !NSWindow.allowsAutomaticWindowTabbing, "menús de ventana: sin las pestañas de macOS")
        // los menús: «Nueva ventana» y «Cerrar ventana»; ni «Cerrar» ni «Cerrar todas» de macOS (cerraban sin preguntar)
        let actions = allItems().compactMap(\.action).map(NSStringFromSelector)
        check(item(L("Nueva ventana")) != nil && item(L("Cerrar ventana")) != nil
              && !actions.contains("performClose:") && !actions.contains("closeAll:"),
              "menús de ventana: Nueva ventana y Cerrar ventana, sin Cerrar/Cerrar todas de macOS")
        check(w.standardWindowButton(.closeButton)?.target is WindowCloseGuard, "cerrar ventana: el botón rojo pregunta antes (con más ventanas)")

        // ⌘N: una ventana nueva, vacía (la portada)
        let n0 = core.attachedWindows.count
        perform(L("Nueva ventana"))
        let opened = await until { core.attachedWindows.count == n0 + 1 }
        guard opened, let b = core.attachedWindows.last, b !== model, let bw = b.window else {
            check(false, "ventana nueva: no se ha abierto (\(core.attachedWindows.count) ventanas)")
            return
        }
        check(b.tabs.isEmpty, "ventana nueva: abierta y vacía (portada)")
        bw.setFrame(CGRect(x: left.maxX + 16, y: left.minY, width: min(1000, screen.maxX - left.maxX - 16), height: left.height),
                    display: true)
        try? await Task.sleep(for: .milliseconds(600))

        // los menús van a la ventana de delante
        core.becameMain(b)
        try? await Task.sleep(for: .milliseconds(300))
        // (⌘K como lo pulsa el usuario: por los atajos del menú)
        let k = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                                 windowNumber: bw.windowNumber, context: nil, characters: "k", charactersIgnoringModifiers: "k",
                                 isARepeat: false, keyCode: 40)
        _ = k.map { NSApp.mainMenu?.performKeyEquivalent(with: $0) }
        let routed = await until { b.sheet == .connect }
        check(routed && model.sheet == nil, "menús de ventana: ⌘K va a la de delante (\(b.sheet == .connect ? "la nueva" : "otra"))")
        // (con una hoja abierta en la de delante, el menú se apaga —al abrirlo— y ⌘K no la sustituye)
        b.sheet = .list
        try? await Task.sleep(for: .milliseconds(400))
        let off = item(L("Conectar / Salto…")).map { i in
            if let m = i.menu { m.delegate?.menuNeedsUpdate?(m); m.update() }
            return !i.isEnabled
        } ?? false
        _ = k.map { NSApp.mainMenu?.performKeyEquivalent(with: $0) }
        try? await Task.sleep(for: .milliseconds(300))
        check(off && b.sheet == .list, "menús de ventana: con una hoja abierta ⌘K no la sustituye (apagado=\(off), hoja=\(b.sheet == .list ? "la misma" : "otra"))")
        b.sheet = nil
        core.becameMain(model)
        try? await Task.sleep(for: .milliseconds(500))

        // menú «Mover a la ventana»: sin reconectar (el mismo terminal, ahora en la otra)
        let s1 = model.tabs[1]
        let moved = model.moveTab(s1, to: b)
        _ = await until { s1.view.window === bw }
        check(moved && b.tabs.contains { $0 === s1 } && !model.tabs.contains { $0 === s1 } && s1.view.window === bw && !s1.exited,
              "mover a otra ventana: «\(s1.title)» pasa con su terminal, sin reconectar")
        // con una hoja abierta en la otra no se le lleva nada (el pegado escribiría en la que llega)
        b.sheet = .paste
        try? await Task.sleep(for: .milliseconds(200))
        let refused = !model.moveTab(model.tabs[0], to: b)
        b.sheet = nil
        check(refused && b.tabs.count == 1, "mover a otra ventana: no si la otra tiene una hoja abierta (pegado)")
        // fuera de MultiExec sigue fuera al moverla; y a una ventana con MultiExec encendido llega fuera
        let sx = model.tabs[2]
        model.toggleExcluded(sx)
        model.moveTab(sx, to: b)
        let keptOut = b.excluded.contains(sx.id)
        b.multiExecOn = true
        let sy = model.tabs[2]
        model.moveTab(sy, to: b)
        let arrivedOut = b.excluded.contains(sy.id) && !b.multiExecTargets.contains { $0 === sy }
        b.multiExecOn = false
        check(keptOut && arrivedOut, "mover a otra ventana: la excluida de MultiExec sigue fuera y a una con MultiExec llega fuera")
        // Ajustes (y sesiones, macros, túneles) sólo en una ventana a la vez: el último en guardar pisaría al otro
        b.openSettings()
        try? await Task.sleep(for: .milliseconds(300))
        model.openSettings()
        model.present(.macros)
        check(b.showSettings && !model.showSettings && model.sheet == nil,
              "menús de ventana: Ajustes, sesiones, macros y túneles sólo en una ventana a la vez")
        b.showSettings = false
        try? await Task.sleep(for: .milliseconds(300))

        // (su título, el de la pestaña elegida: es el que sale en el menú Ventana y en Mission Control)
        let titled = await until { bw.title == b.current?.tabTitle }
        check(titled, "ventana nueva: su título es el de su pestaña elegida («\(bw.title)»)")
        let dock = NSApp.delegate?.applicationDockMenu?(NSApp)
        check(dock?.items.contains { $0.title == L("Nueva ventana") } == true, "menús de ventana: «Nueva ventana» en el Dock")

        // arrastrar una pestaña hasta la barra de la otra ventana: cae en el sitio en que se suelta
        try? await Task.sleep(for: .milliseconds(400))
        let s2 = model.tabs[0]
        model.show(s2)                                  // (que se vea en la tira, aunque esté desplazada)
        try? await Task.sleep(for: .milliseconds(600))
        if let f = model.tabFrames[s2.id], let bar = b.stillZones["pestañas"], let content = bw.contentView {
            let target = bw.convertPoint(toScreen: NSPoint(x: bar.minX + 6, y: content.bounds.height - bar.midY))
            say("· arrastre a otra ventana: destino \(target) · esta \(w.frame) · la otra \(bw.frame) · bajo el punto: \(core.window(at: target) === b ? "la otra" : core.window(at: target) === model ? "esta" : "ninguna") · orden \(NSApp.orderedWindows.map { "\($0.frame.origin.x)/\($0.isVisible)/\($0.isOnActiveSpace)" })")
            await dragOut(w, from: CGPoint(x: f.minX + 40, y: f.midY), toScreen: target)
            let landed = await until { b.tabs.contains { $0 === s2 } }
            check(landed && b.tabs.first === s2 && s2.view.window === bw,
                  "arrastre a otra ventana: «\(s2.title)» en la posición \(b.tabs.firstIndex { $0 === s2 } ?? -1) de la otra")
        } else {
            check(false, "arrastre a otra ventana: sin marcos")
        }

        // soltarla fuera de las ventanas: una nueva con ella, en ese sitio (y en la otra pantalla, si hay)
        var spots = [CGPoint(x: screen.midX, y: screen.maxY - 30), CGPoint(x: screen.maxX - 40, y: screen.maxY - 30)]
        spots.insert(contentsOf: NSScreen.screens.filter { $0 != w.screen }.map { CGPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) }, at: 0)
        for spot in spots.filter({ core.window(at: $0) == nil }).prefix(2) {
            guard model.tabs.count > 1, let s = model.current ?? model.tabs.last else { break }
            model.show(s)
            try? await Task.sleep(for: .milliseconds(500))
            guard let f = model.tabFrames[s.id] else { check(false, "arrastre fuera: sin marco"); break }
            let n = core.attachedWindows.count
            await dragOut(w, from: CGPoint(x: f.minX + 30, y: f.midY), toScreen: spot)
            let made = await until { core.attachedWindows.count == n + 1 }
            let c = core.attachedWindows.last
            let place = NSScreen.screens.first { $0.visibleFrame.contains(spot) }
            check(made && c?.tabs.first === s && !model.tabs.contains { $0 === s } && c?.window?.screen == place
                  && c?.window.map { $0.frame.contains(spot) || $0.frame.insetBy(dx: -40, dy: -40).contains(spot) } == true,
                  "arrastre fuera: ventana nueva en \(spot) (\(place == w.screen ? "esta pantalla" : "otra pantalla")) con «\(s.title)»")
            // y cerrarla: sus pestañas se cortan; las de las otras siguen
            if let c, let cw = c.window {
                let others = core.allTabs.filter { $0 !== s }
                cw.close()
                let gone = await until { !core.allTabs.contains { $0 === s } && core.attachedWindows.count == n }
                check(gone && others.allSatisfy { o in core.allTabs.contains { $0 === o } },
                      "cerrar ventana: se cortan sus pestañas y las otras siguen (\(core.attachedWindows.count) ventanas)")
            }
        }

        // lo que se guarda: cada ventana con sus pestañas y su sitio
        let saved = core.currentOpenWindows()
        check(saved.windows.count == core.attachedWindows.filter { !$0.tabs.isEmpty }.count
              && saved.windows.last?.tabs.map(\.title) == b.tabs.map(\.route.title) && saved.windows.last?.frame == bw.frame,
              "reabrir en sus ventanas: se guardan \(saved.windows.count) ventanas, cada una con las suyas y su sitio")

        // la última pestaña de una ventana pasa a otra: la vacía se cierra sola
        let n1 = core.attachedWindows.count
        for s in b.tabs { b.moveTab(s, to: model) }
        let gone = await until { core.attachedWindows.count == n1 - 1 && !core.attachedWindows.contains { $0 === b } }
        model.show(s1)                                  // (sólo la elegida está en la ventana)
        let closedEmpty = await until { gone && s1.view.window === w }
        check(closedEmpty, "cerrar ventana: la que se queda sin pestañas se cierra y «\(s1.title)» vuelve")

        // reabrir: las de la primera ventana aquí, las de la segunda en una nueva en su sitio
        let firstFrame = w.frame.offsetBy(dx: 20, dy: -20)
        let expectedFirst = WindowPlacement.restored(firstFrame, screens: NSScreen.screens.map(\.visibleFrame))
        let frame = CGRect(x: left.maxX + 30, y: left.minY + 20, width: 980, height: 560)     // (más baja que el mínimo)
        let minimum = core.attachedWindows.first?.window?.minSize ?? .zero
        let want = CGRect(x: frame.minX, y: frame.maxY - max(frame.height, minimum.height),
                          width: max(frame.width, minimum.width), height: max(frame.height, minimum.height))
        let expected = WindowPlacement.restored(want, screens: NSScreen.screens.map(\.visibleFrame))
        core.lastOpen = OpenWindows(windows: [
            .init(tabs: [ConnectionRoute(title: "core-01", target: Endpoint(user: "tu.usuario", host: "192.0.2.11"))], frame: firstFrame),
            .init(tabs: [ConnectionRoute(title: "pe-02", target: Endpoint(user: "tu.usuario", host: "198.51.100.2")),
                         ConnectionRoute(title: "rr-01", target: Endpoint(user: "tu.usuario", host: "198.51.100.3"))], frame: frame),
        ])
        let n2 = core.attachedWindows.count, before = model.tabs.count
        model.reopenLast()
        let reopened = await until { core.attachedWindows.count == n2 + 1 && core.attachedWindows.last?.tabs.count == 2 }
        let r = core.attachedWindows.last
        check(reopened && model.tabs.count == before + 1 && r?.tabs.map(\.route.title) == ["pe-02", "rr-01"]
              && w.frame == expectedFirst && r?.window?.frame == expected,
              "reabrir en sus ventanas: 1 aquí y 2 en una nueva, ambas en su sitio (\(w.frame) · \(r?.window?.frame ?? .zero))")
        if let r, r !== model, let rw = r.window {
            rw.close()
            _ = await until { !core.attachedWindows.contains { $0 === r } }
        }
        await fullScreenMove(model, w)
    }

    /// A pantalla completa: «Mover a una ventana nueva» también (la nueva sale aparte y la conexión sigue).
    private static func fullScreenMove(_ model: AppModel, _ w: NSWindow) async {
        let core = model.core
        w.toggleFullScreen(nil)
        guard await until({ w.styleMask.contains(.fullScreen) }) else { check(false, "ventana nueva: no entra en pantalla completa"); return }
        try? await Task.sleep(for: .seconds(1))
        let n = core.attachedWindows.count
        guard model.tabs.count > 1, let s = model.current else { check(false, "ventana nueva: sin pestañas que mover"); return }
        model.moveTabToNewWindow(s)
        let made = await until { core.attachedWindows.count == n + 1 && core.attachedWindows.last?.tabs.first === s }
        check(made && !s.exited && s.view.window === core.attachedWindows.last?.window,
              "ventana nueva: desde pantalla completa, con «\(s.title)» y sin reconectar")
        if made, let c = core.attachedWindows.last, let cw = c.window {
            _ = c.moveTab(s, to: model)                             // (vuelve; la nueva, vacía, se cierra sola)
            let back = await until { !core.attachedWindows.contains { $0 === c } && model.tabs.contains { $0 === s } }
            check(back && cw.isVisible == false, "cerrar ventana: la de pantalla completa recupera la pestaña y la otra se cierra")
        }
        w.toggleFullScreen(nil)
        _ = await until { !w.styleMask.contains(.fullScreen) }
        try? await Task.sleep(for: .seconds(1))
    }

    /// Arrastra desde `p` (en `w`, de arriba a la izquierda) hasta `target` (pantalla), como el ratón de verdad: los
    /// eventos van a la ventana en la que se pulsó aunque el puntero salga de ella.
    private static func dragOut(_ w: NSWindow, from p: CGPoint, toScreen target: CGPoint) async {
        let h = w.contentView?.bounds.height ?? w.frame.height
        let start = w.convertPoint(toScreen: NSPoint(x: p.x, y: h - p.y))
        func local(_ s: CGPoint) -> CGPoint {
            let q = w.convertPoint(fromScreen: s)
            return CGPoint(x: q.x, y: h - q.y)
        }
        post(.leftMouseDown, p, w)
        try? await Task.sleep(for: .milliseconds(60))
        for k in 1...12 {
            let f = CGFloat(k) / 12
            post(.leftMouseDragged, local(CGPoint(x: start.x + (target.x - start.x) * f, y: start.y + (target.y - start.y) * f)), w)
            try? await Task.sleep(for: .milliseconds(30))
        }
        post(.leftMouseUp, local(target), w)
        try? await Task.sleep(for: .milliseconds(300))
    }

    /// Espera (hasta 6 s) a que se cumpla.
    private static func until(_ ok: () -> Bool) async -> Bool {
        let start = ContinuousClock.now
        while !ok() {
            guard ContinuousClock.now - start < .seconds(6) else { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return true
    }

    private static func allItems(_ menu: NSMenu? = NSApp.mainMenu) -> [NSMenuItem] {
        (menu?.items ?? []).flatMap { [$0] + allItems($0.submenu) }
    }

    private static func item(_ title: String) -> NSMenuItem? { allItems().first { $0.title == title } }

    /// Como al abrir el menú: primero se revalida (si no, queda el estado de la última vez que se miró).
    private static func perform(_ title: String) {
        guard let i = item(title), let menu = i.menu else { check(false, "menús de ventana: no está «\(title)»"); return }
        menu.update()
        menu.performActionForItem(at: menu.index(of: i))
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
