import NetDeckCore
import SwiftUI

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

/// Lista por salto: cada equipo en su pestaña a través del salto, con reintentos controlados.
struct ListSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Stored private var name = "lista"
    @Stored private var jump = ""
    @Stored private var user = ""
    @Stored private var credential = ""
    @Stored private var devices = ""

    var body: some View {
        Form {
            TextField(L("Nombre"), text: $name)
            Picker(L("Salto"), selection: $jump) {
                ForEach(model.sessions.profiles) { Text($0.name).tag($0.name) }
            }
            TextField(L("Usuario en los equipos"), text: $user, prompt: Text("tu.usuario"))
            Picker(L("Contraseña"), selection: $credential) {
                Text(L("(a mano)")).tag("")
                ForEach(model.keychainAccounts, id: \.self) { Text($0.account).tag($0.account) }
            }
            TextEditor(text: $devices)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
            Text(L("\(JumpList.devices(in: devices).count) equipos · una sola pestaña prueba la contraseña a la vez; si falla, no se escribe en las demás"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .onAppear { jump = model.sessions.profiles.first?.name ?? "" }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L("Cancelar")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Abrir")) {
                    let list = makeList()
                    dismiss()
                    Task { await model.run(list) }
                }
                .disabled(jump.isEmpty || JumpList.devices(in: devices).isEmpty)
            }
        }
    }

    private func makeList() -> JumpList {
        let u = user.isEmpty ? nil : user
        let ref = model.keychainAccounts.first { $0.account == credential }
        let owners: Set<String> = ref.map {
            $0.service == .device ? [String($0.account.split(separator: "@").first ?? "")]
                                  : model.sessions.owners(ofNamed: $0.account).union(u.map { [$0] } ?? [])
        } ?? []
        return JumpList(name: name, jump: jump, user: u, devices: JumpList.devices(in: devices),
                        credential: ref.map { CredentialCandidate(ref: $0, owners: owners, origin: .sessionNamed) })
    }
}
