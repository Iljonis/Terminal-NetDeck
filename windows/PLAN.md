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

## Convenciones

- **Shell:** las órdenes de este plan son de **PowerShell**. Desde Git Bash (la herramienta Bash de Claude Code en
  Windows suele ir por Git Bash), los scripts se lanzan así, con barras normales, que valen en los dos:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/<script>.ps1`.
- **Ramas:** el trabajo va en `propuesta/windows`; cada paso grande, en `windows/pN-<tema>` (por ejemplo
  `windows/p4a-procesos`) con un PR contra `propuesta/windows`. Los resultados de las pruebas (P0-P2) se suben a
  `propuesta/windows`, no a ramas desechables. Borrar una rama ya subida, sólo con el OK del autor.
- **Tests:** nunca `swift test` a secas en Windows: `windows/scripts/test.ps1` (pone un `NETDECK_HOME` temporal, como
  `./test.sh` en macOS; sin él, los tests escribirían en tu carpeta de usuario).
- **Resultados sin datos tuyos:** los scripts ya cambian tu carpeta de usuario por `C:\Users\<usuario>` y el destino por
  `<destino>`. Las salidas en bruto (`*.txt`, `*.log` de `windows/resultados/`) no se suben (`.gitignore`); al repo
  van sólo los `.md` resumidos. Antes de cada commit, `bash tools/privacidad.sh` (también busca rutas `C:\Users\…`).

## Invariantes (se comprueban tras cada paso)

1. macOS no cambia: en el Mac, `swift build` y `./test.sh` en verde, y la demo antes de fusionar a `main`. Si un
   paso obliga a tocar algo que se compila en macOS (`Package.swift`, `Package.resolved`), se dice en el PR y lo
   aprueba el autor.
2. Nada personal en el repo: `bash tools/privacidad.sh` en verde (en Windows, desde Git Bash).
3. El código de Windows va tras `#if os(Windows)` o tras un protocolo con la implementación de macOS intacta.
4. Todo texto visible con `L("…")` y su inglés en `Ingles.swift` (skill `netdeck-texto-visible`).
5. Las reglas de seguridad de la raíz valen igual en Windows; donde cambie el mecanismo (Llavero → Administrador de
   credenciales, 0600 → ACL), la regla se mantiene y se escribe aquí cómo se cumple.

## Orden y dependencias

```
P0 ─┬─ P1 (pruebas de ssh.exe) ───────┐
    └─ P2 (compilar el núcleo) ─┬─────┴─ P3 (decisión: ADR 0001, la toma el autor)
                                └─ P5 (CI de Windows, puede empezar ya)
P3 ─ P4.0 (manifiesto y cripto) ─ P4a (procesos) ─┬─ P4b (rutas) ─ P4c (salto compartido)
                                                  ├─ P4d (credenciales) ─ P4e (askpass)
                                                  ├─ P4f (archivos y permisos)
                                                  ├─ P4g (puerto serie)
                                                  └─ P4h (red y archivos de bajo nivel)
P4a + P4b + P4f ─ P6 (tests en Windows)
P3 + P4a + P4b ─ P7 (terminal: ConPTY) ─ P8 (interfaz) ─┬─ P9 (seguridad) ─┐
                                                        └─ P10 (paquete) ──┴─ P11 (lanzamiento)
```

**P3 es una puerta: la decide el autor.** Tras P4a, las cinco ramas de P4 pueden ir en paralelo; las que comparten un
archivo lo dicen en su apartado («comparte con…»): la segunda en fusionarse rebasa sobre la primera.

---

## P0 · Preparar el PC con Windows

- **Contexto:** hace falta un Windows 11 (x64 o ARM64) con las herramientas para compilar Swift y para probar el ssh
  que trae Windows. Lo hace el autor a mano; el agente sólo guía y comprueba.
