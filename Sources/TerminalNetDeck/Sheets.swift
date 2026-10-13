import NetDeckCore
import SwiftUI
import UniformTypeIdentifiers

/// Conexión rápida o acceso directo de salto: «equipo» (alias o usuario@equipo[:puerto]) por «salto» (opcional).
struct ConnectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Stored private var device = ""
    @Stored private var jump = ""
    @Stored private var user = ""
    @Stored private var transport = SessionProfile.Transport.ssh

    var body: some View {
        Form {
            TextField(L("Equipo"), text: $device, prompt: Text(L("192.0.2.5 · admin@core-01 · core-01:2222")))
            Picker(L("Salto"), selection: $jump) {
                Text(L("Directo")).tag("")
                ForEach(model.sessions.profiles) { Text($0.name).tag($0.name) }
            }
            TextField(L("Usuario"), text: $user, prompt: Text(L("(el del equipo o el de la sesión)")))
            Picker(L("Protocolo"), selection: $transport) {
                ForEach(SessionProfile.Transport.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L("Cancelar")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Conectar")) {
                    connect()
                    dismiss()
                }
                .disabled(Endpoint(parsing: device) == nil)
            }
        }
    }

    private func connect() {
        let u = user.isEmpty ? nil : user
        if !jump.isEmpty {
            model.jump(to: device, via: jump, user: u, transport: transport)
        } else if let p = model.sessions.profile(named: device) {
            model.open(p)
        } else if var e = Endpoint(parsing: device) {
            if e.user == nil { e.user = u }
            model.open(ConnectionRoute(title: e.host, target: e, transport: transport))
        }
    }
}

/// Pegado seguro: línea a línea esperando al prompt; las peligrosas hay que confirmarlas antes de empezar.
struct PasteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Stored private var text = NSPasteboard.general.string(forType: .string) ?? ""
    @Stored private var toAll = false
    @Stored private var confirmDangerous = false

    var body: some View {
        let dangerous = PasteRules.dangerousLines(in: text)
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Una a una, esperando al equipo. Se para si da error, si pagina o con Esc."))
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
            if !dangerous.isEmpty {
                Toggle(L("Confirmo \(dangerous.count) peligrosa(s): \(dangerous.prefix(3).joined(separator: " · "))"),
                       isOn: $confirmDangerous)
                    .foregroundStyle(.red)
            }
            Toggle(L("A todas las pestañas (MultiExec)"), isOn: $toAll)
            HStack {
                Spacer()
                Button(L("Cancelar")) { dismiss() }
                Button(L("Enviar \(PasteRules.lines(of: text).count) líneas")) {
                    let (t, all, ok) = (text, toAll, confirmDangerous)
                    dismiss()
                    Task { await model.paste(t, allowDangerous: ok, toAll: all) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(PasteRules.lines(of: text).isEmpty || (!dangerous.isEmpty && !confirmDangerous))
            }
        }
        .padding()
        .frame(width: 560)
    }
}

