import Darwin
import Foundation
import Testing
@testable import NetDeckCore

/// Lo que encontró la auditoría del askpass: rechazos sin volver a preguntar, contraseñas vacías, la sesión de la
/// pestaña, restos de otros días, el askpass que se quedaba vivo y las preguntas secretas con eco.
@Suite(.serialized) struct AskpassRechazosTests {
    @Test func preguntasSecretasSinDistinguirMayusculas() {
        for q in ["(admin@192.0.2.11) Enter PASSCODE:", "PASSWORD:", "Token:", "Response:", "Clave:", "Verification code:",
                  "Enter passphrase for key '/x':"] {
            #expect(Askpass.secretQuestion.matches(q), "«\(q)» sin eco")
        }
        #expect(!Askpass.isSecret("Are you sure you want to continue connecting (yes/no/[fingerprint])?"))
        // (la de la clave del equipo lleva su nombre: «spine-01» casa «pin», pero un sí/no nunca va sin eco)
        #expect(!Askpass.isSecret("The authenticity of host 'spine-01 (192.0.2.1)' can't be established.\nAre you sure you want to continue connecting (yes/no/[fingerprint])?"))
        #expect(Askpass.isSecret("(tu.usuario@core-01) Verification code:"))
    }

    @Test func rechazoAlTerminar() {
        #expect(Askpass.rejectedAtExit(["tu.usuario@192.0.2.11: Permission denied (publickey,password)."]))
        #expect(Askpass.rejectedAtExit(["Received disconnect from 192.0.2.11 port 22:2: Too many authentication failures"]))
        #expect(Askpass.rejectedAtExit(["Connection closed by 192.0.2.11 port 22"]))
        #expect(!Askpass.rejectedAtExit(["Connection closed by UNKNOWN port 65535"]))     // (el salto: su contraseña valía)
        #expect(!Askpass.rejectedAtExit(["ssh: connect to host 192.0.2.11 port 22: Operation timed out"]))
        #expect(!Askpass.rejectedAtExit(["Host key verification failed."]))
        #expect(Askpass.rejection(in: ["tu.usuario@192.0.2.11: Permission denied (publickey,password)."])?.host == "192.0.2.11")
        #expect(Askpass.rejection(in: ["Received disconnect from 192.0.2.11 port 22:2: Too many authentication failures"])?.host == "192.0.2.11")
        #expect(Askpass.rejection(in: ["Connection reset by 2001:db8::11 port 22"])?.host == "2001:db8::11")
        #expect(Askpass.rejection(in: ["tu.usuario@2001:db8::11: Permission denied (publickey)."])?.host == "2001:db8::11")
        #expect(Askpass.rejection(in: ["Too many authentication failures"])?.host == nil)
        // (el corte dice la dirección, el «Permission denied» el nombre del prompt; tras -J, «UNKNOWN» no es ninguno)
        #expect(Askpass.rejection(in: ["Connection closed by 192.0.2.11 port 22"]) == Askpass.Rejection(host: "192.0.2.11", fromAddress: true))
        #expect(Askpass.rejection(in: ["tu.usuario@core-01: Permission denied (password)."]) == Askpass.Rejection(host: "core-01"))
        #expect(Askpass.rejection(in: ["Received disconnect from UNKNOWN port 65535:2: Too many authentication failures"]) == Askpass.Rejection())
    }

    @Test func laUltimaNoValiaYLasDeLosSaltosSi() {
        let jump = CredentialRef.device("tu.usuario", "bastion"), dest = CredentialRef.named("AD")
        let attempts = [Askpass.Attempt(ref: jump, host: "bastion"), Askpass.Attempt(ref: dest, host: "core-01")]
        let r = Askpass.attributeRejection(attempts, rejection: Askpass.Rejection(host: "core-01"))
        #expect(r.failed == [dest] && r.confirmed == [jump])
        let quiet = Askpass.attributeRejection(attempts, rejection: nil)                // (sin rechazo: nada)
        #expect(quiet.failed.isEmpty && quiet.confirmed.isEmpty)
        // (la última, escrita a mano: no se bloquea ninguna guardada por ella)
        let manual = Askpass.attributeRejection([Askpass.Attempt(ref: jump, host: "bastion"), Askpass.Attempt(ref: nil, host: "core-01")],
                                                rejection: Askpass.Rejection(host: "core-01"))
        #expect(manual.failed.isEmpty && manual.confirmed == [jump])
    }

