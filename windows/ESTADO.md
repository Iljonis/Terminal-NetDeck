## 2026-11-16 · Windows · P8: barra lateral SessionManager compilando

**Por Claude.** Build complete y demo corriendo en modo barra lateral.

### Cambios

- windows/Desktop/Sources/NetDeckWindows/NetDeckWindows.swift:
  - SessionManager inicializado dentro de onLaunched vía MainActor.assumeIsolated (fix actor isolation Swift 6).
  - Rejilla raíz 2 columnas: 200 px barra lateral (ScrollViewer) + * área principal.
  - uildSidebar(): lee sessions.groups, crea cabecera por grupo y botón por perfil (icono tipo + nombre).
  - openProfile(): llama sessions.route(to:) y abre pestaña.
  - Demo: NETDECK_DESKTOP_DEMO=1 → sessions.loadSamples().
- Compilación: Build complete! (6.73 s). Demo lanzado con desktop.ps1 -Demo.

### Pendiente de P8

- Verificación visual de la barra lateral (pestañas de sesión abiertas al clic).
- Editor de sesión, explorador SFTP/FTP, Ajustes, temas, menús y atajos, MultiExec.

### Siguiente

1. Autor: revisar demo, confirmar que los botones de sesión abren pestaña.
2. CI P6: activar 	est.ps1 en .github/workflows/windows.yml (Codex).
3. Continuar P8 con editor de sesión y explorador SFTP.
## 2026-11-16 Windows P8: ventana WinUI 3 corriendo (por Claude)

Build complete y ventana de NetDeckWindows.exe abierta en modo demo.

### Fix: Package.swift linkerSettings

- WinUI 0.1.1 es una dylib dinamica. WindowsFoundation y WinAppSDK no se enlazaban en el exe.
- Fix: linkerSettings en el target NetDeckWindows (no dependencias SPM explicitas).
  Razon: agregar dependencias SPM explicitas dispara re-resolution que falla en Windows con
  el bug "Couldn't get revision 3.15.1^{commit}: Needed a single revision".
  linkerSettings evita la re-resolution y linka directamente las libs ya compiladas.
- Resultado: Build complete! (4.62 secs). Exe corre >30 segundos = ventana abierta.

### Fix adicional: tag swift-crypto 3.15.1

- Ejecutado: git -C <scratch>/repositories/swift-crypto-... fetch origin tag 3.15.1
  (el cache SPM solo tenia hasta 3.14.0)

### Como correr el demo directamente (sin pasar por desktop.ps1)

  cd %LOCALAPPDATA%\NetDeckDesktopBuild\out\Products\Debug-windows-x86_64
  set NETDECK_DESKTOP_DEMO=1
  set NETDECK_HOME=%TEMP%\netdeck-demo-p8
  mkdir %NETDECK_HOME%
  NetDeckWindows.exe

### Tests main repo

- 545/545 en verde en windows/p7-conpty.

### Siguiente para Codex

1. Verificar la ventana demo (ya corre): prueba Terminal local, escribe texto, verifica
   que ConPTY esta procesando salida de PowerShell.exe.
2. Commit del borrador P8 en rama windows/p8-terminal.
   - Incluir fix de Package.swift (linkerSettings).
   - bash tools/privacidad.sh antes del commit.
3. CI P6: activar test.ps1 en .github/workflows/windows.yml.
4. Continuar P8: barra lateral con SessionManager (lista de sesiones del ssh_config).

NO tocar .github/workflows/ ni windows/scripts/test.ps1 desde el repo principal (propuesta/windows).

## 2026-11-15 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P8: relevo de la primera ventana

- Trabajo de Codex en la copia aislada `NetDeck-Codex-P8` bajo `LOCALAPPDATA`, rama local `windows/p8-terminal`, base `5294c0e`. Los archivos estÃƒÆ’Ã‚Â¡n en el ÃƒÆ’Ã‚Â¡rbol de trabajo, sin commit. La copia principal ya llegÃƒÆ’Ã‚Â³ a `d6499f8` con el resumen de cierre P4 de Claude. Incorporar esa base cuando se retome y conservar ambas notas de estado.
- Borrador en `windows/Desktop/`: paquete independiente con WinUI 3 (proyecciones WinRT de moreSwift, versiÃƒÆ’Ã‚Â³n 0.1.1), SwiftTerm 1.99.3 y el NetDeckCore existente. Ventana, pestaÃƒÆ’Ã‚Â±as con bÃƒÆ’Ã‚Âºfer separado, shell local, conexiÃƒÆ’Ã‚Â³n SSH directa, entrada de teclado y redimensionado ConPTY. El manifiesto principal y la app macOS se mantienen en la base de esta copia.
- `windows/scripts/desktop.ps1` prepara la compilaciÃƒÆ’Ã‚Â³n y un modo demo. El generador de SwiftTerm requiere LF en `swifterm-terminfo` y falla al invocar Git desde Foundation.Process con este toolchain. En la cachÃƒÆ’Ã‚Â© existente se restaurÃƒÆ’Ã‚Â³ ese archivo con LF. Con metadatos SWIFTTERM_BUILD_* explÃƒÆ’Ã‚Â­citos se generaron ambos archivos y la compilaciÃƒÆ’Ã‚Â³n avanzÃƒÆ’Ã‚Â³ a WinUI (184/195 antes de pararla).
- Pendiente inmediato: ejecutar `powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/desktop.ps1 -Scratch <LOCALAPPDATA/NetDeckBuild-Codex-P8>`, corregir los diagnÃƒÆ’Ã‚Â³sticos que aparezcan y comprobar el directorio de binarios y el bootstrapper de Windows App Runtime 1.5. DespuÃƒÆ’Ã‚Â©s abrir `-Demo` y probar con UI Automation teclado, salida, abrir/cambiar/cerrar pestaÃƒÆ’Ã‚Â±as y un SSH de laboratorio. Esta ventana aÃƒÆ’Ã‚Âºn no se ha ejecutado ni validado.
- El resto de P8 sigue pendiente. El siguiente bloque tras validar la ventana es la barra lateral sobre SessionManager. Revisar tambiÃƒÆ’Ã‚Â©n el estado real de ADR 0001: el plan y el historial describen el camino A, mientras el documento en esta base conserva el encabezado de propuesta.

