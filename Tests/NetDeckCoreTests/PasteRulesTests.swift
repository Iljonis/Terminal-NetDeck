import Foundation
import Testing
@testable import NetDeckCore

/// Órdenes peligrosas (`PasteRules.dangerous`) y la ventana de revisión del pegado (`PasteReview`).
@Suite struct PasteRulesTests {
    static let peligrosas = [
        // Linux: comillas escapadas y «&» suelto (auditoría 0.9.12)
        #"echo \"; reboot"#, #"echo it\'s; reboot"#, "sleep 5 & reboot",
        // Cisco IOS / IOS-XE / NX-OS
        "reload", "reload in 10", "reload at 23:00", "do reload", "shutdown", "shut", " shutdown ",
        "clear ip bgp *", "clear bgp all *", "clear line vty 0", "clear arp-cache",
        "clear ip ospf process", "clear crypto session", "no router bgp 65000", "no router ospf 1",
        "no ip routing", "no interface Loopback10", "no vlan 10", "no feature bgp", "no switchport",
        "no ip address", "no spanning-tree vlan 10", "no username tu.usuario", "no aaa new-model",
        "copy tftp://192.0.2.10/core-01.cfg running-config", "copy flash:base.cfg startup-config",
        "copy startup-config running-config", "copy bootflash:x.cfg nvram:startup-config", "copy scp: running-config",
        "configure replace flash:base.cfg", "conf replace bootflash:x", "boot system flash:c2960.bin",
        "no boot system", "config-register 0x2142", "crypto key zeroize rsa", "aaa new-model",
        "transport input none", "access-class 10 in", "switchport trunk allowed vlan 10,20",
        "debug ip packet", "debug all", "write erase", "wr erase", "erase startup-config", "erase nvram:",
        "format flash:", "delete flash:c2960.bin", "delete /force /recursive bootflash:old", "squeeze flash:",
        "default interface GigabitEthernet0/1", "install all nxos bootflash:nxos.bin", "rollback running-config checkpoint antes",
        "redundancy force-switchover",
        // IOS-XR
        "commit replace", "rollback configuration last 1", "admin reload location all", "hw-module location 0/1/CPU0 reload",
        "process restart bgp", "clear configuration inconsistency", "install activate disk0:x.pie",
        // Junos
        "request system reboot", "request system halt", "request system power-off", "request system zeroize",
        "run request system reboot", "request system software add /var/tmp/junos.tgz", "request chassis fpc slot 0 offline",
        "restart routing", "load override terminal", "load replace /var/tmp/x.conf", "rollback 1", "delete interfaces ge-0/0/0",
        "deactivate protocols bgp", "set interfaces ge-0/0/1 disable", "set interfaces ge-0/0/1 unit 0 disable",
        "wildcard delete interfaces ge-*", "file delete /var/tmp/x", "clear bgp neighbor 192.0.2.1",
        // Huawei VRP
        "reboot", "reset saved-configuration", "reset bgp all", "reset counters interface", "undo bgp 65000",
        "undo interface Vlanif10", "undo ip address", "undo port trunk allow-pass vlan 10", "undo local-user tu.usuario",
        "startup saved-configuration base.cfg", "rollback configuration to label antes",
        // Nokia SR-OS
        "admin reboot now", "/admin reboot", "admin redundancy force-switchover now", "admin rollback revert latest-rb",
        "configure port 1/1/1 shutdown", "admin-state disable", "file delete cf3:/x.cfg",
        // Linux
        "sudo reboot", "sudo shutdown -h now", "/sbin/reboot", "halt", "poweroff", "init 6", "systemctl reboot",
        "systemctl stop sshd", "rm -rf /tmp/x", "rm -fr x", "rm -r x", "sudo rm -Rf /var/log/x", "iptables -F",
        "iptables -t nat -F", "iptables -P INPUT DROP", "nft flush ruleset", "killall ssh", "pkill -9 sshd", "kill -9 1234",
        "ip link set eth0 down", "ip addr flush dev eth0", "ifdown eth0", "mkfs.ext4 /dev/sdb1", "dd if=/dev/zero of=/dev/sda",
        "ls; reboot", "true && rm -rf x", "find . -name x | xargs rm -rf", "for i in a b; do rm -rf $i; done",
        // MikroTik
        "/system reboot",
        // abreviaturas de IOS
        "relo", "reloa", "rel", "do rel", "wr er", "write er", "cle ip bgp *", "shu", "core-01(config-if)#shu",
        "no int Gi0/1", "no inter Loopback0", "copy flash:x runn", "cop flash:x run", "copy flash:x sta",
        "copy /noverify tftp://192.0.2.10/x.cfg running-config", "era nvram:",
        // CR solo y prompts de Linux
        "[root@bastion ~]# reboot", "[tu.usuario@bastion tmp]$ sudo shutdown -h now", "reboot>/dev/null",
        "reboot >/dev/null 2>&1", "sudo -u root reboot", "sudo -g wheel rm -rf /var/log/x",
        // quitar vecinos, rutas y acceso
        "neighbor 192.0.2.2 shutdown", "no neighbor 192.0.2.2", "no neighbor 192.0.2.2 remote-as 65001",
        "no ip route 0.0.0.0 0.0.0.0 192.0.2.1", "no ipv6 route ::/0 2001:db8::1", "no ip default-gateway",
        "undo ip route-static 0.0.0.0 0 192.0.2.1", "undo mpls", "transport input telnet", "transport input none",
        "ipv6 access-class V6-VTY in", "acl 2000 inbound", "acl ipv6 3000 inbound",
        "request vmhost reboot", "request vmhost software add /var/tmp/x.tgz", "load factory-default",
        // SR-OS
        "no bgp", "no ospf", "no ospf3", "no isis", "no ldp", "no rsvp", "no mpls",
        "/configure router bgp admin-state disable", "configure port 1/1/1 admin-state disable",
        // con el prompt delante
        "core-01#reload", "core-01# reload", "core-01(config-if)#shutdown", "core-01(config)#no router bgp 65000",
        "<core-01>reboot", "[~core-01-GigabitEthernet0/0/1]shutdown", "tu.usuario@mx-01> request system reboot",
        "tu.usuario@mx-01# load override terminal", "RP/0/RSP0/CPU0:pe-01#reload", "RP/0/RSP0/CPU0:pe-01(config)#commit replace",
        "A:core-01# admin reboot now", "*A:core-01>config>router# shutdown", "tu.usuario@bastion:~$ sudo reboot",
        "[admin@MikroTik] > /system reboot", "$ rm -rf /tmp/x", "RELOAD", "Clear Ip Bgp *",
    ]

