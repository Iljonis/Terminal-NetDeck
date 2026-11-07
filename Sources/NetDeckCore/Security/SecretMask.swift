import Foundation

/// Una orden que se va a enseñar (el aviso de MultiExec o de un botón, `status`) sin sus secretos: la clave de una URL
/// («scp://tu.usuario:•••@192.0.2.10/x») y lo que sigue a `password`, `secret`, `key` o `community` («username
/// tu.usuario secret 0 •••», «snmp-server community ••• RO», «--password=•••»). Con su tipo de cifrado de IOS delante
/// («password 7 •••») y entre comillas, entero. «crypto key zeroize/generate» y «key chain» no son secretos.
public enum SecretMask {
    static let url = Pattern(#"(://[^/\s:@]*:)[^@\s/]+@"#)
    static let argument = Pattern(#"(\b(?:password|passwd|secret|key-string|key|community)(?:\s+\d)?(?:\s+|\s*[=:]\s*))(?!(?:zeroize|generate|chain|config-key)\b)(?:"[^"]*"|'[^']*'|\S+)"#)

    public static func masked(_ s: String) -> String {
        guard s.range(of: "://", options: .literal) != nil || argument.matches(s) else { return s }
        var out = url.regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1•••@")
        out = argument.regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1•••")
        return out
    }
}
