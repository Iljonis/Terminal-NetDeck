#if !os(Windows)
import Darwin
#endif
import Foundation

/// El SSH_ASKPASS de la app: el mismo ejecutable con NETDECK_ASKPASS=1. ssh lo llama con la pregunta y lee la
/// respuesta, asÃ­ que la contraseÃ±a de cada SESIÃ“N (y de sus saltos con -J) entra sola al abrirla, sin teclearla en el
/// terminal, como en cualquier cliente SSH:
///  Â· sÃ³lo la con nombre de ese perfil o la de su usuario@equipo, con usuario estricto;
///  Â· un intento: si ssh vuelve a preguntar, no valÃ­a â†’ te la pide a ti (no se bloquea: el bloqueo de 15 min es sÃ³lo
///    de la por defecto escrita sola dentro de una sesiÃ³n, `PasswordAutomation`);
///  Â· sin reservas ni esperas entre sesiones guardadas;
///  Â· cualquier otra pregunta (yes/no, passphrase, OTPâ€¦) te la hace a ti, en la pestaÃ±a. Esc cancela.
/// Lo que escribe en la pestaÃ±a empieza por Â«[NetDeck]Â»: el autocompletado de equipos no lo toma por una peticiÃ³n.
public enum Askpass {
    public static let flag = "NETDECK_ASKPASS"
    public static let marker = "[NetDeck]"

