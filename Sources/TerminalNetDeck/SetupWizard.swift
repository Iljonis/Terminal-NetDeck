import AppKit
import NetDeckCore
import Observation
import SwiftUI

/// Asistente de instalación: doble clic en la app (desde el DMG o Descargas) → copiarla a Aplicaciones, elegir temas,
/// fuentes, contraseñas y resaltado. También desde el menú, para volver a elegir.
@MainActor @Observable
final class SetupWizard {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome, place, themes, fonts, passwords, highlight, install
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .welcome: L("Bienvenida")
            case .place: L("Ubicación")
            case .themes: L("Temas")
            case .fonts: L("Fuentes")
            case .passwords: L("Contraseñas")
            case .highlight: L("Resaltado")
            case .install: L("Instalar")
            }
        }
        var icon: String {
            switch self {
            case .welcome: "sparkles"
            case .place: "folder.fill"
            case .themes: "paintpalette.fill"
            case .fonts: "textformat"
            case .passwords: "key.fill"
            case .highlight: "highlighter"
            case .install: "arrow.down.app.fill"
            }
        }
    }

    var step = Step.welcome
    var destination: URL
    /// El tema que se usará (todos vienen con la app: sólo se elige).
    var active: String
    /// El que se ve en la vista previa (al pasar por encima).
    var hovered: String?
    var terminalFont: String
    var uiFont: String
    var fontsToInstall: Set<String> = []
    var sessionAuto: Bool
    var deviceMode: PasswordAutomation.Mode
    var highlight: Bool
    var log: [String] = []
    var running = false
    var finished = false

    let bundleURL = Bundle.main.bundleURL
    let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].contains(where: FileManager.default.fileExists)
    static let userApplications = AppPaths.home.appendingPathComponent("Applications")

    /// Abierta desde fuera de Aplicaciones (DMG, Descargas…): hay que instalarla.
    static var needsInstall: Bool {
        let u = Bundle.main.bundleURL
        return u.pathExtension == "app" && !isInstalled(u)
    }

    /// Nunca se ha visto el asistente en este Mac (las capturas lo saltan con «-asistenteVisto YES»).
    static var firstLaunch: Bool { !UserDefaults.standard.bool(forKey: seenKey) }
    static let seenKey = "asistenteVisto"

    static func isInstalled(_ u: URL) -> Bool {
        let p = u.resolvingSymlinksInPath().path
        return p.hasPrefix("/Applications/") || p.hasPrefix(userApplications.path + "/")
    }

    var isAppBundle: Bool { bundleURL.pathExtension == "app" }
    var needsCopy: Bool { isAppBundle && !Self.isInstalled(bundleURL) }
    var installedApp: URL { destination.appendingPathComponent("Terminal NetDeck.app") }

    init(model: AppModel) {
        destination = FileManager.default.isWritableFile(atPath: "/Applications") ? URL(fileURLWithPath: "/Applications")
                                                                                  : Self.userApplications
        let s = model.settings
        active = model.themes.current.id
        terminalFont = s.fontFamily
        uiFont = s.uiFontFamily
        sessionAuto = s.sessionAutoPassword
        deviceMode = s.devicePasswordMode
        highlight = s.highlightEnabled
    }

    /// El tema con el que se ve el asistente (cambia en vivo al elegir).
    func previewTheme(_ model: AppModel) -> Theme { model.themes.theme(id: active) ?? .builtIn }

    /// Fuentes que recomienda el tema elegido (y las de su grupo).
    func recommendedFonts(_ model: AppModel) -> [String] {
        let th = previewTheme(model)
        let group = model.themes.all.map(\.theme).filter { $0.group == th.group && $0.id != th.id }
        var seen = Set<String>()
        return ([th] + group).flatMap { $0.fonts.prefix(1) }.filter { seen.insert($0).inserted }.prefix(8).map { $0 }
    }

    func run(_ model: AppModel) async {
        running = true
        log = []
        let fm = FileManager.default
        if needsCopy {
            do {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                if fm.fileExists(atPath: installedApp.path) { try fm.removeItem(at: installedApp) }   // (versión anterior)
                try fm.copyItem(at: bundleURL, to: installedApp)
                log.append(L("✓ App instalada en \(AppPaths.tilde(installedApp.path))"))
            } catch {
                log.append(L("✗ No se ha podido copiar la app: \(error.localizedDescription)"))
                running = false
                return
            }
        }
        for f in fontsToInstall.sorted() where !Fonts.isInstalled(f) {
            log.append(L("… fuente «\(f)»"))
            log.append(await Fonts.install(f) ? L("✓ Fuente «\(f)» instalada") : L("✗ Fuente «\(f)»: no se ha podido (Homebrew)"))
        }
        let s = model.settings
        s.sessionAutoPassword = sessionAuto
        s.devicePasswordMode = deviceMode
        s.highlightEnabled = highlight
        s.fontFamily = terminalFont
        s.uiFontFamily = uiFont
        model.selectTheme(active)
        model.applyPasswordModes()
        UserDefaults.standard.set(true, forKey: "configured")
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        log.append(L("✓ Ajustes guardados · tema «\(model.themes.current.name)»"))
        running = false
        finished = true
    }

    /// Abre la instalada (otra instancia) y cierra ésta (la del DMG).
    func launchInstalled() {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: installedApp, configuration: cfg) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

