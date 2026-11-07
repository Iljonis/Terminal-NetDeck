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
            LabeledContent(L("Equipo")) { TextField("", text: $device, prompt: Text(L("192.0.2.5 · admin@core-01 · core-01:2222"))).frame(maxWidth: 380) }
            ThemedPicker(L("Salto"), selection: $jump) { o in
                o.append(("", L("Directo")))
                for x in model.sessions.profiles { o.append((x.name, x.name)) }
            }
            LabeledContent(L("Usuario")) { TextField("", text: $user, prompt: Text(L("(el del equipo o el de la sesión)"))).frame(maxWidth: 380) }
            ThemedSegmented(L("Protocolo"), selection: $transport) { o in
                for x in [SessionProfile.Transport.ssh, .telnet] { o.append((x, x.rawValue)) }
            }
        }
        .formStyle(.themed)
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
            TextEditor(text: $text).themedEditor()
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
        .onAppear {
            // (desde la revisión del pegado: su texto, y a todas si iba con MultiExec)
            guard let d = model.pasteDraft else { return }
            model.pasteDraft = nil
            text = d.text
            toAll = d.toAll
        }
    }
}

/// Revisar antes de pegar (⌘V, «Pegar», clic derecho; Ajustes → Terminal → Pegar): el texto entero, las peligrosas con ⚠
/// y a dónde va. Sólo pregunta: «Pegar» lo pega entero y de golpe, como siempre; «Cancelar» (Esc), nada. Intro pega sólo
/// sin peligrosas: con alguna, hace falta el clic (como `AlertKeys`). Es una hoja: le quita el teclado al terminal, así
/// que ni ese Intro ni ese Esc llegan al equipo ni a MultiExec (y hasta que lo toma, `AppModel.userInput` lo descarta).
struct PasteReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    /// Lo que se revisa, ya mirado (`AppModel.reviewPaste`): copiado al abrir, para que al cerrar, con
    /// `model.pendingPaste` ya vacío, la hoja no se quede en blanco; al día si cambia a cuántas pestañas va.
    @Stored private var p: AppModel.PendingPaste?
    init(paste: AppModel.PendingPaste?) {
        _p = Stored(initialValue: paste)
    }

    var body: some View {
        let r = p?.review
        let count = r?.count ?? 0, dangerous = r?.dangerous.count ?? 0
        let tabs = p?.tabs ?? 1
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: dangerous == 0 ? "doc.on.clipboard" : "exclamationmark.triangle.fill")
                    .foregroundStyle(SwiftUI.Color(dangerous == 0 ? t.accent : t.warning))
                    .accessibilityHidden(true)
                Text(count == 1 ? L("¿Pegar 1 línea?") : L("¿Pegar \(String(count)) líneas?")).font(t.ui(14, .bold))
                Spacer()
                Text(p.map { $0.tabs > 1 ? L("En \(String($0.tabs)) pestañas a la vez (MultiExec)") : L("En «\($0.tabTitle)»") } ?? "")
                    .font(t.ui(12)).foregroundStyle(SwiftUI.Color(tabs > 1 ? t.warning : t.dim))
                    .lineLimit(1).truncationMode(.middle)
            }
            PastedText(review: r, font: Fonts.terminal(family: Fonts.firstInstalled(t.fonts), size: 12),
                       color: NSColor(t.text), warning: NSColor(t.warning),
                       onReturn: dangerous == 0 ? { model.acceptPaste() } : nil,
                       onEscape: { model.closePasteReview() })
                .themedEditor()
                .frame(height: min(360, max(120, CGFloat(r?.rows.count ?? 0) * 15 + 16)))
            if dangerous > 0 {
                Text(L("⚠ Lleva \(String(dangerous)) orden(es) peligrosa(s): revísalas antes de pegar"))
                    .font(t.ui(12, .bold)).foregroundStyle(SwiftUI.Color(t.warning))
            }
            if p?.moved == true {
                Text(L("⚠ Ahora va a \(String(tabs)) pestaña(s): no se ha pegado. Revísalo y vuelve a pulsar «Pegar»."))
                    .font(t.ui(12, .bold)).foregroundStyle(SwiftUI.Color(t.warning))
            }
            Text(L("Se pega entero y de golpe, como siempre. «Pegado seguro…» lo envía línea a línea esperando al equipo."))
                .font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            HStack(spacing: 8) {
                NeonButton(title: L("Pegado seguro…"), icon: "list.bullet", tint: t.dim) { model.safePastePending() }
                    .help(L("Una a una, esperando al equipo. Se para si da error, si pagina o con Esc."))
                Spacer()
                NeonButton(title: L("Cancelar"), icon: "xmark", tint: t.dim) { model.closePasteReview() }
                    .keyboardShortcut(.cancelAction)
                // (con peligrosas, Intro no pega: el botón es destructivo y sin atajo, como en `ThemedAlert`)
                if dangerous > 0 {
                    NeonButton(title: L("Pegar"), icon: "exclamationmark.triangle", tint: t.bad, role: .destructive) { model.acceptPaste() }
                } else {
                    NeonButton(title: L("Pegar"), icon: "checkmark", tint: t.accent, active: true) { model.acceptPaste() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .frame(width: 620)
        .onChange(of: model.pendingPaste) { _, n in if let n { p = n } }
        .onDisappear { if model.sheet != .pasteReview, model.pendingPaste != nil { model.closePasteReview() } }
    }
}

/// El texto pegado, de sólo lectura (`NSTextView`): se puede seleccionar, copiar (⌘C) y buscar (⌘F), y VoiceOver lo lee
/// entero. Sin ajuste de línea; las peligrosas, con ⚠ y en el color de aviso, y los caracteres de control, a la vista.
/// Se monta una vez (una configuración entera puede tener miles de líneas) y sólo se rehace si cambia el texto.
private struct PastedText: NSViewRepresentable {
    let review: PasteReview?
    let font: NSFont
    let color: NSColor
    let warning: NSColor
    /// Intro y Esc con el texto seleccionado: los de los botones (nil = Intro no hace nada, como en la hoja).
    let onReturn: (() -> Void)?
    let onEscape: () -> Void

    final class Coordinator { var shown: PasteReview? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let v = ReadOnlyTextView(frame: .zero)
        v.isEditable = false
        v.isSelectable = true
        v.drawsBackground = false
        v.usesFindBar = true
        v.isIncrementalSearchingEnabled = true
        v.textContainerInset = NSSize(width: 2, height: 4)
        // (sin ajuste de línea: cada una entera, con barra horizontal)
        v.isHorizontallyResizable = true
        v.isVerticallyResizable = true
        v.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        v.autoresizingMask = [.width, .height]
        v.textContainer?.widthTracksTextView = false
        v.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        v.setAccessibilityLabel(L("Texto que se va a pegar"))
        scroll.documentView = v
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let v = scroll.documentView as? ReadOnlyTextView else { return }
        v.onReturn = onReturn
        v.onEscape = onEscape
        guard context.coordinator.shown != review else { return }
        context.coordinator.shown = review
        v.textStorage?.setAttributedString(attributed())
    }

    private func attributed() -> NSAttributedString {
        let out = NSMutableAttributedString()
        guard let review else { return out }
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let bad: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: warning]
        let dangerous = Set(review.dangerous)
        for (i, row) in review.rows.enumerated() {
            let d = dangerous.contains(i)
            // (los caracteres de control, a la vista: «ls␈␈reboot» no es lo que parece)
            out.append(NSAttributedString(string: (d ? "⚠ " : "  ") + PasteRules.visible(row) + (i < review.rows.count - 1 ? "\n" : ""),
                                          attributes: d ? bad : normal))
        }
        return out
    }
}

