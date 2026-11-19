import Foundation
import NetDeckCore
import WinUI

/// Formulario del gestor para el mismo EditableSession que se lee y guarda en el ssh_config.
final class PanelEditorSesion {
    let view = ScrollViewer()
    var onSave: ((EditableSession, String?) -> Bool)?
    var onConnect: ((EditableSession, Bool) -> Void)?
    var onCancel: (() -> Void)?
    var onElegirClave: (() -> URL?)?

    private let form = StackPanel()
    private let name = TextBox()
    private let group = TextBox()
    private let summary = TextBox()
    private let kind = ComboBox()
    private let host = TextBox()
    private let user = TextBox()
    private let port = TextBox()
    private let jump = TextBox()
    private let key = TextBox()
    private let legacy = CheckBox()
    private let credential = ComboBox()
    private let serialDevice = TextBox()
    private let serialPorts = ComboBox()
    private let speed = ComboBox()
    private let bits = ComboBox()
    private let parity = ComboBox()
    private let stop = ComboBox()
    private let tema = ComboBox()
    private let fuente = TextBox()
    private let tamano = TextBox()
    private let interlineado = TextBox()
    private let historial = ComboBox()
    private let retroceso = ComboBox()
    private let meta = ComboBox()
    private let prompt = TextBox()
    private let opcionesSSH = TextBox()
    private let notas = TextBox()
    private let error = TextBlock()
    private let conexion = StackPanel()
    private let saltos = StackPanel()
    private let ssh = StackPanel()
    private let passwords = StackPanel()
    private let serie = StackPanel()
    private let perfil = StackPanel()
    private let extra = StackPanel()
    private var draft = EditableSession(name: "")
    private var original: String?
    private var loading = false
    private let tipos = SessionProfile.Transport.allCases
    private var credenciales: [String] = []
    private var temas: [String] = []
    private var lineas: [Int] = []
    private var puertos: [String] = []

    init() {
        form.spacing = 12
        form.maxWidth = 660
        form.padding = Thickness(left: 20, top: 12, right: 20, bottom: 20)
        for panel in [conexion, saltos, ssh, passwords, serie, perfil, extra] { panel.spacing = 6 }
        view.content = form
        view.verticalScrollBarVisibility = .auto
        view.horizontalScrollBarVisibility = .disabled
        view.visibility = .collapsed
        kind.selectionChanged.addHandler { [weak self] _, _ in self?.kindChanged() }
        serialPorts.selectionChanged.addHandler { [weak self] _, _ in
            guard let self, !loading, puertos.indices.contains(Int(serialPorts.selectedIndex)) else { return }
            serialDevice.text = puertos[Int(serialPorts.selectedIndex)]
        }
        for campo in [opcionesSSH, notas] {
            campo.acceptsReturn = true
            campo.textWrapping = .wrap
            campo.minHeight = 60
        }
        error.textWrapping = .wrap
    }