- **Depende de:** nada. **Rama:** ninguna. **Esfuerzo:** S. **Modelo:** normal.
- **Tareas:**
  - [x] Git for Windows (trae Git Bash): `winget install --id Git.Git -e`. *(DevKitPro/MSYS2 git 2.49.0 + Git Bash de Git for Windows)*
  - [x] Visual Studio Build Tools (2022 o posterior) con «Desarrollo para el escritorio con C++» y el SDK de Windows 11
        (lo pide el toolchain de Swift). Sigue la guía oficial de <https://www.swift.org/install/windows/>: los
        componentes exactos y el id de winget del toolchain cambian entre versiones, así que usa los de esa página. *(Visual Studio Community 2022 ✓)*
  - [x] Toolchain de Swift **6.2 o posterior** (el `Package.swift` usa `swift-tools-version:6.2` y `.defaultIsolation`). *(Swift 6.4.2 ✓)*
  - [x] Cliente OpenSSH de Windows (viene de serie en Windows 11: `C:\Windows\System32\OpenSSH\ssh.exe`). *(OpenSSH_for_Windows_9.5p2 ✓)*
  - [x] Opcional para P1: Cliente Telnet (característica opcional de Windows) y un equipo de laboratorio (o un OpenSSH
        Server local) con dos cuentas de prueba, una por clave y otra por contraseña, y si puede ser un bastión. *(Telnet ✓)*
  - [x] Claude Code para Windows y, si se quieren las skills de ECC que cita este plan (`blueprint`,
        `architecture-decision-records`, `swift-protocol-di-testing`, `windows-desktop-e2e`), el plugin de ECC. Son
        opcionales: el plan se puede seguir sin ellas. *(Claude Code ✓)*
  - [x] Clonar **sin conversión de fin de línea** (si no, los `.sh` salen con CRLF y `tools/privacidad.sh` falla):

    ```powershell
    git clone -c core.autocrlf=false https://github.com/Iljonis/Terminal-NetDeck.git
    cd Terminal-NetDeck
    git switch propuesta/windows
    ```

  - [x] Copiar las skills del proyecto y que git no las vea (en el Mac las oculta el `.gitignore` global del autor):

    ```powershell
    New-Item -ItemType Directory -Force .claude\skills | Out-Null
    Copy-Item -Recurse -Force .agents\skills\* .claude\skills\
    Add-Content .git\info\exclude ".claude/skills/"
    ```

