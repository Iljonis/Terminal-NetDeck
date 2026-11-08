import AppKit
import NetDeckCore
import SwiftUI

// Menús, desplegables y avisos con la temática de la app: los de macOS (NSMenu, NSPopUpButton, NSAlert) no se dejan
// pintar. Los botones de siempre (`Button(…) { … }`) valen dentro: el estilo de fila los pinta y cierra el panel.

/// Cierra el menú en el que está la vista.
@MainActor
final class MenuCloser {
    let close: () -> Void
    init(_ close: @escaping () -> Void) { self.close = close }
}

private struct MenuCloseKey: EnvironmentKey {
    static let defaultValue: MenuCloser? = nil
}

extension EnvironmentValues {
    var menuClose: MenuCloser? {
        get { self[MenuCloseKey.self] }
        set { self[MenuCloseKey.self] = newValue }
    }

    var menuKeys: MenuKeys? {
        get { self[MenuKeysKey.self] }
        set { self[MenuKeysKey.self] = newValue }
    }

    /// La fila de la opción ya elegida (en un desplegable): el menú se abre con ella resaltada y a la vista.
    var menuChosen: Bool {
        get { self[MenuChosenKey.self] }
        set { self[MenuChosenKey.self] = newValue }
    }
}

private struct MenuKeysKey: EnvironmentKey {
    static let defaultValue: MenuKeys? = nil
}

private struct MenuChosenKey: EnvironmentKey {
    static let defaultValue = false
}

/// El teclado en un menú con la temática, como en los de macOS: ↑ ↓ recorren las filas, Intro o espacio la elegida y
/// Esc lo cierra (eso ya lo hace el panel). Una sola fila resaltada, la del ratón o la de las flechas: cada fila se
/// apunta con su altura en el menú (`space`) y lo que hace. La de las flechas se desplaza a la vista (`shown`), y al
/// abrirlo empieza en la ya elegida.
@MainActor @Observable
final class MenuKeys {
    nonisolated static let space = "menú"
    private(set) var lit: UUID?
    /// La que hay que llevar a la vista (la de las flechas o, al abrirlo, la elegida); no la del ratón, que ya se ve.
    private(set) var shown: UUID?
    @ObservationIgnored private var rows: [UUID: (y: CGFloat, enabled: Bool, run: () -> Void)] = [:]
    @ObservationIgnored private var placed = false

    /// `y` nil: donde ya estaba. `chosen`: la opción elegida (sólo cuenta la primera vez).
    func register(_ id: UUID, y: CGFloat?, enabled: Bool, chosen: Bool = false, run: @escaping () -> Void) {
        rows[id] = (y ?? rows[id]?.y ?? 0, enabled, run)
        if !enabled, lit == id { lit = nil }
        if chosen, enabled, !placed {
            placed = true
            (lit, shown) = (id, id)
        }
    }

    func remove(_ id: UUID) {
        rows[id] = nil
        if lit == id { lit = nil }
    }

    func hover(_ id: UUID, _ inside: Bool) {
        if inside { lit = id } else if lit == id { lit = nil }
    }

    /// La de abajo (1) o la de arriba (-1); de la última se pasa a la primera.
    func move(_ step: Int) {
        let order = rows.filter(\.value.enabled).sorted { $0.value.y < $1.value.y }.map(\.key)
        guard !order.isEmpty else { return }
        let i = lit.flatMap(order.firstIndex(of:)).map { $0 + step } ?? (step > 0 ? 0 : order.count - 1)
        lit = order[(i + order.count) % order.count]
        shown = lit
    }

    func activate() -> Bool {
        guard let lit, let row = rows[lit], row.enabled else { return false }
        row.run()
        return true
    }
}

extension View {
    /// Un menú que se recorre con el teclado (`MenuKeys`): se queda con el foco al abrirse.
    func menuKeyboard() -> some View { modifier(MenuKeyboard()) }

