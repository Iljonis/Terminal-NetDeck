import Foundation
import NetDeckCore
import WinUI
import struct UWP.Color

/// Explorador SFTP en el area principal: carpeta actual, subir un nivel, actualizar, entrar en carpetas y descargar
/// (doble clic) y subir un archivo por su ruta local. Usa `SFTPFileSystem` y `Transfer` de NetDeckCore.
/// `@unchecked Sendable`: los controles solo se tocan en el hilo de WinUI (todo lo que llega de las tareas pasa por
/// `deliver` y `enqueue`); el resto del estado se cambia desde ese mismo hilo.
final class ExploradorSFTP: @unchecked Sendable {
    let view = ScrollViewer()
    var onClose: (() -> Void)?
    /// Ejecuta una accion en el hilo de WinUI (lo pone la ventana).
    var enqueue: (@escaping () -> Void) -> Void = { $0() }

    private let title = TextBlock()
    private let pathText = TextBlock()
    private let list = StackPanel()
    private let statusText = TextBlock()
    private let uploadBox = TextBox()
    // Barra de accion (renombrar, carpeta nueva y borrar): sin ContentDialog, como el resto de la interfaz.
    private let actionBar = StackPanel()
    private let actionCaption = TextBlock()
    private let actionBox = TextBox()
    private let actionConfirm = Button()
    private var pendingAction: PendingAction?

    private enum PendingAction {
        case rename(RemoteEntry)
        case newFolder
        case delete(RemoteEntry)
    }
    private var fs: SFTPFileSystem?
    private var current = "/"
    private var generation = 0
    private var task: Task<Void, Never>?