/// Lista por salto: cada equipo en su pestaña a través del salto, con reintentos controlados. Las listas se guardan
/// con nombre (listas.json, sin contraseñas: sólo el nombre de la del Llavero).
struct ListSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Stored private var library = ListLibrary()
    @Stored private var selected: SavedList.ID?
    @Stored private var name = "lista"
    @Stored private var jump = ""
    @Stored private var user = ""
    @Stored private var credential = ""
    @Stored private var devices = ""
    @Stored private var message = ""

    var body: some View {
        let parsed = DeviceListText.parse(devices)
        Form {
            Section {
                HStack {
                    Picker(L("Lista guardada"), selection: Binding(get: { selected }, set: { pick($0) })) {
                        Text(L("(nueva, sin guardar)")).tag(SavedList.ID?.none)
                        ForEach(library.lists) { Text($0.name).tag(SavedList.ID?.some($0.id)) }
                    }
                    Menu {
                        Button(L("Nueva")) { pick(nil) }
                        Button(L("Duplicar")) { duplicate() }.disabled(selected == nil)
                        Button(L("Renombrar…")) { rename() }.disabled(selected == nil)
                        Button(L("Importar equipos de un .txt/.csv…")) { importFile() }
                        Divider()
                        Button(L("Borrar…"), role: .destructive) { remove() }.disabled(selected == nil)
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                }
            }
            TextField(L("Nombre"), text: $name)
            Picker(L("Salto"), selection: $jump) {
                if !jump.isEmpty, model.sessions.profile(named: jump) == nil { Text(jump).tag(jump) }
                ForEach(model.sessions.profiles) { Text($0.name).tag($0.name) }
            }
            TextField(L("Usuario en los equipos"), text: $user, prompt: Text("tu.usuario"))
            Picker(L("Contraseña"), selection: $credential) {
                Text(L("(a mano)")).tag("")
                if !credential.isEmpty, !model.keychainAccounts.contains(where: { $0.account == credential }) {
                    Text(L("\(credential) (no está en el Llavero)")).tag(credential)
                }
                ForEach(model.keychainAccounts, id: \.self) { Text($0.account).tag($0.account) }
            }
            TextEditor(text: $devices)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
            Text(L("\(parsed.devices.count) equipos · una sola pestaña prueba la contraseña a la vez; si falla, no se escribe en las demás"))
                .font(.caption).foregroundStyle(.secondary)
            if !parsed.rejected.isEmpty {
                Text(L("No valen (se ignoran): \(parsed.rejected.prefix(5).joined(separator: " · "))"))
                    .font(.caption).foregroundStyle(.orange)
            }
            if !message.isEmpty { Text(message).font(.caption) }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear(perform: load)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L("Cancelar")) { dismiss() } }
            ToolbarItem {
                Button(L("Guardar lista")) { saveList() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Abrir")) {
                    let list = makeList()
                    dismiss()
                    Task { await model.run(list) }
                }
                .disabled(jump.isEmpty || parsed.devices.isEmpty)
            }
        }
    }

    // MARK: listas guardadas

    private func load() {
        do { library = try ListLibrary(contentsOf: ListLibrary.defaultURL) } catch { message = "✗ \(error.localizedDescription)" }
        if let first = library.lists.first { pick(first.id) } else { jump = model.sessions.profiles.first?.name ?? "" }
    }

    private func pick(_ id: SavedList.ID?) {
        selected = id
        guard let l = library.list(id) else {
            name = library.uniqueName("lista"); devices = ""; message = ""
            return
        }
        (name, jump, user, credential) = (l.name, l.jump, l.user, l.credential)
        devices = l.devices.joined(separator: "\n")
        message = ""
    }

    private var current: SavedList {
        SavedList(id: selected ?? UUID(), name: name.trimmingCharacters(in: .whitespaces), jump: jump,
                  user: user.trimmingCharacters(in: .whitespaces), credential: credential,
                  devices: DeviceListText.parse(devices).devices.map(\.description))
    }

    private func persist(_ ok: String) {
        do {
            try library.save()
            message = ok
        } catch {
            message = "✗ \(error.localizedDescription)"
        }
    }

    private func saveList() {
        let l = library.upsert(current)
        pick(l.id)
        persist(L("✓ Lista «\(l.name)» guardada"))
    }

    private func duplicate() {
        guard let id = selected, let c = library.duplicate(id) else { return }
        pick(c.id)
        persist(L("✓ Copia «\(c.name)»"))
    }

    private func rename() {
        guard let id = selected, let n = SessionEditor.ask(L("Renombrar la lista «\(name)»"), value: name), !n.isEmpty,
              library.rename(id, to: n) else { return }
        name = library.list(id)?.name ?? n
        persist(L("✓ Renombrada"))
    }

    private func remove() {
        guard let id = selected else { return }
        let a = NSAlert()
        a.messageText = L("¿Borrar la lista «\(name)»?")
        a.informativeText = L("Queda una copia en listas.json.anterior. Las contraseñas del Llavero no se tocan.")
        a.addButton(withTitle: L("Borrar"))
        a.addButton(withTitle: L("Cancelar"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        library.remove(id)
        pick(library.lists.first?.id)
        persist(L("✓ Borrada"))
    }

    /// Un equipo por línea (o la primera columna de un .csv): se añaden a los que ya hay.
    private func importFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.plainText, .commaSeparatedText, .tabSeparatedText, .text]
        guard p.runModal() == .OK, let u = p.url else { return }
        do {
            guard let text = try SafeFile.read(u) else { return }
            let found = DeviceListText.importing(text)
            let r = DeviceListText.parse(found)
            devices = [devices.trimmingCharacters(in: .whitespacesAndNewlines), r.devices.map(\.description).joined(separator: "\n")]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            message = L("\(r.devices.count) equipos importados de \(u.lastPathComponent)")
                + (r.rejected.isEmpty ? "" : L(" · \(r.rejected.count) no valen (se ignoran)"))
        } catch {
            message = "✗ \(error.localizedDescription)"
        }
    }

    private func makeList() -> JumpList {
        let u = user.isEmpty ? nil : user
        let ref = model.keychainAccounts.first { $0.account == credential }
        let owners: Set<String> = ref.map {
            $0.service == .device ? [String($0.account.split(separator: "@").first ?? "")]
                                  : model.sessions.owners(ofNamed: $0.account).union(u.map { [$0] } ?? [])
        } ?? []
        return JumpList(name: name, jump: jump, user: u, devices: DeviceListText.parse(devices).devices,
                        credential: ref.map { CredentialCandidate(ref: $0, owners: owners, origin: .sessionNamed) })
    }
}
