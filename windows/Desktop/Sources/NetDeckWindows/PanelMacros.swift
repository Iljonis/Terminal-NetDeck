import Foundation
import NetDeckCore
import WinUI

final class PanelMacros {
    let view = ScrollViewer()
    var onPlay: ((Macro) -> Void)?
    var onSave: ((Macro) -> Void)?
    var onRecord: (() -> Void)?
    var onDelete: ((Macro) -> Void)?
    var onClose: (() -> Void)?

    private let list = ComboBox()
    private let play = Button()
    private let editar = Button()
    private let borrar = Button()
    private let confirmar = CheckBox()
    private var original: Macro?
    private var stepsAreEditable = true
    private let name = TextBox()
    private let commands = TextBox()
    private var library = MacroLibrary()

    // Advanced step editor
    private var draftSteps: [MacroStep] = []
    private var selectedStepIndex = -1
    private var advancedModeActive = false
    private var rebuildingStepList = false
    private let simpleArea = StackPanel()
    private let advancedArea = StackPanel()
    private let modoAvanzado = Button()
    private let stepList = ComboBox()
    private let stepKind = ComboBox()
    private let stepText = TextBox()
    private let stepSeconds = TextBox()
    private let stepEditArea = StackPanel()
    private static let stepKinds = MacroStep.Kind.allCases

    private static func kindTitle(_ k: MacroStep.Kind) -> String {
        switch k {
        case .send:   L("Enviar")
        case .prompt: L("Esperar prompt")
        case .text:   L("Esperar texto")
        case .pause:  L("Pausa")
        }
    }

    private static func stepSummary(_ step: MacroStep) -> String {
        switch step.kind {
        case .send:   "\(L("Enviar")): «\(String(step.text.prefix(40)))»"
        case .prompt: "\(L("Esperar prompt")) (\(Int(step.seconds))s)"
        case .text:   "\(L("Esperar texto")): \(String(step.text.prefix(30))) (\(Int(step.seconds))s)"
        case .pause:  "\(L("Pausa")) \(step.seconds)s"
        }
    }

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.maxWidth = 760
        form.horizontalAlignment = .left
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let title = TextBlock()
        title.text = L("Macros")
        title.fontSize = 20
        list.header = L("Macros")
        name.header = L("Nombre")
        commands.header = L("Una orden por línea")
        commands.acceptsReturn = true
        commands.minHeight = 140
        commands.fontFamily = FontFamily("Consolas")
        list.minWidth = 250
        name.minWidth = 300
        commands.minWidth = 420
        play.content = L("Reproducir")
        editar.content = L("Editar")
        borrar.content = L("Borrar")
        confirmar.content = L("Confirmar antes de reproducir")
        let nueva = Button()
        nueva.content = L("Nueva")
        nueva.click.addHandler { [weak self] _, _ in self?.clearDraft() }
        let grabar = Button()
        grabar.content = L("Grabar macro")
        grabar.click.addHandler { [weak self] _, _ in self?.onRecord?() }
        editar.click.addHandler { [weak self] _, _ in
            guard let self, let macro = self.selected() else { return }
            self.setDraft(macro)
        }
        borrar.click.addHandler { [weak self] _, _ in
            guard let self, let macro = self.selected() else { return }
            self.onDelete?(macro)
        }
        let save = Button()
        save.content = L("Guardar")
        let close = Button()
        close.content = L("Cerrar")

