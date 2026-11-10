# Estudio de viabilidad: Terminal NetDeck en Windows

Hecho el 2026-11-10 sobre `main` en `5e62a85` (1.0.0), leyendo el código desde un Mac. **No se ha compilado nada
para Windows**: en el Mac no había un SDK de Swift para Windows. Lo que dice este documento sobre Windows sale de la
lectura del código y de lo que se sabe de la plataforma; los pasos P1 y P2 del [plan](PLAN.md) lo comprueban de verdad.

## Conclusión

Se puede, pero es una app nueva para Windows, no una adaptación. La interfaz (`Sources/TerminalNetDeck`, unas 17 000
líneas de SwiftUI y AppKit) hay que rehacerla entera. El núcleo (`Sources/NetDeckCore`, otras 17 000) se aprovecha en
buena parte, y sus 705 tests sirven de especificación para comprobar que en Windows se comporta igual.

## Qué se aprovecha (lógica pura)

- Resaltado (`Resaltado/netdeck.yml`, `Highlight/`), órdenes peligrosas (`DangerousCommands`), `SafePaster` y la
  lógica de MultiExec.
- Detección de prompts de contraseña (`PasswordPrompt`) y regla de usuario estricta (`CredentialPolicy`).
- Lector y escritor de ssh_config (`SessionFile`, `SessionImporter`): el ssh de Windows lee
  `%USERPROFILE%\.ssh\config` e `Include` igual.
- El protocolo SFTP propio (`SFTPPacket`, `SFTPClient`): habla con `ssh -s sftp` por tuberías, así que sólo cambia cómo
  se lanza el proceso.
- Los 85 temas (`Temas/`) y la tabla de inglés (`Support/Ingles.swift`).

## Qué hay que reescribir en el núcleo

| macOS (archivo) | En Windows | Dificultad | Paso |
|---|---|---|---|
| `posix_spawn`, `setsid`, `killpg`, `DispatchSourceProcess` (`ChildProcess`, `Tunnels`) | `CreateProcessW` + Job Object, `WaitForSingleObject` | Media | P4a |
| `/usr/bin/ssh`, `/usr/bin/sftp`, `/bin/zsh`, `/etc/shells` (`ConnectionRoute`, `KnownHosts`, `JumpSharing`) | `%SystemRoot%\System32\OpenSSH\*.exe`, PowerShell o cmd | Baja | P4b |
| ControlMaster con socket Unix (`JumpSharing`) | No lo tiene el OpenSSH de Windows (por confirmar en P1) | Alta | P4c |
| Llavero con `/usr/bin/security` (`KeychainStore`) | Administrador de credenciales (`CredWriteW`/`CredReadW`) | Media | P4d |
| `kill(pid, 0)` (`CredentialLedger`, `Askpass`) | `OpenProcess` + `GetExitCodeProcess` | Baja | P4d, P4e |
| `/dev/tty` + `tcgetattr` (`Askpass`) | `CONIN$` + `SetConsoleMode` | Media | P4e |
| Permisos 0600/0700 (`SafeFile`, `AppPaths`, `DataBackup`, `SessionLog`) | ACL de NTFS sólo para el usuario | Media | P4f |
| `/dev/cu.*` + termios (`SerialPort`, `SerialLine`) | `\\.\COMn` + `SetCommState` | Media | P4g |
| `CryptoKit` (`CredentialLedger`, `JumpSharing`, `UpdateCheck`, `Transfer`) | swift-crypto (misma API) | Baja | P4h |
| `Network.framework` (`FTPClient`) | Sockets / Winsock | Media | P4h |
| `CoreText` (`TerminalFont`), `CoreGraphics` (`OpenWindows`) | DirectWrite / lo que pida la interfaz | Baja | P4h |
| pty de SwiftTerm (`LocalProcess` / `forkpty`, en la app) | ConPTY (`CreatePseudoConsole`) | Alta | P7 |
| SwiftUI + AppKit (toda la app) | WinUI 3, Tauri o .NET según la ADR 0001 | Muy alta | P8 |
| `.dmg` + `codesign` (actualizaciones) | MSIX o instalador + Authenticode + `WinVerifyTrust` | Media | P10 |

## Problemas que limitan funciones

1. **Saltos compartidos:** usan ControlMaster con sockets Unix y el OpenSSH de Windows no lo soporta. Sin un SSH propio,
   cada pestaña se autentica en el bastión.
2. **Askpass:** la contraseña automática de las sesiones depende de que `ssh.exe` respete `SSH_ASKPASS` con
   `SSH_ASKPASS_REQUIRE=force`. Es lo primero que hay que probar (P1).