    /// El salto con contraseña y el destino sólo con clave: el «Permission denied» es del destino (lo nombra como el
    /// prompt) y, tras -J, el corte del destino llega como «UNKNOWN»: la del salto no tiene la culpa. Tampoco se
    /// confirma (antes sí): un rechazo que no nombra a ningún equipo de los intentos no demuestra que alguno entrara.
    /// (Los cortes «by core-01 port 22» de antes no salen nunca: ssh pone ahí la dirección o «UNKNOWN».)
    @Test func elRechazoDelDestinoNoBloqueaLaDelSalto() {
        let jump = CredentialRef.device("tu.usuario", "bastion")
        for line in ["tu.usuario@core-01: Permission denied (publickey).",
                     "Received disconnect from UNKNOWN port 65535:2: Too many authentication failures"] {
            let r = Askpass.attributeRejection([Askpass.Attempt(ref: jump, host: "bastion")], rejection: Askpass.rejection(in: [line]))
            #expect(r.failed.isEmpty && r.confirmed.isEmpty, "«\(line)»")
        }
    }

    /// OpenSSH dice la IP al cortar («Connection closed by 192.0.2.10 port 22») y el intento guarda el HostName del
    /// prompt: antes salía failed=[] y confirmed=[la rechazada]. Con un solo equipo y una sola guardada, es ésa; con
    /// varios equipos o varias contraseñas no se sabe cuál. Nunca se confirma ninguna.
    @Test func unCorteConLaIpCulpaALaUnicaYNuncaConfirma() throws {
        let dest = CredentialRef.named("AD"), jump = CredentialRef.device("tu.usuario", "bastion")
        for line in ["Connection closed by 192.0.2.10 port 22", "Connection reset by 192.0.2.10 port 22",
                     "Received disconnect from 192.0.2.10 port 22:2: Too many authentication failures"] {
            let rejection = Askpass.rejection(in: [line])
            for attempts in [[Askpass.Attempt(ref: dest, host: "core-01.example.net")],
                             [Askpass.Attempt(ref: dest, host: "core-01.example.net"), Askpass.Attempt(ref: dest, host: "CORE-01.example.net")]] {
                let r = Askpass.attributeRejection(attempts, rejection: rejection)
                #expect(r.failed == [dest] && r.confirmed.isEmpty, "«\(line)»")
            }
            for attempts in [[Askpass.Attempt(ref: jump, host: "bastion"), Askpass.Attempt(ref: dest, host: "core-01.example.net")],
                             [Askpass.Attempt(ref: jump, host: "core-01.example.net"), Askpass.Attempt(ref: dest, host: "core-01.example.net")],
                             [Askpass.Attempt(ref: nil, host: "core-01.example.net"), Askpass.Attempt(ref: dest, host: "core-01.example.net")]] {
                let r = Askpass.attributeRejection(attempts, rejection: rejection)
                #expect(r.failed.isEmpty && r.confirmed.isEmpty, "«\(line)»: \(attempts)")
            }
        }
        // (de punta a punta, al terminar la pestaña: se dice cuál no valía, sin bloquearla ni confirmarla)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sesiones-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ledger = CredentialLedger(), session = UUID()
        try SafeFile.write(Askpass.encodeGiven(dest, host: "core-01.example.net") + "\n", to: dir.appendingPathComponent(session.uuidString))
        let failed = Askpass.settleAfterExit(session: session, ledger: ledger, directory: dir) {
            Askpass.rejection(in: ["Connection closed by 192.0.2.10 port 22"])
        }
        #expect(failed == [dest] && !ledger.isBlocked(dest))
        #expect(ledger.state(of: dest) == nil)
    }

    @Test func unRechazoSinEquipoNoAcusaAlUltimoSalto() {
        let jump = CredentialRef.device("tu.usuario", "bastion")
        let r = Askpass.attributeRejection([Askpass.Attempt(ref: jump, host: "bastion")],
                                           rejection: Askpass.rejection(in: ["Too many authentication failures"]))
        #expect(r.failed.isEmpty && r.confirmed.isEmpty)
    }

    @Test func dosUsuariosEnElMismoHostNoPermitenAcusarLaClaveDelSalto() {
        let jump = CredentialRef.named("clave-del-salto")
        for destination in [CredentialRef.named("clave-del-destino"), nil] {
            let attempts = [Askpass.Attempt(ref: jump, host: "192.0.2.11"),
                            Askpass.Attempt(ref: destination, host: "192.0.2.11")]
            let r = Askpass.attributeRejection(attempts, rejection: Askpass.rejection(in: ["admin@192.0.2.11: Permission denied (password). "]))
            #expect(r.failed.isEmpty && r.confirmed.isEmpty)
        }
    }

