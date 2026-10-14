import AppKit
import NetDeckCore
import SwiftUI

/// Buscar en TODOS los registros de las sesiones (como «buscar-registros» de NetDeck): una IP, una descripción, una MAC
/// en cualquier formato (aa:bb:cc:dd:ee:ff, aabb.ccdd.eeff, aa-bb-…)… y salen las líneas de todos los días y equipos.
struct LogSearchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var t
    @Stored private var query = ""
    @Stored private var hits: [Hit] = []
    @Stored private var selected: Hit.ID?
    @Stored private var context: [String] = []
    @Stored private var searching = false
    @Stored private var task: Task<Void, Never>?

    struct Hit: Identifiable, Hashable {
        let id = UUID()
        let file: URL
        let line: Int
        let text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SearchField(text: $query, prompt: L("IP, MAC (cualquier formato), interfaz, texto…"))
                    .onSubmit(search)
                Button(L("Buscar"), action: search).keyboardShortcut(.defaultAction)
                if searching { ProgressView().controlSize(.small) }
            }
            Text(L("\(hits.count)\(hits.count >= 500 ? "+" : "") líneas en \(AppPaths.tilde(model.settings.logPath))"))
                .font(.caption).foregroundStyle(.secondary)
            HSplitView {
                List(hits, selection: $selected) { h in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.text).font(.system(.caption, design: .monospaced)).lineLimit(1)
                        Text("\(h.file.deletingLastPathComponent().lastPathComponent) · \(h.file.lastPathComponent):\(h.line)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(h.id)
                }
                .frame(minWidth: 360)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(context.enumerated()), id: \.offset) { _, l in
                            Text(l.isEmpty ? " " : l).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(l.hasPrefix("▶") ? SwiftUI.Color(t.accent) : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(8)
                }
                .frame(minWidth: 300)
            }
            HStack {
                if let h = hits.first(where: { $0.id == selected }) {
                    Button(L("Abrir el registro")) { NSWorkspace.shared.open(h.file) }
                    Button(L("Mostrar en Finder")) { NSWorkspace.shared.activateFileViewerSelecting([h.file]) }
                }
                Spacer()
                Button(L("Cerrar")) { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 940, height: 600)
        .onChange(of: selected) { loadContext() }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        task?.cancel()
        searching = true
        hits = []
        let dir = model.settings.logURL
        task = Task.detached {
            let found = Self.grep(q, in: dir)
            await MainActor.run {
                hits = found
                searching = false
                selected = found.first?.id
            }
        }
    }

    /// grep (y zgrep para los comprimidos de hace más de un mes), sin distinguir mayúsculas.
    nonisolated static func grep(_ q: String, in dir: URL) -> [Hit] {
        let pattern = macPattern(q) ?? NSRegularExpression.escapedPattern(for: q)
        var out: [Hit] = []
        let fm = FileManager.default
        let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let f = e?.nextObject() as? URL {
            if f.pathExtension == "log" || f.lastPathComponent.hasSuffix(".log.gz") { files.append(f) }
        }
        files.sort { $0.path > $1.path }                        // lo más reciente primero
        for chunk in stride(from: 0, to: files.count, by: 200) {
            let part = Array(files[chunk..<min(files.count, chunk + 200)])
            for (tool, list) in [("/usr/bin/grep", part.filter { $0.pathExtension == "log" }),
                                 ("/usr/bin/zgrep", part.filter { $0.pathExtension == "gz" })] where !list.isEmpty {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: tool)
                p.arguments = ["-n", "-i", "-E", "-H", "--", pattern] + list.map(\.path)
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                guard (try? p.run()) != nil else { continue }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                for l in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    let parts = l.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                    guard parts.count == 3, let n = Int(parts[1]) else { continue }
                    out.append(Hit(file: URL(fileURLWithPath: String(parts[0])), line: n, text: String(parts[2])))
                    if out.count >= 500 { return out }
                }
            }
        }
        return out
    }

    /// Una MAC en cualquier formato → la expresión que encaja con todos.
    nonisolated static func macPattern(_ q: String) -> String? {
        let hex = q.lowercased().filter { $0.isHexDigit }
        guard hex.count == 12, q.count <= 17, q.allSatisfy({ $0.isHexDigit || ":-. ".contains($0) }) else { return nil }
        let c = Array(hex)
        let pairs = stride(from: 0, to: 12, by: 2).map { String(c[$0...$0 + 1]) }
        let quads = stride(from: 0, to: 12, by: 4).map { String(c[$0..<$0 + 4]) }
        return "(" + [pairs.joined(separator: "[:-]"), quads.joined(separator: "[.-]"), hex].joined(separator: "|") + ")"
    }

    private func loadContext() {
        guard let h = hits.first(where: { $0.id == selected }) else { context = []; return }
        let id = h.id
        Task {
            // (fuera del hilo principal: un registro grande o comprimido no congela la ventana)
            let lines = await Task.detached { Self.readLines(h.file) }.value
            guard selected == id else { return }
            let lo = max(0, h.line - 13), hi = min(lines.count, h.line + 12)
            context = lo < hi ? (lo..<hi).map { ($0 + 1 == h.line ? "▶ " : "  ") + lines[$0] } : []
        }
    }

    nonisolated static func readLines(_ file: URL) -> [String] {
        let text: String
        if file.pathExtension == "gz" {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/gzcat")
            p.arguments = [file.path]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        }
        return text.components(separatedBy: "\n")
    }
}
