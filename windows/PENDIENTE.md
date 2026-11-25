# Pendientes de Windows (revisión desde el Mac)

Lista de trabajo para la sesión de Windows, por prioridad. Salió de la revisión del PR #7 desde el Mac del 24-11-2026
(agentes de lectura y de implementación). Qué se hizo y cómo se verificó, en `windows/ESTADO.md`; las reglas de paridad con
macOS, en `docs/agentes/paridad.md`. Marca aquí (o borra la línea) lo que cierres y apúntalo en `ESTADO.md`. Sin datos reales.

**Estado a 25-11:** la compilación de la revisión del Mac y los 557 tests están verificados en Windows, y la CI del PR en verde.
De la sección C ya están hechos: C10 (primera parte: tareas fuera del hilo de WinUI en `EdicionRemota`) y la prueba a mano de
MultiExec con órdenes peligrosas. El resto sigue abierto.

### A. Hecho en el Mac (ya compilado y probado en Windows el 25-11; se deja como referencia)
Archivos tocados que sólo compilan en Windows:
- `Support/SafeFile.swift` (`replace` con MoveFileExW + reintentos, `write` con reintentos), `Support/WindowsTypes.swift` (`kill`), `Support/SystemTools.swift`
  (`locateWindows`, `telnet`), `Update/UpdateChecker.swift` (`InstallerLock`, `allowUnsigned` sólo DEBUG), `Terminal/SessionLog.swift` (ACL),
  `Sessions/SessionManager.swift` (`requireSafeJump`), `Sessions/ConnectionRoute.swift` (telnet.exe), `Remote/ConPTYProcess.swift` (`write`).
- App: `EdicionRemota.swift` (copia local por id, se borra al parar), `NetDeckWindows.swift` (`deleteProfile` con `archivoEditable()`, `confirmMultiExec` con
  confirmación de órdenes peligrosas, ruta del ssh_config con `~`), `PanelAjustes.swift`.
- CI: `.github/workflows/windows.yml` sin `continue-on-error`, runner `windows-2022` (con `windows-latest` fallaba `STL1000: expected Clang 22 or newer`; los jobs ya
  estaban en rojo y no se veía). Si el primer run sigue rojo, es un fallo real: léelo.
- Pruebas a ejecutar a mano: borrar una sesión (¿el archivo queda intacto si falla?), MultiExec «Enviar a todas» con `reload` (¿pide confirmar?), telnet directo
  (¿arranca telnet.exe? Es una característica opcional de Windows), registro de sesión en una carpeta ajena (¿ACL sólo tú+SYSTEM?), actualización con MSI sin firma
  (¿se rechaza?), editar dos archivos remotos con el mismo nombre.

### B. Decisiones tomadas (con su porqué)
- **D1** `SystemTools.locate`: sólo System32\OpenSSH y, si falta, PATH dentro de SystemRoot/Program Files (decidido por el autor). Quien tenga ssh en otra ruta verá «No está ssh.exe».
- **D2** `Highlighter` y escapes de reposicionamiento (CUP/CUF) de ConPTY: NO se toca todavía. Es una hipótesis (en el banco del Mac, con el volcado «repintado» simulado, IOS perdía
  37 trozos de color y XR 13). Hace falta un volcado REAL de ConPTY: en Windows graba los bytes crudos de `cls` y de un redimensionado en una pestaña ssh a un equipo de pruebas y guárdalos
  en `Tests/` como fixture sin datos reales. Con eso el Mac parchea `Highlighter.line()` (separador para los CSI que no son SGR) y hace la pasada de demo, porque cambia código de macOS.
- **D3** `DangerousCommands` (compartido con macOS): sin ampliar hasta pasar `netdeck-revisor-red` y la demo en el Mac. Candidatas: `ip access-group X in`, `vrf forwarding X`,
  `switchport mode access`, `no neighbor X activate`, `no network …`, `install add … activate`, `request platform software package install`. Las de PowerShell/cmd NO valen la pena:
  las pestañas locales ya no pasan por esa comprobación.
- **D4** `Package.swift`: `swift-crypto` seguirá declarado para todas las plataformas (condicionarlo cambia `Package.resolved` según el equipo y ensucia macOS).
- **D5** `windows/ci/windows-release.yml` (borrador): antes de activarlo, `permissions: contents: read` + `persist-credentials: false` en el checkout, un segundo job con `contents: write` que sólo
  baje el artefacto y suba la Release (el `.sha256` lo sube el mismo job que el `.msi`: quien comprometa una acción puede cambiar los dos), y acciones (`gha-setup-swift`, setup-dotnet, checkout…) fijadas por SHA.
