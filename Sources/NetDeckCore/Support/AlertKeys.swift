import Foundation

/// Qué botón de un aviso pulsan Intro y Esc (`ThemedAlert`). Intro, el primero; Esc, el último. Nunca el destructivo:
/// con «Sobrescribir» o «Borrar» delante, Intro no hace nada, y con «Aceptar y Actualizar Clave» al final (la clave
/// del equipo ha cambiado), Esc tampoco. Así un Intro o un Esc de más no borra ni acepta nada.
public enum AlertKeys {
    public static func shortcuts(buttons: Int, destructive: Int?) -> (enter: Int?, escape: Int?) {
        guard buttons > 0 else { return (nil, nil) }
        let last = buttons - 1
        return (destructive == 0 ? nil : 0, last == 0 || last == destructive ? nil : last)
    }
}
