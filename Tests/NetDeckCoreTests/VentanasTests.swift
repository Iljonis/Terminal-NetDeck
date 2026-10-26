import CoreGraphics
import Foundation
import Testing
@testable import NetDeckCore

@Suite struct VentanasTests {
    static let core = ConnectionRoute(title: "core-01", target: Endpoint(user: "tu.usuario", host: "192.0.2.11"))
    static let pe = ConnectionRoute(title: "pe-02", target: Endpoint(user: "tu.usuario", host: "198.51.100.2"))
    static let yo = ConnectionRoute(title: "yo", target: Endpoint(host: "127.0.0.1"))

    @Test func abiertasPorVentanaYDeVuelta() throws {
        let w = OpenWindows(windows: [.init(tabs: [Self.core, Self.yo], frame: CGRect(x: 10, y: 20, width: 1400, height: 860)),
                                      .init(tabs: [Self.pe])])
        let back = try #require(OpenWindows.decode(w.encoded()))
        #expect(back == w)
        #expect(back.tabs.map(\.title) == ["core-01", "yo", "pe-02"])
        // (las de este mismo Mac no se reabren; una ventana que sólo tenía ésas desaparece)
        let kept = OpenWindows(windows: [.init(tabs: [Self.yo]), .init(tabs: [Self.pe, Self.yo])]).withoutLoopback()
        #expect(kept.windows.count == 1 && kept.tabs.map(\.title) == ["pe-02"])
    }

    @Test func leeElFormatoDeAntes() throws {
        // (0.9.x guardaba una lista: es una sola ventana, sin marco)
        let old = try JSONEncoder().encode([Self.core, Self.pe])
        let w = try #require(OpenWindows.decode(old))
        #expect(w.windows.count == 1 && w.windows[0].frame == nil)
        #expect(w.tabs.map(\.title) == ["core-01", "pe-02"])
        #expect(OpenWindows.decode(Data("no es json".utf8)) == nil)
        #expect(OpenWindows.decode(Data("{}".utf8)) == nil)
    }

    @Test func ventanaNuevaDondeSeSueltaLaPestaña() {
        let left = CGRect(x: 0, y: 0, width: 1800, height: 1130), above = CGRect(x: 0, y: 1130, width: 1512, height: 920)
        let size = CGSize(width: 1000, height: 860), grab = CGPoint(x: 140, y: 19)
        // (en medio de la pantalla de arriba: el puntero queda sobre la barra de pestañas)
        let f = WindowPlacement.frame(droppingAt: CGPoint(x: 600, y: 2000), size: size, grab: grab, screens: [left, above])
        #expect(f.minX == 460 && f.maxY == 2019 && above.contains(f))
        // (tan abajo que no cabría: sube lo justo, sin salirse de esa pantalla)
        let low = WindowPlacement.frame(droppingAt: CGPoint(x: 600, y: 1150), size: size, grab: grab, screens: [left, above])
        #expect(low.minY == above.minY && above.contains(low))
        // (junto a un borde: se mete entera en esa pantalla)
        let edge = WindowPlacement.frame(droppingAt: CGPoint(x: 1790, y: 100), size: size, grab: grab, screens: [left, above])
        #expect(left.contains(edge) && edge.size == size)
        // (más grande que la pantalla: se encoge)
        let big = WindowPlacement.frame(droppingAt: CGPoint(x: 100, y: 1500), size: CGSize(width: 3000, height: 3000), grab: grab,
                                        screens: [left, above])
        #expect(big.size == above.size && above.contains(big))
        // (fuera de todas: en la más cercana)
        let out = WindowPlacement.frame(droppingAt: CGPoint(x: 5000, y: 50), size: size, grab: grab, screens: [left, above])
        #expect(left.contains(out))
    }

    @Test func marcoGuardadoSoloSiSuPantallaSigue() {
        let left = CGRect(x: 0, y: 0, width: 1800, height: 1130)
        let saved = CGRect(x: 100, y: 1150, width: 1400, height: 860)                   // (estaba en la de arriba)
        #expect(WindowPlacement.restored(saved, screens: [left]) == nil)
        #expect(WindowPlacement.restored(saved, screens: [left, CGRect(x: 0, y: 1130, width: 1512, height: 920)]) == saved)
        // (su centro sigue en la pantalla pero se sale un poco: se mete)
        #expect(WindowPlacement.restored(CGRect(x: 1500, y: 500, width: 400, height: 300), screens: [left])?.maxX == 1800)
        // (su centro ya no está en ninguna: nil)
        #expect(WindowPlacement.restored(CGRect(x: 1700, y: 500, width: 400, height: 300), screens: [left]) == nil)
        #expect(WindowPlacement.restored(.zero, screens: [left]) == nil)
    }

    @Test func nombrePropioHastaOtroEquipo() {
        var r = TabRename()
        r.set("  Agregación Madrid ", on: "core-01")
        #expect(r.name == "Agregación Madrid")
        let same = r.deviceChanged(to: "core-01")                 // (reconectar o el modo configuración: se queda)
        #expect(!same && r.name == "Agregación Madrid")
        let other = r.deviceChanged(to: "pe-02")                  // (otro equipo: vuelve el del equipo)
        #expect(other && r.name == nil)
        let back = r.deviceChanged(to: "core-01")                 // (y no vuelve solo)
        #expect(!back && r.name == nil)
        // (puesto antes del primer prompt: su equipo es el primero que salga)
        var early = TabRename()
        early.set("Lab", on: nil)
        let first = early.deviceChanged(to: "bastion")
        #expect(!first && early.name == "Lab" && early.device == "bastion")
        let next = early.deviceChanged(to: "core-01")
        #expect(next && early.name == nil)
        // (vacío: quitarlo)
        var gone = TabRename()
        gone.set("x", on: "core-01")
        gone.set("  ", on: "core-01")
        #expect(gone.name == nil && gone.device == nil)
    }
}
