import Foundation
import Testing
@testable import NetDeckCore

/// Pendientes de la revisión de 0.9.9: favoritas y recientes con SafeFile y tope, botones sin saltos de línea, la
/// salida de grep a trozos y ⌘1…⌘9.
@Suite struct LimpiezaTests {
    private func carpeta() -> URL {
        AppPaths.ensure(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    @Test func favoritasConCopiaYSinPisarLaIlegible() throws {
        let dir = carpeta()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("favoritas")
        #expect(try SessionLists.loadFavorites(url) == [])
        try SessionLists.saveFavorites(["core-01"], to: url)
        try SessionLists.saveFavorites(["core-01", "bastion"], to: url)
        #expect(try SessionLists.loadFavorites(url) == ["core-01", "bastion"])
        #expect(try SafeFile.read(url.appendingPathExtension("anterior")) == "core-01\n")
        // (una que existe y no es UTF-8: error al leerla y no se guarda encima)
        try Data([0xFF, 0xFE, 0x00, 0x41]).write(to: url)
        #expect(throws: SafeFile.Unreadable.self) { try SessionLists.loadFavorites(url) }
        #expect(throws: SafeFile.Unreadable.self) { try SessionLists.saveFavorites(["otra"], to: url) }
        #expect(try Data(contentsOf: url) == Data([0xFF, 0xFE, 0x00, 0x41]))
    }

    @Test func recientesConTope() throws {
        let dir = carpeta()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("recientes")
        for i in 0..<(2 * SessionLists.recentKept + 30) {
            try SessionLists.noteRecent(i.isMultiple(of: 2) ? "core-01" : "sw-\(i)", at: Date(timeIntervalSince1970: Double(i)), in: url)
        }
        let text = try #require(try SafeFile.read(url))
        let lines = text.split(separator: "\n")
        #expect(lines.count <= 2 * SessionLists.recentKept)
        #expect(lines.last?.hasSuffix("\tsw-\(2 * SessionLists.recentKept + 29)") == true)
        #expect(SessionLists.recents(text).first == "sw-\(2 * SessionLists.recentKept + 29)")
        #expect(SessionLists.recents(text).count == SessionLists.recentShown)
        #expect(Set(SessionLists.recents(text, limit: 1000)).count == SessionLists.recents(text, limit: 1000).count)
        // (al recortar se queda la última vez de cada sesión, también la de la que se repite)
        let recortado = SessionLists.appending("9\tbastion", to: (0..<(2 * SessionLists.recentKept)).map { "\($0)\tcore-01" }.joined(separator: "\n"))
        #expect(recortado == "199\tcore-01\n9\tbastion\n")
        // (uno ilegible no se pisa)
        try Data([0xFF, 0xFE]).write(to: url)
        #expect(throws: SafeFile.Unreadable.self) { try SessionLists.noteRecent("core-01", in: url) }
        #expect(try Data(contentsOf: url) == Data([0xFF, 0xFE]))
    }

    /// Una contraseña escrita en el botón con su Intro pegado (o «\r\n», U+2028…) partiría botones.txt en dos líneas.
    @Test func botonConSaltoDeLineaNoSeGuarda() throws {
        let dir = carpeta()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("botones.txt")
        var f = ButtonFile(text: "Accesos :: clave :: VM BB :: s3cr€t\n")
        try f.save(to: url)
        for roto in ["s3cr€t\n", "s3\r\ncr€t", "s3cr\r", "s3\u{2028}cr€t"] {
            f.buttons[0].command = roto
            #expect(f.lineBreak == ButtonFile.LineBreak(button: "VM BB"))
            #expect(throws: ButtonFile.LineBreak.self) { try f.save(to: url) }
        }
        f.buttons[0].command = "nueva"
        f.buttons[0].name = "VM\nBB"
        #expect(f.lineBreak?.button == "VMBB")
        #expect(try SafeFile.read(url)?.contains(":: s3cr€t\n") == true)          // (sin tocar)
        #expect(f.lineBreak.map { !($0.errorDescription ?? "").contains("nueva") } == true)
    }

    @Test func lineasATrozosYConTope() {
        var s = LineSplitter(maxLine: 8)
        #expect(s.feed(Data("a:1:x\nb:2".utf8)) == ["a:1:x"])
        #expect(s.feed(Data(":y\n".utf8)) == ["b:2:y"])
        #expect(s.feed(Data(String(repeating: "z", count: 50).utf8)).isEmpty)
        #expect(s.feed(Data("zz\nc:3:ñ".utf8)) == ["zzzzzzzz"])
        #expect(s.finish() == ["c:3:ñ"])
        #expect(s.finish().isEmpty)
        #expect(s.feed(Data("\n\n".utf8)) == ["", ""])
    }

    @Test func atajosDePestanas() {
        #expect(TabShortcut.index(1, count: 3) == 0)
        #expect(TabShortcut.index(3, count: 3) == 2)
        #expect(TabShortcut.index(4, count: 3) == nil)
        #expect(TabShortcut.index(9, count: 3) == 2)                 // (⌘9, la última)
        #expect(TabShortcut.index(9, count: 12) == 11)
        #expect(TabShortcut.index(8, count: 12) == 7)
        #expect(TabShortcut.index(1, count: 0) == nil)
        #expect(TabShortcut.index(0, count: 5) == nil)
        #expect(TabShortcut.index(10, count: 20) == nil)
    }
}
