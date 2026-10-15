import AppKit
import NetDeckCore
import SwiftUI
import UniformTypeIdentifiers

/// Ajustes (⌘,): dentro de la ventana, con el tema (en pantalla completa no se van a otro escritorio).
struct SettingsOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    /// Preguntando si se guardan los cambios de la sección: los clics seguidos no lo repiten.
    @Stored private var leaving = false

    static var sections: [(id: String, title: String, icon: String)] { [
        ("contraseñas", L("Contraseñas"), "key.fill"), ("sesiones", L("Sesiones"), "server.rack"),
        ("listas", L("Listas"), "list.bullet.rectangle"), ("temas", L("Temas"), "paintpalette.fill"),
        ("fuentes", L("Fuentes"), "textformat"), ("resaltado", L("Resaltado"), "highlighter"),
        ("botones", L("Botones"), "rectangle.grid.1x2.fill"), ("registro", L("Registro"), "record.circle"),
        ("general", L("General"), "gearshape.fill"),
    ] }

    var body: some View {
        ZStack {
            SwiftUI.Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { leave(to: nil) }
            HStack(spacing: 0) {
                nav
                NeonLine(vertical: true, color: t.panel)
                content
                    .font(t.ui(13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: 1000, maxHeight: 720)
            .background(SwiftUI.Color(t.background.opaque))
            .clipShape(RoundedRectangle(cornerRadius: t.neon ? 6 : 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: t.neon ? 6 : 14, style: .continuous)
                .strokeBorder(SwiftUI.Color(t.accent).opacity(t.neon ? 0.6 : 0.25)))
            .shadow(color: SwiftUI.Color(t.accent).opacity(0.3), radius: t.glow(20))
            .shadow(color: .black.opacity(0.4), radius: 30)
            .padding(30)
        }
        .tint(SwiftUI.Color(t.accent))
        .foregroundStyle(SwiftUI.Color(t.text))
        .onExitCommand { leave(to: nil) }
        .transition(.opacity)
    }

    private var nav: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t.neon ? L("AJUSTES") : L("Ajustes")).font(t.ui(t.neon ? 15 : 18, .heavy)).tracking(t.neon ? 3 : 0)
                .foregroundStyle(SwiftUI.Color(t.neon ? t.accent : t.text))
                .padding(.horizontal, 10).padding(.top, 18).padding(.bottom, 14)
            ForEach(Self.sections, id: \.id) { sec in
                let on = model.settingsTab == sec.id
                Button { leave(to: sec.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: sec.icon).frame(width: 18)
                            .foregroundStyle(SwiftUI.Color(on ? t.onTab : t.accent2))
                        Text(sec.title).font(t.ui(12.5, on ? .bold : .regular))
                        Spacer()
                    }
                    .foregroundStyle(SwiftUI.Color(on ? t.onTab : t.text))
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: t.neon ? 4 : 8).fill(on ? SwiftUI.Color(t.tab) : SwiftUI.Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            NeonButton(title: L("Cerrar"), icon: "xmark") { leave(to: nil) }
                .keyboardShortcut(.cancelAction)
                .padding(10)
        }
        .padding(.horizontal, 8)
        .frame(width: 200)
        .background(SwiftUI.Color(t.bar.opaque))
    }

    @ViewBuilder private var content: some View {
        switch model.settingsTab {
        case "sesiones": SessionEditor(embedded: true)
        case "listas": ListSheet(embedded: true)
        case "temas": ThemeSettings()
        case "fuentes": FontSettings()
        case "resaltado": HighlightSettings()
        case "botones": ButtonSettings()
        case "registro": LogSettings()
        case "general": GeneralSettings()
        default: PasswordSettings()
        }
    }

    /// Otra sección (`tab`) o cerrar (`nil`); si la de ahora tiene cambios sin guardar, antes se pregunta.
    private func leave(to tab: String?) {
        guard tab != model.settingsTab, !leaving else { return }
        leaving = true
        Task {
            defer { leaving = false }
            if let g = model.settingsLeave, !(await g.check()) { return }
            if let tab { model.settingsTab = tab } else { model.showSettings = false }
        }
    }
}

// MARK: - contraseñas

struct PasswordSettings: View {
    @Environment(\.theme) private var t
    @Environment(AppModel.self) private var model
    @Stored private var newService = CredentialRef.Service.named
    @Stored private var newAccount = ""
    @Stored private var newPassword = ""
    @Stored private var message = ""
    @Stored private var editing: CredentialRef?