        AutomationProperties.setAutomationId(list, "Macros_Lista")
        AutomationProperties.setAutomationId(name, "Macros_Nombre")
        AutomationProperties.setAutomationId(commands, "Macros_Ordenes")
        AutomationProperties.setAutomationId(save, "Macros_Guardar")
        AutomationProperties.setAutomationId(play, "Macros_Reproducir")
        play.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            guard let macro = self.selected() else { return }
            self.onPlay?(macro)
        }

        // ── Simple mode area ──
        simpleArea.spacing = 8
        simpleArea.children.append(commands)

        // ── Advanced mode area ──
        advancedArea.spacing = 8
        advancedArea.visibility = .collapsed

        stepList.minWidth = 420
        for k in Self.stepKinds { stepKind.items.append(Self.kindTitle(k)) }
        stepKind.selectedIndex = 0

        stepText.header = L("Orden")
        stepText.minWidth = 420
        stepText.fontFamily = FontFamily("Consolas")
        stepSeconds.header = L("Tiempo (s)")
        stepSeconds.minWidth = 160

        stepEditArea.spacing = 6
        stepEditArea.visibility = .collapsed
        stepEditArea.children.append(stepKind)
        stepEditArea.children.append(stepText)
        stepEditArea.children.append(stepSeconds)

        let stepAdd = Button()
        stepAdd.content = L("Añadir paso")
        let stepDelete = Button()
        stepDelete.content = L("Eliminar paso")
        let stepUp = Button()
        stepUp.content = "↑"
        let stepDown = Button()
        stepDown.content = "↓"

        let stepButtons = StackPanel()
        stepButtons.orientation = .horizontal
        stepButtons.spacing = 8
        for btn in [stepAdd, stepDelete, stepUp, stepDown] { stepButtons.children.append(btn) }

        advancedArea.children.append(stepList)
        advancedArea.children.append(stepButtons)
        advancedArea.children.append(stepEditArea)

        // ── Mode toggle ──
        modoAvanzado.content = L("Pasos avanzados →")

        save.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            if self.advancedModeActive { self.saveCurrentStep() }
            let n = self.name.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var macro = self.original ?? Macro(name: n)
            macro.name = n
            macro.confirm = self.confirmar.isChecked == true
            if self.advancedModeActive || !self.stepsAreEditable {
                macro.steps = self.draftSteps
            } else {
                let lines = self.commands.text.split(whereSeparator: \.isNewline).map(String.init)
                macro.steps = Macro.recorded(lines)
            }
            self.onSave?(macro)
        }
        close.click.addHandler { [weak self] _, _ in self?.onClose?() }

        modoAvanzado.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            if self.advancedModeActive {
                self.saveCurrentStep()
                self.switchToSimple()
            } else {
                if self.stepsAreEditable {
                    let lines = self.commands.text.split(whereSeparator: \.isNewline).map(String.init)
                    self.draftSteps = Macro.recorded(lines)
                }
                self.rebuildStepList()
                self.switchToAdvanced()
            }
        }

        stepList.selectionChanged.addHandler { [weak self] _, _ in
            guard let self, !self.rebuildingStepList else { return }
            self.selectedStepIndex = Int(self.stepList.selectedIndex)
            self.loadStepIntoEditor()
        }

        stepKind.selectionChanged.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.updateStepEditFields()
        }

        stepAdd.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.saveCurrentStep()
            let insertAt = self.draftSteps.isEmpty ? 0 : min(self.selectedStepIndex + 1, self.draftSteps.count)
            self.draftSteps.insert(MacroStep(kind: .send, text: "", seconds: 0), at: insertAt)
            self.selectedStepIndex = insertAt
            self.rebuildStepList()
        }

        stepDelete.click.addHandler { [weak self] _, _ in
            guard let self, self.draftSteps.indices.contains(self.selectedStepIndex) else { return }
            self.draftSteps.remove(at: self.selectedStepIndex)
            self.selectedStepIndex = max(0, self.selectedStepIndex - 1)
            self.rebuildStepList()
        }

        stepUp.click.addHandler { [weak self] _, _ in
            guard let self, self.selectedStepIndex > 0 else { return }
            self.saveCurrentStep()
            self.draftSteps.swapAt(self.selectedStepIndex, self.selectedStepIndex - 1)
            self.selectedStepIndex -= 1
            self.rebuildStepList()
        }

        stepDown.click.addHandler { [weak self] _, _ in
            guard let self, self.selectedStepIndex < self.draftSteps.count - 1 else { return }
            self.saveCurrentStep()
            self.draftSteps.swapAt(self.selectedStepIndex, self.selectedStepIndex + 1)
            self.selectedStepIndex += 1
            self.rebuildStepList()
        }

        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.spacing = 8
        for accion in [play, editar, borrar, nueva, grabar] { acciones.children.append(accion) }
        for control in [title as FrameworkElement, list, acciones, name, modoAvanzado,
                        simpleArea, advancedArea, confirmar, save, close] {
            form.children.append(control)
        }
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.visibility = .collapsed
    }

    func show(_ library: MacroLibrary, selected id: Macro.ID? = nil) {
        self.library = library
        list.items.clear()
        for macro in library.macros { list.items.append(macro.name) }
        play.isEnabled = !library.macros.isEmpty
        editar.isEnabled = play.isEnabled
        borrar.isEnabled = play.isEnabled
        list.selectedIndex = library.macros.isEmpty ? -1 : Int32(library.macros.firstIndex { $0.id == id } ?? 0)
    }

    private func selected() -> Macro? {
        let index = Int(list.selectedIndex)
        guard library.macros.indices.contains(index) else { return nil }
        return library.macros[index]
    }

    private func setDraft(_ macro: Macro) {
        original = macro
        name.text = macro.name
        confirmar.isChecked = macro.confirm
        let lines = macro.lines
        stepsAreEditable = Macro.recorded(lines) == macro.steps
        draftSteps = macro.steps
        if stepsAreEditable {
            commands.text = lines.joined(separator: "\n")
            commands.isReadOnly = false
            commands.header = L("Una orden por línea")
            switchToSimple()
        } else {
            rebuildStepList()
            switchToAdvanced()
        }
    }

    func recorded(_ lines: [String]) {
        clearDraft()
        commands.text = lines.joined(separator: "\n")
    }

    func clearDraft() {
        original = nil
        stepsAreEditable = true
        advancedModeActive = false
        draftSteps = []
        selectedStepIndex = -1
        name.text = ""
        commands.text = ""
        commands.isReadOnly = false
        commands.header = L("Una orden por línea")
        confirmar.isChecked = false
        switchToSimple()
    }

    // MARK: - Advanced editor helpers

    private func switchToSimple() {
        advancedModeActive = false
        simpleArea.visibility = .visible
        advancedArea.visibility = .collapsed
        modoAvanzado.content = L("Pasos avanzados →")
    }

    private func switchToAdvanced() {
        advancedModeActive = true
        simpleArea.visibility = .collapsed
        advancedArea.visibility = .visible
        modoAvanzado.content = L("← Órdenes simples")
    }

    private func rebuildStepList() {
        rebuildingStepList = true
        stepList.items.clear()
        for (i, step) in draftSteps.enumerated() {
            stepList.items.append("\(i + 1): \(Self.stepSummary(step))")
        }
        if draftSteps.isEmpty {
            selectedStepIndex = -1
            stepList.selectedIndex = -1
        } else {
            let newIdx = max(0, min(selectedStepIndex, draftSteps.count - 1))
            selectedStepIndex = newIdx
            stepList.selectedIndex = Int32(newIdx)
        }
        rebuildingStepList = false
        loadStepIntoEditor()
    }

    private func loadStepIntoEditor() {
        guard draftSteps.indices.contains(selectedStepIndex) else {
            stepEditArea.visibility = .collapsed
            return
        }
        stepEditArea.visibility = .visible
        let step = draftSteps[selectedStepIndex]
        if let idx = Self.stepKinds.firstIndex(of: step.kind) {
            stepKind.selectedIndex = Int32(idx)
        }
        stepText.text = step.text
        stepSeconds.text = step.kind == .send ? "" : String(step.seconds)
        updateStepEditFields()
    }

    private func saveCurrentStep() {
        guard advancedModeActive, draftSteps.indices.contains(selectedStepIndex) else { return }
        let idx = Int(stepKind.selectedIndex)
        guard Self.stepKinds.indices.contains(idx) else { return }
        let kind = Self.stepKinds[idx]
        let text = stepText.text
        let secs = Double(stepSeconds.text) ?? MacroStep.defaultTimeout
        draftSteps[selectedStepIndex] = MacroStep(kind: kind, text: text, seconds: secs)
    }

    private func updateStepEditFields() {
        let idx = Int(stepKind.selectedIndex)
        guard Self.stepKinds.indices.contains(idx) else { return }
        let kind = Self.stepKinds[idx]
        stepText.isEnabled = kind == .send || kind == .text
        stepText.header = kind == .text ? L("Expresión regular") : L("Orden")
        stepSeconds.isEnabled = kind != .send
        stepSeconds.header = kind == .pause ? L("Pausa (s)") : L("Tiempo (s)")
        if kind == .send { stepSeconds.text = "" }
        if kind == .prompt || kind == .pause { stepText.text = "" }
    }
}
