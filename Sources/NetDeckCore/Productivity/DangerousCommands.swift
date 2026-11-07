import Foundation

/// Órdenes peligrosas (`PasteRules.dangerous`): las que reinician, apagan, borran o sustituyen la configuración, o cortan
/// el acceso. Se mira la orden, no las palabras sueltas: se quita el prompt («core-01#», «<core-01>», «tu.usuario@mx-01>»,
/// «admin@bastion:~$»…) y lo que la ejecuta desde otro modo (`do`, `run`, `admin`, `sudo`), y cada regla va anclada al
/// principio. Así «no shutdown», «show … reset», «description reload-test», «| include clear» o «reload cancel» no
/// saltan. Un `commit` normal tampoco (sí «commit replace»). Con las abreviaturas de IOS («relo», «shu», «wr er»…).
/// Cisco IOS/IOS-XE/XR/NX-OS, Junos, Huawei VRP, Nokia SR-OS y Linux. Con `;`, `&&` o `||` cuenta cada orden (no entre
/// comillas ni en un `description` o `banner`, que son texto); tras un `|`, los filtros de una orden de lectura
/// (`show … | include reload`) no, y los de una de Linux sí (`… | xargs rm -rf`).
public struct DangerousCommands: Sendable {
    /// El prompt de delante, si lo hay (sin él, la línea es la orden).
    /// («[root@bastion ~]#» de RHEL entero; «reboot>/dev/null» no es un prompt)
    static let prompt = Pattern(#"^\s*(?:<[^<>\s]{1,80}>|\[[^\[\]]{1,80}\]\s*[>#$%]?|\*?[A-D]:\S{0,80}?[#$]|[A-Za-z0-9_.@:/()~\-\[\]>]{0,80}[A-Za-z0-9_)~\]][#>$%](?![/&>])|\$)\s*"#,
                                ignoreCase: false)
    /// Lo que ejecuta la orden desde otro modo o la pasa a otra: `do reload` (configuración de Cisco), `run request
    /// system reboot` (Junos), `admin reboot` (IOS-XR, SR-OS), `sudo reboot`, `/admin reboot` (MD-CLI), `/sbin/reboot`,
    /// `… | xargs rm -rf`, `sudo -u root reboot`.
    static let wrapper = Pattern(#"^(?:(?:/usr)?(?:/local)?/s?bin/|/(?=[a-z])|(?:do|run|admin|exec|nohup|time|sudo(?:\s+-[ugChpD]\s+\S+|\s+-\S+)*|xargs(?:\s+-\S+)*)\s+)"#)
    /// Órdenes de lectura: nunca peligrosas, ni con sus filtros detrás (`show … reset`, `show run | include reload`).
    static let reading = Pattern(#"^(?:sh(?:o(?:w)?)?(?!\s+-)|dis(?:p(?:lay)?)?|ping|traceroute|tracert|trace|description|desc|undebug|un?\s+all|no\s+debug|undo\s+debugging)(?:\s|$)"#)
    /// Lo que deshace un peligro, sólo limpia la pantalla o es de diagnóstico de todos los días (la orden entera): «no shu»,
    /// «reload cancel», «clear ip bgp * soft» (no tira la sesión), «clear counters», «clear logging», «shutdown -c» (Linux:
    /// cancela el apagado), «clear system reboot» (Junos: cancela el reinicio).
    static let harmless = Pattern(#"^(?:(?:no|undo)\s+shu\w*|rel(?:o(?:ad?)?)?\b.*\bcancel|admin-state\s+enable|cle(?:ar?)?(?:\s+screen)?|reset|cle(?:ar?)?\s+(?:ip\s+|ipv6\s+)?bgp\b.*\bsoft(?:-inbound|\s+(?:in|out))?|cle(?:ar?)?\s+system\s+reboot|shutdown\s+-c|cle(?:ar?)?\s+(?:counters|log(?:ging)?)\b.*)\s*$"#)
    /// Texto, no órdenes: ni se corta por `;`, `&&` o `|` ni se mira lo de detrás.
    static let text = Pattern(#"^(?:desc(?:ription)?|banner)(?:\s|$)"#)

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
        #"systemctl\s+(?:reboot|poweroff|halt|kexec)\b"#,
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
        #"rm\s+(?:.*\s)?-(?:[A-Za-z]*[rR]|-recursive\b)"#,           // rm -rf, rm -r, rm -fr
        #"mkfs(?:\.\w+)?\b"#,
        #"wipefs\b"#,
        #"dd\s+.*\bof=/dev/"#,
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
        #"iptables\s+(?:.*\s)?(?:-F|--flush|-X|--delete-chain)\b"#,
        #"iptables\s+(?:.*\s)?-P\s+\S+\s+DROP\b"#,
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

    /// La orden peligrosa de la línea (sin el prompt), o nil.
    public static func command(in line: String) -> String? {
        var l = String(line.trimmed.prefix(2000))
        if let r = prompt.range(in: l) { l = String(l[r.upperBound...]) }
        if text.matches(unwrapped(l)) { return nil }                // (description, banner: todo es texto)
        for part in split(l, pipes: false) {
            let pipes = split(part, pipes: true).map(unwrapped)
            // (los filtros de una orden de lectura son suyos: «show run | include reload», «… | format»)
            if reading.matches(pipes[0]) { continue }
            if pipes.contains(where: { !harmless.matches($0) && pattern.matches($0) }) { return part.trimmed }
        }
        return nil
    }

    /// Sin `do`, `run`, `sudo`… delante.
    private static func unwrapped(_ s: String) -> String {
        var c = s.trimmed
        while let r = wrapper.range(in: c), !r.isEmpty { c = String(c[r.upperBound...]).trimmed }
        return c
    }

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
