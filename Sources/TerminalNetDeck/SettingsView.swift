import AppKit
import NetDeckCore
import SwiftUI
import UniformTypeIdentifiers

/// Ajustes (⌘,): dentro de la ventana, con el tema (en pantalla completa no se van a otro escritorio).
struct SettingsOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    static var sections: [(id: String, title: String, icon: String)] { [
        ("contraseñas", L("Contraseñas"), "key.fill"), ("temas", L("Temas"), "paintpalette.fill"),
        ("fuentes", L("Fuentes"), "textformat"), ("resaltado", L("Resaltado"), "highlighter"),
        ("botones", L("Botones"), "rectangle.grid.1x2.fill"), ("registro", L("Registro"), "record.circle"),
        ("general", L("General"), "gearshape.fill"),
    ] }

    var body: some View {
        ZStack {
            SwiftUI.Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { model.showSettings = false }
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
        .onExitCommand { model.showSettings = false }
        .transition(.opacity)
    }

    private var nav: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t.neon ? L("AJUSTES") : L("Ajustes")).font(t.ui(t.neon ? 15 : 18, .heavy)).tracking(t.neon ? 3 : 0)
                .foregroundStyle(SwiftUI.Color(t.neon ? t.accent : t.text))
                .padding(.horizontal, 10).padding(.top, 18).padding(.bottom, 14)
            ForEach(Self.sections, id: \.id) { sec in
                let on = model.settingsTab == sec.id
                Button { model.settingsTab = sec.id } label: {
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
            NeonButton(title: L("Cerrar"), icon: "xmark") { model.showSettings = false }
                .keyboardShortcut(.cancelAction)
                .padding(10)
        }
        .padding(.horizontal, 8)
        .frame(width: 200)
        .background(SwiftUI.Color(t.bar.opaque))
    }

    @ViewBuilder private var content: some View {
        switch model.settingsTab {
        case "temas": ThemeSettings()
        case "fuentes": FontSettings()
        case "resaltado": HighlightSettings()
        case "botones": ButtonSettings()
        case "registro": LogSettings()
        case "general": GeneralSettings()
        default: PasswordSettings()
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

    var body: some View {
        @Bindable var s = model.settings
        Form {
            Section {
                Toggle(L("Escribir sola la contraseña al abrir una sesión"), isOn: $s.sessionAutoPassword)
                Text(L("La de la sesión y la de sus saltos (-J), con el askpass de la app: no se teclea en el terminal. ")
                     + L("Un solo intento: si falla, queda bloqueada 15 min en todas las pestañas y te la pide ahí mismo."))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            } header: { Text(L("Sesiones")) }

            Section {
                Picker(L("Cuando un equipo pide contraseña"), selection: $s.devicePasswordMode) {
                    Text(L("Escribirla sola")).tag(PasswordAutomation.Mode.autoType)
                    Text(L("Sugerirla (un clic)")).tag(PasswordAutomation.Mode.suggest)
                    Text(L("Nada")).tag(PasswordAutomation.Mode.off)
                }
                Text(L("Al hacer «ssh equipo» o «telnet» desde una sesión. Nunca la de otro usuario: con «ssh root@…» o ")
                     + L("«Username: pepe», sólo una guardada de ese mismo usuario."))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            } header: { Text(L("Equipos")) }

            Section {
                Picker(L("Contraseña por defecto"), selection: $s.defaultCredentialName) {
                    Text(L("(ninguna)")).tag("")
                    ForEach(named, id: \.self) { Text($0).tag($0) }
                }
                TextField(L("Es del usuario"), text: $s.defaultCredentialUser)
            } header: { Text(L("Por defecto")) } footer: {
                Text(L("Sólo se escribe sola cuando piden exactamente ese usuario.")).font(t.ui(11))
            }

            Section {
                ForEach(model.keychainAccounts, id: \.self) { ref in
                    HStack {
                        Image(systemName: ref.service == .named ? "key.fill" : "server.rack")
                        Text(ref.account)
                        Text(ref.service == .named ? L("con nombre") : L("usuario@equipo")).font(t.ui(11)).foregroundStyle(.secondary)
                        Spacer()
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
                    Picker("", selection: $newService) {
                        Text(L("Con nombre")).tag(CredentialRef.Service.named)
                        Text(L("usuario@equipo")).tag(CredentialRef.Service.device)
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    TextField(newService == .named ? L("Nombre (p. ej. AD)") : L("tu.usuario@192.0.2.1"), text: $newAccount)
                    SecureField(L("Contraseña"), text: $newPassword)
                    Button(L("Guardar"), action: save).disabled(newAccount.isEmpty || newPassword.isEmpty)
                }
                if !message.isEmpty { Text(message).font(t.ui(11)) }
            } header: { Text(L("Llavero (compartido con NetDeck)")) }
        }
        .formStyle(.grouped)
        .onChange(of: s.sessionAutoPassword) { model.applyPasswordModes() }
        .onChange(of: s.devicePasswordMode) { model.applyPasswordModes() }
    }

    private var named: [String] { model.keychainAccounts.filter { $0.service == .named }.map(\.account) }

    private func save() {
        let ref = CredentialRef(service: newService, account: newAccount.trimmingCharacters(in: .whitespaces))
        do {
            try model.store.save(newPassword, for: ref)
            model.ledger.reset(ref)
            message = L("Guardada ✓ (\(ref.account))")
            newAccount = ""
        } catch {
            message = error.localizedDescription
        }
        newPassword = ""
        model.keychainRevision += 1
    }

    private func delete(_ ref: CredentialRef) {
        let a = NSAlert()
        a.messageText = L("¿Borrar «\(ref.account)» del Llavero?")
        a.informativeText = L("La usa también NetDeck. No se puede deshacer.")
        a.addButton(withTitle: L("Borrar"))
        a.addButton(withTitle: L("Cancelar"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { try model.store.delete(ref) } catch { message = error.localizedDescription }
        model.keychainRevision += 1
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
                    Picker(L("Claro"), selection: $s.themeLight) { options }.frame(maxWidth: 170)
                    Picker(L("Oscuro"), selection: $s.themeDark) { options }.frame(maxWidth: 170)
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

    @ViewBuilder private var options: some View {
        ForEach(model.themes.all, id: \.theme.id) { Text($0.theme.name).tag($0.theme.id) }
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
                Picker(L("Fuente"), selection: $s.fontFamily) {
                    Text(L("Automática: la del tema (\(Fonts.firstInstalled(th.fonts) ?? L("monoespaciada del sistema")))")).tag("")
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag($0) }
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
                Picker(L("Fuente"), selection: $s.uiFontFamily) {
                    Text(L("La del tema (\(Fonts.firstInstalled(th.fonts) ?? "sistema"))")).tag("")
                    Text(L("Monoespaciada del sistema")).tag("system")
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag($0) }
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
                Text(L("Se instalan con Homebrew (brew install --cask font-…), como en NetDeck.")).font(t.ui(11))
            }
        }
        .formStyle(.grouped)
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
                Picker(L("Reglas"), selection: $s.highlightSource) {
                    Text(L("Automático")).tag(AppSettings.HighlightSource.auto)
                    Text(L("Las de NetDeck (chromaterm.yml)")).tag(AppSettings.HighlightSource.netdeck)
                    Text(L("Las de la app")).tag(AppSettings.HighlightSource.app)
                    Text(L("Personalizadas")).tag(AppSettings.HighlightSource.custom)
                }
                Toggle(L("Con los colores del tema"), isOn: $s.highlightThemeColors)
                HStack {
                    Text(model.highlightFile?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "—")
                        .font(t.ui(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Button(L("Editar…")) {
                        if let u = model.customizeHighlight() { NSWorkspace.shared.open(u) }
                    }
                    .help(L("Crea una copia personalizada (si no la hay) y la abre en tu editor"))
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
            Section(L("Reglas (\(cfg.rules.count))")) {
                ForEach(Array(cfg.rules.enumerated()), id: \.offset) { _, r in
                    Toggle(isOn: Binding(get: { !s.highlightDisabled.contains(r.description) },
                                         set: { on in
                                             if on { s.highlightDisabled.remove(r.description) } else { s.highlightDisabled.insert(r.description) }
                                             model.applyHighlight()
                                         })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.description)
                            Text(r.source).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
                    Text(s.logPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
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
                Button(L("Volver a la de NetDeck (~/Documents/netdeck-logs)")) { s.logPath = SessionLogger.defaultDirectory.path }
                    .disabled(s.logPath == SessionLogger.defaultDirectory.path)
            } header: { Text(L("Registro de las sesiones")) } footer: {
                Text(L("Texto limpio, como en NetDeck: sin colores y con los paginadores borrados, en CARPETA/AAAA-MM-DD/sesión_HH-MM-SS.log. ")
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
                    Text(DebugLog.file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption.monospaced())
                    Spacer()
                    Button(L("Abrir")) { DebugLog.flush(); NSWorkspace.shared.open(DebugLog.file) }
                }
            } header: { Text(L("Depuración")) } footer: {
                Text(L("Qué hace la app (pestañas, saltos, MultiExec, decisiones de contraseña…), nunca contraseñas.")).font(t.ui(11))
            }
        }
        .formStyle(.grouped)
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
                Picker(L("Idioma de la interfaz"), selection: $s.language) {
                    ForEach(Idioma.allCases) { Text($0.nombre).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section(L("Sesiones")) {
                HStack {
                    TextField("ssh_config", text: $s.sshConfigPath)
                    Button(L("Elegir…")) {
                        let p = NSOpenPanel()
                        p.showsHiddenFiles = true
                        p.directoryURL = s.sshConfigURL.deletingLastPathComponent()
                        if p.runModal() == .OK, let u = p.url { s.sshConfigPath = u.path }
                    }
                    Button(L("Recargar")) { model.reloadSessions() }
                }
                Text(L("\(model.sessions.profiles.count) sesiones · anotaciones de NetDeck: # @grupo, # @clave, # @clave-grupo, # @desc, # @telnet"))
                    .font(t.ui(11)).foregroundStyle(.secondary)
            }
            Section(L("Ventana")) {
                Toggle(L("Mostrar la lista de sesiones"), isOn: $s.sidebarVisible)
                Toggle(L("Efecto CRT en la portada (rejilla y líneas de barrido)"), isOn: $s.crtEffect)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - botones (la barra de NetDeck)

struct ButtonSettings: View {
    @Environment(\.theme) private var t
    var body: some View { ButtonEditor() }
}
