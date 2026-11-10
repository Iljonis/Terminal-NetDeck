# Plan: Terminal NetDeck para Windows

Plan por pasos para llevar Terminal NetDeck a Windows. Cada paso se puede hacer en frío, en otra sesión, sin leer los
anteriores: trae su contexto, sus tareas, cómo se comprueba y cuándo está terminado. Se marca con `[x]` lo hecho y se
apunta en [ESTADO.md](ESTADO.md) dónde se quedó.

- **Objetivo:** una versión de Terminal NetDeck para Windows 11 con las mismas reglas de seguridad que la de macOS
  (sesiones en ssh_config, contraseñas sólo en el almacén seguro del sistema, pegado seguro, MultiExec sólo a ssh/telnet,
  actualizaciones sólo desde GitHub y verificadas).
- **Punto de partida:** la 1.0.0 de macOS (`main` en `5e62a85`). `Sources/NetDeckCore` (unas 17 000 líneas, sin
  interfaz, 705 tests) y `Sources/TerminalNetDeck` (unas 17 000, SwiftUI + AppKit + SwiftTerm). Viabilidad y fuentes:
  [ESTUDIO.md](ESTUDIO.md).
- **Esfuerzo:** S (horas) · M (1-2 días) · L (una semana o más). **Modelo:** «fuerte» para diseño y seguridad,
  «normal» para el resto.

## Invariantes (se comprueban tras cada paso)

1. macOS no cambia: en el Mac, `swift build` y `./test.sh` en verde, y la demo antes de fusionar a `main`.
2. Nada personal en el repo: `bash tools/privacidad.sh` en verde (en Windows, desde Git Bash).
3. El código de Windows va tras `#if os(Windows)` o tras un protocolo con la implementación de macOS intacta.
4. Todo texto visible con `L("…")` y su inglés en `Ingles.swift` (skill `netdeck-texto-visible`).
5. Las reglas de seguridad de la raíz valen igual en Windows; donde cambie el mecanismo (Llavero → Administrador de
   credenciales, 0600 → ACL), la regla se mantiene y se escribe aquí cómo se cumple.

## Orden y dependencias

```
P0 ─┬─ P1 (pruebas de ssh.exe) ─┐
    └─ P2 (compilar el núcleo) ─┴─ P3 (decisión: ADR 0001) ─┬─ P4a…P4h (capa de plataforma, en paralelo) ─ P6 (tests)
                                                            ├─ P5 (CI de Windows; puede empezar con P2)
                                                            └─ P7 (terminal: ConPTY) ─ P8 (interfaz) ─ P9 (seguridad)
                                                                                                     └─ P10 (paquete) ─ P11 (lanzamiento)
```

P1 y P2 van en paralelo. P4a…P4h van en paralelo entre sí porque cada uno toca archivos distintos. **P3 es una
puerta: la decide el autor.**

---

## P0 · Preparar el PC con Windows

- **Contexto:** hace falta un Windows 11 (x64 o ARM64) con las herramientas para compilar Swift y para probar el ssh
  que trae Windows. Lo hace el autor a mano; el agente sólo guía y comprueba.
