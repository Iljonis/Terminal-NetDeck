import AppKit
import Foundation
import NetDeckCore

/// «Actualizar ahora»: baja el .dmg de la release (github.com), lo comprueba (sha256 de GitHub, mismo id, versión
/// anunciada, firma íntegra), sustituye la app instalada y la vuelve a abrir con sus pestañas. Sólo cuando lo pides.
/// Lo que pasa queda en ~/Library/Logs/Terminal NetDeck/actualizar.log.
@MainActor
enum Updater {
    /// La app es un .app en una carpeta en la que puedes escribir (si no, se abre la descarga como siempre).
    static var canSelfInstall: Bool {
        let app = Bundle.main.bundleURL
        return app.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
            && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    static func install(_ r: UpdateCheck.Release, model: AppModel) {
        guard let dmg = r.dmg, let sha = r.sha256, canSelfInstall, let id = Bundle.main.bundleIdentifier else {
            NSWorkspace.shared.open(r.dmg ?? r.page)
            return
        }
        model.status = L("⬆ Descargando la \(r.version)…")
        let current = Bundle.main.bundleURL
        Task {
            do {
                let (tmp, _) = try await URLSession.shared.download(from: dmg)
                let new = try await Task.detached { try prepare(download: tmp, sha256: sha, bundleID: id, version: r.version) }.value
                model.saveOpenTabs()
                try relaunch(replacing: current, with: new)
                DebugLog.log("actualizaciones", "instalando la \(r.version)")
                NSApp.terminate(nil)
            } catch {
                ErrorLog.error("actualizaciones", "no se ha podido instalar la \(r.version): \(error.localizedDescription)")
                model.status = L("✗ No se ha podido actualizar: \(error.localizedDescription)")
            }
        }
    }

    struct Failure: LocalizedError {
        var errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    /// Comprueba el .dmg y saca la app a una carpeta temporal (sólo tuya). Devuelve la app nueva.
    nonisolated static func prepare(download: URL, sha256: String, bundleID: String, version: String) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("netdeck-actualizar-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = dir.appendingPathComponent("Terminal-NetDeck.dmg")
        try fm.moveItem(at: download, to: file)
        guard try UpdateCheck.sha256(of: file) == sha256 else { throw Failure(L("el .dmg no coincide con el publicado (sha256)")) }
        let mount = dir.appendingPathComponent("dmg", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, file.path]) == 0 else {
            throw Failure(L("no se ha podido abrir el .dmg"))
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }
        let inDMG = mount.appendingPathComponent("Terminal NetDeck.app")
        if let why = UpdateCheck.validate(app: inDMG, bundleID: bundleID, version: version) { throw Failure(why) }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", inDMG.path]) == 0 else {
            throw Failure(L("la firma de la app del .dmg no es válida"))
        }
        let app = dir.appendingPathComponent("Terminal NetDeck.app")
        guard run("/usr/bin/ditto", [inDMG.path, app.path]) == 0 else { throw Failure(L("no se ha podido copiar la app nueva")) }
        return app
    }

    /// Un ayudante espera a que esta app se cierre, cambia la app (si falla, deja la de antes) y la abre con sus pestañas.
    private static func relaunch(replacing current: URL, with new: URL) throws {
        let dir = new.deletingLastPathComponent()
        let script = dir.appendingPathComponent("cambiar.sh")
        try """
            #!/bin/bash
            pid=$1 actual=$2 nueva=$3 antes=$4
            for _ in $(seq 1 150); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
            echo "=== $(date '+%F %T') · actualizar desde GitHub: $actual"
            if mv "$actual" "$antes"; then
              if mv "$nueva" "$actual"; then echo "✓ app nueva en su sitio"; else mv "$antes" "$actual"; echo "✗ no se ha podido cambiar: sigue la de antes"; fi
            else
              echo "✗ no se ha podido apartar la app de antes"
            fi
            xattr -dr com.apple.quarantine "$actual" 2>/dev/null
            open "$actual" --args --reabrir

            """.write(to: script, atomically: true, encoding: .utf8)
        let log = DebugLog.directory.appendingPathComponent("actualizar.log")
        AppPaths.ensure(DebugLog.directory)
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), current.path, new.path,
                       dir.appendingPathComponent("anterior.app").path]
        if let h = try? FileHandle(forWritingTo: log) {
            h.seekToEndOfFile()
            p.standardOutput = h
            p.standardError = h
        }
        try p.run()
    }

    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
