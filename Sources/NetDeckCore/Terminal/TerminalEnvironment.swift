import Foundation

/// El entorno con el que se lanza cada pestaña. macOS trae «SendEnv LANG LC_*» en /etc/ssh/ssh_config.d: ssh manda
/// el idioma del Mac al servidor y, si allí no existe ese locale (es_ES.UTF-8…), cada orden avisa con «setlocale:
/// LC_CTYPE: cannot change locale». Por defecto, a ssh sólo le llega LC_CTYPE=C.UTF-8: sin ninguna, ssh escribe los
/// banners y avisos con acentos en octal («Clasificaci\303\263n»); C.UTF-8 no impone idioma y existe en cualquier
/// Linux moderno (si el servidor lo recibe; los equipos de red lo ignoran).
public enum TerminalEnvironment {
    public static func prepare(_ base: [String: String], forSSH: Bool, sendLocale: Bool) -> [String: String] {
        var env = base
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if forSSH, !sendLocale {
            for k in env.keys where k == "LANG" || k == "LANGUAGE" || k.hasPrefix("LC_") { env[k] = nil }
            env["LC_CTYPE"] = "C.UTF-8"
            #if os(Windows)
            // Windows: lo heredado del proceso padre no debe mandar sobre ssh.exe. SSH_ASKPASS(_REQUIRE) lo pone la app
            // (Askpass.environment, DESPUES de esta funcion); si ya vienen puestos (Git for Windows, otro lanzador) harian
            // que ssh preguntase por otro programa. GIT_SSH y GIT_SSH_COMMAND son de git, pero asi no hay dudas de que ssh
            // se usa. Los nombres de variable en Windows no distinguen mayusculas. USERPROFILE, APPDATA y LOCALAPPDATA
            // NO se tocan: ssh.exe las necesita para encontrar ~/.ssh y no cambian ningun comportamiento de seguridad.
            let interferentes: Set<String> = ["SSH_ASKPASS", "SSH_ASKPASS_REQUIRE", "GIT_SSH", "GIT_SSH_COMMAND"]
            for k in env.keys where interferentes.contains(k.uppercased()) { env[k] = nil }
            #endif
        } else if env["LANG"] == nil {
            env["LANG"] = "en_US.UTF-8"                  // (local o si lo pides: UTF-8 sin imponer un idioma)
        }
        return env
    }
}