- **Depende de:** nada. **Rama:** ninguna. **Esfuerzo:** S. **Modelo:** normal.
- **Tareas:**
  - [ ] Git for Windows (trae Git Bash): `winget install --id Git.Git -e`.
  - [ ] Visual Studio 2022 Build Tools con «Desarrollo para el escritorio con C++» y el SDK de Windows 11 (lo pide el
        toolchain de Swift). Sigue la guía oficial de <https://www.swift.org/install/windows/>: los componentes exactos y
        el id de winget del toolchain cambian entre versiones, así que usa los de esa página.
  - [ ] Toolchain de Swift **6.2 o posterior** (el `Package.swift` usa `swift-tools-version:6.2` y `.defaultIsolation`).
  - [ ] Cliente OpenSSH de Windows (viene de serie en Windows 11: `C:\Windows\System32\OpenSSH\ssh.exe`).
  - [ ] Opcional para P1: Cliente Telnet (característica opcional de Windows) y un equipo de laboratorio o un OpenSSH
        Server local para probar contra él.
  - [ ] Claude Code para Windows.
  - [ ] Clonar el repo, `git switch propuesta/windows`, `git config core.autocrlf false` y copiar las skills
        (ver [CLAUDE.md](CLAUDE.md#skills-y-agentes)).
- **Comprobación:** `powershell -ExecutionPolicy Bypass -File windows\scripts\comprobar-entorno.ps1` sin ✗.
- **Salida:** el script en verde; la salida, sin datos personales, en `windows/resultados/entorno.md`.
- **Marcha atrás:** no aplica.

## P1 · Probar el ssh de Windows con lo que NetDeck necesita

- **Contexto:** NetDeck no tiene un SSH propio: lanza el `ssh` del sistema (`ConnectionRoute.command`), le pasa la
  contraseña con su propio askpass (`Askpass.environment`: `SSH_ASKPASS` = el ejecutable de la app,
  `SSH_ASKPASS_REQUIRE=force`), valida el ssh_config con `ssh -G` (`SessionFile`), comparte la conexión al bastión con
  ControlMaster (`JumpSharing`) y el explorador SFTP habla el protocolo por `ssh -s … sftp` (`SFTPClient`). Antes de
  decidir nada hay que saber cuáles de estas cinco cosas hace el OpenSSH de Windows.
- **Depende de:** P0. **En paralelo con:** P2. **Rama:** `propuesta/windows` (sólo resultados). **Esfuerzo:** S-M.
  **Modelo:** normal.
- **Tareas:**
  - [ ] `windows\scripts\prueba-ssh.ps1`: versión de ssh, `ssh -G` con un `Include`, ControlMaster, telnet y sftp.
  - [ ] `windows\scripts\prueba-askpass.ps1 -Destino tu.usuario@192.0.2.10` contra un equipo de laboratorio: confirma si
        ssh llama al askpass con `SSH_ASKPASS_REQUIRE=force` y qué texto le pasa (el script registra la pregunta y
        contesta una contraseña falsa, así que la autenticación debe fallar).
  - [ ] Probar el mismo askpass **dentro de una pestaña con terminal** (ConPTY), no sólo sin terminal: en macOS la
        app lanza ssh con un pty (`OutputPipe`/`LocalProcess`) y en Windows el comportamiento puede cambiar. Basta con
        Windows Terminal: `$env:SSH_ASKPASS=…; $env:SSH_ASKPASS_REQUIRE='force'; ssh tu.usuario@192.0.2.10`.
  - [ ] Permisos: con una clave o un `config` con ACL abiertas (heredadas de la carpeta), ¿ssh se niega? Anota el
        mensaje exacto: dirá qué ACL tiene que poner `SafeFile` en P4f.
  - [ ] Apuntar todo en `windows/resultados/ssh-windows.md` con una tabla «función · funciona · notas».
- **Comprobación:** la tabla tiene las cinco funciones (askpass sin terminal, askpass con terminal, `ssh -G` con
  `Include`, ControlMaster, `ssh -s sftp`) más telnet y permisos, cada una con sí/no y la salida que lo demuestra.
- **Salida:** tabla completa y conclusión en [ESTADO.md](ESTADO.md). Si el askpass **no** funciona, se anota en la
  ADR 0001: obliga a escribir la contraseña desde la propia pestaña (como hace ya el autopass de macOS al ver el
  prompt) o a llevar un SSH propio.
- **Marcha atrás:** no aplica (sólo se mide).

## P2 · Compilar NetDeckCore en Windows (sólo medir)

- **Contexto:** el núcleo usa sobre todo Foundation, pero también `Darwin` (posix_spawn, termios, kill/waitpid),
  `CryptoKit`, `Security`, `Network` (FTP), `CoreText` y `CoreGraphics`. La lista por archivo está en
  [ESTUDIO.md](ESTUDIO.md#qué-hay-que-reescribir-en-el-núcleo). Hay que saber cuántos errores salen de verdad antes de
  decidir el camino.
- **Depende de:** P0. **En paralelo con:** P1. **Rama:** `windows/p2-medir` (desechable). **Esfuerzo:** S-M.
  **Modelo:** normal.
- **Tareas:**
  - [ ] `swift build --target NetDeckCore 2>&1 | Tee-Object windows\resultados\compilacion-0.txt` sin tocar nada.
  - [ ] Agrupar los errores por archivo y por causa (módulo que falta, API de Darwin, Foundation distinta) en
        `windows/resultados/compilacion.md`.
  - [ ] Medir cuánto compila sin lo de plataforma: en la rama desechable, envolver en `#if !os(Windows)` los archivos
        con dependencias de plataforma y volver a compilar. Cuenta lo que queda y si alguna parte «pura» (resaltado,
        `SafePaster`, `SessionFile`, `SFTPPacket`, temas) falla por Foundation de Windows.
  - [ ] Igual con SwiftTerm: `swift build --product SwiftTerm` o un paquete de prueba que dependa sólo del motor
        (`Terminal` sin vista). Lo usan los tests (`BuferIncrementalTests`) y podría servir de motor en P7.
- **Comprobación:** `windows/resultados/compilacion.md` con el número de errores por archivo antes y después del
  `#if`, y si el motor de SwiftTerm compila.
- **Salida:** los números en [ESTADO.md](ESTADO.md) y en la ADR 0001 (sección «Datos»). **La rama `windows/p2-medir` no se
  fusiona:** los cambios buenos se rehacen en P4.
- **Marcha atrás:** borrar la rama.

## P3 · Decidir el camino (puerta del autor)

- **Contexto:** hay tres caminos (ver [decisiones/0001](decisiones/0001-camino-para-windows.md)): A) Swift en Windows
  con interfaz WinUI 3 (como Arc), B) app aparte con Tauri + xterm.js (como Tabby y Termius, pero sin Electron) que
  porta el núcleo con los tests como especificación, C) núcleo en Swift como DLL con interfaz en .NET. La propuesta
  recomienda **A, si P2 sale bien; B, si no**.
