import CoreGraphics
import Foundation

/// abiertas.json: las pestañas de cada ventana al salir (o al actualizar), para volver a abrirlas cada una en su ventana
/// y en su sitio. Lee también el formato de antes (una lista de pestañas: una sola ventana).
public struct OpenWindows: Codable, Hashable, Sendable {
    public struct Window: Codable, Hashable, Sendable {
        public var tabs: [ConnectionRoute]
        /// Dónde estaba (coordenadas de pantalla de macOS, origen abajo a la izquierda); nil = donde toque.
        public var frame: CGRect?

        public init(tabs: [ConnectionRoute], frame: CGRect? = nil) {
            self.tabs = tabs
            self.frame = frame
        }

        enum CodingKeys: String, CodingKey {
            case tabs = "pestañas"
            case frame = "marco"
        }
    }

    public var windows: [Window]

    public init(windows: [Window] = []) { self.windows = windows }

    enum CodingKeys: String, CodingKey {
        case windows = "ventanas"
    }

    /// Todas las pestañas, ventana a ventana.
    public var tabs: [ConnectionRoute] { windows.flatMap(\.tabs) }
    public var isEmpty: Bool { tabs.isEmpty }

    /// Sin las pestañas a este mismo Mac (127.x/localhost) y sin ventanas que se queden vacías.
    public func withoutLoopback() -> OpenWindows {
        OpenWindows(windows: windows.compactMap { w in
            let kept = w.tabs.filter { !$0.isLoopback }
            return kept.isEmpty ? nil : Window(tabs: kept, frame: w.frame)
        })
    }

    /// El formato de ahora o el de antes; nil si no es ninguno de los dos.
    public static func decode(_ data: Data) -> OpenWindows? {
        let d = JSONDecoder()
        if let now = try? d.decode(OpenWindows.self, from: data) { return now }
        if let old = try? d.decode([ConnectionRoute].self, from: data) { return OpenWindows(windows: [Window(tabs: old)]) }
        return nil
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
}

/// Dónde abrir una ventana: entera dentro de una pantalla (la que toca), sin taparse con la barra de menús ni el Dock.
/// Coordenadas de pantalla de macOS (origen abajo a la izquierda); `screens`, los `visibleFrame` de cada pantalla.
public enum WindowPlacement {
    /// Una ventana nueva con la pestaña soltada en `point`: queda con su barra de pestañas bajo el puntero (`grab`: dónde
    /// cae el puntero, medido desde arriba a la izquierda de la ventana), en la pantalla en la que se ha soltado.
    public static func frame(droppingAt point: CGPoint, size: CGSize, grab: CGPoint, screens: [CGRect]) -> CGRect {
        let wanted = CGRect(x: point.x - grab.x, y: point.y + grab.y - size.height, width: size.width, height: size.height)
        guard let screen = screens.first(where: { $0.contains(point) }) ?? nearest(to: point, in: screens) else { return wanted }
        return fit(wanted, in: screen)
    }

    /// Un marco guardado, si la pantalla en la que estaba sigue ahí (al menos su centro); si no, nil: que la ventana salga
    /// donde macOS la ponga.
    public static func restored(_ frame: CGRect, screens: [CGRect]) -> CGRect? {
        guard frame.width >= 1, frame.height >= 1,
              let screen = screens.first(where: { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }) else { return nil }
        return fit(frame, in: screen)
    }

    /// Dentro de `screen`: si es más grande, se encoge; si se sale, se mete.
    public static func fit(_ r: CGRect, in screen: CGRect) -> CGRect {
        let w = min(r.width, screen.width), h = min(r.height, screen.height)
        let x = min(max(r.minX, screen.minX), screen.maxX - w)
        let y = min(max(r.minY, screen.minY), screen.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func nearest(to p: CGPoint, in screens: [CGRect]) -> CGRect? {
        func distance(_ r: CGRect) -> CGFloat {
            let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
            return dx * dx + dy * dy
        }
        return screens.min { distance($0) < distance($1) }
    }
}
