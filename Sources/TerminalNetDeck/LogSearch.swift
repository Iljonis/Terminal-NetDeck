import AppKit
import NetDeckCore
import SwiftUI

/// Buscar en TODOS los registros de las sesiones (como «buscar-registros» de NetDeck): una IP, una descripción, una MAC
/// en cualquier formato (aa:bb:cc:dd:ee:ff, aabb.ccdd.eeff, aa-bb-…)… y salen las líneas de todos los días y equipos.
/// La búsqueda es la de `NetDeckCore.LogSearch` (la misma que en Windows); aquí sólo se pinta.
struct LogSearchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var t
    @Stored private var query = ""
    @Stored private var isRegex = false
    @Stored private var caseSensitive = false
    @Stored private var wholeWord = false
    @Stored private var host = ""                            // («» = todos los equipos)
    @Stored private var period = LogPeriod.all
    @Stored private var hosts: [String] = []
    @Stored private var result: LogSearchResult?
    @Stored private var matcher: LogMatcher?
    @Stored private var failure: String?
    @Stored private var selected: LogHit.ID?
    @Stored private var context: [LogContextLine] = []
    @Stored private var searching = false
    @Stored private var turn = 0
    @Stored private var task: Task<Void, Never>?
    @Stored private var contextTask: Task<Void, Never>?
    @FocusState private var focus: Focus?

    private enum Focus { case query, list }

    private var hits: [LogHit] { result?.hits ?? [] }
    private var current: LogHit? { hits.first { $0.id == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SearchField(text: $query, prompt: L("IP, MAC (cualquier formato), interfaz, texto…"))
                    .focused($focus, equals: .query)
                    .onSubmit(search)
                    .onKeyPress(.downArrow) { focus = .list; return .handled }
                Button(L("Buscar"), action: search)
                if searching { ProgressView().controlSize(.small) }
            }
            options
            status
            HSplitView {
                List(hits, selection: $selected) { h in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.row(h, color: SwiftUI.Color(t.accent))).font(.system(.caption, design: .monospaced)).lineLimit(1)
                        Text("\(h.file.deletingLastPathComponent().lastPathComponent) · \(h.file.lastPathComponent):\(h.line)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .focused($focus, equals: .list)
                .onKeyPress(.return) { openLog(); return current == nil ? .ignored : .handled }
                .frame(minWidth: 360)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(context, id: \.number) { l in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(String(l.number)).foregroundStyle(.tertiary).frame(width: 40, alignment: .trailing)
                                Text(Self.highlighted(l.text.isEmpty ? " " : l.text, matcher?.ranges(in: l.text) ?? [],
                                                      color: SwiftUI.Color(t.accent)))
                                    .foregroundStyle(l.isHit ? SwiftUI.Color(t.accent) : .primary)
                                    .fontWeight(l.isHit ? .semibold : .regular)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(8)
                }
                .frame(minWidth: 300)
            }
            HStack {
                if let h = current {
                    Button(L("Abrir el registro")) { NSWorkspace.shared.open(h.file) }
                    Button(L("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([h.file]) }
                    Button(L("Copiar línea")) { copy(h.text) }
                    Button(L("Copiar ruta")) { copy(h.file.path) }
                }
                Spacer()
                Button(L("Cerrar")) { task?.cancel(); contextTask?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 940, height: 600)
        .onChange(of: selected) { loadContext() }
        // (cambiar una opción repite la búsqueda ya hecha)
        .onChange(of: isRegex) { rerun() }
        .onChange(of: caseSensitive) { rerun() }
        .onChange(of: wholeWord) { rerun() }
        .onChange(of: host) { rerun() }
        .onChange(of: period) { rerun() }
        .onAppear {
            focus = .query
            let dir = model.settings.logURL
            Task { hosts = await Task.detached { LogSearch.hosts(in: dir) }.value }
            // (capturas: NETDECK_SNAPSHOT_ACTION=buscar-registros[:texto] abre la hoja y busca)
            let env = ProcessInfo.processInfo.environment
            if env["NETDECK_SNAPSHOT"] != nil, let a = env["NETDECK_SNAPSHOT_ACTION"], a.hasPrefix("buscar-registros") {
                query = a.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? "192.0.2.1"
                search()
            }
        }
    }

    /// Los interruptores, el equipo y el periodo.
    private var options: some View {
        HStack(spacing: 10) {
            Toggle(L("Regex"), isOn: $isRegex).help(L("Interpretar como expresión regular"))
            Toggle(L("Mayúsculas"), isOn: $caseSensitive).help(L("Distinguir mayúsculas de minúsculas"))
            Toggle(L("Palabra"), isOn: $wholeWord).help(L("Sólo palabras completas"))
            Spacer().frame(width: 6)
            Picker(L("Equipo"), selection: $host) {
                Text(L("Todos los equipos")).tag("")
                ForEach(hosts, id: \.self) { Text($0).tag($0) }
            }
            .frame(maxWidth: 260)
            Picker(L("Periodo"), selection: $period) {
                ForEach(LogPeriod.allCases) { Text($0.title).tag($0) }
            }
            .frame(maxWidth: 220)
            Spacer()
        }
        .toggleStyle(.button)
        .controlSize(.small)
    }

    /// «N líneas en M archivos», el tope, lo que no se ha leído y el reparto por equipo; o el error del regex.
    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let failure {
                Text(failure).foregroundStyle(.red)
            } else if let result {
                Text(([result.summary] + result.warnings).joined(separator: " · "))
                    .foregroundStyle(result.warnings.isEmpty ? .secondary : SwiftUI.Color.orange)
                if let byHost = result.hostSummary() { Text(byHost).foregroundStyle(.secondary) }
            } else {
                Text(L("Se busca en \(AppPaths.tilde(model.settings.logPath))")).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    private func makeQuery() -> LogQuery {
        LogQuery(text: query, isRegex: isRegex, caseSensitive: caseSensitive, wholeWord: wholeWord,
                 host: host.isEmpty ? nil : host, period: period)
    }

    private func rerun() { if result != nil || failure != nil { search() } }

    private func search() {
        let q = makeQuery()
        guard !q.trimmed.isEmpty else { return }
        task?.cancel()
        turn += 1
        let mine = turn
        searching = true
        failure = nil
        let dir = model.settings.logURL
        task = Task.detached {
            let outcome: Result<LogSearchResult, any Error> = Result { try LogSearch.search(q, in: dir, isCancelled: { Task.isCancelled }) }
            let compiled = try? q.matcher()
            await MainActor.run {
                guard mine == turn else { return }                  // (otra búsqueda más reciente: ésta ya no vale)
                searching = false
                switch outcome {
                case .success(let found):
                    result = found
                    matcher = compiled
                    selected = found.hits.first?.id
                    if !found.hits.isEmpty { focus = .list }
                case .failure(let error):
                    result = nil
                    selected = nil
                    context = []
                    failure = error.localizedDescription
                }
            }
        }
    }

    private func loadContext() {
        contextTask?.cancel()
        guard let h = current else { context = []; return }
        let id = h.id
        contextTask = Task.detached {
            // (fuera del hilo principal y por trozos: un registro grande o comprimido no congela la ventana)
            let lines = LogSearch.context(file: h.file, line: h.line, isCancelled: { Task.isCancelled })
            await MainActor.run {
                guard selected == id else { return }
                context = lines
            }
        }
    }

    private func openLog() { if let h = current { NSWorkspace.shared.open(h.file) } }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// El texto con los trozos que aciertan marcados (`ranges` en posiciones de carácter).
    nonisolated static func highlighted(_ text: String, _ ranges: [Range<Int>], color: SwiftUI.Color) -> AttributedString {
        var out = AttributedString(text)
        let chars = out.characters
        for r in ranges where r.upperBound <= chars.count {
            let lo = chars.index(chars.startIndex, offsetBy: r.lowerBound), hi = chars.index(chars.startIndex, offsetBy: r.upperBound)
            out[lo..<hi].backgroundColor = color.opacity(0.35)
        }
        return out
    }

    /// La fila de la lista (con el primer acierto a la vista).
    nonisolated static func row(_ h: LogHit, color: SwiftUI.Color) -> AttributedString {
        let p = h.preview()
        return highlighted(p.text, p.ranges, color: color)
    }
}
