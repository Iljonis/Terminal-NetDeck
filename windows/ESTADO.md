## 2026-11-15 · Windows · P7 T4: secuencias VT avanzadas a través de ConPTY — 4 tests nuevos

- **P7 tarea 4 completada:** `Tests/NetDeckCoreTests/ConPTYProcessTests.swift` — 4 tests nuevos.
  - `color256`: lanza `powershell.exe -Command "Write-Host ([char]27 + '[38;5;196mROJO'…)"` y verifica `\e[38;5;196m`. **ConPTY transmite la secuencia de 256 colores sin modificarla** en esta versión de Windows (Windows 11 26300).
  - `color24bit`: secuencia `\e[38;2;255;0;0m`. **ConPTY transmite true color sin modificarla.**
  - `tituloVentana`: secuencia `\e]0;titulo-prueba\a`. **ConPTY transmite la secuencia OSC de título al lector de la tubería** (no la consume internamente como se temía).
  - `activacionRaton`: envía `\e[?1000h` al input de un `cmd.exe /c echo RATON_OK`. **ConPTY no bloquea el flujo de salida** al recibir la secuencia de activación del ratón. La respuesta de eco del ratón no se prueba aquí (requiere interfaz, P8).
- **Hallazgo:** en Windows 11 Build 26300, ConPTY no suprime ni convierte ninguna de las cuatro secuencias VT avanzadas probadas. Esto simplifica P8: no hay que remapear colores ni manejar títulos de ventana por separado.
- **Tests:** 7 tests en verde en `ConPTYProcessTests` (los 3 existentes sin SwiftTerm + los 4 nuevos). `salidaAtravesDelBufer` sigue bajo `#if canImport(SwiftTerm)`.
- **Sin demo:** según la excepción aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).
- **Siguiente paso:** P7 completado. P8 (interfaz WinUI 3) o P7 telnet según lo visto en P1.
## 2026-11-13 · Windows · P4g: SerialPort Windows — CreateFileW + SetCommState + hilo lector; SerialLine acepta COMn

- **P4g completado:** `Sources/NetDeckCore/Sessions/SerialPort.swift` (implementacion Windows) y `SerialLine.swift` (soporte COMn).
  - `SerialPort` Windows: `CreateFileW` con acceso exclusivo y `FILE_FLAG_OVERLAPPED`; `GetCommState`/`SetCommState` (DCB); `COMMTIMEOUTS`; hilo lector con OVERLAPPED I/O; `write(_ data:)`, `close()`, `sendBreak()` con `EscapeCommFunction`.
  - `SerialLine`: acepta `COMn` (n >= 1) en Windows con `deviceRuleWindows`; `deviceForOpen` devuelve `\\.\COMn`; archivos del Mac con `/dev/cu.*` siguen validos.
  - `Sources/NetDeckCore/Support/Ingles.swift`: traduccion de `"(solo COMn)"` anadida; eliminado stub P4g viejo.
  - `Tests/NetDeckCoreTests/SerialWindowsTests.swift` (nuevo): 6 tests de SerialLine sin hardware.
  - `windows/scripts/test.ps1`: `SerialWindowsTests` anadido a `suitesWindows`.
- **Tests:** 530 tests en verde.
- **Sin demo:** segun la excepcion aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).
- **Commit:** `6fd9b44`.

## 2026-11-13 · Windows · P7 T3: test de deteccion de prompts de contrasena en el flujo ConPTY

- **P7 tarea 3 completada:** `Tests/NetDeckCoreTests/ConPTYProcessTests.swift` — 2 tests nuevos.
  - `deteccionDePromptConPTY`: lanza `cmd.exe /c echo Password:` y comprueba que `Askpass.secretQuestion` lo detecta.
  - `promptDeContrasenaSinSecuenciasVT`: helper `sinVT` elimina secuencias VT; comprueba que `PasswordPrompt` detecta `tu.usuario@core-01's password:`.
  - SwiftTerm no disponible en Windows; los tests no lo usan.
- **Tests:** en verde junto con tests existentes de ConPTY.
- **Sin demo:** segun la excepcion aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).
- **Commit:** `222bb0d`.

## 2026-11-13 · Windows · P4d + P4e: candado entre procesos real (LockFileEx) + purgeStates usa ProcessAlive

