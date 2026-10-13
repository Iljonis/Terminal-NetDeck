import Foundation

/// Prompt de un equipo: «core-01#», «core-01(config-if)#», «admin@core-01>», «<core-01>», «[~core-01-xe1]»,
/// «A:admin@core-01#», «admin@bastion:~$». Con una muestra (el prompt de antes de pegar) reconoce los de ese equipo en
/// cualquier modo; sin ella, uno genérico.
public struct DevicePrompt: Sendable {
    public static let generic = Pattern(#"^[\[<*!~]{0,3}(?:[AB]:)?[A-Za-z0-9_][A-Za-z0-9_.@:/()~\-\[\] ]{0,79}[#>$%\]]\s?$"#,
                                        ignoreCase: false)
    private static let prefix = Pattern(#"^[\[<*!~]{0,3}(?:[AB]:)?"#, ignoreCase: false)

    /// Nombre sacado de la muestra («core-01», «admin@core-01»), o nil.
    public let base: String?
    private let pattern: Pattern

    public init(sample: String?) {
        var b: String?
        if let s = sample?.trimmed, Self.generic.matches(s) {
            var rest = Substring(s)
            if let r = Self.prefix.range(in: s) { rest = s[r.upperBound...] }
            let name = rest.prefix { !"(:[ #>$%]".contains($0) }
            if !name.isEmpty { b = String(name) }
        }
        base = b
        pattern = b.map { Pattern(#"^[\[<*!~]{0,3}(?:[AB]:)?"# + Pattern.escape($0) + #".{0,60}[#>$%\]]\s?$"#,
                                  ignoreCase: false) }
            ?? Self.generic
    }

    public func matches(_ line: String) -> Bool { pattern.matches(line.trimmed) }
}

/// El equipo en el que estás de verdad, sacado del prompt (como «detectar» de NetDeck):
///   Huawei <core-01> / [~core-01] · Cisco core-01# · IOS-XR RP/0/RSP0/CPU0:pe-01# · Juniper user@mx-01> ·
///   Linux / Teltonika root@rut955:~# · MikroTik [admin@MikroTik] > · Nokia A:admin@bb01.almeria# / *A:bb01>config>#
public enum PromptDevice {
    static let n = #"[A-Za-z0-9][A-Za-z0-9._:/-]*"#
    static let prompts: [Pattern] = [
        Pattern(#"^<(\#(n))>"#, ignoreCase: false),                                                  // Huawei / H3C
        Pattern(#"^RP/\d+/\w+/CPU\d+:([A-Za-z0-9._-]+)(?:\([^)]*\))?#"#, ignoreCase: false),         // IOS-XR
        Pattern(#"^\[[^@\]]+@([A-Za-z0-9][A-Za-z0-9._ -]*)\]\s*>"#, ignoreCase: false),             // MikroTik
        Pattern(#"^\[?[A-Za-z0-9._-]+@([A-Za-z0-9._-]+)[^#$>%]*?\]?\s?[#$>%]"#, ignoreCase: false), // Juniper, Linux
        Pattern(#"^([A-Za-z0-9][A-Za-z0-9._-]*)(?:\([A-Za-z0-9/.-]+\))?[#>]$"#, ignoreCase: false), // Cisco, Arista
        Pattern(#"^\*?[A-D]:(?:[^@\s#>]+@)?([A-Za-z0-9][A-Za-z0-9._-]*)(?:>[^#\s]*)?[#$>]\s*$"#, ignoreCase: false), // Nokia
    ]
    static let bracket = Pattern(#"^\[[~*]*(\#(n))\]"#, ignoreCase: false)                           // Huawei system-view
    static let valid = Pattern(#"^[A-Za-z0-9][A-Za-z0-9._:/@ -]*$"#, ignoreCase: false)

    /// nil si la línea no es un prompt conocido. `previous`: el de antes ([~core-01-GigabitEthernet0/0/1] sigue en core-01).
    public static func name(_ line: String, previous: String? = nil) -> String? {
        let l = line.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty, l.count < 200, !l.hasPrefix("[NetDeck]") else { return nil }
        var found: String?
        for p in prompts {
            if let g = p.group(1, in: l) { found = g.trimmingCharacters(in: .whitespaces); break }
        }
        if found == nil, let g = bracket.group(1, in: l) {
            found = previous.map { g.hasPrefix($0) ? $0 : g } ?? g
        }
        guard let f = found, valid.matches(f) else { return nil }
        return f
    }
}