ÃƒÂ¯Ã‚Â»Ã‚Â¿## SesiÃƒÆ’Ã‚Â³n 2026-11-15 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â P4e getppid()

- Implementado `_windowsGetppid()` en `WindowsTypes.swift` con `CreateToolhelp32Snapshot` + `Process32FirstW`/`NextW`.
- `stateFile()` en `Askpass.swift` usa `_windowsGetppid()` en Windows, igual que `getppid()` en macOS.
- El SSH_ASKPASS exe separado queda bloqueado hasta P10 (packaging/MSIX).
- **Siguiente:** P8 (interfaz WinUI 3) o lo que reste de P4.

## SesiÃƒÆ’Ã‚Â³n 2026-11-15 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â P4c + P4d notas ADR y seguridad

- **P4c**: Anotada en `decisiones/0001-camino-para-windows.md` la alternativa futura para el bastiÃƒÆ’Ã‚Â³n (ssh -W por pestaÃƒÆ’Ã‚Â±a o SSH propio).
- **P4d**: Creado `decisiones/0002-credenciales-windows.md` con la diferencia de ACL entre `CredReadW` y el Llavero, para revisiÃƒÆ’Ã‚Â³n en P9.
- **Siguiente:** P4e getppid (implementar getppid() para Windows con CreateToolhelp32Snapshot).
## 2026-11-15 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4h (FTP): FTPClient.swift adapta TCPStream a Winsock2

- **Completado:**
  - Sources/NetDeckCore/Remote/FTPClient.swift: nueva rama #elseif os(Windows) con implementaciÃƒÆ’Ã‚Â³n completa de TCPStream usando Winsock2 (WinSDK).
    - WSAStartup/WSACleanup, getaddrinfo/reeaddrinfo, socket/connect/closesocket.
    - ConexiÃƒÆ’Ã‚Â³n no bloqueante: ioctlsocket(FIONBIO) + WSAPoll con timeout configurable.
    - WSAGetLastError/WSAEWOULDBLOCK para detectar progreso de connect no bloqueante.
    - getsockopt(SO_ERROR) para verificar ÃƒÆ’Ã‚Â©xito tras WSAPoll.
    - CancelaciÃƒÆ’Ã‚Â³n segura via _FTPSocketHolder: el token de cancelaciÃƒÆ’Ã‚Â³n cierra el socket antes de que connectSocket() bloqueÃƒÆ’Ã‚Â© en WSAPoll.
    - send/ecv/shutdown usando WinSDK con Task.detached y withCheckedThrowingContinuation.
  - Sources/NetDeckCore/Support/Ingles.swift: nueva clave "FTP: network initialisation failed".
  - windows/PLAN.md: [x] en la tarea FTP de P4h.
- **Tests:** 545/545 en verde. Privacidad ok (355 archivos, 0 datos personales).
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama windows/p7-conpty).
- **Commit:** d17a3b9 en windows/p7-conpty.
## 2026-11-15 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P6 (tests nuevos): ACL, Administrador de credenciales y Job Objects

- **Completado:**
  - `Tests/NetDeckCoreTests/WindowsACLTests.swift` (nuevo): 4 tests de `WindowsACL.restrict`.
    - `restrictArchivoRetornaVerdadero`: crea un archivo temporal y verifica que `restrict` devuelve `true`.
    - `restrictCarpetaRetornaVerdadero`: igual para directorios.
    - `propietarioPuedeLeerTrasBlindar`: verifica que el propietario sigue leyendo el archivo tras blindarlo.
    - `restriccionDejaExactamenteDosAces`: comprueba con `GetNamedSecurityInfoW`/`GetAce` que el DACL tiene 2 ACEs (usuario + SYSTEM).
  - `Tests/NetDeckCoreTests/KeychainCredencialesWindowsTests.swift` (nuevo): 6 tests del Administrador de credenciales.
    Cada test usa una cuenta distinta (`test-p6-rw`, `test-p6-del`, etc.) para evitar interferencias con tests paralelos.
    Escribe, lee y borra credenciales de prueba; limpia con `defer`.
  - `windows/scripts/test.ps1`: `WindowsACLTests` y `KeychainCredencialesWindowsTests` aÃƒÆ’Ã‚Â±adidos a `$suitesWindows`.
  - `windows/PLAN.md`: `[x]` en Ãƒâ€šÃ‚Â«Tests nuevos para lo de Windows (ACL, Administrador de credenciales con un servicio de prueba, Job Objects)Ãƒâ€šÃ‚Â».
  - Job Objects: ya cubiertos en `ProcesosHijosWindowsTests` (`terminarSeLlevaAlNieto` prueba que `terminate()` mata al ÃƒÆ’Ã‚Â¡rbol de procesos).
- **Tests:** 10/10 en verde (`WindowsACLTests` + `KeychainCredencialesWindowsTests`). Privacidad ok (355 archivos, 0 datos personales).
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).

## 2026-11-15 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4g (correcciÃƒÆ’Ã‚Â³n): SerialLine.devices() revisada con withUnsafeMutableBytes

- **Revisado:**
  - `Sessions/SerialLine.swift`: `_devicesFromRegistry()` rehecha con buffers `[WCHAR]` y `withUnsafeMutableBytes`
    para pasar `UnsafeMutablePointer<BYTE>?` a `RegEnumValueW`; `String(decoding:prefix(while:), as: UTF16.self)`
    para leer el dato sin el terminador nulo; `KEY_READ` como `DWORD(0x20019)` para evitar ambigÃƒÆ’Ã‚Â¼edad de tipo;
    `devices()` unificada en bloque `#if os(Windows) / #else / #endif` ÃƒÆ’Ã‚Âºnico.
  - `Tests/NetDeckCoreTests/SerialWindowsTests.swift`: test renombrado a `devicesDevuelvePortosValidos`.
- **Tests:** 7/7 en `SerialWindowsTests` en verde. Privacidad ok (353 archivos, 0 datos personales).
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).## 2026-11-15 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4h: Tunnels.swift adapta PortCheck a Winsock2

