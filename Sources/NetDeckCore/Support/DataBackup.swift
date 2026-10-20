import Foundation

/// Copias de los archivos del usuario (sesiones, ~/.ssh/config, botones, listas, macros, túneles) antes de cada
/// actualización y al estrenar versión, en `~/Library/Application Support/Terminal NetDeck/copias/` (fuera de
/// ~/.config/netdeck, que es también la carpeta de NetDeck: su desinstalador la borra entera). Y al arrancar, si falta el
/// archivo de sesiones, se recupera de la copia más reciente que tenga alguna (las de aquí, `.anterior`/`.original` o la
/// que deja el desinstalador de NetDeck en ~/Documents/netdeck-copia-*). Nada se borra salvo las copias más viejas de `keep`.
/// La copia obligatoria antes de cambiar la app no se ha podido hacer.
public struct BackupError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct DataBackup: Sendable {
    /// Qué se copia: nombre dentro de la copia → archivo.
    public var items: [(name: String, url: URL)]
    public var directory: URL
    /// El archivo de sesiones (el que se recupera si falta).
    public var sessions: URL
    /// Carpetas donde buscar copias de NetDeck (cada subcarpeta «netdeck-copia-*» con su ssh_config).
    public var foreignCopies: [URL]
    public var keep = 15

    static let sessionsName = "ssh_config"

    public init(items: [(name: String, url: URL)], directory: URL, sessions: URL, foreignCopies: [URL] = []) {
        self.items = items
        self.directory = directory
        self.sessions = sessions
        self.foreignCopies = foreignCopies
    }

    /// La de la app (con NETDECK_HOME, la de esa carpeta).
    public static var standard: DataBackup {
        DataBackup(items: [(sessionsName, SessionFile.defaultURL),
                           ("ssh-config", AppPaths.home.appendingPathComponent(".ssh/config")),
                           ("botones.txt", ButtonFile.defaultURL),
                           ("listas.json", ListLibrary.defaultURL),
                           ("macros.json", MacroLibrary.defaultURL),
                           ("tuneles.json", TunnelLibrary.defaultURL),
                           ("espacios.json", WorkspaceLibrary.defaultURL),
                           ("panel-sftp.json", AppPaths.support.appendingPathComponent("panel-sftp.json"))],
                   directory: AppPaths.support.appendingPathComponent("copias", isDirectory: true),
                   sessions: SessionFile.defaultURL,
                   foreignCopies: [AppPaths.home.appendingPathComponent("Documents", isDirectory: true)])
    }

    /// Copia ahora lo que exista en «copias/AAAAMMDD-HHMMSS-<motivo>/» (0700; los archivos, 0600). nil si no había
    /// nada que copiar. Un archivo que no se puede leer se salta (y se apunta), pero no impide copiar los demás.
    @discardableResult
    public func snapshot(reason: String, now: Date = Date()) -> URL? { copy(reason: reason, now: now).dir }

    /// Antes de cambiar la app (instalar o actualizar) la copia es obligatoria: si algún archivo que existe no se ha
    /// podido copiar (o no se puede crear la carpeta), lanza un error y quien llama NO cambia la app. nil si no había
    /// nada que copiar.
    @discardableResult
    public func snapshotBeforeInstall(reason: String, now: Date = Date()) throws -> URL? {
        let r = copy(reason: reason, now: now)
        guard r.failed.isEmpty else {
            throw BackupError(L("No se ha podido copiar \(r.failed.joined(separator: ", ")) antes de cambiar la app: no se cambia nada"))
        }
        return r.dir
    }

