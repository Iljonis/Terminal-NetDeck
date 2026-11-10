# Terminal NetDeck en Windows: instrucciones para el agente

Este archivo y `windows/AGENTS.md` (Codex) son el mismo: si cambias uno, cambia el otro. Las reglas de la raíz
(`CLAUDE.md` / `AGENTS.md`) siguen valiendo todas; aquí sólo va lo que cambia o se añade al trabajar desde Windows.

## Al empezar cada sesión
1. Lee `windows/ESTADO.md` (dónde se quedó) y el paso que toque de `windows/PLAN.md`. No hace falta leer el resto del
   plan: cada paso trae su propio contexto.
2. Comprueba la rama: el trabajo de Windows va en `propuesta/windows` o en ramas que salen de ella
   (`windows/p4-proceso`, `windows/p7-conpty`…). **Nunca** directamente en `main`.
3. `git pull` antes de tocar nada: el autor también trabaja desde un Mac.

## Al terminar cada sesión
- Marca en `windows/PLAN.md` las tareas hechas (`[x]`) y escribe en `windows/ESTADO.md` qué has hecho, qué falta, qué
  ha fallado y cuál es el siguiente paso. Así la próxima sesión, en Windows o en el Mac, sigue sin repetir nada.
- Los resultados de pruebas (salidas de `ssh -V`, errores de compilación, etc.) van a `windows/resultados/`, **sin
  datos reales**: nada de IPs, equipos, usuarios ni rutas tuyas (se ponen `192.0.2.x`, `core-01`, `bastion`,
  `tu.usuario`, `C:\Users\<usuario>`).

## Qué cambia respecto a las reglas de la raíz
- **Comandos:** en Windows no hay `./test.sh` ni `tools/verificar_demo.sh` (son de macOS). Lo que se usa:
  - `powershell -ExecutionPolicy Bypass -File windows\scripts\comprobar-entorno.ps1`
  - `swift build --target NetDeckCore` (desde el paso P2) y `swift test` cuando el paso P6 lo permita.
  - `tools/privacidad.sh` sí funciona desde **Git Bash** (viene con Git for Windows): `bash tools/privacidad.sh`.
- **Antes de un commit desde Windows** (regla provisional hasta que el autor diga otra cosa): no hay demo, porque la
  app de Windows aún no existe. En su lugar: `bash tools/privacidad.sh` en verde, el núcleo compila en Windows (desde
  P2) y un informe al autor en `windows/ESTADO.md`. **Nada se fusiona a `main` sin que el autor haga en su Mac la
  pasada de siempre** (`./test.sh` + `tools/verificar_demo.sh`): los cambios en `Sources/` no pueden romper macOS.
- **El código de Windows no cambia el de macOS.** Lo nuevo va tras `#if os(Windows)` o detrás de un protocolo con su
  implementación de macOS intacta (paso P4). Si un cambio obliga a tocar el comportamiento en macOS, para y pregunta.
- **Git:** autor `Jonay` con el correo de siempre (`git config user.name` / `user.email` locales del repo; compruébalo
  con `git config user.email` antes del primer commit y, si está vacío, pregunta al autor: no lo escribas tú). Sin
  línea de coautor. Mensajes en castellano: título corto, línea en blanco y viñetas con el porqué. Sin `--force`.
- **Fin de línea:** Windows tiende a meter CRLF. Antes del primer commit, `git config core.autocrlf false` en este
  repositorio y comprueba con `git diff --stat` que no cambian archivos enteros por los saltos de línea.

## Decisión pendiente
El camino para la interfaz y la terminal está en `windows/decisiones/0001-camino-para-windows.md`, en estado
**propuesta**. Los pasos P0, P1 y P2 sirven para decidirlo con datos y se pueden hacer ya. A partir de P3 hay que
esperar a que el autor acepte o cambie la ADR: no empieces P7 ni P8 sin eso.

## Skills y agentes
- Las skills del proyecto están en `.agents/skills/` (en el repo). En Windows, Claude Code no las ve en
  `.claude/skills/` (esa carpeta no se sube), así que cópialas la primera vez:
  `New-Item -ItemType Directory -Force .claude\skills; Copy-Item -Recurse -Force .agents\skills\* .claude\skills\`
- Útiles aquí: `terminal-netdeck-patterns` (mapa del núcleo y reglas aprendidas: léela antes de P4),
  `netdeck-texto-visible` (textos con `L("…")` e inglés), y de ECC `blueprint` (para cambiar el plan),
  `architecture-decision-records` (para nuevas decisiones), `security-review` (pasos P9 y P10),
  `swift-protocol-di-testing` (tests sin Llavero, ssh ni red) y `windows-desktop-e2e` (pruebas de la interfaz en P8).
- Los agentes de `.claude/agents/` están escritos para macOS: `netdeck-auditor` y los de ECC (`ecc:security-reviewer`,
  `ecc:code-reviewer`, `ecc:swift-reviewer`) sirven igual para revisar diffs del núcleo.
