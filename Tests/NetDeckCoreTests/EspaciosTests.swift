import Foundation
import Testing
@testable import NetDeckCore

@Suite struct EspaciosTests {
    func remote(_ name: String = "core-01") -> WorkspaceTab {
        WorkspaceTab(route: ConnectionRoute(title: name, target: Endpoint(user: "tu.usuario", host: "192.0.2.10")))
    }
    @Test func conservaOrdenSeleccionPanelYDivisores() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("espacios.json")
        let a = remote(), b = remote("core-02")
        let w = Workspace(name: "Guardia", tabs: [b, a], selected: a.id, layout: "side2", panes: [a.id, b.id], fractions: ["root": [0.3, 0.7]])
        let lib = WorkspaceLibrary(workspaces: [w])
        try lib.save(to: file)
        #expect(try WorkspaceLibrary.load(from: file) == lib)
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try lib.save(to: file)
        #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("anterior").path))
    }
    @Test func datosRotosONuevosNuncaSePisan() throws {
        let dir = AppPaths.ensure(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("espacios.json")
        for text in ["{roto", #"{"version":99,"workspaces":[]}"#] {
            try SafeFile.write(text, to: file)
            #expect(throws: (any Error).self) { try WorkspaceLibrary(workspaces: [Workspace(name: "Guardia", tabs: [remote()])]).save(to: file) }
            #expect(try SafeFile.read(file) == text)
        }
    }
    @Test @MainActor func resuelveSesionesActualesYAvisaLasBorradas() throws {
        var a = remote(), b = remote("borrada")
        a.route.sessionName = "core-01"; b.route.sessionName = "borrada"
        let manager = SessionManager(profiles: SSHConfigParser().parse("Host core-01\n HostName 198.51.100.10\n User tu.usuario\n"))
        let r = try Workspace(name: "Guardia", tabs: [a, b]).resolve(using: manager)
        #expect(r.tabs.count == 1 && r.tabs[0].id == a.id)
        #expect(r.tabs[0].route.target.host == "198.51.100.10")
        #expect(r.missing == ["borrada"])
    }
    @Test func rechazaDuplicadosLoopbackYReferenciasAjenas() {
        let a = remote()
        #expect(Workspace(name: "x", tabs: [a, a]).problem != nil)
        var w = Workspace(name: "x", tabs: [a]); w.panes = [UUID()]
        #expect(w.problem != nil)
        var lib = WorkspaceLibrary(workspaces: [Workspace(name: "x", tabs: [a])]); lib.workspaces.append(lib.workspaces[0])
        #expect(lib.problem != nil)
        let loop = WorkspaceTab(route: ConnectionRoute(title: "local-ssh", target: Endpoint(host: "127.0.0.1")))
        #expect(Workspace(name: "x", tabs: [loop]).tabs.isEmpty)
        #expect(Workspace.weights([0.3, 0.7], count: 2) == [0.3, 0.7])
        #expect(Workspace.weights([.nan], count: 2) == [0.5, 0.5])
    }
}

