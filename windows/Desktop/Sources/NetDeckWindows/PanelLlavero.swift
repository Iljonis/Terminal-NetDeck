import Foundation
import NetDeckCore
import WinUI

/// Ajustes → Contraseñas → Gestionar, como `PasswordSettings`/`CredentialEditorSheet` del Mac: las credenciales del
/// Llavero de Windows (con nombre y de usuario y equipo), dónde se usan, renombrar (y sus asignaciones), cambiar la
/// contraseña repitiéndola, desbloquear tras un fallo y borrar.
final class PanelLlavero {
    let view = ScrollViewer()
    var onClose: (() -> Void)?
    var enqueue: (@escaping () -> Void) -> Void = { $0() }
    /// Los nombres de las credenciales con nombre (para los selectores de sesiones, botones y listas).
    var onNombres: (([String]) -> Void)?
    /// «Se usa en: …» de una credencial, o nil si no la usa nada.
    var usoDe: ((CredentialRef) -> String?)?
    /// Tras renombrar: actualizar la predeterminada y recargar sesiones y botones.
    var onRenombrada: ((CredentialRef, CredentialRef) -> Void)?
    /// La sigue usando una sesión (o un ssh_config que no se pudo leer): no se borra la entrada anterior.
    var sigueEnUso: ((CredentialRef) -> Bool)?
    var onEstado: ((String) -> Void)?
    var ledger: CredentialLedger?
    var demo = false
    private var demoCuentas: Set<CredentialRef> = []
    private var turno = 0
    private var ocupado = false

    private let lista = ComboBox()
    private let nueva = Button()
    private let tipo = ComboBox()
    private let nombre = TextBox()
    private let usuario = TextBox()
    private let equipo = TextBox()
    private let clave = PasswordBox()
    private let repetir = PasswordBox()
    private let aviso = TextBlock()
    private let pie = TextBlock()
    private let usoTexto = TextBlock()
    private let guardar = Button()
    private let desbloquear = Button()
    private let restablecer = Button()
    private let borrar = Button()
    private var cuentas: [CredentialRef] = []
    private var origen: CredentialRef?
    private var pendienteBorrar: CredentialRef?

