import SwiftUI

extension View {
    /// Lo que se pulsa con un gesto propio (pestañas, filas de la lista, la «VISTA»): para VoiceOver, un botón con su
    /// nombre y su estado; con el teclado (Tab, con «Navegación con teclado» en Ajustes del Sistema), espacio o Intro.
    /// Sin cambiar el aspecto: un clic no le da el foco (`.activate`), así que el terminal no pierde el teclado.
    /// `actions`: las de su menú de clic derecho que VoiceOver ofrece con «Acciones» (⌃⌥⌘espacio).
    func pressable(_ label: String, value: String = "", selected: Bool = false,
                   actions: [(String, () -> Void)] = [], action: @escaping () -> Void) -> some View {
        modifier(Pressable(label: label, value: value, selected: selected, actions: actions, action: action))
    }
}

private struct Pressable: ViewModifier {
    let label: String
    let value: String
    let selected: Bool
    let actions: [(String, () -> Void)]
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, action)
            .accessibilityActions {
                ForEach(actions.indices, id: \.self) { i in Button(actions[i].0, action: actions[i].1) }
            }
            .focusable(interactions: .activate)
            .onKeyPress(keys: [.space, .return]) { _ in
                action()
                return .handled
            }
    }
}
