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
                .help(L("Cambiar de grupo de botones"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(shown) { b in CommandChip(button: b) }
                    if shown.isEmpty {
                        Text(L("Sin botones · ✎ para crear")).font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim))
                    }
                }
                .padding(.vertical, 4)
            }
            IconButton(icon: "pencil") { model.openSettings("botones") }
                .help(L("Editar los botones"))
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
        .help("\(button.mode.title): \(button.mode == .pass ? L("contraseña «\(button.command)»") : button.command)"
              + (model.multiExecOn ? L(" · en todas (MultiExec)") : ""))
        .contextMenu {
            Button(L("Editar…")) { model.openSettings("botones") }
            Button(L("Copiar la orden")) {
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

/// Rellenar los huecos de un botón ({{interfaz}}, {{peer=192.0.2.1}}): propone lo copiado, lo que ha salido en la
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
                Button(L("Cancelar")) { model.pendingButton = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.multiExecOn ? L("Enviar a todas (MultiExec)") : L("Enviar")) { send() }.keyboardShortcut(.defaultAction)
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
                Picker(L("Barra"), selection: $s.buttonBar) {
                    Text(L("Arriba")).tag("arriba")
                    Text(L("Abajo")).tag("abajo")
                    Text(L("Oculta")).tag("oculta")
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                Toggle(L("Por grupos (☰)"), isOn: $s.buttonBarGrouped)
                Spacer()
                Text(AppPaths.tilde(ButtonFile.defaultURL.path))
                    .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            .padding(14)
            HStack(spacing: 0) {
                list.frame(width: 270)
                Divider()
                if let i = file.buttons.firstIndex(where: { $0.id == selected }) { form(i) } else {
                    Text(L("Elige un botón o crea uno")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                if let p = file.problems.first { Text("⚠︎ \(p)").font(.caption).foregroundStyle(.orange).lineLimit(1) }
                Text(message).font(.caption).lineLimit(1)
                Spacer()
                Button(L("Recargar")) { load() }
                Button(L("Guardar")) {
                    message = model.saveButtons(file).map { "✗ \($0)" } ?? L("✓ Guardados")
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
                    Section {
                        ForEach(file.buttons.filter { $0.group == g }) { b in
                            HStack {
                                Text(b.name)
                                Spacer()
                                if let k = b.hotkey { Text(k).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                                Text(b.mode.rawValue).font(.caption2).foregroundStyle(.secondary)
                            }
                            .tag(b.id)
                            .contextMenu { buttonMenu(b.id) }
                        }
                    } header: {
                        HStack {
                            Text(g)
                            Spacer()
                            Menu { groupMenu(g) } label: { Image(systemName: "ellipsis.circle") }
                                .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                                .help(L("Categoría: renombrar, ordenar, borrar…"))
                        }
                        .contextMenu { groupMenu(g) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            HStack(spacing: 4) {
                Button { add() } label: { Image(systemName: "plus") }.help(L("Nuevo botón"))
                Button { remove() } label: { Image(systemName: "minus") }.disabled(selected == nil).help(L("Borrar"))
                Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(selected == nil).help(L("Duplicar"))
                Button { move(-1) } label: { Image(systemName: "arrow.up") }.disabled(selected == nil).help(L("Subir"))
                Button { move(1) } label: { Image(systemName: "arrow.down") }.disabled(selected == nil).help(L("Bajar"))
                Spacer()
                Button { addGroup() } label: { Image(systemName: "folder.badge.plus") }.help(L("Nueva categoría"))
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    @ViewBuilder private func groupMenu(_ g: String) -> some View {
        let gs = file.groups
        Button(L("Renombrar…")) { renameGroup(g) }
        Button(L("Subir la categoría")) { file.moveGroup(g, by: -1) }.disabled(gs.first == g)
        Button(L("Bajar la categoría")) { file.moveGroup(g, by: 1) }.disabled(gs.last == g)
        Button(L("Nuevo botón aquí")) { add(in: g) }
        Divider()
        Menu(L("Borrar y pasar sus botones a…")) {
            ForEach(gs.filter { $0 != g }, id: \.self) { o in Button(o) { file.removeGroup(g, movingTo: o) } }
        }
        .disabled(gs.count < 2)
        Button(L("Borrar con sus botones…"), role: .destructive) { removeGroup(g) }
    }

    @ViewBuilder private func buttonMenu(_ id: CommandButton.ID) -> some View {
        let g = file.buttons.first { $0.id == id }?.group
        Button(L("Duplicar")) { selected = file.duplicateButton(id, suffix: L(" (copia)")) ?? selected }
        Menu(L("Mover a la categoría")) {
            ForEach(file.groups.filter { $0 != g }, id: \.self) { o in Button(o) { file.moveButton(id, toGroup: o) } }
            Divider()
            Button(L("Nueva categoría…")) {
                if let n = SessionEditor.ask(L("Nombre de la categoría nueva")), ButtonFile.validGroup(n) {
                    file.moveButton(id, toGroup: n)
                }
            }
        }
        Button(L("Borrar"), role: .destructive) { selected = id; remove() }
    }

    private func form(_ i: Int) -> some View {
        let b = $file.buttons[i]
        return Form {
            Picker(L("Categoría"), selection: Binding(get: { file.buttons[i].group },
                                                     set: { file.moveButton(file.buttons[i].id, toGroup: $0) })) {
                ForEach(file.groups, id: \.self) { Text($0).tag($0) }
            }
            TextField(L("Nombre"), text: b.name)
            Picker(L("Modo"), selection: b.mode) {
                ForEach(CommandButton.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            commandField(i)
            Picker(L("Tecla rápida"), selection: Binding(get: { file.buttons[i].hotkey ?? "" },
                                                       set: { file.buttons[i].hotkey = $0.isEmpty ? nil : $0 })) {
                ForEach(Self.keys, id: \.self) { k in Text(k.isEmpty ? L("(ninguna)") : keyName(k)).tag(k) }
            }
            if let k = file.buttons[i].hotkey, file.buttons.filter({ $0.hotkey == k }).count > 1 {
                Text(L("La tecla \(k) la usa otro botón")).font(.caption).foregroundStyle(.orange)
            }
            Text(help(file.buttons[i].mode)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L("Probar en la pestaña activa")) { model.runButton(file.buttons[i]) }.disabled(model.current == nil)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// Lo que hace el botón: texto libre para órdenes y textos; para contraseña, login y sesión se elige de una lista
    /// (las contraseñas con nombre del Llavero, tus sesiones), sin tener que acordarse del nombre exacto.
    @ViewBuilder private func commandField(_ i: Int) -> some View {
        let b = $file.buttons[i]
        switch file.buttons[i].mode {
        case .pass:
            credentialPicker(L("Contraseña del Llavero"), selection: b.command)
        case .login:
            let parts = file.buttons[i].command.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            let user = parts.first ?? "", cred = parts.count > 1 ? parts[1] : ""
            TextField(L("Usuario"), text: Binding(get: { user }, set: { file.buttons[i].command = "\($0.trimmingCharacters(in: .whitespaces)) / \(cred)" }))
            credentialPicker(L("Su contraseña del Llavero"), selection: Binding(get: { cred }, set: { file.buttons[i].command = "\(user) / \($0)" }))
        case .session:
            let names = model.sessions.profiles.map(\.name)
            Picker(L("Sesión"), selection: b.command) {
                Text(L("(elige una)")).tag("")
                ForEach(names, id: \.self) { Text($0).tag($0) }
                if !b.command.wrappedValue.isEmpty, !names.contains(b.command.wrappedValue) {
                    Text(L("\(b.command.wrappedValue) (no está en tus sesiones)")).tag(b.command.wrappedValue)
                }
            }
        case .run, .type:
            TextField(prompt(file.buttons[i].mode), text: b.command, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...6)
        }
    }

    /// Las contraseñas con nombre del Llavero (las que usan los botones); si la del botón ya no está, se ve y se avisa.
    @ViewBuilder private func credentialPicker(_ title: String, selection: Binding<String>) -> some View {
        let named = model.keychainAccounts.filter { $0.service == .named }.map(\.account)
        HStack {
            Picker(title, selection: selection) {
                Text(L("(elige una)")).tag("")
                ForEach(named, id: \.self) { Text($0).tag($0) }
                if !selection.wrappedValue.isEmpty, !named.contains(selection.wrappedValue) {
                    Text(L("\(selection.wrappedValue) (no está en el Llavero)")).tag(selection.wrappedValue)
                }
            }
            Button(L("Gestionar…")) { model.openSettings("contraseñas") }
                .help(L("Guardar o cambiar contraseñas del Llavero (Ajustes → Contraseñas)"))
        }
        if named.isEmpty {
            Text(L("No hay contraseñas con nombre en el Llavero: guárdala primero en Ajustes → Contraseñas."))
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private func prompt(_ m: CommandButton.Mode) -> String {
        switch m {
        case .run: L("Orden (varias con « ;; »)")
        case .type: L("Texto a escribir")
        case .pass: L("Nombre de la contraseña del Llavero")
        case .login: L("usuario / nombre-de-la-contraseña")
        case .session: L("Sesión del ssh_config")
        }
    }

    private func help(_ m: CommandButton.Mode) -> String {
        switch m {
        case .run: L("Escribe la orden y pulsa Intro. Varias: una a una esperando al equipo (se para si da error). Huecos: {{interfaz}}, {{vlan=100}}.")
        case .type: L("Sólo la escribe, para que la completes tú. También admite huecos {{…}}.")
        case .pass: L("Escribe esa contraseña del Llavero + Intro, sólo si la línea pide «Password:» (si no, no hace nada).")
        case .login: L("Escribe el usuario cuando pidan «Username:/login:» y luego su contraseña cuando la pidan.")
        case .session: L("Abre una pestaña con esa sesión.")
        }
    }

    private func keyName(_ k: String) -> String {
        k.replacingOccurrences(of: "S-", with: "⇧").replacingOccurrences(of: "M-", with: "⌥").replacingOccurrences(of: "C-", with: "⌃")
    }

    private func load() {
        file = model.buttons
        loaded = true
        selected = selected ?? file.buttons.first?.id
        message = FileManager.default.fileExists(atPath: ButtonFile.defaultURL.path) ? "" : L("Botones de ejemplo: «Guardar» para crear el archivo")
    }

    private func add(in group: String? = nil) {
        let g = group ?? file.buttons.first { $0.id == selected }?.group ?? model.settings.buttonGroup
        let b = CommandButton(group: g.isEmpty ? "General" : g, mode: .run, name: L("Nuevo"), command: "")
        let at = (file.buttons.lastIndex { $0.group == b.group }).map { $0 + 1 } ?? file.buttons.count
        file.buttons.insert(b, at: at)
        selected = b.id
    }

    private func duplicate() {
        guard let id = selected else { return }
        selected = file.duplicateButton(id, suffix: L(" (copia)")) ?? selected
    }

    private func remove() {
        guard let i = file.buttons.firstIndex(where: { $0.id == selected }) else { return }
        file.buttons.remove(at: i)
        selected = file.buttons.indices.contains(i) ? file.buttons[i].id : file.buttons.last?.id
    }

    private func move(_ d: Int) {
        guard let id = selected else { return }
        file.moveButton(id, by: d)
    }

    // MARK: categorías (el grupo de cada botón; el orden, el del archivo)

    private func addGroup() {
        guard let n = SessionEditor.ask(L("Nombre de la categoría nueva"))?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return }
        if file.groups.contains(n) { message = L("Ya hay una categoría «\(n)»"); return }
        guard let id = file.addGroup(n, buttonName: L("Nuevo")) else { message = L("Nombre no válido (sin «::» ni «#» delante)"); return }
        selected = id
    }

    private func renameGroup(_ g: String) {
        guard let n = SessionEditor.ask(L("Renombrar la categoría «\(g)»"), value: g)?.trimmingCharacters(in: .whitespaces), !n.isEmpty, n != g else { return }
        guard ButtonFile.validGroup(n) else { message = L("Nombre no válido (sin «::» ni «#» delante)"); return }
        if file.groups.contains(n), !confirm(L("Ya hay una categoría «\(n)»: ¿juntarlas?"), L("Juntar")) { return }
        file.renameGroup(g, to: n)
        if model.settings.buttonGroup == g { model.settings.buttonGroup = n }
    }

    private func removeGroup(_ g: String) {
        let n = file.buttons.filter { $0.group == g }.count
        guard confirm(L("¿Borrar la categoría «\(g)» y sus \(n) botones?"), L("Borrar")) else { return }
        file.removeGroup(g)
        if !file.buttons.contains(where: { $0.id == selected }) { selected = file.buttons.first?.id }
    }

    private func confirm(_ title: String, _ ok: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = L("No se guarda hasta que pulses «Guardar» (queda copia en botones.txt.anterior).")
        a.addButton(withTitle: ok)
        a.addButton(withTitle: L("Cancelar"))
        return a.runModal() == .alertFirstButtonReturn
    }
}