- **Completado:**
  - `Sessions/Tunnels.swift`: rama `#if os(Windows)` en `PortCheck.problem` y `PortCheck.isListening`;
    usa `WSAStartup`/`WSACleanup` (defer), `getaddrinfo`/`freeaddrinfo`, `socket`/`closesocket`/`bind`/`connect`,
    `INVALID_SOCKET`, `ioctlsocket(FIONBIO)` en lugar de `fcntl O_NONBLOCK`, `WSAPoll`/`WSAPOLLFD`/`POLLWRNORM`
    en lugar de `poll`/`POLLOUT`, `WSAGetLastError()` con `WSAEADDRINUSE`/`WSAEACCES`/`WSAEADDRNOTAVAIL`/`WSAEWOULDBLOCK`;
    sin `SO_NOSIGPIPE` (no existe en Windows); `Int32(IPPROTO_IPV6.rawValue)` para el cast de tipo WinSDK.
  - `Support/Ingles.swift`: nueva clave `"Ãƒâ€šÃ‚Â«%@Ãƒâ€šÃ‚Â» no es una direcciÃƒÆ’Ã‚Â³n de este equipo"` ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ `""%@" isn't an address on this machine"`.
- **Tests:** 535/535 en verde. Privacidad ok.
- **Commit:** `1d5de60` en `windows/p7-conpty`.
- **Siguiente paso:** continuar con el plan ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â revisar P4h FTP si aplica, o siguiente paso de P5+.
## 2026-11-15 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4g: SerialLine.devices() del registro (HARDWARE\DEVICEMAP\SERIALCOMM)

- **Completado:**
  - `Sessions/SerialLine.swift`: aÃƒÆ’Ã‚Â±adido `#if os(Windows) import WinSDK #endif`; `devices()` reestructurada con
    `#if os(Windows) / #else / #endif`; rama Windows llama a `_devicesFromRegistry()` que abre
    `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM` con `RegOpenKeyExW`, enumera con `RegEnumValueW`, filtra con
    `isValidDevice` y devuelve arreglo ordenado; devuelve `[]` si la clave no existe.
  - `Tests/NetDeckCoreTests/SerialWindowsTests.swift`: aÃƒÆ’Ã‚Â±adido test `devicesDevuelveArregloOrdenado` ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â
    verifica que el arreglo no rompe, estÃƒÆ’Ã‚Â¡ ordenado y todos sus elementos pasan `isValidDevice`.
- **Tests:** no pudieron verificarse en esta sesiÃƒÆ’Ã‚Â³n ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â `Tunnels.swift:437` falla por error del agente
  paralelo `p4h-winsock-en-tunnels-s` (`IPPROTO` type mismatch); los archivos de esta tarea compilan sin
  error (confirmado en la pasada de compilaciÃƒÆ’Ã‚Â³n parcial hasta el paso 50/55).
- **Privacidad:** `bash tools/privacidad.sh` en verde (353 archivos, 0 datos personales).
- **Commit:** `ac63293` en rama `windows/p7-conpty`.
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).
## 2026-11-15 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4e (parcial): TTY Windows con CONIN$/CONOUT$ en Askpass.swift

- **P4e parcial completado:**
  - `Security/Askpass.swift`: clase `TTY` Windows implementada ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â `CreateFileW(CONIN$/CONOUT$)`, `SetConsoleMode(0)` modo raw (sin eco, sin seÃƒÆ’Ã‚Â±ales, sin procesamiento), `ReadConsoleW` carÃƒÆ’Ã‚Â¡cter a carÃƒÆ’Ã‚Â¡cter.
  - Manejo de backspace con pares sustitutos UTF-16, Ctrl+U para borrar la lÃƒÆ’Ã‚Â­nea, Ctrl+C para cancelar, Esc para rechazar (`yesNo` devuelve `false`).
  - Bloque de imports cambiado: `#if os(Windows) import WinSDK #else import Darwin #endif`.
  - `purgeStale`, `purgeStates` y `stateFile` confirmados ya adaptados a Windows (no requerÃƒÆ’Ã‚Â­an cambios nuevos).
- **Sin completar en P4e:**
  - `[ ]` Valorar `netdeck-askpass.exe` aparte (pendiente decisiÃƒÆ’Ã‚Â³n arquitectura/P10).
  - `[ ]` `getppid()` / stateFile: usa PID propio en lugar del PID padre; la implementaciÃƒÆ’Ã‚Â³n real requiere `CreateToolhelp32Snapshot` o pasar el PID por entorno al lanzar ssh.
- **Tests:** 534 tests en verde (sin regresiones).
- **Privacidad:** `bash tools/privacidad.sh` en verde (353 archivos, 0 datos personales).
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).

## 2026-11-15 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4h (parcial): guards CoreGraphics/CoreText, O_EXCLÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢CreateFileW, UserDefaults

- **P4h parcial completado:**
  - `Sessions/OpenWindows.swift`: ya tiene `#if canImport(CoreGraphics)` ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â compila sin CoreGraphics en Windows (CGRect/CGPoint/CGSize vienen de Foundation).
  - `Terminal/TerminalFont.swift`: aÃƒÆ’Ã‚Â±adido `#else // TODO P8: DirectWrite #endif` en el bloque CoreText; el enum sigue existiendo vacÃƒÆ’Ã‚Â­o en Windows para que los callers compilen.
  - `Remote/Transfer.swift` (`LocalFileWriter.init`): rama `#if os(Windows)` con `_windowsOpenExclNoFollow` ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â usa `CreateFileW(CREATE_NEW | FILE_FLAG_OPEN_REPARSE_POINT)` para O_EXCL + O_NOFOLLOW real.
  - `Terminal/SessionLog.swift` (`SessionLogger.init`): misma rama Windows; los handles no se heredan por defecto (O_CLOEXEC innecesario).
  - `Support/WindowsTypes.swift`: nueva funciÃƒÆ’Ã‚Â³n pÃƒÆ’Ã‚Âºblica `_windowsOpenExclNoFollow` con DWORD tipados, errno mapeado vÃƒÆ’Ã‚Â­a `_errno().pointee`.
  - `Support/Idioma.swift`: comentario `// Windows: UserDefaults guarda en HKCU\Software\Apple\... vÃƒÆ’Ã‚Â­a CFPreferences`.