- **Comprobación:** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/comprobar-entorno.ps1`
  sin ✗ (sale con el número de fallos).
- **Salida:** el script en verde; su salida en `windows/resultados/entorno.md`.
- **Marcha atrás:** no aplica.

## P1 · Probar el ssh de Windows con lo que NetDeck necesita

- **Contexto:** NetDeck no tiene un SSH propio: lanza el `ssh` del sistema (`ConnectionRoute.command`), le pasa la
  contraseña con su propio askpass (`Askpass.environment`: `SSH_ASKPASS` = el ejecutable de la app,
  `SSH_ASKPASS_REQUIRE=force`), valida el ssh_config con `ssh -G` (`SessionFile`), escribe en `~/.ssh/config` la línea
  `Include ~/.config/netdeck/ssh_config` (`SessionFile.includeLine`), salta por bastiones con `-J`
  (`ConnectionRoute.jumpOptions`), comparte la conexión al bastión con ControlMaster (`JumpSharing`) y el explorador
  SFTP habla el protocolo por `ssh -s … sftp` (`SFTPClient`). Antes de decidir nada hay que saber cuáles de estas
  cosas hace el OpenSSH de Windows.
- **Depende de:** P0. **En paralelo con:** P2. **Rama:** `propuesta/windows` (sólo resultados). **Esfuerzo:** S-M.
  **Modelo:** normal.
- **Tareas:**
  - [ ] `windows/scripts/prueba-ssh.ps1` (sin destino): versión, `ssh -G` con `Include` absoluto, con `~/` y relativo,
        rutas con espacios, opciones fijas de NetDeck, permisos (afloja la ACL de un archivo temporal y mira si ssh se
        queja), sftp.exe y telnet.
  - [ ] `prueba-ssh.ps1 -Destino tu.usuario@192.0.2.10 [-Salto tu.usuario@192.0.2.1]` con una cuenta que entre por
        clave o agente: ControlMaster, `-J` y el subsistema sftp.
  - [ ] `windows/scripts/prueba-askpass.ps1 -Destino tu.usuario@192.0.2.10 -Conservar` con la cuenta por contraseña:
        si ssh llama al askpass con `SSH_ASKPASS_REQUIRE=force`, con consola y **sin consola** (proceso sin ventana,
        como lanzaría ssh una app con interfaz). Contesta una contraseña falsa: la autenticación tiene que fallar.
  - [ ] Con el askpass conservado, la misma prueba **dentro de Windows Terminal** (ConPTY, como una pestaña): el script
        imprime al final las órdenes exactas. Y otra con `-J` hacia el bastión: el askpass tiene que llegar también al
        ssh hijo del salto.
  - [ ] telnet.exe dentro de Windows Terminal: anota si se comporta como un flujo VT normal (es un cliente de consola
        interactivo; lo que salga condiciona las pestañas telnet en P7).
  - [ ] Todo en `windows/resultados/ssh-windows.md` con la tabla «función · funciona · notas» que imprimen los scripts.
- **Comprobación:** la tabla tiene: askpass con consola, sin consola y en Windows Terminal; askpass a través de `-J`;
  `ssh -G` con `Include` (absoluto, `~/`, relativo); permisos; ControlMaster; `-J`; `ssh -s sftp`; telnet. Cada fila con
  sí/no y la salida que lo demuestra.
- **Salida:** tabla completa y conclusión en [ESTADO.md](ESTADO.md) y en la sección «Datos» de la ADR 0001. Si el
  askpass **no** funciona, se anota en la ADR: obliga a escribir la contraseña desde la propia pestaña (como hace ya el
  autopass de macOS al ver el prompt) o a llevar un SSH propio.
- **Marcha atrás:** no aplica (sólo se mide).

## P2 · Compilar NetDeckCore en Windows (sólo medir)

- **Contexto:** el núcleo usa sobre todo Foundation, pero también `Darwin` (posix_spawn, termios, kill/waitpid, flock,
  getppid, sockets BSD), `CryptoKit`, `Security`, `Network` (FTP), `CoreText` y `CoreGraphics`. La lista por archivo
  está en [ESTUDIO.md](ESTUDIO.md#qué-hay-que-reescribir-en-el-núcleo). Hay que saber cuántos errores salen de verdad
  antes de decidir el camino.
- **Depende de:** P0. **En paralelo con:** P1. **Rama:** `windows/p2-medir` (desechable; sus resultados se suben a
  `propuesta/windows`). **Esfuerzo:** S-M. **Modelo:** normal.
- **Tareas:**
  - [x] Sin tocar nada (en PowerShell):
        `swift build --target NetDeckCore 2>&1 | Out-File -Encoding utf8 windows/resultados/compilacion-0.txt`
        (el `.txt` no se sube: lleva rutas tuyas).
  - [x] Clasificar cada error en: módulo que falta (`import Darwin`, `CryptoKit`…), símbolo POSIX que falta, diferencia
        de Foundation, o **cascada** (un tipo que no existe porque otro archivo no compila). Resumen por archivo y por
        causa, con las rutas cambiadas por `Sources/…`, en `windows/resultados/compilacion.md`.
  - [x] Segunda medida en la rama desechable: se envolvieron los 12 archivos con `#if !os(Windows)` (en lugar de
        stubs individuales): 6 archivos adicionales fallan por cascada, confirmando las predicciones del plan.
        Las partes «puras» (resaltado, `SafePaster`, `SessionFile`, `SFTPPacket`, temas) compilan sin errores.
        `FileManager.replaceItemAt` no implementado en Windows (aviso en `Macros.swift`): a resolver en P4.
  - [ ] Igual con SwiftTerm: un paquete de prueba fuera del repo que dependa sólo del motor (`Terminal` sin vista). Lo
        usan los tests (`BuferIncrementalTests`) y podría servir de motor en P7.
- **Comprobación:** `windows/resultados/compilacion.md` con errores por archivo y causa, antes y después de los stubs, y
  si el motor de SwiftTerm compila.
- **Salida:** los números en [ESTADO.md](ESTADO.md) y en la ADR 0001 (sección «Datos»), que tiene un umbral medible
  para elegir entre A y B. **La rama `windows/p2-medir` no se fusiona:** los cambios buenos se rehacen en P4.
- **Marcha atrás:** dejar la rama sin usar (borrarla del remoto, sólo con el OK del autor).

## P3 · Decidir el camino (puerta del autor)

- **Contexto:** hay tres caminos (ver [decisiones/0001](decisiones/0001-camino-para-windows.md)): A) Swift en Windows
  con interfaz WinUI 3 (como Arc), B) app aparte con Tauri + xterm.js que porta el núcleo con los tests como
  especificación, C) núcleo en Swift como DLL con interfaz en .NET. La propuesta recomienda **A, si P2 sale bien; B, si
  no**.