    static let questions = [Pattern(#"^(.+)'s password: ?$"#, ignoreCase: false),
                            Pattern(#"^\(([^ )]+@[^ )]+)\) ?[Pp]assword: ?$"#, ignoreCase: false)]
    static let git = Pattern(#"^(Username|Password) for '[^']*': ?$"#, ignoreCase: false)
    /// Lo que se contesta sin eco (no se ve ni queda en el historial de la pestaÃ±a ni en su registro). Sin distinguir
    /// mayÃºsculas: Â«Enter PASSCODE:Â» (SecurID) o Â«PASSWORD:Â» tambiÃ©n; ante la duda, sin eco.
    static let secretQuestion = Pattern(#"assword|assphrase|asscode|ode|pin|otp|token|secret|response|challenge|clave|c[oÃ³]digo"#)
    static let (red, cyan, green, yellow, reset) = ("\u{1b}[38;5;204m", "\u{1b}[38;5;51m", "\u{1b}[38;5;48m",
                                                     "\u{1b}[38;5;221m", "\u{1b}[0m")

    /// SÃ³lo preguntar (sin escribir ninguna guardada): el explorador SFTP con la contraseÃ±a automÃ¡tica apagada.
    public static let manualFlag = "NETDECK_ASKPASS_MANUAL"

    /// Variables para el proceso ssh de una pestaÃ±a. `manual`: no se prueba ninguna guardada, se pregunta siempre.
    /// `profile`: la sesiÃ³n guardada; `route`: sus extremos exactos, tambiÃ©n al conectar sin guardar. La predeterminada
    /// no va: el askpass no la usa (sÃ³lo el salto desde DENTRO de una sesiÃ³n, en la app) y su nombre y usuario los
    /// verÃ­a todo lo que cuelga de ssh.
    public static func environment(executable: String, configPath: String?, session: UUID, manual: Bool = false,
                                   profile: String? = nil, route: ConnectionRoute? = nil) -> [String: String] {
        var env = ["SSH_ASKPASS": executable, "SSH_ASKPASS_REQUIRE": "force", flag: "1",
                   "NETDECK_SESSION": session.uuidString]
        if manual { env[manualFlag] = "1" }
        if let profile, !profile.isEmpty { env[profileVariable] = profile }
        if let route, let data = try? JSONEncoder().encode(route), let text = String(data: data, encoding: .utf8) {
            env[routeVariable] = text                         // (alias, usuarios y extremos; nunca secretos)
        }
        if let configPath { env["NETDECK_SSH_CONFIG"] = configPath }
        return env
    }

    /// Las contraseÃ±as que el askpass ha dado a esa pestaÃ±a (para confirmarlas cuando llega al prompt).
    public static func takeGiven(session: UUID) -> [CredentialRef] { takeAttempts(session: session).compactMap(\.ref) }

    /// Un intento de entrar en `host`: con una guardada (`ref`) o escrita a mano sin guardar (nil).
    public struct Attempt: Equatable, Sendable {
        public var ref: CredentialRef?
        public var host: String?
        /// Esc en una pregunta (la contraseÃ±a, un OTPâ€¦): lo que venga despuÃ©s no es un rechazo de la contraseÃ±a.
        public var cancelled: Bool
        /// Una pregunta secreta manual posterior (OTP, passphraseâ€¦): su rechazo no demuestra que fallase la contraseÃ±a.
        public var manualFactor: Bool
        public init(ref: CredentialRef?, host: String?, cancelled: Bool = false, manualFactor: Bool = false) {
            self.ref = ref; self.host = host; self.cancelled = cancelled; self.manualFactor = manualFactor
        }
    }

    /// Los intentos de esa pestaÃ±a, en orden (y se olvidan).
    public static func takeAttempts(session: UUID) -> [Attempt] {
        takeAttempts(at: AppPaths.sessions.appendingPathComponent(session.uuidString))
    }

    static func takeAttempts(at url: URL) -> [Attempt] {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).compactMap(decodeAttempt)
    }

    /// Lo que dice ssh al terminar sin entrar cuando no valÃ­a la contraseÃ±a, y de quÃ© equipo, si lo dice
    /// (Â«tu.usuario@core-01: Permission denied (â€¦)Â»). `fromAddress`: es la direcciÃ³n de la conexiÃ³n (Â«Connection
    /// closed by 192.0.2.10 port 22Â»), no el nombre con que preguntÃ³ (el HostName del prompt).
    public struct Rejection: Equatable, Sendable {
        public var host: String?
        public var fromAddress: Bool
        public init(host: String? = nil, fromAddress: Bool = false) { self.host = host; self.fromAddress = fromAddress }
    }

    /// Â¿Dicen estas lÃ­neas (las Ãºltimas de la pantalla o el error de ssh) que no valÃ­a? Â«Permission deniedÂ», Â«Too many
    /// authentication failuresÂ», el equipo cortando la conexiÃ³n a medio entrarâ€¦ La Ãºltima que lo diga manda; sin un
    /// equipo explÃ­cito se conserva el rechazo, pero no se culpa a la Ãºltima contraseÃ±a (podrÃ­a ser la del salto).
    public static func rejection(in lines: [String]) -> Rejection? {
        guard let line = lines.last(where: { PromptRule.authenticationFailed($0) || exitRejection.matches($0) }) else { return nil }
        if let host = rejectedAccount.group(2, in: line) { return Rejection(host: host) }
        // (tras -J ssh no sabe la direcciÃ³n del destino: Â«UNKNOWNÂ» no es ningÃºn equipo)
        guard let address = rejectedConnection.group(1, in: line), address.lowercased() != "unknown" else { return Rejection() }
        return Rejection(host: address, fromAddress: true)
    }
    public static func rejectedAtExit(_ lines: [String]) -> Bool { rejection(in: lines) != nil }
    /// (un corte Â«by UNKNOWN port 65535Â» es el salto, que no llega al destino: su contraseÃ±a sÃ­ valÃ­a)
    static let exitRejection = Pattern(#"authentication failures?|connection (?:closed|reset) by (?!unknown\b)"#)
    static let rejectedAccount = Pattern(#"(?:^|\s)([^@\s]+)@(.+?): permission denied"#)
    static let rejectedConnection = Pattern(#"(?:received disconnect from|connection (?:closed|reset) by) ([^\s]+?)(?: port \d+|:\d+:|$)"#)

    /// Sin llegar a entrar y con un rechazo: no valÃ­an las dadas al equipo que nombra ssh; las de los otros (los saltos)
    /// sÃ­ entraron. Sin un equipo explÃ­cito no se sabe cuÃ¡l fallÃ³. Nada si no hay rechazo o si la persona
    /// cancelÃ³ o respondiÃ³ a otro factor despuÃ©s (un OTP rechazado no demuestra que la contraseÃ±a no valga).
    /// Si nombra un equipo al que no se dio ninguna, nunca se confirma nada: con su direcciÃ³n (el intento guarda el
    /// nombre del prompt) y todo dado a un solo equipo con una sola guardada, es Ã©sa; con un nombre, es otro equipo
    /// (el destino con clave tras el salto) y la del salto no tiene la culpa.
    public static func attributeRejection(_ attempts: [Attempt], rejection: Rejection?) -> (confirmed: [CredentialRef], failed: [CredentialRef]) {
        guard let rejection, let host = rejection.host?.lowercased(), !host.isEmpty,
              let last = attempts.last, !last.cancelled, !last.manualFactor else { return ([], []) }
        let valid = attempts.filter { !$0.cancelled && !$0.manualFactor }
        // (salto y destino pueden compartir IP con distintos usuarios: un rechazo que sÃ³lo dice host no los distingue)
        let atHost = valid.filter { $0.host?.lowercased() == host }
        guard Set(atHost.map(\.ref)).count <= 1 else { return ([], []) }
        guard !atHost.isEmpty else {
            guard rejection.fromAddress, Set(valid.map { $0.host?.lowercased() }).count == 1,
                  Set(valid.map(\.ref)).count == 1, let ref = valid.first?.ref else { return ([], []) }
            return ([], [ref])
        }
        var confirmed: [CredentialRef] = [], failed: [CredentialRef] = []
        for a in attempts where !a.cancelled {
            guard let ref = a.ref else { continue }
            if (a.host?.lowercased() ?? "") == host {
                if !failed.contains(ref) { failed.append(ref) }
            } else if !confirmed.contains(ref) {
                confirmed.append(ref)
            }
        }
        confirmed.removeAll(where: failed.contains)
        return (confirmed, failed)
    }

    /// Una pestaÃ±a, un explorador o un tÃºnel han terminado sin entrar: sus intentos, resueltos (`attributeRejection`).
    /// Las que han entrado se confirman; las que no, sÃ³lo se devuelven para decirlo (con Â«NumberOfPasswordPrompts 1Â» o
    /// un equipo que corta al primer fallo, ssh sale sin volver a preguntar). No se bloquean: son de la sesiÃ³n. SÃ³lo
    /// intentos recientes (`maxAge`: un rechazo mucho despuÃ©s no es de esa contraseÃ±a) y la pantalla sÃ³lo se mira si los
    /// hay. Devuelve las que no han valido.
    @discardableResult
    public static func settleAfterExit(session: UUID, ledger: CredentialLedger, maxAge: TimeInterval = 150, now: Date = Date(),
                                       directory: URL = AppPaths.sessions, rejection: () -> Rejection?) -> [CredentialRef] {
        let url = directory.appendingPathComponent(session.uuidString)
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let attempts = takeAttempts(at: url)
        guard !attempts.isEmpty, let modified, now.timeIntervalSince(modified) <= maxAge else { return [] }
        let (confirmed, failed) = attributeRejection(attempts, rejection: rejection())
        // (las de la sesiÃ³n no se bloquean: sÃ³lo se dice cuÃ¡l no ha valido; si la has guardado otra vez despuÃ©s de
        // darla, el rechazo era de la anterior y no se dice)
        confirmed.forEach(ledger.confirmDirect)
        let rejected = failed.filter { !ledger.wasReset($0, after: modified) }
        if !failed.isEmpty {
            DebugLog.log("askpass", "rechazada al terminar: \(failed.map(\.description).joined(separator: ", "))"
                         + (rejected.count < failed.count ? " (guardada otra vez despuÃ©s)" : ""))
        }
        return rejected
    }

    /// En la pestaÃ±a `session` ssh pregunta ya por `host`: las dadas antes a OTROS equipos de esa pestaÃ±a (los saltos)
    /// han entrado (ssh no pasa al siguiente sin haber entrado en el salto) â†’ confirmadas, y las pestaÃ±as que esperaban
    /// siguen ya, sin esperar a todo el login del destino. Si la del salto no valiera, ssh volverÃ­a a preguntar por el
    /// mismo salto: Ã©sa no se confirma aquÃ­ y se marca fallo como siempre. Devuelve las confirmadas.
    @discardableResult
    public static func confirmEarlier(session: String, host: String, ledger: CredentialLedger,
                                      directory: URL = AppPaths.sessions) -> [CredentialRef] {
        let url = directory.appendingPathComponent(session)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var keep: [String] = [], done: [CredentialRef] = []
        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
            if let g = decodeGiven(line), let h = g.host, h.caseInsensitiveCompare(host) != .orderedSame {
                ledger.confirmDirect(g.ref)
                done.append(g.ref)
            } else {
                keep.append(line)
            }
        }
        if !done.isEmpty {
            try? SafeFile.write(keep.map { $0 + "\n" }.joined(), to: url)
            DebugLog.log("askpass", "pregunta por \(host): confirmadas las de los saltos (\(done.map(\.description).joined(separator: ", ")))")
        }
        return done
    }

    /// `dialog`: sin terminal (SFTP, procesos sin pestaÃ±a), la app pregunta en una ventana.
    @MainActor
    public static func run(arguments: [String], environment env: [String: String],
                           dialog: (() -> AskpassUI?)? = nil) -> Int32 {
        let question = arguments.dropFirst().first ?? ""
        if git.matches(question) { return 1 }                 // (las de git no son nuestras)
        guard let tty: AskpassUI = TTY() ?? dialog?() else { return 1 }
        DebugLog.log("askpass", "pregunta Â«\(question)Â» (\(tty is TTY ? "en la pestaÃ±a" : "en una ventana"))")
        let manager = SessionManager()
        manager.load(from: env["NETDECK_SSH_CONFIG"].map { URL(fileURLWithPath: $0) } ?? SessionManager.defaultConfigURL)
        return respond(question: question, environment: env, manager: manager, store: KeychainStore(),
                       ledger: CredentialLedger.shared(), tty: tty, state: stateFile(session: env["NETDECK_SESSION"]))
    }

    /// La misma decisiÃ³n que usa el ayudante real, con sus lÃ­mites de E/S inyectados (los tests no abren el Llavero ni
    /// un terminal). SÃ³lo se leen las candidatas propias del extremo preguntado; nunca la predeterminada de equipos.
    @MainActor
    static func respond(question: String, environment env: [String: String], manager: SessionManager,
                        store: CredentialStore, ledger: CredentialLedger, tty: AskpassUI, state: URL,
                        directory: URL = AppPaths.sessions, reply: @escaping (String) -> Int32 = answer) -> Int32 {
        if git.matches(question) { return 1 }
        // (el nombre del archivo de la pestaÃ±a: sÃ³lo un UUID, nada que se salga de la carpeta)
        let session = env["NETDECK_SESSION"].flatMap(UUID.init(uuidString:))?.uuidString
        guard let account = questions.lazy.compactMap({ $0.group(1, in: question) }).first,
              let at = account.lastIndex(of: "@") else {
            let secret = isSecret(question)
            // (si tras un OTP vuelve a pedir contraseÃ±a, no sabemos si rechazÃ³ Ã©sta o el cÃ³digo)
            if secret { try? SafeFile.write("", to: state) }
            tty.say(question)                                  // yes/no, passphrase, OTPâ€¦: contesta la persona
            guard let a = tty.read(secret: secret) else {
                // (Esc en un OTP: si luego ssh dice Â«Permission deniedÂ», no es que la contraseÃ±a no valga)
                note(hostField(askedAccount.group(2, in: question) ?? "") + "\t" + cancelMark, session: session, directory: directory)
                return 1
            }
            if secret {
                note(hostField(askedAccount.group(2, in: question) ?? "") + "\t" + factorMark, session: session, directory: directory)
            }
            return reply(a)
        }
        let user = String(account[..<at]), host = String(account[account.index(after: at)...])
        let route = env[routeVariable].flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(ConnectionRoute.self, from: $0) }
            ?? env[profileVariable].flatMap(manager.profile(named:)).flatMap { try? manager.route(to: $0) }
        let scope = manager.initialCredentialScope(account: Endpoint(user: user, host: host), route: route)
        let ask = Asker(tty: tty, account: account, user: user, host: host, named: scope.named,
                        store: store, ledger: ledger, state: state, session: session, directory: directory, reply: reply)

        if let session { confirmEarlier(session: session, host: host, ledger: ledger, directory: directory) }
        // ssh vuelve a preguntar enseguida: la que le dimos no valÃ­a â†’ te la pide a ti (un solo intento por pregunta; no
        // se bloquea: eso es sÃ³lo de la por defecto escrita sola)
        if let used = ask.recentlyGiven() {
            tty.say(L("\(red)\(marker) la contraseÃ±a guardada Â«\(used.ref)Â» no ha funcionado en \(account): escrÃ­bela tÃº\(reset)\n"))
            return ask.user(failed: used.ref)
        }
        if ask.typedRecently() || env[manualFlag] == "1" { return ask.user(failed: nil) }
        let request = PasswordRequest(line: question, account: account)
        // (un Llavero que no contesta no es Â«no hay ninguna guardadaÂ»: se dice y te la pide)
        let (candidates, lookupFailed) = store.availability(scope.candidates)
        if lookupFailed {
            tty.say("\(yellow)\(marker) \(explain(.keychainUnavailable))\(reset)\n")
            return ask.user(failed: nil)
        }
        // (las de la sesiÃ³n no se bloquean: un rechazo en otra pestaÃ±a no impide probarla aquÃ­ una vez)
        switch CredentialPolicy().decide(request, commandUser: nil, candidates: candidates, isBlocked: { _ in false }) {
        case .manual(let why):
            if why != .noCredential { tty.say("\(yellow)\(marker) \(explain(why))\(reset)\n") }
            return ask.user(failed: nil)
        case .inject(let ref):
            switch store.read(ref) {
            case .found(let pw):
                ask.given(ref)
                return reply(pw)
            case .missing: return ask.user(failed: ref)
            case .failed:
                tty.say("\(yellow)\(marker) \(explain(.keychainUnavailable))\(reset)\n")
                return ask.user(failed: nil)
            }
        }
    }

    public static func explain(_ why: ManualReason) -> String {
        switch why {
        case .changeOrConfirm: L("piden una contraseÃ±a nueva o repetida: escrÃ­bela tÃº")
        case .userMismatch(let u): L("ninguna guardada es de Â«\(u)Â»: escrÃ­bela tÃº")
        case .conflictingUsers(let c, let p): L("la orden dice Â«\(c)Â» y el prompt Â«\(p)Â»: escrÃ­bela tÃº")
        case .recentlyFailed(let r): L("Â«\(r)Â» fallÃ³ hace poco: no se escribe sola (cuenta AD)")
        case .pendingAttempt(let r):
            L("otra autenticaciÃ³n con Â«\(r)Â» sigue pendiente; escrÃ­bela a mano o, si ya terminÃ³, restablÃ©cela en Ajustes â†’ ContraseÃ±as â†’ Â«Restablecer pendienteÂ»")
        case .unknownUser: L("no se sabe quÃ© usuario la pide: escrÃ­bela tÃº")
        case .noCredential: L("no hay ninguna guardada")
        case .keychainUnavailable: L("no se ha podido leer el Llavero (Â¿bloqueado?): escrÃ­bela tÃº")
        }
    }

    // MARK: - estado

    /// La variable con el nombre de la sesiÃ³n guardada de la pestaÃ±a.
    static let profileVariable = "NETDECK_PROFILE"
    static let routeVariable = "NETDECK_AUTH_ROUTE"

    /// Lo que queda de pestaÃ±as que ya no estÃ¡n (la app se cerrÃ³ sin resolver sus intentos, un explorador que se
    /// cortÃ³): fuera pasado un dÃ­a. Lleva cuentas y equipos, nunca contraseÃ±as. Devuelve cuÃ¡ntos se han borrado.
    @discardableResult
    public static func purgeStale(in directory: URL = AppPaths.sessions, olderThan age: TimeInterval = 24 * 3600,
                                  now: Date = Date()) -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        var removed = 0
        for f in files where !f.lastPathComponent.hasPrefix("ndapp-askpass.") && !f.lastPathComponent.hasPrefix(".") {
            guard let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(m) > age, (try? fm.removeItem(at: f)) != nil else { continue }
            removed += 1
        }
        return removed
    }

    /// Un archivo por cada ssh (sesiÃ³n y PID): quÃ© contraseÃ±a guardada se le dio. Si vuelve a preguntar, no valÃ­a.
    /// (el UUID evita heredar un intento si macOS reutiliza el PID de otra conexiÃ³n reciÃ©n cerrada)
    static func stateFile(session: String? = nil) -> URL {
        let dir = AppPaths.ensure(AppPaths.sessions)
        purgeStale(in: dir)
        purgeStates(in: dir)
        let id = session.flatMap(UUID.init(uuidString:))?.uuidString ?? "externa"
        #if os(Windows)
        return dir.appendingPathComponent("ndapp-askpass.\(id).\(ProcessInfo.processInfo.processIdentifier)")
        #else
        return dir.appendingPathComponent("ndapp-askpass.\(id).\(getppid())")
        #endif
    }

    /// Fuera los de ssh que ya no estÃ¡n (pasados 10 min) y, aunque siga vivo, los de mÃ¡s de un dÃ­a: el de un ssh vivo
    /// que repregunta tarde se queda, para no volver a darle la guardada que ya fallÃ³.
    static func purgeStates(in dir: URL, now: Date = Date(), alive: (pid_t) -> Bool = { pid in
        #if os(Windows)
        return false
        #else
        return kill(pid, 0) == 0 || errno == EPERM
        #endif
    }) {
        guard let old = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for f in old where f.lastPathComponent.hasPrefix("ndapp-askpass.") {
            guard let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
            let age = now.timeIntervalSince(m)
            let pid = f.pathExtension.isEmpty ? nil : pid_t(f.pathExtension)
            if age > 24 * 3600 || (age > 600 && !(pid.map { $0 > 1 && alive($0) } ?? false)) {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }

    static func encode(_ r: CredentialRef) -> String { "\(r.service.rawValue)\t\(r.account)" }

    /// Una lÃ­nea del archivo de la pestaÃ±a: Â«@equipo\tservicio\tcuentaÂ» (el equipo al que se dio; las de antes, sin Ã©l).
    /// (el equipo sale de la pregunta: sin tabuladores ni caracteres de control, que moverÃ­an los campos)
    static func encodeGiven(_ r: CredentialRef, host: String) -> String { "\(hostField(host))\t\(encode(r))" }

    /// Escrita a mano sin guardar en `host`.
    static func encodeManual(host: String) -> String { "\(hostField(host))\t\(manualMark)" }

    static func hostField(_ host: String) -> String {
        "@" + host.filter { !$0.isNewline && $0 != "\t" && $0.asciiValue.map { $0 >= 32 && $0 != 127 } ?? true }
    }

    /// Escrita a mano sin guardarla: Â«@equipo\ta-manoÂ» (cuenta como intento, pero no es ninguna guardada).
    static let manualMark = "a-mano"
    /// Esc en una pregunta: Â«@equipo\tcanceladaÂ».
    static let cancelMark = "cancelada"
    /// Un factor manual distinto de la contraseÃ±a (no se guarda la respuesta).
    static let factorMark = "factor-manual"

    /// Apunta en el archivo de la pestaÃ±a una lÃ­nea mÃ¡s (sin pisar las de antes).
    static func note(_ line: String, session: String?, directory: URL = AppPaths.sessions) {
        guard let session else { return }
        let url = AppPaths.ensure(directory).appendingPathComponent(session)
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? SafeFile.write(old + line + "\n", to: url)
    }

    /// Sin eco: lo que parece secreto, salvo las de sÃ­/no (la de la clave del equipo lleva su nombre, que puede casar).
    static func isSecret(_ question: String) -> Bool {
        !question.lowercased().contains("(yes/no") && secretQuestion.matches(question)
    }
    static let askedAccount = Pattern(#"^\(([^ )]+)@([^ )]+)\)"#)

    static func decodeAttempt(_ s: String) -> Attempt? {
        if s.hasPrefix("@") {
            let (h, _, rest) = String(s.dropFirst()).partition("\t")
            if rest == manualMark { return Attempt(ref: nil, host: h.isEmpty ? nil : h) }
            if rest == cancelMark { return Attempt(ref: nil, host: h.isEmpty ? nil : h, cancelled: true) }
            if rest == factorMark { return Attempt(ref: nil, host: h.isEmpty ? nil : h, manualFactor: true) }
        }
        return decodeGiven(s).map { Attempt(ref: $0.ref, host: $0.host) }
    }

    static func decodeGiven(_ s: String) -> (ref: CredentialRef, host: String?)? {
        guard s.hasPrefix("@") else { return decode(s).map { ($0, nil) } }
        let (h, _, rest) = String(s.dropFirst()).partition("\t")
        return decode(rest).map { ($0, h.isEmpty ? nil : h) }
    }

    static func decode(_ s: String) -> CredentialRef? {
        let (svc, _, acct) = s.partition("\t")
        guard let service = CredentialRef.Service(rawValue: svc), !acct.isEmpty else { return nil }
        return CredentialRef(service: service, account: acct)
    }

    static func answer(_ s: String) -> Int32 {
        // (ssh puede haberse ido mientras se preguntaba: una tuberÃ­a rota no tumba el askpass con un informe de fallo)
        do { try FileHandle.standardOutput.write(contentsOf: Data((s + "\n").utf8)) } catch { return 1 }
        return 0
    }

    /// Lo que se pregunta a la persona (en la pestaÃ±a) y lo que se apunta.
    struct Asker {
        let tty: AskpassUI
        let account: String, user: String, host: String
        let named: String?
        let store: CredentialStore
        let ledger: CredentialLedger
        let state: URL
        let session: String?
        var directory: URL = AppPaths.sessions
        var reply: (String) -> Int32 = Askpass.answer

        /// La que se dio a esta misma pregunta en este mismo ssh, y cuÃ¡ndo (la hora del archivo de estado). Sin lÃ­mite
        /// de tiempo: el archivo es de este ssh (sesiÃ³n y PID), y si repregunta tarde (un TACACS lento) tampoco valÃ­a.
        func recentlyGiven() -> (ref: CredentialRef, at: Date)? {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: state.path),
                  let m = attrs[.modificationDate] as? Date,
                  let text = try? String(contentsOf: state, encoding: .utf8) else { return nil }
            guard let given = decodeGiven(text.trimmed), given.host == account else { return nil }
            return (given.ref, m)
        }

        /// La Ãºltima respuesta a esta pregunta en este ssh la escribiste tÃº sin guardarla: si ssh vuelve a preguntar,
        /// tampoco valÃ­a y se te pregunta otra vez (no se prueba sola la guardada que ya fallÃ³ en este ssh).
        func typedRecently() -> Bool {
            guard let text = try? String(contentsOf: state, encoding: .utf8) else { return false }
            return text.trimmed == encodeManual(host: account)
        }

        func given(_ ref: CredentialRef?) {
            try? SafeFile.write(ref.map { encodeGiven($0, host: account) } ?? encodeManual(host: account), to: state)
            guard let session else { return }
            // (tambiÃ©n la escrita a mano sin guardar: asÃ­, si entra, no se confirma la guardada que fallÃ³ antes)
            let line = ref.map { encodeGiven($0, host: host) } ?? encodeManual(host: host)
            let url = AppPaths.ensure(directory).appendingPathComponent(session)
            let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? SafeFile.write(old + line + "\n", to: url)
        }

        /// Te la pide y te ofrece guardarla (Intro = sÃ­). Ctrl+C en la pregunta de guardar cancela la autenticaciÃ³n.
        func user(failed: CredentialRef?) -> Int32 {
            tty.say(L("\(cyan)\(marker) Esc = cancelar\(reset)\n\(marker) \(account)'s password: "))
            // (vacÃ­a â€”un Intro de mÃ¡sâ€”: se vuelve a pedir; mandarla serÃ­a un fallo mÃ¡s en la cuenta, y guardarla
            // sustituirÃ­a la buena)
            var typed = tty.read(secret: true)
            for _ in 0..<2 where typed?.isEmpty == true {
                tty.say(L("\(yellow)\(marker) estÃ¡ vacÃ­a: escrÃ­bela o pulsa Esc para cancelar\(reset)\n\(marker) \(account)'s password: "))
                typed = tty.read(secret: true)
            }
            guard let pw = typed, !pw.isEmpty else {
                tty.say(L("\(yellow)\(marker) cancelado\(reset)\n"))
                note(hostField(host) + "\t" + cancelMark, session: session, directory: directory)
                return 1
            }
            // (Intro = sÃ­: la respuesta es una pulsaciÃ³n nueva, el TTY descarta lo que quedara de antes)
            let target = named.map(CredentialRef.named) ?? .device(user, host)
            let question = named.map { L("Â¿Guardarla como Â«\($0)Â»?") }
                ?? L("Â¿Guardar la \(failed != nil ? L("nueva ") : "")contraseÃ±a de \(account) en el Llavero?")
            guard let yes = tty.yesNo(question + (store.contains(target) ? L(" (sustituye la guardada)") : ""), default: true) else {
                DebugLog.log("askpass", "guardar: cancelado con Ctrl+C (\(target))")
                tty.say(L("\(yellow)\(marker) cancelado\(reset)\n"))
                note(hostField(host) + "\t" + cancelMark, session: session, directory: directory)
                return 1
            }
            DebugLog.log("askpass", "guardar=\(yes ? "sÃ­" : "no") (\(target))")
            var saved: CredentialRef?
            if yes {
                do {
                    try store.save(pw, for: target)
                    ledger.reset(target)
                    saved = target
                    tty.say(L("\(green)\(marker) guardada âœ“\(reset)\n"))
                    if tty.reportsSaved { noteSaved(target, ok: true, session: session, directory: directory) }
                } catch {
                    // (nunca la salida de security en la pestaÃ±a: podrÃ­a llevar la orden con la contraseÃ±a)
                    ErrorLog.warning("askpass", "no se ha podido guardar Â«\(target)Â» en el Llavero")
                    tty.say(L("\(red)\(marker) no guardada: el Llavero no la ha aceptado\(reset)\n"))
                    if tty.reportsSaved { noteSaved(target, ok: false, session: session, directory: directory) }
                }
            } else {
                tty.say(L("\(marker) no guardada\n"))
            }
            given(saved)
            return reply(pw)
        }
    }
}

extension Askpass {
    /// Sin pestaÃ±a (SFTP): si se ha guardado lo dice la app (`takeSaved`), no otra ventana que pararÃ­a a ssh.
    /// Â«<sesiÃ³n>.guardadoÂ»: una lÃ­nea Â«ok|fallo\tservicio\tcuentaÂ» por intento; nunca la contraseÃ±a.
    static func noteSaved(_ ref: CredentialRef, ok: Bool, session: String?, directory: URL = AppPaths.sessions) {
        guard let session else { return }
        let url = AppPaths.ensure(directory).appendingPathComponent(session + ".guardado")
        let old = (try? SafeFile.read(url)) ?? nil
        try? SafeFile.write((old ?? "") + (ok ? "ok" : "fallo") + "\t" + encode(ref) + "\n", to: url)
    }

    /// Lo que ha guardado (o no) el askpass de esa conexiÃ³n; se borra al leerlo.
    public static func takeSaved(session: UUID, directory: URL = AppPaths.sessions) -> [(ref: CredentialRef, ok: Bool)] {
        let url = directory.appendingPathComponent(session.uuidString + ".guardado")
        guard let text = (try? SafeFile.read(url)) ?? nil else { return [] }
        try? FileManager.default.removeItem(at: url)
        return text.components(separatedBy: "\n").compactMap { line in
            let (mark, _, rest) = line.partition("\t")
            guard mark == "ok" || mark == "fallo", let ref = decode(rest) else { return nil }
            return (ref, mark == "ok")
        }
    }
}

/// DÃ³nde pregunta el askpass: la pestaÃ±a (/dev/tty) o una ventana de la app.
public protocol AskpassUI: AnyObject {
    /// Sin pestaÃ±a donde decirlo: el resultado de guardarla se apunta para que lo diga la app (`Askpass.takeSaved`).
    var reportsSaved: Bool { get }
    func say(_ s: String)
    /// Una lÃ­nea; nil = Esc, Ctrl+C o la pestaÃ±a cerrada.
    func read(secret: Bool) -> String?
    /// SÃ­ o no (Esc = no); nil = Ctrl+C: se cancela la autenticaciÃ³n.
    func yesNo(_ question: String, default d: Bool) -> Bool?
}

public extension AskpassUI {
    var reportsSaved: Bool { false }
}

/// CÃ³mo acaba la lectura de una lÃ­nea en la pestaÃ±a.
enum TTYLine: Equatable {
    case line(String), escape, interrupt, closed

    /// Las teclas de una lÃ­nea (aparte del terminal, para probarlo). `next(nil)` espera lo que haga falta y
    /// `next(n)`, como mucho n dÃ©cimas; `unread` devuelve un byte que es de la pregunta siguiente. Intro tambiÃ©n es el
    /// del teclado numÃ©rico (Â«ESC O MÂ») y âŒ¥+Intro (Â«ESC âŽÂ»); un CR+LF pegado es un solo Intro. Las flechas y F1â€¦
    /// (Â«ESC [ â€¦Â» / Â«ESC O xÂ») se ignoran enteras; Esc sola cancela.
    /// `skipLeadingLF`: lo anterior acabÃ³ en CR; un LF que llega tarde es su otra mitad, no una respuesta.
    static func read(secret: Bool, skipLeadingLF: Bool = false, next: (UInt8?) -> UInt8?, unread: (UInt8) -> Void,
                     echo: (String) -> Void) -> TTYLine {
        var data: [UInt8] = []
        var skipLF = skipLeadingLF
        func done(_ b: UInt8) -> TTYLine {
            if b == 13, let n = next(0), n != 10 { unread(n) }
            return .line(String(decoding: data, as: UTF8.self))
        }
        while true {
            guard let b = next(nil) else { return .closed }      // (la pestaÃ±a se ha cerrado: no lo tecleado a medias)
            if skipLF { skipLF = false; if b == 10 { continue } }
            switch b {
            case 10, 13:
                return done(b)
            case 0x03:
                return .interrupt
            case 0x1B:
                guard let n1 = next(1) else { return .escape }
                if n1 == 13 || n1 == 10 { return done(n1) }
                if n1 == UInt8(ascii: "O") {
                    if let n2 = next(1), n2 == UInt8(ascii: "M") { return done(13) }
                } else if n1 == UInt8(ascii: "[") {
                    while let c = next(1), !(0x40...0x7E).contains(c) {}
                } else {
                    return .escape
                }
            case 0x7F, 0x08:
                if !data.isEmpty {
                    while let last = data.last, last & 0xC0 == 0x80 { data.removeLast() }
                    data.removeLast()
                    if !secret { echo("\u{8} \u{8}") }
                }
            case 0x15:
                if !secret { echo(String(repeating: "\u{8} \u{8}", count: String(decoding: data, as: UTF8.self).count)) }
                data = []
            default:
                if b >= 0x20 {
                    data.append(b)
                    if !secret { echo(String(decoding: [b], as: UTF8.self)) }
                }
            }
        }
    }

    /// Lo que siga llegando del pegado (la cola de un CR+LF partido, un CR repetido): se tira hasta que haya `tenths`
    /// dÃ©cimas sin nada (como mucho `limit` bytes). Devuelve cuÃ¡ntos.
    @discardableResult
    static func drain(within tenths: UInt8 = 3, limit: Int = 4096, next: (UInt8?) -> UInt8?) -> Int {
        var n = 0
        while n < limit, next(tenths) != nil { n += 1 }
        return n
    }
}

#if !os(Windows)
/// La pestaÃ±a de la sesiÃ³n (/dev/tty), no la salida que lee ssh.
final class TTY: AskpassUI {
    let fd: Int32
    /// Lo leÃ­do de mÃ¡s (lo que se escribe deprisa tras el Intro es para la pregunta siguiente).
    private var pending: [UInt8] = []

    init?() {
        fd = open("/dev/tty", O_RDWR | O_NOCTTY)
        if fd < 0 { return nil }
    }

    deinit { close(fd) }

    func say(_ s: String) {
        let d = Array(s.utf8)
        _ = d.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    /// CÃ³mo acabÃ³ la Ãºltima lectura (Ctrl+C o la pestaÃ±a cerrada cancelan la autenticaciÃ³n; Esc sÃ³lo dice Â«noÂ»).
    private var last = TTYLine.closed
    /// El Ãºltimo byte leÃ­do (un CR: un LF que llegue tarde es su otra mitad).
    private var lastByte: UInt8?

    /// Una lÃ­nea; nil = Esc o Ctrl+C. Tecla a tecla (para ver la Esc sin esperar al Intro): `TTYLine`.
    func read(secret: Bool) -> String? { readLine(secret: secret, fresh: false) }

    /// `fresh`: la respuesta tiene que ser una pulsaciÃ³n nueva; antes se tira lo que quede del pegado.
    private func readLine(secret: Bool, fresh: Bool) -> String? {
        var old = termios()
        tcgetattr(fd, &old)
        var raw = old
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
        withUnsafeMutableBytes(of: &raw.c_cc) { cc in
            cc[Int(VMIN)] = 1
            cc[Int(VTIME)] = 0
        }
        tcsetattr(fd, TCSANOW, &raw)
        defer {
            tcsetattr(fd, TCSANOW, &old)
            if secret { say("\n") }
        }
        func next(_ tenths: UInt8?) -> UInt8? {        // nil = esperar lo que haga falta
            let b = rawNext(tenths)
            if let b { lastByte = b }
            return b
        }
        var skipLF = false
        if fresh {
            pending = []
            TTYLine.drain { byte(within: $0 ?? 3) }
            tcflush(fd, TCIFLUSH)
            skipLF = lastByte == 13
        }
        last = TTYLine.read(secret: secret, skipLeadingLF: skipLF, next: next, unread: { pending.insert($0, at: 0) }, echo: say)
        if case .line(let s) = last { return s }
        return nil
    }

    private func rawNext(_ tenths: UInt8?) -> UInt8? {
        if !pending.isEmpty { return pending.removeFirst() }
        if let tenths { return byte(within: tenths) }
        var buf = [UInt8](repeating: 0, count: 256)
        let n = Darwin.read(fd, &buf, buf.count)
        guard n > 0 else { return nil }
        pending = Array(buf[1..<n])
        return buf[0]
    }

    func yesNo(_ question: String, default d: Bool) -> Bool? {
        say(L("\(Askpass.cyan)\(Askpass.marker) \(question) \(d ? L("[S/n]") : L("[s/N]")) (Esc = no)\(Askpass.reset) "))
        // (la respuesta tiene que ser una pulsaciÃ³n nueva: lo pegado o tecleado de mÃ¡s antes no contesta solo)
        guard let r = readLine(secret: false, fresh: true)?.trimmed.lowercased() else {
            say("\n")
            return last == .escape ? false : nil
        }
        say("\n")
        return r.isEmpty ? d : ["s", "si", "sÃ­", "y", "yes"].contains(r)
    }

    /// Un byte si llega en `tenths` dÃ©cimas de segundo (poll() no sirve con /dev/tty en macOS).
    private func byte(within tenths: UInt8) -> UInt8? {
        var t = termios()
        tcgetattr(fd, &t)
        var timed = t
        withUnsafeMutableBytes(of: &timed.c_cc) { cc in
            cc[Int(VMIN)] = 0
            cc[Int(VTIME)] = tenths
        }
        tcsetattr(fd, TCSANOW, &timed)
        defer { tcsetattr(fd, TCSANOW, &t) }
        var b: UInt8 = 0
        return Darwin.read(fd, &b, 1) == 1 ? b : nil
    }
}
#else
// TODO P4e: implementar TTY con SetConsoleMode/ReadConsoleInput de Windows
final class TTY: AskpassUI {
    init?() { return nil }
    var reportsSaved: Bool { false }
    func say(_ s: String) {}
    func read(secret: Bool) -> String? { nil }
    func yesNo(_ question: String, default d: Bool) -> Bool? { nil }
}
#endif