    static let seguras = [
        // «&» que no separa órdenes
        "ls -l 2>&1", "make &> build.log", #"echo "a & reboot""#,
        // lo que deshace un peligro
        "no shutdown", "no shut", "undo shutdown", "reload cancel", "reload in 10 cancel", "admin-state enable",
        "configure port 1/1/1 no shutdown", "undebug all", "u all", "no debug all",
        // lectura (aunque lleve una palabra peligrosa detrás)
        "show running-config", "show reload", "show interfaces counters reset", "show run | include clear",
        "show run | include reload", "show logging | include shutdown", "show tech | format flash:x.odm",
        "sh run | i shutdown", "display current-configuration | include reset", "display reboot-info",
        "show configuration | display set | match reboot", "show system rollback", "show log messages | match reboot",
        "ping 192.0.2.1", "traceroute 198.51.100.1", "do show ip interface brief",
        "core-01#show ip bgp summary", "<core-01>display version", "tu.usuario@mx-01> show route 203.0.113.0/24",
        // configuración normal
        "description reload-test", "description shutdown por obras", "desc enlace a core-02 (clear)",
        "interface GigabitEthernet0/1", "ip address 192.0.2.1 255.255.255.0", "commit", "commit confirmed 5",
        "commit and-quit", "commit check", "set system host-name core-01", "set interfaces ge-0/0/1 description uplink",
        "router bgp 65000", "neighbor 192.0.2.2 remote-as 65001", "switchport trunk allowed vlan add 30",
        "switchport trunk allowed vlan remove 40", "switchport mode trunk", "copy running-config startup-config",
        "copy run start", "copy running-config tftp://192.0.2.10/core-01.cfg", "copy tftp: flash:", "write memory", "wr",
        "end", "exit", "configure terminal", "conf t", "system-view", "save", "port trunk allow-pass vlan 10",
        "line vty 0 4", "transport input ssh", "logging host 192.0.2.50", "! reload despues", "# reboot luego",
        "banner motd ^C Prohibido: reload ^C", "terminal length 0", "clear", "clear screen", "reset",
        "ip access-group 10 in", "aaa authentication login default local",
        // abreviaturas que no son peligrosas, y lo de cada día al diagnosticar
        "shuf x.txt", "no shu", "releases", "relative", "copy stby-bootflash:x bootflash:x",
        "transport input ssh telnet", "transport input all", "no bgp log-neighbor-changes",
        "no neighbor 192.0.2.2 shutdown", "no neighbor 192.0.2.2 description core-02", "clear ip bgp * soft",
        "clear ip bgp 192.0.2.2 soft in", "clear bgp all * soft out", "clear system reboot", "shutdown -c",
        "sudo shutdown -c", "clear counters", "clear counters GigabitEthernet0/1", "clear log", "clear logging",
        // texto y comillas
        "description uplink; reload pendiente", "description \"a; reboot\"", "banner motd ^C a | reload ^C",
        "echo \"a; reboot\"", "echo 'x && rm -rf /'",
        // Linux sin peligro
        "ls -la", "cat /etc/hosts", "grep reboot /var/log/syslog", "tail -f /var/log/messages | grep shutdown",
        "rm archivo.txt", "rm my-report.txt", "echo hola", "sudo systemctl status sshd", "ip link show",
        "killing-floor", "debugger", "deleted", "erased", "", "   ",
    ]

