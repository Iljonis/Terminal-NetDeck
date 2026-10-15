import AppKit
import NetDeckCore
import SwiftUI

/// Lista de reglas de Ajustes → Resaltado: encender/apagar, editar, duplicar, ordenar, borrar, añadir y volver a las
/// de serie. Cualquier cambio se guarda en el archivo personalizado (`AppModel.saveHighlightRules`).
struct HighlightRuleList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Stored private var editing: Target?
    @Stored private var message = ""

    /// Qué se edita: una regla que ya está (su posición) o una nueva.
    struct Target: Identifiable {
        let id = UUID()
        let index: Int?
        let rule: HighlightRule?
    }

    var body: some View {
        let rules = model.highlightConfig.rules
        Section {
            ForEach(Array(rules.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 8) {
                    Toggle(isOn: enabled(r)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.description)
                            Text(r.source).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { editing = Target(index: i, rule: r) } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless).help(L("Editar la regla"))
                    ThemedMenu {
                        Button(L("Duplicar")) { duplicate(i) }
                        Button(L("Subir")) { move(i, -1) }.disabled(i == 0)
                        Button(L("Bajar")) { move(i, 1) }.disabled(i == rules.count - 1)
                        MenuDivider()
                        Button(L("Borrar…")) { delete(i) }
                    } label: { Image(systemName: "ellipsis.circle") }.fixedSize()
                }
            }
        } header: {
            HStack {
                Text(L("Reglas (\(rules.count))"))
                Spacer()
                Button(L("Nueva regla…")) { editing = Target(index: nil, rule: nil) }
                Button(L("Restaurar las de serie…"), action: restore)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if !message.isEmpty { Text(message).font(t.ui(11)).foregroundStyle(message.hasPrefix("✗") ? .red : .secondary) }
                Text(L("Van por orden: la primera que encaja colorea. Al cambiar algo se guardan en tu archivo personalizado."))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { target in
            HighlightRuleEditor(rule: target.rule, taken: Set(rules.map(\.description)).subtracting([target.rule?.description ?? ""])) { new in
                var list = rules
                var renamed: [String: String] = [:]
                if let i = target.index, list.indices.contains(i) {
                    renamed[list[i].description] = new.description
                    list[i] = new
                } else {
                    list.append(new)
                }
                save(list, renamed: renamed, ok: L("✓ Regla «\(new.description)» guardada"))
            }
            .environment(model)
            .environment(\.theme, t)
        }
    }

    private func enabled(_ r: HighlightRule) -> Binding<Bool> {
        Binding(get: { !model.settings.highlightDisabled.contains(r.description) },
                set: { on in
                    if on { model.settings.highlightDisabled.remove(r.description) } else { model.settings.highlightDisabled.insert(r.description) }
                    model.applyHighlight()
                })
    }

    private func save(_ rules: [HighlightRule], renamed: [String: String] = [:], ok: String) {
        if let err = model.saveHighlightRules(rules, renamed: renamed) { message = "✗ \(err)" } else { message = ok }
    }

    private func duplicate(_ i: Int) {
        var list = model.highlightConfig.rules
        var copy = list[i]
        let names = Set(list.map(\.description))
        var n = 2
        while names.contains("\(copy.description) \(n)") { n += 1 }
        copy.description = "\(copy.description) \(n)"
        list.insert(copy, at: i + 1)
        save(list, ok: L("✓ Duplicada: «\(copy.description)»"))
    }

    private func move(_ i: Int, _ step: Int) {
        var list = model.highlightConfig.rules
        let j = i + step
        guard list.indices.contains(i), list.indices.contains(j) else { return }
        list.swapAt(i, j)
        save(list, ok: "")
    }

    private func delete(_ i: Int) {
        let list = model.highlightConfig.rules
        guard list.indices.contains(i) else { return }
        Task {
            guard await ThemedAlert.confirm(L("¿Borrar la regla «\(list[i].description)»?"), message: L("Queda una copia del archivo anterior (resaltado.yml.anterior)."), ok: L("Borrar"), destructive: true) else { return }
            // (con lo que haya ahora: si mientras se preguntaba cambió la lista, no se borra otra)
            var rest = model.highlightConfig.rules
            guard rest.indices.contains(i), rest[i].description == list[i].description else { return }
            let gone = rest.remove(at: i)
            save(rest, ok: L("✓ Borrada «\(gone.description)»"))
        }
    }

    private func restore() {
        Task {
            guard await ThemedAlert.confirm(L("¿Volver a las reglas de serie?"), message: L("Tus reglas personalizadas se sustituyen (queda copia en resaltado.yml.anterior) y se encienden todas."), ok: L("Restaurar"), destructive: true) else { return }
            if let err = model.restoreBundledHighlight() { message = "✗ \(err)" } else { message = L("✓ Reglas de serie restauradas") }
        }
    }
}

