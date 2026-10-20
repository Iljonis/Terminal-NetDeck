import NetDeckCore
import SwiftUI

/// Editor de macros (Herramientas → Macros…, o al parar una grabación): la lista a la izquierda y los pasos de la
/// elegida a la derecha. Guardar escribe macros.json (validado: nombre único, pasos con sus límites).
struct MacroSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @Stored private var library = MacroLibrary()
    @Stored private var selected: Macro.ID?
    @Stored private var draft = Macro(name: "macro")
    /// Lo guardado de la elegida (nil: nueva, sin guardar).
    @Stored private var baseline: Macro?
    @Stored private var message = ""
    @Stored private var loaded = false
    @Stored private var busy = false

    private var dirty: Bool { baseline != draft }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                list.frame(width: 220)
                NeonLine(vertical: true, color: t.panel)
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            NeonLine(color: t.panel)
            footer
        }
        .frame(width: 820, height: 540)
        .background(SwiftUI.Color(t.background))
        .onAppear(perform: load)
    }

    // MARK: lista

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("MACROS")).font(t.ui(13, .heavy)).tracking(3).foregroundStyle(SwiftUI.Color(t.accent))
                Text("\(library.macros.count)").font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim))
                Spacer()
                if dirty { Text(L("● sin guardar")).font(t.ui(10, .bold)).foregroundStyle(SwiftUI.Color(t.warning)) }
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(library.macros) { m in
                        row(m.name, detail: L("\(m.lines.count) órdenes"), on: selected == m.id) { choose(m.id) }
                    }
                    if baseline == nil {
                        row(draft.name, detail: L("(nueva, sin guardar)"), on: true) {}
                    }
                }
                .padding(.horizontal, 8)
            }
            NeonLine(color: t.panel)
            HStack(spacing: 6) {
                IconButton(icon: "plus") { choose(nil) }.help(L("Nueva")).disabled(busy)
                IconButton(icon: "plus.square.on.square") { duplicate() }.help(L("Duplicar")).disabled(busy)
                IconButton(icon: "trash") { act { await remove() } }.help(L("Borrar…")).disabled(busy || baseline == nil)
                Spacer()
                IconButton(icon: model.recording == nil ? "record.circle" : "stop.circle.fill", active: model.recording != nil) {
                    act {
                        if model.recording != nil {
                            model.stopRecording()
                            if let d = model.macroDraft { model.macroDraft = nil; selected = nil; draft = d; baseline = nil }
                        } else if await confirmLeave() {
                            model.toggleRecording()
                            if model.recording != nil { dismiss() }
                        }
                    }
                }
                .help(model.recording == nil ? L("Grabar una macro en la pestaña activa") : L("Parar la grabación"))
            }
            .padding(8)
        }
        .background(SwiftUI.Color(t.bar))
    }

    private func row(_ title: String, detail: String, on: Bool, tap: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "record.circle")
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

    // MARK: pasos

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("", text: $draft.name, prompt: Text(L("Nombre"))).frame(maxWidth: 300)
                Toggle(L("Confirmar antes de reproducir"), isOn: $draft.confirm)
                Spacer()
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(draft.steps.enumerated()), id: \.element.id) { i, _ in stepRow(i) }
                    if draft.steps.isEmpty {
                        Text(L("Sin pasos: añade uno abajo o graba una macro (●)"))
                            .font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim)).padding(8)
                    }
                }
            }
            HStack(spacing: 8) {
                Text(L("Añadir:")).font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
                ForEach(MacroStep.Kind.allCases, id: \.self) { k in
                    NeonButton(title: k.title, icon: k.icon) { add(k) }
                }
                Spacer()
            }
            if let p = problem {
                Text("✗ " + p).font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.bad)).lineLimit(2)
            } else if !draft.dangerousLines.isEmpty {
                Text(L("⚠ Lleva órdenes peligrosas: se confirman antes de reproducirla (\(draft.dangerousLines.prefix(3).joined(separator: " · ")))"))
                    .font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.warning)).lineLimit(2)
            }
            Text(L("Se para si el equipo da error, pagina o pide una contraseña (nunca la escribe). Esc, Ctrl+C o ■ la cortan."))
                .font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim))
        }
        .padding(14)
    }

    private func stepRow(_ i: Int) -> some View {
        let step = $draft.steps[i]
        let k = draft.steps[i].kind
        return HStack(spacing: 8) {
            Text("\(i + 1)").font(t.ui(10, .bold)).foregroundStyle(SwiftUI.Color(t.dim)).frame(width: 22, alignment: .trailing)
            Image(systemName: k.icon).font(.system(size: 11)).foregroundStyle(SwiftUI.Color(t.accent2)).frame(width: 16)
            Text(k.title).font(t.ui(11, .semibold)).frame(width: 104, alignment: .leading)
            if k == .send || k == .text {
                TextField("", text: step.text, prompt: Text(k == .send ? L("orden, p. ej. show ip interface brief") : L("regex, p. ej. ^\\[OK\\]")))
                    .font(.system(.body, design: .monospaced))
            } else {
                Spacer()
            }
            if k != .send {
                Text(k == .pause ? L("dura") : L("máx.")).font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim))
                TextField("", value: step.seconds, format: .number).frame(width: 52)
                Text("s").font(t.ui(10)).foregroundStyle(SwiftUI.Color(t.dim))
            }
            IconButton(icon: "chevron.up") { move(i, -1) }.disabled(i == 0).help(L("Subir"))
            IconButton(icon: "chevron.down") { move(i, 1) }.disabled(i == draft.steps.count - 1).help(L("Bajar"))
            IconButton(icon: "minus") { draft.steps.remove(at: i) }.help(L("Quitar"))
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(SwiftUI.Color(draft.steps[i].problem == nil ? t.panel : t.bad).opacity(0.25)))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(message.isEmpty ? AppPaths.tilde(MacroLibrary.defaultURL.path) : message)
                .font(t.ui(11)).foregroundStyle(SwiftUI.Color(message.hasPrefix("✗") ? t.bad : t.dim)).lineLimit(2)
            Spacer()
            NeonButton(title: L("Cerrar"), icon: "xmark") { act { if await confirmLeave() { dismiss() } } }
                .disabled(busy)
            NeonButton(title: L("Guardar"), icon: "checkmark", active: dirty) { _ = save() }
                .disabled(busy || !dirty)
                .keyboardShortcut("s")
            NeonButton(title: L("Reproducir aquí"), icon: "play.fill", tint: t.good) { play(toAll: false) }
                .disabled(busy || problem != nil || model.current == nil)
                .help(model.current.map { L("En «\($0.title)»") } ?? "")
            NeonButton(title: L("En MultiExec"), icon: "square.stack.3d.forward.dottedline.fill", tint: t.warning) { play(toAll: true) }
                .disabled(busy || problem != nil || !model.multiExecOn)
                .help(L("En todas las pestañas de MultiExec que no se están autenticando"))
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(SwiftUI.Color(t.bar))
    }

    // MARK: acciones

    private var problem: String? {
        if let p = draft.problem { return p }
        let n = draft.name.trimmingCharacters(in: .whitespaces).lowercased()
        if library.macros.contains(where: { $0.id != draft.id && $0.name.lowercased() == n }) {
            return L("ya hay una macro con ese nombre")
        }
        return nil
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        library = model.macros
        if let e = model.macrosError {
            message = "✗ " + e
        } else if !model.macroWarnings.isEmpty {
            message = "✗ " + L("\(model.macroWarnings.count) ignoradas: ") + model.macroWarnings.prefix(2).joined(separator: " · ")
        }
        if let d = model.macroDraft {                 // (lo recién grabado)
            model.macroDraft = nil
            selected = nil
            draft = d
            baseline = nil
        } else {
            pick(library.macros.first?.id)
        }
    }

    private func pick(_ id: Macro.ID?) {
        selected = id
        if let m = library.macro(id) {
            draft = m
            baseline = m
        } else {
            draft = Macro(name: library.uniqueName(L("macro")), steps: [.send(""), .prompt()])
            baseline = nil
        }
    }

    private func choose(_ id: Macro.ID?) {
        guard id != selected || id == nil else { return }
        act { if await confirmLeave() { pick(id) } }
    }

    private func act(_ action: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            await action()
            busy = false
        }
    }

    /// Con cambios sin guardar: guardar, descartar o quedarse (`false`).
    private func confirmLeave() async -> Bool {
        guard dirty else { return true }
        switch await ThemedAlert.run(L("La macro «\(draft.name)» tiene cambios sin guardar"),
                                     buttons: [L("Guardar"), L("Descartar"), L("Cancelar")]).button {
        case 0: return save()
        case 1: return true
        default: return false
        }
    }

    @discardableResult private func save() -> Bool {
        if let p = problem { message = "✗ " + p; return false }
        var lib = library
        var m = draft
        m.name = m.name.trimmingCharacters(in: .whitespaces)
        if let i = lib.macros.firstIndex(where: { $0.id == m.id }) { lib.macros[i] = m } else { lib.macros.append(m) }
        if let e = model.saveMacros(lib) { message = "✗ " + e; return false }
        library = lib
        selected = m.id
        draft = m
        baseline = m
        message = L("✓ Macro «\(m.name)» guardada")
        return true
    }

    private func duplicate() {
        act {
            guard await confirmLeave() else { return }
            var c = draft
            c.id = UUID()
            c.name = library.uniqueName(c.name)
            c.steps = c.steps.map { MacroStep(kind: $0.kind, text: $0.text, seconds: $0.seconds) }
            selected = nil
            draft = c
            baseline = nil
        }
    }

    private func remove() async {
        guard let m = baseline else { return }
        guard await ThemedAlert.confirm(L("¿Borrar la macro «\(m.name)»?"), message: L("Queda una copia en macros.json.anterior."),
                                        ok: L("Borrar"), destructive: true) else { return }
        var lib = library
        lib.macros.removeAll { $0.id == m.id }
        if let e = model.saveMacros(lib) { message = "✗ " + e; return }
        library = lib
        pick(lib.macros.first?.id)
        message = L("✓ Borrada")
    }

    private func add(_ k: MacroStep.Kind) {
        switch k {
        case .send: draft.steps.append(.send(""))
        case .prompt: draft.steps.append(.prompt())
        case .text: draft.steps.append(.text(""))
        case .pause: draft.steps.append(.pause(1))
        }
    }

    private func move(_ i: Int, _ d: Int) {
        let j = i + d
        guard draft.steps.indices.contains(j) else { return }
        draft.steps.swapAt(i, j)
    }

    /// Se reproduce tal como está (aunque no esté guardada): sólo con este clic.
    private func play(toAll: Bool) {
        let m = draft
        // (el borrador sigue disponible si se cancela la confirmación de la reproducción)
        if dirty { model.macroDraft = m }
        dismiss()
        Task { await model.runMacro(m, toAll: toAll) }
    }
}

