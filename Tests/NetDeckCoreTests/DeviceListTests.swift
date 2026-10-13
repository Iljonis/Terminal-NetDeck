import Foundation
import Testing
@testable import NetDeckCore

@Suite struct DeviceListTests {
    @Test func equiposValidosYRechazados() {
        let r = DeviceListText.parse("""
            core-01
            192.0.2.5, tu.usuario@core-02:2222   # comentario
            -oProxyCommand=x
            a@-oProxyCommand=x
            core-01
            """)
        #expect(r.devices.map(\.description) == ["core-01", "192.0.2.5", "tu.usuario@core-02:2222"])
        #expect(r.rejected == ["-oProxyCommand=x", "a@-oProxyCommand=x"])
        #expect(DeviceListText.valid("$(reboot)") == nil)
        #expect(DeviceListText.valid("core-01:99999") == nil)
    }

    @Test func importarTxtYCsv() {
        let csv = """
            hostname,ip,sitio
            "core-01",192.0.2.1,Madrid
            core-02;192.0.2.2
            # nota

            192.0.2.9\totro
            """
        #expect(DeviceListText.importing(csv) == "core-01\ncore-02\n192.0.2.9")
        #expect(DeviceListText.importing("core-01\ncore-02\n") == "core-01\ncore-02")
    }

    @Test func gestionarListas() {
        var lib = ListLibrary()
        let a = lib.upsert(SavedList(name: "Madrid", jump: "bastion", devices: ["core-01"]))
        let b = lib.upsert(SavedList(name: "madrid"))
        #expect(b.name == "madrid 2")
        let r1 = lib.rename(b.id, to: "Sevilla")
        #expect(r1)
        let r2 = lib.rename(b.id, to: "  ")
        #expect(!r2)
        let c = lib.duplicate(a.id)
        #expect(c?.name == "Madrid 2" && c?.devices == ["core-01"] && c?.id != a.id)
        #expect(lib.lists.map(\.name) == ["Madrid", "Madrid 2", "Sevilla"])
        var edited = a
        edited.devices = ["core-01", "core-03"]
        lib.upsert(edited)
        #expect(lib.list(a.id)?.devices.count == 2 && lib.lists.count == 3)
        lib.remove(a.id)
        #expect(lib.lists.map(\.name) == ["Madrid 2", "Sevilla"])
    }

    @Test func guardarYLeer() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("listas-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("listas.json")
        #expect(try ListLibrary(contentsOf: url) == ListLibrary())
        var lib = ListLibrary()
        lib.upsert(SavedList(name: "Madrid", jump: "bastion", user: "tu.usuario", credential: "AD",
                             devices: ["core-01", "192.0.2.5"]))
        try lib.save(to: url)
        try lib.save(to: url)                                  // (la segunda, con copia)
        #expect(try ListLibrary(contentsOf: url) == lib)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("anterior").path))
        #expect(lib.lists[0].endpoints.map(\.host) == ["core-01", "192.0.2.5"])
    }
}