    init() {
        let root = StackPanel()
        root.orientation = .vertical
        root.spacing = 8
        root.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        title.fontSize = 20
        pathText.opacity = 0.8
        pathText.isTextSelectionEnabled = true
        AutomationProperties.setAutomationId(pathText, "SFTP_Ruta")
        AutomationProperties.setAutomationId(statusText, "SFTP_Estado")
        statusText.textWrapping = .wrap

        let up = Button()
        up.content = "\u{2B06} " + L("Arriba")
        up.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.navigate(RemotePath.parent(self.current))
        }
        let refresh = Button()
        refresh.content = L("Actualizar")
        refresh.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.navigate(self.current)
        }
        let close = Button()
        close.content = L("Cerrar")
        close.click.addHandler { [weak self] _, _ in
            self?.disconnect()
            self?.onClose?()
        }
        let newFolder = Button()
        newFolder.content = "+ " + L("Carpeta")
        newFolder.click.addHandler { [weak self] _, _ in self?.beginNewFolder() }
        AutomationProperties.setAutomationId(newFolder, "SFTP_NuevaCarpeta")
        AutomationProperties.setAutomationId(up, "SFTP_Arriba")
        AutomationProperties.setAutomationId(refresh, "SFTP_Actualizar")
        AutomationProperties.setAutomationId(close, "SFTP_Cerrar")
        let header = StackPanel()
        header.orientation = .horizontal
        header.spacing = 8
        header.children.append(up)
        header.children.append(refresh)
        header.children.append(newFolder)
        header.children.append(close)

        actionBar.orientation = .horizontal
        actionBar.spacing = 8
        actionBar.visibility = .collapsed
        actionBox.minWidth = 260
        actionBox.keyDown.addHandler { [weak self] _, args in
            guard let args, args.key.rawValue == 13 else { return }
            args.handled = true
            self?.confirmAction()
        }
        actionConfirm.click.addHandler { [weak self] _, _ in self?.confirmAction() }
        let actionCancel = Button()
        actionCancel.content = L("Cancelar")
        actionCancel.click.addHandler { [weak self] _, _ in self?.cancelAction() }
        AutomationProperties.setAutomationId(actionBox, "SFTP_Accion_Texto")
        AutomationProperties.setAutomationId(actionConfirm, "SFTP_Accion_Confirmar")
        AutomationProperties.setAutomationId(actionCancel, "SFTP_Accion_Cancelar")
        actionCaption.textWrapping = .wrap
        actionCaption.maxWidth = 360
        actionCaption.verticalAlignment = .center
        for item in [actionCaption as FrameworkElement, actionBox, actionConfirm, actionCancel] { actionBar.children.append(item) }

        let upload = StackPanel()
        upload.orientation = .horizontal
        upload.spacing = 8
        uploadBox.placeholderText = L("Ruta del archivo local")
        uploadBox.minWidth = 360
        let uploadButton = Button()
        uploadButton.content = L("Subir archivo")
        uploadButton.click.addHandler { [weak self] _, _ in self?.upload() }
        AutomationProperties.setAutomationId(uploadBox, "SFTP_RutaLocal")
        AutomationProperties.setAutomationId(uploadButton, "SFTP_Subir")
        upload.children.append(uploadBox)
        upload.children.append(uploadButton)

        let hint = TextBlock()
        hint.text = L("Doble clic: abrir carpeta o descargar archivo")
        hint.fontSize = 11
        hint.opacity = 0.6

        for item in [title as FrameworkElement, header, actionBar, pathText, hint, list, upload, statusText] {
            root.children.append(item)
        }
        view.content = root
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .auto
        view.visibility = .collapsed
    }

    // MARK: - conexion

    func connect(label: String, executable: String, arguments: [String], environment: [String: String]) {
        disconnect()
        generation += 1
        let gen = generation
        title.text = L("Explorador SFTP") + " \u{00B7} " + label
        pathText.text = ""
        list.children.clear()
        setStatus(L("Conectando\u{2026}"))
        task = Task { [weak self] in
            do {
                let fs = try await SFTPFileSystem.connect(label: label, executable: executable, arguments: arguments,
                                                          environment: environment)
                let home = try await fs.home()
                let entries = try await fs.list(home)
                self?.deliver(gen, orElse: { Task { await fs.close() } }) { me in
                    me.fs = fs
                    me.show(path: home, entries: entries)
                }
            } catch {
                self?.deliver(gen) { $0.setStatus(L("No se puede conectar: \(error.localizedDescription)")) }
            }
        }
    }

    func disconnect() {
        generation += 1
        task?.cancel()
        task = nil
        if let fs { Task { await fs.close() } }
        fs = nil
    }

    /// Lleva `body` al hilo de WinUI si esta conexion sigue siendo la vigente; si no, `orElse`.
    private func deliver(_ gen: Int, orElse: @escaping () -> Void = {}, _ body: @escaping (ExploradorSFTP) -> Void) {
        enqueue { [weak self] in
            guard let self, self.generation == gen else { orElse(); return }
            body(self)
        }
    }

    // MARK: - listado

    private func navigate(_ path: String) {
        guard let fs else { return }
        let gen = generation
        setStatus(L("Leyendo\u{2026}"))
        task = Task { [weak self] in
            do {
                let entries = try await fs.list(path)
                self?.deliver(gen) { $0.show(path: path, entries: entries) }
            } catch {
                self?.deliver(gen) { $0.setStatus(L("No se puede leer la carpeta: \(error.localizedDescription)")) }
            }
        }
    }

    private func show(path: String, entries: [RemoteEntry]) {
        current = path
        pathText.text = path
        list.children.clear()
        let sorted = RemoteEntry.sorted(entries)
        for entry in sorted { list.children.append(row(for: entry)) }
        setStatus(sorted.isEmpty ? L("Carpeta vac\u{00ED}a") : L("\(sorted.count) elementos"))
    }

    private func row(for entry: RemoteEntry) -> FrameworkElement {
        let grid = Grid()
        for (width, kind) in [(1.0, GridUnitType.star), (90.0, .pixel), (150.0, .pixel), (1.0, .auto), (1.0, .auto)] {
            let column = ColumnDefinition()
            column.width = GridLength(value: width, gridUnitType: kind)
            grid.columnDefinitions.append(column)
        }
        let name = TextBlock()
        name.text = (entry.isDirectory ? "\u{1F4C1} " : "\u{1F4C4} ") + entry.name
        let size = TextBlock()
        size.text = entry.isDirectory ? "" : entry.size.map(Self.human) ?? ""
        size.opacity = 0.7
        let date = TextBlock()
        date.text = entry.modified.map { Self.dateFormat.string(from: $0) } ?? ""
        date.opacity = 0.7
        for (index, cell) in [name, size, date].enumerated() {
            Grid.setColumn(cell, Int32(index))
            grid.children.append(cell)
        }
        let rename = Button()
        rename.content = "\u{270E}"
        rename.margin = Thickness(left: 8, top: 0, right: 0, bottom: 0)
        rename.click.addHandler { [weak self] _, _ in self?.beginRename(entry) }
        let remove = Button()
        remove.content = "\u{1F5D1}"
        remove.margin = Thickness(left: 4, top: 0, right: 0, bottom: 0)
        remove.click.addHandler { [weak self] _, _ in self?.beginDelete(entry) }
        AutomationProperties.setAutomationId(rename, "SFTP_Renombrar_\(entry.name)")
        AutomationProperties.setAutomationId(remove, "SFTP_Borrar_\(entry.name)")
        Grid.setColumn(rename, Int32(3))
        Grid.setColumn(remove, Int32(4))
        grid.children.append(rename)
        grid.children.append(remove)
        let border = Border()
        border.child = grid
        border.padding = Thickness(left: 6, top: 4, right: 6, bottom: 4)
        border.background = SolidColorBrush(Color(a: 0, r: 0, g: 0, b: 0))   // transparente pero con clic
        AutomationProperties.setAutomationId(border, "SFTP_Fila_\(entry.name)")
        border.doubleTapped.addHandler { [weak self] _, _ in
            guard let self else { return }
            if entry.isDirectory { self.navigate(entry.path) } else { self.download(entry) }
        }
        return border
    }

    // MARK: - renombrar, carpeta nueva y borrar

    private func beginRename(_ entry: RemoteEntry) {
        pendingAction = .rename(entry)
        actionCaption.text = L("Nuevo nombre de \u{00AB}\(entry.name)\u{00BB}")
        actionBox.text = entry.name
        actionBox.visibility = .visible
        actionConfirm.content = L("Renombrar")
        showActionBar()
    }

    private func beginNewFolder() {
        pendingAction = .newFolder
        actionCaption.text = L("Nombre de la carpeta nueva")
        actionBox.text = ""
        actionBox.visibility = .visible
        actionConfirm.content = L("Crear")
        showActionBar()
    }

    private func beginDelete(_ entry: RemoteEntry) {
        pendingAction = .delete(entry)
        actionCaption.text = L("\u{00BF}Borrar \u{00AB}\(entry.name)\u{00BB}?")
            + (entry.kind == .directory ? " " + L("S\u{00F3}lo se borran carpetas vac\u{00ED}as.") : "")
        actionBox.visibility = .collapsed
        actionConfirm.content = L("Borrar")
        showActionBar()
    }

    private func showActionBar() {
        setStatus("")
        actionBar.visibility = .visible
        if actionBox.visibility == .visible { _ = try? actionBox.focus(.programmatic) }
    }

    private func cancelAction() {
        pendingAction = nil
        actionBar.visibility = .collapsed
    }

    /// Hace la operacion pendiente y recarga la carpeta; si falla, el motivo va a la barra de estado.
    private func confirmAction() {
        guard let fs, let action = pendingAction else { return }
        let typed = actionBox.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case .rename(let entry):
            guard RemotePath.isValidName(typed), typed != entry.name else {
                setStatus(typed == entry.name ? L("Es el mismo nombre") : L("Nombre no v\u{00E1}lido: \u{00AB}\(typed)\u{00BB}"))
                return
            }
        case .newFolder:
            guard RemotePath.isValidName(typed) else {
                setStatus(L("Nombre no v\u{00E1}lido: \u{00AB}\(typed)\u{00BB}"))
                return
            }
        case .delete:
            break
        }
        cancelAction()
        let gen = generation
        let folder = current
        let target = RemotePath.join(folder, typed)
        setStatus(L("Trabajando\u{2026}"))
        task = Task { [weak self] in
            var failed = ""
            var done = ""
            do {
                switch action {
                case .rename(let entry):
                    failed = L("No se puede renombrar \u{00AB}\(entry.name)\u{00BB}")
                    if try await fs.lookup(target) != nil { throw RemoteError(L("Ya existe \u{00AB}\(typed)\u{00BB} en esta carpeta")) }
                    try await fs.rename(entry.path, to: target)
                    done = L("\u{00AB}\(entry.name)\u{00BB} renombrado a \u{00AB}\(typed)\u{00BB}")
                case .newFolder:
                    failed = L("No se puede crear la carpeta \u{00AB}\(typed)\u{00BB}")
                    if try await fs.lookup(target) != nil { throw RemoteError(L("Ya existe \u{00AB}\(typed)\u{00BB} en esta carpeta")) }
                    try await fs.makeDirectory(target)
                    done = L("Carpeta \u{00AB}\(typed)\u{00BB} creada")
                case .delete(let entry):
                    failed = L("No se puede borrar \u{00AB}\(entry.name)\u{00BB}")
                    // (un enlace a una carpeta se borra como enlace, no como carpeta)
                    try await fs.remove(entry.path, directory: entry.kind == .directory)
                    done = L("\u{00AB}\(entry.name)\u{00BB} borrado")
                }
                let entries = try await fs.list(folder)
                self?.deliver(gen) { me in
                    me.show(path: folder, entries: entries)
                    me.setStatus(done)
                }
            } catch {
                let reason = error.localizedDescription
                self?.deliver(gen) { $0.setStatus(failed + ": " + reason) }
            }
        }
    }

    // MARK: - descargar y subir

    private func download(_ entry: RemoteEntry) {
        guard let fs else { return }
        guard let local = Self.localName(entry.name) else {
            setStatus(L("Nombre no v\u{00E1}lido: \u{00AB}\(entry.name)\u{00BB}"))
            return
        }
        let gen = generation
        let destination = Self.uniqueURL(Self.downloads.appendingPathComponent(local))
        setStatus(L("Descargando \u{00AB}\(entry.name)\u{00BB}\u{2026}"))
        task = Task { [weak self] in
            let owner = self          // (`self` de [weak self] es una variable: no se puede capturar en el closure de progreso)
            var reader: (any RemoteReader)?
            do {
                try FileManager.default.createDirectory(at: Self.downloads, withIntermediateDirectories: true)
                let total = entry.size ?? 0
                let source = try await fs.openRead(entry.path)
                reader = source
                let writer = try LocalFileWriter(url: destination)
                try await Transfer.copy(from: source, to: writer) { sent in
                    owner?.deliver(gen) { $0.setStatus(Self.progress(L("Descargando \u{00AB}\(entry.name)\u{00BB}"), sent, total)) }
                }
                await source.close()
                self?.deliver(gen) { $0.setStatus(L("Descargado en \(destination.lastPathComponent)") + " \u{00B7} " + Self.downloads.lastPathComponent) }
            } catch {
                await reader?.close()
                self?.deliver(gen) { $0.setStatus(L("No se puede descargar \u{00AB}\(entry.name)\u{00BB}: \(error.localizedDescription)")) }
            }
        }
    }

    private func upload() {
        guard let fs else { return }
        var text = uploadBox.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 1, text.hasPrefix("\""), text.hasSuffix("\"") { text = String(text.dropFirst().dropLast()) }
        guard !text.isEmpty else { return }
        let url = URL(fileURLWithPath: text)
        let name = url.lastPathComponent
        guard RemotePath.isValidName(name) else {
            setStatus(L("Nombre no v\u{00E1}lido: \u{00AB}\(name)\u{00BB}"))
            return
        }
        let gen = generation
        let folder = current
        let remote = RemotePath.join(folder, name)
        let total = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        setStatus(L("Subiendo \u{00AB}\(name)\u{00BB}\u{2026}"))
        task = Task { [weak self] in
            let owner = self
            var reader: LocalFileReader?
            do {
                let source = try LocalFileReader(url: url)
                reader = source
                let writer = try await AtomicRemoteWriter.open(fs, remote, verify: false, createOnly: true)
                try await Transfer.copy(from: source, to: writer) { sent in
                    owner?.deliver(gen) { $0.setStatus(Self.progress(L("Subiendo \u{00AB}\(name)\u{00BB}"), sent, total)) }
                }
                await source.close()
                let entries = try await fs.list(folder)
                self?.deliver(gen) { me in
                    me.show(path: folder, entries: entries)
                    me.setStatus(L("Subido \u{00AB}\(name)\u{00BB}"))
                    me.uploadBox.text = ""
                }
            } catch {
                await reader?.close()
                self?.deliver(gen) { $0.setStatus(L("No se puede subir \u{00AB}\(name)\u{00BB}: \(error.localizedDescription)")) }
            }
        }
    }

    // MARK: - utilidades

    private func setStatus(_ text: String) { statusText.text = text }

    private static func progress(_ what: String, _ sent: Int64, _ total: Int64) -> String {
        total > 0 ? "\(what) \(min(100, sent * 100 / total)) % (\(human(sent)) / \(human(total)))"
                  : "\(what) \(human(sent))"
    }

    static func human(_ bytes: Int64) -> String {
        var value = Double(bytes)
        for unit in ["B", "KB", "MB", "GB"] {
            if value < 1024 || unit == "GB" {
                return unit == "B" ? "\(Int(value)) B" : String(format: "%.1f %@", value, unit)
            }
            value /= 1024
        }
        return "\(bytes) B"
    }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    /// Descargas del usuario (si Foundation no la sabe en Windows, `~/Downloads`).
    static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    /// El nombre remoto como nombre local seguro: el servidor decide ese texto, asi que nada de rutas ni de caracteres
    /// que Windows no admite («..\\..\\algo», «con:flujo»).
    static func localName(_ remote: String) -> String? {
        let cleaned = String(remote.map { "<>:\"/\\|?*".contains($0) || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true ? "_" : $0 })
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return cleaned.isEmpty ? nil : cleaned
    }

    /// «a.txt», «a (2).txt»…: el primero libre.
    static func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var n = 2
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) (\(n))" + (ext.isEmpty ? "" : "." + ext))
            n += 1
        }
        return candidate
    }
}