3. **Telnet:** Windows no trae el cliente por defecto (característica opcional).
4. **Permisos:** el OpenSSH de Windows rechaza un `config` o unas claves con ACL abiertas. `SafeFile` tiene que poner las
   ACL correctas o ssh no arrancará.
5. **Firma:** sin un certificado de firma de código, SmartScreen avisa al instalar. Cuesta dinero.
6. **Terminal y aspecto:** SwiftTerm no tiene vista para Windows (como mucho, el motor sin vista). Liquid Glass pasa a
   ser Mica de Fluent.

## Cómo lo hacen otros

Tres modelos. El más parecido a NetDeck es el primero.

### 1. Un núcleo común, interfaz nativa en cada sistema
- **Royal TS (Windows) / Royal TSX (macOS).** Comprobado en un Royal TSX instalado: lleva Mono (.NET) dentro
  (`libmonosgen-2.0`, `libmonobjc`) y frameworks nativos de Cocoa (`RoyalTSXNativeUI`, `RoyalSDKKit`). La lógica en C#
  es común y cada sistema tiene su interfaz. Los documentos valen en las dos; las hacen dos empresas asociadas.
  Fuentes: [Royal Apps](https://royalapps.com/blog/announcing-royal-tsx),
  [formatos compatibles](https://community.royalapps.com/t/compatibility-of-royalts5-and-royaltsx4-file-formats-merged-file/1359),
  [.NET en Windows](https://royalapps.com/blog/major-version-release-2021).
- **Arc.** Swift en Windows: cerca del 80 % del código común con macOS, interfaz WinUI 3 con swift-winrt, Mica y
  Acrylic. Pero Arc sólo recibe mantenimiento desde mayo de 2025 y su empresa es de Atlassian: swift-winrt puede quedarse
  sin quien lo mantenga. Fuentes:
  [Windows Central](https://www.windowscentral.com/software-apps/windows-11/arc-for-windows-is-beautiful-and-unique-web-browser-inside-and-out-and-its-available-for-download-now),
  [Swift, meet WinRT](https://speakinginswift.substack.com/p/swift-meet-winrt),
  [Neowin](https://www.neowin.net/news/atlassian-acquires-the-browser-company-creators-of-arc-browser/),
  [estado de Arc](https://supasidebar.com/blog/is-arc-browser-dead).

### 2. Un único toolkit para todos los sistemas
- **SecureCRT.** Nació en Windows; macOS en 2010 (6.6) y Linux en 2011 (6.7); hoy salen las tres a la vez. VanDyke no
  dice qué toolkit usa; el paquete de Linux de AUR depende de `qt5-base`, así que probablemente **Qt** en macOS y Linux
  (sin confirmar). Lleva **su propio SSH**, no el del sistema. Fuentes: [Wikipedia](https://en.wikipedia.org/wiki/SecureCRT),
  [AUR scrt](https://aur.archlinux.org/packages/scrt?O=90),
  [VanDyke SSH2](https://vandyke.com/products/securecrt/securecrt_ssh2.html).
- **Warp.** Una base de código en Rust con su propia interfaz (Metal en macOS, otras API gráficas en Linux y Windows);
  en Windows desde febrero de 2025. Fuentes: [How Warp Works](https://warp.dev/blog/how-warp-works),
  [Wikipedia](https://en.wikipedia.org/wiki/Warp_(terminal)).

### 3. Electron (web)
- **Termius**, **Tabby** y **electerm**: xterm.js para la terminal y node-pty (ConPTY en Windows) para el pty. Tabby usa
  russh, un SSH en Rust. Llegan a todo casi gratis, a cambio de una app pesada y nada nativa. Fuentes:
  [Termius](https://desktopinsights.com/apps/termius), [análisis de Tabby](https://repopilot.app/r/eugeny/tabby).

## Qué significa para NetDeck

1. **El modelo de Royal y Arc es el que encaja:** NetDeck ya separa `NetDeckCore` (sin interfaz, con tests) de la app.
2. **La dependencia de OpenSSH es la decisión de fondo.** SecureCRT, Tabby y Termius llevan su propio SSH; NetDeck usa
   el del sistema (las sesiones son ssh_config validado con `ssh -G`). Windows trae OpenSSH, así que sesiones e
   `Include` funcionan; se pierde compartir el bastión. Llevar un SSH propio (libssh, russh) son meses y rompe la regla
   de que las sesiones sean ssh_config validado por `ssh -G`.
3. **La terminal es la pieza que falta en cualquier camino:** no hay un control de terminal nativo de Windows para
   reutilizar. Opciones: el motor sin vista de SwiftTerm + ConPTY + vista propia, o xterm.js en un WebView2.
4. **Electron o Tauri es lo más rápido**, pero choca con la idea de app nativa, que es lo que distingue a NetDeck.
