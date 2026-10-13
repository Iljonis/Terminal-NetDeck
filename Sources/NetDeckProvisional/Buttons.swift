import AppKit
import NetDeckCore
import SwiftUI

/// La barra de botones de NetDeck (estilo SecureCRT): ☰ Grupo y sus botones, o todos en fila. Clic = en la pestaña
/// activa (o en todas las de MultiExec). Colores por modo, como NetDeck.
struct ButtonBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        let file = model.buttons
        let grouped = model.settings.buttonBarGrouped
        let shown = grouped ? file.buttons.filter { $0.group == model.settings.buttonGroup } : file.buttons
        HStack(spacing: 6) {
            if grouped, !file.groups.isEmpty {
                Menu {
                    ForEach(file.groups, id: \.self) { g in
                        Button(g) { model.settings.buttonGroup = g }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal")
                        Text(model.settings.buttonGroup).font(t.ui(11, .bold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(SwiftUI.Color(t.onTab))
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: t.neon ? 3 : 6).fill(SwiftUI.Color(t.tab)))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Cambiar de grupo de botones")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(shown) { b in CommandChip(button: b) }
                    if shown.isEmpty {
                        Text("Sin botones · ✎ para crear").font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim))
                    }
                }
                .padding(.vertical, 4)
            }
            IconButton(icon: "pencil") { model.openSettings("botones") }
                .help("Editar los botones (los mismos que NetDeck)")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(SwiftUI.Color(t.bar))
        .overlay(alignment: model.settings.buttonBar == "abajo" ? .top : .bottom) { NeonLine(color: t.panel) }
    }
}

struct CommandChip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let button: CommandButton
    @Stored private var hover = false

    var body: some View {
        let c = SwiftUI.Color(color(button.mode))
        Button { model.runButton(button) } label: {
            HStack(spacing: 5) {
                Text(button.name).font(t.ui(11, .semibold)).lineLimit(1)
                if let k = button.hotkey {
                    Text(k).font(t.ui(8.5, .bold)).opacity(0.75)
                        .padding(.horizontal, 3)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(c.opacity(0.5)))
                }
            }
            .foregroundStyle(hover ? SwiftUI.Color(color(button.mode).readable) : c)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: t.neon ? 3 : 6).fill(hover ? c : SwiftUI.Color(t.panel).opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: t.neon ? 3 : 6).strokeBorder(c.opacity(hover ? 1 : 0.35)))
            .shadow(color: c.opacity(hover ? 0.5 : 0), radius: t.glow(5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("\(button.mode.title): \(button.mode == .pass ? "contraseña «\(button.command)»" : button.command)"
              + (model.multiExecOn ? " · en todas (MultiExec)" : ""))
        .contextMenu {
            Button("Editar…") { model.openSettings("botones") }
            Button("Copiar la orden") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(button.command, forType: .string)
            }
        }
    }

    private func color(_ m: CommandButton.Mode) -> RGB {
        switch m {
        case .run: t.accent2
        case .type: t.accent
        case .pass: t.bad
        case .login: t.special
        case .session: t.good
        }
    }
}