/// El `NSTextView` de `PastedText`: no toma el teclado al abrir la hoja (sólo con un clic en él o con ⌘F), e Intro y Esc
/// no se los queda (un texto de sólo lectura pitaría y Esc sería «completar»): van a los botones.
private final class ReadOnlyTextView: NSTextView {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    private var wantsFocus = false

    override var acceptsFirstResponder: Bool {
        guard window?.firstResponder !== self, !wantsFocus else { return true }
        guard let e = NSApp.currentEvent, e.type == .leftMouseDown, e.window === window else { return false }
        return true
    }

    override func keyDown(with e: NSEvent) {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (e.keyCode, mods.isEmpty) {
        case (36, true), (76, true): onReturn?()                     // Intro y el del teclado numérico
        case (53, true): onEscape?()                                 // Esc
        default: super.keyDown(with: e)
        }
    }

    /// ⌘F y ⌘G desde cualquier sitio de la hoja (el «Buscar» del menú es el de la salida del terminal y está apagado).
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let action: NSTextFinder.Action? = switch (e.charactersIgnoringModifiers?.lowercased(), mods) {
        case ("f", [.command]): .showFindInterface
        case ("g", [.command]): .nextMatch
        case ("g", [.command, .shift]): .previousMatch
        default: nil
        }
        guard let action, e.window === window else { return super.performKeyEquivalent(with: e) }
        wantsFocus = true
        window?.makeFirstResponder(self)
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
        return true
    }
}