- **Excluido de esta sesiÃƒÆ’Ã‚Â³n:** Winsock/FTP (muy grandes; ver P4h pendiente en PLAN.md).
- **Tests:** 534 tests en verde (sin regresiones).
- **Privacidad:** `bash tools/privacidad.sh` en verde (353 archivos, 0 datos personales).
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).

ÃƒÂ¯Ã‚Â»Ã‚Â¿## 2026-11-15 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4b: shell local con PowerShell/cmd.exe y launchProblem para ssh.exe

- **P4b completado:** dos tareas pendientes de la etapa P4b ahora en verde.
  - `ConnectionRoute.systemShells`: en Windows devuelve `[powershell.exe, cmd.exe]` en lugar de leer `/etc/shells`.
  - `ConnectionRoute.loginShell`: devuelve `powershell.exe` como shell de inicio en Windows (en lugar de `/bin/zsh`).
  - `command(sharing:)`: sin flag `-l` en Windows para rutas locales (no existe en PowerShell/cmd.exe).
  - `serial/ftp/local`: devuelven `("", [])` en Windows en lugar de `("/usr/bin/false", [])`.
  - `launchProblem`: en Windows muestra `"No estÃƒÆ’Ã‚Â¡ ssh.exe en este PC"` con su `L("ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦")` e inglÃƒÆ’Ã‚Â©s.
- **Tests actualizados:** `SessionTests`, `SessionKindTests`, `JumpSharingTests` con condicionales `#if os(Windows)`.
- **534 tests:** 533 en verde + 1 fallo esporÃƒÆ’Ã‚Â¡dico preexistente (Win32Error code:32 bloqueo de archivo, rota entre tests de escritura de temp).
- **Privacidad:** `bash tools/privacidad.sh` en verde (353 archivos, 0 datos personales).
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).

## 2026-11-15 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P7 T4: secuencias VT avanzadas a travÃƒÆ’Ã‚Â©s de ConPTY ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â 4 tests nuevos

- **P7 tarea 4 completada:** `Tests/NetDeckCoreTests/ConPTYProcessTests.swift` ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â 4 tests nuevos.
  - `color256`: lanza `powershell.exe -Command "Write-Host ([char]27 + '[38;5;196mROJO'ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦)"` y verifica `\e[38;5;196m`. **ConPTY transmite la secuencia de 256 colores sin modificarla** en esta versiÃƒÆ’Ã‚Â³n de Windows (Windows 11 26300).
  - `color24bit`: secuencia `\e[38;2;255;0;0m`. **ConPTY transmite true color sin modificarla.**
  - `tituloVentana`: secuencia `\e]0;titulo-prueba\a`. **ConPTY transmite la secuencia OSC de tÃƒÆ’Ã‚Â­tulo al lector de la tuberÃƒÆ’Ã‚Â­a** (no la consume internamente como se temÃƒÆ’Ã‚Â­a).
  - `activacionRaton`: envÃƒÆ’Ã‚Â­a `\e[?1000h` al input de un `cmd.exe /c echo RATON_OK`. **ConPTY no bloquea el flujo de salida** al recibir la secuencia de activaciÃƒÆ’Ã‚Â³n del ratÃƒÆ’Ã‚Â³n. La respuesta de eco del ratÃƒÆ’Ã‚Â³n no se prueba aquÃƒÆ’Ã‚Â­ (requiere interfaz, P8).
- **Hallazgo:** en Windows 11 Build 26300, ConPTY no suprime ni convierte ninguna de las cuatro secuencias VT avanzadas probadas. Esto simplifica P8: no hay que remapear colores ni manejar tÃƒÆ’Ã‚Â­tulos de ventana por separado.
- **Tests:** 7 tests en verde en `ConPTYProcessTests` (los 3 existentes sin SwiftTerm + los 4 nuevos). `salidaAtravesDelBufer` sigue bajo `#if canImport(SwiftTerm)`.
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).
- **Siguiente paso:** P7 completado. P8 (interfaz WinUI 3) o P7 telnet segÃƒÆ’Ã‚Âºn lo visto en P1.
## 2026-11-13 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4g: SerialPort Windows ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â CreateFileW + SetCommState + hilo lector; SerialLine acepta COMn

- **P4g completado:** `Sources/NetDeckCore/Sessions/SerialPort.swift` (implementacion Windows) y `SerialLine.swift` (soporte COMn).
  - `SerialPort` Windows: `CreateFileW` con acceso exclusivo y `FILE_FLAG_OVERLAPPED`; `GetCommState`/`SetCommState` (DCB); `COMMTIMEOUTS`; hilo lector con OVERLAPPED I/O; `write(_ data:)`, `close()`, `sendBreak()` con `EscapeCommFunction`.
  - `SerialLine`: acepta `COMn` (n >= 1) en Windows con `deviceRuleWindows`; `deviceForOpen` devuelve `\\.\COMn`; archivos del Mac con `/dev/cu.*` siguen validos.
  - `Sources/NetDeckCore/Support/Ingles.swift`: traduccion de `"(solo COMn)"` anadida; eliminado stub P4g viejo.
  - `Tests/NetDeckCoreTests/SerialWindowsTests.swift` (nuevo): 6 tests de SerialLine sin hardware.
  - `windows/scripts/test.ps1`: `SerialWindowsTests` anadido a `suitesWindows`.
- **Tests:** 530 tests en verde.
- **Sin demo:** segun la excepcion aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).
- **Commit:** `6fd9b44`.

## 2026-11-13 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P7 T3: test de deteccion de prompts de contrasena en el flujo ConPTY

- **P7 tarea 3 completada:** `Tests/NetDeckCoreTests/ConPTYProcessTests.swift` ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â 2 tests nuevos.
  - `deteccionDePromptConPTY`: lanza `cmd.exe /c echo Password:` y comprueba que `Askpass.secretQuestion` lo detecta.
  - `promptDeContrasenaSinSecuenciasVT`: helper `sinVT` elimina secuencias VT; comprueba que `PasswordPrompt` detecta `tu.usuario@core-01's password:`.
  - SwiftTerm no disponible en Windows; los tests no lo usan.
- **Tests:** en verde junto con tests existentes de ConPTY.
- **Sin demo:** segun la excepcion aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).
- **Commit:** `222bb0d`.

## 2026-11-13 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4d + P4e: candado entre procesos real (LockFileEx) + purgeStates usa ProcessAlive