/// Rellenar los huecos de un botón ({{interfaz}}, {{peer=10.0.0.1}}): propone lo copiado, lo que ha salido en la
/// pantalla (interfaces e IPs) y lo que usaste otras veces. Esc = no se envía nada.
struct ButtonFillSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var t
    @Stored private var values: [String: String] = [:]

    static let interface = try! NSRegularExpression(pattern: #"(?i)\b(?:(?:xe|ge|et|mge|ae|irb|lo)-\d+(?:/\d+)*(?:\.\d+)?|(?:\d+|x|xx|ten|twenty five|forty|hundred)?g(?:ig(?:abit)?)?e?(?:thernet)?\d+(?:/\d+)+(?:\.\d+)?|(?:gi|te|tw|fo|hu|xg|ge|fa|eth|xge|mge|25ge|100ge|10ge|40ge)\d+(?:/\d+)+(?:\.\d+)?|eth-trunk\d+(?:\.\d+)?|vlanif\d+|bundle-ether\d+(?:\.\d+)?|port-channel\d+|ae\d+(?:\.\d+)?)\b"#)
    static let ip = try! NSRegularExpression(pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?\b"#)

    var body: some View {
        let b = model.pendingButton
        VStack(alignment: .leading, spacing: 14) {
            Text(b?.name ?? "").font(t.ui(15, .bold))
            Text(b.map { $0.filled(values) } ?? "").font(.system(.callout, design: .monospaced))
                .foregroundStyle(SwiftUI.Color(t.accent2)).textSelection(.enabled)
            ForEach(b?.holes ?? [], id: \.name) { h in
                HStack {
                    Text(h.name).frame(width: 110, alignment: .trailing)
                    TextField(h.value, text: Binding(get: { values[h.name] ?? "" }, set: { values[h.name] = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Menu {
                        ForEach(suggestions(for: h.name), id: \.self) { v in Button(v) { values[h.name] = v } }
                    } label: { Image(systemName: "list.bullet") }
                        .menuStyle(.button).fixedSize()
                        .disabled(suggestions(for: h.name).isEmpty)
                }
            }
            HStack {
                Spacer()
                Button("Cancelar") { model.pendingButton = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.multiExecOn ? "Enviar a todas (MultiExec)" : "Enviar") { send() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            for h in b?.holes ?? [] { values[h.name] = h.value.isEmpty ? (suggestions(for: h.name).first ?? "") : h.value }
        }
    }

    private func send() {
        guard let b = model.pendingButton else { return }
        var filled = values
        for h in b.holes {
            let v = (values[h.name] ?? "").trimmingCharacters(in: .whitespaces)
            filled[h.name] = v.isEmpty ? h.value : v
            Self.remember(h.name, filled[h.name] ?? "")
        }
        model.pendingButton = nil
        dismiss()
        model.runButton(b, values: filled)
    }

    /// Lo copiado (si encaja), lo de la pantalla y lo usado otras veces, según el nombre del hueco.
    private func suggestions(for name: String) -> [String] {
        let n = name.lowercased()
        let wantsIP = ["ip", "peer", "vecino", "neighbor", "next", "gw", "gateway", "destino", "host", "prefijo", "red"]
            .contains { n.hasPrefix($0) || n.contains("_\($0)") || n.contains("-\($0)") }
        let wantsIf = ["int", "if", "puerto", "port", "eth", "ge", "xe", "trunk"].contains { n.hasPrefix($0) }
        var regs: [NSRegularExpression] = wantsIP ? [Self.ip] : (wantsIf ? [Self.interface] : [Self.interface, Self.ip])
        if !wantsIP, !wantsIf, n.contains("vlan") { regs = [] }
        var out: [String] = []
        if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty, clip.count < 60, !clip.contains("\n"),
           regs.isEmpty || regs.contains(where: { $0.firstMatch(in: clip, range: NSRange(clip.startIndex..., in: clip)) != nil }) {
            out.append(clip)
        }
        if let s = model.current {
            let text = s.lines(from: max(0, s.cursorRow - 300)).joined(separator: "\n")
            for r in regs {
                for m in r.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                    if let rr = Range(m.range, in: text) { out.append(String(text[rr])) }
                }
            }
        }
        out += UserDefaults.standard.stringArray(forKey: "hueco.\(n)") ?? []
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }.prefix(15).map { $0 }
    }

    static func remember(_ name: String, _ v: String) {
        guard !v.isEmpty else { return }
        let k = "hueco.\(name.lowercased())"
        var l = UserDefaults.standard.stringArray(forKey: k) ?? []
        l.removeAll { $0 == v }
        l.insert(v, at: 0)
        UserDefaults.standard.set(Array(l.prefix(10)), forKey: k)
    }
}

/// Editor de botones (Ajustes → Botones): el mismo botones.txt que NetDeck.
struct ButtonEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Stored private var file = ButtonFile()
    @Stored private var selected: UUID?
    @Stored private var message = ""
    @Stored private var loaded = false

    static let keys = [""] + (1...12).flatMap { n in ["", "S-", "M-", "C-"].map { "\($0)F\(n)" } }

    var body: some View {
        @Bindable var s = model.settings
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Barra", selection: $s.buttonBar) {
                    Text("Arriba").tag("arriba")
                    Text("Abajo").tag("abajo")
                    Text("Oculta").tag("oculta")
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                Toggle("Por grupos (☰)", isOn: $s.buttonBarGrouped)
                Spacer()
                Text(ButtonFile.defaultURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            .padding(14)
            HStack(spacing: 0) {
                list.frame(width: 270)
                Divider()
                if let i = file.buttons.firstIndex(where: { $0.id == selected }) { form(i) } else {
                    Text("Elige un botón o crea uno").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                if let p = file.problems.first { Text("⚠︎ \(p)").font(.caption).foregroundStyle(.orange).lineLimit(1) }
                Text(message).font(.caption).lineLimit(1)
                Spacer()
                Button("Recargar") { load() }
                Button("Guardar") {
                    message = model.saveButtons(file).map { "✗ \($0)" } ?? "✓ Guardados (NetDeck los ve al momento)"
                }
                .keyboardShortcut("s")
                .disabled(file.render() == model.buttons.render())
            }
            .padding(12)
        }
        .onAppear { if !loaded { load() } }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(file.groups, id: \.self) { g in
                    Section(g) {
                        ForEach(file.buttons.filter { $0.group == g }) { b in
                            HStack {
                                Text(b.name)
                                Spacer()
                                if let k = b.hotkey { Text(k).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                                Text(b.mode.rawValue).font(.caption2).foregroundStyle(.secondary)
                            }
                            .tag(b.id)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            HStack(spacing: 4) {
                Button { add() } label: { Image(systemName: "plus") }.help("Nuevo botón")
                Button { remove() } label: { Image(systemName: "minus") }.disabled(selected == nil).help("Borrar")
                Button { move(-1) } label: { Image(systemName: "arrow.up") }.disabled(selected == nil).help("Subir")
                Button { move(1) } label: { Image(systemName: "arrow.down") }.disabled(selected == nil).help("Bajar")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func form(_ i: Int) -> some View {
        let b = $file.buttons[i]
        return Form {
            TextField("Grupo", text: b.group)
            TextField("Nombre", text: b.name)
            Picker("Modo", selection: b.mode) {
                ForEach(CommandButton.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField(prompt(file.buttons[i].mode), text: b.command, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...6)
            Picker("Tecla rápida", selection: Binding(get: { file.buttons[i].hotkey ?? "" },
                                                       set: { file.buttons[i].hotkey = $0.isEmpty ? nil : $0 })) {
                ForEach(Self.keys, id: \.self) { k in Text(k.isEmpty ? "(ninguna)" : keyName(k)).tag(k) }
            }
            if let k = file.buttons[i].hotkey, file.buttons.filter({ $0.hotkey == k }).count > 1 {
                Text("La tecla \(k) la usa otro botón").font(.caption).foregroundStyle(.orange)
            }
            Text(help(file.buttons[i].mode)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Probar en la pestaña activa") { model.runButton(file.buttons[i]) }.disabled(model.current == nil)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func prompt(_ m: CommandButton.Mode) -> String {
        switch m {
        case .run: "Orden (varias con « ;; »)"
        case .type: "Texto a escribir"
        case .pass: "Nombre de la contraseña del Llavero"
        case .login: "usuario / nombre-de-la-contraseña"
        case .session: "Sesión del ssh_config"
        }
    }

    private func help(_ m: CommandButton.Mode) -> String {
        switch m {
        case .run: "Escribe la orden y pulsa Intro. Varias: una a una esperando al equipo (se para si da error). Huecos: {{interfaz}}, {{vlan=100}}."
        case .type: "Sólo la escribe, para que la completes tú. También admite huecos {{…}}."
        case .pass: "Escribe esa contraseña del Llavero + Intro, sólo si la línea pide «Password:» (si no, no hace nada)."
        case .login: "Escribe el usuario cuando pidan «Username:/login:» y luego su contraseña cuando la pidan."
        case .session: "Abre una pestaña con esa sesión."
        }
    }

    private func keyName(_ k: String) -> String {
        k.replacingOccurrences(of: "S-", with: "⇧").replacingOccurrences(of: "M-", with: "⌥").replacingOccurrences(of: "C-", with: "⌃")
    }

    private func load() {
        file = model.buttons
        loaded = true
        selected = selected ?? file.buttons.first?.id
        message = FileManager.default.fileExists(atPath: ButtonFile.defaultURL.path) ? "" : "Botones de ejemplo: «Guardar» para crear el archivo"
    }

    private func add() {
        let g = file.buttons.first { $0.id == selected }?.group ?? model.settings.buttonGroup
        let b = CommandButton(group: g.isEmpty ? "General" : g, mode: .run, name: "Nuevo", command: "")
        let at = (file.buttons.lastIndex { $0.group == b.group }).map { $0 + 1 } ?? file.buttons.count
        file.buttons.insert(b, at: at)
        selected = b.id
    }

    private func remove() {
        guard let i = file.buttons.firstIndex(where: { $0.id == selected }) else { return }
        file.buttons.remove(at: i)
        selected = file.buttons.indices.contains(i) ? file.buttons[i].id : file.buttons.last?.id
    }

    private func move(_ d: Int) {
        guard let i = file.buttons.firstIndex(where: { $0.id == selected }) else { return }
        let g = file.buttons[i].group
        var j = i + d
        while file.buttons.indices.contains(j), file.buttons[j].group != g { j += d }
        guard file.buttons.indices.contains(j) else { return }
        file.buttons.swapAt(i, j)
    }
}
