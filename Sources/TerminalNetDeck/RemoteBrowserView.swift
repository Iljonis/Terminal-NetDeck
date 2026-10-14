import AppKit
import NetDeckCore
import SwiftUI
import UniformTypeIdentifiers

extension Theme {
    /// La letra de las terminales del tema (para tamaños, permisos y rutas).
    func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let f = Fonts.firstInstalled(fonts) { return .custom(f, size: size).weight(weight) }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

/// «Vista gráfica / Consola»: arriba del explorador y de la consola sftp de la pestaña.
struct RemoteModeSwitch: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let session: TerminalSession

    var body: some View {
        HStack(spacing: 0) {
            segment(L("Vista gráfica"), icon: "folder.fill", on: !session.showConsole) { model.setConsole(false, in: session) }
            segment(L("Consola"), icon: "terminal.fill", on: session.showConsole) { model.setConsole(true, in: session) }
                .disabled(session.route.transport != .sftp)
                .help(session.route.transport == .sftp ? L("La consola sftp de siempre (put, get, ls…)")
                                                       : L("FTP no tiene consola: macOS no trae cliente"))
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: (t.corner ?? 6) + 2).fill(SwiftUI.Color(t.background.opaque).opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: (t.corner ?? 6) + 2).strokeBorder(SwiftUI.Color(t.accent).opacity(0.3)))
    }

    private func segment(_ title: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(t.ui(11, .semibold)).lineLimit(1)
            }
            .foregroundStyle(SwiftUI.Color(on ? t.accent.readable : t.text))
            .padding(.horizontal, 10).frame(height: 22)
            .background(RoundedRectangle(cornerRadius: t.corner ?? 6).fill(SwiftUI.Color(t.accent).opacity(on ? 1 : 0)))
            .shadow(color: SwiftUI.Color(t.accent).opacity(on ? 0.5 : 0), radius: t.glow(5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Barra fina encima de la consola sftp: volver a la vista gráfica.
struct RemoteConsoleBar: View {
    @Environment(\.theme) private var t
    let session: TerminalSession

    var body: some View {
        HStack {
            RemoteModeSwitch(session: session)
            Spacer()
            Text(L("sftp> put · get · ls · cd · help")).font(t.mono(10.5)).foregroundStyle(SwiftUI.Color(t.dim))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(SwiftUI.Color(t.bar))
        .overlay(alignment: .bottom) { NeonLine(color: t.panel) }
    }
}

/// El explorador gráfico de una pestaña SFTP/FTP.
struct RemoteBrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let session: TerminalSession
    @Bindable var browser: RemoteBrowser
    @Stored private var editingPath: String?
    @Stored private var showTransfers = true
    @Stored private var dropping = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            NeonLine(color: t.panel)
            switch browser.state {
            case .connected:
                pathBar
                header
                list
            case .connecting, .idle:
                center(icon: "antenna.radiowaves.left.and.right", text: L("Conectando a \(browser.label)…"), busy: true)
            case .needsPassword(let why):
                FTPPasswordPrompt(browser: browser, reason: why)
            case .failed(let why):
                failed(why)
            }
            footer
            if showTransfers, !model.transfers.jobs.isEmpty { TransferPanel() }
        }
        .background(SwiftUI.Color(t.layer))
        .overlay { if t.neon { Scanlines().opacity(0.5) } }
        .onAppear { browser.connect() }
    }

    // MARK: barra de herramientas

    private var toolbar: some View {
        let connected = browser.state == .connected
        let sel = browser.selectedEntries
        return HStack(spacing: 6) {
            RemoteModeSwitch(session: session)
            NeonLine(vertical: true, color: t.panel).frame(height: 20).padding(.horizontal, 2)
            IconButton(icon: "chevron.left") { browser.goBack() }.help(L("Atrás")).disabled(browser.back.isEmpty)
            IconButton(icon: "chevron.right") { browser.goForward() }.help(L("Adelante")).disabled(browser.forward.isEmpty)
            IconButton(icon: "arrow.up") { browser.goUp() }.help(L("Carpeta de arriba")).disabled(!connected || browser.path == "/")
            IconButton(icon: "house.fill") { browser.open(browser.home) }.help(L("Tu carpeta de inicio")).disabled(!connected)
            IconButton(icon: "arrow.clockwise") { connected ? browser.refresh() : browser.reconnect() }
                .help(connected ? L("Actualizar") : L("Reconectar"))
            NeonLine(vertical: true, color: t.panel).frame(height: 20).padding(.horizontal, 2)
            IconButton(icon: "folder.badge.plus") { newFolder() }.help(L("Nueva carpeta")).disabled(!connected)
            IconButton(icon: "square.and.arrow.up") { upload() }.help(L("Subir archivos o carpetas del Mac")).disabled(!connected)
            IconButton(icon: "square.and.arrow.down") { download(sel) }.help(L("Descargar al Mac")).disabled(sel.isEmpty)
            SendToMenu(browser: browser, entries: sel)
            IconButton(icon: "pencil") { if let e = sel.first { rename(e) } }.help(L("Renombrar")).disabled(sel.count != 1)
            IconButton(icon: "trash", tint: t.bad) { delete(sel) }.help(L("Borrar")).disabled(sel.isEmpty)
            Spacer(minLength: 8)
            SearchField(text: $browser.filter, prompt: L("Filtrar")).frame(maxWidth: 200)
            IconButton(icon: browser.showHidden ? "eye.fill" : "eye.slash", active: browser.showHidden) { browser.showHidden.toggle() }
                .help(L("Mostrar los archivos ocultos (.algo)"))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(SwiftUI.Color(t.bar))
    }

    // MARK: ruta

    private var pathBar: some View {
        HStack(spacing: 2) {
            Image(systemName: browser.isFTP ? "externaldrive.connected.to.line.below" : "lock.fill")
                .font(.system(size: 10)).foregroundStyle(SwiftUI.Color(browser.isFTP ? t.warning : t.good))
                .help(browser.isFTP ? L("FTP: sin cifrar") : L("SFTP: cifrado (ssh)"))
                .padding(.trailing, 4)
            if let p = editingPath {
                TextField("", text: Binding(get: { p }, set: { editingPath = $0 }))
                    .textFieldStyle(.plain).font(t.mono(12)).foregroundStyle(SwiftUI.Color(t.text))
                    .onSubmit {
                        let dest = p.trimmingCharacters(in: .whitespaces)
                        editingPath = nil
                        if dest.hasPrefix("/") { browser.open(dest) }
                    }
                    .onExitCommand { editingPath = nil }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(Array(RemotePath.breadcrumbs(browser.path).enumerated()), id: \.offset) { i, c in
                            if i > 1 { Text("/").font(t.mono(12)).foregroundStyle(SwiftUI.Color(t.dim)) }
                            Crumb(title: c.name, last: c.path == browser.path) { browser.open(c.path) }
                        }
                    }
                }
                Spacer(minLength: 4)
                IconButton(icon: "character.cursor.ibeam") { editingPath = browser.path }.help(L("Escribir la ruta"))
                IconButton(icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(browser.path, forType: .string)
                }
                .help(L("Copiar la ruta"))
            }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(SwiftUI.Color(t.panel).opacity(0.35))
    }

    // MARK: lista

    private var header: some View {
        HStack(spacing: 0) {
            column(L("Nombre"), .name).frame(maxWidth: .infinity, alignment: .leading)
            column(L("Tamaño"), .size, trailing: true).frame(width: 90, alignment: .trailing)
            column(L("Permisos"), .permissions).frame(width: 104, alignment: .leading).padding(.leading, 14)
            Text(L("Propietario").uppercased()).frame(width: 130, alignment: .leading)
            column(L("Modificado"), .modified).frame(width: 136, alignment: .leading)
        }
        .font(t.ui(10, .bold)).tracking(t.tracking / 2)
        .foregroundStyle(SwiftUI.Color(t.accent2))
        .padding(.horizontal, 10).frame(height: 24)
        .background(SwiftUI.Color(t.bar).opacity(0.8))
        .overlay(alignment: .bottom) { NeonLine(color: t.accent2) }
    }

    private func column(_ title: String, _ k: RemoteBrowser.SortKey, trailing: Bool = false) -> some View {
        Button { browser.sort(by: k) } label: {
            HStack(spacing: 3) {
                Text(title.uppercased())
                if browser.sortKey == k { Image(systemName: browser.ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .black)) }
            }
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        let rows = browser.rows
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.entry.path) { i, r in
                    EntryRow(browser: browser, entry: r.entry, depth: r.depth, odd: i % 2 == 1,
                             open: { activate(r.entry) })
                        .themedContextMenu { rowMenu(r.entry) }
                }
                if rows.isEmpty {
                    Text(browser.filter.isEmpty ? L("Carpeta vacía") : L("Nada coincide con «\(browser.filter)»"))
                        .font(t.ui(12)).foregroundStyle(SwiftUI.Color(t.dim)).padding(30)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { browser.selection = [] }
        .themedContextMenu { folderMenu }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: t.corner ?? 6).strokeBorder(SwiftUI.Color(t.accent), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(6)
                    .overlay(Text(L("Suelta para subir a \(browser.path)")).font(t.ui(13, .bold)).foregroundStyle(SwiftUI.Color(t.accent)))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropping) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for p in providers {
                    if let u = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                       let url = URL(dataRepresentation: u, relativeTo: nil), url.isFileURL { urls.append(url) }
                }
                if !urls.isEmpty { uploadURLs(urls) }
            }
            return true
        }
    }

    @ViewBuilder private func rowMenu(_ e: RemoteEntry) -> some View {
        let targets = browser.selection.contains(e.path) ? browser.selectedEntries : [e]
        if e.isDirectory {
            Button { browser.open(e.path) } label: { Label(L("Abrir"), systemImage: "folder") }
            Button { browser.toggle(e) } label: {
                Label(browser.expanded.contains(e.path) ? L("Plegar") : L("Desplegar aquí"), systemImage: "list.bullet.indent")
            }
        }
        Button { download(targets) } label: { Label(L("Descargar…"), systemImage: "square.and.arrow.down") }
        SendToItems(browser: browser, entries: targets)
        MenuDivider()
        Button { rename(e) } label: { Label(L("Renombrar…"), systemImage: "pencil") }.disabled(targets.count != 1)
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(targets.map(\.path).joined(separator: "\n"), forType: .string)
        } label: { Label(L("Copiar la ruta"), systemImage: "doc.on.doc") }
        MenuDivider()
        Button(role: .destructive) { delete(targets) } label: { Label(L("Borrar…"), systemImage: "trash") }
    }

    @ViewBuilder private var folderMenu: some View {
        Button { newFolder() } label: { Label(L("Nueva carpeta…"), systemImage: "folder.badge.plus") }
        Button { upload() } label: { Label(L("Subir aquí…"), systemImage: "square.and.arrow.up") }
        Button { browser.refresh() } label: { Label(L("Actualizar"), systemImage: "arrow.clockwise") }
        if let url = browser.route.ftpURL {
            MenuDivider()
            Button { NSWorkspace.shared.open(url) } label: { Label(L("Abrir también en el Finder"), systemImage: "macwindow") }
        }
    }

    private func activate(_ e: RemoteEntry) {
        if e.isDirectory { browser.open(e.path) } else { download([e], ask: false) }
    }

    // MARK: pie

    private var footer: some View {
        let rows = browser.rows
        let files = rows.filter { !$0.entry.isDirectory }
        let bytes = files.compactMap(\.entry.size).reduce(0, +)
        return HStack(spacing: 12) {
            if let m = browser.message {
                Text(m).foregroundStyle(SwiftUI.Color(t.bad)).lineLimit(1).truncationMode(.middle)
                    .onTapGesture { browser.message = nil }
            } else if browser.state == .connected {
                Text(L("\(rows.count) elementos · \(Self.bytes(bytes))")).foregroundStyle(SwiftUI.Color(t.dim))
                if !browser.selection.isEmpty {
                    Text(L("\(browser.selection.count) elegidos")).foregroundStyle(SwiftUI.Color(t.accent))
                }
            }
            Spacer()
            if !model.transfers.jobs.isEmpty {
                Button { showTransfers.toggle() } label: {
                    Tag(text: L("⇅ TRANSFERENCIAS \(model.transfers.active)/\(model.transfers.jobs.count)"),
                        color: model.transfers.active > 0 ? t.warning : t.accent2)
                }
                .buttonStyle(.plain)
            }
            Text(browser.label).foregroundStyle(SwiftUI.Color(t.dim))
        }
        .font(t.ui(10.5, .medium))
        .padding(.horizontal, 10).frame(height: 24)
        .background(SwiftUI.Color(t.bar))
        .overlay(alignment: .top) { NeonLine(color: t.panel) }
    }

    private func center(icon: String, text: String, busy: Bool = false) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(SwiftUI.Color(t.accent2))
                .shadow(color: SwiftUI.Color(t.accent2).opacity(0.7), radius: t.glow(8))
            if busy { ProgressView().controlSize(.small).tint(SwiftUI.Color(t.accent)) }
            Text(text).font(t.ui(13)).foregroundStyle(SwiftUI.Color(t.text)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ why: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.horizontal.circle").font(.system(size: 34)).foregroundStyle(SwiftUI.Color(t.bad))
                .shadow(color: SwiftUI.Color(t.bad).opacity(0.7), radius: t.glow(8))
            Text(L("No se ha podido conectar")).font(t.ui(14, .bold)).foregroundStyle(SwiftUI.Color(t.text))
            Text(why).font(t.mono(11.5)).foregroundStyle(SwiftUI.Color(t.dim)).multilineTextAlignment(.center)
                .textSelection(.enabled).frame(maxWidth: 560)
            HStack {
                NeonButton(title: L("Reintentar"), icon: "arrow.clockwise", active: true) { browser.reconnect() }
                if session.route.transport == .sftp {
                    NeonButton(title: L("Abrir la consola"), icon: "terminal.fill", tint: t.accent2) { model.setConsole(true, in: session) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    // MARK: acciones

    private func newFolder() {
        let r = ThemedAlert.run(L("Nueva carpeta en \(browser.path)"), buttons: [L("Crear"), L("Cancelar")],
                                field: (L("Nombre"), "", false))
        if r.button == 0 { browser.makeFolder(r.text.trimmingCharacters(in: .whitespaces)) }
    }

    private func rename(_ e: RemoteEntry) {
        let r = ThemedAlert.run(L("Renombrar «\(e.name)»"), buttons: [L("Renombrar"), L("Cancelar")], field: (L("Nombre"), e.name, false))
        if r.button == 0 { browser.rename(e, to: r.text.trimmingCharacters(in: .whitespaces)) }
    }

    private func delete(_ list: [RemoteEntry]) {
        guard !list.isEmpty else { return }
        let dirs = list.contains { $0.kind == .directory }
        let title = list.count == 1 ? L("¿Borrar «\(list[0].name)»?") : L("¿Borrar \(list.count) elementos?")
        guard ThemedAlert.confirm(title, message: dirs ? L("Las carpetas se borran con todo lo que llevan dentro. No se puede deshacer.")
                                                      : L("Se borra del servidor. No se puede deshacer."),
                                  ok: L("Borrar"), destructive: true) else { return }
        browser.delete(list)
    }

    private func download(_ list: [RemoteEntry], ask: Bool = true) {
        guard let fs = browser.fs, !list.isEmpty else { return }
        var folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? AppPaths.home
        if ask {
            let p = NSOpenPanel()
            p.canChooseDirectories = true
            p.canChooseFiles = false
            p.canCreateDirectories = true
            p.directoryURL = folder
            p.prompt = L("Descargar aquí")
            p.message = L("¿Dónde guardo \(list.count == 1 ? "«\(list[0].name)»" : L("\(list.count) elementos"))?")
            guard p.runModal() == .OK, let u = p.url else { return }
            folder = u
        }
        model.transfers.download(list, from: fs, to: folder)
    }

    private func upload() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.allowsMultipleSelection = true
        p.prompt = L("Subir")
        p.message = L("Se suben a \(browser.path)")
        guard p.runModal() == .OK else { return }
        uploadURLs(p.urls)
    }

    private func uploadURLs(_ urls: [URL]) {
        guard let fs = browser.fs, browser.state == .connected else { return }
        let names = Set(browser.entries.map(\.name))
        let clash = urls.map(\.lastPathComponent).filter(names.contains)
        if !clash.isEmpty, !ThemedAlert.confirm(L("Ya existe en \(browser.path): \(clash.prefix(3).joined(separator: ", "))"),
                                                message: L("Se sustituirá lo que haya en el servidor."), ok: L("Sustituir"), destructive: true) {
            return
        }
        model.transfers.upload(urls, to: fs, dir: browser.path) { [weak browser] in browser?.refresh() }
    }
}

/// Un trozo de la ruta (clic: ir ahí).
private struct Crumb: View {
    @Environment(\.theme) private var t
    let title: String
    let last: Bool
    let action: () -> Void
    @Stored private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title).font(t.mono(12, last ? .bold : .regular))
                .foregroundStyle(SwiftUI.Color(last ? t.accent : (hover ? t.accent : t.text)))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(SwiftUI.Color(t.accent).opacity(hover ? 0.12 : 0)))
                .shadow(color: SwiftUI.Color(t.accent).opacity(last ? 0.6 : 0), radius: t.glow(4))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Una fila: ▸ (carpetas), icono, nombre, tamaño, permisos, dueño y fecha. Clic elige (⌘ suma, ⇧ rango); doble clic
/// entra en la carpeta o descarga el archivo.
private struct EntryRow: View {
    @Environment(\.theme) private var t
    let browser: RemoteBrowser
    let entry: RemoteEntry
    let depth: Int
    let odd: Bool
    let open: () -> Void
    @Stored private var hover = false

    var body: some View {
        let selected = browser.selection.contains(entry.path)
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Group {
                    if entry.isDirectory {
                        Image(systemName: browser.loading.contains(entry.path) ? "hourglass"
                              : (browser.expanded.contains(entry.path) ? "chevron.down" : "chevron.right"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SwiftUI.Color(t.dim))
                            .contentShape(Rectangle())
                            .onTapGesture { browser.toggle(entry) }
                    } else {
                        SwiftUI.Color.clear
                    }
                }
                .frame(width: 14)
                Image(systemName: icon).font(.system(size: 12))
                    .foregroundStyle(SwiftUI.Color(iconColor))
                    .shadow(color: SwiftUI.Color(iconColor).opacity(selected ? 0.8 : 0), radius: t.glow(4))
                    .frame(width: 18)
                Text(entry.name).font(t.mono(12, entry.isDirectory ? .semibold : .regular))
                    .foregroundStyle(SwiftUI.Color(selected ? t.accent : (entry.isDirectory ? t.accent2 : t.text)))
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.leading, CGFloat(depth) * 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.isDirectory ? "—" : entry.size.map(RemoteBrowserView.bytes) ?? "?")
                .frame(width: 90, alignment: .trailing)
            Text(entry.permissionString).frame(width: 104, alignment: .leading).padding(.leading, 14)
                .foregroundStyle(SwiftUI.Color(t.dim))
            Text([entry.owner, entry.group].compactMap { $0 }.joined(separator: ":")).lineLimit(1)
                .frame(width: 120, alignment: .leading).padding(.trailing, 10).foregroundStyle(SwiftUI.Color(t.dim))
            Text(entry.modified.map { Self.date.string(from: $0) } ?? "").frame(width: 136, alignment: .leading)
                .foregroundStyle(SwiftUI.Color(t.dim))
        }
        .font(t.mono(11.5))
        .foregroundStyle(SwiftUI.Color(t.text))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(background(selected))
        .overlay(alignment: .leading) {
            Rectangle().fill(SwiftUI.Color(t.accent)).frame(width: 2).opacity(selected ? 1 : 0)
                .shadow(color: SwiftUI.Color(t.accent), radius: t.glow(4))
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .gesture(TapGesture(count: 2).onEnded { open() })
        .simultaneousGesture(TapGesture().onEnded { select() })
        .help(entry.path)
    }

    private func background(_ selected: Bool) -> SwiftUI.Color {
        if selected { return SwiftUI.Color(t.accent).opacity(0.16) }
        if hover { return SwiftUI.Color(t.accent).opacity(0.07) }
        return odd ? SwiftUI.Color(t.panel).opacity(0.18) : .clear
    }

    private var icon: String {
        switch entry.kind {
        case .directory: return "folder.fill"
        case .link: return entry.linkToDirectory ? "folder.badge.questionmark" : "link"
        case .other: return "questionmark.square.dashed"
        case .file:
            let ext = (entry.name as NSString).pathExtension.lowercased()
            if ["cfg", "conf", "txt", "log", "ini", "yaml", "yml", "json", "xml"].contains(ext) { return "doc.text" }
            if ["bin", "img", "iso", "pkg", "tar", "gz", "tgz", "zip", "bz2", "xz"].contains(ext) { return "shippingbox.fill" }
            if ["sh", "py", "pl", "rb", "js"].contains(ext) { return "chevron.left.forwardslash.chevron.right" }
            return "doc"
        }
    }

    private var iconColor: RGB {
        switch entry.kind {
        case .directory: t.accent2
        case .link: t.special
        case .other: t.dim
        case .file: t.good
        }
    }

    private func select() {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            if browser.selection.contains(entry.path) { browser.selection.remove(entry.path) } else { browser.selection.insert(entry.path) }
        } else if mods.contains(.shift), let anchor = browser.selection.first {
            let rows = browser.rows.map(\.entry.path)
            if let a = rows.firstIndex(of: anchor), let b = rows.firstIndex(of: entry.path) {
                browser.selection = Set(rows[min(a, b)...max(a, b)])
            }
        } else {
            browser.selection = [entry.path]
        }
    }

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

/// «Enviar a…»: los otros exploradores abiertos (SFTP o FTP), a la carpeta en la que estén. Se copia de servidor a
/// servidor en memoria, sin pasar por el disco del Mac.
private struct SendToMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let browser: RemoteBrowser
    let entries: [RemoteEntry]

    var body: some View {
        ThemedMenu {
            SendToItems(browser: browser, entries: entries)
        } label: {
            NeonLabel(title: L("Enviar a…"), icon: "arrow.left.arrow.right", tint: t.accent2)
        }
        .disabled(entries.isEmpty)
        .opacity(entries.isEmpty ? 0.5 : 1)
        .help(L("Copiar directamente a otro servidor abierto (en memoria, sin pasar por el disco del Mac)"))
    }
}