- **D6** Tests desactivados con «pendiente P7»: no se reactivan a ciegas. Orden en Windows: (1) `test.ps1 --no-parallel` sin los `#if !os(Windows)`; (2) si siguen con error 32, Procmon filtrando
  `SHARING VIOLATION` (¿ssh.exe o MsMpEng/SearchProtocolHost?); (3) causa probable: `Data.write(.atomic)` deja el temporal heredable y un `Foundation.Process` lanzado a la vez lo hereda
  (CreateProcessW con bInheritHandles sin lista). Arreglo (a): `SafeFile.write` con temporal por `CreateFileW` no heredable (share READ|WRITE|DELETE) + `SafeFile.replace`; (b) lanzar `ssh -G`
  (`SessionFile.sshCheck`), `KnownHosts` (2) y `Tunnels` con el lanzador de `ChildProcess` (HANDLE_LIST). Cuenta los reintentos de `replace`/`write` en DebugLog para no esconder el problema.
  `copiaObligatoriaAntesDeInstalar` e `ilegibleEsError` usan chmod 0o000: en Windows no impide leer; simular con `CreateFileW(dwShareMode=0)`.

### C. Pendiente de código en Windows (por prioridad)
**Seguridad / datos**
- C1 Botón de modo `.clave`: la contraseña se escribe en un `TextBox` y se ve (`PanelBotones.swift:17,117,127`). Usar `PasswordBox` en ese modo y quitar saltos de línea (el Mac usa `SecureField`).
- C2 `FileLock.acquire` nil → `CredentialLedger.locked` sigue SIN candado (`CredentialLedger.swift:~329`): registrar y tratar la ausencia de candado como «no escribir sola» (el bloqueo de 15 min puede fallar).
- C3 `WindowsACL.restrict` falla en silencio (`SafeFile.swift`, `SessionFile.swift`, `AppPaths.ensure`, `repairPermissions`): `ErrorLog.warning` una vez con `GetLastError`; las copias `.original`/`.anterior` de `SafeFile.backup` nunca se restringen.
- C4 `ConPTYProcess` y túneles sin Job Object: `terminate()` sólo mata el ssh raíz; sobreviven askpass y ProxyCommand (`ConPTYProcess.swift:~141`, `Tunnels.swift:~602`). Reutilizar `WindowsChild`. `commandLine` de ConPTY es otra copia y no entrecomilla tabuladores.
- C5 `PestanaTerminal.swift:70-72` y `nuevaVentana`: ruta del askpass desde `CommandLine.arguments[0]`; usar `GetModuleFileNameW`.
- C6 Rutas absolutas a `%SystemRoot%\System32` para `powershell.exe` (`NetDeckWindows.wxs:70,72`, `detectar-runtime.js:8`) y `msiexec.exe` (`UpdateChecker.launchInstaller`).
- C7 Actualizador: fijar el firmante Authenticode y comparar la versión del MSI con el tag; liberar `InstallerLock` y la carpeta temporal tras lanzar; distinguir «UAC cancelado» de «no se pudo lanzar»;
  `lastUpdateCheck` se guarda aunque falle la comprobación (`NetDeckWindows.swift:~2367`).
- C8 `TerminalEnvironment`: con «Enviar el idioma» activo se heredan `SSH_ASKPASS`/`GIT_SSH` (y variantes de mayúsculas); quitarlas siempre en la rama Windows.
- C9 `NETDECK_SFTP_SERVER`, `NETDECK_UPDATE_FAKE`, `NETDECK_ASISTENTE`, `NETDECK_TEMAS` y `NETDECK_DESKTOP_DEMO` (apaga el askpass): acotarlos con `#if DEBUG`.

**Fiabilidad**
- C10 `EdicionRemota`: tareas fuera del hilo de WinUI (`setEstado`/`reloadLista` desde `Task` sin `enqueue`: riesgo RPC_E_WRONG_THREAD); `lastMod` nil deja de vigilar para siempre; la subida sobrescribe sin comprobar si el remoto cambió.
- C11 FTP: `recv`/`WSAPoll` con error devuelven nil como «fin normal» (un LIST puede salir truncado) y el canal de datos no tiene timeout (`FTPClient.swift:~274,282`).
- C12 `persistirSesiones` y `deleteProfile` guardan en síncrono (`ssh -G`, hasta `checkTimeout`) en el hilo de UI; usar `saveInBackground` como el Mac. `ImportadorSesiones` lee la carpeta entera en el hilo de UI.
- C13 Resaltado en el hilo de WinUI (`PestanaTerminal.swift:~107`): pasarlo a una cola serial como `netdeck.salida` del Mac (3-8 ms por línea larga medido en macOS).
- C14 Mensajes engañosos en `ExploradorSFTP.swift` (498-527, 549): si `list` falla tras una operación buena se dice «No se puede…»; `try?` de `SelectorArchivos.abrir` (562, `NetDeckWindows.swift:432`); botones.txt ilegible deja la barra vacía sin aviso (`:268`);
  `print(error…)` (`:768`) → `ErrorLog`. En todo el cliente Windows no hay ninguna llamada a `ErrorLog`.
- C15 Líneas partidas entre dos lecturas del `Highlighter` y OSC de título de más de 64 B (ambos también en macOS; ver D2).

