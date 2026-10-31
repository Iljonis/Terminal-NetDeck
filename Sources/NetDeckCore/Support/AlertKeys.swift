import Foundation

/// Qué botón de un aviso pulsan Intro y Esc (`ThemedAlert`). Intro, el primero; Esc, el último. Nunca el destructivo:
/// con «Sobrescribir» o «Borrar» delante, Intro no hace nada. Con «Aceptar y Actualizar Clave» al final (la clave del
/// equipo ha cambiado), Esc pulsa el primero («Cancelar»), como en macOS, e Intro nada (un botón, un atajo). Así un
/// Intro o un Esc de más no borra ni acepta nada.
public enum AlertKeys {
    public static func shortcuts(buttons: Int, destructive: Int?) -> (enter: Int?, escape: Int?) {
        guard buttons > 0 else { return (nil, nil) }
        let last = buttons - 1
        let enter = destructive == 0 ? nil : 0
        guard last > 0 else { return (enter, nil) }
        guard last == destructive else { return (enter, last) }
        return enter == 0 ? (nil, 0) : (enter, nil)
    }
}