- **Depende de:** P1 y P2. **Esfuerzo:** S. **Modelo:** fuerte (para preparar el resumen).
- **Tareas:**
  - [x] Completar la sección «Datos» de la ADR 0001 con los resultados de P1 y P2.
        *(P2 completo; P1 pendiente de equipo de laboratorio. No cambia la elección A/B.)*
  - [x] El autor elige y la ADR pasa a `aceptada` (o se escribe una nueva que la sustituya).
        *(Camino A elegido con datos de P2: umbral cumplido.)*
  - [x] Si se elige B o C, reescribir P4-P8 con la skill `blueprint` (o a mano) antes de seguir.
        *(No aplica: se elige A.)*
- **Salida:** ADR 0001 `aceptada`. **Sin esto no se empieza P4, P7 ni P8.**

## P4 · Capa de plataforma en el núcleo

- **Contexto común:** con el camino A (o C), el núcleo tiene que compilar y funcionar en Windows **sin cambiar nada en
  macOS**. Cada subpaso aísla una dependencia detrás de `#if os(Windows)` o de un protocolo pequeño, con la
  implementación de macOS tal cual. Antes de empezar, lee la skill `terminal-netdeck-patterns` (archivos que cambian
  juntos y regresiones conocidas) y, para los tests, `swift-protocol-di-testing` si la tienes. Cada subpaso es **un PR**
  contra `propuesta/windows`, en su rama `windows/p4x-<tema>`.
- **Depende de:** P3 (camino A o C). **Esfuerzo total:** L.
- **Comprobación de cada subpaso:** en Windows, `swift build --target NetDeckCore` con menos errores que antes y los
  tests nuevos en verde (`windows/scripts/test.ps1 --filter …`); en el Mac (el autor), `./test.sh` en verde. Revisión
  con `netdeck-auditor` o `ecc:swift-reviewer` antes de fusionar.
- **Marcha atrás:** cada subpaso es un PR aparte; se revierte sin afectar a los demás.

### P4.0 · Manifiesto y cripto (S, fuerte; el primero, solo, con OK del autor)
- `Package.swift`, los cuatro `import CryptoKit` (`CredentialLedger`, `JumpSharing`, `UpdateCheck`, `Transfer`) y
  `Tests/NetDeckCoreTests/BuferIncrementalTests.swift`.
- [ ] Que el ejecutable `TerminalNetDeck` (SwiftUI + AppKit) sólo exista en macOS: `#if os(macOS)` en el manifiesto
      alrededor del producto y el target. Si no, `swift build` y `swift test` en Windows intentan compilar la app.
- [ ] SwiftTerm en los tests sólo en macOS y Linux (`condition: .when(platforms: [.macOS, .linux])`) y
      `#if canImport(SwiftTerm)` en `BuferIncrementalTests` (o, si P2 confirma que el motor compila en Windows, dejarlo).
- [ ] Cripto: en cada archivo, `#if canImport(CryptoKit) import CryptoKit #else import Crypto #endif`, y swift-crypto
      como dependencia **sólo para Windows** (`.product(name: "Crypto", package: "swift-crypto", condition:
      .when(platforms: [.windows]))`). **Ojo, toca macOS:** el paquete se resuelve igualmente en el Mac y cambia
      `Package.resolved` (y lo que revisa `tools/test_osv.sh`). Se dice en el PR y lo aprueba el autor.
- [ ] Comprobar en el Mac que `swift build -c release` sigue igual (la Release de la 1.0.0 ya se rompió una vez por el
      compilador de la CI).

### P4a · Procesos hijos (M, fuerte)
- `Remote/ChildProcess.swift`, `Sessions/Tunnels.swift` (lanzar y parar el ssh del túnel), un `ProcessAlive` nuevo.
- [ ] Sustituir `posix_spawn` + `setsid` + `killpg` por `CreateProcessW` con un **Job Object** (al cerrar se mueren
      también los hijos, como hoy el grupo de procesos) o por `Foundation.Process` si basta. Siempre con
      `CREATE_NO_WINDOW`: si no, una app con interfaz abre una consola por cada ssh.
- [ ] Regla que no cambia: sólo se heredan stdin/stdout/stderr (`PROC_THREAD_ATTRIBUTE_HANDLE_LIST`).
- [ ] `DispatchSourceProcess` no existe en Windows: esperar el fin con `WaitForSingleObject` en un hilo.
- [ ] Un `ProcessAlive.isAlive(pid)` común (`kill(pid, 0)` en macOS; `OpenProcess` + `GetExitCodeProcess` en Windows)
      que luego usan `CredentialLedger` (P4d) y `Askpass` (P4e).

