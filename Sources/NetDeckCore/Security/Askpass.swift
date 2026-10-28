import Darwin
import Foundation

/// El SSH_ASKPASS de la app: el mismo ejecutable con NETDECK_ASKPASS=1. ssh lo llama con la pregunta y lee la
/// respuesta, así que la contraseña de cada SESIÓN (y de sus saltos con -J) entra sola al abrirla, sin teclearla en el
/// terminal, como en cualquier cliente SSH:
///  · sólo la con nombre de ese perfil o la de su usuario@equipo, con usuario estricto;
///  · un intento: si ssh vuelve a preguntar, no valía → te la pide a ti (no se bloquea: el bloqueo de 15 min es sólo
///    de la por defecto escrita sola dentro de una sesión, `PasswordAutomation`);
///  · sin reservas ni esperas entre sesiones guardadas;
///  · cualquier otra pregunta (yes/no, passphrase, OTP…) te la hace a ti, en la pestaña. Esc cancela.
/// Lo que escribe en la pestaña empieza por «[NetDeck]»: el autocompletado de equipos no lo toma por una petición.
public enum Askpass {
    public static let flag = "NETDECK_ASKPASS"
    public static let marker = "[NetDeck]"

    static let questions = [Pattern(#"^(.+)'s password: ?$"#, ignoreCase: false),
                            Pattern(#"^\(([^ )]+@[^ )]+)\) ?[Pp]assword: ?$"#, ignoreCase: false)]
    static let git = Pattern(#"^(Username|Password) for '[^']*': ?$"#, ignoreCase: false)
    /// Lo que se contesta sin eco (no se ve ni queda en el historial de la pestaña ni en su registro). Sin distinguir
    /// mayúsculas: «Enter PASSCODE:» (SecurID) o «PASSWORD:» también; ante la duda, sin eco.
    static let secretQuestion = Pattern(#"assword|assphrase|asscode|ode|pin|otp|token|secret|response|challenge|clave|c[oó]digo"#)
    static let (red, cyan, green, yellow, reset) = ("\u{1b}[38;5;204m", "\u{1b}[38;5;51m", "\u{1b}[38;5;48m",
                                                     "\u{1b}[38;5;221m", "\u{1b}[0m")

    /// Sólo preguntar (sin escribir ninguna guardada): el explorador SFTP con la contraseña automática apagada.
    public static let manualFlag = "NETDECK_ASKPASS_MANUAL"

    /// Variables para el proceso ssh de una pestaña. `manual`: no se prueba ninguna guardada, se pregunta siempre.
    /// `profile`: la sesión guardada; `route`: sus extremos exactos, también al conectar sin guardar. La predeterminada
    /// no va: el askpass no la usa (sólo el salto desde DENTRO de una sesión, en la app) y su nombre y usuario los
    /// vería todo lo que cuelga de ssh.
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

    /// Las contraseñas que el askpass ha dado a esa pestaña (para confirmarlas cuando llega al prompt).
    public static func takeGiven(session: UUID) -> [CredentialRef] { takeAttempts(session: session).compactMap(\.ref) }

    /// Un intento de entrar en `host`: con una guardada (`ref`) o escrita a mano sin guardar (nil).
    public struct Attempt: Equatable, Sendable {
        public var ref: CredentialRef?
        public var host: String?
        /// Esc en una pregunta (la contraseña, un OTP…): lo que venga después no es un rechazo de la contraseña.
        public var cancelled: Bool
        /// Una pregunta secreta manual posterior (OTP, passphrase…): su rechazo no demuestra que fallase la contraseña.
        public var manualFactor: Bool
        public init(ref: CredentialRef?, host: String?, cancelled: Bool = false, manualFactor: Bool = false) {
            self.ref = ref; self.host = host; self.cancelled = cancelled; self.manualFactor = manualFactor
        }
    }

    /// Los intentos de esa pestaña, en orden (y se olvidan).
    public static func takeAttempts(session: UUID) -> [Attempt] {
        takeAttempts(at: AppPaths.sessions.appendingPathComponent(session.uuidString))
    }

    static func takeAttempts(at url: URL) -> [Attempt] {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).compactMap(decodeAttempt)
    }

    /// Ya ha entrado: de cada equipo sólo vale el último intento (ssh no pasa de ahí sin entrar); los de antes en ese
    /// equipo no valían. Si el último fue a mano, no se confirma ninguna guardada (la rechazada sigue bloqueada y el
    /// reintento a mano no la desbloquea). Las de otros equipos (los saltos) han entrado.
    public static func attribute(_ attempts: [Attempt]) -> (confirmed: [CredentialRef], failed: [CredentialRef]) {
        let attempts = attempts.filter { !$0.manualFactor }      // (un OTP no es un reintento de la contraseña)
        var last: [String: Int] = [:]
        for (i, a) in attempts.enumerated() { last[a.host?.lowercased() ?? ""] = i }
        var confirmed: [CredentialRef] = [], failed: [CredentialRef] = []
        for (i, a) in attempts.enumerated() {
            guard let ref = a.ref else { continue }
            if last[a.host?.lowercased() ?? ""] == i { if !confirmed.contains(ref) { confirmed.append(ref) } }
        }
        for a in attempts {
            guard let ref = a.ref, !confirmed.contains(ref), !failed.contains(ref) else { continue }
            failed.append(ref)
        }
        return (confirmed, failed)
    }

    /// Lo que dice ssh al terminar sin entrar cuando no valía la contraseña, y de qué equipo, si lo dice
    /// («tu.usuario@core-01: Permission denied (…)»). `fromAddress`: es la dirección de la conexión («Connection
    /// closed by 192.0.2.10 port 22»), no el nombre con que preguntó (el HostName del prompt).
    public struct Rejection: Equatable, Sendable {
        public var host: String?
        public var fromAddress: Bool
        public init(host: String? = nil, fromAddress: Bool = false) { self.host = host; self.fromAddress = fromAddress }
    }

    /// ¿Dicen estas líneas (las últimas de la pantalla o el error de ssh) que no valía? «Permission denied», «Too many
    /// authentication failures», el equipo cortando la conexión a medio entrar… La última que lo diga manda; sin un
    /// equipo explícito se conserva el rechazo, pero no se culpa a la última contraseña (podría ser la del salto).
    public static func rejection(in lines: [String]) -> Rejection? {
        guard let line = lines.last(where: { PromptRule.authenticationFailed($0) || exitRejection.matches($0) }) else { return nil }
        if let host = rejectedAccount.group(2, in: line) { return Rejection(host: host) }
        // (tras -J ssh no sabe la dirección del destino: «UNKNOWN» no es ningún equipo)
        guard let address = rejectedConnection.group(1, in: line), address.lowercased() != "unknown" else { return Rejection() }
        return Rejection(host: address, fromAddress: true)
    }
    public static func rejectedAtExit(_ lines: [String]) -> Bool { rejection(in: lines) != nil }
    /// (un corte «by UNKNOWN port 65535» es el salto, que no llega al destino: su contraseña sí valía)
    static let exitRejection = Pattern(#"authentication failures?|connection (?:closed|reset) by (?!unknown\b)"#)
    static let rejectedAccount = Pattern(#"(?:^|\s)([^@\s]+)@(.+?): permission denied"#)
    static let rejectedConnection = Pattern(#"(?:received disconnect from|connection (?:closed|reset) by) ([^\s]+?)(?: port \d+|:\d+:|$)"#)

    /// Sin llegar a entrar y con un rechazo: no valían las dadas al equipo que nombra ssh; las de los otros (los saltos)
    /// sí entraron. Sin un equipo explícito no se sabe cuál falló. Nada si no hay rechazo o si la persona
    /// canceló o respondió a otro factor después (un OTP rechazado no demuestra que la contraseña no valga).
    /// Si nombra un equipo al que no se dio ninguna, nunca se confirma nada: con su dirección (el intento guarda el
    /// nombre del prompt) y todo dado a un solo equipo con una sola guardada, es ésa; con un nombre, es otro equipo
    /// (el destino con clave tras el salto) y la del salto no tiene la culpa.
    public static func attributeRejection(_ attempts: [Attempt], rejection: Rejection?) -> (confirmed: [CredentialRef], failed: [CredentialRef]) {
        guard let rejection, let host = rejection.host?.lowercased(), !host.isEmpty,
              let last = attempts.last, !last.cancelled, !last.manualFactor else { return ([], []) }
        let valid = attempts.filter { !$0.cancelled && !$0.manualFactor }
        // (salto y destino pueden compartir IP con distintos usuarios: un rechazo que sólo dice host no los distingue)
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

    /// Una pestaña, un explorador o un túnel han terminado sin entrar: sus intentos, resueltos (`attributeRejection`).
    /// Las que han entrado se confirman; las que no, sólo se devuelven para decirlo (con «NumberOfPasswordPrompts 1» o
    /// un equipo que corta al primer fallo, ssh sale sin volver a preguntar). No se bloquean: son de la sesión. Sólo
    /// intentos recientes (`maxAge`: un rechazo mucho después no es de esa contraseña) y la pantalla sólo se mira si los
    /// hay. Devuelve las que no han valido.
    @discardableResult
    public static func settleAfterExit(session: UUID, ledger: CredentialLedger, maxAge: TimeInterval = 150, now: Date = Date(),
                                       directory: URL = AppPaths.sessions, rejection: () -> Rejection?) -> [CredentialRef] {
        let url = directory.appendingPathComponent(session.uuidString)
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let attempts = takeAttempts(at: url)
        guard !attempts.isEmpty, let modified, now.timeIntervalSince(modified) <= maxAge else { return [] }
        let (confirmed, failed) = attributeRejection(attempts, rejection: rejection())
        // (las de la sesión no se bloquean: sólo se dice cuál no ha valido; si la has guardado otra vez después de
        // darla, el rechazo era de la anterior y no se dice)
        confirmed.forEach(ledger.confirmDirect)
        let rejected = failed.filter { !ledger.wasReset($0, after: modified) }
        if !failed.isEmpty {
            DebugLog.log("askpass", "rechazada al terminar: \(failed.map(\.description).joined(separator: ", "))"
                         + (rejected.count < failed.count ? " (guardada otra vez después)" : ""))
        }
        return rejected
    }

    /// En la pestaña `session` ssh pregunta ya por `host`: las dadas antes a OTROS equipos de esa pestaña (los saltos)
    /// han entrado (ssh no pasa al siguiente sin haber entrado en el salto) → confirmadas, y las pestañas que esperaban
    /// siguen ya, sin esperar a todo el login del destino. Si la del salto no valiera, ssh volvería a preguntar por el
    /// mismo salto: ésa no se confirma aquí y se marca fallo como siempre. Devuelve las confirmadas.
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

    /// `dialog`: sin terminal (SFTP, procesos sin pestaña), la app pregunta en una ventana.
    @MainActor
    public static func run(arguments: [String], environment env: [String: String],
                           dialog: (() -> AskpassUI?)? = nil) -> Int32 {
        let question = arguments.dropFirst().first ?? ""
        if git.matches(question) { return 1 }                 // (las de git no son nuestras)
        guard let tty: AskpassUI = TTY() ?? dialog?() else { return 1 }
        DebugLog.log("askpass", "pregunta «\(question)» (\(tty is TTY ? "en la pestaña" : "en una ventana"))")
        let manager = SessionManager()
        manager.load(from: env["NETDECK_SSH_CONFIG"].map { URL(fileURLWithPath: $0) } ?? SessionManager.defaultConfigURL)
        return respond(question: question, environment: env, manager: manager, store: KeychainStore(),
                       ledger: CredentialLedger.shared(), tty: tty, state: stateFile(session: env["NETDECK_SESSION"]))
    }

    /// La misma decisión que usa el ayudante real, con sus límites de E/S inyectados (los tests no abren el Llavero ni
    /// un terminal). Sólo se leen las candidatas propias del extremo preguntado; nunca la predeterminada de equipos.
    @MainActor
    static func respond(question: String, environment env: [String: String], manager: SessionManager,
                        store: CredentialStore, ledger: CredentialLedger, tty: AskpassUI, state: URL,
                        directory: URL = AppPaths.sessions, reply: @escaping (String) -> Int32 = answer) -> Int32 {
        if git.matches(question) { return 1 }
        // (el nombre del archivo de la pestaña: sólo un UUID, nada que se salga de la carpeta)
        let session = env["NETDECK_SESSION"].flatMap(UUID.init(uuidString:))?.uuidString
        guard let account = questions.lazy.compactMap({ $0.group(1, in: question) }).first,
              let at = account.lastIndex(of: "@") else {
            let secret = isSecret(question)
            // (si tras un OTP vuelve a pedir contraseña, no sabemos si rechazó ésta o el código)
            if secret { try? SafeFile.write("", to: state) }
            tty.say(question)                                  // yes/no, passphrase, OTP…: contesta la persona
            guard let a = tty.read(secret: secret) else {
                // (Esc en un OTP: si luego ssh dice «Permission denied», no es que la contraseña no valga)
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
        // ssh vuelve a preguntar enseguida: la que le dimos no valía → te la pide a ti (un solo intento por pregunta; no
        // se bloquea: eso es sólo de la por defecto escrita sola)
        if let used = ask.recentlyGiven() {
            tty.say(L("\(red)\(marker) la contraseña guardada «\(used.ref)» no ha funcionado en \(account): escríbela tú\(reset)\n"))
            return ask.user(failed: used.ref)
        }
        if ask.typedRecently() || env[manualFlag] == "1" { return ask.user(failed: nil) }
        let request = PasswordRequest(line: question, account: account)
        // (un Llavero que no contesta no es «no hay ninguna guardada»: se dice y te la pide)
        let (candidates, lookupFailed) = store.availability(scope.candidates)
        if lookupFailed {
            tty.say("\(yellow)\(marker) \(explain(.keychainUnavailable))\(reset)\n")
            return ask.user(failed: nil)
        }
        // (las de la sesión no se bloquean: un rechazo en otra pestaña no impide probarla aquí una vez)
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
        case .changeOrConfirm: L("piden una contraseña nueva o repetida: escríbela tú")
        case .userMismatch(let u): L("ninguna guardada es de «\(u)»: escríbela tú")
        case .conflictingUsers(let c, let p): L("la orden dice «\(c)» y el prompt «\(p)»: escríbela tú")
        case .recentlyFailed(let r): L("«\(r)» falló hace poco: no se escribe sola (cuenta AD)")
        case .pendingAttempt(let r):
            L("otra autenticación con «\(r)» sigue pendiente; escríbela a mano o, si ya terminó, restablécela en Ajustes → Contraseñas → «Restablecer pendiente»")
        case .unknownUser: L("no se sabe qué usuario la pide: escríbela tú")
        case .noCredential: L("no hay ninguna guardada")
        case .keychainUnavailable: L("no se ha podido leer el Llavero (¿bloqueado?): escríbela tú")
        }
    }

    // MARK: - estado

    /// La variable con el nombre de la sesión guardada de la pestaña.
    static let profileVariable = "NETDECK_PROFILE"
    static let routeVariable = "NETDECK_AUTH_ROUTE"

    /// Lo que queda de pestañas que ya no están (la app se cerró sin resolver sus intentos, un explorador que se
    /// cortó): fuera pasado un día. Lleva cuentas y equipos, nunca contraseñas. Devuelve cuántos se han borrado.
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

    /// Un archivo por cada ssh (sesión y PID): qué contraseña guardada se le dio. Si vuelve a preguntar, no valía.
    /// (el UUID evita heredar un intento si macOS reutiliza el PID de otra conexión recién cerrada)
    static func stateFile(session: String? = nil) -> URL {
        let dir = AppPaths.ensure(AppPaths.sessions)
        purgeStale(in: dir)
        purgeStates(in: dir)
        let id = session.flatMap(UUID.init(uuidString:))?.uuidString ?? "externa"
        return dir.appendingPathComponent("ndapp-askpass.\(id).\(getppid())")
    }

    /// Fuera los de ssh que ya no están (pasados 10 min) y, aunque siga vivo, los de más de un día: el de un ssh vivo
    /// que repregunta tarde se queda, para no volver a darle la guardada que ya falló.
    static func purgeStates(in dir: URL, now: Date = Date(), alive: (pid_t) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) {
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

    /// Una línea del archivo de la pestaña: «@equipo\tservicio\tcuenta» (el equipo al que se dio; las de antes, sin él).
    /// (el equipo sale de la pregunta: sin tabuladores ni caracteres de control, que moverían los campos)
    static func encodeGiven(_ r: CredentialRef, host: String) -> String { "\(hostField(host))\t\(encode(r))" }

    /// Escrita a mano sin guardar en `host`.
    static func encodeManual(host: String) -> String { "\(hostField(host))\t\(manualMark)" }

    static func hostField(_ host: String) -> String {
        "@" + host.filter { !$0.isNewline && $0 != "\t" && $0.asciiValue.map { $0 >= 32 && $0 != 127 } ?? true }
    }

    /// Escrita a mano sin guardarla: «@equipo\ta-mano» (cuenta como intento, pero no es ninguna guardada).
    static let manualMark = "a-mano"
    /// Esc en una pregunta: «@equipo\tcancelada».
    static let cancelMark = "cancelada"
    /// Un factor manual distinto de la contraseña (no se guarda la respuesta).
    static let factorMark = "factor-manual"

    /// Apunta en el archivo de la pestaña una línea más (sin pisar las de antes).
    static func note(_ line: String, session: String?, directory: URL = AppPaths.sessions) {
        guard let session else { return }
        let url = AppPaths.ensure(directory).appendingPathComponent(session)
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? SafeFile.write(old + line + "\n", to: url)
    }

    /// Sin eco: lo que parece secreto, salvo las de sí/no (la de la clave del equipo lleva su nombre, que puede casar).
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
        // (ssh puede haberse ido mientras se preguntaba: una tubería rota no tumba el askpass con un informe de fallo)
        do { try FileHandle.standardOutput.write(contentsOf: Data((s + "\n").utf8)) } catch { return 1 }
        return 0
    }

    /// Lo que se pregunta a la persona (en la pestaña) y lo que se apunta.
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

        /// La que se dio a esta misma pregunta en este mismo ssh, y cuándo (la hora del archivo de estado). Sin límite
        /// de tiempo: el archivo es de este ssh (sesión y PID), y si repregunta tarde (un TACACS lento) tampoco valía.
        func recentlyGiven() -> (ref: CredentialRef, at: Date)? {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: state.path),
                  let m = attrs[.modificationDate] as? Date,
                  let text = try? String(contentsOf: state, encoding: .utf8) else { return nil }
            guard let given = decodeGiven(text.trimmed), given.host == account else { return nil }
            return (given.ref, m)
        }

        /// La última respuesta a esta pregunta en este ssh la escribiste tú sin guardarla: si ssh vuelve a preguntar,
        /// tampoco valía y se te pregunta otra vez (no se prueba sola la guardada que ya falló en este ssh).
        func typedRecently() -> Bool {
            guard let text = try? String(contentsOf: state, encoding: .utf8) else { return false }
            return text.trimmed == encodeManual(host: account)
        }

        func given(_ ref: CredentialRef?) {
            try? SafeFile.write(ref.map { encodeGiven($0, host: account) } ?? encodeManual(host: account), to: state)
            guard let session else { return }
            // (también la escrita a mano sin guardar: así, si entra, no se confirma la guardada que falló antes)
            let line = ref.map { encodeGiven($0, host: host) } ?? encodeManual(host: host)
            let url = AppPaths.ensure(directory).appendingPathComponent(session)
            let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? SafeFile.write(old + line + "\n", to: url)
        }

        /// Te la pide; te ofrece guardarla (si la guardada falló, por defecto sí).
        func user(failed: CredentialRef?) -> Int32 {
            tty.say(L("\(cyan)\(marker) Esc = cancelar\(reset)\n\(marker) \(account)'s password: "))
            // (vacía —un Intro de más—: se vuelve a pedir; mandarla sería un fallo más en la cuenta, y guardarla
            // sustituiría la buena)
            var typed = tty.read(secret: true)
            for _ in 0..<2 where typed?.isEmpty == true {
                tty.say(L("\(yellow)\(marker) está vacía: escríbela o pulsa Esc para cancelar\(reset)\n\(marker) \(account)'s password: "))
                typed = tty.read(secret: true)
            }
            guard let pw = typed, !pw.isEmpty else {
                tty.say(L("\(yellow)\(marker) cancelado\(reset)\n"))
                note(hostField(host) + "\t" + cancelMark, session: session, directory: directory)
                return 1
            }
            var saved: CredentialRef?
            // (sin una guardada que fallase, por defecto no: un Intro de más no pisa «named» con otra)
            if let named, tty.yesNo(L("¿Guardarla como «\(named)»?"), default: failed != nil) == true {
                saved = .named(named)
            } else if named == nil,
                      tty.yesNo(L("¿Guardar la \(failed != nil ? L("nueva ") : "")contraseña de \(account) en el Llavero?"),
                                default: failed != nil) == true {
                saved = .device(user, host)
            }
            if let s = saved {
                do {
                    try store.save(pw, for: s)
                    ledger.reset(s)
                    tty.say(L("\(green)\(marker) guardada ✓\(reset)\n"))
                } catch {
                    tty.say("\(red)\(marker) \(error.localizedDescription)\(reset)\n")
                    saved = nil
                }
            }
            given(saved)
            return reply(pw)
        }
    }
}

/// Dónde pregunta el askpass: la pestaña (/dev/tty) o una ventana de la app.
public protocol AskpassUI: AnyObject {
    func say(_ s: String)
    func read(secret: Bool) -> String?
    func yesNo(_ question: String, default d: Bool) -> Bool?
}

/// La pestaña de la sesión (/dev/tty), no la salida que lee ssh.
final class TTY: AskpassUI {
    let fd: Int32
    /// Lo leído de más (lo que se escribe deprisa tras el Intro es para la pregunta siguiente).
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

    /// Una línea; nil = Esc o Ctrl+C. Tecla a tecla (para ver la Esc sin esperar al Intro), sin confundirla con las
    /// flechas y F1… («ESC [ …» / «ESC O x», que se ignoran enteras).
    func read(secret: Bool) -> String? {
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
            if !pending.isEmpty { return pending.removeFirst() }
            if let tenths { return byte(within: tenths) }
            var buf = [UInt8](repeating: 0, count: 256)
            let n = Darwin.read(fd, &buf, buf.count)
            guard n > 0 else { return nil }
            pending = Array(buf[1..<n])
            return buf[0]
        }
        var data: [UInt8] = []
        while true {
            guard let b = next(nil) else { return nil }        // (la pestaña se ha cerrado: cancelado, no lo tecleado a medias)
            switch b {
            case 10, 13:
                return String(decoding: data, as: UTF8.self)
            case 0x03:
                return nil
            case 0x1B:
                guard let n1 = next(1), n1 == UInt8(ascii: "[") || n1 == UInt8(ascii: "O") else { return nil }  // Esc
                if n1 == UInt8(ascii: "O") {
                    _ = next(1)
                } else {
                    while let c = next(1), !(0x40...0x7E).contains(c) {}
                }
            case 0x7F, 0x08:
                if !data.isEmpty {
                    while let last = data.last, last & 0xC0 == 0x80 { data.removeLast() }
                    data.removeLast()
                    if !secret { say("\u{8} \u{8}") }
                }
            case 0x15:
                if !secret { say(String(repeating: "\u{8} \u{8}", count: String(decoding: data, as: UTF8.self).count)) }
                data = []
            default:
                if b >= 0x20 {
                    data.append(b)
                    if !secret { _ = withUnsafePointer(to: b) { write(fd, $0, 1) } }
                }
            }
        }
    }

    func yesNo(_ question: String, default d: Bool) -> Bool? {
        say(L("\(Askpass.cyan)\(Askpass.marker) \(question) \(d ? L("[S/n]") : L("[s/N]")) (Esc = no)\(Askpass.reset) "))
        guard let r = read(secret: false)?.trimmed.lowercased() else { say("\n"); return nil }
        say("\n")
        return r.isEmpty ? d : ["s", "si", "sí", "y", "yes"].contains(r)
    }

    /// Un byte si llega en `tenths` décimas de segundo (poll() no sirve con /dev/tty en macOS).
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
