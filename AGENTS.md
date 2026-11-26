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
  contraseña por defecto escrita sola (ssh/telnet desde una sesión, salvo si ha entrado hace menos de 5 min) y las
  listas de equipos. Nunca lo activan el askpass de las sesiones guardadas, las contraseñas de salto, los botones ni el
  menú 🔑.
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
- **Paridad Mac ↔ Windows:** la lógica va UNA vez en `NetDeckCore` y las dos apps sólo la pintan; ninguna función se copia
  entre `Sources/TerminalNetDeck` y `windows/Desktop` (lo vigila `tools/comprobar_paridad.sh`); una función nueva o un
  cambio visible llega a las dos en el mismo PR o queda anotado en la matriz → docs/agentes/paridad.md.
- **Ejemplos y tests sin datos reales:** IPs `192.0.2.x` / `198.51.100.x` / `203.0.113.x` (RFC 5737), `tu.usuario`,
  `core-01`, `bastion`.

## Antes de un commit (obligatorio)
Una pasada funcional en DEMO (`tools/verificar_demo.sh`, con `NETDECK_HOME` temporal y `tools/demo`; nunca con tus
datos reales) que compruebe terminal, explorador SFTP/FTP, pestañas, temas, resaltado y menús, mirando las capturas.
Después, un informe al autor: problemas detectados, arreglos y estado de `./test.sh` y `tools/privacidad.sh`. Skill
`netdeck-verificar-demo` (en .agents/skills).
Excepción, aprobada por el autor el 2026-11-10: los commits hechos **desde Windows** en `propuesta/windows` y en las
ramas `windows/*` no llevan demo (allí no hay app que probar todavía). Basta con `bash tools/privacidad.sh` en verde, el
núcleo compilando en Windows (desde el paso P2), los tests con `windows/scripts/test.ps1` (desde P6) y el informe en
`windows/ESTADO.md`. Nada de esas ramas se fusiona a `main` sin la pasada completa en el Mac (`./test.sh` + demo).

## Git
- Autor `Jonay <jonayrr.jr@gmail.com>` (git config local del repo). Nunca el correo corporativo ni una línea de coautor.
- Mensajes en castellano: un título corto, una línea en blanco y viñetas con el porqué.
- Forzar un push (`--force`) o mover un tag, sólo si el autor lo pide expresamente.

## Windows (port en curso)
- El código Windows vive en `windows/` y en las ramas `#if os(Windows)` de `Sources/NetDeckCore`. Todo lo nuevo va tras
  `#if os(Windows)` o en archivos exclusivos del target `NetDeckWindows`. Lo compartido con macOS sólo se cambia si en
  macOS el comportamiento queda idéntico y `./test.sh` sigue en verde; si hace falta tocar `Package.swift`,
  `Package.resolved` o el comportamiento de macOS, se para y se pregunta al autor.
- Rama activa: `windows/p14-escritorio` (PR #7 contra `main`). Estado y próximos pasos: `windows/ESTADO.md`; la lista
  priorizada de pendientes, en `windows/PENDIENTE.md`.
- Fin de línea y BOM: LF y sin BOM en `Sources/`, `Tests/`, `tools/` y `.github/` (lo vigila `tools/comprobar_formato.sh`
  dentro de `./test.sh`); los `.ps1` con acentos sí llevan BOM (PowerShell 5.1 los lee como ANSI sin él).
  Los `.ps1` con algún carácter no ASCII (acentos, «—») llevan BOM; el resto, no. Al escribir archivos desde Windows,
  sin BOM: `[System.IO.File]::WriteAllText(path, content, (New-Object System.Text.UTF8Encoding $false))`. La regla antigua
  «no usar Edit/Write de Claude» no se ha reproducido en el PC del autor: manda `tools/comprobar_formato.sh`.
- CI de Windows: `.github/workflows/windows.yml` (`windows-2022`, sin `continue-on-error`: un rojo es real; los tests
  van con `windows/scripts/test.ps1 --no-parallel`) y `.github/workflows/windows-release.yml` (instalador `.msi` y
  versión portable `.zip`; sube a la Release sólo en tags y con la variable `WINDOWS_RELEASE=true`). Se pueden
  cambiar, pero cada cambio se comprueba con un run en GitHub y no se vuelve a ocultar un job con `continue-on-error`.
  `windows/scripts/test.ps1` lo gestiona Codex: si hay que tocarlo, se avisa. Publicar un tag o una Release lo hace el autor.

## Más detalle (léelo cuando el trabajo lo toque)
- docs/agentes/agentes.md: qué agente o skill usar y cómo se fusiona su trabajo. Los agentes, para trabajo grande y
  revisiones.
- docs/agentes/publicar.md: cambio de versión, tag y Release (skill `netdeck-publicar` en .agents/skills).
- docs/agentes/arquitectura.md · docs/agentes/idiomas.md · docs/agentes/comandos.md · docs/agentes/paridad.md.
- `windows/CLAUDE.md`: guía completa del port Windows (ramas `windows/*`). **Si trabajas desde Windows,
  léelo antes de nada**: allí no hay `./test.sh` ni demo y cambian los comandos.