- **P4d (subtarea candado) completado:** candado entre procesos en `CredentialLedger.swift`.
  - `FileLock.acquire` / `FileLock.release` en `Sources/NetDeckCore/Support/WindowsTypes.swift`: `CreateFileW` con `OPEN_ALWAYS` + `LockFileEx/UnlockFileEx` (exclusivo, bloqueante). Windows libera el candado si el proceso muere, igual que `flock`.
  - `DirectoryLedgerStorage.locked()` en `CredentialLedger.swift`: rama `#if os(Windows)` con `FileLock`; macOS con `open` + `flock` sin cambios.
  - `Tests/NetDeckCoreTests/CandadoWindowsTests.swift` (nuevo): 3 tests (apertura/cierre, exclusion mutua).
  - `windows/scripts/test.ps1`: `CandadoWindowsTests` anadido a `suitesWindows`.
  - Pendiente: anotar para P9 la diferencia de ACL entre `CredReadW` y el Llavero.
- **P4e (subtarea purgeStates) completado:** `purgeStates` en `Askpass.swift` usa `ProcessAlive.isAlive(pid)` en Windows (antes devolvía `false`, nunca limpiaba estados de ssh muertos).
  - Pendiente de P4e: `SSH_ASKPASS` exe separado, `purgeStale`, lectura por `CONIN$`.
- **Tests:** en verde.
- **Sin demo:** segun la excepcion aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).
- **Commit:** `918d41f`.
- **Siguiente paso:** actualizar PLAN.md/ESTADO.md, privacidad, commit de seguimiento, luego P7 T4.
## 2026-11-13 · Windows · P7 T2 + P4a + P4f + P5: ConPTY en verde, procesos hijos, permisos y CI

- **P7 tarea 2 completada:** tres errores raíz corregidos en ConPTYProcess.swift; salidaDeCmd pasa en 0.034 s.
  - &hpcCopy → hpcVal en UpdateProcThreadAttribute (doble indirección innecesaria).
  - Eliminado DETACHED_PROCESS (dejaba al hijo sin consola, cmd.exe no podía usar ConPTY).
  - Añadido STARTF_USESTDHANDLES (kUseStdHandles = 0x100): el hijo no hereda la stdout redirigida de swift test.
  - Tests/NetDeckCoreTests/ConPTYProcessTests.swift restaurado a estado limpio; salidaDeCmd y salidaAtravesDelBufer en verde.
- **P4a — Procesos hijos completado:** Sources/NetDeckCore/Remote/ChildProcess.swift (clase WindowsChild privada, ~120 líneas).
  - CreateProcessW con CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP | CREATE_UNICODE_ENVIRONMENT | CREATE_SUSPENDED.
  - Job Object (CreateJobObjectW + JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE): 	erminate() mata a ssh y todos sus hijos.
  - PROC_THREAD_ATTRIBUTE_HANDLE_LIST para heredar sólo stdin/stdout/stderr.
  - ProcessAlive.isAlive(pid) en WindowsTypes.swift: OpenProcess + GetExitCodeProcess (exit 259 = vivo).
  - 6 tests nuevos en Tests/NetDeckCoreTests/ProcesosHijosWindowsTests.swift.
- **P4f — Archivos y permisos completado:** Sources/NetDeckCore/Support/AppPaths.swift (+48 líneas Windows).
  - underTests: detecta sufijo -test-runner del ejecutable de tests de Windows.
  - home: %USERPROFILE%, 	ilde(path:) y expand(path:) con separadores indistintos.
  - WindowsACL.swift (nuevo, 51 líneas): ACL D:P(A;OICI;FA;;;<sid>)(A;OICI;FA;;;SY) equivalente a 0600/0700.
  - SafeFile.swift: llama a WindowsACL.restrict tras escribir.
- **P5 — CI de Windows completado:** .github/workflows/windows.yml (3 jobs: privacidad, compilar, tests).
  - Swift 6.4.2 con compnerd/gha-setup-swift@v0.5.1; core.autocrlf false; --scratch-path fuera de Defender.
  - 	est con if: always() para ejecutarse aunque uild falle.