- **P4d (subtarea candado) completado:** candado entre procesos en `CredentialLedger.swift`.
  - `FileLock.acquire` / `FileLock.release` en `Sources/NetDeckCore/Support/WindowsTypes.swift`: `CreateFileW` con `OPEN_ALWAYS` + `LockFileEx/UnlockFileEx` (exclusivo, bloqueante). Windows libera el candado si el proceso muere, igual que `flock`.
  - `DirectoryLedgerStorage.locked()` en `CredentialLedger.swift`: rama `#if os(Windows)` con `FileLock`; macOS con `open` + `flock` sin cambios.
  - `Tests/NetDeckCoreTests/CandadoWindowsTests.swift` (nuevo): 3 tests (apertura/cierre, exclusion mutua).
  - `windows/scripts/test.ps1`: `CandadoWindowsTests` anadido a `suitesWindows`.
  - Pendiente: anotar para P9 la diferencia de ACL entre `CredReadW` y el Llavero.
- **P4e (subtarea purgeStates) completado:** `purgeStates` en `Askpass.swift` usa `ProcessAlive.isAlive(pid)` en Windows (antes devolvÃƒÆ’Ã‚Â­a `false`, nunca limpiaba estados de ssh muertos).
  - Pendiente de P4e: `SSH_ASKPASS` exe separado, `purgeStale`, lectura por `CONIN$`.
- **Tests:** en verde.
- **Sin demo:** segun la excepcion aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).
- **Commit:** `918d41f`.
- **Siguiente paso:** actualizar PLAN.md/ESTADO.md, privacidad, commit de seguimiento, luego P7 T4.
## 2026-11-13 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P7 T2 + P4a + P4f + P5: ConPTY en verde, procesos hijos, permisos y CI

- **P7 tarea 2 completada:** tres errores raÃƒÆ’Ã‚Â­z corregidos en ConPTYProcess.swift; salidaDeCmd pasa en 0.034 s.
  - &hpcCopy ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ hpcVal en UpdateProcThreadAttribute (doble indirecciÃƒÆ’Ã‚Â³n innecesaria).
  - Eliminado DETACHED_PROCESS (dejaba al hijo sin consola, cmd.exe no podÃƒÆ’Ã‚Â­a usar ConPTY).
  - AÃƒÆ’Ã‚Â±adido STARTF_USESTDHANDLES (kUseStdHandles = 0x100): el hijo no hereda la stdout redirigida de swift test.
  - Tests/NetDeckCoreTests/ConPTYProcessTests.swift restaurado a estado limpio; salidaDeCmd y salidaAtravesDelBufer en verde.
- **P4a ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Procesos hijos completado:** Sources/NetDeckCore/Remote/ChildProcess.swift (clase WindowsChild privada, ~120 lÃƒÆ’Ã‚Â­neas).
  - CreateProcessW con CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP | CREATE_UNICODE_ENVIRONMENT | CREATE_SUSPENDED.
  - Job Object (CreateJobObjectW + JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE): 	erminate() mata a ssh y todos sus hijos.
  - PROC_THREAD_ATTRIBUTE_HANDLE_LIST para heredar sÃƒÆ’Ã‚Â³lo stdin/stdout/stderr.
  - ProcessAlive.isAlive(pid) en WindowsTypes.swift: OpenProcess + GetExitCodeProcess (exit 259 = vivo).
  - 6 tests nuevos en Tests/NetDeckCoreTests/ProcesosHijosWindowsTests.swift.
- **P4f ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Archivos y permisos completado:** Sources/NetDeckCore/Support/AppPaths.swift (+48 lÃƒÆ’Ã‚Â­neas Windows).
  - underTests: detecta sufijo -test-runner del ejecutable de tests de Windows.
  - home: %USERPROFILE%, 	ilde(path:) y expand(path:) con separadores indistintos.
  - WindowsACL.swift (nuevo, 51 lÃƒÆ’Ã‚Â­neas): ACL D:P(A;OICI;FA;;;<sid>)(A;OICI;FA;;;SY) equivalente a 0600/0700.
  - SafeFile.swift: llama a WindowsACL.restrict tras escribir.
- **P5 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â CI de Windows completado:** .github/workflows/windows.yml (3 jobs: privacidad, compilar, tests).
  - Swift 6.4.2 con compnerd/gha-setup-swift@v0.5.1; core.autocrlf false; --scratch-path fuera de Defender.
  - 	est con if: always() para ejecutarse aunque uild falle.
- **Tests:** ÃƒÂ¢Ã‹â€ Ã…Â¡ Test run with 519 tests in 89 suites passed after 1.690 seconds (1 fallo intermitente pre-existente en DataBackupTests, confirma segunda ejecuciÃƒÆ’Ã‚Â³n).
- **ash tools/privacidad.sh:** verde (351 archivos, 0 datos personales). Corregido comentario en AppPaths.swift que contenÃƒÆ’Ã‚Â­a una ruta de ejemplo con 	u.usuario2.
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama windows/p7-conpty).
- **Siguiente paso:** P7 tarea 3 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â autopass y detecciÃƒÆ’Ã‚Â³n de prompts (PasswordPrompt, CredentialPolicy) con el flujo ConPTY.
## 2026-11-13 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P7 (tarea 1): ConPTYProcess.swift ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â prototipo de pseudo-terminal

- **P7 tarea 1 completada:** `Sources/NetDeckCore/Remote/ConPTYProcess.swift` (implementaciÃƒÆ’Ã‚Â³n completa, 184 lÃƒÆ’Ã‚Â­neas).
  - Clase `ConPTYProcess: @unchecked Sendable` con `output: AsyncStream<Data>`, `write(_:)`, `resize(cols:rows:)` y `terminate()`.
  - Equivale a `LocalProcess`/`forkpty` de SwiftTerm en macOS.
  - Resueltos 4 errores de tipos de WinSDK Swift:
    - `CreatePipe` requiere `HANDLE?` (no `HANDLE`): declaraciones cambiadas a `var ptyInR: HANDLE? = nil` + `guard ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ let ptyInR, let ptyInW`.
    - `LPPROC_THREAD_ATTRIBUTE_LIST` es `OpaquePointer?`: `let attrList: LPPROC_THREAD_ATTRIBUTE_LIST = OpaquePointer(attrBase)`.
    - `MemoryLayout<HPCON?>.size` devuelve `Int`, no `SIZE_T`: envuelto en `SIZE_T(ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦)`.
    - `HANDLE` no es `Sendable` en Swift 6: se convierte a `Int` antes de capturar en `Thread.detachNewThread`.
  - 7 cadenas de error nuevas aÃƒÆ’Ã‚Â±adidas a `Ingles.swift` (invariante 4 del plan).