### P4b · Rutas de los programas del sistema (S, normal; comparte `Tunnels`, `KnownHosts` con P4a/P4f)
- Todos los ejecutables fijos: `Sessions/ConnectionRoute.swift` (`/usr/bin/ssh`, `/usr/bin/sftp`,
  `/usr/bin/env telnet`, `/usr/bin/false`, `/bin/zsh` y `/etc/shells`, y el argumento `-l` de la shell local),
  `Sessions/SessionFile.swift` (`sshCheck`), `Sessions/JumpSharing.swift`, `Security/KnownHosts.swift`
  (`ssh`, `ssh-keygen`), `Sessions/Tunnels.swift`.
- [ ] Un sitio único para las rutas: en Windows, `%SystemRoot%\System32\OpenSSH\ssh.exe` etc. **Nunca buscarlos por el
      `PATH`** (es la misma regla que las rutas fijas de macOS; `/usr/bin/env telnet` ya es una búsqueda por `PATH` y en
      Windows pasa a `%SystemRoot%\System32\telnet.exe`).
- [ ] Shell local: PowerShell o `cmd.exe` en lugar de `/etc/shells`, **sin** `-l` (no existe en esos dos). Las
      pestañas sin orden (serie, FTP) no pueden usar `/usr/bin/false`: que no lancen nada.
- [ ] `launchProblem`: «No está ssh.exe en este PC», con su `L("…")` e inglés.

### P4c · Compartir el salto (M, fuerte; después de P4b)
- `Sessions/JumpSharing.swift`, `Sessions/ConnectionRoute.swift` (`jumpOptions`).
- [ ] Si P1 confirma que no hay ControlMaster, `JumpSharing.standard()` devuelve `nil` en Windows (ya es el camino de
      «se conecta como siempre, sin compartir», por `-J`) y se dice en la interfaz que en Windows cada pestaña entra en
      el bastión.
- [ ] Anotar en la ADR la alternativa para más adelante (un único ssh al bastión con `-W` por pestaña, o un SSH propio).

### P4d · Credenciales (M, fuerte, `security-review`; después de P4a)
- `Security/KeychainStore.swift` (usa `/usr/bin/security` para leer y guardar **y** `Security.framework`
  `SecItemCopyMatching` para comprobar y listar), `Security/CredentialLedger.swift`.
- [ ] Implementación con el **Administrador de credenciales** (`CredWriteW` / `CredReadW` / `CredDeleteW` /
      `CredEnumerateW`, tipo `CRED_TYPE_GENERIC`, persistencia `LOCAL_MACHINE`). Clave única: `TargetName =
      "Terminal NetDeck:<servicio>:<cuenta>"`. Límite del secreto: 2560 bytes (rechazar lo que pase, con su mensaje).
- [ ] Reglas que no cambian: el secreto nunca en argumentos ni en `DebugLog`; las lecturas, fuera del hilo principal.
- [ ] `CredentialLedger`: `ProcessAlive` (de P4a) en vez de `kill(pid, 0)`, y el candado entre procesos `flock` pasa a
      `LockFileEx`. El bloqueo de 15 min y sus casos (raíz, «Contraseñas») no cambian.
- [ ] Anotar para P9: en Windows cualquier proceso del mismo usuario puede leer la credencial con `CredReadW` sin que se
      le pregunte (el Llavero tiene ACL por app). Es más débil y hay que decirlo.

### P4e · Askpass (M, fuerte; después de P4d)
- `Security/Askpass.swift`.
- [ ] Según P1: si `SSH_ASKPASS` funciona, el askpass sigue siendo un ejecutable al que ssh llama. Valorar un
      `netdeck-askpass.exe` de consola aparte en vez de la propia app: con MSIX/WinUI 3 puede que ssh no pueda lanzar el
      ejecutable empaquetado por su ruta, y arrancar la app entera para cada pregunta es lento (comprobarlo en P10).
- [ ] El archivo de estado se nombra con `getppid()` (no existe en Windows): el PID del padre con
      `CreateToolhelp32Snapshot`, o pasar el PID por el entorno al lanzar ssh.
- [ ] La lectura de respaldo por `/dev/tty` y `tcgetattr` pasa a `CONIN$` con `SetConsoleMode` (sin eco).
- [ ] `purgeStates` usa `kill(pid, 0)`: `ProcessAlive`.