    var body: some View {
        @Bindable var s = model.settings
        let sessions = model.sessionFile
        Form {
            Section {
                Toggle(L("Escribir sola la contraseña al abrir una sesión"), isOn: $s.sessionAutoPassword)
                Text(L("La de la sesión y la de sus saltos (-J), con el askpass de la app: no se teclea en el terminal. ")
                     + L("Un solo intento: si falla, queda bloqueada 15 min en todas las pestañas y te la pide ahí mismo."))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            } header: { Text(L("Sesiones")) }

            Section {
                ThemedPicker(L("Cuando un equipo pide contraseña"), selection: $s.devicePasswordMode) { o in
                    o.append((PasswordAutomation.Mode.autoType, L("Escribirla sola")))
                    o.append((PasswordAutomation.Mode.suggest, L("Sugerirla (un clic)")))
                    o.append((PasswordAutomation.Mode.off, L("Nada")))
                }
                Text(L("Al hacer «ssh equipo» o «telnet» desde una sesión. Nunca la de otro usuario: con «ssh root@…» o ")
                     + L("«Username: pepe», sólo una guardada de ese mismo usuario."))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            } header: { Text(L("Equipos")) }

            Section {
                ThemedPicker(L("Contraseña por defecto"), selection: $s.defaultCredentialName) { o in
                    o.append(("", L("(ninguna)")))
                    for x in named { o.append((x, x)) }
                }
                LabeledContent(L("Es del usuario")) { TextField("", text: $s.defaultCredentialUser, prompt: Text(L("Es del usuario"))).frame(maxWidth: 380) }
            } header: { Text(L("Por defecto")) } footer: {
                Text(L("Sólo se escribe sola cuando piden exactamente ese usuario.")).font(t.ui(11))
            }

            Section {
                ForEach(model.keychainAccounts, id: \.self) { ref in
                    HStack {
                        Image(systemName: ref.service == .named ? "key.fill" : "server.rack")
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(ref.account)
                                Text(ref.service == .named ? L("con nombre") : L("usuario@equipo")).font(t.ui(11)).foregroundStyle(.secondary)
                            }
                            if let u = usage(ref, sessions) {
                                Text(u).font(t.ui(10.5)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        Button(L("Editar…")) { editing = ref }
                            .help(L("Cambiar la contraseña guardada"))
                        if model.ledger.isBlocked(ref) {
                            Button(L("Desbloquear")) {
                                model.ledger.reset(ref)
                                model.keychainRevision += 1
                            }
                            .help(L("Ha fallado hace poco: ahora no se escribe sola (para no bloquear la cuenta AD)"))
                        }
                        Button(role: .destructive) { delete(ref) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    ThemedPicker("", selection: $newService) { o in
                        o.append((CredentialRef.Service.named, L("Con nombre")))
                        o.append((CredentialRef.Service.device, L("usuario@equipo")))
                    }
                    .frame(width: 140)
                    TextField(newService == .named ? L("Nombre (p. ej. AD)") : L("tu.usuario@192.0.2.1"), text: $newAccount)
                    SecureField(L("Contraseña"), text: $newPassword)
                    Button(L("Guardar"), action: save).disabled(newAccount.isEmpty || newPassword.isEmpty)
                }
                if !message.isEmpty { Text(message).font(t.ui(11)) }
            } header: { Text(L("Llavero")) }
        }
        .formStyle(.themed)
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let ref = editing { PasswordChangeSheet(ref: ref) { message = $0 } }
        }
        .onChange(of: s.sessionAutoPassword) { model.applyPasswordModes() }
        .onChange(of: s.devicePasswordMode) { model.applyPasswordModes() }
    }

    private var named: [String] { model.keychainAccounts.filter { $0.service == .named }.map(\.account) }

    /// «Sesiones: core-01, core-02 · grupos: Core · por defecto».
    private func usage(_ ref: CredentialRef, _ file: SessionFile) -> String? {
        var parts: [String] = []
        if ref.service == .named {
            let u = file.usage(ofNamed: ref.account)
            if !u.sessions.isEmpty { parts.append(L("sesiones: \(u.sessions.prefix(6).joined(separator: ", "))\(u.sessions.count > 6 ? "…" : "")")) }
            if !u.groups.isEmpty { parts.append(L("grupos: \(u.groups.joined(separator: ", "))")) }
            if model.settings.defaultCredentialName == ref.account { parts.append(L("por defecto")) }
        } else {
            let s = file.sessions.filter {
                "\($0.user.isEmpty ? NSUserName() : $0.user)@\($0.host.isEmpty ? $0.name : $0.host)" == ref.account
            }.map(\.name)
            if !s.isEmpty { parts.append(L("sesiones: \(s.prefix(6).joined(separator: ", "))\(s.count > 6 ? "…" : "")")) }
        }
        return parts.isEmpty ? nil : L("La usan: ") + parts.joined(separator: " · ")
    }

    private func save() {
        let ref = CredentialRef(service: newService, account: newAccount.trimmingCharacters(in: .whitespaces))
        let pw = newPassword
        newPassword = ""                            // (vacío: el botón se apaga y un segundo clic no la guarda otra vez)
        // (el Llavero, fuera del hilo principal: si pide desbloquearse, la ventana no se congela)
        Task {
            do {
                try await model.store.saveInBackground(pw, for: ref)
                model.ledger.reset(ref)
                message = L("Guardada ✓ (\(ref.account))")
                newAccount = ""
            } catch {
                ErrorLog.error("llavero", "no se ha podido guardar «\(ref.account)»: \(error.localizedDescription)")
                message = error.localizedDescription
            }
            model.keychainRevision += 1
        }
    }

    private func delete(_ ref: CredentialRef) {
        Task {
            guard await ThemedAlert.confirm(L("¿Borrar «\(ref.account)» del Llavero?"), message: L("No se puede deshacer."), ok: L("Borrar"), destructive: true) else { return }
            do { try await model.store.deleteInBackground(ref) } catch {
                ErrorLog.error("llavero", "no se ha podido borrar «\(ref.account)»: \(error.localizedDescription)")
                message = error.localizedDescription
            }
            model.keychainRevision += 1
        }
    }
}

/// Cambiar una contraseña del Llavero (la sustituye: `save` actualiza si ya existe). Dos veces, para no equivocarse.
/// Nunca se guarda ni se registra en otro sitio.
struct PasswordChangeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ref: CredentialRef
    var done: (String) -> Void = { _ in }
    @Stored private var first = ""
    @Stored private var second = ""
    @Stored private var error = ""

    var body: some View {
        let exists = model.store.contains(ref)
        Form {
            Section {
                SecureField(L("Contraseña nueva"), text: $first)
                SecureField(L("Repítela"), text: $second)
                if !second.isEmpty, first != second {
                    Text(L("No coinciden")).font(.caption).foregroundStyle(.orange)
                }
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            } header: {
                Text(exists ? L("Cambiar «\(ref.account)»") : L("Guardar «\(ref.account)»"))
            } footer: {
                Text(L("Se guarda sólo en el Llavero y se olvida su bloqueo por fallo."))
                    .font(.caption)
            }
        }
        .formStyle(.themed)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L("Cancelar")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(exists ? L("Sustituir") : L("Guardar")) { save() }
                    .disabled(first.isEmpty || first != second)
            }
        }
    }

    private func save() {
        let pw = first
        first = ""; second = ""                     // (vacías: el botón se apaga mientras se guarda)
        Task {
            do {
                try await model.store.saveInBackground(pw, for: ref)
                model.ledger.reset(ref)
                model.keychainRevision += 1
                done(L("Guardada ✓ (\(ref.account))"))
                dismiss()
            } catch {
                ErrorLog.error("llavero", "no se ha podido cambiar «\(ref.account)»: \(error.localizedDescription)")
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - temas

struct ThemeSettings: View {
    @Environment(\.theme) private var t
    @Environment(AppModel.self) private var model
    @Stored private var hovered: String?
    @Stored private var message = ""

    var body: some View {
        @Bindable var s = model.settings
        let themes = model.themes
        VStack(alignment: .leading, spacing: 0) {
            ThemePreview(theme: hovered.flatMap(themes.theme(id:)) ?? themes.current)
                .frame(height: 190)
                .padding([.horizontal, .top], 14)
            HStack(spacing: 10) {
                Toggle(L("Seguir al Mac (claro / oscuro)"), isOn: $s.themeAuto)
                if s.themeAuto {
                    ThemedPicker(L("Claro"), selection: $s.themeLight, options: options).frame(maxWidth: 220)
                    ThemedPicker(L("Oscuro"), selection: $s.themeDark, options: options).frame(maxWidth: 220)
                }
                Spacer()
                Button(L("Importar .tema…"), action: importFile)
            }
            .font(t.ui(12))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if !message.isEmpty { Text(message).font(t.ui(11)).padding(.horizontal, 14) }
            ScrollView {
                ThemeGallery(active: themes.current.id,
                             select: { id in
                                 if s.themeAuto { s.themeAuto = false }
                                 model.selectTheme(id)
                             },
                             hover: { hovered = $0 },
                             remove: { model.themes.remove($0); model.selectTheme(model.themes.current.id) })
                    .padding(14)
            }
        }
        .background(SwiftUI.Color(themes.current.background))
        .foregroundStyle(SwiftUI.Color(themes.current.text))
        .environment(\.theme, themes.current)
        .onChange(of: s.themeAuto) { model.followAppearance() }
        .onChange(of: s.themeLight) { model.followAppearance() }
        .onChange(of: s.themeDark) { model.followAppearance() }
    }

    private var options: [(value: String, label: String)] {
        model.themes.all.map { ($0.theme.id, $0.theme.name) }
    }

    private func importFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType(filenameExtension: "tema") ?? .plainText]
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        message = p.urls.map { model.themes.importTheme(file: $0) }.joined(separator: " · ")
    }
}

// MARK: - fuentes (aparte de los temas: se cambian cuando quieras)

struct FontSettings: View {
    @Environment(\.theme) private var t
    @Environment(AppModel.self) private var model
    @Stored private var families: [String] = []
    @Stored private var message = ""
    @Stored private var installing: String?

    var body: some View {
        @Bindable var s = model.settings
        let th = model.themes.current
        Form {
            Section(L("Terminal")) {
                ThemedPicker(L("Fuente"), selection: $s.fontFamily) { o in
                    o.append(("", L("Automática: la del tema (\(Fonts.firstInstalled(th.fonts) ?? L("monoespaciada del sistema")))")))
                    for x in families { o.append((x, x)) }
                }
                HStack {
                    Text(L("Tamaño"))
                    Slider(value: $s.fontSize, in: 0...26, step: 1)
                    Text(s.fontSize == 0 ? L("del tema (\(th.size - 1))") : L("\(Int(s.fontSize)) pt")).monospacedDigit().frame(width: 110)
                }
                Text(L("core-01(config)# interface xe-0/0/1\nadmin@core-01> show bgp summary | match Estab"))
                    .font(SwiftUI.Font(model.terminalFont))
                    .foregroundStyle(SwiftUI.Color(th.text))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SwiftUI.Color(th.background))
            }
            Section(L("Interfaz")) {
                ThemedPicker(L("Fuente"), selection: $s.uiFontFamily) { o in
                    o.append(("", L("La del tema (\(Fonts.firstInstalled(th.fonts) ?? "sistema"))")))
                    o.append(("system", L("Monoespaciada del sistema")))
                    for x in families { o.append((x, x)) }
                }
            }
            Section {
                ForEach(catalog, id: \.self) { f in
                    let ok = Fonts.isInstalled(f)
                    HStack {
                        Text(f).font(ok ? .custom(f, size: 13) : .body)
                        if f == th.fonts.first { Text(L("oficial de \(th.name)")).font(t.ui(11)).foregroundStyle(.secondary) }
                        Spacer()
                        if ok {
                            Button(L("Terminal")) { s.fontFamily = f }.disabled(s.fontFamily == f)
                            Button(L("Interfaz")) { s.uiFontFamily = f }.disabled(s.uiFontFamily == f)
                        } else if installing == f {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(L("Instalar")) { install(f) }.disabled(installing != nil)
                        }
                    }
                }
                if !message.isEmpty { Text(message).font(t.ui(11)) }
            } header: { Text(L("Fuentes de los temas")) } footer: {
                Text(L("Se instalan mediante Homebrew (brew install --cask font-…).")).font(t.ui(11))
            }
        }
        .formStyle(.themed)
        .onAppear { families = Fonts.monospacedFamilies() }
        .onChange(of: s.fontFamily) { model.applyAppearance() }
        .onChange(of: s.fontSize) { model.applyAppearance() }
    }

    /// Todas las fuentes que recomiendan los temas (instalados y del catálogo).
    private var catalog: [String] {
        let all = model.themes.all.map(\.theme)
        var seen = Set<String>()
        return all.flatMap(\.fonts).filter { seen.insert($0).inserted }.sorted()
    }

    private func install(_ f: String) {
        installing = f
        message = L("Instalando «\(f)»…")
        Task {
            let ok = await Fonts.install(f)
            installing = nil
            message = ok ? L("«\(f)» instalada ✓") : L("No se ha podido instalar «\(f)» (¿falta Homebrew?)")
            families = Fonts.monospacedFamilies()
            model.applyAppearance()
        }
    }
}