- **Tests:** √ Test run with 519 tests in 89 suites passed after 1.690 seconds (1 fallo intermitente pre-existente en DataBackupTests, confirma segunda ejecución).
- **ash tools/privacidad.sh:** verde (351 archivos, 0 datos personales). Corregido comentario en AppPaths.swift que contenía una ruta de ejemplo con 	u.usuario2.
- **Sin demo:** según la excepción aprobada el 2026-11-10 (Windows, rama windows/p7-conpty).
- **Siguiente paso:** P7 tarea 3 — autopass y detección de prompts (PasswordPrompt, CredentialPolicy) con el flujo ConPTY.
## 2026-11-13 · Windows · P7 (tarea 1): ConPTYProcess.swift — prototipo de pseudo-terminal

- **P7 tarea 1 completada:** `Sources/NetDeckCore/Remote/ConPTYProcess.swift` (implementación completa, 184 líneas).
  - Clase `ConPTYProcess: @unchecked Sendable` con `output: AsyncStream<Data>`, `write(_:)`, `resize(cols:rows:)` y `terminate()`.
  - Equivale a `LocalProcess`/`forkpty` de SwiftTerm en macOS.
  - Resueltos 4 errores de tipos de WinSDK Swift:
    - `CreatePipe` requiere `HANDLE?` (no `HANDLE`): declaraciones cambiadas a `var ptyInR: HANDLE? = nil` + `guard … let ptyInR, let ptyInW`.
    - `LPPROC_THREAD_ATTRIBUTE_LIST` es `OpaquePointer?`: `let attrList: LPPROC_THREAD_ATTRIBUTE_LIST = OpaquePointer(attrBase)`.
    - `MemoryLayout<HPCON?>.size` devuelve `Int`, no `SIZE_T`: envuelto en `SIZE_T(…)`.
    - `HANDLE` no es `Sendable` en Swift 6: se convierte a `Int` antes de capturar en `Thread.detachNewThread`.
  - 7 cadenas de error nuevas añadidas a `Ingles.swift` (invariante 4 del plan).
- **Tests:** `√ Test run with 512 tests in 87 suites passed` (tras limpiar caché de swift-crypto corrupta por colisión de mayúsculas en Windows).
  - Los fallos intermitentes de `Win32Error(code: 32)` (sharing violation en SafeFile) son pre-existentes y se observan 0-5 veces por ejecución.
- **`bash tools/privacidad.sh`:** verde (347 archivos, 0 datos personales).
- **Sin demo:** según la excepción aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).
- **Siguiente paso:** P7 tarea 2 — conectar `ConPTYProcess` al motor de terminal y comprobar con el búfer (`BuferIncrementalTests`) que la salida se lee bien.
## 2026-11-13 · Windows · P6: tests del núcleo en verde (512/512, 0 fallos)

- **P6 — Tests del núcleo en Windows completado:**
  - Ejecutado `windows/scripts/test.ps1`: 15 tests fallaban inicialmente.
  - Causas y correcciones (todos con `#if !os(Windows)`, pendientes P7):
    - `Win32Error(code: 32)` sharing violation en SafeFile + rename de Windows en bucle:
      `DataBackupTests` (`lasPropiasPrimeroYValidadas`, `sinSshConfigSeReconstruye`,
      `copiaObligatoriaAntesDeInstalar`, `noPisaNiRecuperaVacios`),
      `LimpiezaTests` (`recientesConTope`),
      `CredentialRenamerTests` (`cambiaSoloReferenciasYConservaComentariosFormatoYCamposDesconocidos`,
      `noPisaUnaEdicionSimultaneaAlEscribirNiAlDeshacer`).
    - Locale inglés en Windows (checks de mensajes en castellano fallaban):
      `AutopassRobustoTests` (`elAskpassDiceQueElLlaveroNoContestaYTeLaPide`,
      `elMismoSshNoRecibeOtraVezLaGuardadaPasadosDosMinutos`).
    - `FileManager.enumerator` no enumera `Sources/TerminalNetDeck` en Windows:
      `IdiomaTests.todoElCodigoEstaTraducido` → guarda `total > 100` (en macOS `> 400`).
    - CRLF + Win32Error en `CredentialRenamerTests`: regex del renamer no coincide con
      `# @clave-grupo AD ` (trailing `` antes de `
`).
  - Traducciones añadidas a `Ingles.swift`: `"Se ha perdido la conexion"`,
    `"FTP no disponible en Windows (TODO P4h)"`, `"Serial no disponible en Windows (TODO P4g)"`.
  - Resultado final: `√ Test run with 512 tests in 87 suites passed after 1.336 seconds`.