**Textos**
- C16 15 claves del asistente sin inglés (`AsistenteInicio.swift` 293, 298, 376, 397, 425, 428, 429, 439, 445, 557-560) y `PestanaTerminal.swift:62` (motivo de SerialPort). `IdiomaTests` sólo recorre `Sources/TerminalNetDeck` y `Sources/NetDeckCore`: añadir `windows/Desktop/Sources`.
- C17 El texto de Ajustes dice que el pegado «se pega entero» (`PanelAjustes.swift:~1238`) y el código usa `SafePaster` línea a línea.

### D. Tests (de la revisión de cobertura)
Mover fuera de `#if os(Windows)` para probarla en el Mac: `commandLine`/`quoted`/`windowsEnvironmentBlock` (`ChildProcess.swift`), `UpdateChecker.candidate/checksum/isAllowedDownload/safeFileName` y los
layouts WINTRUST (16/32/88), `AppPaths.tilde` con rutas Windows, `FTPClient.windowsListingLines`, `SerialLine.deviceRuleWindows/deviceForOpen`, `launchProblem`/`systemShells`.
Tests que faltan: ACL con SID exacto + flag PROTECTED + herencia de carpeta (los actuales hacen `guard restrict else return` y pasan sin comprobar); `replace` falla sin tocar `url`; `FileLock` entre procesos; `KeychainStore`
(unicode, vacío, límite de 2560 B del blob, no mezclar servicios); FTP LIST/pasivo. Desactivados que ocultan bugs: `CredentialRenamerTests` Unicode combinante (`:48`) y `CredentialManagementTests:8`,
`AskpassRechazosTests:225` (grupo entero), `SessionKindTests:70/82` y `SessionFileTests:91` (reescribir con `SystemTools`), `AutopassRobustoTests` (se quitaron `#expect` de mensajes), `IdiomaTests:59` (mínimo 400 → 100).

### E. Paridad con el Mac («exactamente igual»)
El cuerpo del PR tenía errores: los modos de botón son los MISMOS que en el Mac (run, type, pass, clave, login, session); importar `.tema` SÍ existe; MD5 existe a medias («Calcular MD5»); `ButtonFile.merge/render/renameGroup/moveGroup`,
`SessionExport`, `OpenWindows`, `GroupTree`, `JumpBatchRunner`, `MacroLibrary`, `TunnelLibrary` ya están en NetDeckCore: sólo falta la interfaz. Las ~15 claves sin inglés son 15 de 664.
Falta de verdad (interfaz, B): menú contextual del terminal (clic derecho), selección por palabra/línea, reporte de ratón (vim/tmux/mc), reabrir pestañas y ventanas, posición de ventana, aviso al cerrar con conexiones,
atajo cerrar ventana, pantalla de bienvenida y aviso de salida nueva, suavizado de fuente, gestión de grupos (renombrar, quitar, contraseña de grupo, subir/bajar), exportar sesiones JSON/CSV, importar/exportar botones.txt,
exportar `.tema`, duplicar túnel/macro y subir/bajar pasos, SFTP (selección múltiple, arrastrar y soltar, cola, filtro, ocultos, «Enviar a…», `verifyTransfers`), editor de resaltado con vista previa, efecto CRT, ruta del ssh_config editable,
detección de alto contraste de Windows (el Mac usa `Theme.solid`), Jump List. «Nueva ventana» lanza otro proceso: no comparten estado ni `moveTab` y escriben a la vez los mismos archivos (a verificar).
Ocho extracciones baratas a NetDeckCore con tests en el Mac (hacerlas primero, luego la interfaz): `MacroReport/PasteReport.summary`, operaciones de grupo en `SessionFile` (renameGroup/removeGroup/setGroupCredential),
`ButtonImport`, `ButtonPlan.make` (Windows hoy escribe la contraseña a mano en `.pass`/`.login` en vez de `InputScript.login` y la política de `CredentialLedger`), `TabStrip<ID>`, `HighlightSetup`, `OpenTabsStore` + `CloseGuard`,
`Macro.copy`/`Tunnel.copy`/`MacroSteps.move`. Luego: `RemoteListing`, `TransferJob/TransferCenter`, `SavedList.jumpList`. Cada una deja el Mac igual y exige `./test.sh` + demo allí.

### F. Antes de fusionar a main
- Pasada completa en el Mac (`./test.sh` + `tools/verificar_demo.sh`): `./test.sh` ya está en verde con estos cambios; falta la demo (la hace el autor).
- Instalación en máquina limpia sin Windows App Runtime + asistente en el primer arranque del MSI.
- CI de Windows en verde de verdad (ver A) y decidir si `Privacidad` es el único check obligatorio (el filtro `paths` deja PRs sin `build`/`test`).
- `windows/ESTADO.md` tiene mojibake en varias líneas; `windows/scripts/desktop.ps1` y `windows/installer/preparar-instalador.ps1` llevan acentos sin BOM (PowerShell 5.1 los leería mal).
- PR #6 (borrador «Propuesta») sigue abierto: ciérralo o fusiónalo cuando el #7 lo sustituya.
