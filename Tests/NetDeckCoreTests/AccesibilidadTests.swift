import Testing
@testable import NetDeckCore

@Suite struct AccesibilidadTests {
    /// El nombre de un botón de icono para VoiceOver, sacado de su ayuda (la ayuda entera queda de pista).
    @Test func nombreDesdeLaAyuda() {
        #expect(AccessibilityText.label(fromHelp: "Pegado seguro: revisa líneas peligrosas antes de enviarlas (⇧⌘V)") == "Pegado seguro")
        #expect(AccessibilityText.label(fromHelp: "Ajustes (⌘,)") == "Ajustes")
        #expect(AccessibilityText.label(fromHelp: "Mostrar/ocultar sesiones (⌃⌘S)") == "Mostrar/ocultar sesiones")
        #expect(AccessibilityText.label(fromHelp: "Pantalla dividida · clic derecho: volver") == "Pantalla dividida")
        #expect(AccessibilityText.label(fromHelp: "Safe paste: review dangerous lines (⇧⌘V)") == "Safe paste")
        #expect(AccessibilityText.label(fromHelp: "Borrar") == "Borrar")
        // (lo que empieza por el corte se queda entero: mejor largo que vacío)
        #expect(AccessibilityText.label(fromHelp: ": raro") == ": raro")
    }
}
