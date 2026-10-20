// tools/ventana.swift PID — el número de la ventana principal de ese proceso, para `screencapture -l` (tools/
// verificar_demo.sh): sale sólo esa ventana, nunca lo de otras apps que haya encima o detrás (un rectángulo de la
// pantalla sí podría llevarlo). Sus menús, aparte: los captura la propia app («-menu.png»).
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int(CommandLine.arguments[1]) else { exit(2) }
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
let windows = mine.compactMap { w -> (id: Int, area: CGFloat)? in
    guard let id = w[kCGWindowNumber as String] as? Int, let b = w[kCGWindowBounds as String] as? NSDictionary,
          let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return nil }
    return (id, r.width * r.height)
}
guard let main = windows.max(by: { $0.area < $1.area }) else { exit(1) }
print(main.id)