extension MacroStep.Kind {
    var title: String {
        switch self {
        case .send: L("Enviar")
        case .prompt: L("Esperar prompt")
        case .text: L("Esperar texto")
        case .pause: L("Pausa")
        }
    }

    var icon: String {
        switch self {
        case .send: "return"
        case .prompt: "chevron.right.square"
        case .text: "text.magnifyingglass"
        case .pause: "pause.circle"
        }
    }
}

/// El ● de la barra: grabar, reproducir una guardada (en la pestaña activa o en MultiExec) y el editor.
struct MacroMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        IconMenu(icon: model.recording == nil ? "record.circle" : "record.circle.fill", active: model.recording != nil || model.macroRunning) {
            if model.recording != nil {
                Button(L("■ Parar la grabación")) { model.stopRecording() }
            } else {
                Button(model.current.map { L("● Grabar macro en «\($0.title)»") } ?? L("● Grabar macro")) { model.toggleRecording() }
                    .disabled(model.current == nil)
            }
            if model.macroRunning {
                Button(L("■ Parar la macro (Esc)")) { model.abortAll() }
            }
            if !model.macros.macros.isEmpty {
                MenuDivider()
                MenuHeader(title: model.multiExecOn ? L("Reproducir en MultiExec (\(model.multiExecTargets.count))")
                                                    : L("Reproducir en «\(model.current?.title ?? "—")»"))
                ForEach(model.macros.macros) { m in
                    Button { Task { await model.runMacro(m, toAll: model.multiExecOn) } } label: {
                        Label(m.name, systemImage: "play.fill")
                    }
                    .disabled(model.macroRunning || (model.multiExecOn ? model.multiExecTargets.isEmpty : model.current == nil))
                }
            }
            MenuDivider()
            Button(L("Macros…")) { model.sheet = .macros }
        }
    }
}