    /// Una fila de un menú con teclado: se apunta en `MenuKeys` (si está en uno) y avisa del ratón. `chosen`: la opción
    /// ya elegida.
    func menuKey(_ id: UUID, enabled: Bool = true, chosen: Bool = false, hover: Binding<Bool>, run: @escaping () -> Void) -> some View {
        modifier(MenuKeyRow(id: id, enabled: enabled, chosen: chosen, hover: hover, run: run))
    }
}

private struct MenuKeyboard: ViewModifier {
    @Stored private var keys = MenuKeys()
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        // (la fila de las flechas, a la vista: en un menú largo o en la lista de grupos de «+», se salía por abajo)
        ScrollViewReader { proxy in
            content
                .coordinateSpace(.named(MenuKeys.space))
                .environment(\.menuKeys, keys)
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onAppear { focused = true }
                .onKeyPress(.downArrow) { keys.move(1); return .handled }
                .onKeyPress(.upArrow) { keys.move(-1); return .handled }
                .onKeyPress(keys: [.return, .space]) { _ in keys.activate() ? .handled : .ignored }
                .onChange(of: keys.shown) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }
}

private struct MenuKeyRow: ViewModifier {
    @Environment(\.menuKeys) private var keys
    let id: UUID
    let enabled: Bool
    let chosen: Bool
    @Binding var hover: Bool
    let run: () -> Void

    func body(content: Content) -> some View {
        content
            .id(id)                                             // (para `scrollTo`)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(MenuKeys.space)).minY } action: {
                keys?.register(id, y: $0, enabled: enabled, chosen: chosen, run: run)
            }
            .onChange(of: enabled) { keys?.register(id, y: nil, enabled: enabled, run: run) }
            .onDisappear { keys?.remove(id) }
            // (en un menú con teclado, resaltada = la de `MenuKeys`, sea del ratón o de las flechas)
            .onHover { inside in
                if let keys { keys.hover(id, inside && enabled) } else { hover = inside && enabled }
            }
            .onChange(of: keys?.lit == id) { _, lit in if keys != nil { hover = lit } }
    }
}

/// Una fila de menú: el título del botón, resaltada al pasar por encima; al pulsarla se cierra el menú y se hace lo
/// suyo. Las de `role: .destructive`, en el color de error del tema.
struct ThemedMenuRowStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }

    private struct Row: View {
        @Environment(\.theme) private var t
        @Environment(\.isEnabled) private var enabled
        @Environment(\.menuClose) private var close
        @Environment(\.menuChosen) private var chosen
        let configuration: Configuration
        @Stored private var hover = false
        @Stored private var id = UUID()

        var body: some View {
            let tint = configuration.role == .destructive ? t.bad : (hover ? t.accent : t.text)
            HStack(spacing: 8) {
                configuration.label.labelStyle(MenuLabelStyle(hover: hover))
                Spacer(minLength: 14)
            }
            .font(t.ui(12))
            .foregroundStyle(SwiftUI.Color(tint))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 25)
            .background(RoundedRectangle(cornerRadius: t.corner ?? 4).fill(SwiftUI.Color(t.accent).opacity(hover && enabled ? 0.14 : 0)))
            .overlay(alignment: .leading) {
                Rectangle().fill(SwiftUI.Color(t.accent)).frame(width: 2).opacity(hover && enabled && t.glows ? 1 : 0)
                    .shadow(color: SwiftUI.Color(t.accent), radius: t.glow(3))
            }
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .menuKey(id, enabled: enabled, chosen: chosen, hover: $hover, run: choose)
            .onTapGesture(perform: choose)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, choose)
        }

        private func choose() {
            guard enabled else { return }
            close?.close()
            // (en la vuelta siguiente: así el panel ya se ha cerrado si la acción abre un aviso modal; dentro del
            // gesto, el bucle modal dejaba el panel abierto encima y la ventana parecía congelada)
            DispatchQueue.main.async { configuration.trigger() }
        }
    }
}