### P4f · Archivos del usuario y permisos (M, fuerte)
- `Support/SafeFile.swift`, `Support/AppPaths.swift`, `Support/DataBackup.swift`, `Support/DebugLog.swift`,
  `Support/ErrorLog.swift`, `Terminal/SessionLog.swift` (permisos), `Sessions/SessionFile.swift` (0600/0700),
  `Security/KnownHosts.swift` (0600). Comparte `SessionFile` y `KnownHosts` con P4b.
- [ ] Todos los `.posixPermissions` (0600 / 0700) pasan a una ACL con sólo el usuario actual (y SYSTEM), sin herencia.
      Es lo que pide el OpenSSH de Windows para `config` y claves (mensaje exacto en P1).
- [ ] `AppPaths`: `%APPDATA%\Terminal NetDeck` (o lo que diga P1 sobre espacios en el `Include`); el `Include` en
      `%USERPROFILE%\.ssh\config` con la forma que P1 haya visto funcionar; `AppPaths.tilde` enseña `%USERPROFILE%`
      como `~`.
- [ ] **`AppPaths.underTests`** detecta los tests por el nombre del proceso (`xctest`, `swiftpm-testing-helper`): en
      Windows el proceso se llama distinto y los tests escribirían en tu carpeta. Añadir el de Windows. Lo comprueba
      `losTestsNoEscribenEnTuCarpeta` (`AskpassGuardarTests`).
- [ ] Escritura atómica: `SafeFile` ya usa `FileManager.replaceItemAt`. Primero comprobar qué hace Foundation en
      Windows (¿`ReplaceFileW`?) y sólo si no es atómico, escribirlo a mano.

### P4g · Puerto serie (M, normal)
- `Sessions/SerialPort.swift`, `Sessions/SerialLine.swift`.
- [ ] `\\.\COMn` con `CreateFileW`, `SetCommState` (velocidad, bits, paridad, parada, control de flujo) y
      `SetCommTimeouts`; la lista de puertos, del registro (`HARDWARE\DEVICEMAP\SERIALCOMM`).
- [ ] `SerialLine` sólo acepta `/dev/cu.*` y `/dev/tty.*`: en Windows tiene que aceptar `COMn` (y rechazar el resto).
      Decidir cómo se escribe en la anotación `# @serie` y que un archivo de sesiones hecho en el Mac no rompa en
      Windows (el puerto simplemente no estará).
- [ ] Los textos de error («¿está conectado el adaptador USB-serie?») valen igual.

### P4h · Red y archivos de bajo nivel (M, normal)
- `Sessions/Tunnels.swift` (comprobación de puertos con `getaddrinfo`, `bind`, `fcntl O_NONBLOCK`, `poll`,
  `SO_NOSIGPIPE`), `Remote/FTPClient.swift` (`Network.framework`), `Remote/Transfer.swift` (`LocalFileWriter`:
  `open(O_EXCL|O_NOFOLLOW)` y `lstat`, también lo usa la edición remota), `Terminal/SessionLog.swift`
  (`O_CLOEXEC|O_NOFOLLOW`), `Terminal/TerminalFont.swift` (`CoreText`), `Sessions/OpenWindows.swift` (`CoreGraphics`).
- [ ] Sockets de los túneles: Winsock (`WinSDK`), con la misma lógica.
- [ ] FTP: Foundation de Windows no tiene un API de flujos TCP útil, así que Winsock o SwiftNIO, con la misma máquina
      de estados de FTP.
- [ ] `open(O_EXCL|O_NOFOLLOW)`: `CreateFileW` con `CREATE_NEW` y `FILE_FLAG_OPEN_REPARSE_POINT` (no seguir enlaces es
      una regla de seguridad, no se quita).
- [ ] `OpenWindows` sólo usa `CGRect/CGPoint/CGSize`, que Foundation de Windows ya tiene: `#if canImport(CoreGraphics)`.
- [ ] `TerminalFont`: tras `#if canImport(CoreText)`, con lo que pida la interfaz en P8 (DirectWrite).
- [ ] `UserDefaults` (idioma, historial): funciona en Windows, pero comprobar dónde guarda y que el askpass lo lee igual.

## P5 · CI de Windows (S, normal)

- **Contexto:** hoy `.github/workflows/tests.yml` sólo corre en `macos-26`. Hay un borrador en
  [ci/windows-nucleo.yml](ci/windows-nucleo.yml) que compila el núcleo en `windows-latest`.