- **Depende de:** P1 y P2. **Esfuerzo:** S. **Modelo:** fuerte (para preparar el resumen).
- **Tareas:**
  - [ ] Completar la sección «Datos» de la ADR 0001 con los resultados de P1 y P2.
  - [ ] El autor elige y la ADR pasa a `aceptada` (o se escribe una nueva que la sustituya).
  - [ ] Si se elige B o C, reescribir P4-P8 con la skill `blueprint` antes de seguir.
- **Salida:** ADR 0001 `aceptada`. **Sin esto no se empieza P7 ni P8.**

## P4 · Capa de plataforma en el núcleo

- **Contexto común:** con el camino A (o C), el núcleo tiene que compilar y funcionar en Windows **sin cambiar nada en
  macOS**. Cada subpaso aísla una dependencia detrás de `#if os(Windows)` o de un protocolo pequeño, con la
  implementación de macOS tal cual. Antes de empezar, lee la skill `terminal-netdeck-patterns` (archivos que cambian
  juntos y regresiones conocidas) y, para los tests, `swift-protocol-di-testing`. Cada subpaso es **un PR** contra
  `propuesta/windows`, en su rama `windows/p4x-…`.
- **Depende de:** P3 (camino A o C). **En paralelo:** P4a…P4h entre sí (archivos distintos). **Esfuerzo total:** L.
- **Comprobación de cada subpaso:** en Windows, `swift build --target NetDeckCore` con menos errores que antes y los
  tests nuevos en verde; en el Mac (el autor), `./test.sh` en verde. Revisión con `netdeck-auditor` o
  `ecc:swift-reviewer` antes de fusionar.
- **Marcha atrás:** cada subpaso es un PR aparte; se revierte sin afectar a los demás.

### P4a · Procesos hijos (M, fuerte)
- `Remote/ChildProcess.swift`, `Sessions/Tunnels.swift`, `Security/KnownHosts.swift`, `Sessions/SessionFile.swift`.
- [ ] Sustituir `posix_spawn` + `setsid` + `killpg` por `CreateProcessW` con un **Job Object** (para que al cerrar
      se mueran también los hijos, como hace hoy el grupo de procesos) o por `Foundation.Process` si basta.
