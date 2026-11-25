import Foundation

/// Un botón configurable de la barra superior. El `rawValue` es el id que se guarda (y el de accesibilidad en
/// Windows): no se cambia, o se pierde lo que el usuario ya tiene oculto. El orden de `allCases` es el de la barra
/// y el de Ajustes → General → «Barra superior» en las dos apps.
public enum ToolbarButton: String, CaseIterable, Sendable, Identifiable {
    case nuevaLocal = "NuevaLocal"
    case pegarSeguro = "PegarSeguro"
    case macros = "Macros"
    case tuneles = "Tuneles"
    case dividirTerminal = "DividirTerminal"
    case llavero = "Llavero"
    case multiExec = "MultiExec"
    case buscarTerminal = "BuscarTerminal"
    case espacios = "Espacios"
    /// El explorador SFTP al lado del terminal (donde se elige un archivo y se edita). Sustituye a «EditarRemoto» y
    /// «PanelSFTP» (ver `ToolbarLayout.init(stored:)`).
    case exploradorSFTP = "ExploradorSFTP"
    case mostrarSesiones = "MostrarSesiones"

    public var id: String { rawValue }

    /// Su nombre en Ajustes.
    public var title: String {
        switch self {
        case .nuevaLocal: L("Nueva terminal local")
        case .pegarSeguro: L("Pegado seguro")
        case .macros: L("Macros")
        case .tuneles: L("Túneles SSH")
        case .dividirTerminal: L("Pantalla dividida")
        case .llavero: L("Contraseñas y Llavero")
        case .multiExec: L("MultiExec")
        case .buscarTerminal: L("Buscar")
        case .espacios: L("Espacios de trabajo")
        case .exploradorSFTP: L("Explorador SFTP")
        case .mostrarSesiones: L("Mostrar/ocultar sesiones")
        }
    }

    /// Los ids que se guardaron antes con otro nombre y ahora son éste.
    fileprivate static func migrated(_ id: String) -> ToolbarButton? {
        ["EditarRemoto", "PanelSFTP"].contains(id) ? .exploradorSFTP : ToolbarButton(rawValue: id)
    }
}

/// Qué botones configurables de la barra superior están ocultos (todo visible por defecto). No cubre lo que siempre
/// se ve: el «+», Ajustes y los controles de acciones activas (parar la grabación, detener el envío).
public struct ToolbarLayout: Equatable, Sendable {
    /// La clave en la que cada app guarda `encoded` (en Windows ya existía con este nombre).
    public static let storageKey = "ndToolbarOcultos"

    public private(set) var hidden: Set<ToolbarButton>

    /// Los botones configurables, en el orden de la barra (los mismos en las dos apps).
    public static var catalog: [ToolbarButton] { ToolbarButton.allCases }

    public init(hidden: some Sequence<ToolbarButton> = []) {
        self.hidden = Set(hidden)
    }

    /// Lo guardado (`encoded`): se descartan los ids desconocidos y los repetidos, y «EditarRemoto» o «PanelSFTP»
    /// (antiguos) pasan a «ExploradorSFTP»: oculto si cualquiera de los dos lo estaba.
    public init(stored: [String]?) {
        self.init(hidden: (stored ?? []).compactMap(ToolbarButton.migrated))
    }

    public func isVisible(_ button: ToolbarButton) -> Bool { !hidden.contains(button) }

    public mutating func setVisible(_ button: ToolbarButton, _ visible: Bool) {
        if visible { hidden.remove(button) } else { hidden.insert(button) }
    }

    /// Lo que se guarda: los ids de los ocultos, en el orden de la barra (estable entre guardados).
    public var encoded: [String] {
        ToolbarButton.allCases.filter(hidden.contains).map(\.rawValue)
    }
}