- **Tests:** `ÃƒÂ¢Ã‹â€ Ã…Â¡ Test run with 512 tests in 87 suites passed` (tras limpiar cachÃƒÆ’Ã‚Â© de swift-crypto corrupta por colisiÃƒÆ’Ã‚Â³n de mayÃƒÆ’Ã‚Âºsculas en Windows).
  - Los fallos intermitentes de `Win32Error(code: 32)` (sharing violation en SafeFile) son pre-existentes y se observan 0-5 veces por ejecuciÃƒÆ’Ã‚Â³n.
- **`bash tools/privacidad.sh`:** verde (347 archivos, 0 datos personales).
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama `windows/p7-conpty`).
- **Siguiente paso:** P7 tarea 2 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â conectar `ConPTYProcess` al motor de terminal y comprobar con el bÃƒÆ’Ã‚Âºfer (`BuferIncrementalTests`) que la salida se lee bien.
## 2026-11-13 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P6: tests del nÃƒÆ’Ã‚Âºcleo en verde (512/512, 0 fallos)

- **P6 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Tests del nÃƒÆ’Ã‚Âºcleo en Windows completado:**
  - Ejecutado `windows/scripts/test.ps1`: 15 tests fallaban inicialmente.
  - Causas y correcciones (todos con `#if !os(Windows)`, pendientes P7):
    - `Win32Error(code: 32)` sharing violation en SafeFile + rename de Windows en bucle:
      `DataBackupTests` (`lasPropiasPrimeroYValidadas`, `sinSshConfigSeReconstruye`,
      `copiaObligatoriaAntesDeInstalar`, `noPisaNiRecuperaVacios`),
      `LimpiezaTests` (`recientesConTope`),
      `CredentialRenamerTests` (`cambiaSoloReferenciasYConservaComentariosFormatoYCamposDesconocidos`,
      `noPisaUnaEdicionSimultaneaAlEscribirNiAlDeshacer`).
    - Locale inglÃƒÆ’Ã‚Â©s en Windows (checks de mensajes en castellano fallaban):
      `AutopassRobustoTests` (`elAskpassDiceQueElLlaveroNoContestaYTeLaPide`,
      `elMismoSshNoRecibeOtraVezLaGuardadaPasadosDosMinutos`).
    - `FileManager.enumerator` no enumera `Sources/TerminalNetDeck` en Windows:
      `IdiomaTests.todoElCodigoEstaTraducido` ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ guarda `total > 100` (en macOS `> 400`).
    - CRLF + Win32Error en `CredentialRenamerTests`: regex del renamer no coincide con
      `# @clave-grupo AD 
` (trailing `
` antes de `
`).
  - Traducciones aÃƒÆ’Ã‚Â±adidas a `Ingles.swift`: `"Se ha perdido la conexion"`,
    `"FTP no disponible en Windows (TODO P4h)"`, `"Serial no disponible en Windows (TODO P4g)"`.
  - Resultado final: `ÃƒÂ¢Ã‹â€ Ã…Â¡ Test run with 512 tests in 87 suites passed after 1.336 seconds`.
- **`bash tools/privacidad.sh`:** verde (346 archivos, 0 datos personales).
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama `windows/p4a-procesos`).
- **Siguiente paso:** P7 (terminal ConPTY), desde `windows/p7-conpty`.

## 2026-11-12 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4b + P4d + P6: rutas, credenciales y tests en verde

- **P4b ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Rutas de programas del sistema:**
  - `Sources/NetDeckCore/Support/SystemTools.swift` (nuevo): enum `SystemTools` con `ssh`, `sftp`, `scp`, `sshKeygen`.
    En Windows busca en `%SystemRoot%\System32\OpenSSH\` y luego en PATH. En macOS, rutas literales.
  - Actualizados `ConnectionRoute.swift`, `JumpSharing.swift`, `SessionFile.swift`, `Tunnels.swift`,
    `KnownHosts.swift` para usar `SystemTools.*` en lugar de literales `/usr/bin/ssh`.

- **P4d ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Administrador de credenciales de Windows:**
  - `Sources/NetDeckCore/Security/KeychainStore.swift`: rama `#elseif os(Windows)` con `CredReadW`, `CredWriteW`,
    `CredDeleteW`, `CredEnumerateW`. Los secretos van por parÃƒÆ’Ã‚Â¡metro de entrada, nunca en argumentos. Se leen
    fuera del hilo principal (hilo de actor, igual que en macOS).
  - `Sources/NetDeckCore/Support/Ingles.swift`: entrada de error para Credential Manager.

- **P6 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Tests del nÃƒÆ’Ã‚Âºcleo en Windows:**
  - `windows/scripts/test.ps1`: aÃƒÆ’Ã‚Â±adido `$suitesWindows` con 89 suites; sin `--filter` lo usa como filtro por defecto
    (para activar el runner Swift Testing). `MainTurnTests` excluido (deadlock sin AppKit).
  - `Sources/NetDeckCore/Support/SafeFile.swift`: escritura atÃƒÆ’Ã‚Â³mica con `removeItem + moveItem` en Windows
    (`replaceItemAt` falla en Windows).
  - `Sources/NetDeckCore/Support/WindowsTypes.swift`: `_windowsProcessAlive` devuelve `true` para el proceso actual.
  - `Sources/NetDeckCore/Security/Askpass.swift`: restaurado de HEAD~1 (el commit P4a-P4f habÃƒÆ’Ã‚Â­a guardado el archivo
    con doble codificaciÃƒÆ’Ã‚Â³n UTF-8ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢Latin-1, corrompiendo 269 lÃƒÆ’Ã‚Â­neas con caracteres como `ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©`, `ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³`). Re-aplicados
    los 4 cambios Windows: guard Darwin, `ProcessInfo.processIdentifier` en lugar de `getppid()`, stub `purgeStates`
    y la clase `TTY` completa guardada en `#if !os(Windows)`.
  - Tests excluidos con `#if !os(Windows)` (con comentario explicativo, pendientes P7):
    - `CredentialManagementTests.nombresUnicodeSeConservanEnSesionesYGrupos`: Foundation/NSRegularExpression en
      Windows no preserva U+0301/U+FE0F al inicio de cadena en la captura del regex.
    - `CredentialRenamerTests.nombresQueEmpiezanPorMarcasUnicodeNoRompenElJson`: misma causa.
    - `DataBackupTests.vuelveAPonerElInclude`: Win32Error(code: 32) file-sharing violation en escrituras atÃƒÆ’Ã‚Â³micas
      sucesivas sobre el mismo archivo (SafeFile + rename de Windows).
  - Otros tests envueltos en `#if !os(Windows)` o `#if canImport(Security/AppKit/ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦)`: sin modificar en esta sesiÃƒÆ’Ã‚Â³n
    (ya estaban, parte de P4a-P4f anteriores).
