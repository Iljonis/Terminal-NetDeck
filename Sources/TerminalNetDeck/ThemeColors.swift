import AppKit
import NetDeckCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - colores a medida (lo que cambia el modelo)

extension AppModel {
    /// Un color a medida del tema actual (nil = el del tema), al momento en todas las pestañas de todas las ventanas.
    func setThemeColor(_ key: String, _ c: RGB?) {
        editOverrides { $0[key] = c }
    }

    /// Opacidad del fondo del tema actual (sólo los de cristal; nil = la del tema).
    func setThemeOpacity(_ v: Double?) {
        editOverrides { $0.setOpacity(v) }
    }

    /// Todos los colores del tema actual, los del .tema.
    func resetThemeColors() {
        editOverrides { $0 = ThemeOverrides() }
    }

    private func editOverrides(_ change: (inout ThemeOverrides) -> Void) {
        let id = themes.current.id
        var o = themes.overrides[id] ?? ThemeOverrides()
        change(&o)
        themes.overrides[id] = o.isEmpty ? nil : o
        settings.themeOverrides[id] = o.isEmpty ? nil : o.dictionary
        applyAppearance()                       // (barra, pestañas, menús y terminal a la vez)
    }

    /// Quita un tema importado y sus colores a medida.
    func removeTheme(_ id: String) {
        themes.remove(id)
        themes.overrides[id] = nil
        settings.themeOverrides[id] = nil
        selectTheme(themes.current.id)
    }

    /// El tema actual con sus colores a medida, como un tema nuevo (entre los importados); y se pasa a él.
    func saveThemeAsNew(name: String) {
        do {
            let t = try themes.library.saveNew(themes.customized, name: name)
            themes.refresh()
            if settings.themeAuto { settings.themeAuto = false }
            selectTheme(t.id)
            status = L("✓ Tema «\(t.name)» guardado en \(AppPaths.tilde(themes.library.importDirectory.path))")
        } catch {
            ErrorLog.warning("temas", "guardar como tema nuevo: \(error.localizedDescription)")
            status = "✗ " + error.localizedDescription
        }
    }

    /// El tema actual con sus colores a medida, a un .tema donde digas.
    func exportTheme(to url: URL) {
        do {
            try SafeFile.write(themes.customized.temaText, to: url)
            status = L("✓ Tema exportado a \(AppPaths.tilde(url.path))")
        } catch {
            ErrorLog.error("temas", "exportar \(url.lastPathComponent): \(error.localizedDescription)")
            status = "✗ " + error.localizedDescription
        }
    }
}

// MARK: - Ajustes → Temas → «Personalizar colores»