    @Test(arguments: peligrosas) func peligrosa(_ line: String) {
        #expect(PasteRules.dangerous.matches(line), "debería ser peligrosa: «\(line)»")
    }

    @Test(arguments: seguras) func segura(_ line: String) {
        #expect(!PasteRules.dangerous.matches(line), "no debería ser peligrosa: «\(line)»")
    }

    @Test func laOrdenSinElPrompt() {
        #expect(DangerousCommands.command(in: "core-01(config)#no router bgp 65000") == "no router bgp 65000")
        #expect(DangerousCommands.command(in: "<core-01>reboot") == "reboot")
        #expect(DangerousCommands.command(in: "ls; reboot") == "reboot")
        #expect(DangerousCommands.command(in: "core-01#show version") == nil)
        #expect(DangerousCommands.command(in: "[root@bastion ~]# reboot") == "reboot")
        #expect(DangerousCommands.command(in: "echo \"a; b\"; reboot") == "reboot")
    }

    @Test func cortaTambienPorUnCRSolo() {
        #expect(PasteRules.dangerousLines(in: "show clock\rreload") == ["reload"])
        #expect(PasteRules.dangerousLines(in: "interface Gi0/1\rshutdown") == ["shutdown"])
        #expect(PasteRules.lines(of: "a\r\nb\rc\n\nd") == ["a", "b", "c", "d"])
    }