    init() {
        let form = StackPanel()
        form.spacing = 8
        form.maxWidth = 600
        form.horizontalAlignment = .left
        form.margin = Thickness(left: 8, top: 4, right: 8, bottom: 8)

        let titulo = TextBlock()
        titulo.text = L("Llavero de Windows")
        titulo.fontSize = 20

        lista.minWidth = 340
        lista.header = L("Credencial")
        nueva.content = L("Nueva…")
        nueva.verticalAlignment = .bottom
        let filaLista = StackPanel()
        filaLista.orientation = .horizontal
        filaLista.spacing = 8
        filaLista.children.append(lista)
        filaLista.children.append(nueva)

        tipo.header = L("Tipo")
        tipo.minWidth = 220
        tipo.items.append(L("Con nombre"))
        tipo.items.append(L("Usuario y equipo"))
        tipo.selectedIndex = 0
        nombre.header = L("Nombre")
        nombre.placeholderText = L("Por ejemplo: Red principal")
        usuario.header = L("Usuario")
        equipo.header = L("Equipo")
        equipo.placeholderText = "core-01"
        for campo in [nombre, usuario, equipo] { campo.minWidth = 340 }
        clave.minWidth = 340
        repetir.minWidth = 340
        repetir.header = L("Repítela")
        aviso.textWrapping = .wrap
        pie.opacity = 0.6
        pie.fontSize = 11.5
        pie.textWrapping = .wrap
        usoTexto.opacity = 0.75
        usoTexto.textWrapping = .wrap

        guardar.content = L("Guardar")
        desbloquear.content = L("Desbloquear")
        restablecer.content = L("Restablecer pendiente")
        ToolTipService.setToolTip(restablecer, L("Úsalo sólo si el login pendiente ya terminó. No cambia la contraseña guardada."))
        borrar.content = L("Borrar")
        let recargar = Button()
        recargar.content = L("Recargar lista")
        let cerrar = Button()
        cerrar.content = L("Cerrar")

        AutomationProperties.setAutomationId(lista, "Llavero_Lista")
        AutomationProperties.setAutomationId(nombre, "Llavero_Nombre")
        AutomationProperties.setAutomationId(guardar, "Llavero_Guardar")
        AutomationProperties.setAutomationId(borrar, "Llavero_Borrar")
        AutomationProperties.setAutomationId(desbloquear, "Llavero_Desbloquear")

        lista.selectionChanged.addHandler { [weak self] _, _ in self?.cargarElegida() }
        nueva.click.addHandler { [weak self] _, _ in self?.empezarNueva() }
        tipo.selectionChanged.addHandler { [weak self] _, _ in self?.actualizarCampos() }
        for caja in [nombre, usuario, equipo] { caja.textChanged.addHandler { [weak self] _, _ in self?.validar() } }
        for caja in [clave, repetir] { caja.passwordChanged.addHandler { [weak self] _, _ in self?.validar() } }
        guardar.click.addHandler { [weak self] _, _ in self?.guardarCredencial() }
        desbloquear.click.addHandler { [weak self] _, _ in self?.desbloquearElegida() }
        restablecer.click.addHandler { [weak self] _, _ in
            guard let self, let ref = origen else { return }
            ledger?.reset(ref)
            cargarElegida()
        }
        borrar.click.addHandler { [weak self] _, _ in self?.borrarElegida() }
        recargar.click.addHandler { [weak self] _, _ in self?.reload(cuenta: self?.origen) }
        cerrar.click.addHandler { [weak self] _, _ in self?.onClose?() }

        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.spacing = 8
        acciones.margin = Thickness(left: 0, top: 8, right: 0, bottom: 0)
        for b in [guardar, desbloquear, restablecer, borrar, recargar, cerrar] { acciones.children.append(b) }

        for item in [titulo as FrameworkElement, filaLista, tipo, nombre, usuario, equipo, pie, clave, repetir, aviso,
                     usoTexto, acciones] {
            form.children.append(item)
        }
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
    }

    /// `cuenta`: el nombre de una credencial con nombre que elegir; `nueva`: empezar una con nombre.
    func mostrar(cuenta: String?, nueva: Bool) {
        reload(cuenta: cuenta.map { CredentialRef.named($0) }, nueva: nueva)
    }

    func reload(cuenta: CredentialRef? = nil, nueva: Bool = false, mensaje: String? = nil) {
        pendienteBorrar = nil
        turno += 1
        let pedido = turno
        if demo {
            cargar(Array(demoCuentas), cuenta: cuenta, nueva: nueva, mensaje: mensaje)
            return
        }
        Task { [weak self] in
            do {
                let todas = try await KeychainStore().accountsInBackground().filter { $0.account != "-" }
                self?.enqueue { [weak self] in
                    guard let self, self.turno == pedido else { return }
                    self.cargar(todas, cuenta: cuenta, nueva: nueva, mensaje: mensaje)
                }
            } catch {
                let motivo = error.localizedDescription
                self?.enqueue { [weak self] in
                    guard let self, self.turno == pedido else { return }
                    self.aviso.text = motivo
                }
            }
        }
    }

    private func cargar(_ todas: [CredentialRef], cuenta: CredentialRef?, nueva: Bool, mensaje: String?) {
        // (primero las de nombre, como en el Mac; luego las de usuario y equipo)
        cuentas = todas.sorted {
            ($0.service == .named ? 0 : 1, $0.account.lowercased()) < ($1.service == .named ? 0 : 1, $1.account.lowercased())
        }
        lista.items.clear()
        for ref in cuentas { lista.items.append(ref.service == .named ? ref.account : L("\(ref.account) (equipo)")) }
        if nueva || cuentas.isEmpty {
            empezarNueva()
        } else {
            lista.selectedIndex = Int32(cuenta.flatMap { cuentas.firstIndex(of: $0) } ?? 0)
            cargarElegida()
        }
        if let mensaje { aviso.text = mensaje }
        onNombres?(cuentas.filter { $0.service == .named }.map(\.account))
    }