- **Depende de:** P2 (puede activarse en cuanto haya algo que compilar). **Rama:** `windows/p5-ci`.
- **Tareas:**
  - [ ] Fijar la acción de instalación de Swift a un tag o commit (nunca `@main`) y comprobar sus parámetros actuales
        (pueden ser `branch`/`tag` o `swift-version`).
  - [ ] Copiarlo a `.github/workflows/windows.yml`. La privacidad va en su propio job, **sin** `continue-on-error`; el de
        compilar, con `continue-on-error: true` hasta que P4 termine.
  - [ ] `core.autocrlf false` antes del checkout (el runner de Windows convierte a CRLF por defecto).
- **Salida:** la CI de Windows corre en cada PR de `propuesta/windows` y su resultado se apunta en ESTADO.md.

## P6 · Tests del núcleo en Windows (M, normal)

- **Contexto:** `Tests/NetDeckCoreTests` tiene 705 tests (Swift Testing). Una docena de archivos lanzan programas del
  sistema o usan rutas de macOS. Los que se sabe que fallarán: `sinSshNoSeDaPorBueno` (`RobustezTests`) y
  `losTestsNoEscribenEnTuCarpeta` (`AskpassGuardarTests`, si P4f no está).
- **Depende de:** P4.0, P4a, P4b y P4f; y del resultado de P2 sobre SwiftTerm. **Rama:** `windows/p6-tests`.
- **Tareas:**
  - [ ] `powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/test.ps1` y lista de los que fallan,
        por causa.
  - [ ] Los que dependen de macOS de verdad: `@Test(.enabled(if: …))` o `#if os(macOS)`, nunca borrarlos.
  - [ ] Tests nuevos para lo de Windows (ACL, Administrador de credenciales con un servicio de prueba, Job Objects).
  - [ ] Activar `test.ps1` en la CI de Windows (P5).
- **Salida:** los tests en verde en Windows (con `test.ps1`) y en macOS (`./test.sh`).

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
  - [ ] Ojo: ConPTY reinterpreta algunas secuencias VT. Probar colores de 256 y 24 bits, el ratón y el título. Y telnet
        según lo visto en P1.
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
  reales) y, si está, la skill `windows-desktop-e2e` para las pruebas de la interfaz.

## P9 · Seguridad en Windows (M, fuerte)

- **Depende de:** P4, P8. **Rama:** `windows/p9-seguridad`.
- **Tareas (skill `security-review` y agente `ecc:security-reviewer`):**
  - [ ] `SessionImporter.safeExtra` sigue quitando las opciones que ejecutan órdenes; comprobar también las rutas de
        Windows (`ProxyCommand C:\…`, `LocalCommand`, `KnownHostsCommand`).
  - [ ] Nombres, equipos y usuarios que empiezan por `-` se siguen rechazando. Ojo con `/`: en Windows algunos
        programas lo leen como opción.
  - [ ] `TerminalEnvironment` quita `LANG`, `LANGUAGE` y `LC_*` y pone `LC_CTYPE=C.UTF-8`; el resto del entorno pasa,
        igual que en macOS. Comprobar que en Windows no hay variables propias que cambien el comportamiento de ssh.
  - [ ] Credenciales, askpass y bloqueo de 15 min: las mismas pruebas que en macOS. Documentar la diferencia de
        `CredReadW` frente a la ACL del Llavero (P4d).
- **Salida:** informe sin hallazgos graves abiertos.

## P10 · Paquete, firma y actualizaciones (M-L, fuerte)

- **Contexto:** en macOS hay un `.dmg` que se comprueba con sha256, id, versión y `codesign --verify`, y nada se
  instala sin el clic en «Actualizar ahora». En Windows hay que hacer lo mismo.
- **Depende de:** P8. **Rama:** `windows/p10-paquete`.
- **Tareas:**
  - [ ] Paquete MSIX o instalador (decidirlo con una ADR nueva; comprobar que ssh.exe puede lanzar el askpass desde la
        instalación elegida, ver P4e) y su workflow de Release en `windows-latest`.
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
Con la skill `blueprint` (o a mano): partir un paso, añadir uno o saltarlo, siempre dejando en [ESTADO.md](ESTADO.md)
el motivo. Si una decisión cambia el camino, una ADR nueva en `decisiones/` que diga a cuál sustituye.
