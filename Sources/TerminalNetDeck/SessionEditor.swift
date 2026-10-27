import AppKit
import NetDeckCore
import SwiftUI

/// Gestor de Sesiones (como el Session Manager de SecureCRT): crear, editar, duplicar, borrar,
/// grupos y su contraseña, importar. Guarda en ~/.config/netdeck/ssh_config. Como hoja (⇧⌘E) o dentro de Ajustes
/// (`embedded`: ocupa la sección, sin «Cerrar»; los cambios sin guardar se preguntan al salir de ella).
struct SessionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    var embedded = false
    /// Quién pone el aviso de cambios sin guardar en Ajustes (`AppModel.settingsLeave`).
    @Stored private var token = UUID()
    @Stored private var file = SessionFile()
    @Stored private var saved = SessionFile()
    @Stored private var selected: UUID?
    @Stored private var query = ""
    @Stored private var message = ""
    @Stored private var importing = false
    @Stored private var newPassword = ""
    @Stored private var changing: CredentialRef?
    @Stored private var creatingCredential = false
    /// Puertos /dev/cu.* de este Mac (se buscan al abrir y con ↻).
    @Stored private var ports: [String] = []
    /// Fuentes monoespaciadas instaladas (para el perfil; se buscan al abrir).
    @Stored private var families: [String] = []
    /// Ya cargado (onAppear puede repetirse: no se vuelve a leer el archivo ni a crear otra sesión nueva).
    @Stored private var loaded = false
    /// Hay una acción en curso: los clics seguidos no la repiten.
    @Stored private var busy = false
    /// Guardando (en segundo plano): no se cierra ni se vuelve a guardar hasta que acabe.
    /// Mientras se guardan: ni cerrar, ni conectar, ni volver a guardar (`EditorSaveGate`).
    @Stored private var gate = EditorSaveGate()
    private var saving: Bool { gate.saving }

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
                            message = L("\(ids.count) importadas: revísalas y pulsa «Guardar»")
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
        .frame(width: embedded ? nil : 940, height: embedded ? nil : 640)
        .frame(maxWidth: embedded ? .infinity : nil, maxHeight: embedded ? .infinity : nil)
        .background(SwiftUI.Color(t.background))
        .onAppear {
            if embedded { model.settingsLeave = (token, { await confirmLeave() }) }
            guard !loaded else { return }
            loaded = true
            load()
            ports = SerialLine.devices()
            families = Fonts.monospacedFamilies()
        }
        .onDisappear {
            if model.settingsLeave?.owner == token { model.settingsLeave = nil }
        }
        .sheet(isPresented: Binding(get: { changing != nil }, set: { if !$0 { changing = nil } })) {
            if let ref = changing { PasswordChangeSheet(ref: ref) { message = $0 } }
        }
        .sheet(isPresented: $creatingCredential) {
            CredentialEditorSheet(ref: nil, namedOnly: true) { ref, result in
                if let i = index { file.sessions[i].credential = ref.account }
                message = result
            }
        }
    }

    private var index: Int? { file.sessions.firstIndex { $0.id == selected } }
    private var dirty: Bool { file.render() != saved.render() }

    // MARK: lista

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("SESIONES")).font(t.ui(13, .heavy)).tracking(3).foregroundStyle(SwiftUI.Color(t.accent))
                Text("\(file.sessions.count)").font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim))
                Spacer()
                if dirty { Text(L("● sin guardar")).font(t.ui(10, .bold)).foregroundStyle(SwiftUI.Color(t.warning)) }
            }
            .padding(.horizontal, 12).padding(.top, 14)
            SearchField(text: $query, prompt: L("Filtrar")).padding(10)
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
                IconButton(icon: "plus") { once { add(group: index.map { file.sessions[$0].group }) } }.help(L("Nueva sesión")).disabled(busy)
                IconButton(icon: "plus.square.on.square") { once(duplicate) }.help(L("Duplicar")).disabled(busy || index == nil)
                IconButton(icon: "trash") { once(delete) }.help(L("Borrar")).disabled(busy || index == nil)
                IconButton(icon: "chevron.up") { move(-1) }.help(L("Subir (dentro de su grupo)")).disabled(index == nil)
                IconButton(icon: "chevron.down") { move(1) }.help(L("Bajar (dentro de su grupo)")).disabled(index == nil)
                Spacer()
                ThemedMenu {
                    Button(L("Todas (JSON)…")) { export(groups: nil, csv: false) }
                    Button(L("Todas (CSV)…")) { export(groups: nil, csv: true) }
                    if !file.groups.isEmpty {
                        MenuDivider()
                        ForEach(file.groups, id: \.self) { g in Button(L("Grupo «\(g)» (JSON)…")) { export(groups: [g], csv: false) } }
                    }
                } label: { Image(systemName: "square.and.arrow.up") }.fixedSize()
                    .help(L("Exportar (sin contraseñas)"))
                IconButton(icon: "square.and.arrow.down", tint: t.accent2) { importing = true }      // (en la columna estrecha, sin texto: cabe entero)
                    .help(L("SecureCRT, MobaXterm, PuTTY, electerm, CSV, un ssh_config o un JSON exportado"))
            }
            .padding(8)
        }
        .background(SwiftUI.Color(t.bar))
    }

    private func matches(_ s: EditableSession) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || [s.name, s.host, s.user, s.summary, s.group, s.kind.label, s.serial.device]
            .contains { $0.lowercased().contains(q) }
    }

    private func groupHeader(_ g: String) -> some View {
        HStack(spacing: 6) {
            Text(g.uppercased()).font(t.ui(10, .bold)).tracking(2).foregroundStyle(SwiftUI.Color(t.accent2))
            if let c = file.groupCredentials[g], !c.isEmpty {
                Image(systemName: "key.fill").font(.system(size: 8)).foregroundStyle(SwiftUI.Color(t.warning)).help(L("Contraseña del grupo: \(c)"))
            }
            Rectangle().fill(SwiftUI.Color(t.accent2).opacity(0.25)).frame(height: 1)
            ThemedMenu {
                Button(L("Nueva sesión en «\(g)»")) { add(group: g) }
                Button(L("Renombrar grupo…")) { renameGroup(g) }
                Button(L("Exportar el grupo (JSON)…")) { export(groups: [g], csv: false) }
                Button(L("Exportar el grupo (CSV)…")) { export(groups: [g], csv: true) }
                ThemedSubmenu(title: L("Contraseña del grupo")) {
                    Button(L("(ninguna)")) { file.groupCredentials[g] = nil }
                    ForEach(namedCredentials, id: \.self) { n in Button(n) { file.groupCredentials[g] = n } }
                }
                MenuDivider()
                Button(L("Quitar el grupo (sus sesiones pasan a General)")) { removeGroup(g) }
            } label: { Image(systemName: "ellipsis.circle").foregroundStyle(SwiftUI.Color(t.dim)) }.fixedSize()
        }
        .padding(.horizontal, 6).padding(.top, 12).padding(.bottom, 4)
    }

    private func row(_ s: EditableSession) -> some View {
        let on = s.id == selected
        return HStack(spacing: 8) {
            Image(systemName: s.kind.icon(jump: !s.jump.isEmpty))
                .font(.system(size: 10)).foregroundStyle(SwiftUI.Color(on ? t.onTab : t.accent2)).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(t.ui(12, .semibold)).lineLimit(1)
                Text(endpoint(s)).font(t.ui(9.5)).opacity(0.7).lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.settings.startupSession == s.name {
                Image(systemName: "power").font(.system(size: 9)).foregroundStyle(SwiftUI.Color(t.warning)).help(L("Se abre al arrancar (⌥⌘K)"))
            }
            if model.favorites.contains(s.name) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(SwiftUI.Color(t.warning)) }
        }
        .foregroundStyle(SwiftUI.Color(on ? t.onTab : t.text))
        .padding(.vertical, 5).padding(.horizontal, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? SwiftUI.Color(t.tab) : SwiftUI.Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { importing = false; selected = s.id; newPassword = "" }
        // (arrastrar una sobre otra: se pone delante, en su grupo; el orden es el del archivo)
        .draggable(s.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)), id != s.id else { return false }
            file.move(id, to: s.id)
            selected = id
            return true
        }
        .themedContextMenu {
            Button(L("Subir")) { selected = s.id; move(-1) }
            Button(L("Bajar")) { selected = s.id; move(1) }
            MenuDivider()
            Button(L("Duplicar")) { selected = s.id; duplicate() }
            Button(L("Borrar")) { selected = s.id; delete() }
        }
    }

    private func endpoint(_ s: EditableSession) -> String {
        switch s.kind {
        case .serial: return "\(s.serial.device) · \(s.serial.speed) \(s.serial.frame)"
        case .local: return L("Este Mac")
        case .ssh, .telnet, .sftp, .ftp:
            return (s.user.isEmpty ? "" : "\(s.user)@") + (s.host.isEmpty ? s.name : s.host)
                + (s.port == "22" || s.port.isEmpty ? "" : ":\(s.port)") + (s.jump.isEmpty ? "" : "  ⟵ \(s.jump)")
                + (s.kind == .ssh ? "" : " · \(s.kind.label)")
        }
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "server.rack").font(.system(size: 34)).foregroundStyle(SwiftUI.Color(t.accent2))
            Text(L("Elige una sesión o crea una nueva")).font(t.ui(13)).foregroundStyle(SwiftUI.Color(t.dim))
            HStack {
                NeonButton(title: L("Nueva sesión"), icon: "plus") { once { add(group: nil) } }.disabled(busy)
                NeonButton(title: L("Importar"), icon: "square.and.arrow.down", tint: t.accent2) { importing = true }
            }
        }
    }

    // MARK: formulario

    private func form(_ i: Int) -> some View {
        let s = $file.sessions[i]
        let others = file.sessions.map(\.name).filter { $0 != file.sessions[i].name }
        return Form {
            Section {
                HStack {
                    LabeledContent(L("Grupo")) { TextField("", text: s.group, prompt: Text(L("Grupo"))).frame(maxWidth: 380) }
                    ThemedMenu {
                        ForEach(file.groups, id: \.self) { g in Button(g) { file.sessions[i].group = g } }
                    } label: { Image(systemName: "chevron.down.circle") }.fixedSize()
                }
                LabeledContent(L("Nombre")) { TextField("", text: s.name, prompt: Text(L("core-01 (sin espacios)"))).frame(maxWidth: 380) }
                if !EditableSession.isValidName(file.sessions[i].name) {
                    Text(L("Sin espacios ni * ? ! (es el nombre que usa ssh)")).font(.caption).foregroundStyle(SwiftUI.Color(t.bad))
                }
                LabeledContent(L("Descripción")) { TextField("", text: s.summary, prompt: Text("opcional")).frame(maxWidth: 380) }
                Toggle(L("⏻ Abrir al arrancar (sólo una; ⌥⌘K la abre cuando quieras)"), isOn: Binding(
                    get: { model.settings.startupSession == file.sessions[i].name },
                    set: { model.settings.startupSession = $0 ? file.sessions[i].name : "" }))
            } header: { header(L("SESIÓN")) }

            Section {
                let k = file.sessions[i].kind
                ThemedPicker(L("Tipo"), selection: Binding(get: { file.sessions[i].kind },
                                                      set: { file.sessions[i].setKind($0) })) { o in
                    for x in SessionProfile.Transport.allCases { o.append((x, x.label)) }
                }
                if k.isNetwork {
                    LabeledContent(L("Equipo (nombre o IP)")) { TextField("", text: s.host, prompt: Text("192.0.2.1")).frame(maxWidth: 380) }
                    LabeledContent(L("Usuario")) { TextField("", text: s.user, prompt: Text(AppPaths.userName)).frame(maxWidth: 380) }
                    LabeledContent(L("Puerto")) { TextField("", text: s.port, prompt: Text(EditableSession.defaultPort(k))).frame(maxWidth: 380) }
                }
                if k.isNetwork, k != .ftp {
                    ThemedPicker(L("Saltar por"), selection: s.jump) { o in
                        o.append(("", L("Directo")))
                        if !file.sessions[i].jump.isEmpty, !others.contains(file.sessions[i].jump) { o.append((file.sessions[i].jump, file.sessions[i].jump)) }
                        for x in others { o.append((x, x)) }
                    }
                }
                if k == .ssh, !file.sessions[i].jump.isEmpty {
                    Text(L("Si el salto no deja reenviar (-J), la app entra en él y escribe «ssh equipo»."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if k == .ssh || k == .sftp {
                    HStack {
                        LabeledContent(L("Clave privada")) { TextField("", text: s.keyFile, prompt: Text(L("(ninguna)"))).frame(maxWidth: 380) }
                        Button(L("Elegir…")) { chooseKey(i) }
                    }
                    Toggle(L("Equipo antiguo (algoritmos ssh viejos)"), isOn: s.legacy)
                }
                switch k {
                case .sftp: note(L("Se abre en el explorador gráfico (con el mismo alias, salto, puerto y usuario que ssh); la consola sftp, con un clic. La contraseña, como en ssh."))
                case .ftp: note(L("Se abre en el explorador gráfico de la app (subir, bajar, renombrar, borrar). FTP no va cifrado: si el equipo lo admite, mejor SFTP. La contraseña, del Llavero o se pide."))
                case .local: note(L("Tu shell de inicio en este Mac (como ⌘T): sin contraseñas ni MultiExec."))
                case .serial: serialFields(i)
                case .ssh, .telnet: EmptyView()
                }
            } header: { header(L("CONEXIÓN")) }

            if [.ssh, .telnet, .sftp].contains(file.sessions[i].kind) { passwordSection(i) }

            if [.ssh, .sftp].contains(file.sessions[i].kind) {
                Section {
                    TextEditor(text: Binding(get: { file.sessions[i].extra.joined(separator: "\n") },
                                             set: { file.sessions[i].extra = $0.components(separatedBy: .newlines)
                                                 .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })).themedEditor()
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 60)
                } header: { header(L("OPCIONES DE SSH (AVANZADO)")) } footer: {
                    Text(L("Una por línea: LocalForward 8080 192.0.2.1:80 · ServerAliveInterval 30 · …")).font(.caption)
                }
            }

            if file.sessions[i].kind != .sftp, file.sessions[i].kind != .ftp { profileSection(i) }

            Section {
                TextEditor(text: Binding(get: { file.sessions[i].notes.joined(separator: "\n") },
                                         set: { file.sessions[i].notes = $0.components(separatedBy: .newlines)
                                             .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })).themedEditor()
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 44)
            } header: { header(L("NOTAS")) } footer: {
                Text(L("Una por línea; se guardan como comentarios «# …» de la sesión (p. ej. «@proyecto despliegue»).")).font(.caption)
            }
        }
        .formStyle(.themed)
        .scrollContentBackground(.hidden)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    /// Puerto serie: los /dev/cu.* que hay ahora (o la ruta a mano), velocidad y trama.
    @ViewBuilder private func serialFields(_ i: Int) -> some View {
        let line = $file.sessions[i].serial
        let cur = file.sessions[i].serial.device
        HStack {
            ThemedPicker(L("Puerto serie"), selection: line.device) { o in
                o.append(("", L("(elige uno)")))
                if !cur.isEmpty, !ports.contains(cur) { o.append((cur, L("\(cur) (no conectado)"))) }
                for x in ports { o.append((x, x)) }
            }
            IconButton(icon: "arrow.clockwise") { ports = SerialLine.devices() }.help(L("Volver a buscar puertos"))
        }
        LabeledContent(L("Ruta del puerto")) { TextField("", text: line.device, prompt: Text("/dev/cu.usbserial-0001")).frame(maxWidth: 380) }
        if !cur.isEmpty, !SerialLine.isValidDevice(cur) {
            Text(L("Sólo /dev/cu.* o /dev/tty.*, sin espacios ni símbolos")).font(.caption).foregroundStyle(SwiftUI.Color(t.bad))
        }
        ThemedPicker(L("Velocidad"), selection: line.speed) { o in
            for x in SerialLine.speeds { o.append((x, "\(x)")) }
        }
        ThemedSegmented(L("Bits de datos"), selection: line.dataBits) { o in
            for x in [8, 7, 6, 5] { o.append((x, "\(x)")) }
        }
        ThemedSegmented(L("Paridad"), selection: line.parity) { o in
            o.append((SerialLine.Parity.none, L("Ninguna")))
            o.append((SerialLine.Parity.even, L("Par")))
            o.append((SerialLine.Parity.odd, L("Impar")))
        }
        ThemedSegmented(L("Bits de parada"), selection: line.stopBits) { o in
            o.append((1, "1"))
            o.append((2, "2"))
        }
        note(L("La app abre el puerto y le aplica velocidad, bits de datos, paridad y bits de parada (sin control de flujo); si el puerto no acepta algún valor, la pestaña lo dice y no se conecta. Para salir, cierra la pestaña."))
    }

    /// Perfil de la pestaña (`TerminalProfile`): cada campo, de serie, «Heredar» lo de Ajustes (y sigue sus cambios).
    private func profileSection(_ i: Int) -> some View {
        let p = $file.sessions[i].terminal
        let cur = file.sessions[i].terminal
        let th = model.themes.current
        let inherit = { (v: String) in L("Heredar (\(v))") }
        let globalFamily = model.settings.fontFamily.isEmpty ? (Fonts.firstInstalled(th.fonts) ?? L("monoespaciada del sistema"))
                                                             : model.settings.fontFamily
        let globalSize = model.settings.fontSize > 0 ? Int(model.settings.fontSize) : th.size - 1
        let sizes = [0.0] + stride(from: 9.0, through: 24.0, by: 1.0) + (cur.fontSize > 0 && !(9...24).contains(cur.fontSize) ? [cur.fontSize] : [])
        let lines = [0] + TerminalHistory.options + (cur.scrollback.map { TerminalHistory.options.contains($0) ? [] : [$0] } ?? [])
        let problem = cur.prompt.isEmpty ? nil : PromptRule.problem(cur.prompt)
        return Section {
            ThemedPicker(L("Tema"), selection: p.theme) { o in
                o.append(("", inherit(th.name)))
                if !cur.theme.isEmpty, model.themes.theme(id: cur.theme) == nil { o.append((cur.theme, L("\(cur.theme) (no está)"))) }
                for x in model.themes.all { o.append((x.theme.id, x.theme.name)) }
            }
            ThemedPicker(L("Fuente"), selection: p.fontFamily) { o in
                o.append(("", inherit(globalFamily)))
                if !cur.fontFamily.isEmpty, !families.contains(cur.fontFamily) { o.append((cur.fontFamily, L("\(cur.fontFamily) (no instalada)"))) }
                for x in families { o.append((x, x)) }
            }
            ThemedPicker(L("Tamaño"), selection: p.fontSize) { o in
                for x in sizes { o.append((x, x == 0 ? inherit(L("\(globalSize) pt")) : L("\(Int(x)) pt"))) }
            }
            ThemedPicker(L("Líneas guardadas"), selection: Binding(get: { cur.scrollback ?? 0 },
                                                                  set: { file.sessions[i].terminal.scrollback = $0 == 0 ? nil : $0 })) { o in
                for n in lines { o.append((n, n == 0 ? inherit(TerminalHistory.label(model.settings.scrollback)) : TerminalHistory.label(n))) }
            }
            ThemedPicker(L("Tecla ⌥"), selection: p.optionAsMeta) { o in
                o.append((nil, inherit(L("escribe «@», «#», «|»…"))))
                o.append((false, L("Escribe «@», «#», «|»… (teclado español)")))
                o.append((true, L("Como Meta (Esc + tecla: emacs, readline)")))
            }
            ThemedPicker(L("Retroceso"), selection: p.backspaceSendsCtrlH) { o in
                o.append((nil, inherit("DEL")))
                o.append((false, L("Envía DEL (^?)")))
                o.append((true, L("Envía ^H (equipos antiguos, consolas)")))
            }
            LabeledContent(L("Prompt (regex)")) {
                TextField("", text: p.prompt, prompt: Text(L("Heredar (genérico)"))).frame(maxWidth: 380)
                    .font(.system(.callout, design: .monospaced))
            }
            if let problem {
                Text(L("Prompt no válido: \(problem)")).font(.caption).foregroundStyle(SwiftUI.Color(t.bad))
            }
        } header: { header(L("PERFIL")) } footer: {
            Text(L("Lo que dejes en «Heredar» sigue a Ajustes. El prompt (p. ej. ^core-\\d+[#>]$) sustituye al genérico para saber que has entrado y para el pegado seguro; una línea que pide contraseña, passphrase u OTP nunca cuenta como prompt.")).font(.caption)
        }
    }

    private func passwordSection(_ i: Int) -> some View {
        let s = $file.sessions[i]
        let user = file.sessions[i].user.isEmpty ? AppPaths.userName : file.sessions[i].user
        let host = file.sessions[i].host.isEmpty ? file.sessions[i].name : file.sessions[i].host
        return Section {
                ThemedPicker(L("Credencial de la sesión"), selection: s.credential) { o in
                    let group = file.groupCredentials[file.sessions[i].group] ?? ""
                    o.append(("", group.isEmpty ? L("Automática: propia del equipo") : L("Heredar del grupo: \(group)")))
                    o.append(("-", L("Propia del equipo (ignorar grupo)")))
                    if !file.sessions[i].credential.isEmpty, file.sessions[i].credential != "-",
                       !namedCredentials.contains(file.sessions[i].credential) { o.append((file.sessions[i].credential, L("\(file.sessions[i].credential) (no está en el Llavero)"))) }
                    for x in namedCredentials { o.append((x, "🔑 \(x)")) }
                }
                ThemedPicker(L("Del grupo «\(file.sessions[i].group)»"), selection: Binding(
                    get: { file.groupCredentials[file.sessions[i].group] ?? "" },
                    set: { file.groupCredentials[file.sessions[i].group] = $0.isEmpty ? nil : $0 })) { o in
                    o.append(("", L("(ninguna)")))
                    if let group = file.groupCredentials[file.sessions[i].group], !group.isEmpty, !namedCredentials.contains(group) {
                        o.append((group, L("\(group) (no está en el Llavero)")))
                    }
                    for x in namedCredentials { o.append((x, "🔑 \(x)")) }
                }
                Button(L("Nueva credencial con nombre…")) { creatingCredential = true }
                let hasDevice = model.hasCredential(.device(user, host))
                HStack {
                    SecureField(hasDevice ? L("Sustituir la de \(user)@\(host)") : L("Guardar una para \(user)@\(host)"),
                                text: $newPassword)
                    Button(L("Al Llavero")) { savePassword(user: user, host: host) }.disabled(newPassword.isEmpty)
                }
                if hasDevice {
                    Text(L("✓ Hay una guardada para \(user)@\(host)")).font(.caption).foregroundStyle(SwiftUI.Color(t.good))
                }
                inUse(file.sessions[i], user: user, host: host, hasDevice: hasDevice)
            } header: { header(L("CONTRASEÑA (LLAVERO)")) } footer: {
                Text(L("Nunca se escribe sola la de otro usuario: sólo la de ese mismo usuario.")).font(.caption)
            }
    }

    /// Cuál usará de verdad (en el orden en que se prueban) y «Cambiar contraseña…» para sustituirla.
    @ViewBuilder private func inUse(_ se: EditableSession, user: String, host: String, hasDevice: Bool) -> some View {
        let named = file.namedCredential(of: se)
        let ref: CredentialRef = named.map { .named($0.name) } ?? .device(user, host)
        HStack {
            Text(named.map { $0.fromGroup ? L("Usa: 🔑 \($0.name) (la del grupo)") : L("Usa: 🔑 \($0.name)") }
                 ?? (hasDevice ? L("Usa: la de \(user)@\(host)") : L("Usa: ninguna (a mano)")))
                .font(.caption).foregroundStyle(.secondary)
            if named != nil, !model.hasCredential(ref) {
                Text(L("(no está en el Llavero)")).font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Button(model.hasCredential(ref) ? L("Cambiar contraseña…") : L("Guardarla…")) { changing = ref }
        }
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
                Text(message.isEmpty ? AppPaths.tilde(SessionFile.defaultURL.path) : message)
                    .font(t.ui(11)).foregroundStyle(SwiftUI.Color(message.hasPrefix("✗") ? t.bad : t.dim)).lineLimit(2)
            }
            Spacer()
            if !embedded {
                Button(L("Cerrar")) { DispatchQueue.main.async { close() } }.keyboardShortcut(.cancelAction)
            }
            NeonButton(title: L("Conectar"), icon: "bolt.horizontal", tint: t.accent2) { once(connect) }
                .disabled(busy || saving || index.map { !EditableSession.isValidName(file.sessions[$0].name) } ?? true)
                .help(L("Abre la sesión tal como está, sin guardar los cambios"))
            // (⌘S: en la hoja, guardar y conectar; en Ajustes, sólo guardar: se sigue editando)
            NeonButton(title: L("Guardar"), icon: "checkmark", active: dirty) { once { save(connect: false) } }
                .disabled(busy || saving || !problems.isEmpty || !dirty)
                .help(L("Guarda los cambios sin abrir ninguna pestaña"))
                .keyboardShortcut(embedded ? KeyboardShortcut("s") : nil)
            NeonButton(title: L("Guardar y conectar"), icon: "bolt.horizontal.fill", tint: t.good) { once { save(connect: true) } }
                .disabled(busy || saving || !problems.isEmpty || index == nil)
                .keyboardShortcut(embedded ? nil : KeyboardShortcut("s"))
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(SwiftUI.Color(t.bar))
    }

    // MARK: acciones

    private var namedCredentials: [String] {
        model.keychainAccounts.filter { $0.service == .named && $0.account != "-" }.map(\.account)
    }

    private func load() {
        file = model.sessionFile
        saved = file
        switch model.editorFocus {
        case .session(let n): selected = file.sessions.first { $0.name == n }?.id
        case .new(let g, let k): add(group: g, kind: k)
        case .duplicate(let n):
            selected = file.sessions.first { $0.name == n }?.id
            duplicate()
        case .importing: importing = true
        case nil: selected = file.sessions.first?.id
        }
        model.editorFocus = nil
    }

    private func add(group: String?, kind: SessionProfile.Transport = .ssh) {
        let g = group ?? file.groups.first ?? "General"
        let s = EditableSession.new(group: g, name: file.uniqueName("nueva"), kind: kind)
        let at = (file.sessions.lastIndex { $0.group == g }).map { $0 + 1 } ?? file.sessions.count
        file.sessions.insert(s, at: at)
        selected = s.id
        importing = false
    }

    private func duplicate() {
        guard let i = index else { return }
        let d = file.sessions[i].copy(named: file.uniqueName("\(file.sessions[i].name)-2"))
        file.sessions.insert(d, at: i + 1)
        selected = d.id
        importing = false
    }

    private func move(_ step: Int) {
        guard let id = selected else { return }
        file.move(id, by: step)
    }

    /// JSON (todos los campos) o CSV (las columnas del importador) de todas o de unos grupos. Nunca contraseñas.
    private func export(groups: Set<String>?, csv: Bool) {
        let list = SessionExport.select(file.sessions, groups: groups)
        guard !list.isEmpty else { message = L("✗ No hay sesiones que exportar"); return }
        let p = NSSavePanel()
        let base = groups.flatMap { $0.count == 1 ? $0.first : nil }.map(SessionImporter.validName) ?? "sesiones"
        p.nameFieldStringValue = base + (csv ? ".csv" : ".json")
        guard p.runModal() == .OK, let u = p.url else { return }
        do {
            if csv { try SessionExport.csv(list).write(to: u, atomically: true, encoding: .utf8) }
            else { try SessionExport.json(list).write(to: u, options: .atomic) }
            message = L("✓ \(list.count) exportadas a \(u.lastPathComponent) (sin contraseñas)")
        } catch {
            ErrorLog.error("exportar", "\(u.lastPathComponent): \(error.localizedDescription)")
            message = "✗ \(error.localizedDescription)"
        }
    }

    private func delete() {
        guard let i = index else { return }
        let id = file.sessions[i].id, name = file.sessions[i].name
        Task {
            guard await ThemedAlert.confirm(L("¿Borrar la sesión «\(name)»?"), message: L("Se quita al pulsar «Guardar» (queda una copia en ssh_config.anterior). Su contraseña del Llavero no se toca."), ok: L("Borrar"), destructive: true) else { return }
            // (por su id: mientras se preguntaba, la lista pudo cambiar)
            guard let at = file.sessions.firstIndex(where: { $0.id == id }) else { return }
            file.sessions.remove(at: at)
            selected = file.sessions.indices.contains(at) ? file.sessions[at].id : file.sessions.last?.id
        }
    }

    private func renameGroup(_ g: String) {
        Task {
            guard let n = await Self.ask(L("Renombrar el grupo «\(g)»"), value: g), !n.isEmpty, n != g else { return }
            for i in file.sessions.indices where file.sessions[i].group == g { file.sessions[i].group = n }
            if let c = file.groupCredentials.removeValue(forKey: g) { file.groupCredentials[n] = c }
        }
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
        file.sessions[i].keyFile = AppPaths.tilde(u.path)
    }

    private func savePassword(user: String, host: String) {
        let ref = CredentialRef.device(user, host)
        let pw = newPassword
        newPassword = ""                            // (vacío: «Al Llavero» se apaga mientras se guarda)
        Task {
            do {
                try await model.store.saveInBackground(pw, for: ref)
                model.ledger.reset(ref)
                model.keychainRevision += 1
                message = L("✓ Contraseña de \(user)@\(host) guardada en el Llavero")
            } catch {
                ErrorLog.error("llavero", "no se ha podido guardar \(user)@\(host): \(error.localizedDescription)")
                message = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func save(connect: Bool) {
        let name = index.map { file.sessions[$0].name }         // (la de ahora: mientras se guarda puedes elegir otra)
        if let why = gate.blocks(.save) { message = why; return }
        guard dirty else { return open(connect ? name : nil) }
        guard gate.begin() else { return }
        let toSave = file
        message = L("Guardando…")
        Task {
            let err = await model.saveSessions(toSave)
            gate.end()                          // (antes de abrir: si no, la guarda de `finish` no dejaría cerrar)
            if let err {
                message = "✗ \(err)"
                return
            }
            saved = toSave
            // (lo que se haya cambiado mientras se guardaba sigue aquí, sin guardar: no se cierra la hoja)
            message = dirty ? L("✓ Guardadas; los cambios de mientras se guardaba siguen sin guardar") : L("✓ Guardadas")
            open(connect ? name : nil)
        }
    }

    /// «Guardar y conectar»: abre la sesión guardada `name`; la hoja se cierra sólo si no queda nada sin guardar.
    private func open(_ name: String?) {
        guard let name else { return }
        if let why = gate.blocks(.connect) { message = why; return }
        guard let p = model.sessions.profile(named: name) else {
            message = L("✗ No se encuentra «\(name)» en las sesiones guardadas")
            return
        }
        model.open(p)
        if dirty { message = L("✓ «\(name)» abierta: los cambios sin guardar siguen aquí") } else { finish() }
    }

    /// «Conectar»: la sesión tal como está, sin guardarla. Si no ha cambiado, como siempre (con su alias del
    /// ssh_config); si es nueva o ha cambiado, con equipo, usuario, puerto y saltos explícitos. Con cambios sin
    /// guardar el gestor sigue abierto para no perderlos.
    private func connect() {
        if let why = gate.blocks(.connect) { message = why; return }
        guard let i = index else { return }
        let s = file.sessions[i]
        if saved.sessions.contains(where: { $0.id == s.id && $0 == s }), let p = model.sessions.profile(named: s.name) {
            model.open(p)
        } else {
            do {
                model.open(try model.sessions.route(unsaved: s))
            } catch {
                message = "✗ \(error.localizedDescription)"
                return
            }
        }
        if dirty { message = L("✓ «\(s.name)» abierta sin guardar: los cambios siguen aquí") } else { finish() }
    }

    /// Una acción a la vez y fuera del gesto: los clics seguidos (crear, borrar, guardar, conectar…) no la repiten, y
    /// si abre un aviso modal (borrar, cerrar con cambios) lo hace con el clic ya terminado, sin congelar la hoja.
    private func once(_ action: @escaping @MainActor () -> Void) {
        guard !busy else { return }
        busy = true
        DispatchQueue.main.async {
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { busy = false }
        }
    }

    private func close() {
        if let why = gate.blocks(.close) { message = why; return }
        guard dirty else { return dismiss() }
        Task { if await confirmLeave() { dismiss() } }
    }

    /// Antes de cerrar la hoja o de salir de la sección de Ajustes: con cambios, guardar, descartar o quedarse.
    private func confirmLeave() async -> Bool {
        if let why = gate.blocks(.close) { message = why; return false }
        guard dirty else { return true }
        switch await ThemedAlert.run(L("Hay cambios sin guardar"), buttons: [L("Guardar"), L("Descartar"), L("Cancelar")]).button {
        case 0:
            let toSave = file
            guard gate.begin() else { return false }
            defer { gate.end() }
            if let err = await model.saveSessions(toSave) { message = "✗ \(err)"; return false }
            saved = toSave
            return !dirty                       // (cambiado mientras se guardaba: no se cierra)
        case 1: return true
        default: return false
        }
    }

    /// Tras abrir la pestaña: la hoja se cierra; dentro de Ajustes, se cierran los Ajustes para verla.
    private func finish() {
        if let why = gate.blocks(.finish) { message = why; return }
        if embedded { model.showSettings = false } else { dismiss() }
    }

    static func ask(_ title: String, value: String = "") async -> String? {
        let r = await ThemedAlert.run(title, buttons: [L("Aceptar"), L("Cancelar")], field: ("", value, false))
        return r.button == 0 ? r.text.trimmingCharacters(in: .whitespaces) : nil
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
            Text(L("IMPORTAR SESIONES")).font(t.ui(16, .heavy)).tracking(3).foregroundStyle(SwiftUI.Color(t.accent))
            Text(L("SecureCRT (la carpeta Sessions o un .ini), MobaXterm (.mxtsessions), PuTTY (.reg), electerm (.json), ")
                 + L("CSV del inventario, un ssh_config o un JSON exportado desde aquí. Las carpetas pasan a ser grupos. Nunca se importa ninguna contraseña."))
                .font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            HStack(spacing: 8) {
                ForEach(SessionImporter.suggestions(), id: \.1) { name, url in
                    NeonButton(title: name, icon: "sparkles", tint: t.accent2) { read(url) }
                }
                NeonButton(title: L("Elegir archivo o carpeta…"), icon: "folder") { pick() }
            }
            if let r = result {
                HStack {
                    Text(L("\(r.format): \(r.sessions.count) nuevas")).font(t.ui(12, .bold))
                    if !r.skipped.isEmpty { Text(L("· \(r.skipped.count) saltadas")).font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim)) }
                    Spacer()
                    Button(chosen.count == r.sessions.count ? L("Ninguna") : L("Todas")) {
                        chosen = chosen.count == r.sessions.count ? [] : Set(r.sessions.map(\.id))
                    }
                }
                List {
                    ForEach(r.sessions) { s in
                        Toggle(isOn: Binding(get: { chosen.contains(s.id) },
                                             set: { if $0 { chosen.insert(s.id) } else { chosen.remove(s.id) } })) {
                            HStack {
                                Text(s.name).font(t.ui(12, .semibold))
                                Text("\(s.user.isEmpty ? "" : s.user + "@")\(s.host):\(s.port)\(s.jump.isEmpty ? "" : " ⟵ " + s.jump)\(s.kind == .ssh ? "" : " · " + s.kind.label)")
                                    .font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim))
                                Spacer()
                                Text(L(nombre: s.group)).font(t.ui(10, .bold)).foregroundStyle(SwiftUI.Color(t.accent2))
                            }
                        }
                    }
                    if !r.skipped.isEmpty {
                        Section(L("Saltadas")) {
                            ForEach(Array(r.skipped.enumerated()), id: \.offset) { _, x in
                                Text("\(x.0): \(x.1)").font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim))
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                HStack {
                    Spacer()
                    NeonButton(title: L("Añadir \(chosen.count) al gestor"), icon: "plus", active: !chosen.isEmpty) {
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
        if r.sessions.isEmpty { ErrorLog.warning("importar", "\(u.lastPathComponent) (\(r.format)): ninguna sesión que importar") }
        if !r.skipped.isEmpty {
            ErrorLog.warning("importar", "\(u.lastPathComponent): \(r.skipped.count) descartadas: "
                             + r.skipped.prefix(5).map { "\($0.0) (\($0.1))" }.joined(separator: ", "))
        }
        result = r
        chosen = Set(r.sessions.map(\.id))
    }
}

extension SessionProfile.Transport {
    /// Icono de la lista: el de su tipo (ssh con salto, con la flecha).
    func icon(jump: Bool) -> String {
        switch self {
        case .ssh: jump ? "arrow.triangle.turn.up.right.diamond.fill" : "terminal.fill"
        case .telnet: "cable.connector"
        case .sftp: "folder.fill"
        case .ftp: "externaldrive.connected.to.line.below"
        case .serial: "cable.connector.horizontal"
        case .local: "apple.terminal"
        }
    }
}
