import AppKit
import NetDeckCore
import SwiftUI

extension AppModel {
    func macroAccepts(_ s: TerminalSession) -> Bool {
        !s.exited && (!s.route.usesPasswords || s.loggedIn) && !SecretPrompt.asks(s.cursorLine)
            && (s.browser == nil || s.showConsole)
    }

    func reloadWorkspaces() {
        do { workspaces = try WorkspaceLibrary.load(); workspacesError = nil }
        catch { workspacesError = error.localizedDescription; status = "✗ " + error.localizedDescription }
    }

    func captureWorkspace(name: String, id: UUID = UUID()) -> Workspace {
        // (el panel SFTP, también oculto, explícito: si no, al restaurar lo reabriría el estado global de esa sesión)
        let entries = tabs.map { s in
            WorkspaceTab(id: s.id, route: s.route,
                         panel: s.sidePanel?.layout ?? (SFTPPanel.offers(s.route) ? SFTPPanelLayout(visible: false) : nil))
        }
        return Workspace(id: id, name: name, tabs: entries, selected: selection,
                         layout: showSplit ? split?.layout.rawValue : nil,
                         panes: showSplit ? split?.panes ?? [] : [], fractions: split?.fractions ?? [:])
    }

    func saveWorkspace(name: String, replacing id: UUID? = nil) -> String? {
        guard workspacesError == nil else { return workspacesError }
        let w = captureWorkspace(name: name.trimmingCharacters(in: .whitespacesAndNewlines), id: id ?? UUID())
        var lib = workspaces
        if let i = lib.workspaces.firstIndex(where: { $0.id == w.id }) { lib.workspaces[i] = w }
        else { lib.workspaces.append(w) }
        do { try lib.save(); workspaces = lib; return nil }
        catch { return error.localizedDescription }
    }

    func removeWorkspace(_ id: UUID) -> String? {
        guard workspacesError == nil else { return workspacesError }
        var lib = workspaces; lib.workspaces.removeAll { $0.id == id }
        do { try lib.save(); workspaces = lib; return nil }
        catch { return error.localizedDescription }
    }

    /// La restauración requiere un clic y apaga MultiExec. Macros y túneles no se arrancan al abrir un espacio.
    func restoreWorkspace(_ w: Workspace, replacing: Bool) async -> Bool {
        do {
            let resolved = try w.resolve(using: sessions)
            guard !resolved.tabs.isEmpty else { status = L("✗ El espacio no tiene sesiones disponibles"); return false }
            if !resolved.missing.isEmpty,
               !(await ThemedAlert.confirm(L("Faltan sesiones del espacio"),
                    message: resolved.missing.joined(separator: ", "), ok: L("Abrir las disponibles"))) { return false }
            if replacing, !tabs.isEmpty,
               !(await ThemedAlert.confirm(L("¿Sustituir las pestañas abiertas?"),
                    message: L("Se cerrarán las conexiones actuales. Las copias del editor remoto se conservan."),
                    ok: L("Sustituir pestañas"), destructive: true)) { return false }
            multiExecOn = false; abortAll()
            if replacing { for s in tabs { close(s) }; split = nil; showSplit = false }
            var ids: [UUID: UUID] = [:]
            for entry in resolved.tabs {
                let s = open(entry.route); ids[entry.id] = s.id
                if let layout = entry.panel, SFTPPanel.offers(s.route) {
                    s.sidePanel?.close()
                    let panel = SFTPSidePanel(key: SFTPPanel.key(for: s.route), layout: layout, model: self)
                    s.sidePanel = panel
                    if layout.visible { panel.show(in: s) }
                }
            }
            if let raw = w.layout, let layout = Split.Layout(rawValue: raw) {
                let panes = w.panes.compactMap { ids[$0] }
                if !panes.isEmpty { split = Split(layout: layout, panes: panes, fractions: w.fractions); showSplit = true }
            } else if showSplit {
                showSplit = false            // (un espacio sin vista dividida: que se vea la pestaña elegida; la vista sigue)
            }
            selection = w.selected.flatMap { ids[$0] } ?? resolved.tabs.first.flatMap { ids[$0.id] }
            saveOpenTabs()
            status = L("✓ Espacio «\(w.name)» abierto (\(ids.count) pestañas)")
            return true
        } catch { status = "✗ " + error.localizedDescription; return false }
    }