/// Icono de un `Label` en las filas de menú: el segundo color del tema.
private struct MenuLabelStyle: LabelStyle {
    @Environment(\.theme) private var t
    let hover: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SwiftUI.Color(hover ? t.accent : t.accent2)).frame(width: 15)
            configuration.title
        }
    }
}

/// El panel de un menú: fondo y borde del tema; los `Button` de dentro son filas.
struct ThemedMenuPanel<Content: View>: View {
    @Environment(\.theme) private var t
    let close: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 1) { content() }
                .padding(6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 210, maxHeight: 520)
        .fixedSize(horizontal: true, vertical: true)
        .buttonStyle(ThemedMenuRowStyle())
        .environment(\.menuClose, MenuCloser(close))
        .menuKeyboard()
        .background(SwiftUI.Color(t.bar.opaque))
        .overlay(alignment: .top) { Rectangle().fill(SwiftUI.Color(t.accent)).frame(height: 2).opacity(t.glows ? 0.8 : 0) }
        .presentationBackground(SwiftUI.Color(t.bar.opaque))
    }
}

/// Raya entre grupos de un menú.
struct MenuDivider: View {
    @Environment(\.theme) private var t
    var body: some View {
        Rectangle().fill(SwiftUI.Color(t.panel)).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 6)
    }
}

/// Título de un grupo dentro de un menú.
struct MenuHeader: View {
    @Environment(\.theme) private var t
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(t.ui(9.5, .bold)).tracking(t.tracking)
            .foregroundStyle(SwiftUI.Color(t.dim))
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)
    }
}

/// Submenú: se despliega dentro del mismo panel (▸ / ▾).
struct ThemedSubmenu<Content: View>: View {
    @Environment(\.theme) private var t
    let title: String
    @ViewBuilder var content: () -> Content
    @Stored private var open = false
    @Stored private var hover = false
    @Stored private var id = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 14)
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .font(t.ui(12))
            .foregroundStyle(SwiftUI.Color(hover ? t.accent : t.text))
            .padding(.horizontal, 10)
            .frame(minHeight: 25)
            .background(RoundedRectangle(cornerRadius: t.corner ?? 4).fill(SwiftUI.Color(t.accent).opacity(hover ? 0.10 : 0)))
            .contentShape(Rectangle())
            .menuKey(id, hover: $hover, run: toggle)
            .onTapGesture(perform: toggle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(open ? L("desplegado") : L("plegado"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, toggle)
            if open {
                VStack(alignment: .leading, spacing: 1) { content() }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(SwiftUI.Color(t.accent2).opacity(0.3)).frame(width: 1).padding(.leading, 6) }
            }
        }
    }

    private func toggle() { withAnimation(.easeOut(duration: 0.12)) { open.toggle() } }
}

/// `Menu` con la temática: la etiqueta abre un panel con el contenido.
struct ThemedMenu<Label: View, Content: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label
    @Stored private var open = false

    var body: some View {
        Button { open.toggle() } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ThemedMenuPanel(close: { open = false }, content: content)
            }
    }
}

// MARK: - clic derecho

extension View {
    /// Como `.contextMenu`, pero con la temática: clic derecho (o ⌃clic) abre el panel donde se ha pulsado.
    func themedContextMenu<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        modifier(ThemedContextMenu(menu: content))
    }
}

private struct ThemedContextMenu<Menu: View>: ViewModifier {
    let menu: () -> Menu
    @Stored private var at: UnitPoint?

    func body(content: Content) -> some View {
        content
            .overlay(RightClickCatcher { at = $0 })
            .popover(isPresented: Binding(get: { at != nil }, set: { if !$0 { at = nil } }),
                     attachmentAnchor: .point(at ?? .center), arrowEdge: .bottom) {
                ThemedMenuPanel(close: { at = nil }, content: menu)
            }
    }
}

/// Recoge el clic derecho (y ⌃clic) sin quitarle a la vista de debajo los clics normales ni el arrastre.
private struct RightClickCatcher: NSViewRepresentable {
    let found: (UnitPoint) -> Void