- [ ] `DispatchSourceProcess` no existe en Windows: esperar el fin con `WaitForSingleObject` en un hilo.
- [ ] Regla que no cambia: sólo se heredan stdin/stdout/stderr (`bInheritHandles` con `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`).

### P4b · Rutas de los programas del sistema (S, normal)
- `Sessions/ConnectionRoute.swift`, `Sessions/JumpSharing.swift`, `Security/KnownHosts.swift`, `Sessions/Tunnels.swift`.
- [ ] Un sitio único para `ssh`, `sftp`, `ssh-keygen`, `telnet` y la shell local: en Windows,
      `%SystemRoot%\System32\OpenSSH\ssh.exe` etc. (nunca buscarlos por el `PATH`: es la misma regla que las rutas fijas
      de macOS), y PowerShell o `cmd.exe` en lugar de `/bin/zsh` y `/etc/shells`.
- [ ] `launchProblem`: «No está ssh.exe en este PC», con su `L("…")` e inglés.

### P4c · Compartir el salto (M, fuerte)
- `Sessions/JumpSharing.swift`, `Sessions/ConnectionRoute.swift` (`jumpOptions`).
- [ ] Si P1 confirma que no hay ControlMaster, `JumpSharing.standard()` devuelve `nil` en Windows (ya es el camino de
      «se conecta como siempre, sin compartir») y se dice en la interfaz que en Windows cada pestaña entra en el bastión.
- [ ] Anotar en la ADR la alternativa para más adelante (un único ssh al bastión con `-W` por pestaña, o un SSH propio).

### P4d · Credenciales (M, fuerte, `security-review`)
- `Security/KeychainStore.swift` y quien lo use (`CredentialPolicy`, `CredentialLedger`, `Askpass`).
- [ ] Implementación con el **Administrador de credenciales** (`CredWriteW` / `CredReadW` / `CredDeleteW`, tipo
      `CRED_TYPE_GENERIC`, persistencia `LOCAL_MACHINE`), con el mismo nombre de servicio y cuenta que en macOS.
- [ ] Reglas que no cambian: el secreto nunca en argumentos ni en `DebugLog`; las lecturas, fuera del hilo principal.
- [ ] `CredentialLedger` usa `kill(pid, 0)` para saber si un proceso vive: en Windows, `OpenProcess` +
      `GetExitCodeProcess`. El bloqueo de 15 min y sus casos (raíz, «Contraseñas») no cambian.

### P4e · Askpass (M, fuerte)
- `Security/Askpass.swift`.
- [ ] Según P1: si `SSH_ASKPASS` funciona, el mismo ejecutable hace de askpass igual que en macOS (`NETDECK_ASKPASS=1`).
- [ ] La lectura de respaldo por `/dev/tty` y `tcgetattr` pasa a `CONIN$` con `SetConsoleMode` (sin eco).
- [ ] `purgeStates` usa `kill(pid, 0)`: lo mismo que en P4d.

### P4f · Archivos del usuario y permisos (M, fuerte)
- `Support/SafeFile.swift`, `Support/AppPaths.swift`, `Support/DataBackup.swift`, `Terminal/SessionLog.swift`.
- [ ] El «0600 / 0700» de `SafeFile` y `AppPaths.ensure` pasa a una ACL con sólo el usuario actual (y SYSTEM), sin
      herencia. Es lo que pide el OpenSSH de Windows para `config` y claves (mensaje exacto en P1).
- [ ] Rutas: `AppPaths` en `%APPDATA%\Terminal NetDeck`; el `Include` en `%USERPROFILE%\.ssh\config`;
      `AppPaths.tilde` enseña `%USERPROFILE%` como `~`.
- [ ] Escritura atómica: `ReplaceFileW` (el rename sobre un archivo existente no es atómico igual que en APFS).

### P4g · Puerto serie (M, normal)
- `Sessions/SerialPort.swift`, `Sessions/SerialLine.swift`.
- [ ] `\\.\COMn` con `CreateFileW`, `SetCommState` (velocidad, bits, paridad, parada, control de flujo) y
      `SetCommTimeouts`; la lista de puertos, del registro (`HARDWARE\DEVICEMAP\SERIALCOMM`).
