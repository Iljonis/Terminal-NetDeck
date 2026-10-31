import Testing
@testable import NetDeckCore

/// Intro y Esc en los avisos (`ThemedAlert`): nunca pulsan el botón destructivo.
struct AvisosTests {
    @Test func introYEscNuncaPulsanElDestructivo() {
        // (sin destructivo, como siempre: Intro el primero, Esc el último)
        #expect(AlertKeys.shortcuts(buttons: 2, destructive: nil) == (0, 1))
        #expect(AlertKeys.shortcuts(buttons: 3, destructive: nil) == (0, 2))
        #expect(AlertKeys.shortcuts(buttons: 1, destructive: nil) == (0, nil))
        // «Sobrescribir» / «Borrar» delante: Intro no hace nada, Esc sigue siendo Cancelar
        #expect(AlertKeys.shortcuts(buttons: 2, destructive: 0) == (nil, 1))
        #expect(AlertKeys.shortcuts(buttons: 3, destructive: 0) == (nil, 2))
        // «Añadir · Sustituir · Cancelar»: el del medio no lleva atajo
        #expect(AlertKeys.shortcuts(buttons: 3, destructive: 1) == (0, 2))
        // «Cancelar · Aceptar y Actualizar Clave»: Esc cancela (ya no acepta la clave nueva) e Intro no hace nada
        #expect(AlertKeys.shortcuts(buttons: 2, destructive: 1) == (nil, 0))
        #expect(AlertKeys.shortcuts(buttons: 0, destructive: nil) == (nil, nil))
    }
}
