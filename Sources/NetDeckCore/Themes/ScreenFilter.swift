import Foundation

/// Filtro de pantalla encima del terminal (1.0.0): un dibujo fijo (líneas, rejilla, velo, bordes) que se pinta al
/// cambiar de tamaño o de filtro, nunca con el texto que entra. En los .tema, «filtro = crt|lcd|fosforo|holograma»:
/// es el de «Automático» en Ajustes.
public enum ScreenFilter: String, CaseIterable, Sendable {
    case none = "ninguno", crt, lcd, phosphor = "fosforo", hologram = "holograma"

    /// En Ajustes: el del tema (lo que se guarda en vez de un filtro).
    public static let automatic = "auto"
    /// Intensidad: de serie, moderada; ni con la máxima tapa el texto (`look`).
    public static let defaultIntensity = 0.5
    public static let intensityRange = 0.1...1.0

    /// Lo que pone un .tema, sin mayúsculas ni tildes («Fósforo», «CRT»); «no» o «ninguna», ninguno. Lo que no se
    /// entiende (o no está), nil: como si el tema no llevara filtro.
    public init?(tema: String?) {
        guard let t = tema?.trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil), !t.isEmpty
        else { return nil }
        self.init(rawValue: ["no", "ninguna", "none"].contains(t) ? "ninguno" : t)
    }

    public var name: String {
        switch self {
        case .none: L("Ninguno")
        case .crt: L("CRT")
        case .lcd: L("LCD")
        case .phosphor: L("Fósforo")
        case .hologram: L("Holograma")
        }
    }

    /// La de Ajustes, dentro de lo que se deja elegir (lo de fuera, al borde; algo que no es un número, la de serie).
    public static func intensity(_ v: Double) -> Double {
        v.isFinite ? min(max(v, intensityRange.lowerBound), intensityRange.upperBound) : defaultIntensity
    }

    /// El de una pestaña: ninguno si está apagado (⌥⌘F) o si el Mac pide calma («Reducir movimiento», «Reducir
    /// transparencia» o «Aumentar contraste»); con «auto», el de su tema (sin `filtro =`, ninguno); si no, el elegido
    /// (un valor guardado que no se entiende cuenta como «auto»).
    public static func resolve(choice: String, on: Bool, theme: ScreenFilter?, calm: Bool) -> ScreenFilter {
        guard on, !calm else { return .none }
        return ScreenFilter(rawValue: choice) ?? theme ?? .none
    }

    /// Cómo se pinta con esta intensidad y los colores de la pestaña (nil = nada encima). Los alfas van a escala de la
    /// intensidad y, con la máxima, ninguno pasa de 0,35 (las líneas), 0,12 (los velos) ni 0,4 (los bordes): el texto se lee.
    public func look(intensity: Double, text: RGB) -> ScreenLook? {
        let k = Self.intensity(intensity)
        switch self {
        case .none:
            return nil
        case .crt:                      // barrido cada 3 puntos, bordes oscuros y las esquinas del tubo
            return ScreenLook(scan: .init(every: 3, width: 1, color: .black.alpha(0.30 * k)),
                              vignette: 0.40 * k, curve: 10)
        case .lcd:                      // rejilla de píxeles y el velo de los apagados («fantasma»)
            return ScreenLook(grid: .init(every: 3, width: 1, color: .black.alpha(0.26 * k)),
                              tint: text.opaque.alpha(0.06 * k), vignette: 0.15 * k)
        case .phosphor:                 // barrido fino y resplandor del color del texto desde el centro
            return ScreenLook(scan: .init(every: 2, width: 1, color: .black.alpha(0.22 * k)),
                              glow: text.opaque.alpha(0.10 * k), vignette: 0.25 * k)
        case .hologram:                 // líneas claras muy suaves y un tono frío
            return ScreenLook(scan: .init(every: 4, width: 1, color: RGB(140, 225, 255, 0.08 * k)),
                              tint: RGB(60, 150, 255, 0.07 * k))
        }
    }
}

/// Lo que dibuja un filtro, de abajo arriba: velo, resplandor, líneas, rejilla, bordes y esquinas.
public struct ScreenLook: Equatable, Sendable {
    /// Una línea de `width` puntos cada `every`, de `color` (con su alfa).
    public struct Lines: Equatable, Sendable {
        public var every: Double
        public var width: Double
        public var color: RGB
    }

    /// Barrido (líneas horizontales).
    public var scan: Lines?
    /// Rejilla de píxeles (horizontales y verticales).
    public var grid: Lines?
    /// Velo de color en toda la pantalla.
    public var tint: RGB?
    /// Resplandor desde el centro, que se apaga hacia los bordes.
    public var glow: RGB?
    /// Oscuro en los bordes: el alfa en las esquinas.
    public var vignette = 0.0
    /// Radio de las esquinas redondeadas del tubo, en puntos (0 = rectas).
    public var curve = 0.0

    public init(scan: Lines? = nil, grid: Lines? = nil, tint: RGB? = nil, glow: RGB? = nil, vignette: Double = 0, curve: Double = 0) {
        self.scan = scan
        self.grid = grid
        self.tint = tint
        self.glow = glow
        self.vignette = vignette
        self.curve = curve
    }
}