/// Los colores del tema actual, uno a uno (con su nombre real y un aviso si se lee mal), los 16 ANSI en cuadrícula y la
/// opacidad en los de cristal. Se ve al momento en la vista previa de arriba y en todas las pestañas.
struct ThemeColorsEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Binding var expanded: Bool
    @Stored private var message = ""

    private static var labels: [String: String] { [
        "fondo": L("Fondo"), "texto": L("Texto"), "acento": L("Acento"), "acento2": L("Acento 2"),
        "pestaña": L("Pestaña activa"), "selección": L("Selección"), "cursor": L("Cursor"),
    ] }

    var body: some View {
        let th = model.themes.current
        let mine = model.themes.overrides[th.id] ?? ThemeOverrides()
        let warnings = Dictionary(ThemeOverrides.contrastWarnings(th).map { ($0.key, $0) }) { a, _ in a }
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12, alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(ThemeOverrides.colorKeys, id: \.self) { k in
                        // (el fondo avisa con el texto: es la misma pareja)
                        row(k, title: Self.labels[k] ?? k, color: color(k, th), custom: mine[k] != nil,
                            warning: warnings[k == "fondo" ? "texto" : k])
                    }
                }
                if model.themes.customized.isTranslucent { opacity(mine) }
                Text(L("Colores ANSI del terminal")).font(t.ui(11.5, .bold)).foregroundStyle(SwiftUI.Color(t.accent2))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 40), spacing: 8), count: 8), spacing: 8) {
                    ForEach(0..<16, id: \.self) { i in ansiCell(i, th.ansi[i], custom: mine["ansi\(i)"] != nil, warning: warnings["ansi\(i)"]) }
                }
                if !warnings.isEmpty {
                    Label(L("Algunos colores se leen mal sobre el fondo (⚠). Puedes dejarlos así."), systemImage: "exclamationmark.triangle")
                        .font(t.ui(11)).foregroundStyle(SwiftUI.Color(th.warning))
                }
                HStack(spacing: 10) {
                    Button(L("Restablecer todo"), action: resetAll).disabled(mine.isEmpty)
                    Spacer()
                    Button(L("Guardar como tema nuevo…"), action: saveAsNew)
                    Button(L("Exportar .tema…"), action: export)
                }
                if !message.isEmpty { Text(message).font(t.ui(11)) }
                Text(L("Sólo cambian este tema y no tocan su archivo .tema: los demás temas siguen igual."))
                    .font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Text(L("Personalizar colores (tema «\(th.name)»)")).font(t.ui(12.5, .bold))
                if !mine.isEmpty {
                    Text(L("personalizado")).font(t.ui(10, .semibold)).foregroundStyle(SwiftUI.Color(t.accent))
                }
            }
        }
        .font(t.ui(12))
    }

    private func color(_ k: String, _ th: Theme) -> RGB {
        switch k {
        case "fondo": th.background.opaque
        case "texto": th.text
        case "acento": th.accent
        case "acento2": th.accent2
        case "pestaña": th.tab
        case "selección": th.selection
        default: th.cursor
        }
    }

    /// Selector, nombre, el nombre real del color, el aviso de contraste y «Restablecer».
    private func row(_ k: String, title: String, color c: RGB, custom: Bool, warning: ThemeOverrides.ContrastWarning?) -> some View {
        HStack(spacing: 6) {
            picker(k, c, help: L("Elegir el color de «\(title)»"))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(t.ui(12, custom ? .bold : .regular))
                Text(c.nombre).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if let warning { warningIcon(warning) }
            if custom { resetButton(k) }
        }
    }

    private func ansiCell(_ i: Int, _ c: RGB, custom: Bool, warning: ThemeOverrides.ContrastWarning?) -> some View {
        VStack(spacing: 2) {
            picker("ansi\(i)", c, help: L("ANSI \(String(i)): \(c.nombre)"))
            HStack(spacing: 2) {
                Text(verbatim: "\(i)").font(.caption.monospaced().weight(custom ? .bold : .regular)).foregroundStyle(.secondary)
                if let warning { warningIcon(warning) }
                if custom { resetButton("ansi\(i)") }
            }
        }
    }

    private func picker(_ k: String, _ c: RGB, help: String) -> some View {
        ColorPicker(help, selection: Binding(
            get: { SwiftUI.Color(c.opaque) },
            set: { new in
                guard let s = NSColor(new).usingColorSpace(.sRGB) else { return }
                // (un color de P3 da componentes fuera de 0…1: «#rrggbb» no los cabe)
                func v(_ x: CGFloat) -> Double { Double(min(max(x, 0), 1) * 255) }
                model.setThemeColor(k, RGB(v(s.redComponent), v(s.greenComponent), v(s.blueComponent)))
            }), supportsOpacity: false)
            .labelsHidden()
            .help(help)
            .accessibilityLabel(help)
    }

    private func warningIcon(_ w: ThemeOverrides.ContrastWarning) -> some View {
        let text = L("Se lee mal: contraste \(w.ratio.formatted(.number.precision(.fractionLength(1)))):1 (mínimo \(w.minimum.formatted(.number.precision(.fractionLength(1)))):1)")
        return Image(systemName: "exclamationmark.triangle.fill").font(.caption)
            .foregroundStyle(SwiftUI.Color(model.themes.current.warning))
            .help(text)
            .accessibilityLabel(text)
    }

    private func resetButton(_ k: String) -> some View {
        Button { model.setThemeColor(k, nil) } label: { Image(systemName: "arrow.uturn.backward") }
            .buttonStyle(.borderless)
            .help(L("Volver al color del tema"))
            .accessibilityLabel(L("Volver al color del tema"))
    }

    /// Opacidad del fondo (cristal). Con «Reducir transparencia» del Mac no se nota: va opaco.
    private func opacity(_ mine: ThemeOverrides) -> some View {
        let id = model.themes.current.id
        let base = model.themes.all.first { $0.theme.id == id }?.theme.background.a ?? 1
        return HStack(spacing: 8) {
            Text(L("Opacidad del fondo"))
            Slider(value: Binding(get: { mine.opacity ?? base }, set: { model.setThemeOpacity($0) }),
                   in: ThemeOverrides.opacityRange)
                .frame(maxWidth: 220)
                .accessibilityLabel(L("Opacidad del fondo"))
            Text((mine.opacity ?? base).formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
            if mine.opacity != nil {
                Button { model.setThemeOpacity(nil) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .help(L("Volver a la del tema"))
                    .accessibilityLabel(L("Volver a la del tema"))
            }
            if model.themes.solidOnly {
                Text(L("(con «Reducir transparencia» del Mac va opaco)")).font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            }
        }
    }

    private func resetAll() {
        let name = model.themes.current.name
        Task {
            guard await ThemedAlert.confirm(L("¿Volver a los colores del tema «\(name)»?"),
                                            message: L("Se quitan todos sus colores a medida."),
                                            ok: L("Restablecer todo"), destructive: true) else { return }
            model.resetThemeColors()
        }
    }

    private func saveAsNew() {
        let name = model.themes.current.name
        Task {
            let r = await ThemedAlert.run(L("Guardar como tema nuevo"),
                                          message: L("Con los colores de ahora. Se guarda en \(AppPaths.tilde(model.themes.library.importDirectory.path))."),
                                          buttons: [L("Guardar"), L("Cancelar")],
                                          field: (L("Nombre del tema"), L("\(name) a medida"), false))
            guard r.button == 0 else { return }
            model.saveThemeAsNew(name: r.text)
            message = model.status
        }
    }

    private func export() {
        let p = NSSavePanel()
        p.allowedContentTypes = [UTType(filenameExtension: "tema") ?? .plainText]
        p.nameFieldStringValue = "\(model.themes.current.id).tema"
        guard p.runModal() == .OK, let u = p.url else { return }
        model.exportTheme(to: u)
        message = model.status
    }
}