private struct SendToItems: View {
    @Environment(AppModel.self) private var model
    let browser: RemoteBrowser
    let entries: [RemoteEntry]

    var body: some View {
        let others = model.tabs.compactMap { s in s.browser.map { (s, $0) } }
            .filter { $0.1 !== browser && $0.1.state == .connected }
        MenuHeader(title: L("Enviar a otro servidor"))
        if others.isEmpty {
            Text(L("Abre otra pestaña SFTP o FTP y conéctala")).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.bottom, 4)
        }
        ForEach(others, id: \.0.id) { s, b in
            Button { model.send(entries, from: browser, to: b) } label: {
                Label("\(s.title) → \(b.path)", systemImage: b.isFTP ? "externaldrive.connected.to.line.below" : "server.rack")
            }
        }
    }
}

/// FTP: la contraseña (no había una guardada que valiera o la contraseña automática está apagada).
private struct FTPPasswordPrompt: View {
    @Environment(\.theme) private var t
    let browser: RemoteBrowser
    let reason: String?
    @Stored private var password = ""
    @Stored private var save = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill").font(.system(size: 20)).foregroundStyle(SwiftUI.Color(t.warning))
                    .shadow(color: SwiftUI.Color(t.warning).opacity(0.7), radius: t.glow(6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Contraseña de \(browser.user)@\(browser.route.target.host)")).font(t.ui(14, .bold))
                        .foregroundStyle(SwiftUI.Color(t.text))
                    Text(L("FTP no va cifrado: la contraseña viaja tal cual por la red.")).font(t.ui(11))
                        .foregroundStyle(SwiftUI.Color(t.warning))
                }
            }
            if let reason { Text(reason).font(t.ui(11.5)).foregroundStyle(SwiftUI.Color(t.bad)) }
            SecureField(L("Contraseña"), text: $password)
                .textFieldStyle(.plain).font(t.mono(13)).foregroundStyle(SwiftUI.Color(t.text))
                .padding(.horizontal, 8).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: t.corner ?? 5).fill(SwiftUI.Color(t.background.opaque)))
                .overlay(RoundedRectangle(cornerRadius: t.corner ?? 5).strokeBorder(SwiftUI.Color(t.accent).opacity(focused ? 0.8 : 0.3)))
                .focused($focused)
                .onSubmit(go)
            Toggle(L("Guardarla en el Llavero como «\(browser.saveTarget.account)»"), isOn: $save)
                .toggleStyle(.themedCheckbox).font(t.ui(11.5)).foregroundStyle(SwiftUI.Color(t.text))
            HStack {
                Spacer()
                NeonButton(title: L("Conectar"), icon: "bolt.horizontal.fill", active: true, action: go)
                    .disabled(password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(RoundedRectangle(cornerRadius: t.corner ?? 8).fill(SwiftUI.Color(t.bar.opaque)))
        .overlay(RoundedRectangle(cornerRadius: t.corner ?? 8).strokeBorder(SwiftUI.Color(t.accent).opacity(0.4)))
        .shadow(color: SwiftUI.Color(t.accent).opacity(0.3), radius: t.glow(12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focused = true }
    }

    private func go() {
        guard !password.isEmpty else { return }
        let pw = password
        password = ""
        browser.connectFTP(password: pw, save: save ? browser.saveTarget : nil)
    }
}

/// Las copias en curso y las últimas (de todas las pestañas).
struct TransferPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("TRANSFERENCIAS")).font(t.ui(10, .heavy)).tracking(t.tracking).foregroundStyle(SwiftUI.Color(t.accent))
                Text(L("servidor ↔ servidor en memoria · sin pasar por el disco del Mac")).font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim))
                Spacer()
                Button(L("Quitar las acabadas")) { model.transfers.clearFinished() }
                    .buttonStyle(.plain).font(t.ui(10.5, .semibold)).foregroundStyle(SwiftUI.Color(t.accent2))
            }
            .padding(.horizontal, 10).frame(height: 24)
            ScrollView {
                VStack(spacing: 2) { ForEach(model.transfers.jobs) { TransferRow(job: $0) } }
                    .padding(.horizontal, 8).padding(.bottom, 6)
            }
            .frame(maxHeight: 130)
        }
        .background(SwiftUI.Color(t.bar))
        .overlay(alignment: .top) { NeonLine(color: t.accent2) }
    }
}