// MARK: - resaltado (tipo ChromaTerm)

struct HighlightSettings: View {
    @Environment(\.theme) private var t
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var s = model.settings
        let cfg = model.highlightConfig
        Form {
            Section {
                Toggle(L("Resaltar la salida de los equipos"), isOn: $s.highlightEnabled)
                ThemedPicker(L("Reglas"), selection: $s.highlightSource) { o in
                    o.append((AppSettings.HighlightSource.auto, L("Automático")))
                    o.append((AppSettings.HighlightSource.netdeck, L("Reglas incluidas (chromaterm.yml)")))
                    o.append((AppSettings.HighlightSource.app, L("Las de la app")))
                    o.append((AppSettings.HighlightSource.custom, L("Personalizadas")))
                }
                Toggle(L("Con los colores del tema"), isOn: $s.highlightThemeColors)
                HStack {
                    Text(model.highlightFile.map { AppPaths.tilde($0.path) } ?? "—")
                        .font(t.ui(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Button(L("Abrir en el editor…")) {
                        if let u = model.customizeHighlight() { NSWorkspace.shared.open(u) }
                    }
                    .help(L("Crea una copia personalizada (si no la hay) y la abre en tu editor de texto"))
                    Button(L("Recargar")) { model.reloadHighlight() }
                }
                if !cfg.problems.isEmpty {
                    Text(L("No se han podido leer: ") + cfg.problems.joined(separator: " · ")).font(t.ui(11)).foregroundStyle(.red)
                }
            } header: { Text(L("Resaltado tipo ChromaTerm")) } footer: {
                Text(L("Mismo formato que ChromaTerm (description, regex, color «f.cyan bold», exclusive). ")
                     + L("No toca los colores que ya pone el equipo ni las pantallas completas (vi, less, top)."))
                    .font(t.ui(11))
            }
            Section(L("Vista previa")) {
                HighlightPreview(enabled: s.highlightEnabled).environment(\.theme, model.themes.current)
            }
            HighlightRuleList()
        }
        .formStyle(.themed)
        .onChange(of: s.highlightEnabled) { model.applyHighlight() }
        .onChange(of: s.highlightThemeColors) { model.applyHighlight() }
        .onChange(of: s.highlightSource) { model.reloadHighlight() }
    }

}

// MARK: - registro de las sesiones

struct LogSettings: View {
    @Environment(\.theme) private var t
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var s = model.settings
        Form {
            Section {
                Toggle(L("Grabar todas las sesiones a un archivo"), isOn: $s.logEnabled)
                HStack {
                    Text(AppPaths.tilde(s.logPath))
                        .font(.callout.monospaced()).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Button(L("Elegir carpeta…")) {
                        let p = NSOpenPanel()
                        p.canChooseDirectories = true
                        p.canChooseFiles = false
                        p.canCreateDirectories = true
                        p.directoryURL = s.logURL
                        if p.runModal() == .OK, let u = p.url { s.logPath = u.path }
                    }
                    Button(L("Abrir")) {
                        AppPaths.ensure(s.logURL)
                        NSWorkspace.shared.open(s.logURL)
                    }
                }
                Button(L("Volver a la predeterminada (~/Documents/netdeck-logs)")) { s.logPath = SessionLogger.defaultDirectory.path }
                    .disabled(s.logPath == SessionLogger.defaultDirectory.path)
            } header: { Text(L("Registro de las sesiones")) } footer: {
                Text(L("Texto limpio: sin colores y con los paginadores borrados, en CARPETA/AAAA-MM-DD/sesión_HH-MM-SS.log. ")
                     + L("Mientras graba sale ● REC en la esquina; clic derecho en una pestaña para grabar o parar sólo esa."))
                    .font(t.ui(11))
            }
            Section(L("Ahora")) {
                let rec = model.tabs.filter { $0.logFile != nil }
                if rec.isEmpty { Text(L("Ninguna pestaña grabando")).foregroundStyle(.secondary) }
                ForEach(rec) { t in
                    HStack {
                        Text("● \(t.title)").foregroundStyle(.red)
                        Spacer()
                        Button(L("Abrir")) { t.logFile.map { _ = NSWorkspace.shared.open($0) } }
                        Button(L("Parar")) { model.toggleLog(t) }
                    }
                }
            }
            Section {
                Toggle(L("Registro de depuración"), isOn: $s.debugLog)
                HStack {
                    Text(AppPaths.tilde(DebugLog.file.path)).font(.caption.monospaced())
                    Spacer()
                    Button(L("Abrir")) { DebugLog.flush(); NSWorkspace.shared.open(DebugLog.file) }
                }
            } header: { Text(L("Depuración")) } footer: {
                Text(L("Qué hace la app (pestañas, saltos, MultiExec, decisiones de contraseña…), nunca contraseñas.")).font(t.ui(11))
            }
        }
        .formStyle(.themed)
    }
}

