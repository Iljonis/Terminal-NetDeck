import Foundation
import NetDeckCore
import struct UWP.Color
import struct UWP.FontWeight
import WinUI

/// El marco de la ventana como el del Mac (barra con pestañas e iconos, barra lateral, barra de estado): los colores
/// salen del tema elegido, como allí; sin tema, los de Liquid Glass.
struct EstiloMac {
    static let idPorDefecto = "liquid-glass"
    static var fuenteInterfaz = FontFamily("Segoe UI Variable, Segoe UI")
    static let fuenteIconos = FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")

    let tema: Theme
    let fondo: SolidColorBrush
    let barra: SolidColorBrush
    let panel: SolidColorBrush
    let pestana: SolidColorBrush
    let sobrePestana: SolidColorBrush
    let acento: SolidColorBrush
    let acento2: SolidColorBrush
    let bien: SolidColorBrush
    let mal: SolidColorBrush
    let especial: SolidColorBrush
    let aviso: SolidColorBrush
    let apagado: SolidColorBrush
    let texto: SolidColorBrush
    let linea: SolidColorBrush
    let transparente = SolidColorBrush(Color(a: 0, r: 0, g: 0, b: 0))

    init(tema elegido: Theme?) {
        // Opaco: WinUI pinta el terminal con fondo liso, y así las barras no dependen de lo que haya detrás.
        let t = (elegido ?? TemasTerminal.tema(id: Self.idPorDefecto) ?? Theme.builtIn).solid
        tema = t
        fondo = Self.pincel(t.background)
        barra = Self.pincel(t.bar)
        panel = Self.pincel(t.panel)
        pestana = Self.pincel(t.tab)
        sobrePestana = Self.pincel(t.onTab)
        acento = Self.pincel(t.accent)
        acento2 = Self.pincel(t.accent2)
        bien = Self.pincel(t.good)
        mal = Self.pincel(t.bad)
        especial = Self.pincel(t.special)
        aviso = Self.pincel(t.warning)
        apagado = Self.pincel(t.dim)
        texto = Self.pincel(t.text)
        linea = Self.pincel(t.line)
    }

    static func pincel(_ c: RGB, alfa: Double = 1) -> SolidColorBrush {
        func canal(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        return SolidColorBrush(Color(a: canal(255 * alfa * c.a), r: canal(c.r), g: canal(c.g), b: canal(c.b)))
    }

    static func color(_ c: RGB) -> Color {
        func canal(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        return Color(a: 255, r: canal(c.r), g: canal(c.g), b: canal(c.b))
    }

    func panel(alfa: Double) -> SolidColorBrush { Self.pincel(tema.panel, alfa: alfa) }
    func acento(alfa: Double) -> SolidColorBrush { Self.pincel(tema.accent, alfa: alfa) }

    static func radio(_ r: Double) -> CornerRadius { CornerRadius(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }

    static func icono(_ glifo: String, tamano: Double = 14, color: Brush? = nil) -> TextBlock {
        let t = TextBlock()
        t.text = glifo
        t.fontFamily = fuenteIconos
        t.fontSize = tamano
        t.verticalAlignment = .center
        t.horizontalAlignment = .center
        if let color { t.foreground = color }
        return t
    }

    static func letra(_ texto: String, tamano: Double, peso: UInt16 = 400, color: Brush? = nil) -> TextBlock {
        let t = TextBlock()
        t.text = texto
        t.fontSize = tamano
        t.fontFamily = fuenteInterfaz
        t.fontWeight = FontWeight(weight: peso)
        t.verticalAlignment = .center
        t.textTrimming = .characterEllipsis
        if let color { t.foreground = color }
        return t
    }

    /// Un botón de la barra de iconos (32×28, esquinas de 6, relleno del panel al 40 %), con su ayuda al pasar el ratón.
    func vestirIcono(_ boton: Button, _ glifo: String, ayuda: String, id: String, tinte: SolidColorBrush? = nil) {
        boton.content = Self.icono(glifo, tamano: 14, color: tinte ?? texto)
        boton.minWidth = 32
        boton.height = 28
        boton.padding = Thickness(left: 8, top: 0, right: 8, bottom: 0)
        boton.cornerRadius = Self.radio(6)
        boton.background = panel(alfa: 0.4)
        boton.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        boton.verticalAlignment = .center
        ToolTipService.setToolTip(boton, ayuda)
        AutomationProperties.setName(boton, ayuda)
        AutomationProperties.setAutomationId(boton, id)
    }

    func botonIcono(_ glifo: String, ayuda: String, id: String, tinte: SolidColorBrush? = nil,
                    accion: @escaping () -> Void) -> Button {
        let b = Button()
        vestirIcono(b, glifo, ayuda: ayuda, id: id, tinte: tinte)
        b.click.addHandler { _, _ in accion() }
        return b
    }

    /// Botón plano (sin borde ni relleno): filas de la barra lateral y pie.
    func plano(_ boton: Button) {
        boton.background = transparente
        boton.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        boton.cornerRadius = Self.radio(6)
        boton.horizontalAlignment = .stretch
        boton.horizontalContentAlignment = .stretch
    }

    /// Con el ratón encima o pulsado, la plantilla de Button pone su gris y pisa el color del tema (la pestaña elegida se
    /// veía gris al hacer clic): se fijan los colores de esos dos estados en el propio botón.
    static func conservarColores(_ boton: Button, encima: SolidColorBrush, pulsado: SolidColorBrush, borde: SolidColorBrush? = nil) {
        guard let recursos = boton.resources else { return }
        _ = recursos.insert("ButtonBackgroundPointerOver", encima)
        _ = recursos.insert("ButtonBackgroundPressed", pulsado)
        if let borde {
            _ = recursos.insert("ButtonBorderBrushPointerOver", borde)
            _ = recursos.insert("ButtonBorderBrushPressed", borde)
        }
    }
}

/// Glifos de Segoe Fluent Icons (los equivalentes de los SF Symbols del Mac).
enum Glifo {
    static let mas = "\u{E710}"
    static let terminal = "\u{E756}"
    static let pegar = "\u{E77F}"
    static let grabar = "\u{E7C8}"
    static let tuneles = "\u{E968}"
    static let dividir = "\u{E8A9}"
    static let llave = "\u{E8D7}"
    static let multiExec = "\u{E762}"
    static let parar = "\u{E71A}"
    static let buscar = "\u{E721}"
    static let espacios = "\u{E8F1}"
    static let editar = "\u{E70F}"
    static let barraLateral = "\u{E8A0}"
    static let ajustes = "\u{E713}"
    static let cerrar = "\u{E711}"
    static let importar = "\u{E896}"
    static let recargar = "\u{E72C}"
    static let carpeta = "\u{E8B7}"
    static let carpetaAbierta = "\u{E838}"
    static let flechaDerecha = "\u{E76C}"
    static let flechaAbajo = "\u{E70D}"
    static let estrella = "\u{E735}"
    static let encendido = "\u{E7E8}"
    static let recientes = "\u{E81C}"
    static let lista = "\u{E700}"
    static let red = "\u{E839}"
    static let serie = "\u{E88E}"
    static let disco = "\u{E8F7}"
    static let salto = "\u{E72A}"
    static let conectar = "\u{E703}"
}