    private func empezarNueva() {
        origen = nil
        lista.selectedIndex = -1
        tipo.selectedIndex = 0
        for caja in [nombre, usuario, equipo] { caja.text = "" }
        limpiarClaves()
        usoTexto.text = ""
        aviso.text = ""
        actualizarCampos()
    }

    private func cargarElegida() {
        let i = Int(lista.selectedIndex)
        guard cuentas.indices.contains(i) else { return }
        let ref = cuentas[i]
        origen = ref
        pendienteBorrar = nil
        tipo.selectedIndex = ref.service == .named ? 0 : 1
        nombre.text = ref.service == .named ? ref.account : ""
        if ref.service == .device, let at = ref.account.lastIndex(of: "@") {
            usuario.text = String(ref.account[..<at])
            equipo.text = String(ref.account[ref.account.index(after: at)...])
        } else {
            usuario.text = ""
            equipo.text = ref.service == .device ? ref.account : ""
        }
        limpiarClaves()
        aviso.text = ""
        usoTexto.text = usoDe?(ref) ?? L("Sin usar")
        actualizarCampos()
    }

    private func limpiarClaves() {
        clave.password = ""
        repetir.password = ""
    }

    private var destino: CredentialRef {
        tipo.selectedIndex == 0
            ? .named(nombre.text.trimmingCharacters(in: .whitespacesAndNewlines))
            : .device(usuario.text.trimmingCharacters(in: .whitespacesAndNewlines),
                      equipo.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func actualizarCampos() {
        let conNombre = tipo.selectedIndex == 0
        tipo.visibility = origen == nil ? .visible : .collapsed         // (el tipo no se cambia al editar)
        nombre.visibility = conNombre ? .visible : .collapsed
        usuario.visibility = conNombre ? .collapsed : .visible
        equipo.visibility = conNombre ? .collapsed : .visible
        clave.header = origen == nil ? L("Contraseña") : L("Contraseña nueva (opcional)")
        var nota = conNombre
            ? L("Al renombrarla se actualizan sus asignaciones en sesiones, grupos, botones, listas y la predeterminada.")
            : L("La cuenta propia corresponde a ese usuario y equipo. Para contraseñas distintas según el servicio, usa credenciales con nombre.")
        if origen != nil {
            nota += " " + L("Deja ambos campos vacíos para conservar la contraseña. Renombrar conserva también su bloqueo por fallo.")
        }
        pie.text = nota
        let bloqueada = origen.map { ledger?.isBlocked($0) ?? false } ?? false
        var probando = false
        if let ref = origen, case .probing = ledger?.state(of: ref) { probando = true }
        desbloquear.visibility = bloqueada ? .visible : .collapsed
        restablecer.visibility = !bloqueada && probando ? .visible : .collapsed
        borrar.isEnabled = origen != nil
        validar()
    }

    private func validar() {
        let primera = clave.password, segunda = repetir.password
        if !segunda.isEmpty, primera != segunda {
            aviso.text = L("No coinciden")
        } else if aviso.text == L("No coinciden") {
            aviso.text = ""
        }
        let referencia = (try? CredentialValidation.validateReference(destino)) != nil
        let valida = referencia && primera == segunda && (origen != nil || !primera.isEmpty)
            && (origen != destino || !primera.isEmpty)
        guardar.isEnabled = valida && !ocupado
    }

    // MARK: - acciones (como `guardarCredencial` del Mac)

    private func guardarCredencial() {
        let objetivo = destino, fuente = origen
        if let problema = Self.problemaDeReferencia(objetivo) {
            aviso.text = problema
            return
        }
        let contrasena = clave.password.isEmpty ? nil : clave.password
        limpiarClaves()
        if demo {
            if let fuente { demoCuentas.remove(fuente) }
            demoCuentas.insert(objetivo)
            reload(cuenta: objetivo, mensaje: L("Guardada ✓ (\(objetivo.account))"))
            return
        }
        ocupado = true
        aviso.text = L("Guardando…")
        let ledger = self.ledger
        let renombrada: @Sendable () -> Void = { [weak self] in
            guard let fuente else { return }
            self?.enqueue { [weak self] in self?.onRenombrada?(fuente, objetivo) }
        }
        let sigue: @Sendable (CredentialRef) async -> Bool = { [weak self] ref in
            await withCheckedContinuation { c in
                guard let self else { c.resume(returning: true); return }
                self.enqueue { [weak self] in c.resume(returning: self?.sigueEnUso?(ref) ?? true) }
            }
        }
        Task { [weak self] in
            let resultado: Result<String, Error>
            do {
                resultado = .success(try await Self.guardar(from: fuente, to: objetivo, password: contrasena,
                                                            ledger: ledger, sigueEnUso: sigue, renombrada: renombrada))
            } catch {
                resultado = .failure(error)
            }
            self?.enqueue { [weak self] in
                guard let self else { return }
                ocupado = false
                switch resultado {
                case .success(let mensaje): reload(cuenta: objetivo, mensaje: mensaje)
                case .failure(let error):
                    aviso.text = error.localizedDescription
                    validar()
                }
            }
        }
    }

    private static func problemaDeReferencia(_ ref: CredentialRef) -> String? {
        do { try CredentialValidation.validateReference(ref); return nil } catch { return error.localizedDescription }
    }

    private static func guardar(from source: CredentialRef?, to target: CredentialRef, password: String?,
                                ledger: CredentialLedger?, sigueEnUso: @Sendable (CredentialRef) async -> Bool,
                                renombrada: @Sendable () -> Void) async throws -> String {
        try CredentialValidation.validateReference(target)
        if let password { try CredentialValidation.validate(password, for: target) }
        let store = KeychainStore()
        guard let source else {
            guard let password else { throw KeychainError(message: L("la contraseña está vacía")) }
            try await store.createInBackground(password, for: target)
            ledger?.reset(target)
            return L("Guardada ✓ (\(target.account))")
        }
        if source == target {
            if let password {
                try await store.saveInBackground(password, for: target)
                ledger?.reset(target)
            }
            return L("Guardada ✓ (\(target.account))")
        }
        if let ledger, case .probing = ledger.state(of: source) {
            throw KeychainError(message: L("Espera a que termine la autenticación pendiente antes de renombrar"))
        }
        _ = try await CredentialRenamer.renameInBackground(from: source, to: target, password: password, store: store) {
            guard ledger?.copyFailure(from: source, to: target) ?? true else {
                throw KeychainError(message: L("Espera a que termine la autenticación pendiente antes de renombrar"))
            }
        }
        if password != nil { ledger?.reset(target) }
        renombrada()
        if await sigueEnUso(source) {
            return L("Guardada como «\(target.account)». Se conserva «\(source.account)» porque todavía la usa una sesión o configuración externa.")
        }
        do { try await store.deleteInBackground(source) }
        catch { return L("Guardada como «\(target.account)»; no se pudo borrar la entrada anterior: \(error.localizedDescription)") }
        return L("Credencial renombrada: \(target.account)")
    }

    private func desbloquearElegida() {
        guard let ref = origen else { return }
        if ledger?.isBlocked(ref) == true { ledger?.reset(ref) }
        onEstado?(L("🔑 «\(ref.account)» desbloqueada: vuelve a escribirse sola"))
        cargarElegida()
    }

    private func borrarElegida() {
        guard let ref = origen else { return }
        guard pendienteBorrar == ref else {
            pendienteBorrar = ref
            aviso.text = [L("\u{00BF}Borrar \u{00AB}%@\u{00BB} del Llavero de Windows?").replacingOccurrences(of: "%@", with: ref.account),
                          usoDe?(ref), L("Las asignaciones que la usen quedarán sin contraseña guardada."),
                          L("No se puede deshacer.")].compactMap { $0 }.joined(separator: "\n")
            return
        }
        pendienteBorrar = nil
        if demo {
            demoCuentas.remove(ref)
            reload(mensaje: L("Credencial borrada"))
            return
        }
        Task { [weak self] in
            do {
                try await KeychainStore().deleteInBackground(ref)
                self?.enqueue { [weak self] in self?.reload(mensaje: L("Credencial borrada")) }
            } catch {
                let mensaje = error.localizedDescription
                self?.enqueue { [weak self] in self?.aviso.text = mensaje }
            }
        }
    }
}
