# Terminal NetDeck

App nativa de macOS (Swift 6 / SwiftUI + SwiftTerm) para ingenieros de red. Funciones y uso: README.md.
Repositorio público: https://github.com/Iljonis/Terminal-NetDeck. Este archivo y CLAUDE.md (Claude Code) son la misma raíz:
si cambias uno, cambia el otro.

## Comandos
- `swift build` · `./test.sh` (privacidad, prueba de actualización y tests del núcleo; siempre en verde antes de un
  commit, también en GitHub Actions) · `tools/verificar_demo.sh` (demo) · `tools/privacidad.sh [--binario]`.
- `swift run TerminalNetDeck` sólo lo usa el autor (arranca con sus datos). Un agente nunca arranca la app sin un
  `NETDECK_HOME` temporal con `tools/demo`: skill `netdeck-run`.
- Más órdenes (install, actualizar, seguridad_cron, capturas y sus variables `NETDECK_SNAPSHOT*`): docs/agentes/comandos.md.

## Reglas que no se rompen
- **Idiomas:** el código está en castellano de España y la interfaz va en castellano e inglés. Todo texto visible va con
  `L("…")` y su inglés en `NetDeckCore/Support/Ingles.swift` → docs/agentes/idiomas.md antes de tocar textos.
- **Sesiones:** sólo en el archivo propio de la app, en formato ssh_config (`SessionFile`, validado con `ssh -G`), con
  un `Include` en `~/.ssh/config`. Nada de un `sesiones.json` aparte. Los datos propios van como anotaciones `# @…`.
- **Archivos del usuario** (ssh_config, botones.txt, listas): siempre con `SafeFile` (no se pisa lo que no se puede
  leer; copias `.anterior` y `.original`; escritura atómica 0600). Carpetas con `AppPaths.ensure` (0700).
- **Contraseñas:** sólo en el Llavero (`KeychainStore` vía `/usr/bin/security`, el secreto por stdin, nunca en
  argumentos ni en `DebugLog`), con lecturas fuera del hilo principal y la regla de usuario estricta
  (`CredentialPolicy`). El bloqueo de 15 min en todas las pestañas (`CredentialLedger`) sólo lo activan un fallo de la
  contraseña por defecto escrita sola (ssh/telnet desde una sesión) y las listas de equipos. Nunca lo activan el askpass
  de las sesiones guardadas, las contraseñas de salto, los botones ni el menú 🔑.
- **MultiExec y pegado:** sólo a pestañas ssh/telnet (`route.isLocal` y los tipos sftp/serie/ftp quedan fuera). El
  pegado seguro se para ante errores, paginadores, órdenes peligrosas sin confirmar o un prompt de contraseña.
- **Ventanas:** un `AppCore` común y un `AppModel` por ventana. Lo que afecta a todas las pestañas va por
  `core.allTabs`. Los menús se refrescan con `MenuRefresh` y comprueban `modalOpen` → docs/agentes/arquitectura.md.
- **Seguridad de entrada:** `SessionImporter.safeExtra` quita las opciones que ejecutan órdenes. Los nombres, equipos y
  usuarios que empiezan por `-` se rechazan. A ssh sólo le llega `LC_CTYPE=C.UTF-8` (`TerminalEnvironment`).
- **Actualizaciones:** sólo enlaces https de github.com y nada se instala sin el clic en «Actualizar ahora». El .dmg se
  comprueba con sha256, id, versión y `codesign --verify`.
- **Mensajes y rutas:** los errores van a `ErrorLog`, sin secretos. Lo que ve el usuario, por `model.status`; sólo los
  que empiezan por ✗ 🔑 ⎋ ⬆ salen como aviso. Rutas en pantalla siempre con `AppPaths.tilde(…)`.
- **Pestañas al arrancar:** no se guardan ni se reabren las de loopback (127.x/localhost) ni las de las capturas.
- **Ejemplos y tests sin datos reales:** IPs `192.0.2.x` / `198.51.100.x` / `203.0.113.x` (RFC 5737), `tu.usuario`,
  `core-01`, `bastion`.

## Antes de un commit (obligatorio)
Una pasada funcional en DEMO (`tools/verificar_demo.sh`, con `NETDECK_HOME` temporal y `tools/demo`; nunca con tus
datos reales) que compruebe terminal, explorador SFTP/FTP, pestañas, temas, resaltado y menús, mirando las capturas.
Después, un informe al autor: problemas detectados, arreglos y estado de `./test.sh` y `tools/privacidad.sh`. Skill
`netdeck-verificar-demo` (en .agents/skills).

## Git
- Autor `Jonay <jonayrr.jr@gmail.com>` (git config local del repo). Nunca el correo corporativo ni una línea de coautor.
- Mensajes en castellano: un título corto, una línea en blanco y viñetas con el porqué.
- Forzar un push (`--force`) o mover un tag, sólo si el autor lo pide expresamente.

## Más detalle (léelo cuando el trabajo lo toque)
- docs/agentes/agentes.md: qué agente o skill usar y cómo se fusiona su trabajo. Los agentes, para trabajo grande y
  revisiones.
- docs/agentes/publicar.md: cambio de versión, tag y Release (skill `netdeck-publicar` en .agents/skills).
- docs/agentes/arquitectura.md · docs/agentes/idiomas.md · docs/agentes/comandos.md.