/// Editar (o crear) una regla: descripción, expresión (se comprueba mientras se escribe), colores por grupo,
/// exclusiva y una vista previa con un texto de muestra que se puede cambiar.
struct HighlightRuleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let rule: HighlightRule?
    /// Descripciones de las otras reglas (no se pueden repetir: el encendido/apagado va por descripción).
    let taken: Set<String>
    let onSave: (HighlightRule) -> Void

    struct StyleRow: Identifiable {
        let id = UUID()
        var group: Int
        var style: HighlightStyle
    }

    @Stored private var name = ""
    @Stored private var regex = ""
    @Stored private var exclusive = false
    @Stored private var rows: [StyleRow] = []
    @Stored private var sample = HighlightPreview.sample
    @Stored private var loaded = false

    var body: some View {
        let th = model.themes.current
        let problem = HighlightRule.problem(regex: regex)
        let draft = problem == nil ? try? HighlightRule(description: name, regex: regex, styles: styles, exclusive: exclusive) : nil
        let nameProblem = name.trimmingCharacters(in: .whitespaces).isEmpty ? L("Falta la descripción")
            : taken.contains(name.trimmingCharacters(in: .whitespaces)) ? L("Ya hay otra regla con esa descripción") : nil
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent(L("Descripción")) { TextField("", text: $name, prompt: Text(L("p. ej. VLAN"))).frame(maxWidth: 380) }
                    if let nameProblem { Text(nameProblem).font(.caption).foregroundStyle(.red) }
                    LabeledContent(L("Expresión regular")) { TextField("", text: $regex, prompt: Text(#"\bvlan\s?\d+\b"#)).frame(maxWidth: 380) }
                        .font(.body.monospaced())
                    if let problem {
                        Text("✗ " + problem).font(.caption).foregroundStyle(.red)
                    } else if let d = draft {
                        Text(L("✓ Válida · \(d.groupCount) grupos")).font(.caption).foregroundStyle(.green)
                    }
                    Toggle(L("Exclusiva: lo que colorea ya no lo colorea ninguna regla de después"), isOn: $exclusive)
                } header: { Text(rule == nil ? L("Nueva regla") : L("Editar la regla")) } footer: {
                    Text(L("Sintaxis de ChromaTerm/Python: (?i) sin distinguir mayúsculas, \\b borde de palabra, (…) grupos."))
                        .font(.caption)
                }
                Section {
                    ForEach($rows) { $row in styleRow($row, groups: draft?.groupCount ?? 0, palette: palette(th)) }
                    Button(L("Añadir color para un grupo")) {
                        let used = Set(rows.map(\.group))
                        let next = (0...max(0, draft?.groupCount ?? 0)).first { !used.contains($0) } ?? 0
                        rows.append(StyleRow(group: next, style: HighlightStyle(foreground: "cyan")))
                    }
                } header: { Text(L("Colores")) } footer: {
                    Text(L("Grupo 0 = todo el acierto. Los colores con nombre siguen al tema (si está activado «Con los colores del tema»)."))
                        .font(.caption)
                }
                Section(L("Vista previa (sólo esta regla)")) {
                    TextEditor(text: $sample).themedEditor().font(.callout.monospaced()).frame(height: 90)
                    let h = draft.map { Highlighter(rules: [$0], palette: palette(th)) }
                    Text(HighlightPreview.render(sample, with: h, palette: palette(th), theme: th))
                        .font(SwiftUI.Font(model.terminalFont))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SwiftUI.Color(th.background))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    if let h {
                        let n = sample.components(separatedBy: "\n").filter { !h.styledRuns($0).isEmpty }.count
                        Text(L("Colorea \(n) líneas de la muestra")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.themed)
            HStack {
                Spacer()
                Button(L("Cancelar")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Guardar")) {
                    if let d = try? HighlightRule(description: name.trimmingCharacters(in: .whitespaces), regex: regex, styles: styles, exclusive: exclusive) {
                        onSave(d)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft == nil || nameProblem != nil || rows.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 620, height: 680)
        .onAppear(perform: load)
    }

    private var styles: [Int: HighlightStyle] {
        var out: [Int: HighlightStyle] = [:]
        for r in rows where out[r.group] == nil { out[r.group] = r.style }
        return out
    }

    private func palette(_ th: Theme) -> [String: RGB] {
        let cfg = model.highlightConfig
        return model.settings.highlightThemeColors ? th.highlightPalette : th.highlightPalette.merging(cfg.palette) { $1 }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let rule else {
            rows = [StyleRow(group: 0, style: HighlightStyle(foreground: "cyan", bold: true))]
            return
        }
        name = rule.description
        regex = rule.source
        exclusive = rule.exclusive
        rows = rule.styles.keys.sorted().map { StyleRow(group: $0, style: rule.styles[$0]!) }
        // (la muestra: primero las líneas que ya colorea, para verla al momento)
        let h = Highlighter(rules: [rule], palette: [:])
        let lines = HighlightPreview.sample.components(separatedBy: "\n")
        let hit = lines.filter { !h.styledRuns($0).isEmpty }
        sample = (hit + lines.filter { !hit.contains($0) }).joined(separator: "\n")
    }

    @ViewBuilder
    private func styleRow(_ row: Binding<StyleRow>, groups: Int, palette: [String: RGB]) -> some View {
        HStack(spacing: 10) {
            ThemedPicker(L("Grupo"), selection: row.group) { o in
                for g in Array(Set(0...max(groups, row.wrappedValue.group))).sorted() { o.append((g, g == 0 ? L("todo") : "\(g)")) }
            }
            .frame(width: 120)
            colorPicker(L("Texto"), row.style.foreground, palette: palette)
            colorPicker(L("Fondo"), row.style.background, palette: palette)
            Toggle("B", isOn: row.style.bold).toggleStyle(.themedCheckbox).help(L("Negrita"))
            Toggle("I", isOn: row.style.italic).toggleStyle(.themedCheckbox).help(L("Cursiva"))
            Toggle("U", isOn: row.style.underline).toggleStyle(.themedCheckbox).help(L("Subrayado"))
            Spacer()
            Button { rows.removeAll { $0.id == row.wrappedValue.id } } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).help(L("Quitar este color"))
        }
    }

    /// Colores con nombre de ChromaTerm (los del tema) o uno a mano («#rrggbb»).
    private func colorPicker(_ title: String, _ value: Binding<String?>, palette: [String: RGB]) -> some View {
        HStack(spacing: 4) {
            ThemedMenu {
                Button(L("Ninguno")) { value.wrappedValue = nil }
                MenuDivider()
                ForEach(HighlightStyle.colorNames, id: \.self) { n in
                    Button { value.wrappedValue = n } label: {
                        Label { Text(n) } icon: { Image(nsImage: Self.swatch(palette[n])) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(nsImage: Self.swatch(value.wrappedValue.flatMap { palette[$0] ?? RGB(hex: $0) }))
                    Text(value.wrappedValue ?? "—").font(.caption.monospaced())
                }
            }
            .fixedSize()
            .help(title)
            ColorPicker(title, selection: Binding(
                get: { SwiftUI.Color(value.wrappedValue.flatMap { palette[$0] ?? RGB(hex: $0) } ?? RGB(128, 128, 128)) },
                set: { c in
                    guard let s = NSColor(c).usingColorSpace(.sRGB) else { return }
                    value.wrappedValue = RGB(s.redComponent * 255, s.greenComponent * 255, s.blueComponent * 255).description
                }), supportsOpacity: false)
                .labelsHidden()
                .help(L("\(title): otro color (#rrggbb)"))
        }
    }

    /// Muestra de color para los menús (en macOS, los menús sólo pintan imágenes).
    static func swatch(_ c: RGB?) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            if let c { NSColor(c).setFill() } else { NSColor.clear.setFill() }
            let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            p.fill()
            NSColor.gray.setStroke()
            p.stroke()
            return true
        }
    }
}