// MARK: - vista

struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Stored private var wizard: SetupWizard?

    var body: some View {
        Group {
            if let w = wizard {
                SetupContent(wizard: w, start: start)
                    .environment(\.theme, w.previewTheme(model))
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard wizard == nil else { return }
            let w = SetupWizard(model: model)
            // (desarrollo: NETDECK_SNAPSHOT_ACTION=setup:3 abre ese paso)
            if let a = ProcessInfo.processInfo.environment["NETDECK_SNAPSHOT_ACTION"], a.hasPrefix("setup:"),
               let n = Int(a.dropFirst(6)), let st = SetupWizard.Step(rawValue: n) { w.step = st }
            wizard = w
        }
    }

    private func start() {
        UserDefaults.standard.set(true, forKey: SetupWizard.seenKey)
        model.showSetup = false
    }
}

struct SetupContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    @Bindable var wizard: SetupWizard
    let start: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            rail
            NeonLine(vertical: true, color: t.panel)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wizard.step.title.uppercased()).font(t.ui(20, .heavy)).tracking(3)
                        .foregroundStyle(SwiftUI.Color(t.accent))
                        .shadow(color: SwiftUI.Color(t.accent).opacity(0.6), radius: t.glow(6))
                    Text(subtitle).font(t.ui(11.5)).foregroundStyle(SwiftUI.Color(t.dim))
                }
                .padding(.horizontal, 28)
                .padding(.top, 36)
                .padding(.bottom, 14)
                ScrollView { page.padding(.horizontal, 28).padding(.bottom, 20) }
                NeonLine(color: t.panel)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SwiftUI.Color(t.background))
        .foregroundStyle(SwiftUI.Color(t.text))
        .tint(SwiftUI.Color(t.accent))
        .preferredColorScheme(t.isLight ? .light : .dark)
        .animation(.easeOut(duration: 0.2), value: wizard.active)
    }

    // MARK: barra de pasos

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Brand().padding(.bottom, 22).padding(.top, 44)
            ForEach(SetupWizard.Step.allCases) { s in
                let current = s == wizard.step, done = s.rawValue < wizard.step.rawValue
                Button { if !wizard.running { wizard.step = s } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: done ? "checkmark.circle.fill" : s.icon)
                            .frame(width: 18)
                            .foregroundStyle(SwiftUI.Color(current ? t.accent : (done ? t.good : t.dim)))
                        Text(s.title).font(t.ui(12.5, current ? .bold : .regular))
                            .foregroundStyle(SwiftUI.Color(current ? t.text : t.dim))
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(SwiftUI.Color(t.panel).opacity(current ? 0.8 : 0)))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(SwiftUI.Color(t.accent)).frame(width: 2).opacity(current ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(UpdateCheck.currentVersion == "0" ? "dev" : "v\(UpdateCheck.currentVersion)").font(t.ui(9.5)).foregroundStyle(SwiftUI.Color(t.dim)).padding(.bottom, 16)
        }
        .padding(.horizontal, 14)
        .frame(width: 230)
        .background(SwiftUI.Color(t.bar).gesture(WindowDragGesture()))
    }

    private var footer: some View {
        HStack {
            if wizard.step == .welcome {
                Button(wizard.needsCopy ? L("Probar sin instalar") : L("Omitir"), action: start).buttonStyle(.plain).font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            }
            Spacer()
            if wizard.step != .welcome, !wizard.finished {
                NeonButton(title: L("Atrás"), icon: "chevron.left") { go(-1) }.disabled(wizard.running)
            }
            if wizard.step == .install {
                if wizard.finished {
                    NeonButton(title: wizard.needsCopy ? L("Abrir Terminal NetDeck") : L("Empezar"), icon: "play.fill",
                               tint: t.good, active: true) {
                        wizard.needsCopy ? wizard.launchInstalled() : start()
                    }
                } else {
                    NeonButton(title: wizard.running ? L("Instalando…") : L("Instalar"), icon: "arrow.down.app.fill", active: true) {
                        Task { await wizard.run(model) }
                    }
                    .disabled(wizard.running)
                }
            } else {
                NeonButton(title: L("Siguiente"), icon: "chevron.right", active: true) { go(1) }
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 64)
    }

    private func go(_ d: Int) {
        if let s = SetupWizard.Step(rawValue: wizard.step.rawValue + d) { wizard.step = s }
    }

    private var subtitle: String {
        switch wizard.step {
        case .welcome: L("Terminal nativo para ingenieros de red")
        case .place: L("Dónde se instala la app")
        case .themes: L("Todos vienen con la app: pasa por encima para verlo, clic para usarlo (se cambia cuando quieras)")
        case .fonts: L("Aparte de los temas: se pueden cambiar cuando quieras en Ajustes → Fuentes")
        case .passwords: L("Siempre en el Llavero de macOS")
        case .highlight: L("Colores en la salida de los equipos, como ChromaTerm")
        case .install: wizard.finished ? L("Listo") : L("Revisa y pulsa «Instalar»")
        }
    }

    // MARK: páginas

    @ViewBuilder private var page: some View {
        switch wizard.step {
        case .welcome: welcome
        case .place: place
        case .themes: themes
        case .fonts: fonts
        case .passwords: passwords
        case .highlight: highlightPage
        case .install: install
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            PixelBanner(text: L("NETDECK"), cell: 13).padding(.top, 10)
            VStack(alignment: .leading, spacing: 9) {
                bullet("bolt.horizontal.fill", L("Sesiones de tu ssh_config, con saltos y contraseña automática"))
                bullet("paintpalette.fill", L("Todas las temáticas incluidas, con vista previa"))
                bullet("highlighter", L("Resaltado de la salida tipo ChromaTerm"))
                bullet("square.grid.2x2.fill", L("MultiExec, pegado seguro y listas por salto"))
            }
            if FileManager.default.fileExists(atPath: AppPaths.netdeck.path) {
                card(L("Configuración existente encontrada"), L("Se respetan el Llavero, el ssh_config, los temas y los ajustes que ya tenías ")
                     + L("(\(model.sessions.profiles.count) sesiones · tema «\(model.themes.current.name)»)."), t.good)
            }
            if !model.sessions.profiles.isEmpty {
                card(L("Sesiones de este Mac"), L("\(model.sessions.profiles.count) sesiones leídas de \(AppPaths.tilde(model.settings.sshConfigURL.path)) ")
                     + L("(y lo que incluye): son las tuyas, la app no trae ninguna."), t.good)
            }
        }
    }

    private var place: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !wizard.isAppBundle {
                card(L("Desde «swift run»"), L("No hay .app que copiar: para instalarla usa ./install.sh (o ./install.sh --dmg). ")
                     + L("Puedes seguir para elegir temas y ajustes."), t.warning)
            } else if !wizard.needsCopy {
                card(L("Ya instalada"), wizard.bundleURL.path, t.good)
            } else {
                choice("/Applications", L("Para todos los usuarios del Mac"), URL(fileURLWithPath: "/Applications"),
                       enabled: FileManager.default.isWritableFile(atPath: "/Applications"))
                choice("~/Applications", L("Sólo para ti"), SetupWizard.userApplications, enabled: true)
                Text(L("Si ya había una versión instalada, se sustituye. Tus temas, ajustes y contraseñas se conservan."))
                    .font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            }
        }
    }

    private var themes: some View {
        VStack(alignment: .leading, spacing: 16) {
            ThemePreview(theme: model.themes.theme(id: wizard.hovered ?? wizard.active) ?? .builtIn)
                .frame(height: 230)
            ThemeGallery(active: wizard.active, select: { wizard.active = $0 }, hover: { wizard.hovered = $0 })
        }
    }

    private var fonts: some View {
        let families = Fonts.monospacedFamilies()
        let rec = wizard.recommendedFonts(model)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                picker(L("Terminal"), $wizard.terminalFont, L("Automática (la del tema)"), families + rec.filter { !families.contains($0) })
                picker(L("Interfaz"), $wizard.uiFont, L("La del tema"), ["system"] + families)
            }
            section(L("RECOMENDADAS POR TUS TEMAS"))
            ForEach(rec, id: \.self) { f in
                let ok = Fonts.isInstalled(f)
                HStack {
                    Image(systemName: ok ? "checkmark.circle.fill" : (wizard.fontsToInstall.contains(f) ? "checkmark.square.fill" : "square"))
                        .foregroundStyle(SwiftUI.Color(ok ? t.good : t.accent))
                    Text(f).font(ok ? .custom(f, size: 14) : t.ui(13))
                    Spacer()
                    Text(ok ? "instalada" : (wizard.brew ? L("se instalará con Homebrew") : L("falta Homebrew")))
                        .font(t.ui(10.5)).foregroundStyle(SwiftUI.Color(t.dim))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 7).fill(SwiftUI.Color(t.panel).opacity(0.5)))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !ok, wizard.brew else { return }
                    if wizard.fontsToInstall.contains(f) { wizard.fontsToInstall.remove(f) } else { wizard.fontsToInstall.insert(f) }
                }
            }
        }
    }

    private var passwords: some View {
        VStack(alignment: .leading, spacing: 14) {
            toggleCard(L("Contraseña de las sesiones automática"),
                       L("Al abrir una sesión (y sus saltos) entra sola, con el askpass de la app. Un solo intento: si falla, ")
                       + L("queda bloqueada 15 min y te la pide en la pestaña."), $wizard.sessionAuto)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("EQUIPOS (ssh / telnet desde una sesión)")).font(t.ui(10, .bold)).tracking(2).foregroundStyle(SwiftUI.Color(t.accent2))
                Picker("", selection: $wizard.deviceMode) {
                    Text(L("Escribirla sola")).tag(PasswordAutomation.Mode.autoType)
                    Text(L("Sugerirla")).tag(PasswordAutomation.Mode.suggest)
                    Text(L("Nada")).tag(PasswordAutomation.Mode.off)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(L("Nunca la de otro usuario: con «ssh root@…» o «Username: pepe», sólo una guardada de ese usuario."))
                    .font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 9).fill(SwiftUI.Color(t.panel).opacity(0.5)))
        }
    }

    private var highlightPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            toggleCard(L("Resaltar la salida"), L("Reglas incluidas (o las tuyas): interfaces, IPs, estados, dBm, errores, prompts…"),
                       $wizard.highlight)
            HighlightPreview(enabled: wizard.highlight)
        }
    }

    private var install: some View {
        VStack(alignment: .leading, spacing: 10) {
            if wizard.log.isEmpty {
                summary(L("Ubicación"), wizard.needsCopy ? AppPaths.tilde(wizard.installedApp.path)
                                                      : L("sin copiar"))
                summary(L("Tema"), wizard.previewTheme(model).name)
                summary(L("Fuentes"), wizard.fontsToInstall.isEmpty ? L("ninguna nueva") : wizard.fontsToInstall.sorted().joined(separator: ", "))
                summary(L("Contraseñas"), L("sesión \(wizard.sessionAuto ? L("automática") : L("a mano")) · equipos: \(modeName)"))
                summary(L("Resaltado"), wizard.highlight ? "sí" : "no")
            } else {
                ForEach(Array(wizard.log.enumerated()), id: \.offset) { _, l in
                    Text(l).font(t.ui(12))
                        .foregroundStyle(SwiftUI.Color(l.hasPrefix("✗") ? t.bad : (l.hasPrefix("✓") ? t.good : t.text)))
                }
                if wizard.running { ProgressView().controlSize(.small).padding(.top, 6) }
            }
        }
    }

    private var modeName: String {
        switch wizard.deviceMode { case .autoType: L("escribirla sola"); case .suggest: L("sugerirla"); case .off: L("nada") }
    }

    // MARK: piezas

    private func section(_ s: String) -> some View {
        HStack {
            Text(s).font(t.ui(10, .bold)).tracking(2.5).foregroundStyle(SwiftUI.Color(t.accent2))
            Rectangle().fill(SwiftUI.Color(t.accent2).opacity(0.25)).frame(height: 1)
        }
    }

    private func bullet(_ icon: String, _ s: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(SwiftUI.Color(t.accent2)).frame(width: 20)
            Text(s).font(t.ui(13))
        }
    }

    private func card(_ title: String, _ body: String, _ c: RGB) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(t.ui(12.5, .bold)).foregroundStyle(SwiftUI.Color(c))
            Text(body).font(t.ui(11.5)).foregroundStyle(SwiftUI.Color(t.text))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(SwiftUI.Color(c).opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(SwiftUI.Color(c).opacity(0.5)))
    }

    private func choice(_ title: String, _ sub: String, _ url: URL, enabled: Bool) -> some View {
        let on = wizard.destination == url
        return HStack(spacing: 12) {
            Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(SwiftUI.Color(t.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(t.ui(13.5, .bold))
                Text(enabled ? sub : L("sin permiso de escritura")).font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 9).fill(SwiftUI.Color(t.panel).opacity(on ? 0.9 : 0.45)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(SwiftUI.Color(t.accent).opacity(on ? 0.8 : 0.15)))
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { wizard.destination = url } }
    }

    private func toggleCard(_ title: String, _ sub: String, _ value: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(t.ui(13.5, .bold))
                Text(sub).font(t.ui(11)).foregroundStyle(SwiftUI.Color(t.dim))
            }
            Spacer()
            Toggle("", isOn: value).toggleStyle(.switch).labelsHidden()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 9).fill(SwiftUI.Color(t.panel).opacity(0.5)))
    }

    private func picker(_ title: String, _ value: Binding<String>, _ auto: String, _ options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(t.ui(10, .bold)).tracking(2).foregroundStyle(SwiftUI.Color(t.accent2))
            Picker("", selection: value) {
                Text(auto).tag("")
                ForEach(options, id: \.self) { Text($0 == "system" ? L("Monoespaciada del sistema") : $0).tag($0) }
            }
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k.uppercased()).font(t.ui(10, .bold)).tracking(2).foregroundStyle(SwiftUI.Color(t.accent2)).frame(width: 130, alignment: .leading)
            Text(v).font(t.ui(12.5))
        }
    }
}

