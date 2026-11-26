import NetDeckCore
import WinUI

/// Menú de la barra «+» y submenú de cada carpeta.
final class MenuNuevo {
    let flyout = Flyout()
    private let menu = StackPanel()
    private let submenu = StackPanel()
    private var estilo = EstiloMac(tema: nil)
    private var carpeta: String?
    /// Cuando el menú ya se ha cerrado (WinUI devuelve entonces el foco al botón «+»).
    var alCerrar: (() -> Void)?

    init() {
        flyout.closed.addHandler { [weak self] _, _ in self?.alCerrar?() }
        flyout.placement = .bottomEdgeAlignedRight
        let presentador = Style(TypeName(name: "Microsoft.UI.Xaml.Controls.FlyoutPresenter", kind: .metadata))
        presentador.setters.append(Setter(FrameworkElement.maxWidthProperty, 690.0))
        flyout.flyoutPresenterStyle = presentador
        let contenido = StackPanel()
        contenido.orientation = .horizontal
        contenido.spacing = 1
        for panel in [menu, submenu] {
            panel.minWidth = 250
            panel.maxWidth = 310
            panel.padding = Thickness(left: 6, top: 6, right: 6, bottom: 6)
            panel.spacing = 1
            contenido.children.append(panel)
        }
        submenu.verticalAlignment = .top
        flyout.content = contenido
    }

    func preparar(estilo: EstiloMac, perfiles: [SessionProfile], favoritas: [String],
                 inicio: String, grupos: [(name: String, profiles: [SessionProfile])],
                 conectar: @escaping () -> Void, local: @escaping () -> Void,
                 nueva: @escaping (SessionProfile.Transport) -> Void,
                 listas: @escaping () -> Void,
                 abrir: @escaping (SessionProfile) -> Void,
                 abrirGrupo: @escaping (String, [SessionProfile]) -> Void) {
        self.estilo = estilo
        menu.background = estilo.barra
        submenu.background = estilo.barra
        menu.children.clear()
        submenu.children.clear()
        submenu.visibility = .collapsed
        carpeta = nil

        menu.children.append(fila(L("Conectar / Salto…"), Glifo.conectar, tecla: L("Ctrl+Mayús+K"), accion: conectar))
        menu.children.append(fila(L("Terminal local"), Glifo.terminal, tecla: L("Ctrl+Mayús+T"), accion: local))
        menu.children.append(separador())
        menu.children.append(fila(L("Nueva sesión…"), Glifo.mas) { nueva(.ssh) })
        menu.children.append(fila(L("Nueva sesión SFTP…"), Glifo.carpeta) { nueva(.sftp) })
        menu.children.append(fila(L("Nueva sesión serie…"), Glifo.serie) { nueva(.serial) })
        menu.children.append(fila(L("Listas de equipos…"), Glifo.lista, tecla: L("Ctrl+Mayús+L"), accion: listas))

        let porNombre = Dictionary(perfiles.map { ($0.name, $0) }, uniquingKeysWith: { primero, _ in primero })
        let fijas = favoritas.compactMap { porNombre[$0] }
        let inicioSolo = favoritas.contains(inicio) ? nil : porNombre[inicio]
        if !fijas.isEmpty || inicioSolo != nil {
            menu.children.append(separador())
            menu.children.append(titulo(L("Favoritas")))
            if let inicioSolo {
                menu.children.append(fila(inicioSolo.name, Glifo.encendido, tecla: L("al arrancar"), aviso: true) { abrir(inicioSolo) })
            }
            let filas = StackPanel()
            filas.spacing = 1
            for perfil in fijas {
                filas.children.append(fila(perfil.name, perfil.name == inicio ? Glifo.encendido : Glifo.estrella,
                                           tecla: destino(perfil), aviso: true) { abrir(perfil) })
            }
            if !fijas.isEmpty { menu.children.append(scroll(filas, alto: min(Double(fijas.count), 6.5) * 27)) }
        }

        let arbol = grupos.map { (name: $0.name, items: $0.profiles) }
        let carpetas = GroupTree.folders(arbol)
        if !carpetas.isEmpty {
            menu.children.append(separador())
            menu.children.append(titulo(L("Grupos")))
            let filas = StackPanel()
            filas.spacing = 1
            let conjunto = Set(favoritas)
            for f in carpetas {
                let sesiones = GroupTree.items(under: f.path, in: arbol)
                let mostrar = { [weak self] in
                    self?.mostrarGrupo(f.path, nombre: f.name, sesiones: sesiones, favoritas: conjunto,
                                       abrir: abrir, abrirGrupo: abrirGrupo)
                }
                let boton = fila(L(nombre: f.name), Glifo.carpeta, tecla: "\(f.count) ›", sangria: f.depth,
                                 cerrar: false) { mostrar() }
                AutomationProperties.setName(boton, L(nombre: f.name))
                boton.pointerEntered.addHandler { _, _ in mostrar() }
                filas.children.append(boton)
            }
            menu.children.append(scroll(filas, alto: min(Double(carpetas.count), 9.5) * 27))
        }
    }

