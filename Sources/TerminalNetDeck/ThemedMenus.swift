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
}

/// Una fila de menú: el título del botón, resaltada al pasar por encima; al pulsarla se cierra el menú y se hace lo
/// suyo. Las de `role: .destructive`, en el color de error del tema.
struct ThemedMenuRowStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }

    private struct Row: View {
        @Environment(\.theme) private var t
        @Environment(\.isEnabled) private var enabled
        @Environment(\.menuClose) private var close
        let configuration: Configuration
        @Stored private var hover = false

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
                Rectangle().fill(SwiftUI.Color(t.accent)).frame(width: 2).opacity(hover && enabled && t.neon ? 1 : 0)
                    .shadow(color: SwiftUI.Color(t.accent), radius: t.glow(3))
            }
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onHover { hover = $0 && enabled }
            .onTapGesture {
                guard enabled else { return }
                close?.close()
                // (en la vuelta siguiente: así el panel ya se ha cerrado si la acción abre un aviso modal; dentro del
                // gesto, el bucle modal dejaba el panel abierto encima y la ventana parecía congelada)
                DispatchQueue.main.async { configuration.trigger() }
            }
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
        .background(SwiftUI.Color(t.bar.opaque))
        .overlay(alignment: .top) { Rectangle().fill(SwiftUI.Color(t.accent)).frame(height: 2).opacity(t.neon ? 0.8 : 0) }
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
            .onHover { hover = $0 }
            .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { open.toggle() } }
            if open {
                VStack(alignment: .leading, spacing: 1) { content() }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(SwiftUI.Color(t.accent2).opacity(0.3)).frame(width: 1).padding(.leading, 6) }
            }
        }
    }
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

        override func hitTest(_ point: NSPoint) -> NSView? {
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
        /// ratón dentro de sus bounds (el `visibleRect` de las vistas de SwiftUI no se recorta a ellos).
        private static func owner(of event: NSEvent, from first: Catcher) -> Catcher {
            let area = first.convert(first.bounds, to: nil)
            var best = first
            for c in all.allObjects where c !== first && c.window === event.window && !c.isHiddenOrHasHiddenAncestor {
                let frame = c.convert(c.bounds, to: nil)
                guard frame.contains(event.locationInWindow), area.contains(frame),
                      frame.width * frame.height < best.bounds.width * best.bounds.height else { continue }
                best = c
            }
            return best
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
                            Label(o.label, systemImage: o.value == selection ? "checkmark" : "")
                        }
                    }
                }
            }
        }
    }

    private var current: String { options.first { $0.value == selection }?.label ?? "—" }
}

// MARK: - avisos (en vez de NSAlert)

/// Aviso modal con la temática (como `NSAlert.runModal`: devuelve el número del botón pulsado, 0 el primero; Esc = el
/// último). `field`: con un campo de texto (su valor queda en `text`). Siempre con `await`: se abre en la vuelta
/// siguiente del bucle principal (`MainTurn`), nunca dentro de la acción de un botón, donde el aviso no recibía los
/// clics y la app se quedaba colgada (Borrar en el explorador, 0.8.5).
@MainActor
enum ThemedAlert {
    struct Result: Sendable {
        var button: Int
        var text: String
    }

    @discardableResult
    static func run(_ title: String, message: String = "", buttons: [String], destructive: Int? = nil,
                    field: (placeholder: String, value: String, secure: Bool)? = nil) async -> Result {
        await MainTurn.next { present(title, message: message, buttons: buttons, destructive: destructive, field: field) }
    }

    /// Sí/no: true si se pulsa el primero.
    static func confirm(_ title: String, message: String = "", ok: String, cancel: String = L("Cancelar"),
                        destructive: Bool = false) async -> Bool {
        await run(title, message: message, buttons: [ok, cancel], destructive: destructive ? 0 : nil).button == 0
    }

    /// El aviso de verdad, al momento (sólo desde `run`, ya fuera de cualquier acción).
    private static func present(_ title: String, message: String, buttons: [String], destructive: Int?,
                                field: (placeholder: String, value: String, secure: Bool)?) -> Result {
        let theme = AppModel.instance?.uiTheme ?? .builtIn
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
        if let parent = AppModel.instance?.window ?? NSApp.keyWindow {
            let f = parent.frame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY - panel.frame.height / 2 + f.height / 6))
        } else {
            panel.center()
        }
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return Result(button: box.button ?? buttons.count - 1, text: box.text)
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
                    .onSubmit { done(0) }
                }
                HStack(spacing: 8) {
                    Spacer()
                    ForEach(Array(buttons.enumerated()).reversed(), id: \.offset) { i, b in
                        NeonButton(title: b, icon: i == 0 ? (destructive == 0 ? "trash" : "checkmark") : "xmark",
                                   tint: i == destructive ? t.bad : (i == 0 ? t.accent : t.dim), active: i == 0) { done(i) }
                            .keyboardShortcut(i == 0 ? .defaultAction : (i == buttons.count - 1 ? .cancelAction : nil))
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