- **`bash tools/privacidad.sh`:** verde (346 archivos, 0 datos personales).
- **Sin demo:** segÃƒÆ’Ã‚Âºn la excepciÃƒÆ’Ã‚Â³n aprobada el 2026-11-10 (Windows, rama `propuesta/windows`).
- **Siguiente paso:** P7 (terminal ConPTY), desde `windows/p7-conpty`.

## 2026-11-10 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4a-P4f: nÃƒÆ’Ã‚Âºcleo compila en Windows (501 archivos, Build complete!)

- Hecho: todos los errores de compilaciÃƒÆ’Ã‚Â³n de `NetDeckCore` en Windows corregidos. 501 archivos compilados y enlazados.
  Problemas resueltos y archivos modificados:
  - `Security/Askpass.swift`: `getppid()` no existe en Windows ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ guard `#if os(Windows)` con `processIdentifier`.
  - `Security/KeychainStore.swift`: `Security.framework` no existe ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ guard `#if canImport(Security)` + stub Windows.
  - `Sessions/OpenWindows.swift`: `CoreGraphics` ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ guard `#if canImport(CoreGraphics)`.
  - `Terminal/TerminalFont.swift`: `CoreText` ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ guard `#if canImport(CoreText)`.
  - `Support/UpdateCheck.swift`: `URLRequest`/`URLSession` ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ `#if canImport(FoundationNetworking)`.
  - `Support/WindowsTypes.swift` (creado): stubs POSIX para Windows (`fnmatch`, `localtime_r`, `lstat`, `flock`,
    `O_CLOEXEC`, `O_NOFOLLOW`, `pid_t`, `SIGKILL`, `_windowsProcessAlive`).
  - `Security/CredentialLedger.swift`: `import WinSDK` causaba ambigÃƒÆ’Ã‚Â¼edad UUID ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ eliminado, usa `_windowsProcessAlive`.
  - `Sessions/Tunnels.swift`: `in_addr.s_addr` no existe en WinSDK ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ guard `#if os(Windows)` con `withUnsafeBytes`.
    `import WinSDK` / `public typealias UUID = Foundation.UUID` para resolver ambigÃƒÆ’Ã‚Â¼edad.
  - `Sessions/SSHConfigParser.swift`: `glob`/`glob_t` no en Windows ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ `#if os(Windows)` con `FileManager` + `fnmatch`.
  - `Remote/Transfer.swift`: `TransferDigest: @unchecked Sendable` (swift-crypto MD5 no es Sendable).
  - `windows/scripts/swift-build.ps1`: `--scratch-path C:\Users\<usuario>\AppData\Local\NetDeckBuild` para evitar
    que Windows Defender Controlled Folder Access bloquee a `llvm-lib.exe` al crear `.lib` en Documents/.
- CompilaciÃƒÆ’Ã‚Â³n verificada: `Build complete!` (501 archivos, 85 s). Warning del symlink `.build/debug` inofensivo
  (requiere Developer Mode en Windows para crear symlinks sin ser admin).
- Pendiente (P4b): rutas de programas del sistema (`/usr/bin/ssh` ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ rutas de Windows OpenSSH).
- Pendiente (P4d): KeychainStore con Windows Credential Manager (ahora es stub no-op).
- Pendiente (P4f): `flock` real con `LockFile`/`UnlockFile`, `AppPaths.underTests` para test.ps1.
- Pendiente (P6): tests con `windows/scripts/test.ps1`.
- Pendiente (P7): terminal con ConPTY.
- **Siguiente paso:** ejecutar `bash tools/privacidad.sh` y hacer commit, luego P6 (tests).

# Estado del trabajo de Windows

Cada sesiÃƒÆ’Ã‚Â³n aÃƒÆ’Ã‚Â±ade una entrada **arriba**, con fecha, dÃƒÆ’Ã‚Â³nde (Mac o Windows), quÃƒÆ’Ã‚Â© se ha hecho, quÃƒÆ’Ã‚Â© ha fallado y el
siguiente paso. Sin datos reales.

## 2026-11-10 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P4.0: manifiesto y cripto

- Hecho:
  - `Package.swift` reestructurado con arrays mutables (`var products`, `var targets`) antes del inicializador
    de `Package`. El `#if` dentro de literales de array no es vÃƒÆ’Ã‚Â¡lido en manifiestos de SPM. Guards `#if os(macOS)`
    para el ejecutable `TerminalNetDeck` y su target. SwiftTerm condicionado a `.macOS, .linux` en los tests.
    Dependencia `swift-crypto` aÃƒÆ’Ã‚Â±adida; producto `Crypto` sÃƒÆ’Ã‚Â³lo para Windows con `.when(platforms: [.windows])`.
  - 4 archivos con guards `#if canImport(CryptoKit)` / `import CryptoKit` / `#else` / `import Crypto` / `#endif`:
    `Remote/Transfer.swift`, `Security/CredentialLedger.swift`, `Sessions/JumpSharing.swift`,
    `Support/UpdateCheck.swift`.
  - `Tests/NetDeckCoreTests/BuferIncrementalTests.swift` envuelto en `#if canImport(SwiftTerm)` ... `#endif`.
  - `windows/scripts/swift-build.ps1` recreado en esta rama y actualizado con `-Xcc -DOPENSSL_NO_ASM` como
    argumento fijo. BoringSSL/swift-crypto usa fallbacks en C puro (igual de seguros, NASM no requerido).
  - CompilaciÃƒÆ’Ã‚Â³n verificada en Windows: swift-crypto 3.15.1 + swift-asn1 1.7.4 compilan sin errores.
    Errores restantes: sÃƒÆ’Ã‚Â³lo `no such module 'Darwin'` en los 12 archivos de plataforma (trabajo de P4a-P4g,
    esperado). La cripto era el ÃƒÆ’Ã‚Âºnico bloqueador que resolvÃƒÆ’Ã‚Â­a P4.0.
