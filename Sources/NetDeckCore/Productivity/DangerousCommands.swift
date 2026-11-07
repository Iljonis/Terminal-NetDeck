import Foundation

/// Órdenes peligrosas (`PasteRules.dangerous`): las que reinician, apagan, borran o sustituyen la configuración, o cortan
/// el acceso. Se mira la orden, no las palabras sueltas: se quita el prompt («core-01#», «<core-01>», «tu.usuario@mx-01>»,
/// «admin@bastion:~$»…) y lo que la ejecuta desde otro modo (`do`, `run`, `admin`, `sudo`, `env`, `then`, `(`…), y cada
/// regla va anclada al principio. Así «no shutdown», «show … reset», «description reload-test», «| include clear» o
/// «reload cancel» no saltan. Un `commit` normal tampoco (sí «commit replace»). Con las abreviaturas de IOS («relo», «shu»,
/// «wr er»…). Cisco IOS/IOS-XE/XR/NX-OS, Junos, Huawei VRP, Nokia SR-OS y Linux. Con `;`, `&&` o `||` cuenta cada orden
/// (no entre comillas ni en un `description` o `banner`, que son texto); tras un `|`, los filtros de una orden de lectura
/// (`show … | include reload`) no, y los de una de Linux sí (`… | xargs rm -rf`, `… | sh`). Lo de `sh -c '…'`, `eval …`,
/// `$(…)` y `` `…` `` se mira como otra línea (`$(…)` también entre comillas).
/// Es una lista de mejor esfuerzo, no un intérprete de shell ni de la CLI de cada fabricante: un script, un alias o
/// `ssh core-01 reboot` se le escapan. Lo que no puede seguir cuenta como peligroso: una línea con caracteres de control
/// (`x^Ureboot` es «reboot» para el equipo) o más larga que `maxLength`.
public struct DangerousCommands: Sendable {
    /// El prompt de delante, si lo hay (sin él, la línea es la orden).
    /// («[root@bastion ~]#» de RHEL entero; «reboot>/dev/null» no es un prompt)
    static let prompt = Pattern(#"^\s*(?:<[^<>\s]{1,80}>|\[[^\[\]]{1,80}\]\s*[>#$%]?|\*?[A-D]:\S{0,80}?[#$]|[A-Za-z0-9_.@:/()~\-\[\]>]{0,80}[A-Za-z0-9_)~\]][#>$%](?![/&>])|\$)\s*"#,
                                ignoreCase: false)
    /// Lo que ejecuta la orden desde otro modo o la pasa a otra: `do reload` (configuración de Cisco), `run request
    /// system reboot` (Junos), `admin reboot` (IOS-XR, SR-OS), `sudo reboot`, `/admin reboot` (MD-CLI), `/sbin/reboot`,
    /// `… | xargs rm -rf`, `sudo -u root reboot`; de la shell, `env -i X=1 reboot`, `X=1 reboot`, `command reboot`,
    /// `then reboot`, `(reboot)`, `{ reboot; }` y `! reboot` (en IOS, «!» es un comentario: aquí cuenta como la negación
    /// de la shell, por si acaso).
    static let wrapper = Pattern(#"^(?:(?:/usr)?(?:/local)?/s?bin/|/(?=[a-z])|[({!](?=\s*\S)|(?:do|run|admin|exec|nohup|time|then|else|if|elif|while|until|command(?:\s+-[pvV]+)*|env(?:\s+(?:-[iv0]+|-[uSC]\s*\S+|--\S+|\w+=\S*))*|\w+=\S*|sudo(?:\s+-[ugChpD]\s+\S+|\s+-\S+)*|xargs(?:\s+-\S+)*)\s+)"#)
    /// Órdenes de lectura: nunca peligrosas, ni con sus filtros detrás (`show … reset`, `show run | include reload`).
    /// «sh» a secas es «show» (IOS) sólo si lo que sigue es una palabra suelta, como las de IOS («sh run», «sh ip int br»,
    /// «sh int Gi0/1»); con una ruta, un archivo con extensión, una opción, comillas o `$` es la shell de Linux
    /// («sh ./x», «sh x.sh», «sh -c …»). Un script sin extensión («sh limpia») pasa por lectura: mejor esfuerzo.
    static let reading = Pattern(#"^(?:sh(?=\s+[a-z][a-z0-9-]*(?:\s|$))|sho(?:w)?(?!\s+-)|dis(?:p(?:lay)?)?|ping|traceroute|tracert|trace|description|desc|undebug|un?\s+all|no\s+debug|undo\s+debugging)(?:\s|$)"#)
    /// Lo que deshace un peligro, sólo limpia la pantalla o es de diagnóstico de todos los días (la orden entera): «no shu»,
    /// «reload cancel», «clear ip bgp * soft» (no tira la sesión), «clear counters», «clear logging», «shutdown -c» (Linux:
    /// cancela el apagado), «clear system reboot» (Junos: cancela el reinicio).
    static let harmless = Pattern(#"^(?:(?:no|undo)\s+shu\w*|rel(?:o(?:ad?)?)?\b.*\bcancel|admin-state\s+enable|cle(?:ar?)?(?:\s+screen)?|reset|cle(?:ar?)?\s+(?:ip\s+|ipv6\s+)?bgp\b.*\bsoft(?:-inbound|\s+(?:in|out))?|cle(?:ar?)?\s+system\s+reboot|shutdown\s+-c|cle(?:ar?)?\s+(?:counters|log(?:ging)?)\b.*)\s*$"#)
    /// Texto, no órdenes: ni se corta por `;`, `&&` o `|` ni se mira lo de detrás.
    static let text = Pattern(#"^(?:desc(?:ription)?|banner)(?:\s|$)"#)
    /// Una shell que ejecuta lo que le llega por la tubería (`curl … | sh`, `… | sudo bash`).
    static let shell = Pattern(#"^(?:ba|z|da|k)?sh(?:\s|$)"#)
    /// Una shell con su orden en `-c` («sh -c 'reboot'», «bash -lc "…"»): el grupo 1 es lo de detrás.
    static let shellCommand = Pattern(#"^(?:ba|z|da|k)?sh\s+(?:-[a-z]+\s+)*?-[a-z]*c[a-z]*\s+(.+)$"#)
    static let eval = Pattern(#"^eval\s+(.+)$"#)
    /// Más larga, peligrosa sin mirarla. Hasta ahí se mira entera: lo peor medido son unos 2 ms por línea (en debug).
    /// Más allá, una regla con `.*` que crezca más que lineal congelaría la ventana (con `\s+(?:.*\s)?`, «rm» + 8000
    /// espacios + «x» tardaba 3 s; `PasteRulesTests.unaLineaLarguisima`).
    public static let maxLength = 2000
    /// Lo que se mira dentro de `sh -c`, `eval` o `$(…)`, y dentro de eso…
    static let maxDepth = 4

    /// Las reglas (todas ancladas al principio de la orden).
    static let rules: [String] = [
        // reinicio y apagado (IOS, NX-OS, XR, Junos, VRP, SR-OS, Linux)
        #"rel(?:o(?:ad?)?)?\b"#,                                     // reload, relo, reloa, rel
        #"reboot\b"#,
        #"system\s+(?:reboot|shutdown|reset-configuration)\b"#,     // MikroTik: /system reboot
        #"shu(?:t(?:d(?:o(?:wn?)?)?)?)?\b"#,                         // interfaz, shu (y Linux: shutdown -h now)
        #"neighbor\s+\S+\s+shutdown\b"#,                             // BGP
        #"halt\b"#,
        #"poweroff\b"#,
        #"init\s+[06]\b"#,
        #"telinit\s+[06]\b"#,
        #"systemctl\s+(?:reboot|poweroff|halt|kexec|isolate)\b"#,
        #"systemctl\s+(?:stop|disable|mask)\s+(?:ssh|sshd|network|networking|NetworkManager|systemd-networkd)\b"#,
        #"hw-module\b.*\b(?:reload|shutdown|reset)\b"#,              // IOS-XR, NX-OS
        #"redundancy\s+(?:force-switchover|switch-activity)\b"#,
        #"process\s+(?:restart|shutdown|kill)\b"#,                   // IOS-XR
        #"restart\s+\S"#,                                            // Junos: restart routing
        #"request\s+(?:system|vmhost)\s+(?:reboot|halt|power-off|power-cycle|zeroize)\b"#,
        #"request\s+(?:system|vmhost)\s+software\s+(?:add|delete|rollback)\b"#,
        #"request\s+system\s+storage\s+cleanup\b"#,
        #"request\s+chassis\b.*\b(?:offline|restart|power-off|switch)\b"#,
        #"install\s+(?:all|activate|deactivate|remove|rollback)\b"#, // NX-OS, IOS-XE, IOS-XR
        // borrar y vaciar
        #"cle(?:ar?)?\s+\S"#,                                        // clear ip bgp *, cle ip bgp *, clear line…
        #"reset\s+\S"#,                                              // VRP: reset bgp all, reset saved-configuration
        #"wr(?:i(?:te?)?)?\s+er(?:a(?:se?)?)?\b"#,                  // write erase, wr er
        #"era(?:se?)?\b"#,
        #"format\b"#,
        #"delete\b"#,                                                // flash:, bootflash:, Junos/MD-CLI config
        #"wildcard\s+delete\b"#,
        #"file\s+(?:delete|remove|rd|format)\b"#,                    // Junos, SR-OS
        #"squeeze\b"#,
        #"crypto\s+key\s+zeroize\b"#,
        #"rm\s(?:.*\s)?-(?:[A-Za-z]*[rR]|-recursive\b)"#,            // rm -rf, rm -r, rm -fr («\s», no «\s+»: con «.*», cuadrático)
        #"mkfs(?:\.\w+)?\b"#,
        #"wipefs\b"#,
        #"dd\s.*\bof=/dev/"#,
        #"find\s.*\s-(?:delete|exec(?:dir)?\s+(?:\S*/)?rm)\b"#,       // find … -delete, find … -exec rm
        #"shred\b"#,
        #"truncate\b"#,
        // sustituir la configuración
        #"conf(?:ig(?:ure)?)?\s+replace\b"#,
        #"commit\s+replace\b"#,                                      // IOS-XR
        #"rollback\b"#,                                              // XR, NX-OS, Junos, VRP, SR-OS
        #"load\s+(?:override|replace|factory-default)\b"#,           // Junos
        // (copy algo a running/startup, también abreviado y con /noverify; de la running a otro sitio, no)
        #"cop(?:y)?(?:\s+/\S+)*\s+(?!ru[a-z-]*(?=\s)|system:ru[a-z-]*(?=\s))\S+\s+(?:\S*:)?(?:ru[a-z-]*|sta[a-z-]*)(?=\s|$)"#,
        #"startup\s+saved-configuration\b"#,                         // VRP
        #"boot\s+system\b"#,
        #"no\s+boot\s+system\b"#,
        #"config-register\b"#,
        #"default\s+interface\b"#,
        // quitar lo que da servicio o acceso
        #"no\s+router\b"#,
        #"no\s+(?:ip\s+routing|ipv6\s+unicast-routing)\b"#,
        #"no\s+(?:interface|vlan|vrf|ip\s+vrf|feature|spanning-tree|mpls\s+ip|channel-group|switchport)\b"#,
        #"no\s+int(?:e(?:r(?:f(?:a(?:ce?)?)?)?)?)?\s"#,              // no int Gi0/1
        #"no\s+neighbor\s+\S+(?:\s+remote-as\s+\S+)?\s*$"#,          // quita el vecino BGP entero
        #"no\s+(?:ip\s+route|ipv6\s+route|ip\s+default-gateway)\b"#,
        #"no\s+(?:bgp|ospf3?|isis|ldp|rsvp|mpls)\s*$"#,              // SR-OS (no bgp log-neighbor-changes, no)
        #"no\s+(?:ip|ipv6)\s+address\b"#,
        #"no\s+(?:aaa|username|ip\s+ssh|line\s+vty)\b"#,
        #"undo\s+(?:bgp|ospf|isis|mpls|interface|vlan|ip\s+vpn-instance|ip\s+address|ip\s+route-static|port\s+trunk|local-user|stelnet\s+server|ssh\s+server|user-interface)\b"#,
        #"deactivate\b"#,                                            // Junos
        #"set\s+interfaces\s+\S+(?:\s+unit\s+\S+)?\s+disable\b"#,    // Junos
        #"admin-state\s+disable\b"#,                                 // SR-OS MD-CLI
        #"/?configure\s.*(?<!\bno\s)\bshutdown\s*$"#,                // SR-OS en una línea: configure port 1/1/1 shutdown
        #"/?configure\s.*\badmin-state\s+disable\b"#,
        #"aaa\s+new-model\b"#,
        #"transport\s+input\b(?!.*\b(?:ssh|all)\b)"#,                // sin ssh en las vty: se pierde el acceso
        #"(?:ipv6\s+)?access-class\b"#,
        #"acl\s+(?:ipv6\s+)?\S+\s+inbound\b"#,                       // VRP user-interface
        #"switchport\s+trunk\s+allowed\s+vlan\s+(?!add\b|remove\b)"#, // sustituye la lista entera
        #"debug\b"#,                                                 // (undebug y no debug, no)
        // procesos y cortafuegos (Linux)
        #"(?:kill|killall|pkill)\b"#,
        #"iptables\s(?:.*\s)?(?:-F|--flush|-X|--delete-chain)\b"#,
        #"iptables\s(?:.*\s)?-P\s+\S+\s+DROP\b"#,
        #"nft\s+flush\s+ruleset\b"#,
        #"ufw\s+(?:disable|reset)\b"#,
        #"ip\s+link\s+set\s+(?:dev\s+)?\S+\s+down\b"#,
        #"ip\s+(?:addr(?:ess)?|route)\s+flush\b"#,
        #"ifdown\b"#,
        #"ifconfig\s+\S+\s+down\b"#,
    ]
    static let pattern = Pattern("^(?:" + rules.joined(separator: "|") + ")")

    public init() {}

    public func matches(_ line: String) -> Bool { Self.command(in: line) != nil }

    /// La orden peligrosa de la línea (sin el prompt), o nil. Con caracteres de control, la línea entera, con ellos a la
    /// vista (`PasteRules.visible`).
    public static func command(in line: String) -> String? {
        let (clean, controls) = erased(line)
        var l = clean.trimmed
        if let r = prompt.range(in: l) { l = String(l[r.upperBound...]) }
        if controls {
            var raw = line.trimmed
            if let r = prompt.range(in: raw) { raw = String(raw[r.upperBound...]) }
            return PasteRules.visible(raw.trimmed)
        }
        if l.count > maxLength { return String(l.prefix(80)) + "…" }
        return analyze(l, depth: 0)
    }

    /// La línea tal como la ejecutaría el equipo: BS y DEL borran el carácter de antes, Ctrl+U la línea y Ctrl+W la
    /// palabra; ESC (con su secuencia CSI) y los demás C0 y C1 se quitan, salvo TAB, CR y LF. `controls`: llevaba alguno.
    static func erased(_ line: String) -> (text: String, controls: Bool) {
        let u = Array(line.unicodeScalars)
        var out: [Unicode.Scalar] = [], controls = false, i = 0
        while i < u.count {
            let c = u[i]
            i += 1
            switch c.value {
            case 0x09: out.append(c)
            case 0x0A, 0x0D: continue
            case 0x08, 0x7F: controls = true; if !out.isEmpty { out.removeLast() }
            case 0x15: controls = true; out.removeAll()
            case 0x17:
                controls = true
                while let x = out.last, x == " " || x == "\t" { out.removeLast() }
                while let x = out.last, x != " ", x != "\t" { out.removeLast() }
            case 0x1B:
                controls = true
                if i < u.count, u[i] == "[" {                  // (ESC [ … final: «ESC[200~», una flecha)
                    i += 1
                    while i < u.count, !(0x40...0x7E).contains(u[i].value) { i += 1 }
                    i += 1
                }
            case 0x00...0x1F, 0x80...0x9F: controls = true
            default: out.append(c)
            }
        }
        var s = ""
        s.unicodeScalars.append(contentsOf: out)
        return (s, controls)
    }

    private static func analyze(_ l: String, depth: Int) -> String? {
        guard depth <= maxDepth else { return l.trimmed.isEmpty ? nil : l.trimmed }   // (tan anidado, no se sigue: peligrosa)
        if text.matches(unwrapped(l)) { return nil }                // (description, banner: todo es texto)
        // (`$(…)` y `` `…` ``, también entre comillas: lo ejecuta la shell antes que la orden)
        for sub in substitutions(l) {
            if let c = analyze(sub, depth: depth + 1) { return c }
        }
        for part in split(l, pipes: false) {
            let pipes = split(part, pipes: true).map(unwrapped)
            // (lo que va a una shell por la tubería es otra orden: «… | sh», «… | sudo bash»)
            if pipes.count > 1, let last = pipes.last, shell.matches(last) { return part.trimmed }
            for p in pipes {
                guard let inner = shellCommand.group(1, in: p).map(firstArgument) ?? eval.group(1, in: p).map(unquoted) else { continue }
                if let c = analyze(inner, depth: depth + 1) { return c }
            }
            // (los filtros de una orden de lectura son suyos: «show run | include reload», «… | format»)
            if reading.matches(pipes[0]) { continue }
            if pipes.contains(where: { !harmless.matches($0) && pattern.matches($0) }) { return part.trimmed }
        }
        return nil
    }

    /// Sin `do`, `run`, `sudo`… delante, y con la primera palabra como la lee la shell: sin comillas ni `\`
    /// («"reboot"», «\reboot», «re''boot» son «reboot»).
    private static func unwrapped(_ s: String) -> String {
        var c = plainFirstWord(s.trimmed)
        while let r = wrapper.range(in: c), !r.isEmpty { c = plainFirstWord(String(c[r.upperBound...]).trimmed) }
        return c
    }

    private static func plainFirstWord(_ s: String) -> String {
        guard s.contains(where: { $0 == "\"" || $0 == "'" || $0 == "\\" }) else { return s }
        var word = "", quote: Character?, i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if quote == nil, ch == " " || ch == "\t" { break }
            if let q = quote {
                if ch == q { quote = nil } else { word.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == "\\" {
                i = s.index(after: i)
                if i < s.endIndex { word.append(s[i]) } else { break }
            } else {
                word.append(ch)
            }
            i = s.index(after: i)
        }
        return word + s[i...]
    }

    /// Lo de dentro de cada `$(…)` (con sus paréntesis anidados) y de cada `` `…` ``.
    private static func substitutions(_ s: String) -> [String] {
        guard s.contains("$(") || s.contains("`") else { return [] }
        let c = Array(s)
        var out: [String] = [], i = 0
        while i < c.count {
            if c[i] == "\\" { i += 2; continue }
            if c[i] == "$", i + 1 < c.count, c[i + 1] == "(" {
                var depth = 1, j = i + 2, cur = ""
                while j < c.count {
                    if c[j] == "(" { depth += 1 } else if c[j] == ")" { depth -= 1; if depth == 0 { break } }
                    cur.append(c[j])
                    j += 1
                }
                out.append(cur)
                i = j + 1
            } else if c[i] == "`" {
                var j = i + 1, cur = ""
                while j < c.count, c[j] != "`" {
                    if c[j] == "\\", j + 1 < c.count { j += 1 }
                    cur.append(c[j])
                    j += 1
                }
                out.append(cur)
                i = j + 1
            } else {
                i += 1
            }
        }
        return out
    }

    /// El primer argumento, sin sus comillas (el guion de `sh -c '…' arg0`).
    private static func firstArgument(_ s: String) -> String {
        let t = s.trimmed
        guard let q = t.first, q == "\"" || q == "'" else { return t }
        var out = "", i = t.index(after: t.startIndex)
        while i < t.endIndex, t[i] != q {
            if q == "\"", t[i] == "\\", t.index(after: i) < t.endIndex { i = t.index(after: i) }
            out.append(t[i])
            i = t.index(after: i)
        }
        return out
    }

    /// Lo que ejecuta `eval`: sus argumentos juntos, sin comillas (de más: «eval "echo 'a; reboot'"» cuenta).
    private static func unquoted(_ s: String) -> String { s.filter { $0 != "\"" && $0 != "'" } }

    /// Las órdenes: por `;`, `&&` y `||` o, con `pipes`, por `|`; nunca entre comillas («echo "a; reboot"»).
    private static func split(_ s: String, pipes: Bool) -> [String] {
        let c = Array(s)
        var out: [String] = [], cur = "", quote: Character?, i = 0
        while i < c.count {
            let ch = c[i], next: Character? = i + 1 < c.count ? c[i + 1] : nil
            let prev: Character? = i > 0 ? c[i - 1] : nil
            if ch == "\\", quote != "'", let next {      // «\;», «\"»: escapado, no separa ni abre comillas
                cur.append(ch); cur.append(next)
                i += 2
                continue
            }
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if pipes ? ch == "|" : (ch == ";" || (ch == "&" || ch == "|") && next == ch) {
                out.append(cur); cur = ""
                i += pipes || ch == ";" ? 1 : 2
                continue
            } else if !pipes, ch == "&", next != ">", prev != ">", prev != "&" {
                out.append(cur); cur = ""      // «sleep 5 & reboot» (no «&>» ni «2>&1»)
                i += 1
                continue
            }
            cur.append(ch)
            i += 1
        }
        out.append(cur)
        return out
    }
}
