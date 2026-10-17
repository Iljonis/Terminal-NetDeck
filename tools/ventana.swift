// tools/ventana.swift PID — el rectángulo (x,y,ancho,alto, en puntos de pantalla) de la ventana principal de ese
// proceso, para `screencapture -R` (tools/verificar_demo.sh): así salen también sus menús, que son otras ventanas.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int(CommandLine.arguments[1]) else { exit(2) }
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
let rects = mine.compactMap { w -> CGRect? in
    guard let b = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: b as CFDictionary)
}
guard let main = rects.max(by: { $0.width * $0.height < $1.width * $1.height }) else { exit(1) }
print("\(Int(main.minX)),\(Int(main.minY)),\(Int(main.width)),\(Int(main.height))")
