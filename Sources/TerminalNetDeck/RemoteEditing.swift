import AppKit
import NetDeckCore
import UniformTypeIdentifiers

/// «Editar» en un explorador: el archivo se baja a la carpeta de edición (`RemoteEdit`), se abre en tu editor de texto
/// y cada vez que lo guardas se sube (si el remoto sigue como se bajó; si no, se pregunta). Al cerrar el explorador o
/// la pestaña se conservan las copias abiertas (el editor puede seguir guardándolas) y se dice dónde.
@MainActor
final class RemoteEdits {
    private struct Item {
        var file: RemoteEditFile
        /// Fecha y tamaño de la copia local la última vez que se miró (para no calcular el MD5 cada segundo).
        var stamp: Stamp?
        var busy = false
        var retry = RemoteEditRetry()
        /// Lo guardado que se decidió no subir (Cancelar ante un cambio remoto): no se vuelve a preguntar hasta otro guardado.
        var declined: String?
        /// El último fallo dicho (no se repite en cada vuelta).
        var problem: String?
    }

    private struct Stamp: Equatable {
        var date: Date?
        var size: Int?
    }

    private var items: [String: Item] = [:]
    private let downloads = RemoteEditDownloads()
    private var uploads: [UUID: Task<Void, Never>] = [:]
    private var timer: Timer?
    private let folder: URL
    private weak var browser: RemoteBrowser?
    /// El de la ventana en la que está ahora su pestaña (puede pasar a otra).
    private var model: AppModel? { browser?.model }

    init(browser: RemoteBrowser) {
        self.browser = browser
        folder = RemoteEdit.workspace.appendingPathComponent(browser.id.uuidString.prefix(8).lowercased(), isDirectory: true)
    }

    static func canEdit(_ e: RemoteEntry) -> Bool { e.kind == .file && (e.size ?? 0) <= RemoteEdit.maxSize }

    /// Baja y abre (o vuelve a abrir, si ya se estaba editando).
    func edit(_ e: RemoteEntry) {
        guard !downloads.finished, let browser, let fs = browser.fs, browser.state == .connected else { return }
        if let it = items[e.path] {
            if FileManager.default.fileExists(atPath: it.file.local.path) { open(it.file) }
            else { fail("✗ " + L("No se puede leer la copia local de «\(it.file.name)»"), e.path) }
            return
        }
        if let n = e.size, n > RemoteEdit.maxSize {
            model?.status = L("✗ «\(e.name)» es demasiado grande para editarlo (máximo \(ByteCountFormatter.string(fromByteCount: RemoteEdit.maxSize, countStyle: .file)))")
            return
        }
        let folder = folder, label = browser.label
        let started = downloads.start(e.path, download: {
            try await RemoteEdit.download(fs, e.path, into: folder)
        }, opened: { [weak self, weak browser] f in
            guard let self else { return }
            self.items[e.path] = Item(file: f, stamp: Self.stamp(f.local))
            if browser?.message == L("Bajando «\(e.name)» para editarlo…") { browser?.message = nil }
            DebugLog.log("edición", "\(label):\(e.path) → \(AppPaths.tilde(f.local.path))")
            self.open(f)
            self.startWatching()
        }, failed: { [weak self, weak browser] error in
            browser?.message = nil
            self?.fail(L("✗ No se puede editar «\(e.name)»: \(error.localizedDescription)"), e.path)
        })
        if started { browser.message = L("Bajando «\(e.name)» para editarlo…") }
    }

