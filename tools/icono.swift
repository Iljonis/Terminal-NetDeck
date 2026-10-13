// icono.swift — dibuja el icono de la app (neón cyberpunk) en un .iconset: swiftc icono.swift && ./icono DIR
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.09
    let r = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: r, xRadius: r.width * 0.22, yRadius: r.width * 0.22)
    NSGradient(colors: [color(0x1a1740), color(0x07061a)])!.draw(in: shape, angle: -90)
    // rejilla
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    color(0xff2e88, 0.18).setStroke()
    for i in 1..<8 {
        let y = r.minY + r.height * CGFloat(i) / 16
        let p = NSBezierPath(); p.move(to: NSPoint(x: r.minX, y: y)); p.line(to: NSPoint(x: r.maxX, y: y))
        p.lineWidth = max(1, s / 256); p.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    // borde de neón
    let glow = NSShadow(); glow.shadowColor = color(0x00e5ff); glow.shadowBlurRadius = s * 0.04; glow.set()
    color(0x00e5ff, 0.9).setStroke()
    shape.lineWidth = s * 0.018
    shape.stroke()
    // «>_»
    let font = NSFont.monospacedSystemFont(ofSize: s * 0.36, weight: .black)
    let shadow = NSShadow(); shadow.shadowColor = color(0xff2e88); shadow.shadowBlurRadius = s * 0.05
    let text = NSAttributedString(string: ">_", attributes: [.font: font, .foregroundColor: color(0x00e5ff), .shadow: shadow])
    let ts = text.size()
    text.draw(at: NSPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2 + s * 0.04))
    // «ND»
    let small = NSAttributedString(string: "NETDECK", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: s * 0.075, weight: .bold), .foregroundColor: color(0xff2e88), .kern: s * 0.01])
    let ss = small.size()
    small.draw(at: NSPoint(x: r.midX - ss.width / 2, y: r.minY + r.height * 0.12))
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for (size, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for k in scales {
        let name = "icon_\(size)x\(size)\(k == 2 ? "@2x" : "").png"
        try! draw(size * k).write(to: out.appendingPathComponent(name))
    }
}
