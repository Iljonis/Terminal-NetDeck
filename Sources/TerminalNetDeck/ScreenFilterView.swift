import AppKit
import NetDeckCore
import SwiftUI

// Filtro de pantalla (1.0.0): CRT, LCD, Fósforo u Holograma encima del terminal de cada pestaña. Es una vista fija
// sobre la de SwiftTerm que se pinta sólo al cambiar de tamaño o de filtro (no con el texto que entra: va en su propia
// capa) y no recibe el ratón: selección, clic derecho, arrastre y rueda siguen siendo del terminal.

/// Lo que se pinta encima del terminal (`ScreenLook`, de NetDeckCore).
final class ScreenFilterOverlay: NSView {
    var look: ScreenLook? {
        didSet {
            guard look != oldValue else { return }
            isHidden = look == nil
            needsDisplay = true
        }
    }

    /// El Mac pide menos efectos («Reducir movimiento», «Reducir transparencia» o «Aumentar contraste»): sin filtro.
    static var systemWantsCalm: Bool {
        let w = NSWorkspace.shared
        return w.accessibilityDisplayShouldReduceMotion || w.accessibilityDisplayShouldReduceTransparency
            || w.accessibilityDisplayShouldIncreaseContrast
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay        // (sólo cuando se pide: tamaño o filtro)
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if look != nil { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let l = look, let cg = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds, center = CGPoint(x: b.midX, y: b.midY), corner = hypot(b.width, b.height) / 2
        if let c = l.tint {
            cg.setFillColor(NSColor(c).cgColor)
            cg.fill(b)
        }
        if let c = l.glow { radial(cg, center, corner, [(0, c), (1, c.alpha(0))]) }
        // (cada juego de líneas, en un solo trazado: donde se cruzan las de la rejilla no oscurece el doble)
        if let s = l.scan { lines(cg, b, s, vertical: false) }
        if let g = l.grid { lines(cg, b, g, vertical: true) }
        if l.vignette > 0 { radial(cg, center, corner, [(0.55, RGB.black.alpha(0)), (1, RGB.black.alpha(l.vignette))]) }
        if l.curve > 0 {
            // (las esquinas del tubo: lo que queda fuera de un rectángulo redondeado, con el borde suavizado)
            cg.saveGState()
            let path = CGMutablePath()
            path.addRect(b)
            path.addPath(CGPath(roundedRect: b, cornerWidth: l.curve, cornerHeight: l.curve, transform: nil))
            cg.addPath(path)
            cg.setShadow(offset: .zero, blur: l.curve * 0.8, color: NSColor.black.withAlphaComponent(l.cornerAlpha).cgColor)
            cg.setFillColor(NSColor.black.withAlphaComponent(l.cornerAlpha).cgColor)
            cg.fillPath(using: .evenOdd)
            cg.restoreGState()
        }
    }

    private func lines(_ cg: CGContext, _ b: CGRect, _ l: ScreenLook.Lines, vertical: Bool) {
        guard l.every > 0, l.width > 0 else { return }
        let path = CGMutablePath()
        var y = b.minY
        while y < b.maxY {
            path.addRect(CGRect(x: b.minX, y: y, width: b.width, height: l.width))
            y += l.every
        }
        if vertical {
            var x = b.minX
            while x < b.maxX {
                path.addRect(CGRect(x: x, y: b.minY, width: l.width, height: b.height))
                x += l.every
            }
        }
        cg.addPath(path)
        cg.setFillColor(NSColor(l.color).cgColor)
        cg.fillPath(using: .winding)
    }

    private func radial(_ cg: CGContext, _ center: CGPoint, _ radius: CGFloat, _ stops: [(CGFloat, RGB)]) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: stops.map { NSColor($0.1).cgColor } as CFArray,
                                 locations: stops.map(\.0)) else { return }
        cg.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                              options: .drawsAfterEndLocation)
    }
}

extension NetDeckTerminalView {
    /// El filtro de esta pestaña (nil = ninguno). La vista se crea la primera vez que hace falta, encima del texto
    /// pero debajo de la barra de desplazamiento y de la de ⌘F (las dos de SwiftTerm), aunque ya estuvieran.
    func showScreenFilter(_ look: ScreenLook?) {
        let current = subviews.lazy.compactMap { $0 as? ScreenFilterOverlay }.first
        guard look != nil || current != nil else { return }
        let overlay = current ?? {
            let v = ScreenFilterOverlay(frame: bounds)
            v.autoresizingMask = [.width, .height]
            return v
        }()
        if let bar = subviews.first(where: { $0 !== overlay && ($0 is NSScroller || $0 is NSVisualEffectView) }) {
            if subviews.firstIndex(of: overlay).map({ $0 > subviews.firstIndex(of: bar)! }) ?? true {
                addSubview(overlay, positioned: .below, relativeTo: bar)
            }
        } else if overlay.superview == nil {
            addSubview(overlay, positioned: .above, relativeTo: nil)
        }
        overlay.look = look
    }
}