private struct TransferRow: View {
    @Environment(\.theme) private var t
    let job: TransferJob

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(SwiftUI.Color(color)).frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(job.title).font(t.mono(11.5, .semibold)).foregroundStyle(SwiftUI.Color(t.text)).lineLimit(1)
                    Text("\(job.from) → \(job.to)").font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim))
                        .lineLimit(1).truncationMode(.middle)
                }
                NeonProgress(fraction: job.fraction ?? (job.finished ? 1 : 0), color: color)
            }
            Text(detail).font(t.mono(10.5)).foregroundStyle(SwiftUI.Color(color)).frame(width: 170, alignment: .trailing)
                .lineLimit(1).truncationMode(.middle)
            if !job.finished {
                IconButton(icon: "xmark", tint: t.bad) { job.cancel() }.help(L("Cancelar"))
            }
        }
        .padding(.vertical, 3)
        .help(failure ?? "")
    }

    private var failure: String? { if case .failed(let m) = job.state { m } else { nil } }

    private var detail: String {
        let done = RemoteBrowserView.bytes(job.done)
        switch job.state {
        case .queued: return L("en cola")
        case .running:
            let speed = job.speed > 0 ? " · " + RemoteBrowserView.bytes(Int64(job.speed)) + "/s" : ""
            return done + (job.total.map { " / " + RemoteBrowserView.bytes($0) } ?? "") + speed
        case .done: return L("✓ \(done) · \(job.files) archivos")
        case .failed(let m): return "✗ " + m
        case .cancelled: return L("cancelada")
        }
    }

    private var icon: String {
        switch job.state {
        case .queued, .running: "arrow.left.arrow.right"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "stop.circle"
        }
    }

    private var color: RGB {
        switch job.state {
        case .queued, .running: t.accent
        case .done: t.good
        case .failed: t.bad
        case .cancelled: t.dim
        }
    }
}

/// Barra de progreso con la temática (brillo de neón en los temas de NetDeck).
struct NeonProgress: View {
    @Environment(\.theme) private var t
    let fraction: Double
    let color: RGB

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(SwiftUI.Color(t.panel).opacity(0.7))
                RoundedRectangle(cornerRadius: 2).fill(SwiftUI.Color(color))
                    .frame(width: max(2, g.size.width * min(1, max(0, fraction))))
                    .shadow(color: SwiftUI.Color(color).opacity(0.8), radius: t.glow(4))
            }
        }
        .frame(height: 4)
        .animation(.linear(duration: 0.2), value: fraction)
    }
}

/// Líneas de barrido tipo CRT (sólo en los temas de neón).
struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            var y = 0.0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.12)))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}
