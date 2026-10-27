import AppKit
import NetDeckCore
import SwiftUI

extension CredentialRef {
    var menuTitle: String { service == .named ? L("\(account) (con nombre)") : L("\(account) (equipo)") }
}

/// Catálogo del Llavero: los nombres y asociaciones se editan sin sacar los secretos de macOS.
struct PasswordSettings: View {
    private struct Edition: Identifiable {
        let id = UUID()
        let ref: CredentialRef?
    }
    @Environment(\.theme) private var t
    @Environment(AppModel.self) private var model
    @Stored private var query = ""
    @Stored private var message = ""
    @Stored private var edition: Edition?

    var body: some View {
        @Bindable var s = model.settings
        Form {
            Section {
                Toggle(L("Escribir sola la contraseña al abrir una sesión"), isOn: $s.sessionAutoPassword)
                Text(L("Al abrir SSH o SFTP, usa sólo la contraseña asignada a esa sesión y a cada salto. Si falta, te la pide; Telnet se inicia a mano. ")
                     + L("No espera a otras pestañas. Si no vale, te la pide a ti (no se bloquea)."))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            } header: { Text(L("Sesiones")) }
            Section {
                ThemedPicker(L("Cuando un equipo pide contraseña"), selection: $s.devicePasswordMode) { o in
                    o.append((PasswordAutomation.Mode.autoType, L("Escribirla sola")))
                    o.append((PasswordAutomation.Mode.suggest, L("Sugerirla (un clic)")))
                    o.append((PasswordAutomation.Mode.off, L("Nada")))
                }
                Text(L("Sólo después de enviar «ssh equipo» o «telnet» desde una sesión. La salida del equipo y los banners no activan la detección. ")
                     + L("El usuario debe coincidir exactamente; los códigos de un solo uso y los cambios de contraseña se contestan a mano. ")
                     + L("Si la credencial por defecto, escrita sola, no vale, no se vuelve a escribir sola en 15 min (a mano o con un botón, sí)."))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            } header: { Text(L("Equipos")) }
            Section {
                ThemedPicker(L("Credencial predeterminada"), selection: $s.defaultCredentialName) { o in
                    o.append(("", L("Ninguna (preguntar)")))
                    if !s.defaultCredentialName.isEmpty, !named.contains(s.defaultCredentialName) {
                        o.append((s.defaultCredentialName, L("\(s.defaultCredentialName) (no está en el Llavero)")))
                    }
                    for name in named { o.append((name, "🔑 \(name)")) }
                }
                if !s.defaultCredentialName.isEmpty {
                    LabeledContent(L("Usuario exacto")) {
                        TextField("", text: $s.defaultCredentialUser, prompt: Text(L("tu.usuario"))).frame(maxWidth: 380)
                    }
                    if s.defaultCredentialUser.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(L("Indica el usuario para activar la credencial predeterminada.")).font(.caption).foregroundStyle(.orange)
                    }
                    Button(L("Editar credencial…")) { edit(.named(s.defaultCredentialName)) }
                        .disabled(!model.hasCredential(.named(s.defaultCredentialName)))
                }
            } header: { Text(L("Por defecto")) } footer: {
                Text(L("Se usa si el equipo no tiene otra asignada y pide exactamente ese usuario. Las sesiones guardadas usan su propia asignación.")).font(t.ui(11))
            }
            Section {
                HStack {
                    SearchField(text: $query, prompt: L("Buscar credenciales"))
                    Button(L("Recargar")) { model.core.refreshKeychain() }.disabled(model.core.keychainLoading)
                    Button(L("Añadir…")) { edition = Edition(ref: nil) }
                }
                if model.core.keychainLoading { ProgressView().controlSize(.small) }
                if let error = model.core.keychainError { Text(error).font(.caption).foregroundStyle(.orange) }
                if filtered.isEmpty, !model.core.keychainLoading {
                    Text(model.keychainAccounts.isEmpty ? L("Añade una credencial y selecciónala en Sesiones.") : L("Sin coincidencias"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(filtered, id: \.self) { ref in
                    HStack {
                        Image(systemName: ref.service == .named ? "key.fill" : "server.rack")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ref.account).lineLimit(1).truncationMode(.middle)
                            Text(ref.service == .named ? L("Con nombre · asignable a sesiones y grupos") : L("Propia de este usuario y equipo"))
                                .font(t.ui(10.5)).foregroundStyle(.secondary)
                            if let use = usage(ref) { Text(use).font(t.ui(10.5)).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        Spacer()
                        Button(L("Editar…")) { edit(ref) }.help(L("Editar nombre, usuario, equipo o contraseña"))
                        if model.ledger.isBlocked(ref) {
                            Button(L("Desbloquear")) { model.ledger.reset(ref); model.keychainRevision += 1 }
                        } else if case .probing = model.ledger.state(of: ref) {
                            Button(L("Restablecer pendiente")) { model.ledger.reset(ref); model.keychainRevision += 1 }
                                .help(L("Úsalo sólo si el login pendiente ya terminó. No cambia la contraseña guardada."))
                        }
                        Button(role: .destructive) { delete(ref) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
                if !message.isEmpty { Text(message).font(t.ui(11)) }
            } header: { Text(L("Llavero de macOS")) } footer: {
                Text(L("Con nombre: reutiliza una credencial en las sesiones o grupos que elijas. Usuario y equipo: sólo para esa cuenta. Los secretos se guardan únicamente en el Llavero de macOS.")).font(t.ui(11))
            }
        }
        .formStyle(.themed)
        .disabled(model.core.editingCredential)
        .sheet(item: $edition) { item in
            CredentialEditorSheet(ref: item.ref) { _, result in message = result }
        }
        .onChange(of: s.sessionAutoPassword) { model.applyPasswordModes() }
        .onChange(of: s.devicePasswordMode) { model.applyPasswordModes() }
        .onAppear {
            if ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT"] != nil,
               ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT_ACTION"] == "settings:credencial" { edit(.named("AD")) }
        }
    }

    private var named: [String] { model.keychainAccounts.filter { $0.service == .named && $0.account != "-" }.map(\.account) }
    private var filtered: [CredentialRef] {
        model.keychainAccounts.filter { query.isEmpty || $0.account.localizedCaseInsensitiveContains(query) }
    }
    private func edit(_ ref: CredentialRef) { edition = Edition(ref: ref) }

    private func usage(_ ref: CredentialRef) -> String? {
        let file = model.sessionFile
        var parts: [String] = []
        if ref.service == .named {
            let use = file.usage(ofNamed: ref.account)
            if !use.sessions.isEmpty { parts.append(L("sesiones: \(use.sessions.prefix(6).joined(separator: ", "))\(use.sessions.count > 6 ? "…" : "")")) }
            if !use.groups.isEmpty { parts.append(L("grupos: \(use.groups.joined(separator: ", "))")) }
            if model.settings.defaultCredentialName == ref.account { parts.append(L("por defecto")) }
        } else {
            let names = file.sessions.filter {
                "\($0.user.isEmpty ? AppPaths.userName : $0.user)@\($0.host.isEmpty ? $0.name : $0.host)" == ref.account
            }.map(\.name)
            if !names.isEmpty { parts.append(L("sesiones: \(names.prefix(6).joined(separator: ", "))\(names.count > 6 ? "…" : "")")) }
        }
        return parts.isEmpty ? nil : L("La usan: ") + parts.joined(separator: " · ")
    }

    private func delete(_ ref: CredentialRef) {
        Task {
            let detail = [usage(ref), L("Las asignaciones que la usen quedarán sin contraseña guardada."), L("No se puede deshacer.")].compactMap { $0 }.joined(separator: "\n")
            guard await ThemedAlert.confirm(L("¿Borrar «\(ref.account)» del Llavero?"), message: detail, ok: L("Borrar"), destructive: true) else { return }
            do { try await model.store.deleteInBackground(ref) }
            catch { message = error.localizedDescription }
            model.keychainRevision += 1
        }
    }
}

/// Editar la identidad no exige volver a escribir el secreto; cambiarlo sigue siendo una decisión explícita.
struct CredentialEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    let ref: CredentialRef?
    var namedOnly = false
    var done: (CredentialRef, String) -> Void = { _, _ in }
    @Stored private var service = CredentialRef.Service.named
    @Stored private var name = ""
    @Stored private var user = ""
    @Stored private var host = ""
    @Stored private var first = ""
    @Stored private var second = ""
    @Stored private var error = ""
    @Stored private var busy = false

    init(ref: CredentialRef?, namedOnly: Bool = false, done: @escaping (CredentialRef, String) -> Void = { _, _ in }) {
        self.ref = ref; self.namedOnly = namedOnly; self.done = done
        _service = Stored(initialValue: ref?.service ?? .named)
        _name = Stored(initialValue: ref?.service == .named ? ref?.account ?? "" : "")
        var user = "", host = ""
        if let ref, ref.service == .device {
            if let at = ref.account.lastIndex(of: "@") {
                user = String(ref.account[..<at]); host = String(ref.account[ref.account.index(after: at)...])
            } else { host = ref.account }
        }
        _user = Stored(initialValue: user); _host = Stored(initialValue: host)
    }

    private var destination: CredentialRef {
        service == .named ? .named(name.trimmingCharacters(in: .whitespacesAndNewlines))
            : .device(user.trimmingCharacters(in: .whitespacesAndNewlines), host.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private var valid: Bool {
        (try? CredentialValidation.validateReference(destination)) != nil && first == second
            && (ref != nil || !first.isEmpty) && (ref != destination || !first.isEmpty)
    }

    private var referenceProblem: String? {
        guard !name.isEmpty || !user.isEmpty || !host.isEmpty else { return nil }
        do { try CredentialValidation.validateReference(destination); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if ref == nil, !namedOnly {
                        ThemedPicker(L("Tipo"), selection: $service) { o in
                            o.append((CredentialRef.Service.named, L("Con nombre")))
                            o.append((CredentialRef.Service.device, L("Usuario y equipo")))
                        }
                    }
                    if service == .named {
                        LabeledContent(L("Nombre")) { TextField("", text: $name, prompt: Text(L("Por ejemplo: Red principal"))) }
                    } else {
                        LabeledContent(L("Usuario")) { TextField("", text: $user) }
                        LabeledContent(L("Equipo")) { TextField("", text: $host, prompt: Text("core-01")) }
                    }
                    if let problem = referenceProblem { Text(problem).font(.caption).foregroundStyle(.orange) }
                } header: { Text(ref == nil ? L("Nueva credencial") : L("Editar credencial")) } footer: {
                    Text(service == .named
                         ? L("Al renombrarla se actualizan sus asignaciones en sesiones, grupos, botones, listas y la predeterminada.")
                         : L("La cuenta propia corresponde a ese usuario y equipo. Para contraseñas distintas según el servicio, usa credenciales con nombre."))
                        .font(.caption)
                }
                Section {
                    SecureField(ref == nil ? L("Contraseña") : L("Contraseña nueva (opcional)"), text: $first)
                    SecureField(L("Repítela"), text: $second)
                    if !second.isEmpty, first != second { Text(L("No coinciden")).font(.caption).foregroundStyle(.orange) }
                } footer: {
                    Text(ref == nil ? L("Se guarda únicamente en el Llavero de macOS.")
                         : L("Deja ambos campos vacíos para conservar la contraseña. Renombrar conserva también su bloqueo por fallo."))
                        .font(.caption)
                }
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .formStyle(.themed)
            Divider().overlay(SwiftUI.Color(t.panel))
            HStack {
                Spacer()
                Button(L("Cancelar")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(busy ? L("Guardando…") : L("Guardar")) { save() }
                    .keyboardShortcut(.defaultAction).disabled(!valid)
            }.padding(12)
        }
        .frame(width: 540, height: 420)
        .background(SwiftUI.Color(t.background.opaque))
        .foregroundStyle(SwiftUI.Color(t.text))
        .tint(SwiftUI.Color(t.accent))
        .themedControls()
        .disabled(busy)
        .interactiveDismissDisabled(busy)
    }

    private func save() {
        let target = destination, password = first.isEmpty ? nil : first
        busy = true; error = ""
        first = ""; second = ""
        Task {
            defer { busy = false }
            do {
                let message = try await model.guardarCredencial(from: ref, to: target, password: password)
                done(target, message)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
