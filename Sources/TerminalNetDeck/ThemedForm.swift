import AppKit
import NetDeckCore
import SwiftUI

// Formularios, botones, interruptores y campos con la temática: los de macOS (Form agrupado, NSButton, NSSwitch,
// NSTextField) salen grises y no se dejan pintar. Se ponen una vez arriba (`themedControls()`) y valen para todo lo de
// dentro que no diga otro estilo.

extension View {
    /// Botones, interruptores y campos de texto con el tema (para la ventana, las hojas y los paneles).
    func themedControls() -> some View {
        buttonStyle(ThemedButtonStyle())
            .toggleStyle(ThemedSwitchStyle())
            .textFieldStyle(ThemedTextFieldStyle())
            .labeledContentStyle(ThemedLabeledStyle())
    }
}

/// `Form` con tarjetas del tema (en vez de las grises de macOS): título de la sección, filas separadas con una raya
/// y el pie en pequeño.
struct ThemedFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        @Environment(\.theme) private var t
        let configuration: Configuration

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections: configuration.content) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            if !section.header.isEmpty {
                                section.header
                                    .font(t.ui(11, .bold)).tracking(t.tracking / 2)
                                    .foregroundStyle(SwiftUI.Color(t.accent2))
                                    .textCase(nil)
                                    .padding(.leading, 4)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(subviews: section.content) { row in
                                    if row.id != section.content.first?.id {
                                        Rectangle().fill(SwiftUI.Color(t.panel)).frame(height: 1)
                                    }
                                    row.padding(.vertical, 7).padding(.horizontal, 12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .font(t.ui(12))
                            .foregroundStyle(SwiftUI.Color(t.text))
                            .background(RoundedRectangle(cornerRadius: t.corner ?? 6).fill(SwiftUI.Color(t.panel).opacity(0.45)))
                            .overlay(RoundedRectangle(cornerRadius: t.corner ?? 6)
                                .strokeBorder(SwiftUI.Color(t.accent).opacity(t.neon ? 0.35 : 0.15)))
                            if !section.footer.isEmpty {
                                section.footer.font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim)).padding(.leading, 4)
                            }
                        }
                    }
                }
                .padding(18)
            }
            .scrollContentBackground(.hidden)
        }
    }
}

extension FormStyle where Self == ThemedFormStyle {
    static var themed: ThemedFormStyle { ThemedFormStyle() }
}

/// Etiqueta a la izquierda y el control a la derecha (filas de los formularios).
struct ThemedLabeledStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 10)
            configuration.content
        }
    }
}

/// Botón con el tema: borde fino del color de acento, se enciende al pasar por encima.
struct ThemedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        @Environment(\.theme) private var t
        @Environment(\.isEnabled) private var enabled
        let configuration: Configuration
        @Stored private var hover = false

        var body: some View {
            let c = configuration.role == .destructive ? t.bad : t.accent
            configuration.label
                .font(t.ui(12, .medium))
                .foregroundStyle(SwiftUI.Color(hover ? c : t.text))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 24)
                .background(RoundedRectangle(cornerRadius: t.corner ?? 5)
                    .fill(SwiftUI.Color(t.panel).opacity(configuration.isPressed ? 1 : (hover ? 0.9 : 0.6))))
                .overlay(RoundedRectangle(cornerRadius: t.corner ?? 5).strokeBorder(SwiftUI.Color(c).opacity(hover ? 0.85 : 0.3)))
                .shadow(color: SwiftUI.Color(c).opacity(hover ? 0.45 : 0), radius: t.glow(5))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hover = $0 && enabled }
        }
    }
}

/// Interruptor con el tema (el acento encendido, con brillo de neón).
struct ThemedSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        @Environment(\.theme) private var t
        @Environment(\.isEnabled) private var enabled
        let configuration: Configuration

        var body: some View {
            HStack(spacing: 10) {
                configuration.label
                Spacer(minLength: 10)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(SwiftUI.Color(configuration.isOn ? t.accent : t.panel))
                        .overlay(Capsule().strokeBorder(SwiftUI.Color(t.accent).opacity(configuration.isOn ? 0 : 0.4)))
                    Circle().fill(SwiftUI.Color(configuration.isOn ? t.accent.readable : t.dim)).padding(3)
                }
                .frame(width: 34, height: 19)
                .shadow(color: SwiftUI.Color(t.accent).opacity(configuration.isOn ? 0.6 : 0), radius: t.glow(5))
                .animation(.easeOut(duration: 0.12), value: configuration.isOn)
            }
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { configuration.isOn.toggle() } }
        }
    }
}