    private func copy(reason: String, now: Date) -> (dir: URL?, failed: [String]) {
        let fm = FileManager.default
        let present = items.filter { fm.fileExists(atPath: $0.url.path) }
        guard !present.isEmpty else { return (nil, []) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let tag = String(reason.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "." ? Character($0) : "-" })
        let base = "\(f.string(from: now))-\(tag)"
        var dir = directory.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: dir.path) { dir = directory.appendingPathComponent("\(base)-\(n)", isDirectory: true); n += 1 }
        AppPaths.ensure(directory)
        AppPaths.ensure(dir)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            ErrorLog.warning("copias", "no se puede crear \(AppPaths.tilde(dir.path))")
            return (nil, [AppPaths.tilde(directory.path)])
        }
        var copied = 0
        var failed: [String] = []
        for (name, url) in present {
            do {
                let text = try SafeFile.read(url.resolvingSymlinksInPath()) ?? ""
                try SafeFile.write(text, to: dir.appendingPathComponent(name))
                copied += 1
            } catch {
                ErrorLog.warning("copias", "sin copia de \(AppPaths.tilde(url.path)): \(error.localizedDescription)")
                failed.append(AppPaths.tilde(url.path))
            }
        }
        if copied == 0 { try? fm.removeItem(at: dir); return (nil, failed) }
        prune()
        DebugLog.log("copias", "\(copied) archivos en \(dir.path) (\(reason))")
        return (dir, failed)
    }

    /// Las sesiones tal como estaban antes del último guardado (fuera de ~/.config/netdeck: se salva aunque se borre).
    public var sessionsBak: URL { directory.appendingPathComponent("ssh_config.bak") }

    /// Antes de guardar las sesiones: el archivo de ahora a `sessionsBak` (0600). Sólo si tiene alguna sesión (un archivo
    /// vacío no pisa una copia buena) y se puede leer. false si no se ha podido copiar (se apunta en el error.log): entonces
    /// NO se guarda (`SessionFile.save(to:including:backup:)` se para y lo dice).
    public func backupSessionsBeforeSave() -> Bool {
        do {
            guard let text = try SafeFile.read(sessions.resolvingSymlinksInPath()),
                  !SessionFile(text: text).sessions.isEmpty else { return true }
            AppPaths.ensure(directory)
            try SafeFile.write(text, to: sessionsBak)
            return true
        } catch {
            ErrorLog.warning("copias", "sin \(AppPaths.tilde(sessionsBak.path)): \(error.localizedDescription)")
            return false
        }
    }

    /// Si hay sesiones pero el ssh_config (el de siempre o el elegido en Ajustes) ya no las incluye o ya no existe (el
    /// desinstalador de NetDeck quita el Include; también otra herramienta que lo reescriba o lo borre), la lista se queda
    /// vacía aunque el archivo siga intacto: vuelve a poner el Include (con copia del de antes, si lo había). true si lo
    /// ha añadido; false si no faltaba o no hay sesiones. Si las sesiones o el ssh_config no se pueden leer, o no se puede
    /// escribir, lanza un error y no se toca nada (un archivo ilegible no es un archivo vacío).
    @discardableResult
    public func restoreIncludeIfMissing(sshConfig: URL) throws -> Bool {
        guard let text = try SafeFile.read(sessions.resolvingSymlinksInPath()), !SessionFile(text: text).sessions.isEmpty else { return false }
        if let config = try SafeFile.read(sshConfig.resolvingSymlinksInPath()), SessionFile.hasInclude(config) { return false }
        try SessionFile.applyInclude(try SessionFile.includePlan(sshConfig))
        ErrorLog.warning("sesiones", "\(AppPaths.tilde(sshConfig.path)) no incluía \(AppPaths.tilde(sessions.path)): vuelto a incluir")
        return true
    }

    /// Las copias de la app, de la más nueva a la más vieja.
    public var snapshots: [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return all.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Deja las `keep` más nuevas (sólo dentro de «copias»).
    func prune() {
        for old in snapshots.dropFirst(keep) { try? FileManager.default.removeItem(at: old) }
    }

    /// Dónde puede haber sesiones guardadas, por orden de confianza (no por fecha: una copia ajena con fecha futura no
    /// gana): las copias de la app (la más nueva primero; `sessionsBak` delante si es más reciente que ella: se guardó
    /// algo después de copiar) y `.anterior`/`.original`. Las «netdeck-copia-*» de NetDeck, aparte
    /// (`foreignCandidates`): mirar ~/Documents puede sacar el aviso de privacidad de macOS.
    public var sessionCandidates: [URL] {
        let fm = FileManager.default
        func date(_ u: URL) -> Date { ((try? fm.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date) ?? .distantPast }
        var own = snapshots.map { $0.appendingPathComponent(Self.sessionsName) }.filter { fm.fileExists(atPath: $0.path) }
        if fm.fileExists(atPath: sessionsBak.path) {
            if let newest = own.first, date(newest) > date(sessionsBak) { own.append(sessionsBak) } else { own.insert(sessionsBak, at: 0) }
        }
        return own + [sessions.appendingPathExtension("anterior"), sessions.appendingPathExtension("original")]
            .filter { fm.fileExists(atPath: $0.path) }
    }

    /// Las «netdeck-copia-AAAAMMDD-HHMMSS» de NetDeck, la más nueva primero (por el nombre).
    public var foreignCandidates: [URL] {
        let fm = FileManager.default
        return foreignCopies.flatMap { d in
            ((try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("netdeck-copia-") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .map { $0.appendingPathComponent(Self.sessionsName) }
        }.filter { fm.fileExists(atPath: $0.path) }
    }

    /// Si el archivo de sesiones no existe, lo recupera de la mejor copia con alguna sesión. Se guarda como desde el
    /// gestor (`SessionFile.save`: comprobado con «ssh -G»; si ssh no lo entiende, se prueba la siguiente), y las de
    /// NetDeck pasan además el filtro de importar (fuera ProxyCommand, LocalCommand…). Devuelve de dónde y cuántas, o nil
    /// si no faltaba o no hay copia. Si existe (aunque esté vacío) no se toca: puede que las hayas borrado tú. Sólo
    /// tiene sentido si consta que había sesiones (la app lo apunta al guardarlas).
    @discardableResult
    public func recoverSessionsIfMissing(validate: Bool = true) -> (source: URL, count: Int)? {
        guard !FileManager.default.fileExists(atPath: sessions.path) else { return nil }
        let own = sessionCandidates.map { ($0, false) }
        for (c, foreign) in own + (own.isEmpty ? foreignCandidates.map { ($0, true) } : []) {
            guard let text = try? SafeFile.read(c) else { continue }
            var file = SessionFile(text: text)
            guard !file.sessions.isEmpty else { continue }
            if foreign {
                file.head = []
                file.tail = []
                for i in file.sessions.indices { file.sessions[i].extra = SessionImporter.safeExtra(file.sessions[i].extra, session: file.sessions[i].name) }
            }
            if let err = file.save(to: sessions, validate: validate) {
                ErrorLog.error("sesiones", "no se han podido recuperar de \(AppPaths.tilde(c.path)): \(err)")
                continue
            }
            ErrorLog.warning("sesiones", "faltaba \(AppPaths.tilde(sessions.path)): recuperadas \(file.sessions.count) de \(AppPaths.tilde(c.path))")
            return (c, file.sessions.count)
        }
        return nil
    }
}
