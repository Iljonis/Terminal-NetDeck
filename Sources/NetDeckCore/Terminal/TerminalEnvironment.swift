import Foundation

/// El entorno con el que se lanza cada pestaña. macOS trae «SendEnv LANG LC_*» en /etc/ssh/ssh_config.d: ssh manda
/// el idioma del Mac al servidor y, si allí no existe ese locale (es_ES.UTF-8…), cada orden avisa con «setlocale:
/// LC_CTYPE: cannot change locale». Por defecto, a ssh no le llega ninguna de esas variables (el servidor usa la suya).
public enum TerminalEnvironment {
    public static func prepare(_ base: [String: String], forSSH: Bool, sendLocale: Bool) -> [String: String] {
        var env = base
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if forSSH, !sendLocale {
            for k in env.keys where k == "LANG" || k == "LANGUAGE" || k.hasPrefix("LC_") { env[k] = nil }
        } else if env["LANG"] == nil {
            env["LANG"] = "en_US.UTF-8"                  // (local o si lo pides: UTF-8 sin imponer un idioma)
        }
        return env
    }
}