/// Hallazgos de la auditoría de espacios que viven en el núcleo.
@Suite struct EspaciosAuditoriaTests {
    /// Lo que se guarda tiene que poder leerse: load rechaza más de 5 MB, así que save tampoco escribe más (y deja el
    /// archivo de antes como estaba).
    @Test func nuncaSeGuardaLoQueNoSePuedeLeer() throws {
        let dir = AppPaths.ensure(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("espacios.json")
        let pequeño = WorkspaceLibrary(workspaces: [Workspace(name: "Guardia", tabs: [
            WorkspaceTab(route: ConnectionRoute(title: "core-01", target: Endpoint(user: "tu.usuario", host: "192.0.2.10")))])])
        try pequeño.save(to: file)
        let antes = try SafeFile.read(file)
        let titulo = String(repeating: "☰", count: 300)                    // (3 bytes cada uno)
        let enorme = WorkspaceLibrary(workspaces: (0..<100).map { i in
            Workspace(name: "espacio \(i)", tabs: (0..<64).map { _ in
                WorkspaceTab(route: ConnectionRoute(title: titulo, target: Endpoint(user: "tu.usuario", host: "192.0.2.10")))
            })
        })
        #expect(enorme.problem == nil)                                       // (válida: sólo es grande)
        let bytes = try JSONEncoder().encode(enorme).count
        #expect(bytes > 5_000_000, "la prueba necesita más de 5 MB: \(bytes)")
        #expect(throws: (any Error).self) { try enorme.save(to: file) }
        #expect(try SafeFile.read(file) == antes)
        #expect(try WorkspaceLibrary.load(from: file) == pequeño)
    }

    /// «Conectar» sin guardar con su perfil, y el salto no deja reenviar: la ruta escrita en el salto conserva el
    /// perfil (si no, al reconectar o clonar la pestaña volvía al global).
    @Test @MainActor func elSaltoAManoConservaElPerfilTemporal() throws {
        let manager = SessionManager(profiles: SSHConfigParser().parse(
            "Host bastion\n HostName 192.0.2.1\n User tu.usuario\nHost core-01\n HostName 192.0.2.11\n User tu.usuario\n ProxyJump bastion\n"))
        var r = try manager.route(to: #require(manager.profile(named: "core-01")))
        var perfil = TerminalProfile()
        perfil.theme = "papel"
        perfil.scrollback = 9000
        r.transientProfile = perfil
        let h = try #require(try manager.typedHop(for: r))
        #expect(h.transientProfile == perfil)
    }
}

/// Qué credencial ha valido al entrar: de cada equipo, el último intento. Una guardada rechazada no se confirma
/// aunque después se entre (con otra o escribiéndola a mano), y la nueva que ha entrado no se marca como fallida.
@Suite struct AtribucionCredencialesTests {
    let viejo = CredentialRef.device("tu.usuario", "192.0.2.11"), ad = CredentialRef.named("AD"), salto = CredentialRef.named("salto")

    @Test func cadaEquipoSuUltimoIntento() {
        func at(_ r: CredentialRef?, _ h: String) -> Askpass.Attempt { .init(ref: r, host: h) }
        // (la de siempre, a la primera)
        #expect(Askpass.attribute([at(ad, "192.0.2.11")]) == ([ad], []))
        // (la guardada falla y se guarda otra que entra: la nueva vale, la vieja no)
        #expect(Askpass.attribute([at(viejo, "192.0.2.11"), at(ad, "192.0.2.11")]) == ([ad], [viejo]))
        // (falla y se escribe a mano sin guardar: ninguna guardada se confirma; la rechazada sigue fallida)
        #expect(Askpass.attribute([at(ad, "192.0.2.11"), at(nil, "192.0.2.11")]) == ([], [ad]))
        // (la misma, guardada otra vez con la contraseña corregida: vale)
        #expect(Askpass.attribute([at(ad, "192.0.2.11"), at(ad, "192.0.2.11")]) == ([ad], []))
        // (el salto y el destino: los dos han entrado)
        #expect(Askpass.attribute([at(salto, "192.0.2.1"), at(ad, "192.0.2.11")]) == ([salto, ad], []))
    }

    /// El archivo de la pestaña lleva también los intentos a mano, y se lee en orden.
    @Test func elArchivoLlevaLosIntentosAMano() throws {
        let id = UUID()
        let url = AppPaths.ensure(AppPaths.sessions).appendingPathComponent(id.uuidString)
        try SafeFile.write([Askpass.encodeGiven(ad, host: "192.0.2.11"), Askpass.encodeManual(host: "192.0.2.11")]
            .joined(separator: "\n") + "\n", to: url)
        let attempts = Askpass.takeAttempts(session: id)
        #expect(attempts == [.init(ref: ad, host: "192.0.2.11"), .init(ref: nil, host: "192.0.2.11")])
        #expect(Askpass.attribute(attempts) == ([], [ad]))
        #expect(!FileManager.default.fileExists(atPath: url.path))         // (leídos, se olvidan)
    }
}