    private func mostrarGrupo(_ path: String, nombre: String, sesiones: [SessionProfile], favoritas: Set<String>,
                              abrir: @escaping (SessionProfile) -> Void, abrirGrupo: @escaping (String, [SessionProfile]) -> Void) {
        guard carpeta != path else { return }
        carpeta = path
        submenu.children.clear()
        submenu.children.append(titulo(L(nombre: nombre)))
        let todas = fila(L("Abrir todas"), Glifo.dividir, tecla: "\(sesiones.count)") { abrirGrupo(path, sesiones) }
        ToolTipService.setToolTip(todas, L("Abrir las \(sesiones.count) (si son varias, en la vista dividida)"))
        submenu.children.append(todas)
        submenu.children.append(separador())
        let filas = StackPanel()
        filas.spacing = 1
        for perfil in sesiones {
            let fav = favoritas.contains(perfil.name)
            filas.children.append(fila(perfil.name, fav ? Glifo.estrella : icono(perfil),
                                       tecla: destino(perfil), aviso: fav) { abrir(perfil) })
        }
        submenu.children.append(scroll(filas, alto: min(Double(sesiones.count), 12.5) * 27))
        submenu.visibility = .visible
    }

    private func destino(_ perfil: SessionProfile) -> String {
        perfil.user.map { "\($0)@\(perfil.endpoint.host)" } ?? perfil.endpoint.host
    }

    private func icono(_ perfil: SessionProfile) -> String {
        switch perfil.transport {
        case .ssh: perfil.proxyJump.isEmpty ? Glifo.terminal : Glifo.salto
        case .telnet: Glifo.red
        case .sftp: Glifo.carpeta
        case .ftp: Glifo.disco
        case .serial: Glifo.serie
        case .local: Glifo.terminal
        }
    }

    private func scroll(_ contenido: StackPanel, alto: Double) -> ScrollViewer {
        let visor = ScrollViewer()
        visor.content = contenido
        visor.height = alto
        visor.verticalScrollBarVisibility = .auto
        visor.horizontalScrollBarVisibility = .disabled
        return visor
    }

    private func titulo(_ texto: String) -> TextBlock {
        let etiqueta = EstiloMac.letra(texto.uppercased(), tamano: 9.5, peso: 700, color: estilo.apagado)
        etiqueta.margin = Thickness(left: 10, top: 2, right: 10, bottom: 3)
        return etiqueta
    }

    private func separador() -> Border {
        let barra = Border()
        barra.background = estilo.panel
        barra.height = 1
        barra.margin = Thickness(left: 6, top: 4, right: 6, bottom: 4)
        return barra
    }

    private func fila(_ texto: String, _ glifo: String, tecla: String? = nil, aviso: Bool = false, sangria: Int = 0,
                      cerrar: Bool = true, accion: @escaping () -> Void) -> Button {
        let boton = Button()
        estilo.plano(boton)
        boton.height = 26
        boton.padding = Thickness(left: 10 + Double(sangria) * 14, top: 0, right: 10, bottom: 0)
        let fila = Grid()
        for unidad in [GridUnitType.auto, .star, .auto] {
            let columna = ColumnDefinition()
            columna.width = GridLength(value: 1, gridUnitType: unidad)
            fila.columnDefinitions.append(columna)
        }
        let icono = EstiloMac.icono(glifo, tamano: 11, color: aviso ? estilo.aviso : estilo.acento2)
        icono.width = 16
        fila.children.append(icono)
        let nombre = EstiloMac.letra(texto, tamano: 12, color: estilo.texto)
        nombre.margin = Thickness(left: 9, top: 0, right: 16, bottom: 0)
        Grid.setColumn(nombre, 1)
        fila.children.append(nombre)
        if let tecla {
            let etiqueta = EstiloMac.letra(tecla, tamano: 10.5, color: estilo.apagado)
            etiqueta.maxWidth = 195
            Grid.setColumn(etiqueta, 2)
            fila.children.append(etiqueta)
        }
        boton.content = fila
        let normal = estilo.transparente
        let resaltado = estilo.acento(alfa: 0.14)
        boton.pointerEntered.addHandler { origen, _ in (origen as? Button)?.background = resaltado }
        boton.pointerExited.addHandler { origen, _ in (origen as? Button)?.background = normal }
        boton.click.addHandler { [weak self] _, _ in
            if cerrar { try? self?.flyout.hide() }
            accion()
        }
        return boton
    }
}