/// Casilla con el tema (las de «Guardar en el Llavero», listas…).
struct ThemedCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        @Environment(\.theme) private var t
        @Environment(\.isEnabled) private var enabled
        let configuration: Configuration

        var body: some View {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(SwiftUI.Color(configuration.isOn ? t.accent : t.panel))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(SwiftUI.Color(t.accent).opacity(0.6)))
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .black))
                                .foregroundStyle(SwiftUI.Color(t.accent.readable))
                        }
                    }
                    .frame(width: 14, height: 14)
                    .shadow(color: SwiftUI.Color(t.accent).opacity(configuration.isOn ? 0.5 : 0), radius: t.glow(4))
                configuration.label
            }
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { configuration.isOn.toggle() } }
        }
    }
}

extension ToggleStyle where Self == ThemedCheckboxStyle {
    static var themedCheckbox: ThemedCheckboxStyle { ThemedCheckboxStyle() }
}

/// Campo de texto con el tema: fondo oscuro/claro del tema y borde de acento al escribir.
struct ThemedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View { configuration.modifier(FieldChrome()) }

    private struct FieldChrome: ViewModifier {
        @Environment(\.theme) private var t
        @FocusState private var focused: Bool

        nonisolated init() {}

        func body(content: Content) -> some View {
            content
                .textFieldStyle(.plain)
                .font(t.ui(12.5))
                .foregroundStyle(SwiftUI.Color(t.text))
                .focused($focused)
                .padding(.horizontal, 7)
                .frame(minHeight: 24)
                .background(RoundedRectangle(cornerRadius: t.corner ?? 5).fill(SwiftUI.Color(t.background.opaque).opacity(0.75)))
                .overlay(RoundedRectangle(cornerRadius: t.corner ?? 5)
                    .strokeBorder(SwiftUI.Color(t.accent).opacity(focused ? 0.85 : 0.25)))
                .shadow(color: SwiftUI.Color(t.accent).opacity(focused ? 0.35 : 0), radius: t.glow(4))
        }
    }
}

/// Selector de pocas opciones (en vez del segmentado de macOS).
struct ThemedSegmented<Value: Hashable>: View {
    @Environment(\.theme) private var t
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    init(_ title: String = "", selection: Binding<Value>, options: [(value: Value, label: String)]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    init(_ title: String = "", selection: Binding<Value>, _ build: (inout [(value: Value, label: String)]) -> Void) {
        var o: [(value: Value, label: String)] = []
        build(&o)
        self.init(title, selection: selection, options: o)
    }

    var body: some View {
        HStack {
            if !title.isEmpty {
                Text(title)
                Spacer(minLength: 10)
            }
            HStack(spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                    let on = o.value == selection
                    Button { selection = o.value } label: {
                        Text(o.label).font(t.ui(11.5, .semibold)).lineLimit(1)
                            .foregroundStyle(SwiftUI.Color(on ? t.accent.readable : t.text))
                            .padding(.horizontal, 10).frame(minHeight: 22)
                            .background(RoundedRectangle(cornerRadius: t.corner ?? 4).fill(SwiftUI.Color(t.accent).opacity(on ? 1 : 0)))
                            .shadow(color: SwiftUI.Color(t.accent).opacity(on ? 0.5 : 0), radius: t.glow(4))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: (t.corner ?? 4) + 2).fill(SwiftUI.Color(t.panel).opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: (t.corner ?? 4) + 2).strokeBorder(SwiftUI.Color(t.accent).opacity(0.25)))
        }
    }
}

/// Editor de varias líneas con el tema.
extension View {
    func themedEditor() -> some View { modifier(EditorChrome()) }
}

private struct EditorChrome: ViewModifier {
    @Environment(\.theme) private var t

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: t.corner ?? 5).fill(SwiftUI.Color(t.background.opaque).opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: t.corner ?? 5).strokeBorder(SwiftUI.Color(t.accent).opacity(0.25)))
    }
}
