// tools/imagen_social.swift [captura] [salida] — la imagen social de GitHub (1280 × 640, Settings → Social preview) a
// partir de una captura de la demo: nombre y frase a la izquierda, la captura a la derecha. Sin dependencias.
//   swift tools/imagen_social.swift docs/capturas/portada-en.png docs/capturas/social-preview.png
import AppKit

let a = CommandLine.arguments
let entrada = a.count > 1 ? a[1] : "docs/capturas/portada-en.png"
let salida = a.count > 2 ? a[2] : "docs/capturas/social-preview.png"
guard let captura = NSImage(contentsOfFile: entrada) else { print("✗ no se puede leer \(entrada)"); exit(1) }

let ancho = 1280, alto = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: ancho, pixelsHigh: alto, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: ancho, height: alto)                 // (1 punto = 1 píxel)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ alfa: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255, alpha: alfa)
}
let rosa = color(0xFF2E88), cian = color(0x5CE1F0), fondo = color(0x0A0D22), texto = color(0xE8ECF8)

// Fondo con un degradado suave y la línea rosa de la barra de la app
NSGradient(starting: color(0x12163A), ending: fondo)!.draw(in: NSRect(x: 0, y: 0, width: ancho, height: alto), angle: -90)
rosa.setFill(); NSRect(x: 0, y: alto - 6, width: ancho, height: 6).fill()

// La captura, a la derecha, con borde y esquinas redondeadas (se corta a propósito por el borde derecho)
let marco = NSRect(x: 560, y: 95, width: 790, height: 790 * captura.size.height / captura.size.width)
NSGraphicsContext.saveGraphicsState()
let sombra = NSShadow(); sombra.shadowColor = rosa.withAlphaComponent(0.45); sombra.shadowBlurRadius = 40
sombra.set()
fondo.setFill(); NSBezierPath(roundedRect: marco, xRadius: 14, yRadius: 14).fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: marco, xRadius: 14, yRadius: 14).addClip()
captura.draw(in: marco, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
rosa.withAlphaComponent(0.8).setStroke()
let borde = NSBezierPath(roundedRect: marco, xRadius: 14, yRadius: 14); borde.lineWidth = 2; borde.stroke()

// Los textos, a la izquierda (`arriba`: distancia desde el borde de arriba, que es donde empieza el texto)
func escribir(_ s: String, _ arriba: CGFloat, _ fuente: NSFont, _ c: NSColor, kern: CGFloat = 0) {
  let p = NSMutableParagraphStyle(); p.lineSpacing = 6
  NSAttributedString(string: s, attributes: [.font: fuente, .foregroundColor: c, .kern: kern, .paragraphStyle: p])
    .draw(with: NSRect(x: 64, y: CGFloat(alto) - arriba - 200, width: 470, height: 200), options: [.usesLineFragmentOrigin])
}
let mono = { (t: CGFloat, w: NSFont.Weight) in NSFont.monospacedSystemFont(ofSize: t, weight: w) }
escribir("TERMINAL", 92, mono(28, .semibold), cian, kern: 10)
escribir("NetDeck", 122, NSFont.systemFont(ofSize: 86, weight: .heavy), texto)
escribir("The native macOS SSH terminal\nfor network engineers", 238, NSFont.systemFont(ofSize: 30, weight: .semibold), texto)
escribir("Jump hosts · Keychain passwords\nMultiExec · Safe paste · SFTP/FTP\nHighlighting for Cisco · Juniper · Nokia",
         352, mono(19, .regular), color(0xA9B4D6))
escribir("Free & open source · MIT · macOS 15+", 510, mono(19, .semibold), rosa)

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: URL(fileURLWithPath: salida))) != nil
else { print("✗ no se puede escribir \(salida)"); exit(1) }
print("✓ \(salida) (\(ancho) × \(alto))")
