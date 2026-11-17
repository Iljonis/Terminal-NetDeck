import Foundation
import NetDeckCore
import SwiftTerm

/// Los temas de NetDeckCore aplicados al terminal de Windows: de donde salen, y los colores que usa el terminal.
enum TemasTerminal {
    /// Clave de UserDefaults. Guarda el **id** del tema (estable), no su nombre visible, que puede traducirse; vacio = sin tema.
    static let clave = "ndTemaNombre"

    /// La carpeta «Temas» de la app: junto al exe (el instalador la lleva) o la de NETDECK_TEMAS (desarrollo).
    static var carpeta: URL? {
        let fm = FileManager.default
        if let ruta = ProcessInfo.processInfo.environment["NETDECK_TEMAS"], !ruta.isEmpty, fm.fileExists(atPath: ruta) {
            return URL(fileURLWithPath: ruta, isDirectory: true)
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent()
        let junto = exe.appendingPathComponent("Temas", isDirectory: true)
        return fm.fileExists(atPath: junto.path) ? junto : nil
    }

    static func biblioteca() -> ThemeLibrary { ThemeLibrary(appDirectory: carpeta) }

    /// Todos los disponibles, en el orden de NetDeck (siempre esta el original, `Theme.builtIn`).
    static func disponibles() -> [Theme] { biblioteca().all().map(\.theme) }

    static func tema(id: String) -> Theme? { id.isEmpty ? nil : biblioteca().theme(id: id) }
}

/// Un trozo de una linea de la pantalla con un solo color de texto (nil = el de por defecto).
struct SegmentoColor: Equatable {
    var texto: String
    var color: RGB?
}

/// Los colores de un tema para el terminal: fondo, texto, cursor y los 16 ANSI (todos opacos).
struct PaletaTerminal: Equatable {
    var ansi: [RGB]
    var texto: RGB
    var fondo: RGB
    var cursor: RGB

    init(tema: Theme) {
        let t = tema.solid                       // (sin transparencias: el terminal pinta sobre un fondo liso)
        ansi = t.ansi
        texto = t.text.opaque
        fondo = t.background.opaque
        cursor = t.cursor.opaque
    }

    /// El color de una celda: nil si es el de por defecto.
    func color(_ c: Attribute.Color) -> RGB? {
        switch c {
        case .defaultColor:
            return nil
        case .defaultInvertedColor:
            return fondo
        case .trueColor(let r, let g, let b):
            return RGB(Double(r), Double(g), Double(b))
        case .ansi256(let code):
            let n = Int(code)
            if n < 16 { return ansi.indices.contains(n) ? ansi[n] : nil }
            if n < 232 {                          // cubo 6x6x6
                func nivel(_ x: Int) -> Double { x == 0 ? 0 : Double(55 + 40 * x) }
                let i = n - 16
                return RGB(nivel(i / 36), nivel((i / 6) % 6), nivel(i % 6))
            }
            let gris = Double(8 + 10 * (n - 232))  // 24 grises
            return RGB(gris, gris, gris)
        }
    }

    /// Los colores de SwiftTerm: de 0 a 255 por canal.
    static func swiftTerm(_ c: RGB) -> SwiftTerm.Color {
        func canal(_ v: Double) -> UInt16 { UInt16(max(0, min(255, v.rounded()))) }
        return SwiftTerm.Color(red8: canal(c.r), green8: canal(c.g), blue8: canal(c.b))
    }
}
