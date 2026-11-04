---
name: terminal-netdeck-patterns
description: "Use in Terminal NetDeck before changing passwords, askpass, autopass, the Keychain, credentials, MultiExec/paste, AppModel, AppCore or TerminalSession, or when unsure which files change together: module map, hot spots, co-change sets and the non-obvious rules (15-min block, SecureCRT-style credentials) learned from past regressions. For commits use CLAUDE.md, for UI text netdeck-texto-visible, for releases netdeck-publicar."
metadata:
  version: "2.0.0"
  source: local-git-analysis + historial de regresiones
  analyzed_commits: "92"
---

# Terminal NetDeck: mapa y reglas que no se ven en el código

## Mapa
- NetDeckCore (lógica con tests): Highlight/, Input/, Productivity/ (SafePaster, MultiExec, macros), Remote/ (SFTP/FTP),
  Security/ (Askpass, PasswordAutomation, TypedPassword, KeychainStore, CredentialStore), Sessions/, Support/
  (Idioma, Ingles), Terminal/, Themes/. TerminalNetDeck = la app SwiftUI. Desde 0.9.8 sólo el `ssh` de macOS.
- Puntos calientes: AppModel, TerminalSession, ContentView, Ingles, Askpass, PasswordAutomation, SessionManager.
  Un cambio en uno de ellos casi siempre arrastra a otro: antes de dar algo por terminado, mira si el otro necesita
  el mismo ajuste.

## Qué cambia junto
| Si tocas… | Revisa también |
|---|---|
| Askpass / autopass / Llavero | PasswordAutomation, TypedPassword, KeychainStore, CredentialStore y sus tests (AskpassGuardarTests, AutopassRobustoTests…) |
| Texto visible | Ingles.swift en el mismo commit (44 de 92 commits) → skill `netdeck-texto-visible` |
| Lo de una ventana | si afecta a todas las pestañas, va por `core.allTabs`, no por `model.tabs` |
| Menús | `MenuRefresh` (SwiftUI no los reevalúa con `@Observable`) y `modalOpen` en la acción |
| MultiExec, pegado, botones `.run` | `route.isLocal` y los tipos sftp/serie/ftp, fuera; `PasteRules` |

## NUNCA (cada punto costó una regresión o una petición expresa del autor)
- **Bloqueo de 15 min:** sólo lo activa la contraseña por defecto que se escribe sola al hacer ssh/telnet desde una
  sesión (salvo si ha entrado hace menos de 5 min: el rechazo es de ese equipo, sin ese usuario), y las listas de
  equipos (para proteger la cuenta AD). Nunca lo actives desde el askpass de sesiones
  guardadas, las contraseñas de salto, los botones o el menú 🔑: el autor quiere que esos caminos funcionen siempre.
- **Credenciales:** al estilo de SecureCRT: una lista de contraseñas con nombre y el mismo selector, con «Nueva…»,
  en todas partes. Nunca hagas pantallas de credenciales complejas. Los botones pueden llevar la contraseña escrita en
  texto plano (sólo se escribe ante «Password:», nunca se muestra, nunca se exporta).
- **Llavero:** lee con `-g`, no con `-w`: con `-w`, macOS devuelve en hexadecimal las contraseñas con ñ, €, º o «\\»
  y se escribían mal (una cuenta AD quedó bloqueada). El secreto va por stdin y las lecturas, fuera del hilo principal.
- **Autopass:** no lo dispares por salida (`show run`, banners, registros): sólo al enviar una orden SSH/Telnet. Ten
  en cuenta `clear`, la pantalla alternativa (tmux, screen, less, vi), el historial lleno y los cortes de conexión;
  un Esc no puede comerse la tecla siguiente.
- **Ratón en las pestañas:** no interceptes clics en monitores locales para reenviarlos a mano (`stillZones`): así se
  rompió la 0.9.2 (no se podía cambiar ni cerrar pestañas) y hubo que retirarla.
- **Tests de ventana:** la pantalla del runner de la CI es de 1024 px. Ninguna ventana ni clic de un test puede tapar
  los puntos de arrastre ni caer fuera de la pantalla.
- **Tests de tiempo:** márgenes amplios (p. ej. 30 s en vez de 5): en la CI van más lentos y fallan sin motivo real.