extension AppModel {
    /// El de cada pestaña de todas las ventanas (al cambiar Ajustes, el menú o la Accesibilidad del Mac).
    func applyScreenFilter() { core.allTabs.forEach(applyScreenFilter) }

    /// Con el tema de la pestaña (su perfil puede llevar otro): el suyo en «Automático» y sus colores.
    func applyScreenFilter(to s: TerminalSession) {
        let th = s.theme ?? themes.current
        s.view.showScreenFilter(screenFilter(for: th).look(intensity: settings.screenFilterIntensity, text: th.text))
    }

    func screenFilter(for th: Theme) -> ScreenFilter {
        ScreenFilter.resolve(choice: settings.screenFilter, on: settings.screenFilterOn, theme: th.screenFilter,
                             calm: core.screenCalm)
    }

    /// Desde el menú Ver (⌥⌘F o un filtro): a todas las pestañas, y lo que queda en la de delante, en la barra.
    func setScreenFilter(on: Bool? = nil, choice: String? = nil) {
        if let choice { settings.screenFilter = choice }
        settings.screenFilterOn = on ?? (choice != nil ? true : settings.screenFilterOn)
        applyScreenFilter()
        let f = screenFilter(for: current?.theme ?? themes.current)
        status = !settings.screenFilterOn ? L("Filtro de pantalla apagado")
            : core.screenCalm ? L("Filtro de pantalla apagado: el Mac pide menos efectos (Accesibilidad → Pantalla)")
            : f == .none ? L("Filtro de pantalla: este tema no lleva ninguno (elige uno en Ver → Filtro de pantalla)")
            : L("Filtro de pantalla: \(f.name)")
    }
}

/// Ajustes → Terminal → Filtro de pantalla.
struct ScreenFilterSection: View {
    @Environment(\.theme) private var t
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var s = model.settings
        let th = model.current?.theme ?? model.themes.current
        Section(L("Filtro de pantalla")) {
            Toggle(L("Filtro encima del terminal (⌥⌘F)"), isOn: $s.screenFilterOn)
            ThemedPicker(L("Filtro"), selection: $s.screenFilter) { o in
                o.append((ScreenFilter.automatic, L("Automático: el del tema (\((th.screenFilter ?? .none).name))")))
                for f in ScreenFilter.allCases { o.append((f.rawValue, f.name)) }
            }
            .disabled(!s.screenFilterOn)
            HStack {
                Text(L("Intensidad"))
                Slider(value: $s.screenFilterIntensity, in: ScreenFilter.intensityRange)
                    .accessibilityLabel(L("Intensidad"))
                Text(L("\(String(Int((s.screenFilterIntensity * 100).rounded()))) %")).monospacedDigit().frame(width: 50)
            }
            .disabled(!s.screenFilterOn)
            if model.core.screenCalm {
                Text(L("Ahora apagado: el Mac tiene activado «Reducir movimiento», «Reducir transparencia» o «Aumentar contraste» (Ajustes del Sistema → Accesibilidad → Pantalla)."))
                    .font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.warning))
            }
            Text(L("Líneas de barrido, rejilla de píxeles o resplandor encima del texto, como en una pantalla antigua. «Automático» usa el del tema. Es un dibujo fijo: no gasta mientras sale texto y no toca el ratón ni la selección."))
                .font(t.ui(11)).foregroundStyle(.secondary)
        }
        .onChange(of: s.screenFilter) { model.applyScreenFilter() }
        .onChange(of: s.screenFilterOn) { model.applyScreenFilter() }
        .onChange(of: s.screenFilterIntensity) { model.applyScreenFilter() }
    }
}

/// Ver → Filtro de pantalla: encenderlo y apagarlo (⌥⌘F) y elegirlo, en la ventana de delante sin hojas abiertas
/// (`modalOpen`); se refresca con `MenuRefresh` (AppCore mira `screenFilterOn` y `screenFilter`).
struct ScreenFilterMenu: View {
    let core: AppCore
    let modal: Bool

    var body: some View {
        let s = core.settings
        Menu(L("Filtro de pantalla")) {
            Toggle(L("Filtro encima del terminal"), isOn: Binding(get: { s.screenFilterOn },
                                                               set: { on in act { $0.setScreenFilter(on: on) } }))
                .keyboardShortcut("f", modifiers: [.command, .option])
            if core.screenCalm { Text(L("Ahora apagado por Accesibilidad del Mac")) }
            Divider()
            Picker(L("Filtro"), selection: Binding(get: { s.screenFilter }, set: { c in act { $0.setScreenFilter(choice: c) } })) {
                Text(L("Automático (el del tema)")).tag(ScreenFilter.automatic)
                ForEach(ScreenFilter.allCases, id: \.self) { f in Text(f.name).tag(f.rawValue) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .disabled(modal)
    }

    private func act(_ f: (AppModel) -> Void) {
        guard let m = core.front, !m.modalOpen else { return }
        f(m)
    }
}