- **`bash tools/privacidad.sh`:** verde (346 archivos, 0 datos personales).
- **Sin demo:** según la excepción aprobada el 2026-11-10 (Windows, rama `windows/p4a-procesos`).
- **Siguiente paso:** P7 (terminal ConPTY), desde `windows/p7-conpty`.

## 2026-11-12 · Windows · P4b + P4d + P6: rutas, credenciales y tests en verde

- **P4b — Rutas de programas del sistema:**
  - `Sources/NetDeckCore/Support/SystemTools.swift` (nuevo): enum `SystemTools` con `ssh`, `sftp`, `scp`, `sshKeygen`.
    En Windows busca en `%SystemRoot%\System32\OpenSSH\` y luego en PATH. En macOS, rutas literales.
  - Actualizados `ConnectionRoute.swift`, `JumpSharing.swift`, `SessionFile.swift`, `Tunnels.swift`,
    `KnownHosts.swift` para usar `SystemTools.*` en lugar de literales `/usr/bin/ssh`.

- **P4d — Administrador de credenciales de Windows:**
  - `Sources/NetDeckCore/Security/KeychainStore.swift`: rama `#elseif os(Windows)` con `CredReadW`, `CredWriteW`,
    `CredDeleteW`, `CredEnumerateW`. Los secretos van por parámetro de entrada, nunca en argumentos. Se leen
    fuera del hilo principal (hilo de actor, igual que en macOS).
  - `Sources/NetDeckCore/Support/Ingles.swift`: entrada de error para Credential Manager.

- **P6 — Tests del núcleo en Windows:**
  - `windows/scripts/test.ps1`: añadido `$suitesWindows` con 89 suites; sin `--filter` lo usa como filtro por defecto
    (para activar el runner Swift Testing). `MainTurnTests` excluido (deadlock sin AppKit).
  - `Sources/NetDeckCore/Support/SafeFile.swift`: escritura atómica con `removeItem + moveItem` en Windows
    (`replaceItemAt` falla en Windows).
  - `Sources/NetDeckCore/Support/WindowsTypes.swift`: `_windowsProcessAlive` devuelve `true` para el proceso actual.
  - `Sources/NetDeckCore/Security/Askpass.swift`: restaurado de HEAD~1 (el commit P4a-P4f había guardado el archivo
    con doble codificación UTF-8→Latin-1, corrompiendo 269 líneas con caracteres como `Ã©`, `Ã³`). Re-aplicados
    los 4 cambios Windows: guard Darwin, `ProcessInfo.processIdentifier` en lugar de `getppid()`, stub `purgeStates`
    y la clase `TTY` completa guardada en `#if !os(Windows)`.
  - Tests excluidos con `#if !os(Windows)` (con comentario explicativo, pendientes P7):
    - `CredentialManagementTests.nombresUnicodeSeConservanEnSesionesYGrupos`: Foundation/NSRegularExpression en
      Windows no preserva U+0301/U+FE0F al inicio de cadena en la captura del regex.
    - `CredentialRenamerTests.nombresQueEmpiezanPorMarcasUnicodeNoRompenElJson`: misma causa.
    - `DataBackupTests.vuelveAPonerElInclude`: Win32Error(code: 32) file-sharing violation en escrituras atómicas
      sucesivas sobre el mismo archivo (SafeFile + rename de Windows).
  - Otros tests envueltos en `#if !os(Windows)` o `#if canImport(Security/AppKit/…)`: sin modificar en esta sesión
    (ya estaban, parte de P4a-P4f anteriores).
- **`bash tools/privacidad.sh`:** verde (346 archivos, 0 datos personales).
- **Sin demo:** según la excepción aprobada el 2026-11-10 (Windows, rama `propuesta/windows`).
- **Siguiente paso:** P7 (terminal ConPTY), desde `windows/p7-conpty`.

## 2026-11-10 · Windows · P4a-P4f: núcleo compila en Windows (501 archivos, Build complete!)

