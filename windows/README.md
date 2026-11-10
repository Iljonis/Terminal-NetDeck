# Terminal NetDeck para Windows (propuesta)

Esta carpeta es una **propuesta**: todavía no hay versión para Windows. Recoge el estudio de viabilidad, cómo lo hacen
otras apps (SecureCRT, Royal TS/TSX, Arc, Warp, Termius, Tabby), la decisión de arquitectura pendiente y el plan por
fases para hacerlo. Está pensada para seguir el trabajo desde un PC con Windows y Claude Code (o Codex).

| Archivo | Qué es |
|---|---|
| [CLAUDE.md](CLAUDE.md) · [AGENTS.md](AGENTS.md) | Instrucciones para el agente que siga el trabajo en Windows (las dos iguales) |
| [PLAN.md](PLAN.md) | El plan por pasos (P0…P11), cada uno con contexto, tareas, comprobación y criterio de salida |
| [ESTADO.md](ESTADO.md) | Dónde se quedó el trabajo: cada sesión lo actualiza al terminar |
| [ESTUDIO.md](ESTUDIO.md) | Viabilidad: qué se aprovecha del núcleo, qué hay que reescribir y qué hacen otros, con fuentes |
| [decisiones/](decisiones/README.md) | Decisiones de arquitectura (ADR); la 0001, qué camino seguir, está «propuesta» |
| [scripts/](scripts/) | PowerShell para comprobar el entorno, probar el ssh de Windows (askpass, `ssh -G`, `-J`, sftp) y pasar los tests con un `NETDECK_HOME` temporal (`test.ps1`) |
| [ci/windows-nucleo.yml](ci/windows-nucleo.yml) | Borrador de GitHub Actions para compilar el núcleo en Windows (sin activar) |
| [resultados/](resultados/) | Lo que salga de las pruebas en Windows (lo rellenan los pasos P1 y P2) |

## Empezar en Windows

1. Instala Git for Windows, el toolchain de Swift para Windows y Claude Code (detalle en [PLAN.md, paso P0](PLAN.md#p0--preparar-el-pc-con-windows)).
2. Clona el repositorio **sin conversión de fin de línea** y cámbiate a la rama de la propuesta:

   ```powershell
   git clone -c core.autocrlf=false https://github.com/Iljonis/Terminal-NetDeck.git
   cd Terminal-NetDeck
   git switch propuesta/windows
   ```

3. Comprueba el entorno:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/comprobar-entorno.ps1
   ```

4. Abre Claude Code en la raíz del repositorio (no dentro de `windows\`) y dile:

   > Continúa con el plan de Windows: lee windows/CLAUDE.md y windows/ESTADO.md y sigue por el siguiente paso.

Nada de esta carpeta cambia la app de macOS: el código de `Sources/` sigue igual hasta el paso P4.