    func splitWeights(_ key: String, count: Int) -> [Double] { Workspace.weights(split?.fractions[key], count: count) }
    func setSplitWeights(_ weights: [Double], key: String) {
        guard var sp = split else { return }; sp.fractions[key] = weights; split = sp
    }
}

struct WorkspaceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @Stored private var name = ""
    @Stored private var selected: UUID?
    @Stored private var message = ""
    @Stored private var busy = false
    private var picked: Workspace? { model.workspaces.workspaces.first { $0.id == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Espacios de trabajo")).font(t.ui(19, .bold)).foregroundStyle(SwiftUI.Color(t.accent))
            Text(L("Guarda las pestañas, su orden, la selección y la distribución. Abrir un espacio requiere tu confirmación; MultiExec queda apagado."))
                .font(t.ui(12)).foregroundStyle(SwiftUI.Color(t.dim))
            List(model.workspaces.workspaces, selection: $selected) { w in
                HStack { Text(w.name); Spacer(); Text(L("\(w.tabs.count) pestañas")).foregroundStyle(.secondary) }.tag(w.id)
            }
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: t.neon ? 3 : 6).fill(SwiftUI.Color(t.panel).opacity(0.5)))
            .overlay {
                if model.workspaces.workspaces.isEmpty {
                    Text(L("Aún no hay espacios: abre las pestañas que quieras, ponle un nombre y pulsa «Guardar disposición actual»."))
                        .font(t.ui(12)).foregroundStyle(SwiftUI.Color(t.dim)).multilineTextAlignment(.center).padding(30)
                }
            }
            .onChange(of: selected) { name = picked?.name ?? "" }
            HStack {
                TextField(L("Nombre del espacio"), text: $name)
                Button(L("Guardar disposición actual")) { act {
                    let id = picked?.id
                    if id != nil, !(await ThemedAlert.confirm(L("¿Actualizar este espacio?"), message: L("Se guardará la disposición actual de la ventana."), ok: L("Guardar"))) { return }
                    if let e = model.saveWorkspace(name: name, replacing: id) { message = "✗ " + e }
                    else { message = L("✓ Espacio guardado") }
                } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.tabs.isEmpty || model.workspacesError != nil)
                Button(L("Nuevo")) { selected = nil; name = "" }
            }
            Text(message.isEmpty ? (model.workspacesError ?? AppPaths.tilde(WorkspaceLibrary.defaultURL.path)) : message)
                .font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim)).lineLimit(3)
            HStack {
                Button(L("Borrar…")) { act {
                    guard let w = picked, await ThemedAlert.confirm(L("¿Borrar el espacio «\(w.name)»?"), message: L("Las sesiones y las pestañas abiertas se conservan."), ok: L("Borrar"), destructive: true) else { return }
                    if let e = model.removeWorkspace(w.id) { message = "✗ " + e } else { selected = nil; name = "" }
                } }.disabled(picked == nil || model.workspacesError != nil)
                Spacer()
                Button(L("Añadir pestañas")) { open(replacing: false) }.disabled(picked == nil)
                Button(L("Sustituir pestañas")) { open(replacing: true) }.disabled(picked == nil)
                Button(L("Cerrar")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 720, height: 480).background(SwiftUI.Color(t.background))
        .disabled(busy).interactiveDismissDisabled(busy)
    }
    private func act(_ body: @escaping @MainActor () async -> Void) {
        guard !busy else { return }; busy = true
        Task { await body(); busy = false }
    }
    private func open(replacing: Bool) {
        guard let w = picked else { return }
        act { if await model.restoreWorkspace(w, replacing: replacing) { dismiss() } }
    }
}
