import Darwin
import Foundation

/// El SSH_ASKPASS de la app: el mismo ejecutable con NETDECK_ASKPASS=1. ssh lo llama con la pregunta y lee la
/// respuesta, así que la contraseña de cada SESIÓN (y de sus saltos con -J) entra sola al abrirla, sin teclearla en el
/// terminal. Igual que «askpass» en NetDeck:
///  · la con nombre de esa sesión, la de usuario@equipo o la por defecto, con la regla de usuario;
///  · un intento: si ssh vuelve a preguntar, no valía → bloqueada 15 min en todas partes y te la pide a ti;
///  · si otra pestaña la está probando, espera a ver si vale;
///  · cualquier otra pregunta (yes/no, passphrase, OTP…) te la hace a ti, en la pestaña. Esc cancela.
/// Lo que escribe en la pestaña empieza por «[NetDeck]»: el autocompletado de equipos no lo toma por una petición.
public enum Askpass {
    public static let flag = "NETDECK_ASKPASS"
    public static let marker = "[NetDeck]"

    static let questions = [Pattern(#"^(.+)'s password: ?$"#, ignoreCase: false),
                            Pattern(#"^\(([^ )]+@[^ )]+)\) ?[Pp]assword: ?$"#, ignoreCase: false)]
    static let git = Pattern(#"^(Username|Password) for '[^']*': ?$"#, ignoreCase: false)
    static let secretQuestion = Pattern(#"assword|assphrase|ode|PIN|OTP"#, ignoreCase: false)
    static let (red, cyan, green, yellow, reset) = ("\u{1b}[38;5;204m", "\u{1b}[38;5;51m", "\u{1b}[38;5;48m",
                                                     "\u{1b}[38;5;221m", "\u{1b}[0m")

    /// Sólo preguntar (sin escribir ninguna guardada): el explorador SFTP con la contraseña automática apagada.
    public static let manualFlag = "NETDECK_ASKPASS_MANUAL"

    /// Variables para el proceso ssh de una pestaña. `manual`: no se prueba ninguna guardada, se pregunta siempre.
    public static func environment(executable: String, configPath: String?, defaultCredential: DefaultCredential?,
                                   session: UUID, manual: Bool = false) -> [String: String] {
        var env = ["SSH_ASKPASS": executable, "SSH_ASKPASS_REQUIRE": "force", flag: "1",
                   "NETDECK_SESSION": session.uuidString]
        if manual { env[manualFlag] = "1" }
        if let configPath { env["NETDECK_SSH_CONFIG"] = configPath }
        if let d = defaultCredential { env["NETDECK_DEFAULT"] = "\(d.name)\t\(d.user)" }
        return env
    }

    /// Las contraseñas que el askpass ha dado a esa pestaña (para confirmarlas cuando llega al prompt).
    public static func takeGiven(session: UUID) -> [CredentialRef] {
        let url = AppPaths.sessions.appendingPathComponent(session.uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).compactMap { decodeGiven($0)?.ref }
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
                ledger.confirm(g.ref)
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
        guard let account = questions.lazy.compactMap({ $0.group(1, in: question) }).first,
              let at = account.lastIndex(of: "@") else {
            tty.say(question)                                  // yes/no, passphrase, OTP…: contesta la persona
            guard let a = tty.read(secret: secretQuestion.matches(question)) else { return 1 }
            return answer(a)
        }
        let user = String(account[..<at]), host = String(account[account.index(after: at)...])
        let manager = SessionManager()
        manager.load(from: env["NETDECK_SSH_CONFIG"].map { URL(fileURLWithPath: $0) } ?? SessionManager.defaultConfigURL)
        let defaultCredential = env["NETDECK_DEFAULT"].flatMap { s -> DefaultCredential? in
            let (n, _, u) = s.partition("\t")
            return n.isEmpty || u.isEmpty ? nil : DefaultCredential(name: n, user: u)
        }
        let ledger = CredentialLedger.shared()
        let store = KeychainStore()
        let profile = manager.profiles.first { $0.endpoint.host == host } ?? manager.profile(named: host)
        let ask = Asker(tty: tty, account: account, user: user, host: host, named: profile?.namedCredential,
                        store: store, ledger: ledger, state: stateFile(), session: env["NETDECK_SESSION"])

        if let s = env["NETDECK_SESSION"] { confirmEarlier(session: s, host: host, ledger: ledger) }
        if env[manualFlag] == "1" { return ask.user(failed: nil) }
        // ssh vuelve a preguntar enseguida: la que le dimos no valía
        if let used = ask.recentlyGiven() {
            ledger.markFailed(used)
            tty.say(L("\(red)\(marker) la contraseña guardada «\(used)» no ha funcionado en \(account): ")
                    + L("no se probará sola en 15 min\(reset)\n"))
            return ask.user(failed: used)
        }
        let request = PasswordRequest(line: question, account: account)
        let route = profile.flatMap { try? manager.route(to: $0) }
        // (la cuenta de la pregunta la pone el propio ssh con el equipo de verdad: no la escribe el remoto)
        let candidates = manager.credentialCandidates(for: request, route: route, defaultCredential: defaultCredential,
                                                      trustAccount: true)
            .filter { store.contains($0.ref) }
        let deadline = Date().addingTimeInterval(ledger.probeWindow + 2)
        var told = false
        while true {
            switch CredentialPolicy().decide(request, commandUser: nil, candidates: candidates, isBlocked: ledger.isBlocked) {
            case .manual(let why):
                if why != .noCredential { tty.say("\(yellow)\(marker) \(explain(why))\(reset)\n") }
                return ask.user(failed: nil)
            case .inject(let ref):
                switch ledger.beginProbe(ref) {
                case .go:
                    guard let pw = try? store.password(for: ref) else {
                        ledger.release(ref)
                        return ask.user(failed: nil)
                    }
                    ask.given(ref)
                    return answer(pw)
                case .wait where Date() < deadline:
                    if !told {
                        tty.say(L("\(cyan)\(marker) otra pestaña está probando «\(ref)»: espero a ver si vale…\(reset)\n"))
                        told = true
                    }
                    Thread.sleep(forTimeInterval: 0.3)
                case .wait:                        // (no ha fallado: la otra pestaña tarda demasiado)
                    tty.say(L("\(yellow)\(marker) otra pestaña sigue probando «\(ref)»: no espero más, escríbela tú\(reset)\n"))
                    return ask.user(failed: nil)
                case .blocked:
                    tty.say(L("\(yellow)\(marker) «\(ref)» falló hace poco: no la escribo (cuenta AD)\(reset)\n"))
                    return ask.user(failed: nil)
                }
            }
        }
    }

    public static func explain(_ why: ManualReason) -> String {
        switch why {
        case .changeOrConfirm: L("piden una contraseña nueva o repetida: escríbela tú")
        case .userMismatch(let u): L("ninguna guardada es de «\(u)»: escríbela tú")
        case .conflictingUsers(let c, let p): L("la orden dice «\(c)» y el prompt «\(p)»: escríbela tú")
        case .recentlyFailed(let r): L("«\(r)» falló hace poco: no se escribe sola (cuenta AD)")
        case .unknownUser: L("no se sabe qué usuario la pide: escríbela tú")
        case .noCredential: L("no hay ninguna guardada")
        }
    }

    // MARK: - estado

    /// Un archivo por cada ssh (su PID): qué contraseña guardada se le dio. Si vuelve a preguntar, no valía.
    static func stateFile() -> URL {
        let dir = AppPaths.ensure(AppPaths.sessions)
        if let old = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for f in old where f.lastPathComponent.hasPrefix("ndapp-askpass.") {
                let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let m, Date().timeIntervalSince(m) > 600 { try? FileManager.default.removeItem(at: f) }
            }
        }
        return dir.appendingPathComponent("ndapp-askpass.\(getppid())")
    }

    static func encode(_ r: CredentialRef) -> String { "\(r.service.rawValue)\t\(r.account)" }

    /// Una línea del archivo de la pestaña: «@equipo\tservicio\tcuenta» (el equipo al que se dio; las de antes, sin él).
    /// (el equipo sale de la pregunta: sin tabuladores ni caracteres de control, que moverían los campos)
    static func encodeGiven(_ r: CredentialRef, host: String) -> String {
        "@\(host.filter { !$0.isNewline && $0.asciiValue.map { $0 >= 32 && $0 != 127 } ?? true })\t\(encode(r))"
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
        FileHandle.standardOutput.write(Data((s + "\n").utf8))
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

        func recentlyGiven() -> CredentialRef? {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: state.path),
                  let m = attrs[.modificationDate] as? Date, Date().timeIntervalSince(m) < 120,
                  let text = try? String(contentsOf: state, encoding: .utf8) else { return nil }
            return decode(text.trimmed)
        }

        func given(_ ref: CredentialRef?) {
            try? SafeFile.write(ref.map(encode) ?? "", to: state)
            guard let ref, let session else { return }
            let url = AppPaths.ensure(AppPaths.sessions).appendingPathComponent(session)
            let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? SafeFile.write(old + encodeGiven(ref, host: host) + "\n", to: url)
        }

        /// Te la pide; te ofrece guardarla (si la guardada falló, por defecto sí).
        func user(failed: CredentialRef?) -> Int32 {
            tty.say(L("\(cyan)\(marker) Esc = cancelar\(reset)\n\(marker) \(account)'s password: "))
            guard let pw = tty.read(secret: true) else {
                tty.say(L("\(yellow)\(marker) cancelado\(reset)\n"))
                return 1
            }
            var saved: CredentialRef?
            if let named, tty.yesNo(L("¿Guardarla como «\(named)»?"), default: true) == true {
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
                    _ = ledger.beginProbe(s)
                    tty.say(L("\(green)\(marker) guardada ✓\(reset)\n"))
                } catch {
                    tty.say("\(red)\(marker) \(error.localizedDescription)\(reset)\n")
                    saved = nil
                }
            }
            given(saved)
            return answer(pw)
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
            guard let b = next(nil) else { return String(decoding: data, as: UTF8.self) }
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