    /// En tu editor de texto por defecto (nunca la app «por defecto» de esa extensión: un .sh o un .command se
    /// ejecutarían en Terminal).
    private func open(_ f: RemoteEditFile) {
        guard !downloads.finished else { return }
        let editor = NSWorkspace.shared.urlForApplication(toOpen: UTType.plainText)
            ?? URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        let name = f.name
        NSWorkspace.shared.open([f.local], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                guard let self, !self.downloads.finished else { return }
                self.fail(L("✗ No se puede abrir «\(name)» en el editor: \(error.localizedDescription)"), nil)
            }
        }
        model?.status = L("✎ «\(name)» abierto en el editor: al guardarlo se sube al servidor")
    }

    private func startWatching() {
        guard !downloads.finished, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private static func stamp(_ url: URL) -> Stamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return Stamp(date: a[.modificationDate] as? Date, size: (a[.size] as? NSNumber)?.intValue)
    }

    /// Cada segundo: ¿alguna copia local tiene otra fecha o tamaño? Entonces, si su MD5 es otro, se sube.
    private func poll() {
        guard !downloads.finished else { return }
        for (path, var it) in items where !it.busy {
            guard let now = Self.stamp(it.file.local), now != it.stamp || it.retry.operation != nil else { continue }
            if it.retry.operation != nil, !it.retry.ready(connected: browser?.state == .connected) { continue }
            it.stamp = now
            items[path] = it
            do {
                let md5 = try RemoteEdit.localDigest(it.file)
                guard md5 != it.file.syncedMD5, md5 != it.declined else { items[path]?.retry.reset(); continue }
            } catch {
                items[path]?.retry.failed(it.retry.operation ?? .upload)
                fail(L("✗ No se ha podido subir «\(it.file.name)»: \(error.localizedDescription). Tu copia está en \(AppPaths.tilde(it.file.local.path))"), path)
                continue
            }
            if it.retry.operation == .copy { saveCopy(path) } else { save(path, force: false) }
        }
    }

    private func save(_ path: String, force: Bool) {
        guard !downloads.finished, var it = items[path], !it.busy else { return }
        guard let browser, let fs = browser.fs, browser.state == .connected else {
            it.retry.failed(.upload)                       // (pendiente hasta reconectar, con espera entre intentos)
            items[path] = it
            fail(L("✗ «\(it.file.name)» guardado en el Mac pero sin conexión: se subirá al reconectar el explorador"), path)
            return
        }
        it.busy = true
        items[path] = it
        let file = it.file, name = file.name
        model?.status = L("Subiendo «\(name)»…")
        let id = UUID()
        uploads[id] = Task {
            defer { uploads[id] = nil }
            do {
                let r = try await RemoteEdit.upload(fs, file, force: force)
                guard !downloads.finished else { return }
                items[path]?.busy = false
                switch r {
                case .unchanged:
                    items[path]?.retry.reset()
                    model?.status = ""
                case .uploaded(let f):
                    done(path, f, L("✓ «\(name)» guardado en el servidor (MD5 comprobado)"))
                case .conflict(let c):
                    await ask(path, c)
                }
            } catch {
                guard !downloads.finished || error is ReplaceStuckError else { return }
                items[path]?.busy = false
                // (un resultado incierto conserva sus rutas: no se vuelve a publicar automáticamente)
                if error is ReplaceStuckError { items[path]?.retry.reset() } else { items[path]?.retry.failed(.upload) }
                fail(L("✗ No se ha podido subir «\(name)»: \(error.localizedDescription). Tu copia está en \(AppPaths.tilde(file.local.path))"), path)
            }
        }
    }

    private func done(_ path: String, _ f: RemoteEditFile, _ note: String) {
        items[path]?.file = f
        items[path]?.problem = nil
        items[path]?.declined = nil
        items[path]?.retry.reset()
        model?.status = note
        DebugLog.log("edición", "\(browser?.label ?? ""):\(path) subido (\(f.syncedMD5))")
        browser?.refresh()
    }

    /// El remoto ha cambiado o el protocolo exige confirmación: sobrescribir, guardar como copia al lado o dejarlo.
    private func ask(_ path: String, _ c: RemoteEdit.Conflict) async {
        guard !downloads.finished, let it = items[path] else { return }
        items[path]?.busy = true
        let name = it.file.name
        let canCopy = browser?.fs?.renameDoesNotOverwrite == true
        let why: String
        switch c {
        case .removed: why = L("«\(name)» ya no está en el servidor.")
        case .changed: why = L("«\(name)» ha cambiado en el servidor desde que lo abriste (otro tamaño u otro MD5).")
        case .requiresOverwrite:
            why = L("Este servidor no permite guardar una copia sin riesgo de sobrescribir otro archivo. Tu copia local se conserva.")
        }
        let title = c == .requiresOverwrite ? L("⚠️ Confirmar guardado de «\(name)»") : L("⚠️ «\(name)» ha cambiado en el servidor")
        let r = await ThemedAlert.run(title,
                                      message: why + "\n\n" + L("No se ha sobrescrito nada. Tu copia sigue en \(AppPaths.tilde(it.file.local.path))."),
                                      buttons: canCopy ? [L("Sobrescribir"), L("Guardar como copia"), L("Cancelar")]
                                                       : [L("Sobrescribir"), L("Cancelar")], destructive: 0)
        guard !downloads.finished, let it = items[path] else { return }
        items[path]?.busy = false
        switch r.button {
        case 0:
            save(path, force: true)
        case 1 where canCopy:
            saveCopy(path)
        default:
            items[path]?.retry.reset()
            items[path]?.declined = try? RemoteEdit.localDigest(it.file)
            model?.status = L("«\(name)» no se ha subido: el servidor y tu copia siguen como estaban")
        }
    }

    /// También al reintentar una copia: se publica otra copia exclusiva, nunca sobre el original.
    private func saveCopy(_ path: String) {
        guard !downloads.finished, var it = items[path], !it.busy else { return }
        let file = it.file, name = file.name
        guard let browser, let fs = browser.fs, browser.state == .connected else {
            it.retry.failed(.copy)
            items[path] = it
            fail(L("✗ Sin conexión: no se ha guardado la copia de «\(name)»"), path)
            return
        }
        it.busy = true
        items[path] = it
        let id = UUID()
        uploads[id] = Task {
            defer { items[path]?.busy = false; uploads[id] = nil }
            do {
                let (copy, f) = try await RemoteEdit.uploadCopy(fs, file)
                guard !downloads.finished else { return }
                done(path, f, L("✓ Guardado como «\(RemotePath.name(copy))» junto al original (que no se ha tocado)"))
            } catch {
                guard !downloads.finished || error is ReplaceStuckError else { return }
                if error is ReplaceStuckError {
                    items[path]?.retry.reset()
                    fail(L("✗ No se ha podido subir «\(name)»: \(error.localizedDescription). Tu copia está en \(AppPaths.tilde(file.local.path))"), path)
                } else {
                    items[path]?.retry.failed(.copy)
                    fail(L("✗ No se ha podido guardar la copia de «\(name)»: \(error.localizedDescription)"), path)
                }
            }
        }
    }

    private func fail(_ message: String, _ path: String?) {
        if let path {
            guard items[path]?.problem != message else { return }
            items[path]?.problem = message
        }
        model?.status = message
        ErrorLog.error("edición", "\(browser?.label ?? ""): \(message)")
    }

    /// Al cerrar: cancelar operaciones pendientes y conservar todo lo que pudo abrirse en el editor. Ni siquiera un
    /// MD5 sincronizado permite borrarlo: el editor puede guardar atómicamente justo después de comprobarlo.
    func finish() {
        guard !downloads.finished else { return }
        downloads.finish()
        uploads.values.forEach { $0.cancel() }
        uploads = [:]
        timer?.invalidate()
        timer = nil
        let kept = items.values.map(\.file)
        items = [:]
        if !kept.isEmpty {
            let sitios = kept.map { AppPaths.tilde($0.local.path) }.joined(separator: ", ")
            ErrorLog.warning("edición", "se conservan las copias abiertas en el editor: \(sitios)")
            model?.status = L("✗ Copias de edición conservadas en \(sitios). Puedes seguir guardándolas en el editor; ya no se subirán al servidor.")
        }
    }
}