    final class Catcher: NSView {
        var found: ((UnitPoint) -> Void)?
        override var isFlipped: Bool { true }

        /// Todos los que hay en una ventana, para dar el clic al más concreto.
        private static let all = NSHashTable<Catcher>.weakObjects()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { Self.all.add(self) } else { Self.all.remove(self) }
        }

        /// Mientras se comprueba si uno está de verdad bajo el ratón (`reachable`), sólo responde ése.
        private static var probe: Catcher?

        override func hitTest(_ point: NSPoint) -> NSView? {
            if let p = Self.probe { return p === self ? super.hitTest(point) : nil }
            guard let e = NSApp.currentEvent else { return nil }
            let right = e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
            return right ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { Self.owner(of: event, from: self).report(event) }
        override func mouseDown(with event: NSEvent) { Self.owner(of: event, from: self).report(event) }

        /// Con un menú dentro de otro (el de una fila bajo el del fondo de la lista) el clic lo recibe el de encima,
        /// que no tiene por qué ser el más concreto: es del más pequeño que haya bajo el ratón (como el contextMenu
        /// nativo). Sin preguntar a `hitTest` desde `hitTest`: así ninguno cedía el clic al otro y se perdía. Sólo los
        /// que están dentro del que lo ha recibido (una fila que el scroll ha sacado de la lista no cuenta) y con el
        /// ratón dentro de sus bounds (el `visibleRect` de las vistas de SwiftUI no se recorta a ellos). Una fila que
        /// asoma a medias por el borde de la lista (la última, cortada) también, si es lo que hay bajo el ratón: si no,
        /// su clic derecho abría el menú del fondo («Nueva carpeta…») en vez del suyo.
        private static func owner(of event: NSEvent, from first: Catcher) -> Catcher {
            let area = first.convert(first.bounds, to: nil)
            let p = event.locationInWindow
            var best = first
            for c in all.allObjects where c !== first && c.window === event.window && !c.isHiddenOrHasHiddenAncestor {
                let frame = c.convert(c.bounds, to: nil)
                guard frame.contains(p), area.intersects(frame),
                      frame.width * frame.height < best.bounds.width * best.bounds.height,
                      area.contains(frame) || reachable(c, at: p) else { continue }
                best = c
            }
            return best
        }

        /// ¿Es `c` lo que la ventana encuentra en `p` (con lo que lo recorta y lo que tiene encima)? Sólo responde él
        /// a `hitTest` mientras tanto; se pregunta desde el clic, nunca desde `hitTest`. Así una fila tapada por la
        /// cabecera fija de una lista no se lleva el clic de la cabecera.
        private static func reachable(_ c: Catcher, at p: NSPoint) -> Bool {
            guard let root = c.window?.contentView?.superview ?? c.window?.contentView else { return false }
            probe = c
            defer { probe = nil }
            return root.hitTest(root.superview?.convert(p, from: nil) ?? p) === c
        }

        private func report(_ event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            guard bounds.width > 0, bounds.height > 0 else { return }
            found?(UnitPoint(x: p.x / bounds.width, y: p.y / bounds.height))
        }
    }

    func makeNSView(context: Context) -> Catcher {
        let v = Catcher()
        v.found = found
        return v
    }

    func updateNSView(_ v: Catcher, context: Context) { v.found = found }
}

// MARK: - desplegable (Picker)

/// `Picker` con la temática: título a la izquierda y, a la derecha, el valor elegido; al pulsarlo, las opciones.
struct ThemedPicker<Value: Hashable>: View {
    @Environment(\.theme) private var t
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var width: CGFloat?
    @Stored private var open = false
    @Stored private var hover = false

    init(_ title: String, selection: Binding<Value>, options: [(value: Value, label: String)], width: CGFloat? = nil) {
        self.title = title
        _selection = selection
        self.options = options
        self.width = width
    }

