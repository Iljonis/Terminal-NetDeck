import AppKit
import NetDeckCore
import SwiftUI

/// Gestor de Sesiones (como el de NetDeck / el Session Manager de SecureCRT): crear, editar, duplicar, borrar,
/// grupos y su contraseña, importar. Guarda en ~/.config/netdeck/ssh_config (el mismo que NetDeck).
struct SessionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @Stored private var file = SessionFile()
    @Stored private var saved = SessionFile()
    @Stored private var selected: UUID?
    @Stored private var query = ""
    @Stored private var message = ""
    @Stored private var importing = false
    @Stored private var newPassword = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                list.frame(width: 300)
                NeonLine(vertical: true, color: t.panel)
                Group {
                    if importing {
                        ImportPane(file: $file) { ids in
                            importing = false
                            selected = ids.first
                            message = "\(ids.count) importadas: revísalas y pulsa «Guardar»"
                        }
                    } else if let i = index {
                        form(i)
                    } else {
                        placeholder
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            NeonLine(color: t.panel)
            footer
        }
        .frame(width: 940, height: 640)
        .background(SwiftUI.Color(t.background))
        .onAppear(perform: load)
    }

    private var index: Int? { file.sessions.firstIndex { $0.id == selected } }
    private var dirty: Bool { file.render() != saved.render() }

    // MARK: lista

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SESIONES").font(t.ui(13, .heavy)).tracking(3).foregroundStyle(SwiftUI.Color(t.accent))
                Text("\(file.sessions.count)").font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim))
                Spacer()
                if dirty { Text("● sin guardar").font(t.ui(10, .bold)).foregroundStyle(SwiftUI.Color(t.warning)) }
            }
            .padding(.horizontal, 12).padding(.top, 14)
            SearchField(text: $query, prompt: "Filtrar").padding(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(file.groups, id: \.self) { g in
                        let items = file.sessions.filter { $0.group == g && matches($0) }
                        if !items.isEmpty {
                            groupHeader(g)
                            ForEach(items) { row($0) }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            NeonLine(color: t.panel)
            HStack(spacing: 6) {
                IconButton(icon: "plus") { add(group: index.map { file.sessions[$0].group }) }.help("Nueva sesión")
                IconButton(icon: "plus.square.on.square") { duplicate() }.help("Duplicar").disabled(index == nil)
                IconButton(icon: "trash") { delete() }.help("Borrar").disabled(index == nil)
                Spacer()
                NeonButton(title: "Importar", icon: "square.and.arrow.down", tint: t.accent2) { importing = true }
                    .help("SecureCRT, MobaXterm, PuTTY, electerm, CSV o un ssh_config")
            }
            .padding(8)
        }
        .background(SwiftUI.Color(t.bar))
    }

    private func matches(_ s: EditableSession) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || [s.name, s.host, s.user, s.summary, s.group].contains { $0.lowercased().contains(q) }
    }

    private func groupHeader(_ g: String) -> some View {
        HStack(spacing: 6) {
            Text(g.uppercased()).font(t.ui(10, .bold)).tracking(2).foregroundStyle(SwiftUI.Color(t.accent2))
            if let c = file.groupCredentials[g], !c.isEmpty {
                Image(systemName: "key.fill").font(.system(size: 8)).foregroundStyle(SwiftUI.Color(t.warning)).help("Contraseña del grupo: \(c)")
            }
            Rectangle().fill(SwiftUI.Color(t.accent2).opacity(0.25)).frame(height: 1)
            Menu {
                Button("Nueva sesión en «\(g)»") { add(group: g) }
                Button("Renombrar grupo…") { renameGroup(g) }
                Menu("Contraseña del grupo") {
                    Button("(ninguna)") { file.groupCredentials[g] = nil }
                    ForEach(namedCredentials, id: \.self) { n in Button(n) { file.groupCredentials[g] = n } }
                }
                Divider()
                Button("Quitar el grupo (sus sesiones pasan a General)") { removeGroup(g) }
            } label: { Image(systemName: "ellipsis.circle").foregroundStyle(SwiftUI.Color(t.dim)) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 6).padding(.top, 12).padding(.bottom, 4)
    }

    private func row(_ s: EditableSession) -> some View {
        let on = s.id == selected
        return HStack(spacing: 8) {
            Image(systemName: s.telnet ? "cable.connector" : (s.jump.isEmpty ? "terminal.fill" : "arrow.triangle.turn.up.right.diamond.fill"))
                .font(.system(size: 10)).foregroundStyle(SwiftUI.Color(on ? t.onTab : t.accent2)).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(t.ui(12, .semibold)).lineLimit(1)
                Text(endpoint(s)).font(t.ui(9.5)).opacity(0.7).lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.favorites.contains(s.name) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(SwiftUI.Color(t.warning)) }
        }
        .foregroundStyle(SwiftUI.Color(on ? t.onTab : t.text))
        .padding(.vertical, 5).padding(.horizontal, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? SwiftUI.Color(t.tab) : SwiftUI.Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { importing = false; selected = s.id; newPassword = "" }
        .contextMenu {
            Button("Duplicar") { selected = s.id; duplicate() }
            Button("Borrar") { selected = s.id; delete() }
        }
    }

    private func endpoint(_ s: EditableSession) -> String {
        (s.user.isEmpty ? "" : "\(s.user)@") + (s.host.isEmpty ? s.name : s.host) + (s.port == "22" || s.port.isEmpty ? "" : ":\(s.port)")
            + (s.jump.isEmpty ? "" : "  ⟵ \(s.jump)")
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "server.rack").font(.system(size: 34)).foregroundStyle(SwiftUI.Color(t.accent2))
            Text("Elige una sesión o crea una nueva").font(t.ui(13)).foregroundStyle(SwiftUI.Color(t.dim))
            HStack {
                NeonButton(title: "Nueva sesión", icon: "plus") { add(group: nil) }
                NeonButton(title: "Importar", icon: "square.and.arrow.down", tint: t.accent2) { importing = true }
            }
        }
    }

    // MARK: formulario

    private func form(_ i: Int) -> some View {
        let s = $file.sessions[i]
        let others = file.sessions.map(\.name).filter { $0 != file.sessions[i].name }
        let user = file.sessions[i].user.isEmpty ? NSUserName() : file.sessions[i].user
        let host = file.sessions[i].host.isEmpty ? file.sessions[i].name : file.sessions[i].host
        return Form {
            Section {
                HStack {
                    TextField("Grupo", text: s.group)
                    Menu {
                        ForEach(file.groups, id: \.self) { g in Button(g) { file.sessions[i].group = g } }
                    } label: { Image(systemName: "chevron.down.circle") }
                        .menuStyle(.button).buttonStyle(.plain).fixedSize()
                }
                TextField("Nombre", text: s.name, prompt: Text("core-01 (sin espacios)"))
                if !EditableSession.isValidName(file.sessions[i].name) {
                    Text("Sin espacios ni * ? ! (es el nombre que usa ssh)").font(.caption).foregroundStyle(SwiftUI.Color(t.bad))
                }
                TextField("Descripción", text: s.summary, prompt: Text("opcional"))
            } header: { header("SESIÓN") }

            Section {
                Picker("Protocolo", selection: s.telnet) {
                    Text("SSH").tag(false)
                    Text("Telnet").tag(true)
                }
                .pickerStyle(.segmented)
                TextField("Equipo (nombre o IP)", text: s.host, prompt: Text("10.0.0.1"))
                TextField("Usuario", text: s.user, prompt: Text(NSUserName()))
                TextField("Puerto", text: s.port, prompt: Text(file.sessions[i].telnet ? "23" : "22"))
                Picker("Saltar por", selection: s.jump) {
                    Text("Directo").tag("")
                    if !file.sessions[i].jump.isEmpty, !others.contains(file.sessions[i].jump) {
                        Text(file.sessions[i].jump).tag(file.sessions[i].jump)
                    }
                    ForEach(others, id: \.self) { Text($0).tag($0) }
                }
                if !file.sessions[i].jump.isEmpty {
                    Text("Si el salto no deja reenviar (-J), la app entra en él y escribe «ssh equipo», como NetDeck.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !file.sessions[i].telnet {
                    HStack {
                        TextField("Clave privada", text: s.keyFile, prompt: Text("(ninguna)"))
                        Button("Elegir…") { chooseKey(i) }
                    }
                    Toggle("Equipo antiguo (algoritmos ssh viejos)", isOn: s.legacy)
                }
            } header: { header("CONEXIÓN") }

            Section {
                Picker("Contraseña", selection: s.credential) {
                    Text("Automática (la de \(user)@\(host) o la por defecto)").tag("")
                    Text("La propia del equipo (-)").tag("-")
                    if !file.sessions[i].credential.isEmpty, file.sessions[i].credential != "-",
                       !namedCredentials.contains(file.sessions[i].credential) {
                        Text("\(file.sessions[i].credential) (no está en el Llavero)").tag(file.sessions[i].credential)
                    }
                    ForEach(namedCredentials, id: \.self) { Text("🔑 \($0)").tag($0) }
                }
                Picker("Del grupo «\(file.sessions[i].group)»", selection: Binding(
                    get: { file.groupCredentials[file.sessions[i].group] ?? "" },
                    set: { file.groupCredentials[file.sessions[i].group] = $0.isEmpty ? nil : $0 })) {
                    Text("(ninguna)").tag("")
                    ForEach(namedCredentials, id: \.self) { Text("🔑 \($0)").tag($0) }
                }
                HStack {
                    SecureField("Guardar una para \(user)@\(host)", text: $newPassword)
                    Button("Al Llavero") { savePassword(user: user, host: host) }.disabled(newPassword.isEmpty)
                }
                if model.store.contains(.device(user, host)) {
                    Text("✓ Hay una guardada para \(user)@\(host)").font(.caption).foregroundStyle(SwiftUI.Color(t.good))
                }
            } header: { header("CONTRASEÑA (LLAVERO)") } footer: {
                Text("Nunca se escribe sola la de otro usuario: sólo la de ese mismo usuario.").font(.caption)
            }

            Section {
                TextEditor(text: Binding(get: { file.sessions[i].extra.joined(separator: "\n") },
                                         set: { file.sessions[i].extra = $0.components(separatedBy: .newlines)
                                             .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 60)
            } header: { header("OPCIONES DE SSH (AVANZADO)") } footer: {
                Text("Una por línea: LocalForward 8080 10.0.0.1:80 · ServerAliveInterval 30 · …").font(.caption)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func header(_ s: String) -> some View {
        Text(s).font(t.ui(10, .bold)).tracking(2).foregroundStyle(SwiftUI.Color(t.accent2))
    }

    // MARK: pie

    private var footer: some View {
        HStack(spacing: 10) {
            let problems = file.problems()
            if let p = problems.first {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SwiftUI.Color(t.bad))
                Text(p).font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.bad)).lineLimit(2)
            } else {
                Text(message.isEmpty ? SessionFile.defaultURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") + " · lo comparte con NetDeck" : message)
                    .font(t.ui(11)).foregroundStyle(SwiftUI.Color(message.hasPrefix("✗") ? t.bad : t.dim)).lineLimit(2)
            }
            Spacer()
            Button("Cerrar") { close() }.keyboardShortcut(.cancelAction)
            NeonButton(title: "Guardar y conectar", icon: "bolt.horizontal.fill", tint: t.good) { save(connect: true) }
                .disabled(!problems.isEmpty || index == nil)
            NeonButton(title: "Guardar", icon: "checkmark", active: dirty) { save(connect: false) }
                .disabled(!problems.isEmpty || !dirty)
                .keyboardShortcut("s")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(SwiftUI.Color(t.bar))
    }

    // MARK: acciones

    private var namedCredentials: [String] {
        model.keychainAccounts.filter { $0.service == .named }.map(\.account)
    }

    private func load() {
        file = model.sessionFile
        saved = file
        switch model.editorFocus {
        case .session(let n): selected = file.sessions.first { $0.name == n }?.id
        case .new(let g): add(group: g)
        case .importing: importing = true
        case nil: selected = file.sessions.first?.id
        }
        model.editorFocus = nil
    }

    private func add(group: String?) {
        let g = group ?? file.groups.first ?? "General"
        var n = "nueva", k = 2
        while file.sessions.contains(where: { $0.name.lowercased() == n }) { n = "nueva-\(k)"; k += 1 }
        let s = EditableSession(group: g, name: n)
        let at = (file.sessions.lastIndex { $0.group == g }).map { $0 + 1 } ?? file.sessions.count
        file.sessions.insert(s, at: at)
        selected = s.id
        importing = false
    }

    private func duplicate() {
        guard let i = index else { return }
        var c = file.sessions[i]
        var n = "\(c.name)-2", k = 3
        while file.sessions.contains(where: { $0.name.lowercased() == n.lowercased() }) { n = "\(c.name)-\(k)"; k += 1 }
        let copy = EditableSession(group: c.group, name: n)
        c.name = n
        var d = copy
        (d.summary, d.host, d.user, d.port, d.jump, d.keyFile) = (c.summary, c.host, c.user, c.port, c.jump, c.keyFile)
        (d.legacy, d.credential, d.telnet, d.extra) = (c.legacy, c.credential, c.telnet, c.extra)
        file.sessions.insert(d, at: i + 1)
        selected = d.id
    }

    private func delete() {
        guard let i = index else { return }
        let a = NSAlert()
        a.messageText = "¿Borrar la sesión «\(file.sessions[i].name)»?"
        a.informativeText = "Se quita al pulsar «Guardar» (queda una copia en ssh_config.anterior). Su contraseña del Llavero no se toca."
        a.addButton(withTitle: "Borrar")
        a.addButton(withTitle: "Cancelar")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        file.sessions.remove(at: i)
        selected = file.sessions.indices.contains(i) ? file.sessions[i].id : file.sessions.last?.id
    }

    private func renameGroup(_ g: String) {
        guard let n = Self.ask("Renombrar el grupo «\(g)»", value: g), !n.isEmpty, n != g else { return }
        for i in file.sessions.indices where file.sessions[i].group == g { file.sessions[i].group = n }
        if let c = file.groupCredentials.removeValue(forKey: g) { file.groupCredentials[n] = c }
    }

    private func removeGroup(_ g: String) {
        for i in file.sessions.indices where file.sessions[i].group == g { file.sessions[i].group = "General" }
        file.groupCredentials[g] = nil
    }

    private func chooseKey(_ i: Int) {
        let p = NSOpenPanel()
        p.showsHiddenFiles = true
        p.directoryURL = AppPaths.home.appendingPathComponent(".ssh")
        guard p.runModal() == .OK, let u = p.url else { return }
        file.sessions[i].keyFile = u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func savePassword(user: String, host: String) {
        let ref = CredentialRef.device(user, host)
        do {
            try model.store.save(newPassword, for: ref)
            model.ledger.reset(ref)
            model.keychainRevision += 1
            message = "✓ Contraseña de \(user)@\(host) guardada en el Llavero"
        } catch {
            message = "✗ \(error.localizedDescription)"
        }
        newPassword = ""
    }

    private func save(connect: Bool) {
        if dirty {
            if let err = model.saveSessions(file) {
                message = "✗ \(err)"
                return
            }
            saved = file
            message = "✓ Guardadas"
        }
        if connect, let i = index, let p = model.sessions.profile(named: file.sessions[i].name) {
            model.open(p)
            dismiss()
        }
    }

    private func close() {
        if dirty {
            let a = NSAlert()
            a.messageText = "Hay cambios sin guardar"
            a.addButton(withTitle: "Guardar")
            a.addButton(withTitle: "Descartar")
            a.addButton(withTitle: "Cancelar")
            switch a.runModal() {
            case .alertFirstButtonReturn:
                if let err = model.saveSessions(file) { message = "✗ \(err)"; return }
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        dismiss()
    }

    static func ask(_ title: String, value: String = "") -> String? {
        let a = NSAlert()
        a.messageText = title
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        f.stringValue = value
        a.accessoryView = f
        a.addButton(withTitle: "Aceptar")
        a.addButton(withTitle: "Cancelar")
        a.window.initialFirstResponder = f
        return a.runModal() == .alertFirstButtonReturn ? f.stringValue.trimmingCharacters(in: .whitespaces) : nil
    }
}

/// Importar: lo que hay en este Mac (SecureCRT, exports) o un archivo/carpeta; marcas cuáles y se añaden al gestor.
struct ImportPane: View {
    @Environment(\.theme) private var t
    @Binding var file: SessionFile
    let done: ([UUID]) -> Void
    @Stored private var result: SessionImporter.Result?
    @Stored private var chosen: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("IMPORTAR SESIONES").font(t.ui(16, .heavy)).tracking(3).foregroundStyle(SwiftUI.Color(t.accent))
            Text("SecureCRT (la carpeta Sessions o un .ini), MobaXterm (.mxtsessions), PuTTY (.reg), electerm (.json), "
                 + "CSV del inventario o un ssh_config. Las carpetas pasan a ser grupos. Nunca se importa ninguna contraseña.")
                .font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            HStack(spacing: 8) {
                ForEach(SessionImporter.suggestions(), id: \.1) { name, url in
                    NeonButton(title: name, icon: "sparkles", tint: t.accent2) { read(url) }
                }
                NeonButton(title: "Elegir archivo o carpeta…", icon: "folder") { pick() }
            }
            if let r = result {
                HStack {
                    Text("\(r.format): \(r.sessions.count) nuevas").font(t.ui(12, .bold))
                    if !r.skipped.isEmpty { Text("· \(r.skipped.count) saltadas").font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim)) }
                    Spacer()
                    Button(chosen.count == r.sessions.count ? "Ninguna" : "Todas") {
                        chosen = chosen.count == r.sessions.count ? [] : Set(r.sessions.map(\.id))
                    }
                }
                List {
                    ForEach(r.sessions) { s in
                        Toggle(isOn: Binding(get: { chosen.contains(s.id) },
                                             set: { if $0 { chosen.insert(s.id) } else { chosen.remove(s.id) } })) {
                            HStack {
                                Text(s.name).font(t.ui(12, .semibold))
                                Text("\(s.user.isEmpty ? "" : s.user + "@")\(s.host):\(s.port)\(s.jump.isEmpty ? "" : " ⟵ " + s.jump)\(s.telnet ? " · telnet" : "")")
                                    .font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim))
                                Spacer()
                                Text(s.group).font(t.ui(10, .bold)).foregroundStyle(SwiftUI.Color(t.accent2))
                            }
                        }
                    }
                    if !r.skipped.isEmpty {
                        Section("Saltadas") {
                            ForEach(Array(r.skipped.enumerated()), id: \.offset) { _, x in
                                Text("\(x.0): \(x.1)").font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim))
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                HStack {
                    Spacer()
                    NeonButton(title: "Añadir \(chosen.count) al gestor", icon: "plus", active: !chosen.isEmpty) {
                        let add = r.sessions.filter { chosen.contains($0.id) }
                        file.sessions += add
                        done(add.map(\.id))
                    }
                    .disabled(chosen.isEmpty)
                }
            } else {
                Spacer()
            }
        }
        .padding(20)
    }

    private func pick() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.showsHiddenFiles = true
        guard p.runModal() == .OK, let u = p.url else { return }
        read(u)
    }

    private func read(_ u: URL) {
        let r = SessionImporter.read(u, existing: file.sessions)
        result = r
        chosen = Set(r.sessions.map(\.id))
    }
}
