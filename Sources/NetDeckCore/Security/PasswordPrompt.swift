import Foundation

/// Una petición de contraseña en pantalla.
public struct PasswordRequest: Equatable, Sendable {
    public var line: String
    /// usuario@equipo si la petición lo dice: «admin@192.0.2.1's password:», «(admin@192.0.2.1) Enter password:»
    public var account: String?
    /// El tecleado en «Username:»/«login:»/«User:»/«login as:» justo antes (telnet, consolas, TACACS…).
    public var typedUser: String?
    /// Nueva / repetir / actual…: nunca se escribe sola.
    public var isChangeOrConfirm: Bool

    public init(line: String, account: String? = nil, typedUser: String? = nil, isChangeOrConfirm: Bool = false) {
        self.line = line
        self.account = account
        self.typedUser = typedUser
        self.isChangeOrConfirm = isChangeOrConfirm
    }

    /// El usuario que pide: el de la cuenta o, si sólo dice «Password:», el tecleado. nil = no se sabe.
    public var user: String? {
        if let a = account, let at = a.lastIndex(of: "@") { return String(a[..<at]) }
        return typedUser
    }
}

/// Reconocer peticiones de contraseña (los mismos patrones que «clave» en NetDeck).
public enum PasswordPrompt {
    static let asks = Pattern(#"(?:^|[\s'(\[])(?:password|contraseña|passwd)(?:\s+for\s+[^:]{1,80})?\s*:\s*$"#)
    /// …pero no si delante hay un prompt con una orden («core-01#show run | i password:»): eso lo escribes tú.
    static let command = Pattern(#"[#>$%|]"#)
    static let changeOrConfirm = Pattern(#"\b(new|nueva|retype|re-enter|confirm|repeat|verify|old|current|actual|again)\b"#)
    static let account = Pattern(#"([^\s'()\[\]]+@[^\s'()\[\]]+?)(?:'s\s+password|\)\s*(?:enter\s+)?password)"#)
    static let typed = Pattern(#"^\s*(?:user\s*name|user|login(?:\s+as)?|usuario)\s*:\s*(\S+)\s*$"#)
    static let loginLine = Pattern(#"^\s*(?:user\s*name|user|login(?:\s+as)?|usuario)\s*:(?:\s*\S+)?\s*$"#)

    /// La respuesta al usuario de un login no es una orden nueva, aunque se termine con Intro.
    public static func isLoginLine(_ line: String) -> Bool { loginLine.matches(line) }

    public static func asksForPassword(_ line: String) -> Bool {
        let l = line.trimmed
        guard !l.hasPrefix(Askpass.marker), l.count <= 120, let r = asks.range(in: l) else { return false }
        return !command.matches(String(l[..<r.lowerBound]))
    }

    /// La petición de la línea del cursor (`above`: las líneas de encima, la última justo antes), o nil.
    public static func detect(cursorLine: String, above: [String]) -> PasswordRequest? {
        guard asksForPassword(cursorLine) else { return nil }
        let l = cursorLine.trimmed
        return PasswordRequest(line: l, account: account.group(1, in: l), typedUser: typedUser(in: above),
                               isChangeOrConfirm: changeOrConfirm.matches(l))
    }

    /// El usuario escrito en «Username:»/«login:» en las dos últimas líneas no vacías, o nil.
    public static func typedUser(in lines: [String]) -> String? {
        for l in lines.filter({ !$0.trimmed.isEmpty }).suffix(2).reversed() {
            if let u = typed.group(1, in: l) { return u }
        }
        return nil
    }
}

/// Lo que no debe salir de su pestaña (MultiExec): la petición de una contraseña, de la passphrase de una clave, de un
/// código de un solo uso (OTP, PIN, token…), la pregunta de ssh por la clave de un equipo nuevo y las preguntas del
/// askpass («[NetDeck] …», sólo mientras ssh se autentica).
public enum SecretPrompt {
    static let other = Pattern(#"(?:^|[\s'(\[])(?:passphrase|pass\s?code|pin|otp|one[- ]time|verification\s+code|security\s+code|token(?:\s+code)?|authenticator(?:\s+code)?|two[- ]factor|2fa|mfa|c[oó]digo)\b[^:]{0,80}:\s*$"#)

    public static func asks(_ line: String) -> Bool {
        let l = line.trimmed
        if l.hasPrefix(Askpass.marker) || PasswordPrompt.asksForPassword(l) { return true }
        if l.hasPrefix("Are you sure you want to continue connecting") { return true }
        guard l.count <= 160, let r = other.range(in: l) else { return false }
        return !PasswordPrompt.command.matches(String(l[..<r.lowerBound]))
    }
}

/// Usuario y equipo de una orden «ssh …»/«telnet …» tecleada (al conectar o en la shell de un salto).
public enum CommandLineUser {
    private static let sshOptionsWithArgument = Set("BbcDEeFIiJLlmOoPpQRSWw")

    /// Para armar el login interno: una invocación interactiva completa, sin una orden remota después del destino.
    /// Las variantes que no se pueden interpretar sin una shell (comillas, escapes…) se quedan manuales.
    public static func interactiveTarget(_ command: String) -> Endpoint? {
        guard !command.contains(where: { "'\"\\;|&$`<>".contains($0) }),
              !command.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first, ["ssh", "telnet"].contains(first) else { return nil }
        let ssh = first == "ssh"
        let flags = Set(ssh ? "1246AaCKkMqstvXxYy" : "468acdEKLrx")
        let arguments = Set(ssh ? "BbcDEeFIiJLlmPpRSo" : "l")
        var user: String?, port: Int?, target: Endpoint?, options = true
        var i = 1
        while i < words.count {
            let word = words[i]
            if target == nil, options, word == "--" { options = false; i += 1; continue }
            if target == nil, options, word.hasPrefix("-") {
                let chars = Array(word.dropFirst())
                guard !chars.isEmpty else { return nil }
                var j = 0
                while j < chars.count {
                    let flag = chars[j]
                    if arguments.contains(flag) {
                        let value: String
                        if j + 1 < chars.count { value = String(chars[(j + 1)...]) }
                        else { i += 1; guard i < words.count else { return nil }; value = words[i] }
                        guard !value.isEmpty else { return nil }
                        switch flag {
                        case "l": user = value
                        case "p":
                            guard let p = Int(value), (1...65535).contains(p) else { return nil }; port = p
                        case "J":
                            let jumps = value.split(separator: ",", omittingEmptySubsequences: false)
                            guard !jumps.isEmpty, jumps.allSatisfy({ Endpoint(parsing: String($0))?.isShellSafe == true }) else { return nil }
                        case "o":
                            let (key, sep, option) = value.partition("=")
                            guard !sep.isEmpty else { return nil }
                            let k = key.lowercased(), v = option.lowercased()
                            guard !["remotecommand", "localcommand", "proxycommand", "sessiontype"].contains(k),
                                  !(k == "requesttty" && v == "no"), !(k == "batchmode" && v == "yes") else { return nil }
                            if k == "user" { user = option }
                            if k == "port" { guard let p = Int(option), (1...65535).contains(p) else { return nil }; port = p }
                        default: break
                        }
                        break                                      // (lo demás era el valor de esta opción)
                    }
                    guard flags.contains(flag) else { return nil }   // (-N/-f/-T/-G/-W… no son este login)
                    j += 1
                }
            } else if target == nil {
                guard let endpoint = Endpoint(parsing: word), endpoint.isShellSafe else { return nil }
                target = endpoint
            } else if !ssh, port == nil, let p = Int(word), (1...65535).contains(p) {
                port = p
            } else { return nil }                                  // (payload remoto o argumentos sobrantes)
            i += 1
        }
        guard var target else { return nil }
        if let user { target.user = user }
        if let port { target.port = port }
        return target.isShellSafe ? target : nil
    }

    /// «admin@bastion:~$ ssh -p 2222 -l root 192.0.2.1» → root@192.0.2.1:2222. «-l» gana a «usuario@» (como ssh).
    public static func parse(_ commandLine: String) -> Endpoint? { scan(commandLine).target }

    /// Los equipos de la orden: el destino y los saltos («ssh -J bastion admin@core-01» → core-01, bastion).
    public static func hosts(_ commandLine: String) -> Set<String> {
        let s = scan(commandLine)
        return Set(([s.target].compactMap { $0 } + s.jumps).map(\.host))
    }

    /// Los usuarios explícitos de los saltos: «ssh -J tu.usuario@bastion,ops@b2 admin@…» → tu.usuario, ops.
    /// (Un salto sin «usuario@» no cuenta: no se sabe quién es.)
    public static func jumpUsers(_ commandLine: String) -> Set<String> {
        Set(scan(commandLine).jumps.compactMap(\.user))
    }

    private static func scan(_ commandLine: String) -> (target: Endpoint?, jumps: [Endpoint]) {
        let t = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let s = t.lastIndex(where: { ["ssh", "telnet"].contains(($0 as NSString).lastPathComponent) }) else { return (nil, []) }
        let isSSH = (t[s] as NSString).lastPathComponent == "ssh"
        var user: String?, port: Int?, host: Endpoint?, jumps: [Endpoint] = []
        func addJumps(_ arg: String?) {
            jumps += (arg ?? "").split(separator: ",").compactMap { Endpoint(parsing: String($0)) }
        }
        var i = s + 1
        while i < t.count {
            let tok = t[i]
            if host == nil, tok.hasPrefix("-"), tok.count >= 2 {
                let flag = tok.dropFirst()
                let takesArg = isSSH ? sshOptionsWithArgument.contains(flag.first!) : flag == "l"
                if takesArg {
                    let arg = flag.count > 1 ? String(flag.dropFirst()) : (i + 1 < t.count ? t[i + 1] : nil)
                    if flag.count == 1 { i += 1 }
                    switch flag.first! {
                    case "l": user = arg
                    case "p": port = arg.flatMap { Int($0) }
                    case "J": addJumps(arg)
                    case "o" where arg?.lowercased().hasPrefix("proxyjump=") == true: addJumps(String(arg!.dropFirst(10)))
                    case "o" where arg?.lowercased().hasPrefix("user=") == true: user = String(arg!.dropFirst(5))
                    case "o" where arg?.lowercased().hasPrefix("port=") == true: port = Int(arg!.dropFirst(5))
                    default: break
                    }
                }
            } else if host == nil {
                host = Endpoint(parsing: tok)
                if host == nil { return (nil, []) }
            } else if !isSSH, port == nil, let p = Int(tok) {
                port = p
            } else {
                break                                   // (ssh: lo demás es la orden remota)
            }
            i += 1
        }
        guard var e = host else { return (nil, []) }
        if let user { e.user = user }
        if e.port == nil { e.port = port }
        return (e, jumps)
    }
}