- [ ] Los textos de error («¿está conectado el adaptador USB-serie?») valen igual.

### P4h · Cripto, red, fuentes y ventanas (M, normal)
- `CryptoKit` (`CredentialLedger`, `JumpSharing`, `UpdateCheck`, `Transfer`) → **swift-crypto** (misma API,
  `import Crypto`): añadirlo a `Package.swift` sólo para Windows (`.when(platforms: [.windows])`).
- `Remote/FTPClient.swift` (`Network.framework`) → sockets de Foundation o una conexión TCP propia con Winsock, con la
  misma máquina de estados de FTP.
- `Terminal/TerminalFont.swift` (`CoreText`) y `Sessions/OpenWindows.swift` (`CoreGraphics`): tras `#if canImport`,
  con el equivalente que pida la interfaz en P8.
- `UserDefaults` (idioma, historial): funciona en Windows, pero comprobar dónde guarda y que el askpass lo lee igual.

## P5 · CI de Windows (S, normal)

- **Contexto:** hoy `.github/workflows/tests.yml` sólo corre en `macos-26`. Hay un borrador en
  [ci/windows-nucleo.yml](ci/windows-nucleo.yml) que compila el núcleo en `windows-latest`.
- **Depende de:** P2 (puede activarse en cuanto haya algo que compilar). **Rama:** `windows/p5-ci`.
- **Tareas:**
  - [ ] Revisar y fijar las versiones del borrador (acción de instalación de Swift y toolchain) y copiarlo a
        `.github/workflows/windows.yml`. Al principio, con `continue-on-error: true` para no poner en rojo los PR
        de macOS; se quita cuando P4 termine.
  - [ ] Que corra `bash tools/privacidad.sh` también en Windows.
- **Salida:** la CI de Windows corre en cada PR de `propuesta/windows` y su resultado se apunta en ESTADO.md.

## P6 · Tests del núcleo en Windows (M, normal)

- **Contexto:** `Tests/NetDeckCoreTests` tiene 705 tests (Swift Testing). Unos 23 archivos lanzan programas del sistema
  o usan rutas de macOS.
- **Depende de:** P4 (al menos P4a, P4b y P4f). **Rama:** `windows/p6-tests`.
- **Tareas:**
  - [ ] `swift test` en Windows y lista de los que fallan, por causa.
  - [ ] Los que dependen de macOS de verdad: `@Test(.enabled(if: …))` o `#if os(macOS)`, nunca borrarlos.
  - [ ] Tests nuevos para lo de Windows (ACL, Administrador de credenciales con un servicio de prueba, Job Objects).
  - [ ] Activar `swift test` en la CI de Windows (P5).
- **Salida:** `swift test` en verde en Windows y en macOS.

## P7 · Terminal en Windows: ConPTY (L, fuerte)

- **Contexto:** en macOS la pestaña es una vista de SwiftTerm con un pty (`LocalProcess`/`forkpty`) donde corre
  `/usr/bin/ssh`; el autopass, el resaltado, el pegado seguro y el Esc leen y escriben ese flujo. En Windows, el
  equivalente del pty es **ConPTY** (`CreatePseudoConsole`). Con el camino A, el motor puede ser el de SwiftTerm sin
  vista (si P2 confirma que compila) y la vista se dibuja aparte.
- **Depende de:** P3, P4a, P4b. **Rama:** `windows/p7-conpty`.
- **Tareas:**
  - [ ] Prototipo de consola (sin interfaz): lanzar `ssh.exe` dentro de una ConPTY, leer su salida, escribir la
        entrada y cambiar el tamaño (`ResizePseudoConsole`).
  - [ ] Conectar esa salida al motor de terminal y comprobar con el búfer (como `BuferIncrementalTests`) que un
        `show run` con paginador se lee bien.
  - [ ] Probar el autopass y la detección de prompts (`PasswordPrompt`, `CredentialPolicy`) con ese flujo.
  - [ ] Ojo: ConPTY reinterpreta algunas secuencias VT. Probar colores de 256 y 24 bits, el ratón y el título.
- **Salida:** un ssh a un equipo de laboratorio, con contraseña automática, desde el prototipo.