    func show(_ session: EditableSession, original: String?, estilo: EstiloMac,
              credenciales disponibles: [String], saltos disponiblesSaltos: [String]) {
        loading = true
        defer { loading = false }
        draft = session
        self.original = original
        for panel in [form, conexion, saltos, ssh, passwords, serie, perfil, extra] { panel.children.clear() }

        func seccion(_ titulo: String, en panel: StackPanel) {
            panel.children.append(EstiloMac.letra(titulo, tamano: 10, peso: 700, color: estilo.acento2))
        }
        seccion(L("SESIÓN"), en: form)
        campo(L("Nombre"), name, en: form)
        campo(L("Grupo"), group, en: form)
        campo(L("Descripción"), summary, en: form)
        seccion(L("CONEXIÓN"), en: form)
        cambiarOpciones(kind, tipos.map(\.label), indice: tipos.firstIndex(of: session.kind) ?? 0)
        campo(L("Tipo"), kind, en: form)
        campo(L("Equipo (nombre o IP)"), host, en: conexion)
        campo(L("Usuario"), user, en: conexion)
        campo(L("Puerto"), port, en: conexion)
        let ayudaSalto = disponiblesSaltos.isEmpty ? L("Directo") : disponiblesSaltos.joined(separator: ", ")
        jump.placeholderText = L("Directo")
        ToolTipService.setToolTip(jump, ayudaSalto)
        campo(L("Saltar por"), jump, en: saltos)
        let filaClave = StackPanel()
        filaClave.orientation = .horizontal
        filaClave.spacing = 8
        key.minWidth = 350
        key.header = L("Clave privada")
        filaClave.children.append(key)
        let buscar = boton(L("Elegir…"), estilo: estilo) { [weak self] in
            guard let self, let archivo = onElegirClave?() else { return }
            key.text = AppPaths.tilde(archivo.path)
        }
        buscar.verticalAlignment = .bottom
        filaClave.children.append(buscar)
        ssh.children.append(filaClave)
        legacy.content = L("Equipo antiguo (algoritmos ssh viejos)")
        legacy.isChecked = session.legacy
        ssh.children.append(legacy)

        seccion(L("CONTRASEÑA (LLAVERO)"), en: passwords)
        credenciales = ["", "-"] + disponibles.filter { !$0.isEmpty && $0 != "-" }
        if !credenciales.contains(session.credential) { credenciales.append(session.credential) }
        cambiarOpciones(credential, [L("Heredar"), L("Ninguna (sin la del grupo)")] + credenciales.dropFirst(2),
                         indice: credenciales.firstIndex(of: session.credential) ?? 0)
        campo(L("Contraseña"), credential, en: passwords)

        recargarPuertos()
        serialDevice.placeholderText = "COM3"
        campo(L("Puerto serie"), serialDevice, en: serie)
        let opcionesSerie = StackPanel()
        opcionesSerie.orientation = .horizontal
        opcionesSerie.spacing = 8
        opcionesSerie.children.append(serialPorts)
        opcionesSerie.children.append(boton(L("Volver a buscar puertos"), estilo: estilo) { [weak self] in self?.recargarPuertos() })
        serie.children.append(opcionesSerie)
        cambiarOpciones(speed, SerialLine.speeds.map(String.init), indice: SerialLine.speeds.firstIndex(of: session.serial.speed) ?? 0)
        cambiarOpciones(bits, ["8", "7", "6", "5"], indice: min(3, max(0, 8 - session.serial.dataBits)))
        cambiarOpciones(parity, [L("Ninguna"), L("Par"), L("Impar")], indice: SerialLine.Parity.allCases.firstIndex(of: session.serial.parity) ?? 0)
        cambiarOpciones(stop, ["1", "2"], indice: min(1, max(0, session.serial.stopBits - 1)))
        campo(L("Velocidad"), speed, en: serie)
        campo(L("Bits de datos"), bits, en: serie)
        campo(L("Paridad"), parity, en: serie)
        campo(L("Bits de parada"), stop, en: serie)

        seccion(L("OPCIONES DE SSH (AVANZADO)"), en: extra)
        extra.children.append(opcionesSSH)
        seccion(L("PERFIL"), en: perfil)
        let catalogo = TemasTerminal.disponibles()
        temas = [""] + catalogo.map(\.id)
        var nombresTemas = [L("Heredar")] + catalogo.map(\.name)
        if !temas.contains(session.terminal.theme) {
            temas.append(session.terminal.theme)
            nombresTemas.append(session.terminal.theme)
        }
        cambiarOpciones(tema, nombresTemas, indice: temas.firstIndex(of: session.terminal.theme) ?? 0)
        lineas = [0] + TerminalHistory.options
        if let guardadas = session.terminal.scrollback, !lineas.contains(guardadas) { lineas.append(guardadas) }
        cambiarOpciones(historial, lineas.map { $0 == 0 ? L("Heredar") : TerminalHistory.label($0) },
                        indice: lineas.firstIndex(of: session.terminal.scrollback ?? 0) ?? 0)
        cambiarOpciones(retroceso, [L("Heredar"), L("Envía DEL (^?)"), L("Envía ^H (equipos antiguos, consolas)")],
                         indice: session.terminal.backspaceSendsCtrlH.map { $0 ? 2 : 1 } ?? 0)
        cambiarOpciones(meta, [L("Heredar"), L("Escribe «@», «#», «|»… (teclado español)"), L("Como Meta (Esc + tecla: emacs, readline)")],
                         indice: session.terminal.optionAsMeta.map { $0 ? 2 : 1 } ?? 0)
        campo(L("Tema"), tema, en: perfil)
        for dato in [fuente, tamano, interlineado] { dato.placeholderText = L("Heredar") }
        campo(L("Fuente"), fuente, en: perfil)
        campo(L("Tamaño"), tamano, en: perfil)
        campo(L("Interlineado"), interlineado, en: perfil)
        campo(L("Líneas guardadas"), historial, en: perfil)
        campo(L("Alt"), meta, en: perfil)
        campo(L("Retroceso"), retroceso, en: perfil)
        campo(L("Prompt (regex)"), prompt, en: perfil)

        for panel in [conexion, saltos, ssh, serie, passwords, extra, perfil] { form.children.append(panel) }
        seccion(L("NOTAS"), en: form)
        form.children.append(notas)
        error.text = ""
        error.foreground = estilo.mal
        form.children.append(error)

        let acciones = StackPanel()
        acciones.orientation = .horizontal
        acciones.horizontalAlignment = .right
        acciones.spacing = 8
        acciones.children.append(boton(L("Cancelar"), estilo: estilo) { [weak self] in self?.onCancel?() })
        acciones.children.append(boton(L("Conectar"), estilo: estilo) { [weak self] in self?.conectar(guardar: false) })
        acciones.children.append(boton(L("Guardar"), estilo: estilo) { [weak self] in
            guard let self, let session = leer() else { return }
            _ = onSave?(session, self.original)
        })
        acciones.children.append(boton(L("Guardar y conectar"), estilo: estilo) { [weak self] in self?.conectar(guardar: true) })
        form.children.append(acciones)

        name.text = session.name
        group.text = session.group
        host.text = session.host
        user.text = session.user
        port.text = session.port
        summary.text = session.summary
        jump.text = session.jump
        key.text = session.keyFile
        serialDevice.text = session.serial.device
        fuente.text = session.terminal.fontFamily
        tamano.text = session.terminal.fontSize == 0 ? "" : String(Int(session.terminal.fontSize))
        interlineado.text = session.terminal.lineSpacing == 0 ? "" : String(session.terminal.lineSpacing)
        prompt.text = session.terminal.prompt
        opcionesSSH.text = session.extra.joined(separator: "\n")
        notas.text = session.notes.joined(separator: "\n")
        visibilidad(session.kind)
    }