    /// Las opciones se van añadiendo: `{ o in o.append((valor, "texto")) }`.
    init(_ title: String, selection: Binding<Value>, width: CGFloat? = nil,
         _ build: (inout [(value: Value, label: String)]) -> Void) {
        var o: [(value: Value, label: String)] = []
        build(&o)
        self.init(title, selection: selection, options: o, width: width)
    }

    var body: some View {
        HStack {
            if !title.isEmpty {
                Text(title).foregroundStyle(SwiftUI.Color(t.text))
                Spacer(minLength: 10)
            }
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Text(current).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SwiftUI.Color(t.accent))
                }
                .font(t.ui(12))
                .foregroundStyle(SwiftUI.Color(t.text))
                .padding(.horizontal, 9)
                .frame(minWidth: width, minHeight: 24, alignment: .trailing)
                .background(RoundedRectangle(cornerRadius: t.corner ?? 5).fill(SwiftUI.Color(t.panel).opacity(hover ? 1 : 0.7)))
                .overlay(RoundedRectangle(cornerRadius: t.corner ?? 5)
                    .strokeBorder(SwiftUI.Color(t.accent).opacity(open || hover ? 0.8 : 0.25)))
                .shadow(color: SwiftUI.Color(t.accent).opacity(open ? 0.4 : 0), radius: t.glow(4))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ThemedMenuPanel(close: { open = false }) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                        Button { selection = o.value } label: {
                            // (la marca siempre, a la vista o no: un `systemImage` vacío no es un símbolo y avisa)
                            Label { Text(o.label) } icon: { Image(systemName: "checkmark").opacity(o.value == selection ? 1 : 0) }
                        }
                        .environment(\.menuChosen, o.value == selection)
                    }
                }
            }
        }
    }

    private var current: String { options.first { $0.value == selection }?.label ?? "—" }
}

// MARK: - avisos (en vez de NSAlert)

/// Aviso modal con la temática (como `NSAlert.runModal`: devuelve el número del botón pulsado, 0 el primero; Intro = el
/// primero y Esc = el último, salvo si es el destructivo: `AlertKeys`). `field`: con un campo de texto (su valor queda
/// en `text`). Siempre con `await`: se abre en la vuelta siguiente del bucle principal (`MainTurn`), nunca dentro de la
/// acción de un botón, donde el aviso no recibía los clics y la app se quedaba colgada (Borrar en el explorador, 0.8.5).
@MainActor
enum ThemedAlert {
    struct Result: Sendable {
        var button: Int
        var text: String
    }

    /// `over`: la ventana sobre la que sale (si no, la de delante).
    @discardableResult
    static func run(_ title: String, message: String = "", buttons: [String], destructive: Int? = nil,
                    field: (placeholder: String, value: String, secure: Bool)? = nil, over: NSWindow? = nil) async -> Result {
        await MainTurn.next { present(title, message: message, buttons: buttons, destructive: destructive, field: field, over: over) }
    }

    /// Sí/no: true si se pulsa el primero.
    static func confirm(_ title: String, message: String = "", ok: String, cancel: String = L("Cancelar"),
                        destructive: Bool = false, over: NSWindow? = nil) async -> Bool {
        await run(title, message: message, buttons: [ok, cancel], destructive: destructive ? 0 : nil, over: over).button == 0
    }

    /// Sí/no al momento, sin `MainTurn`: para ⌘Q, que con `.terminateLater` deja el bucle en el modo de los paneles
    /// (allí no llega `MainTurn`). Sólo ya fuera de cualquier acción (`AppDelegate.applicationShouldTerminate`).
    static func confirmNow(_ title: String, message: String, ok: String, destructive: Bool, over: NSWindow?) -> Bool {
        present(title, message: message, buttons: [ok, L("Cancelar")], destructive: destructive ? 0 : nil, field: nil, over: over).button == 0
    }