/// Lista por salto: cada equipo en su pestaña a través del salto, con reintentos controlados. Las listas se guardan
/// con nombre (listas.json, sin contraseñas: sólo el nombre de la del Llavero). Como hoja (⇧⌘L) o dentro de Ajustes
/// (`embedded`: las listas a la izquierda; los cambios sin guardar se preguntan al cambiar de lista o de sección).
struct ListSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    var embedded = false
    @Stored private var library = ListLibrary()
    @Stored private var selected: SavedList.ID?
    @Stored private var name = "lista"
    @Stored private var jump = ""
    @Stored private var user = ""
    @Stored private var credential = ""
    @Stored private var creatingCredential = false
    @Stored private var devices = ""
    @Stored private var message = ""
    /// Lo que había al elegir o guardar la lista: si lo de ahora no es igual, hay cambios sin guardar.
    @Stored private var baseline: [String] = []
    @Stored private var loaded = false
    /// Hay una acción en curso (un aviso abierto…): los clics seguidos no la repiten.
    @Stored private var busy = false
    /// Quién pone el aviso de cambios sin guardar en Ajustes (`AppModel.settingsLeave`).
    @Stored private var token = UUID()

    var body: some View {
        Group { if embedded { manager } else { sheet } }
            .sheet(isPresented: $creatingCredential) {
                CredentialEditorSheet(ref: nil, namedOnly: true) { ref, result in credential = ref.account; message = result }
            }
            .onAppear {
                if embedded { model.settingsLeave = (token, { dirty }, { await confirmLeave() }) }
                guard !loaded else { return }
                loaded = true
                load()
            }
            .onDisappear {
                if model.settingsLeave?.owner == token { model.settingsLeave = nil }
            }
    }

    private var fields: [String] { [name, jump, user, credential, devices] }
    private var dirty: Bool { fields != baseline }
    private var canOpen: Bool { !jump.isEmpty && !DeviceListText.parse(devices).devices.isEmpty }

    private var sheet: some View {
        form(picker: true)
            .frame(width: 520)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancelar")) { act { if await confirmLeave() { dismiss() } } }
                }
                ToolbarItem {
                    Button(L("Guardar lista")) { _ = saveList() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Abrir")) { openList() }.disabled(!canOpen)
                }
            }
    }

    /// En Ajustes: las listas a la izquierda (como el gestor de sesiones) y la elegida a la derecha.
    private var manager: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                lists.frame(width: 250)
                NeonLine(vertical: true, color: t.panel)
                form(picker: false).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            NeonLine(color: t.panel)
            HStack(spacing: 10) {
                Text(message.isEmpty ? AppPaths.tilde(ListLibrary.defaultURL.path) : message)
                    .font(t.ui(11)).foregroundStyle(SwiftUI.Color(message.hasPrefix("✗") ? t.bad : t.dim)).lineLimit(2)
                Spacer()
                NeonButton(title: L("Guardar lista"), icon: "checkmark", active: dirty) { _ = saveList() }
                    .disabled(busy || !dirty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut("s")
                NeonButton(title: L("Abrir"), icon: "bolt.horizontal.fill", tint: t.good) { openList() }
                    .disabled(busy || !canOpen)
                    .help(L("Cada equipo en su pestaña por el salto (tal como está, sin guardar)"))
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(SwiftUI.Color(t.bar))
        }
        .background(SwiftUI.Color(t.background))
    }

    private var lists: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("LISTAS")).font(t.ui(13, .heavy)).tracking(3).foregroundStyle(SwiftUI.Color(t.accent))
                Text("\(library.lists.count)").font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim))
                Spacer()
                if dirty { Text(L("● sin guardar")).font(t.ui(10, .bold)).foregroundStyle(SwiftUI.Color(t.warning)) }
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(library.lists) { l in
                        listRow(l.name, detail: L("\(l.devices.count) equipos") + (l.jump.isEmpty ? "" : "  ⟵ \(l.jump)"),
                                on: selected == l.id) { choose(l.id) }
                            .themedContextMenu {
                                Button(L("Duplicar")) { act { if await leaveTo(l.id) { await duplicate() } } }
                                Button(L("Renombrar…")) { act { if await leaveTo(l.id) { await rename() } } }
                                MenuDivider()
                                Button(L("Borrar…")) { act { if await leaveTo(l.id) { await remove() } } }
                            }
                    }
                    if selected == nil {
                        listRow(name.isEmpty ? L("(nueva, sin guardar)") : name, detail: L("(nueva, sin guardar)"), on: true) {}
                    }
                    if library.lists.isEmpty {
                        Text(L("Pon los equipos, el salto y «Guardar lista»"))
                            .font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim)).padding(8)
                    }
                }
                .padding(.horizontal, 8)
            }
            NeonLine(color: t.panel)
            HStack(spacing: 6) {
                IconButton(icon: "plus") { choose(nil) }.help(L("Nueva")).disabled(busy)
                IconButton(icon: "plus.square.on.square") { act { await duplicate() } }.help(L("Duplicar")).disabled(busy || selected == nil)
                IconButton(icon: "pencil") { act { await rename() } }.help(L("Renombrar…")).disabled(busy || selected == nil)
                IconButton(icon: "trash") { act { await remove() } }.help(L("Borrar…")).disabled(busy || selected == nil)
                Spacer()
                IconButton(icon: "square.and.arrow.down") { importFile() }.help(L("Importar equipos de un .txt/.csv…"))
            }
            .padding(8)
        }
        .background(SwiftUI.Color(t.bar))
    }

    private func listRow(_ title: String, detail: String, on: Bool, tap: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 10)).foregroundStyle(SwiftUI.Color(on ? t.onTab : t.accent2)).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(t.ui(12, .semibold)).lineLimit(1)
                Text(detail).font(t.ui(9.5)).opacity(0.7).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(SwiftUI.Color(on ? t.onTab : t.text))
        .padding(.vertical, 5).padding(.horizontal, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? SwiftUI.Color(t.tab) : SwiftUI.Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
    }

    /// El formulario de la lista; en la hoja, con el selector de listas guardadas arriba (en Ajustes van a la izquierda).
    private func form(picker: Bool) -> some View {
        let parsed = DeviceListText.parse(devices)
        return Form {
            if picker {
                Section {
                    HStack {
                        ThemedPicker(L("Lista guardada"), selection: Binding(get: { selected }, set: { choose($0) })) { o in
                            o.append((SavedList.ID?.none, L("(nueva, sin guardar)")))
                            for x in library.lists { o.append((SavedList.ID?.some(x.id), x.name)) }
                        }
                        ThemedMenu {
                            Button(L("Nueva")) { choose(nil) }
                            Button(L("Duplicar")) { act { await duplicate() } }.disabled(selected == nil)
                            Button(L("Renombrar…")) { act { await rename() } }.disabled(selected == nil)
                            Button(L("Importar equipos de un .txt/.csv…")) { importFile() }
                            MenuDivider()
                            Button(L("Borrar…"), role: .destructive) { act { await remove() } }.disabled(selected == nil)
                        } label: { Image(systemName: "ellipsis.circle") }.fixedSize()
                    }
                }
            }
            LabeledContent(L("Nombre")) { TextField("", text: $name, prompt: Text(L("Nombre"))).frame(maxWidth: 380) }
            ThemedPicker(L("Salto"), selection: $jump) { o in
                if !jump.isEmpty, model.sessions.profile(named: jump) == nil { o.append((jump, jump)) }
                for x in model.sessions.profiles { o.append((x.name, x.name)) }
            }
            LabeledContent(L("Usuario en los equipos")) { TextField("", text: $user, prompt: Text("tu.usuario")).frame(maxWidth: 380) }
            HStack {
                ThemedPicker(L("Contraseña"), selection: $credential) { o in
                    o.append(("", L("(a mano)")))
                    if !credential.isEmpty, !model.keychainAccounts.contains(where: { $0.account == credential }) {
                        o.append((credential, L("\(credential) (no está en el Llavero)")))
                    }
                    for r in model.keychainAccounts { o.append((r.account, r.account)) }
                }
                Button(L("Nueva…")) { creatingCredential = true }
                    .help(L("Guardar una contraseña nueva en el Llavero y usarla en esta lista"))
            }
            TextEditor(text: $devices).themedEditor()
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: embedded ? 220 : 140)
            Text(L("\(parsed.devices.count) equipos · una sola pestaña prueba la contraseña a la vez; si falla, no se escribe en las demás"))
                .font(.caption).foregroundStyle(.secondary)
            if !parsed.rejected.isEmpty {
                Text(L("No valen (se ignoran): \(parsed.rejected.prefix(5).joined(separator: " · "))"))
                    .font(.caption).foregroundStyle(.orange)
            }
            if picker, !message.isEmpty { Text(message).font(.caption) }
        }
        .formStyle(.themed)
        .scrollContentBackground(.hidden)
    }

    /// Abre la lista tal como está (sin guardarla) y cierra la hoja o los Ajustes para ver las pestañas.
    private func openList() {
        guard !busy, canOpen else { return }
        busy = true
        let list = makeList()
        if embedded, dirty {
            // (en Ajustes, con cambios sin guardar: se abre pero los Ajustes siguen, para no perderlos)
            message = L("✓ «\(name)» abierta sin guardar: los cambios siguen aquí")
            busy = false
        } else if embedded {
            model.showSettings = false
        } else {
            dismiss()
        }
        Task { await model.run(list) }
    }

    /// Una acción con aviso a la vez (borrar, renombrar, cambiar de lista con cambios): los clics seguidos no la
    /// repiten y el aviso sale con el clic ya terminado.
    private func act(_ action: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            await action()
            busy = false
        }
    }

    /// Elegir otra lista (o una nueva, `nil`): si la de ahora tiene cambios, antes se pregunta.
    private func choose(_ id: SavedList.ID?) {
        guard id != selected || id == nil else { return }
        act { if await confirmLeave() { pick(id) } }
    }

    /// Para actuar sobre otra lista (menú de una fila): primero se deja la de ahora (preguntando si tiene cambios).
    private func leaveTo(_ id: SavedList.ID) async -> Bool {
        guard id != selected else { return true }
        guard await confirmLeave() else { return false }
        pick(id)
        return true
    }

    /// Con cambios sin guardar: guardar, descartar o quedarse (`false`).
    private func confirmLeave() async -> Bool {
        guard dirty else { return true }
        switch await ThemedAlert.run(L("La lista «\(name)» tiene cambios sin guardar"),
                                     buttons: [L("Guardar"), L("Descartar"), L("Cancelar")]).button {
        case 0: return saveList()
        case 1: return true
        default: return false
        }
    }

    // MARK: listas guardadas

    private func load() {
        do { library = try ListLibrary(contentsOf: ListLibrary.defaultURL) } catch {
            ErrorLog.error("listas", "no se han podido leer: \(error.localizedDescription)")
            message = "✗ \(error.localizedDescription)"
        }
        if library.lists.isEmpty { jump = model.sessions.profiles.first?.name ?? "" }
        let error = message
        pick(library.lists.first?.id)
        message = error                             // (que no se pierda el aviso de que no se ha podido leer)
    }

    private func pick(_ id: SavedList.ID?) {
        selected = id
        if let l = library.list(id) {
            (name, jump, user, credential) = (l.name, l.jump, l.user, l.credential)
            devices = l.devices.joined(separator: "\n")
        } else {
            name = library.uniqueName("lista"); devices = ""
        }
        message = ""
        baseline = fields
    }

    private var current: SavedList {
        SavedList(id: selected ?? UUID(), name: name.trimmingCharacters(in: .whitespaces), jump: jump,
                  user: user.trimmingCharacters(in: .whitespaces), credential: credential,
                  devices: DeviceListText.parse(devices).devices.map(\.description))
    }

    @discardableResult private func persist(_ ok: String) -> Bool {
        do {
            try library.save()
            message = ok
            return true
        } catch {
            ErrorLog.error("listas", "no se han podido guardar: \(error.localizedDescription)")
            message = "✗ \(error.localizedDescription)"
            return false
        }
    }

    /// Guarda la de ahora (nueva o cambiada); `false` si no se ha podido (sin nombre o al escribir el archivo).
    private func saveList() -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = L("✗ Ponle un nombre a la lista")
            return false
        }
        let l = library.upsert(current)
        selected = l.id
        // (si no se ha podido escribir, sigue constando como cambiada: al salir se vuelve a preguntar)
        guard persist(L("✓ Lista «\(l.name)» guardada")) else { return false }
        let ok = message
        pick(l.id)
        message = ok
        return true
    }

    /// Copia de la guardada: si la de ahora tiene cambios, antes se pregunta (para que la copia los lleve o no).
    private func duplicate() async {
        guard let id = selected, await confirmLeave(), let c = library.duplicate(id) else { return }
        pick(c.id)
        persist(L("✓ Copia «\(c.name)»"))
    }

    private func rename() async {
        guard let id = selected, let old = library.list(id)?.name,
              let n = await SessionEditor.ask(L("Renombrar la lista «\(old)»"), value: old), !n.isEmpty,
              library.rename(id, to: n) else { return }
        // (sólo cambia el nombre: lo demás que estuviera sin guardar sigue así)
        let untouched = name == old
        if untouched {                              // (un nombre cambiado a mano y sin guardar no se pisa)
            name = library.list(id)?.name ?? n
            if baseline.count == fields.count { baseline[0] = name }
        }
        persist(L("✓ Renombrada"))
    }

    private func remove() async {
        guard let id = selected, let l = library.list(id) else { return }
        guard await ThemedAlert.confirm(L("¿Borrar la lista «\(l.name)»?"), message: L("Queda una copia en listas.json.anterior. Las contraseñas del Llavero no se tocan."), ok: L("Borrar"), destructive: true) else { return }
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
            ErrorLog.error("importar", "\(u.lastPathComponent): \(error.localizedDescription)")
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