    func focusName() { _ = try? name.focus(.programmatic) }

    private func campo(_ titulo: String, _ control: Control, en panel: StackPanel) {
        if let t = control as? TextBox { t.header = titulo }
        if let c = control as? ComboBox { c.header = titulo }
        panel.children.append(control)
    }

    private func boton(_ texto: String, estilo: EstiloMac, accion: @escaping () -> Void) -> Button {
        let b = Button()
        b.content = EstiloMac.letra(texto, tamano: 12, peso: 500, color: estilo.texto)
        b.background = estilo.panel
        b.click.addHandler { _, _ in accion() }
        return b
    }

    private func cambiarOpciones(_ combo: ComboBox, _ valores: [String], indice: Int) {
        combo.items.clear()
        for valor in valores { combo.items.append(valor) }
        combo.selectedIndex = Int32(indice)
    }

    private func recargarPuertos() {
        puertos = SerialLine.devices()
        cambiarOpciones(serialPorts, puertos, indice: puertos.firstIndex(of: serialDevice.text) ?? -1)
        serialPorts.placeholderText = L("(elige uno)")
    }

    private func kindChanged() {
        guard !loading, tipos.indices.contains(Int(kind.selectedIndex)) else { return }
        draft.port = port.text
        draft.setKind(tipos[Int(kind.selectedIndex)])
        port.text = draft.port
        visibilidad(draft.kind)
    }

    private func visibilidad(_ tipo: SessionProfile.Transport) {
        conexion.visibility = tipo.isNetwork ? .visible : .collapsed
        saltos.visibility = tipo.isNetwork && tipo != .ftp ? .visible : .collapsed
        let usaSSH = tipo == .ssh || tipo == .sftp
        ssh.visibility = usaSSH ? .visible : .collapsed
        extra.visibility = usaSSH ? .visible : .collapsed
        passwords.visibility = [.ssh, .telnet, .sftp].contains(tipo) ? .visible : .collapsed
        serie.visibility = tipo == .serial ? .visible : .collapsed
        perfil.visibility = [.sftp, .ftp].contains(tipo) ? .collapsed : .visible
    }

    private func conectar(guardar: Bool) {
        guard let session = leer() else { return }
        if guardar, onSave?(session, original) != true { return }
        onConnect?(session, guardar)
    }

    private func leer() -> EditableSession? {
        func texto(_ campo: TextBox) -> String { campo.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        func lineas(_ campo: TextBox) -> [String] {
            campo.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        var s = draft
        s.name = texto(name)
        s.group = texto(group).isEmpty ? "General" : texto(group)
        s.summary = texto(summary)
        s.host = texto(host)
        s.user = texto(user)
        s.port = texto(port)
        s.jump = texto(jump)
        s.keyFile = texto(key)
        s.legacy = legacy.isChecked == true
        s.credential = credenciales[max(0, Int(credential.selectedIndex))]
        s.notes = lineas(notas)
        s.extra = lineas(opcionesSSH)
        if s.kind == .serial {
            s.serial = SerialLine(device: texto(serialDevice).uppercased(), speed: SerialLine.speeds[max(0, Int(speed.selectedIndex))],
                                  dataBits: 8 - max(0, Int(bits.selectedIndex)),
                                  parity: SerialLine.Parity.allCases[max(0, Int(parity.selectedIndex))],
                                  stopBits: max(0, Int(stop.selectedIndex)) + 1)
        }
        s.terminal.theme = temas[max(0, Int(tema.selectedIndex))]
        s.terminal.fontFamily = texto(fuente)
        s.terminal.fontSize = Double(texto(tamano)) ?? (texto(tamano).isEmpty ? 0 : -1)
        s.terminal.lineSpacing = Double(texto(interlineado).replacingOccurrences(of: ",", with: "."))
            ?? (texto(interlineado).isEmpty ? 0 : -1)
        let n = self.lineas[max(0, Int(historial.selectedIndex))]
        s.terminal.scrollback = n == 0 ? nil : n
        s.terminal.backspaceSendsCtrlH = retroceso.selectedIndex > 0 ? retroceso.selectedIndex == 2 : nil
        s.terminal.optionAsMeta = meta.selectedIndex > 0 ? meta.selectedIndex == 2 : nil
        s.terminal.prompt = texto(prompt)
        var prueba = SessionFile()
        prueba.sessions = [s]
        if let problema = prueba.problems().first { error.text = problema; return nil }
        return s
    }
}