    @Test func lineasPeligrosasDeUnPegado() {
        let text = "interface GigabitEthernet0/1\r\n description reload-test\r\n shutdown\r\n no shutdown\r\nend\r\nreload\n"
        #expect(PasteRules.dangerousLines(in: text) == [" shutdown", "reload"])
        #expect(Macro(name: "m", steps: [.send("show clock"), .send("clear ip bgp *")]).dangerousLines == ["clear ip bgp *"])
    }

    @Test func unaConfiguracionEnteraNoTarda() {
        let config = (1...2000).map { "interface GigabitEthernet0/\($0)\n description enlace \($0)\n no shutdown" }.joined(separator: "\n")
        let start = ContinuousClock.now
        #expect(PasteRules.dangerousLines(in: config).isEmpty)
        #expect(ContinuousClock.now - start < .seconds(30))
    }

    // MARK: - revisar antes de pegar

    @Test func revisionPorElUmbral() {
        #expect(!PasteReview.needed("show clock", enabled: true))
        #expect(!PasteReview.needed("a\nb\nc", enabled: true, threshold: 3))
        #expect(PasteReview.needed("a\nb\nc\nd", enabled: true, threshold: 3))
        #expect(!PasteReview.needed("a\nb\nc\nd", enabled: true, threshold: 5))
        #expect(PasteReview.needed("a\nb", enabled: true, threshold: 1))
        #expect(PasteReview.defaultThreshold == 3)
    }

    @Test func revisionSinContarLasVacias() {
        #expect(!PasteReview.needed("a\n\n\nb\n   \n\tc\n\n", enabled: true, threshold: 3))
        #expect(!PasteReview.needed("\n\n\n\n\n", enabled: true))
        #expect(!PasteReview.needed("", enabled: true))
    }

    @Test func revisionConFinalesDeWindowsYCRSolo() {
        #expect(!PasteReview.needed("a\r\nb\r\nc\r\n", enabled: true, threshold: 3))
        #expect(PasteReview.needed("a\r\nb\r\nc\r\nd\r\n", enabled: true, threshold: 3))
        // (un CR solo también es un Intro en el equipo)
        #expect(PasteReview.needed("a\rb\rc\rd", enabled: true, threshold: 3))
        #expect(PasteReview.lines(of: "a\r\nb\rc\nd") == ["a", "b", "c", "d"])
    }

    @Test func revisionConPeligrosas() {
        #expect(PasteReview.needed("reload", enabled: true))
        #expect(PasteReview.needed("interface Gi0/1\r\nshutdown", enabled: true, threshold: 3))
        #expect(PasteReview.needed("core-01#clear ip bgp *\n", enabled: true, threshold: 50))
        #expect(!PasteReview.needed("interface Gi0/1\nno shutdown", enabled: true, threshold: 3))
    }

    @Test func revisionNoSaleSiPidenUnSecreto() {
        // (lo pegado es la contraseña: ni se enseña con ⚠ ni se cuenta)
        #expect(PasteReview.needed("Delete!2024", enabled: true))
        #expect(!PasteReview.needed("Delete!2024", enabled: true, secretPrompt: true))
        #expect(!PasteReview.needed("reload\nreload\nreload\nreload\nreload", enabled: true, threshold: 1, secretPrompt: true))
    }

    @Test func revisionConLasPeligrosasYaMiradas() {
        let r = PasteReview.review("interface Gi0/1\r\n\r\n shutdown\rno shutdown\nreload", enabled: true)
        #expect(r?.rows == ["interface Gi0/1", "", " shutdown", "no shutdown", "reload"])
        #expect(r?.dangerous == [2, 4])
        #expect(r?.count == 4)
        #expect(PasteReview.review("show clock", enabled: true) == nil)
    }

    @Test func revisionDesactivadaNuncaSale() {
        #expect(!PasteReview.needed("reload", enabled: false))
        #expect(!PasteReview.needed((1...500).map { "line \($0)" }.joined(separator: "\n"), enabled: false, threshold: 1))
        #expect(!PasteReview.needed("write erase\nreload", enabled: false))
    }
}
