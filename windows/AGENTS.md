# Terminal NetDeck en Windows: instrucciones para el agente

Este archivo y `windows/CLAUDE.md` (Claude Code) son el mismo: si cambias uno, cambia el otro. Las reglas de la raíz
(`CLAUDE.md` / `AGENTS.md`) siguen valiendo todas; aquí sólo va lo que cambia o se añade al trabajar desde Windows.

## Al empezar cada sesión
1. Lee `windows/ESTADO.md` (dónde se quedó) y el paso que toque de `windows/PLAN.md`. No hace falta leer el resto del
   plan: cada paso trae su propio contexto. Lee también el apartado «Convenciones» del plan.
2. Comprueba la rama: el trabajo de Windows va en `propuesta/windows` o en ramas `windows/pN-<tema>` que salen de ella.
   **Nunca** directamente en `main`.
3. `git pull` antes de tocar nada: el autor también trabaja desde un Mac.

## Al terminar cada sesión
- Marca en `windows/PLAN.md` las tareas hechas (`[x]`) y escribe arriba en `windows/ESTADO.md` qué has hecho, qué falta,
  qué ha fallado y cuál es el siguiente paso. Así la próxima sesión, en Windows o en el Mac, sigue sin repetir nada.
- Los resultados van resumidos en `windows/resultados/*.md`, **sin datos reales**: nada de IPs, equipos, usuarios ni
  rutas tuyas (`192.0.2.x`, `core-01`, `bastion`, `tu.usuario`, `C:\Users\<usuario>`). Las salidas en bruto
  (`*.txt`, `*.log`) no se suben.

## Shell
La herramienta Bash de Claude Code en Windows suele ir por **Git Bash**, y las órdenes del plan son de PowerShell.
- Scripts: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/<script>.ps1` (barras normales:
  valen en los dos shells; con `\` Git Bash se come las barras).
- Órdenes sueltas de PowerShell (`$env:…`, `Out-File`, `Copy-Item`): `powershell.exe -NoProfile -Command "…"`.
- `bash tools/privacidad.sh` va directo desde Git Bash.

## Qué cambia respecto a las reglas de la raíz
- **Comandos:** en Windows no hay `./test.sh` ni `tools/verificar_demo.sh` (son de macOS). Lo que se usa:
  - `windows/scripts/comprobar-entorno.ps1` (entorno), `prueba-ssh.ps1` y `prueba-askpass.ps1` (paso P1).
  - `swift build --target NetDeckCore` (desde el paso P2).
  - **Tests: sólo con `windows/scripts/test.ps1`**, nunca `swift test` a secas: pone un `NETDECK_HOME` temporal como
    `./test.sh`; sin él, los tests escribirían en tu carpeta de usuario (`AppPaths.underTests` no reconoce aún el
    proceso de tests de Windows: lo arregla el paso P4f).
  - `bash tools/privacidad.sh` desde Git Bash (también busca rutas `C:\Users\…`).
- **Antes de un commit desde Windows** (aprobado por el autor el 2026-11-10 y escrito en la sección «Antes de un
  commit» de la raíz): no hay demo, porque en Windows no hay app que probar todavía. En su lugar:
  `bash tools/privacidad.sh` en verde, el núcleo compila en Windows (desde P2), los tests con `test.ps1` (desde P6) y un
  informe en `windows/ESTADO.md`. Vale sólo para `propuesta/windows` y `windows/*`. **Nada se fusiona a `main` sin que
  el autor haga en su Mac la pasada de siempre** (`./test.sh` + demo): los cambios en `Sources/` no pueden romper macOS.
- **El código de Windows no cambia el de macOS.** Lo nuevo va tras `#if os(Windows)` o detrás de un protocolo con su
  implementación de macOS intacta (paso P4). Si un cambio obliga a tocar lo que se compila en macOS (`Package.swift`,
  `Package.resolved`) o su comportamiento, para y pregunta.
- **Git:** autor `Jonay` con el correo de siempre (`git config user.name` / `user.email` locales del repo; compruébalo
  con `git config user.email` antes del primer commit y, si está vacío, pregunta al autor: no lo escribas tú). Sin
  línea de coautor. Mensajes en castellano: título corto, línea en blanco y viñetas con el porqué. Sin `--force`.
- **Fin de línea:** el repo se clona con `git clone -c core.autocrlf=false …` y `.gitattributes` fija LF. Si
  `git status` enseña archivos enteros cambiados sin motivo, es eso: `git config core.autocrlf false` y
  `git checkout -- .` (sólo si no hay trabajo tuyo sin guardar).

## Decisión pendiente
El camino para la interfaz y la terminal está en `windows/decisiones/0001-camino-para-windows.md`, en estado
**propuesta**. Los pasos P0, P1, P2 y P5 sirven para decidirlo con datos y se pueden hacer ya. A partir de P4 hay que
esperar a que el autor acepte o cambie la ADR (paso P3).

## Skills y agentes
- Las skills del proyecto están en `.agents/skills/` (en el repo). En Windows, Claude Code no las ve hasta copiarlas a
  `.claude/skills/` (paso P0 del plan; la copia queda fuera de git con `.git/info/exclude`).
- Útiles aquí: `terminal-netdeck-patterns` (mapa del núcleo y reglas aprendidas: léela antes de P4) y
  `netdeck-texto-visible` (textos con `L("…")` e inglés).
- Opcionales, si está instalado el plugin de ECC (no viene con el repo): `blueprint` (para cambiar el plan),
  `architecture-decision-records` (para nuevas decisiones), `security-review` (P9 y P10),
  `swift-protocol-di-testing` (tests sin Llavero, ssh ni red) y `windows-desktop-e2e` (pruebas de la interfaz en P8).
- Los agentes de `.claude/agents/` están escritos para macOS: `netdeck-auditor` sirve igual para revisar diffs del
  núcleo; con ECC, también `ecc:security-reviewer`, `ecc:code-reviewer` y `ecc:swift-reviewer`.