    /// Esc en el segundo factor (OTP) después de dar la contraseña: no es que la contraseña no valga.
    @Test func cancelarElSegundoFactorNoBloquea() {
        let dest = CredentialRef.named("AD")
        let r = Askpass.attributeRejection([Askpass.Attempt(ref: dest, host: "core-01"),
                                            Askpass.Attempt(ref: nil, host: "core-01", cancelled: true)],
                                           rejection: Askpass.Rejection(host: "core-01"))
        #expect(r.failed.isEmpty && r.confirmed.isEmpty)
        #expect(Askpass.decodeAttempt("@core-01\t\(Askpass.cancelMark)") == Askpass.Attempt(ref: nil, host: "core-01", cancelled: true))
    }

    /// Un rechazo mucho después de dar la contraseña (un equipo cuyo prompt no se reconoce) no es de ella.
    @Test func losIntentosAntiguosNoSeBloquean() throws {
        let ledger = CredentialLedger(), session = UUID(), ref = CredentialRef.named("AD")
        let file = AppPaths.ensure(AppPaths.sessions).appendingPathComponent(session.uuidString)
        try SafeFile.write(Askpass.encodeGiven(ref, host: "core-01") + "\n", to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: file.path)
        var looked = false
        let failed = Askpass.settleAfterExit(session: session, ledger: ledger) { looked = true; return Askpass.Rejection() }
        #expect(failed.isEmpty && !ledger.isBlocked(ref) && !looked)                 // (ni se mira la pantalla)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// La de una sesión guardada que no entra: se dice, pero no se bloquea (sólo la por defecto escrita sola se bloquea).
    @Test func alTerminarSinEntrarSeDiceSinBloquear() throws {
        let ledger = CredentialLedger(), session = UUID(), ref = CredentialRef.named("AD")
        let file = AppPaths.ensure(AppPaths.sessions).appendingPathComponent(session.uuidString)
        try SafeFile.write(Askpass.encodeGiven(ref, host: "core-01") + "\n", to: file)
        let failed = Askpass.settleAfterExit(session: session, ledger: ledger) { Askpass.Rejection(host: "core-01") }
        #expect(failed == [ref] && !ledger.isBlocked(ref))
        #expect(!FileManager.default.fileExists(atPath: file.path))                     // (resuelto: no queda)
    }

    /// Un rechazo tardío (un TACACS lento) llega cuando ya has guardado la nueva: era de la anterior y no se dice. Si el
    /// intento es de después de guardarla, sí se dice; en ningún caso se bloquea.
    @Test func unRechazoTardioNoAcusaALaRecienGuardada() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sesiones-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for savedAfter in [true, false] {
            let ledger = CredentialLedger(), session = UUID(), ref = CredentialRef.named("AD")
            if !savedAfter { ledger.reset(ref) }
            let file = dir.appendingPathComponent(session.uuidString)
            try SafeFile.write(Askpass.encodeGiven(ref, host: "core-01") + "\n", to: file)
            if savedAfter {
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-5)], ofItemAtPath: file.path)
                ledger.reset(ref)                                   // (la guardas otra vez mientras TACACS contesta)
            }
            let failed = Askpass.settleAfterExit(session: session, ledger: ledger, directory: dir) { Askpass.Rejection(host: "core-01") }
            #expect(failed == (savedAfter ? [] : [ref]))
            #expect(!ledger.isBlocked(ref))
        }
    }

    @Test func unaVaciaNiSeGuardaNiDesbloquea() throws {
        let store = MemoryCredentialStore([.named("AD"): "buena"]), ledger = CredentialLedger()
        ledger.markFailed(.named("AD"))
        let state = FileManager.default.temporaryDirectory.appendingPathComponent("askpass-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: state) }
        let ask = Askpass.Asker(tty: Respuestas(texto: ""), account: "tu.usuario@core-01", user: "tu.usuario", host: "core-01",
                                named: "AD", store: store, ledger: ledger, state: state, session: nil)
        #expect(ask.user(failed: .named("AD")) == 1)                                    // (tres veces vacía: cancelado)
        #expect(try store.password(for: .named("AD")) == "buena")
        #expect(ledger.isBlocked(.named("AD")))
        // (un Intro de más y luego la buena: se vuelve a pedir y vale)
        let again = Askpass.Asker(tty: Respuestas(textos: ["", "nueva"]), account: "tu.usuario@core-01", user: "tu.usuario",
                                  host: "core-01", named: nil, store: store, ledger: ledger, state: state, session: nil)
        #expect(again.user(failed: nil) == 0)
    }

    /// «¿Guardarla como «AD»? (sustituye la guardada)» con Intro: sí, haya fallado o no la guardada (decisión del
    /// autor: Intro = guardar; la pregunta avisa de que sustituye la que hay).
    @Test func guardarlaComoConIntroSiempreLaGuarda() throws {
        for failed in [nil, CredentialRef.named("AD")] {
            let store = MemoryCredentialStore([.named("AD"): "buena"]), ledger = CredentialLedger()
            let state = FileManager.default.temporaryDirectory.appendingPathComponent("askpass-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: state) }
            let ask = Askpass.Asker(tty: SoloIntro(texto: "otra"), account: "tu.usuario@core-01", user: "tu.usuario",
                                    host: "core-01", named: "AD", store: store, ledger: ledger, state: state, session: nil,
                                    reply: { _ in 0 })
            #expect(ask.user(failed: failed) == 0)
            #expect(try store.password(for: .named("AD")) == "otra")
        }
    }

    @Test func unaVaciaEnElLlaveroCuentaComoQueNoEsta() async {
        #expect(await MemoryCredentialStore([.named("AD"): ""]).passwordInBackground(for: .named("AD")) == nil)
    }

    @Test func elEntornoLlevaLaSesion() {
        let env = Askpass.environment(executable: "/x", configPath: nil, session: UUID(), profile: "core-01-ro")
        #expect(env["NETDECK_PROFILE"] == "core-01-ro")
        #expect(Askpass.environment(executable: "/x", configPath: nil, session: UUID())["NETDECK_PROFILE"] == nil)
    }

    @Test func seBorranLosRestosDeOtrosDias() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sesiones-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = dir.appendingPathComponent(UUID().uuidString), fresh = dir.appendingPathComponent(UUID().uuidString)
        let state = dir.appendingPathComponent("ndapp-askpass.123")
        for f in [old, fresh, state] { try Data("@core-01\tnamed\tAD\n".utf8).write(to: f) }
        let twoDays = Date().addingTimeInterval(-2 * 24 * 3600)
        for f in [old, state] { try FileManager.default.setAttributes([.modificationDate: twoDays], ofItemAtPath: f.path) }
        #expect(Askpass.purgeStale(in: dir) == 1)
        #expect(!FileManager.default.fileExists(atPath: old.path) && FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: state.path))                     // (ésos tienen su propia limpieza)
    }

    /// Lo que lanza ssh sin terminal (el askpass, con su ventana) se va con él: al cerrarlo y si termina solo.
    @Test func alTerminarSeVaTodoSuGrupo() async throws {
        for script in ["/bin/sleep 60 & echo $!; wait", "/bin/sleep 60 & echo $!"] {
            let p = try ChildProcess(executable: "/bin/sh", arguments: ["-c", script], environment: [:])
            var lines = p.output.makeAsyncIterator(), text = ""
            while !text.contains("\n"), let d = await lines.next() { text += String(decoding: d, as: UTF8.self) }
            let child = try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            if script.hasSuffix("wait") { p.terminate() }
            var gone = false
            for _ in 0..<40 {
                if kill(child, 0) != 0 { gone = true; break }
                try await Task.sleep(for: .milliseconds(100))
            }
            if !gone { kill(child, SIGKILL) }
            #expect(gone, "«\(script)»: el hijo sigue vivo")
        }
    }
}

/// Lo que «teclea» la persona en el askpass: siempre lo mismo, y «sí» a todo.
private final class Respuestas: AskpassUI {
    private var textos: [String]
    private let siempre: String
    init(texto: String) { textos = []; siempre = texto }
    init(textos: [String]) { self.textos = textos; siempre = textos.last ?? "" }
    func say(_ s: String) {}
    func read(secret: Bool) -> String? { textos.isEmpty ? siempre : textos.removeFirst() }
    func yesNo(_ question: String, default d: Bool) -> Bool? { false }
}

/// Escribe una contraseña y contesta Intro (lo de por defecto) a todo.
private final class SoloIntro: AskpassUI {
    let texto: String
    init(texto: String) { self.texto = texto }
    func say(_ s: String) {}
    func read(secret: Bool) -> String? { texto }
    func yesNo(_ question: String, default d: Bool) -> Bool? { d }
}
