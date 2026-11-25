import Testing
@testable import NetDeckCore

@Suite struct ToolbarLayoutTests {
    @Test func todoVisiblePorDefecto() {
        let l = ToolbarLayout()
        #expect(ToolbarLayout.catalog.allSatisfy(l.isVisible))
        #expect(l.encoded.isEmpty)
    }

    /// Los ids no cambian: lo que el usuario ya tiene oculto sigue oculto.
    @Test func idsEstables() {
        #expect(ToolbarButton.allCases.map(\.rawValue) == [
            "NuevaLocal", "PegarSeguro", "Macros", "Tuneles", "DividirTerminal", "Llavero", "MultiExec",
            "BuscarTerminal", "Espacios", "ExploradorSFTP", "MostrarSesiones",
        ])
        #expect(ToolbarLayout.storageKey == "ndToolbarOcultos")
    }

    @Test func leeLoGuardadoYDescartaLoQueSobra() {
        let l = ToolbarLayout(stored: ["Macros", "Macros", "Inventado", "", "Tuneles"])
        #expect(l.hidden == [.macros, .tuneles])          // (sin repetidos ni desconocidos)
        #expect(ToolbarLayout(stored: nil).hidden.isEmpty)
    }

    /// «EditarRemoto» (Windows) y «PanelSFTP» (Mac) eran dos botones del mismo explorador: ahora es uno.
    @Test func migraLosIdsAntiguosDelExplorador() {
        #expect(ToolbarLayout(stored: ["EditarRemoto"]).hidden == [.exploradorSFTP])
        #expect(ToolbarLayout(stored: ["PanelSFTP"]).hidden == [.exploradorSFTP])
        #expect(ToolbarLayout(stored: ["PanelSFTP", "Macros"]).hidden == [.macros, .exploradorSFTP])
        // (oculto si cualquiera de los dos lo estaba, y sin duplicados al guardar)
        let l = ToolbarLayout(stored: ["EditarRemoto", "PanelSFTP", "ExploradorSFTP"])
        #expect(l.encoded == ["ExploradorSFTP"])
        #expect(ToolbarLayout(stored: l.encoded) == l)
    }

    @Test func ocultarYMostrar() {
        var l = ToolbarLayout()
        l.setVisible(.llavero, false)
        l.setVisible(.buscarTerminal, false)
        #expect(!l.isVisible(.llavero))
        #expect(l.isVisible(.macros))
        l.setVisible(.llavero, true)
        #expect(l.isVisible(.llavero) && !l.isVisible(.buscarTerminal))
    }

    @Test func codificarEsEstableYVuelve() {
        var l = ToolbarLayout()
        l.setVisible(.mostrarSesiones, false)
        l.setVisible(.macros, false)
        #expect(l.encoded == ["Macros", "MostrarSesiones"])  // (en el orden de la barra, no el de ocultar)
        #expect(ToolbarLayout(stored: l.encoded) == l)
    }

    @Test func todosTienenTitulo() {
        #expect(ToolbarButton.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(Set(ToolbarButton.allCases.map(\.title)).count == ToolbarButton.allCases.count)
    }
}