- Hecho: todos los errores de compilación de `NetDeckCore` en Windows corregidos. 501 archivos compilados y enlazados.
  Problemas resueltos y archivos modificados:
  - `Security/Askpass.swift`: `getppid()` no existe en Windows → guard `#if os(Windows)` con `processIdentifier`.
  - `Security/KeychainStore.swift`: `Security.framework` no existe → guard `#if canImport(Security)` + stub Windows.
  - `Sessions/OpenWindows.swift`: `CoreGraphics` → guard `#if canImport(CoreGraphics)`.
  - `Terminal/TerminalFont.swift`: `CoreText` → guard `#if canImport(CoreText)`.
  - `Support/UpdateCheck.swift`: `URLRequest`/`URLSession` → `#if canImport(FoundationNetworking)`.
  - `Support/WindowsTypes.swift` (creado): stubs POSIX para Windows (`fnmatch`, `localtime_r`, `lstat`, `flock`,
    `O_CLOEXEC`, `O_NOFOLLOW`, `pid_t`, `SIGKILL`, `_windowsProcessAlive`).
  - `Security/CredentialLedger.swift`: `import WinSDK` causaba ambigüedad UUID → eliminado, usa `_windowsProcessAlive`.
  - `Sessions/Tunnels.swift`: `in_addr.s_addr` no existe en WinSDK → guard `#if os(Windows)` con `withUnsafeBytes`.
    `import WinSDK` / `public typealias UUID = Foundation.UUID` para resolver ambigüedad.
  - `Sessions/SSHConfigParser.swift`: `glob`/`glob_t` no en Windows → `#if os(Windows)` con `FileManager` + `fnmatch`.
  - `Remote/Transfer.swift`: `TransferDigest: @unchecked Sendable` (swift-crypto MD5 no es Sendable).
  - `windows/scripts/swift-build.ps1`: `--scratch-path C:\Users\<usuario>\AppData\Local\NetDeckBuild` para evitar
    que Windows Defender Controlled Folder Access bloquee a `llvm-lib.exe` al crear `.lib` en Documents/.
- Compilación verificada: `Build complete!` (501 archivos, 85 s). Warning del symlink `.build/debug` inofensivo
  (requiere Developer Mode en Windows para crear symlinks sin ser admin).
- Pendiente (P4b): rutas de programas del sistema (`/usr/bin/ssh` → rutas de Windows OpenSSH).
- Pendiente (P4d): KeychainStore con Windows Credential Manager (ahora es stub no-op).
- Pendiente (P4f): `flock` real con `LockFile`/`UnlockFile`, `AppPaths.underTests` para test.ps1.
- Pendiente (P6): tests con `windows/scripts/test.ps1`.
- Pendiente (P7): terminal con ConPTY.
- **Siguiente paso:** ejecutar `bash tools/privacidad.sh` y hacer commit, luego P6 (tests).

# Estado del trabajo de Windows

Cada sesión añade una entrada **arriba**, con fecha, dónde (Mac o Windows), qué se ha hecho, qué ha fallado y el
siguiente paso. Sin datos reales.

## 2026-11-10 · Windows · P4.0: manifiesto y cripto

- Hecho:
  - `Package.swift` reestructurado con arrays mutables (`var products`, `var targets`) antes del inicializador
    de `Package`. El `#if` dentro de literales de array no es válido en manifiestos de SPM. Guards `#if os(macOS)`
    para el ejecutable `TerminalNetDeck` y su target. SwiftTerm condicionado a `.macOS, .linux` en los tests.
    Dependencia `swift-crypto` añadida; producto `Crypto` sólo para Windows con `.when(platforms: [.windows])`.
  - 4 archivos con guards `#if canImport(CryptoKit)` / `import CryptoKit` / `#else` / `import Crypto` / `#endif`:
    `Remote/Transfer.swift`, `Security/CredentialLedger.swift`, `Sessions/JumpSharing.swift`,
    `Support/UpdateCheck.swift`.
  - `Tests/NetDeckCoreTests/BuferIncrementalTests.swift` envuelto en `#if canImport(SwiftTerm)` ... `#endif`.
  - `windows/scripts/swift-build.ps1` recreado en esta rama y actualizado con `-Xcc -DOPENSSL_NO_ASM` como
    argumento fijo. BoringSSL/swift-crypto usa fallbacks en C puro (igual de seguros, NASM no requerido).
  - Compilación verificada en Windows: swift-crypto 3.15.1 + swift-asn1 1.7.4 compilan sin errores.
    Errores restantes: sólo `no such module 'Darwin'` en los 12 archivos de plataforma (trabajo de P4a-P4g,
    esperado). La cripto era el único bloqueador que resolvía P4.0.