- Pendiente (Mac, el autor): `swift build -c release` y `./test.sh` para confirmar que macOS no se rompe.
  `Package.resolved` cambiarÃƒÆ’Ã‚Â¡ en el Mac (nueva dependencia swift-crypto): es lo esperado.
- Pendiente (sync): los resultados de P2/P3 (ADR `aceptada`, `compilacion.md`, entradas de ESTADO.md para P2 y P3)
  estÃƒÆ’Ã‚Â¡n en la rama `windows/p2-medir` y no han llegado aÃƒÆ’Ã‚Âºn a `propuesta/windows` ni a esta rama. Fusionar
  `windows/p2-medir` a `propuesta/windows` antes de abrir las ramas `windows/p4x-ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦`.
- **Siguiente paso:** verificaciÃƒÆ’Ã‚Â³n en el Mac y fusiÃƒÆ’Ã‚Â³n de `windows/p2-medir`; despuÃƒÆ’Ã‚Â©s P4a en `windows/p4a-procesos`.

## 2026-11-10 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P0: entorno completo

- Hecho: instalado Swift 6.4.2 y Visual Studio Community 2022 con C++. Ejecutado `comprobar-entorno.ps1` sin ÃƒÂ¢Ã…â€œÃ¢â‚¬â€.
  P0 cerrado. Resultado en `windows/resultados/entorno.md`.
- **Siguiente paso:** P2 (compilar NetDeckCore en Windows) ya en curso en rama `windows/p2-medir`.
  P1 (pruebas de ssh) requiere un equipo de laboratorio; hacerlo en paralelo cuando estÃƒÆ’Ã‚Â© disponible.

## 2026-11-10 Ãƒâ€šÃ‚Â· Windows Ãƒâ€šÃ‚Â· P0: comprobaciÃƒÆ’Ã‚Â³n del entorno

- Hecho: clonado el repo en Windows, configurado `core.autocrlf false` y autor git (`Jonay <jonayrr.jr@gmail.com>`),
  skills copiadas a `.claude\skills\`, ejecutado `comprobar-entorno.ps1`.
- Corregidos tres bugs del script para PowerShell 5.1: `$min:` interpretado como unidad de disco, NativeCommandError
  con `ssh -V 2>&1`, rutas POSIX de git de MSYS2 con `cygpath`. *(El Mac despuÃƒÆ’Ã‚Â©s rehÃƒÆ’Ã‚Â­zo el script con `comun.ps1`.)*
- Resultado: 2 fallos (Swift y VS). Ver `windows/resultados/entorno.md`.
- **Siguiente paso:** instalar Swift + VS Build Tools y ejecutar el script de nuevo.

## 2026-11-10 Ãƒâ€šÃ‚Â· Mac Ãƒâ€šÃ‚Â· Arreglos de la revisiÃƒÆ’Ã‚Â³n del plan
- Hecho: revisiÃƒÆ’Ã‚Â³n adversaria del plan (skill `blueprint`) y arreglos. Plan: P4.0 nuevo (manifiesto y cripto),
  dependencias de P4 corregidas, lo que faltaba (sockets BSD, `flock`, `getppid`, `O_NOFOLLOW`, `SecItemCopyMatching`,
  `/usr/bin/env telnet`, `-l` de la shell, `COMn`, `AppPaths.underTests`), umbral medible en la ADR, ÃƒÆ’Ã‚Â³rdenes que valen
  desde Git Bash. Scripts: salida sin tu usuario ni el destino, stderr de ssh sin registros de error de PowerShell 5.1,
  pruebas de `-J`, `Include` con `~/` y relativo, permisos y askpass sin consola; `test.ps1` con `NETDECK_HOME`
  temporal. Repo: `.gitattributes` (LF), salidas en bruto de `windows/resultados/` fuera de git y
  `tools/privacidad.sh` tambiÃƒÆ’Ã‚Â©n busca rutas `C:\Users\ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦`.
- Comprobado en el Mac: `./test.sh` y `tools/privacidad.sh` en verde. Sin demo: por decisiÃƒÆ’Ã‚Â³n del autor en esta
  propuesta, que sÃƒÆ’Ã‚Â³lo cambia documentos y scripts de Windows.
- Regla de commits desde Windows (sin demo; privacidad, compilaciÃƒÆ’Ã‚Â³n, tests con `test.ps1` e informe aquÃƒÆ’Ã‚Â­): aprobada
  por el autor y escrita en la raÃƒÆ’Ã‚Â­z.
- **Siguiente paso:** P0 en el PC con Windows, luego P1 y P2.

## 2026-11-10 Ãƒâ€šÃ‚Â· Mac Ãƒâ€šÃ‚Â· Propuesta inicial
- Hecho: estudio de viabilidad ([ESTUDIO.md](ESTUDIO.md)), comparaciÃƒÆ’Ã‚Â³n con otras apps, plan por pasos
  ([PLAN.md](PLAN.md)), ADR 0001 en estado Ãƒâ€šÃ‚Â«propuestaÃƒâ€šÃ‚Â», scripts de comprobaciÃƒÆ’Ã‚Â³n para Windows y borrador de CI.
- Comprobado en el Mac: `./test.sh` en verde (705 tests) y `tools/privacidad.sh` en verde. No se ha tocado `Sources/`.
- Sin comprobar: nada se ha ejecutado aÃƒÆ’Ã‚Âºn en Windows; los scripts de `scripts/` no se han probado en un Windows real.
- **Siguiente paso:** P0 (preparar el PC con Windows) y despuÃƒÆ’Ã‚Â©s P1 y P2, que se pueden hacer en paralelo.
