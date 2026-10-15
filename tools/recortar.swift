// tools/recortar.swift entrada salida alto — deja sólo la franja de arriba (`alto` px) de una captura (tools/capturas.sh).
import AppKit
let a = CommandLine.arguments
guard a.count == 4, let h = Int(a[3]), let img = NSImage(contentsOfFile: a[1]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let top = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: min(h, cg.height))) else { exit(1) }
let rep = NSBitmapImageRep(cgImage: top)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