// MARK: - general

struct GeneralSettings: View {
    @Environment(\.theme) private var t
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var s = model.settings
        Form {
            Section(L("Idioma")) {
                ThemedSegmented(L("Idioma de la interfaz"), selection: $s.language) { o in
                    for x in Idioma.allCases { o.append((x, x.nombre)) }
                }
            }
            Section(L("Sesiones")) {
                HStack {
                    LabeledContent("ssh_config") { TextField("", text: $s.sshConfigPath, prompt: Text("ssh_config")).frame(maxWidth: 380) }
                    Button(L("Elegir…")) {
                        let p = NSOpenPanel()
                        p.showsHiddenFiles = true
                        p.directoryURL = s.sshConfigURL.deletingLastPathComponent()
                        if p.runModal() == .OK, let u = p.url { s.sshConfigPath = u.path }
                    }
                    Button(L("Recargar")) { model.reloadSessions() }
                }
                Text(L("\(model.sessions.profiles.count) sesiones · anotaciones: # @grupo, # @clave, # @clave-grupo, # @desc, # @telnet"))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            }
            Section(L("Al arrancar")) {
                ThemedPicker(L("Sesión de inicio"), selection: $s.startupSession) { o in
                    o.append(("", L("(ninguna)")))
                    if !s.startupSession.isEmpty, model.startupProfile == nil { o.append((s.startupSession, L("\(s.startupSession) (ya no existe)"))) }
                    for x in model.sessions.profiles.map(\.name) { o.append((x, x)) }
                }
                Toggle(L("Abrir una terminal local al arrancar si no hay otras pestañas"), isOn: $s.startupLocalTerminal)
                Text(L("La sesión de inicio también se marca con clic derecho en la lista y se abre con ⌥⌘K; la terminal local, con ⌘T."))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            }
            Section(L("Actualizaciones")) {
                Toggle(L("Buscar versiones nuevas automáticamente (una vez al día)"), isOn: $s.autoUpdateCheck)
                HStack {
                    Text(L("Versión \(UpdateCheck.currentVersion == "0" ? "dev" : UpdateCheck.currentVersion)")).font(t.ui(11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Buscar ahora")) { model.checkForUpdates() }
                }
            }
            Section(L("Conexiones")) {
                Toggle(L("Enviar el idioma del Mac a los servidores (LANG, LC_*)"), isOn: $s.sendLocale)
                Text(L("Desactivado, los servidores usan su propio idioma y no salen avisos como «setlocale: LC_CTYPE». Se aplica a las conexiones nuevas."))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            }
            Section(L("Ratón")) {
                Toggle(L("Copiar al seleccionar"), isOn: $s.copyOnSelect)
                Toggle(L("Pegar con clic derecho"), isOn: $s.pasteOnRightClick)
                Text(L("Como en PuTTY o SecureCRT. El clic derecho pega igual que ⌘V; con ⌃ o ⌥ abre el menú de siempre."))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            }
            Section(L("Ventana")) {
                Toggle(L("Mostrar la lista de sesiones"), isOn: $s.sidebarVisible)
                Toggle(L("Efecto CRT en la portada (rejilla y líneas de barrido)"), isOn: $s.crtEffect)
            }
        }
        .formStyle(.themed)
    }
}

// MARK: - botones (la barra)

struct ButtonSettings: View {
    @Environment(\.theme) private var t
    var body: some View { ButtonEditor() }
}