    /// El aviso de verdad, al momento (sólo desde `run` y `confirmNow`, ya fuera de cualquier acción).
    private static func present(_ title: String, message: String, buttons: [String], destructive: Int?,
                                field: (placeholder: String, value: String, secure: Bool)?, over: NSWindow?) -> Result {
        let theme = AppCore.shared.uiTheme
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
                            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .modalPanel                   // (por encima de la hoja abierta y de sus menús)
        panel.backgroundColor = NSColor(theme.bar.opaque)
        panel.appearance = NSAppearance(named: theme.isLight ? .aqua : .darkAqua)
        let box = AlertBox(text: field?.value ?? "")
        let view = AlertView(title: title, message: message, buttons: buttons, destructive: destructive, field: field, box: box) { i in
            box.button = i
            NSApp.stopModal()
        }
        .environment(\.theme, theme)
        let host = NSHostingView(rootView: view)
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        if let parent = over ?? AppCore.shared.front?.window ?? NSApp.keyWindow {
            let f = parent.frame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY - panel.frame.height / 2 + f.height / 6))
        } else {
            panel.center()
        }
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return Result(button: box.button ?? AlertKeys.closed(buttons: buttons.count, destructive: destructive), text: box.text)
    }


    @MainActor @Observable
    final class AlertBox {
        var text: String
        var button: Int?
        init(text: String) { self.text = text }
    }

    private struct AlertView: View {
        @Environment(\.theme) private var t
        let title: String
        let message: String
        let buttons: [String]
        let destructive: Int?
        let field: (placeholder: String, value: String, secure: Bool)?
        @Bindable var box: AlertBox
        let done: (Int) -> Void
        @FocusState private var focused: Bool
        /// (ni Intro ni Esc pulsan el destructivo)
        private var keys: (enter: Int?, escape: Int?) { AlertKeys.shortcuts(buttons: buttons.count, destructive: destructive) }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: destructive != nil ? "exclamationmark.triangle.fill" : "terminal.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(SwiftUI.Color(destructive != nil ? t.warning : t.accent))
                        .shadow(color: SwiftUI.Color(t.accent).opacity(0.6), radius: t.glow(6))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(t.ui(14, .bold)).foregroundStyle(SwiftUI.Color(t.text))
                            .fixedSize(horizontal: false, vertical: true)
                        if !message.isEmpty {
                            Text(message).font(t.ui(12)).foregroundStyle(SwiftUI.Color(t.dim))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let field {
                    Group {
                        if field.secure { SecureField(field.placeholder, text: $box.text) } else { TextField(field.placeholder, text: $box.text) }
                    }
                    .textFieldStyle(.plain)
                    .font(t.ui(12.5))
                    .foregroundStyle(SwiftUI.Color(t.text))
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: t.corner ?? 5).fill(SwiftUI.Color(t.background.opaque)))
                    .overlay(RoundedRectangle(cornerRadius: t.corner ?? 5).strokeBorder(SwiftUI.Color(t.accent).opacity(focused ? 0.8 : 0.3)))
                    .focused($focused)
                    .onSubmit { if let k = keys.enter { done(k) } }
                }
                HStack(spacing: 8) {
                    Spacer()
                    ForEach(Array(buttons.enumerated()).reversed(), id: \.offset) { i, b in
                        // (el icono y el resalte, por lo que hace el botón: el que pulsa Intro va resaltado; el
                        // destructivo, con el aviso, nunca como el de por defecto)
                        NeonButton(title: b, icon: i == destructive ? "exclamationmark.triangle" : (i == keys.enter ? "checkmark" : "xmark"),
                                   tint: i == destructive ? t.bad : (i == keys.enter ? t.accent : t.dim), active: i == keys.enter) { done(i) }
                            .keyboardShortcut(i == keys.enter ? .defaultAction : (i == keys.escape ? .cancelAction : nil))
                    }
                }
            }
            .padding(18)
            .padding(.top, 8)
            .frame(width: 420)
            .background(SwiftUI.Color(t.bar.opaque))
            .overlay(alignment: .top) { Rectangle().fill(SwiftUI.Color(t.accent)).frame(height: 2).opacity(t.neon ? 0.8 : 0.4) }
            .onAppear { if field != nil { focused = true } }
        }
    }
}