/// Muestra de salida coloreada con las reglas activas y los colores que tocan.
struct HighlightPreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var t
    var enabled = true

    static let sample = """
        admin@core-01> show interfaces terse | match "xe-|ae"
        xe-0/0/0   up   up     inet 192.0.2.1/30
        xe-0/0/1   up   down
        ae0        up   up     inet 192.0.2.5/30   2001:db8::1/64
        core-01#show ip bgp summary
        192.0.2.2   4  65001   1234   1200   Established
        Rx power: -27.80 dBm   Tx power: -2.10 dBm
        CRC errors 15, input errors 3, 0 drops
        2026-10-13 14:51:02 %LINK-3-UPDOWN: Interface GigabitEthernet0/1, changed state to down
        tu.usuario@bastion:~$ ping -c1 192.0.2.1
        64 bytes from 192.0.2.1: icmp_seq=1 ttl=64 time=1.23 ms --- 0% packet loss
        """

    var body: some View {
        Text(attributed)
            .font(SwiftUI.Font(model.terminalFont))
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SwiftUI.Color(t.background))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SwiftUI.Color(t.panel)))
    }

    private var attributed: AttributedString {
        let cfg = model.highlightConfig
        let palette = model.settings.highlightThemeColors ? t.highlightPalette : t.highlightPalette.merging(cfg.palette) { $1 }
        let h = Highlighter(rules: cfg.rules.filter { !model.settings.highlightDisabled.contains($0.description) }, palette: palette)
        return Self.render(Self.sample, with: enabled ? h : nil, palette: palette, theme: t)
    }

    /// Texto (varias líneas) coloreado con `h` (nil = sin resaltar). También para la vista previa del editor de reglas.
    static func render(_ text: String, with h: Highlighter?, palette: [String: RGB], theme t: Theme) -> AttributedString {
        var out = AttributedString()
        let lines = text.components(separatedBy: "\n")
        for (n, line) in lines.enumerated() {
            var a = AttributedString(line + (n < lines.count - 1 ? "\n" : ""))
            a.foregroundColor = SwiftUI.Color(t.text)
            for (r, st) in h?.styledRuns(line) ?? [] {
                guard let lo = AttributedString.Index(r.lowerBound, within: a),
                      let hi = AttributedString.Index(r.upperBound, within: a) else { continue }
                if let f = st.foreground.flatMap({ palette[$0] ?? RGB(hex: $0) }) { a[lo..<hi].foregroundColor = SwiftUI.Color(f) }
                if let b = st.background.flatMap({ palette[$0] ?? RGB(hex: $0) }) { a[lo..<hi].backgroundColor = SwiftUI.Color(b) }
                if st.underline { a[lo..<hi].underlineStyle = .single }
                if st.bold || st.italic {
                    a[lo..<hi].inlinePresentationIntent = st.bold && st.italic ? [.stronglyEmphasized, .emphasized]
                        : st.bold ? .stronglyEmphasized : .emphasized
                }
            }
            out += a
        }
        return out
    }
}
