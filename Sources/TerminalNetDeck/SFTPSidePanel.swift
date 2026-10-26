import AppKit
import NetDeckCore
import SwiftUI

/// El explorador SFTP al lado del terminal de una pestaña ssh: su propia conexión (ssh -s sftp con la misma ruta, «-F»,
/// saltos y askpass que el terminal: `SFTPPanel.route`), aparte del proceso del terminal. Si falla, se desconecta o se
/// cancela, sólo lo nota el panel; ocultarlo no cierra nada y cerrar la pestaña lo cierra todo (`close`).
@MainActor @Observable
final class SFTPSidePanel {
    let key: String
    var visible: Bool
    var width: Double
    private(set) var browser: RemoteBrowser?
    /// Por qué no hay explorador (la pestaña llega por un salto «a mano»…).
    private(set) var unavailable: String?
    /// Conectar cuando entre el terminal (no a la vez que pide su contraseña).
    var waitingForLogin = false
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let fixedRoute: ConnectionRoute?

    /// `route`: la del explorador ya hecha (sólo las capturas); si no, sale de la del terminal al abrirse.
    init(key: String, layout: SFTPPanelLayout, model: AppModel, route: ConnectionRoute? = nil) {
        self.key = key
        visible = layout.visible
        width = layout.width
        self.model = model
        fixedRoute = route
    }

    var layout: SFTPPanelLayout { SFTPPanelLayout(visible: visible, width: width) }

    /// Su pestaña ha pasado a otra ventana: el explorador, con ella (la conexión sigue).
    func retarget(_ m: AppModel) {
        model = m
        browser?.retarget(m)
    }

    /// El explorador de la ruta del terminal de ahora (si la pestaña ha cambiado de ruta, uno nuevo).
    func prepare(for s: TerminalSession) {
        guard let model else { return }
        do {
            let r = try fixedRoute ?? SFTPPanel.route(for: s.route)
            unavailable = nil
            if let b = browser, b.route == r { return }
            browser?.shutdown()
            browser = RemoteBrowser(route: r, model: model)
        } catch {
            browser?.shutdown()
            browser = nil
            unavailable = error.localizedDescription
        }
    }

    /// Mostrar: conecta ya si el terminal ha entrado (o si se pide con `now`); si no, en cuanto entre.
    func show(in s: TerminalSession, now: Bool = false) {
        visible = true
        prepare(for: s)
        guard let b = browser else { return }
        if now || s.state == .connected || fixedRoute != nil {
            waitingForLogin = false
            if b.state == .idle { b.connect() }
        } else if b.state == .idle {
            waitingForLogin = true
        }
    }

    /// El terminal ha entrado: si se estaba esperando, se conecta.
    func terminalLoggedIn(_ s: TerminalSession) {
        guard visible, waitingForLogin else { return }
        show(in: s, now: true)
    }

    func retry(in s: TerminalSession) {
        browser?.disconnect()
        show(in: s, now: true)
    }

    /// Al cerrar la pestaña: su ssh, sus lecturas y las copias de edición sin nada pendiente.
    func close() {
        browser?.shutdown()
        browser = nil
        waitingForLogin = false
    }
}

/// El panel: el separador que se arrastra (con mínimo y máximo) y el explorador en su versión estrecha.
struct SFTPSidePanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    let session: TerminalSession
    @Bindable var panel: SFTPSidePanel
    /// El ancho de la pestaña (para dejarle sitio al terminal).
    let available: CGFloat
    @Stored private var dragStart: Double?
    @Stored private var hover = false

    var body: some View {
        HStack(spacing: 0) {
            handle
            content
                .frame(width: CGFloat(SFTPPanelLayout.clamp(panel.width, available: Double(available))))
        }
        .onAppear { if session.state == .connected { panel.terminalLoggedIn(session) } }
        .onChange(of: session.state) { if session.state == .connected { panel.terminalLoggedIn(session) } }
    }

    private var handle: some View {
        ZStack {
            SwiftUI.Color(t.bar).opacity(0.001)
            NeonLine(vertical: true, color: hover || dragStart != nil ? t.accent : t.panel)
        }
        .frame(width: 6)
        .contentShape(Rectangle())
        .onHover { inside in
            hover = inside
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { v in
                let start = dragStart ?? SFTPPanelLayout.clamp(panel.width, available: Double(available))
                dragStart = start
                panel.width = SFTPPanelLayout.clamp(start - Double(v.translation.width), available: Double(available))
            }
            .onEnded { _ in
                dragStart = nil
                model.rememberPanel(panel)
            })
        .help(L("Arrastra para cambiar el ancho del explorador"))
    }

    @ViewBuilder private var content: some View {
        if let why = panel.unavailable {
            note(icon: "exclamationmark.triangle", text: why, color: t.warning) {
                NeonButton(title: L("Ocultar"), icon: "sidebar.right") { model.toggleSidePanel(session) }
            }
        } else if let b = panel.browser {
            if b.state == .idle {
                note(icon: "hourglass", text: panel.waitingForLogin ? L("El explorador se conecta cuando entre el terminal")
                                                                     : L("Explorador SFTP sin conectar"), color: t.accent2) {
                    HStack {
                        NeonButton(title: L("Conectar ya"), icon: "bolt.fill", active: true) { panel.show(in: session, now: true) }
                        NeonButton(title: L("Ocultar"), icon: "sidebar.right") { model.toggleSidePanel(session) }
                    }
                }
            } else {
                RemoteBrowserView(session: session, browser: b, compact: true,
                                  onRetry: { panel.retry(in: session) }, onClose: { model.toggleSidePanel(session) })
            }
        }
    }

    private func note(icon: String, text: String, color: RGB, @ViewBuilder buttons: () -> some View) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(SwiftUI.Color(color))
                .shadow(color: SwiftUI.Color(color).opacity(0.7), radius: t.glow(8))
            Text(text).font(t.ui(12.5)).foregroundStyle(SwiftUI.Color(t.text)).multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            buttons()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SwiftUI.Color(t.layer))
    }
}