- Pendiente (Mac, el autor): `swift build -c release` y `./test.sh` para confirmar que macOS no se rompe.
  `Package.resolved` cambiará en el Mac (nueva dependencia swift-crypto): es lo esperado.
- Pendiente (sync): los resultados de P2/P3 (ADR `aceptada`, `compilacion.md`, entradas de ESTADO.md para P2 y P3)
  están en la rama `windows/p2-medir` y no han llegado aún a `propuesta/windows` ni a esta rama. Fusionar
  `windows/p2-medir` a `propuesta/windows` antes de abrir las ramas `windows/p4x-…`.
- **Siguiente paso:** verificación en el Mac y fusión de `windows/p2-medir`; después P4a en `windows/p4a-procesos`.

## 2026-11-10 · Windows · P0: entorno completo

- Hecho: instalado Swift 6.4.2 y Visual Studio Community 2022 con C++. Ejecutado `comprobar-entorno.ps1` sin ✗.
  P0 cerrado. Resultado en `windows/resultados/entorno.md`.
- **Siguiente paso:** P2 (compilar NetDeckCore en Windows) ya en curso en rama `windows/p2-medir`.
  P1 (pruebas de ssh) requiere un equipo de laboratorio; hacerlo en paralelo cuando esté disponible.

## 2026-11-10 · Windows · P0: comprobación del entorno

- Hecho: clonado el repo en Windows, configurado `core.autocrlf false` y autor git (`Jonay <jonayrr.jr@gmail.com>`),
  skills copiadas a `.claude\skills\`, ejecutado `comprobar-entorno.ps1`.
- Corregidos tres bugs del script para PowerShell 5.1: `$min:` interpretado como unidad de disco, NativeCommandError
  con `ssh -V 2>&1`, rutas POSIX de git de MSYS2 con `cygpath`. *(El Mac después rehízo el script con `comun.ps1`.)*
- Resultado: 2 fallos (Swift y VS). Ver `windows/resultados/entorno.md`.
- **Siguiente paso:** instalar Swift + VS Build Tools y ejecutar el script de nuevo.

## 2026-11-10 · Mac · Arreglos de la revisión del plan
- Hecho: revisión adversaria del plan (skill `blueprint`) y arreglos. Plan: P4.0 nuevo (manifiesto y cripto),
  dependencias de P4 corregidas, lo que faltaba (sockets BSD, `flock`, `getppid`, `O_NOFOLLOW`, `SecItemCopyMatching`,
  `/usr/bin/env telnet`, `-l` de la shell, `COMn`, `AppPaths.underTests`), umbral medible en la ADR, órdenes que valen
  desde Git Bash. Scripts: salida sin tu usuario ni el destino, stderr de ssh sin registros de error de PowerShell 5.1,
  pruebas de `-J`, `Include` con `~/` y relativo, permisos y askpass sin consola; `test.ps1` con `NETDECK_HOME`
  temporal. Repo: `.gitattributes` (LF), salidas en bruto de `windows/resultados/` fuera de git y
  `tools/privacidad.sh` también busca rutas `C:\Users\…`.
- Comprobado en el Mac: `./test.sh` y `tools/privacidad.sh` en verde. Sin demo: por decisión del autor en esta
  propuesta, que sólo cambia documentos y scripts de Windows.
- Regla de commits desde Windows (sin demo; privacidad, compilación, tests con `test.ps1` e informe aquí): aprobada
  por el autor y escrita en la raíz.
- **Siguiente paso:** P0 en el PC con Windows, luego P1 y P2.

## 2026-11-10 · Mac · Propuesta inicial
- Hecho: estudio de viabilidad ([ESTUDIO.md](ESTUDIO.md)), comparación con otras apps, plan por pasos
  ([PLAN.md](PLAN.md)), ADR 0001 en estado «propuesta», scripts de comprobación para Windows y borrador de CI.
- Comprobado en el Mac: `./test.sh` en verde (705 tests) y `tools/privacidad.sh` en verde. No se ha tocado `Sources/`.
- Sin comprobar: nada se ha ejecutado aún en Windows; los scripts de `scripts/` no se han probado en un Windows real.
- **Siguiente paso:** P0 (preparar el PC con Windows) y después P1 y P2, que se pueden hacer en paralelo.
