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
    /// El prompt propio de la sesión («# @prompt …»): si lo hay, manda él (sin contar las peticiones de secretos).
    private let custom: PromptRule?

    public init(sample: String?, custom: PromptRule? = nil) {
        self.custom = custom
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

    public func matches(_ line: String) -> Bool {
        if let custom { return PromptRule.isPrompt(line, custom: custom) }
        return pattern.matches(line.trimmed)
    }
}

/// Prompt propio de una sesión («# @prompt …»): una regex que reconoce el prompt del equipo en lugar del genérico
/// (`DevicePrompt.generic`) para «ha entrado», el pegado seguro y la contraseña. Una línea que pide un secreto
/// (`SecretPrompt`: contraseña, passphrase, OTP…) o una pregunta del askpass nunca cuenta como prompt, la acepte o no
/// la regex: un «.*» no saca a una pestaña de «autenticándose» (MultiExec) ni deja pegar sobre «Password:».
public struct PromptRule: Hashable, Sendable {
    public let source: String
    let pattern: Pattern

    public static let maxLength = 200
    /// Sólo se mira contra líneas de hasta tantos caracteres (un prompt no es más largo; acota el coste de la regex).
    static let maxLine = 160
    private static let rejection = Pattern(#"\b(?:permission denied|access denied|authentication (?:failed|failure)|authorization failed|login (?:incorrect|failed)|invalid (?:password|credentials)|incorrect password|bad password|acceso denegado|autenticaci[oó]n fallida|contrase[nñ]a incorrecta)\b"#)
    private static let login = Pattern(#"^\s*(?:user\s*name|user|login(?:\s+as)?|usuario)\s*:"#)

    /// Un rechazo nunca confirma credenciales, aunque la regex del usuario lo acepte.
    public static func authenticationFailed(_ line: String) -> Bool { rejection.matches(line) }

    public init?(_ source: String) {
        guard Self.problem(source) == nil, let p = Pattern(compiling: source) else { return nil }
        self.source = source
        pattern = p
    }

    /// Por qué no vale (para el usuario), o nil.
    public static func problem(_ s: String) -> String? {
        if s.trimmed.isEmpty { return L("vacío") }
        if s.count > maxLength { return L("más de \(String(maxLength)) caracteres") }
        if SessionFile.hasControl(s) { return L("saltos de línea o caracteres de control") }
        if Pattern(compiling: s) == nil { return L("no es una expresión regular válida") }
        if Pattern.repeticionPeligrosa(en: s) { return L("grupos repetidos con alternativas o cuantificadores (pueden bloquear la app)") }
        return nil
    }

    /// La regex sola (sin la protección de los secretos).
    func accepts(_ line: String) -> Bool {
        let l = line.trimmed
        return l.count <= Self.maxLine && pattern.matches(l)
    }

    /// ¿Es el prompt del equipo? Con `custom`, el suyo; si no, el genérico. Nunca una petición de secreto ni una línea
    /// del askpass. Las reglas que aceptan vacío necesitan además un prompt genérico reconocible.
    public static func isPrompt(_ line: String, custom: PromptRule?) -> Bool {
        let l = line.trimmed
        guard !l.isEmpty, l.count <= maxLine, !SecretPrompt.asks(l), !authenticationFailed(l),
              !login.matches(l), !PasteRules.errors.matches(l), !PasteRules.pager.matches(l) else { return false }
        if let custom {
            // (una regla que acepta vacío, como «.*», tampoco demuestra que un banner o un fragmento sea un prompt)
            if custom.pattern.matches(""), !DevicePrompt.generic.matches(l) { return false }
            return custom.accepts(l)
        }
        return DevicePrompt.generic.matches(l)
    }

    /// Fin de un login anidado (desde la sesión a otro equipo): el prompt de la sesión o también el genérico. El
    /// «# @prompt» propio es el del equipo de la sesión; «core-01#», el del equipo al que se ha saltado, no lo cumple
    /// y, sin éste, su contraseña quedaba pendiente mientras trabajabas allí.
    public static func endsNestedLogin(_ line: String, custom: PromptRule?) -> Bool {
        isPrompt(line, custom: custom) || (custom != nil && isPrompt(line, custom: nil))
    }

    public static func == (a: Self, b: Self) -> Bool { a.source == b.source }
    public func hash(into h: inout Hasher) { h.combine(source) }
}

/// El equipo en el que estás de verdad, sacado del prompt (como «detectar» de NetDeck):
///   Huawei <core-01> / [~core-01] · Cisco core-01# · IOS-XR RP/0/RSP0/CPU0:pe-01# · Juniper user@mx-01> ·
///   Linux / Teltonika root@rut955:~# · MikroTik [admin@MikroTik] > · Nokia A:admin@bb01.ejemplo# / *A:bb01>config>#
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