## P8 · Interfaz para Windows (L, fuerte)

- **Contexto:** la interfaz de macOS (`Sources/TerminalNetDeck`, unas 17 000 líneas) no se puede llevar: SwiftUI y
  AppKit no existen en Windows. Con el camino A se hace en WinUI 3 con swift-winrt (como Arc); con B o C, en la
  tecnología de la ADR. Se rehace en este orden, cada punto en un PR: ventana con pestañas y terminal (P7) →
  barra lateral de sesiones (lee el ssh_config de `SessionManager`) → editor de sesión → explorador SFTP/FTP →
  Ajustes → temas (85, con Mica en lugar de Liquid Glass) → menús y atajos → botones, MultiExec y pegado seguro →
  túneles → asistente de inicio.
- **Depende de:** P3, P7. **Rama:** `windows/p8-<parte>`.
- **Reglas que no cambian:** un estado común (`AppCore`) y uno por ventana (`AppModel`); todo texto con `L("…")`;
  los avisos sólo para los mensajes que empiezan por ✗ 🔑 ⎋ ⬆; rutas con `AppPaths.tilde`.
- **Comprobación:** con datos de demo (equivalente de `tools/demo` en un `NETDECK_HOME` temporal, **nunca** con datos
  reales) y la skill `windows-desktop-e2e` para las pruebas de la interfaz.

## P9 · Seguridad en Windows (M, fuerte)

- **Depende de:** P4, P8. **Rama:** `windows/p9-seguridad`.
- **Tareas (skill `security-review` y agente `ecc:security-reviewer`):**
  - [ ] `SessionImporter.safeExtra` sigue quitando las opciones que ejecutan órdenes; comprobar también las rutas de
        Windows (`ProxyCommand C:\…`, `LocalCommand`, `KnownHostsCommand`).
  - [ ] Nombres, equipos y usuarios que empiezan por `-` se siguen rechazando. Ojo con `/`: en Windows algunos
        programas lo leen como opción.
  - [ ] A ssh sólo le llega `LC_CTYPE=C.UTF-8` (`TerminalEnvironment`): comprobar que en Windows no se cuela el
        entorno entero.
  - [ ] Credenciales, askpass y bloqueo de 15 min: las mismas pruebas que en macOS.
- **Salida:** informe sin hallazgos graves abiertos.

## P10 · Paquete, firma y actualizaciones (M-L, fuerte)

- **Contexto:** en macOS hay un `.dmg` que se comprueba con sha256, id, versión y `codesign --verify`, y nada se
  instala sin el clic en «Actualizar ahora». En Windows hay que hacer lo mismo.
- **Depende de:** P8. **Rama:** `windows/p10-paquete`.
- **Tareas:**
  - [ ] Paquete MSIX o instalador (decidirlo con una ADR nueva) y su workflow de Release en `windows-latest`.
  - [ ] **Firma Authenticode**: sin certificado, SmartScreen avisa al instalar. Opciones: certificado de firma de código
        o un servicio de firma en la nube. Coste y decisión del autor.
  - [ ] Actualizador: sólo enlaces https de github.com, sha256, id y versión, y firma verificada con
        `WinVerifyTrust` antes de instalar; nada sin el clic del usuario.
  - [ ] Opcional: manifiesto de winget.
- **Salida:** un instalador firmado que se instala en un Windows limpio y se actualiza desde una Release de prueba.

## P11 · Documentación y lanzamiento (M, normal)

- **Depende de:** P9, P10.
- **Tareas:**
  - [ ] README y README.en: quitar «no tiene versión para Windows», requisitos e instalación en Windows, capturas.
  - [ ] CHANGELOG, `docs/agentes/` (comandos y arquitectura de Windows) y la raíz CLAUDE.md / AGENTS.md.
  - [ ] Release con la skill `netdeck-publicar`, adaptada a dos sistemas.

---

## Cómo cambiar este plan
Con la skill `blueprint`: partir un paso, añadir uno o saltarlo, siempre dejando en [ESTADO.md](ESTADO.md) el
motivo. Si una decisión cambia el camino, una ADR nueva en `decisiones/` que diga a cuál sustituye.
