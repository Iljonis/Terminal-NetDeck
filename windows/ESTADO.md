## 2026-11-17 · Windows · P10: el instalador compila con WiX 4 (por Claude)

**Por Claude.** Rama `windows/p10-paquete`. El `.wxs` ya compila: `wix build` termina sin errores ni avisos y genera un `.msi` de 69 MB.
**El `.msi` no está firmado** (`Get-AuthenticodeSignature`: `NotSigned`) y **no se ha instalado** en ningún equipo; `wix msi validate` (reglas ICE) sale con código 0.

- **Privacidad** (punto 1-2 del encargo): `tools/privacidad.sh` sale con código 0 en `windows/p10-paquete`; el fallo del actualizador ya estaba corregido en
  `4e038c2` (se enmendó antes de publicar), así que no hizo falta un commit de corrección.
- **WiX 4.0.6 y .NET, en una carpeta de usuario y sin tocar el sistema ni el `PATH`:** `dotnet tool install --global wix` necesitaba un SDK de .NET que no estaba.
  Se instaló el SDK 8.0.428 con el script oficial `dotnet-install.ps1` (Microsoft, MIT) en `C:\Users\<usuario>\.dotnet` y WiX como herramienta local en
  `C:\Users\<usuario>\.dotnet-tools`. Para quitarlo basta con borrar esas dos carpetas. Comando:
  `DOTNET_ROOT=…\.dotnet  …\.dotnet-tools\wix.exe build NetDeckWindows.wxs archivos.wxs -arch x64 -d SourceDir=<carpeta> -o NetDeckWindows.msi`.
- **Qué hubo que corregir en el `.wxs`:** WiX 4.0 **no tiene el elemento `Files`** (llegó después), así que `ComponentGroup`/`Directory` lo rechazaban.
  `preparar-instalador.ps1` genera ahora `archivos.wxs` (un componente por archivo, con `Subdirectory`) junto a la carpeta preparada, y `NetDeckWindows.wxs`
  sólo referencia `ArchivosDeLaApp`. El comando del encargo (`wix build NetDeckWindows.wxs -o …`) tampoco bastaba sin `-d SourceDir=…` y sin `archivos.wxs`.
- **Pendiente** (sin cambios): probar la instalación, el registro del Sparse Package y la actualización en un Windows limpio; firmar; build Release.

## 2026-11-17 · Windows · P10: informe del paquete, la firma y el actualizador (por Claude)

**Por Claude.** Rama `windows/p10-paquete`, que sale de `windows/p9-seguridad` con la ADR-0003 de `windows/p8-terminal` fusionada (`d5c3ca8`). El worktree
sigue en `C:\Users\<usuario>\NetDeck-P9`. **P10 no está completo**: la «Salida» del plan (un instalador firmado que se instala en un Windows limpio y se
actualiza desde una release de prueba) no se ha podido alcanzar; está hecho lo que se puede escribir y probar sin WiX, sin certificado y sin release.

### Commits
- `1828288` AppxManifest.xml del Sparse Package (validado con `makeappx pack`; iconos provisionales).
- `01a5bc3` instalador WiX 4 (`windows/installer/`): `.wxs`, scripts de registro y preparación de la carpeta. **`.wxs` sin compilar.**
- `4e038c2` `UpdateChecker`, 9 tests, textos en inglés y botón «Buscar actualizaciones» en Ajustes.

### Qué falta para cerrar P10
1. **Compilar el `.msi`** con WiX 4 (`dotnet tool install --global wix`) y probarlo en un Windows limpio (instalar, registrar el Sparse Package, actualizar, desinstalar).
2. Un **build Release** para el instalador (el Debug pesa 376 MB).
3. El `.msix` firmado del Sparse Package (`makeappx pack /nv` + `signtool`) y el `Publisher` igual al Subject del certificado.
4. **Firma Authenticode** (Azure Code Signing o un certificado): decisión y coste del autor; hasta entonces el actualizador rechaza instaladores sin firma
   (salvo `NETDECK_UPDATE_ALLOW_UNSIGNED=1` en pruebas).
5. En el actualizador: **fijar el firmante** y comprobar que el `.msi` es esta app y la versión anunciada (el equivalente al `validate` de macOS).
6. **El workflow de Release de Windows** (`.github/workflows/`, de Codex; no se ha tocado y no existe todavía) y añadir `UpdateCheckerWindowsTests` a la
   lista de suites de `windows/scripts/test.ps1` (tampoco se ha tocado).
7. El **askpass de P4e** dentro del instalador (ADR-0003).
8. Decidir la **versión de Windows**: se pidió 0.9.0 y la última release es la 1.0.0.
9. Registro del Sparse Package para todos los usuarios (hoy sólo para quien instala).

### Nota de proceso
En el commit del actualizador, `tools/privacidad.sh` falló (una URL de prueba con usuario delante del servidor parecía un correo) y se comitó igual, porque la tubería
`| tail` enmascaró el código de salida; se detectó justo después y se enmendó el commit local (sin publicar) con la privacidad ya en verde. Los demás commits de
esta serie la tenían en verde. Hay que comprobar el código de salida, no sólo leer la última línea.

## 2026-11-17 · Windows · P10: actualizador (UpdateChecker) y botón «Buscar actualizaciones» (por Claude)

**Por Claude.** `Sources/NetDeckCore/Update/UpdateChecker.swift` (todo bajo `#if os(Windows)`), su suite de tests y la interfaz. Compila y la app
arranca; 9 tests nuevos en verde y `IdiomaTests` en verde con los textos en inglés.

### Qué hay
- `UpdateChecker` (actor, `shared`): `checkForUpdates()` (como pedía, devuelve `nil` si hay error) y `check()` (lanza el motivo; lo usa la interfaz
  para distinguir «al día» de «no se pudo comprobar»), `downloadAndVerify(_:)` y `launchInstaller(at:)`. Reutiliza `UpdateCheck` del núcleo
  (`isNewer`, `sha256(of:)`): no se duplica la lógica de macOS.
- **sha256:** el campo `digest` que GitHub publica en el asset y/o un asset `<instalador>.sha256`; si hay los dos y no coinciden, se rechaza; si
  no hay ninguno, no se ofrece la actualización. (El encargo hablaba sólo de `.sha256`; `digest` es lo que ya usa el actualizador de macOS.)
- **Enlaces:** sólo `https://github.com/Iljonis/Terminal-NetDeck/releases/download/…`, sin usuario, puerto ni «..»; el nombre del instalador se limpia
  antes de escribirlo en la carpeta temporal.
- **Firma:** `WinVerifyTrust` (revocación incluida) cargado de `wintrust.dll`: `WinSDK` no lo expone ni lo enlaza. Las estructuras se
  comprueban por tamaño antes de usarlas y cualquier duda cuenta como firma inválida. **Probado con una DLL firmada de Microsoft (válida) y una sin
  firma.** Un instalador sin firma se rechaza, salvo `NETDECK_UPDATE_ALLOW_UNSIGNED=1` (los instaladores de prueba del CI sin certificado).
- `launchInstaller`: `ShellExecuteW` con `runas`; para un `.msi` lanza `msiexec.exe /i "<ruta>"` (más fiable que ejecutar el verbo sobre el `.msi`).
- Interfaz: botón «Buscar actualizaciones» en Ajustes y un panel con las notas y «Descargar e instalar» (sin `ContentDialog`, como el resto). Nada se
  comprueba ni descarga sin clic. `NETDECK_UPDATE_FAKE=1` en la demo enseña una actualización inventada, sin red, para probar la interfaz.
- `Ingles.swift`: 19 textos nuevos.

### Probado
- Consulta real a la API de GitHub desde la app: responde y, como la última release (1.0.0, macOS) no trae un `.msi`, dice «al día».
- Panel de actualización (con la inventada) y el error de descarga (404 → «No se puede actualizar: la descarga no ha terminado bien»).
- **Sin probar:** una descarga y un lanzamiento de instalador reales (no existe todavía ninguna release con `.msi`).

### Pendiente
- **Fijar el firmante:** hoy se comprueba que la firma es válida y de confianza, no QUIEN firma; con Azure Code Signing hay que comparar el Subject.
- **Que el instalador sea de esta app y de la versión anunciada** (como `UpdateCheck.validate` con el `.dmg`): leer `ProductCode`/`ProductVersion` del `.msi`.
- `currentVersion` es 0.9.0 (como se pidió) y la última release publicada es la 1.0.0: hay que decidir la versión de Windows.
- **`windows/scripts/test.ps1` sin filtro ejecuta una lista fija de suites**: `UpdateCheckerWindowsTests` no está en ella (y no se ha tocado ese archivo).
  Se ejecuta con `--filter UpdateCheckerWindowsTests`; hay que añadirla a esa lista.

## 2026-11-17 · Windows · P10: instalador WiX (por Claude)

**Por Claude.** `windows/installer/`. **El `.wxs` no se ha compilado**: WiX 4 (ni `dotnet`) no está instalado aquí; sólo se comprobó
que el XML está bien formado. Lo demás sí se probó.

- `NetDeckWindows.wxs` (WiX 4): instala en `C:\Program Files\Terminal NetDeck` (por máquina), `Files Include="$(var.SourceDir)\**"`
  para el exe, los `.dll` de la app y del runtime de Swift y el manifiesto; acceso del menú Inicio y, opcional (nivel 2,
  `ADDLOCAL=Principal,AccesoEscritorio`), el del escritorio; `MajorUpgrade`; `UpgradeCode` fijo (no se cambia nunca) y versión 0.9.0.
- Registro del Sparse Package con dos `CustomAction` diferidas (`RegistrarSparse` tras `InstallFiles`, `QuitarSparse` antes de
  `RemoveFiles` y al actualizar) que llaman a `registrar-sparse.ps1` y `quitar-sparse.ps1`. Diferencias con el encargo:
  - **`Impersonate="yes"`** y no `"no"`: con `no` se ejecuta como SYSTEM y `Add-AppxPackage` registraría el paquete para SYSTEM, no para
    el usuario que instala. Consecuencia: sólo queda registrado para quien instala; los demás usuarios no tienen identidad hasta
    que se registre (pendiente: que la app lo haga al arrancar).
  - **`Return="ignore"`** y scripts que nunca fallan: el registro es opcional y la app funciona sin identidad de paquete.
  - Los scripts van aparte (un `deferred` no resuelve `[Propiedades]` y comillas en un atributo XML serían un infierno).
- `preparar-instalador.ps1`: reúne en una carpeta lo que lleva el instalador (salida de `desktop.ps1`, los `.dll` del runtime de Swift,
  manifiesto, iconos y scripts). Salvaguarda: sólo vacía su destino si está vacío o lo creó él.
- **Probado:** el script genera 52 archivos (376 MB, con el build Debug) y **`NetDeckWindows.exe` arranca desde esa carpeta con el `PATH`
  reducido a `System32`**: el instalador lleva todo lo que necesita. `makeappx` valida el manifiesto (entrada anterior).
- **Pendiente:** compilar el `.msi` con WiX 4, instalarlo en un Windows limpio, un build Release (el Debug pesa y arrastra símbolos), el
  `.msix` firmado del Sparse Package, el askpass de P4e dentro del instalador (ADR-0003) y la firma Authenticode.

## 2026-11-17 · Windows · P10: AppxManifest.xml del Sparse Package (por Claude)

**Por Claude.** Rama `windows/p10-paquete` (sale de `windows/p9-seguridad`, con la ADR-0003 traída de `windows/p8-terminal`).

- `windows/Desktop/AppxManifest.xml`: identidad `Iljonis.TerminalNetDeck`, versión `0.9.0.0`, x64, `Publisher="CN=TerminalNetDeck"`
  (provisional), aplicación `NetDeckWindows.exe` con `runFullTrust`, y `Windows.Desktop` desde 10.0.19041.0. **Validado con
  `makeappx pack /nv`** (empaqueta bien). No se ha registrado en este equipo (sin firma sólo vale en modo desarrollador).
- Dos diferencias con el encargo, las dos por lo que dijo `makeappx` o la documentación:
  - **`MinVersion` 10.0.19041.0** y no 17763: los paquetes de ubicación externa (Sparse Package) empiezan en Windows 10 2004.
  - **Capacidad `unvirtualizedResources`**: `makeappx` rechaza el manifiesto sin ella. Además evita que el sistema redirija
    `AppData` y el registro a una copia privada del paquete (el mismo efecto que rompe otras herramientas aquí).
- Registro correcto: `Add-AppxPackage -Path NetDeckSparse.msix -ExternalLocation <carpeta>` (el .msix se genera con
  `makeappx pack /nv` y se firma) o, sin firma y con el modo desarrollador, `Add-AppxPackage -Register AppxManifest.xml
  -ExternalLocation <carpeta>`. La sintaxis `--ExternalLocation … --Path AppxManifest.xml` del encargo no existe en PowerShell.
- `windows/Desktop/Assets/*.png`: tres iconos **provisionales** (un color liso, el índigo del tema NetDeck); no hay icono de la
  app en el repositorio. Pendiente antes de publicar: iconos, `Publisher` igual al Subject del certificado y firma.
- **Versión:** 0.9.0 como se pidió, pero `CHANGELOG.md` ya publica 1.0.0 (macOS). Hay que decidir cuál es la versión de
  Windows antes del primer lanzamiento y cambiarla a la vez en el manifiesto, el `.wxs` y `UpdateChecker.currentVersion`.

## 2026-11-17 · Windows · P9: informe de seguridad (por Claude)

**Por Claude.** Rama `windows/p9-seguridad`, salida de `windows/p8-terminal` en `652d840`. Cuatro commits, suite completa en verde
(549 tests). Los puntos de `windows/PLAN.md` hechos están marcados `[x]`.

### Hecho
- **Importación de sesiones** (`68bf80d`): `safeExtra` filtra con lista blanca, así que `ProxyCommand`, `LocalCommand`,
  `KnownHostsCommand` e `IdentityAgent` se descartan siempre, con rutas de Windows o sin ellas; no hacía falta código nuevo.
  Se añaden tests con rutas `C:\`, `%VAR%` y tuberías, y un test que falla si alguien amplía la lista con una opción que
  ejecuta código.
- **Prefijos peligrosos** (`68bf80d`): nombre, equipo y usuario con `-` ya se rechazaban (`isValidName`, `Endpoint`,
  `problems()`); ahora con test. `/` no se rechaza: `ssh.exe -G /x` lo toma como un nombre literal.
- **Entorno** (`00d96c3`): `TerminalEnvironment.prepare` quita `SSH_ASKPASS`, `SSH_ASKPASS_REQUIRE`, `GIT_SSH` y `GIT_SSH_COMMAND` en
  Windows, sólo para ssh y sin tocar las shells locales; `USERPROFILE`, `APPDATA` y `LOCALAPPDATA` se conservan.
- **Credenciales** (`3d62b39`): ADR 0004. El almacén de Windows ya existía (P4d); la ADR documenta la diferencia con el Llavero y
  matiza la ADR-0002.

### Pendiente
- **Flujo de askpass en Windows** y sus pruebas (P4e/P10): hoy sólo claves y agente. La ADR 0004 lo explica.
- **Aviso en la pantalla de «Contraseñas»** de que en Windows la barrera es el perfil de usuario (P8/P9; esa pantalla no existe
  todavía en la interfaz de Windows).
- Evaluar DPAPI como capa extra sobre el Administrador de credenciales, y revisar la frase de la ADR-0002.
- **No se ha hecho la revisión formal** con la skill `security-review` ni `ecc:security-reviewer`: la «Salida» de P9 («informe sin
  hallazgos graves abiertos») sigue abierta.
- Los tests de NetDeckCore tienen **fallos intermitentes** ajenos a esto (ver la entrada de túneles de P8): conviene mirarlos
  antes de dar P6 por cerrado.

### Rama y entorno
- Esta rama no lleva el commit `03796ed` (ADR-0003) que otra sesión hizo en `windows/p8-terminal` después: al fusionar habrá
  que traer P8 primero o resolver `ESTADO.md` y `decisiones/README.md`.
- El worktree está en `C:\Users\<usuario>\NetDeck-P9`, fuera de `AppData\Local` (el MSIX de Claude redirige allí las carpetas
  nuevas).

## 2026-11-17 · Windows · P9: ADR 0004, credenciales en Windows (por Claude)

**Por Claude.** Rama `windows/p9-seguridad`. Documentación: `windows/decisiones/0004-credenciales-p9.md` (propuesta) y su fila en
`windows/decisiones/README.md`. La ADR describe lo que el código hace de verdad, y eso corrige tres cosas del encargo:

- **La implementación de Windows ya existe** (P4d): `KeychainStore` usa `CredWriteW`, `CredReadW`, `CredDeleteW` y
  `CredEnumerateW`, `CRED_TYPE_GENERIC` y `CRED_PERSIST_LOCAL_MACHINE`, con tests (`KeychainCredencialesWindowsTests`). Lo
  pendiente es el flujo con askpass (P4e/P10) y el aviso en la pantalla de «Contraseñas».
- **macOS no usa `SecItemAdd` ni una «ACL 0600»**: lee y guarda con `/usr/bin/security`, y las contraseñas confían en esa
  herramienta (por eso no sale el aviso por app). La ADR lo anota y **matiza la ADR-0002**: la distancia real entre las dos
  plataformas es menor que «ACL por app frente a nada».
- **El bloqueo de 15 minutos no es un `Timer` que borre una caché**: es el `CredentialLedger` (`blockWindow`), con marcas
  con fecha sin secretos, igual en las dos plataformas. `CredReadW` no caduca.
- DPAPI protege frente a otros usuarios y al disco apagado, no frente a otros procesos del mismo usuario: así queda escrito.

## 2026-11-17 · Windows · P9: TerminalEnvironment sin variables de ssh ajenas (por Claude)

**Por Claude.** Rama `windows/p9-seguridad`. Suite completa: 549 tests en verde (546 + los 3 de la tarea 1 + 1 de ésta).

- `TerminalEnvironment.prepare` (`#if os(Windows)`, sólo con `forSSH: true` y `sendLocale: false`, la misma condición que ya
  quita el idioma) elimina `SSH_ASKPASS`, `SSH_ASKPASS_REQUIRE`, `GIT_SSH` y `GIT_SSH_COMMAND` del entorno heredado. Los
  nombres se comparan sin distinguir mayúsculas, como Windows. `USERPROFILE`, `APPDATA` y `LOCALAPPDATA` no se tocan (ssh.exe
  las necesita para encontrar `~/.ssh`; son inofensivas) y queda dicho en un comentario.
- **No se tocan las shells locales** (`forSSH: false`): ahí el `GIT_SSH` o el `SSH_ASKPASS` del usuario son suyos. Tampoco con
  `sendLocale: true`, por coherencia con el resto de la función; si se quiere la limpieza también ahí, es mover el bloque.
- El askpass propio (`Askpass.environment`) se mezcla DESPUÉS de `prepare`, así que no se pierde.
- Test nuevo (`SessionTests.swift`, `TerminalEnvironmentTests`): `enWindowsAsshNoLeLlegaElAskpassNiGitSshAjenos`. En macOS
  comprueba que no cambia nada.
- La tarea pedía `testWindowsRemovesInterferingVars`: el proyecto usa Swift Testing con nombres en castellano, así que se
  llama de otra forma.

## 2026-11-17 · Windows · P9: importación de sesiones y prefijos peligrosos (por Claude)

**Por Claude.** Rama `windows/p9-seguridad`. Sólo tests: el código de la tarea ya estaba cubierto, y añadir el filtro pedido
habría sido código muerto.

- `SessionImporter.safeExtra` filtra con una **lista blanca** (`allowedOptions`). `ProxyCommand`, `LocalCommand`,
  `KnownHostsCommand` e `IdentityAgent` no están en ella, así que se descartan siempre, con o sin ruta de Windows; un
  filtro adicional por `C:\` o `%VAR%` después del `guard` nunca se ejecutaría. Para proteger de verdad, los tests nuevos
  (`SessionFileTests.swift`):
  - `alImportarSeQuitanLasOpcionesQueEjecutanTambienConRutasDeWindows`: las cuatro opciones con rutas `C:\…`, `%USERPROFILE%`
    y `\.\pipe\…`, y `PermitLocalCommand`, quedan fuera.
  - `laListaBlancaDeImportacionNoTieneOpcionesQueEjecutenOAbranOtroBloque`: falla si alguien añade a `allowedOptions` una
    opción que ejecuta código, abre otro bloque o toca reenvíos y `known_hosts` (`ProxyCommand`, `Include`, `Match`,
    `LocalForward`, `StrictHostKeyChecking`…).
- Prefijos peligrosos, ya rechazados y ahora con test (`nombresEquiposYUsuariosConPrefijoDeOpcionSeRechazan`):
  `EditableSession.isValidName` exige que el primer carácter sea alfanumérico o `_` (rechaza `-`, `/`, `.`);
  `Endpoint(parsing:)` rechaza equipo o usuario con `-`; `SessionFile.problems()` rechaza equipo, usuario y salto con `-`.
- **No** se rechaza el prefijo `/` en equipo o usuario: `ssh.exe` sólo trata `-` como opción (no hay opciones con `/`), así
  que no hay un riesgo concreto. Si se quiere, es una regla de validez de nombres de equipo, no de seguridad.
- Entorno: el worktree está en `C:\Users\<usuario>\NetDeck-P9`, fuera de `AppData\Local`: el MSIX de Claude redirige a su caché
  las carpetas nuevas que se crean ahí y otros programas (Python) no las veían.

## 2026-11-17 · Windows · P8: warnings de Sendability en ExploradorSFTP (por Claude)

**Por Claude.** Corregidos los dos avisos «reference to captured var 'self' in concurrently-executing code» que serían
errores en Swift 6. `Build complete!` sin avisos del compilador (sólo queda el del enlace simbólico `debug`, del entorno).

- Causa: los closures de progreso de `Transfer.copy` (descarga, línea ~210, y subida, ~244) usaban el `self` de
  `[weak self]`, que es una variable, dentro de un closure `@Sendable`.
- Arreglo (`ExploradorSFTP.swift`): cada tarea copia `let owner = self` antes de `Transfer.copy` y el closure usa `owner`; la
  clase pasa a `@unchecked Sendable`, con el motivo escrito: sus controles sólo se tocan en el hilo de WinUI (lo que llega de
  las tareas pasa por `deliver` y `enqueue`). No se usa `Task { @MainActor … }`: en Windows no se sabe si el actor principal
  se vacía con el bucle de WinUI, y `enqueue` (el `DispatcherQueue`) ya hace ese papel.
- Sin cambios de comportamiento; la interfaz del explorador no se ha vuelto a probar.

### Aviso para quien compile
La app lanzada por `desktop.ps1 -Demo` aparece a veces como `NETDEC~1.EXE` (nombre corto) y `taskkill /IM NetDeckWindows.exe`
no la encuentra: el enlazador falla con «unable to remove file: permission denied». Cerrarla por PID (`Stop-Process -Id`).

## 2026-11-17 · Windows · P8: asistente de inicio (por Claude)

**Por Claude.** Asistente de la primera vez en el área principal. Compila (`Build complete!`) y está probado de verdad,
también el camino sin demo: arranca solo, crea la sesión y la escribe en el `ssh_config` de NetDeck.

### Qué hay
- `windows/Desktop/Sources/NetDeckWindows/AsistenteInicio.swift` (nuevo): tres pantallas, una a la vez. Bienvenida
  («Siguiente →»); primera sesión (nombre y equipo obligatorios, usuario y puerto opcionales; «Crear sesión» u «Omitir»);
  «¡Todo listo! Haz clic en tu sesión para conectar.» («Empezar»). Ids `Asistente_*`.
- `NetDeckWindows.swift`: se muestra al arrancar si no es la demo, no existe `ndAsistenteVisto` en `UserDefaults` y no hay
  sesiones. «Empezar» y «Omitir» lo marcan como visto. «Crear sesión» usa `saveSession` (la misma validación y guardado
  que el editor) y vuelve a «Todo listo» (guardar cierra los paneles, así que se reabre el del asistente).
- Sin `ContentDialog`, igual que el resto: son paneles del área principal.
- Para probarlo: `NETDECK_ASISTENTE=1` lo fuerza (también en la demo) sin marcarlo como visto.
- `Ingles.swift`: textos nuevos en inglés.

### Probado
- Demo forzada: las tres pantallas, el aviso de nombre y equipo vacíos y la sesión nueva en la barra lateral.
- Sin demo, con un `NETDECK_HOME` temporal vacío: el asistente sale solo, «Crear sesión» escribe el `ssh_config`
  (con la comprobación `ssh -G` del núcleo) y la barra lateral lo recarga. Esto prueba además el **guardado real del editor
  de sesión**, que estaba pendiente.
- Sin probar: que «Empezar» persista `ndAsistenteVisto` entre arranques (no se pulsó para no tocar los ajustes reales).

## 2026-11-17 · Windows · P8: panel de túneles SSH (por Claude)

**Por Claude.** Panel de túneles en el área principal. Compila (`Build complete!`) y está probado en la demo con capturas:
crear, iniciar y detener un túnel. Dos fallos de `TunnelManager` en Windows corregidos en el núcleo.

### Qué hay
- `windows/Desktop/Sources/NetDeckWindows/PanelTuneles.swift` (nuevo): lista con nombre, tipo, `forwardSpec`, estado y
  botones ▶ Iniciar / ■ Detener, ✎ y ✕; botón «+ Nuevo túnel» y formulario (nombre, sesión, equipo, tipo, puerto de
  escucha, destino, puerto de destino, «escuchar fuera de este equipo»). Datos de `TunnelLibrary` (`tuneles.json`); en la
  demo, sólo en memoria.
- `NetDeckWindows.swift`: botón «Túneles» (id `Tuneles`) y **Ctrl+T**. Usa el `TunnelManager` del núcleo (preflight `ssh -G`,
  vigilancia y parada), no un `ChildProcess` a mano: `startTunnel`, `stopTunnel`, `tunnelChanged`; al salir se paran todos.
- `Ingles.swift`: textos nuevos en inglés.

### Correcciones en el núcleo (`Sources/NetDeckCore/Sessions/Tunnels.swift`)
1. **`ssh -G` en Windows devuelve líneas con `\r\n`** y `split(separator: "\n")` no parte ese grafema: la comprobación previa
   fallaba siempre con «ssh -G ha devuelto una configuración incompleta». Ahora `split(whereSeparator: \.isNewline)`
   (igual en macOS).
2. **`TunnelProcess` (rama `#if os(Windows)`)**: el `terminationHandler` daba el proceso por terminado y anulaba la lectura
   antes de vaciar la tubería. Ahora lee lo que queda y luego fija el estado; la lógica de añadir salida pasa a
   `appendOutput(_:)`. macOS no cambia.

### Notas
- Probado: iniciar pasa el preflight y queda «Iniciando…»; Detener lo para y quita el ssh. Sin probar un túnel realmente
  activo (no hay un servidor ssh al que llegar) ni un túnel remoto o SOCKS.
- La contraseña por teclado sigue sin askpass en Windows (P4e/P10): de momento claves y agente.
- Los tests (`test.ps1`, 545) pasan, pero **hay fallos intermitentes ajenos a los túneles**: en 4 ejecuciones, una dio 545/545,
  otra 5 fallos en `DataBackupTests.copiaAntesDeGuardar` (que pasa aislado) y otra 1 en
  `SessionFileTests.importarUnJSONConOpcionesMaliciosasNoInyectaNada` («You don't have permission», código 513). Parecen
  carreras de permisos de archivos temporales en Windows al correr en paralelo; hay que investigarlo (P6).

## 2026-11-17 · Windows · P8: aviso claro para FTP (por Claude)

**Por Claude.** Pequeño ajuste sobre el explorador SFTP. Compila (`Build complete!`) y la app arranca en demo.

- `open(_:)` (`NetDeckWindows.swift`): si `route.transport == .ftp`, la barra de estado dice «FTP no disponible aún en la
  versión de Windows» en lugar del «FTP no tiene consola» de `launchProblem`, que confundía. FTP en Windows sigue pendiente
  (`TCPStream.start()` lanza «FTP no disponible en Windows (TODO P4h)»).
- `Ingles.swift`: el texto en inglés.
- Sin probar con una sesión FTP real en la interfaz: sólo compila y arranca.

## 2026-11-17 · Windows · P8: explorador SFTP (por Claude)

**Por Claude.** Explorador SFTP en el área principal. Compila (`Build complete!`) y está probado de verdad en la demo
contra un servidor SFTP local: listar, entrar en una carpeta, descargar con doble clic y subir un archivo.

### Qué hay
- `windows/Desktop/Sources/NetDeckWindows/ExploradorSFTP.swift` (nuevo): `ExploradorSFTP` con ruta actual, «⬆ Arriba»,
  «Actualizar», «Cerrar», lista con icono, nombre, tamaño y fecha, subida por ruta local y barra de estado con el
  progreso. Usa lo que ya había en NetDeckCore: `SFTPFileSystem`, `Transfer.copy`, `LocalFileWriter` (descarga sin pisar
  nada, con «.part») y `AtomicRemoteWriter` (subida sin pisar un archivo existente). No hizo falta tocar `Sources/`.
- `NetDeckWindows.swift`: botón 📂 en la barra lateral junto a cada sesión SSH o SFTP (`SFTP_<nombre>`);
  `open(_:)` abre el explorador si `route.transport == .sftp`; `openSFTP(_:)`, `openSFTPProfile(_:)`.
- Descarga a `Descargas` del usuario (`~/Downloads` si Foundation no la da), con nombre único («a (2).txt»). El nombre lo
  decide el servidor: se limpia (`localName`) de rutas y de caracteres que Windows no admite.
- Para probar sin red: en la demo, `NETDECK_SFTP_SERVER` apunta a un `sftp-server` local (Git for Windows trae
  `usr/lib/ssh/sftp-server.exe`), como el gancho `NETDECK_SNAPSHOT` del Mac.
- `Ingles.swift`: textos nuevos en inglés.

### Notas
- La tarea hablaba de `SFTPClient` y `route.target == .sftp(...)`: el núcleo tiene `SFTPFileSystem` y el tipo va en
  `route.transport`.
- No hay selector de archivos nativo (`FilePicker`) en swift-winui 0.1.1 a mano: la subida pide la ruta en un cuadro de
  texto (admite comillas).
- **Sin probar con ssh real:** la conexión por ssh (`sftpSubsystemCommand`) compila y se construye igual que en el Mac, pero
  la contraseña por teclado necesita el askpass de Windows (P4e/P10): de momento sólo claves y agente.
- FTP no está en el explorador: `FTPClient` existe en el núcleo pero pide contraseña y credenciales (P9).
- Una sola conexión a la vez: abrir otra cierra la anterior.

## 2026-11-17 · Windows · P8: pegado seguro y MultiExec (por Claude)

**Por Claude.** Botones «Pegar» y «MultiExec» en la barra de herramientas, después de «Cerrar pestaña». Compila
(`Build complete!`); el pegado seguro está probado en la demo con capturas.

### Qué hay
- `PanelTexto.swift` (nuevo): panel de texto multilínea con Enviar y Cancelar en el área principal. **No se usa
  `ContentDialog`**: en swift-winui 0.1.1 no hay un camino sencillo y síncrono, y el resto de la interfaz ya reparte el área
  principal entre paneles (`showPanel`).
- `safePaste()` (`NetDeckWindows.swift`, id `PegarSeguro`): lee el portapapeles con Win32 (`OpenClipboard`,
  `GetClipboardData(CF_UNICODETEXT)`; la API WinRT `Clipboard` es asíncrona). Una línea se pega directamente; varias abren
  la vista previa (hasta 2000 caracteres visibles; se pega todo). Se quitan los saltos finales para no ejecutar una línea
  de más.
- `PestanaTerminal.paste(_:)`: pega con Intro por cada salto y, si el programa lo pide, entre marcas de «pegado entre
  corchetes»; quita los ESC del texto para que no pueda cerrar la marca antes de tiempo.
- `multiExec()` (id `MultiExec`): un comando a todas las pestañas abiertas con `route.transport` SSH o Telnet
  (`PestanaTerminal` guarda ahora su `route`). El resumen de a cuántas se envió va a la barra de estado.
- `Ingles.swift`: textos nuevos en inglés.

### Notas
- Probado: pegar tres líneas desde el portapapeles las ejecuta en el shell local.
- **Sin probar:** el envío de MultiExec a pestañas SSH/Telnet reales (en demo `ssh` no conecta a ningún sitio).
- La tarea hablaba de `route.target` `.ssh(_)`/`.telnet(_,_)`: no existe; el tipo va en `route.transport`.

## 2026-11-17 · Windows · P8: tema Mica, claro y oscuro desde Ajustes (por Claude)

**Por Claude.** El tema elegido en Ajustes se aplica de verdad a la ventana. Compila (`Build complete!`) y está probado en
la demo con capturas.

### Qué hay
- `applySettings(_:)` en `NetDeckWindows.swift`:
  - **Sistema (Mica)**: `window.systemBackdrop = MicaBackdrop()` (existe en swift-winui 0.1.1) y el tema de Windows.
  - **Claro / Oscuro**: `requestedTheme` en la rejilla raíz, sin Mica y con un fondo explícito (`SolidColorBrush`
    #F3F3F3 / #202020): sin Mica la ventana no pinta fondo y quedaba negra con el texto invisible.
- `windows/Desktop/Package.swift`: `.linkedLibrary("UWP")`. Hace falta para construir un `Color` (`import struct
  UWP.Color`; el `import UWP` completo hace ambiguos varios tipos).
- `PanelAjustes.swift`: `UserDefaults.synchronize()` tras guardar. En Windows no se vuelca solo y los ajustes se perdían
  si la app se cerraba a la fuerza; con esto se comprobó que Claro sobrevive a un cierre y reinicio.

### Notas
- El primer build tras cambiar de rama de trabajo falló dos veces con «A file with the same name already exists» en
  `*.objlib`; se arregla borrando esos `.objlib` de `NetDeckDesktopBuild/out/Products` y reconstruyendo.
- Los temas de color de NetDeckCore (`Theme`) siguen sin conectar: «tema» aquí es claro/oscuro/Mica.

## 2026-11-17 · Windows · P8: atajos de teclado (por Claude)

**Por Claude.** Atajos globales de la ventana principal. Compila (`Build complete!`) y se han probado de verdad en la
demo: enviando las teclas a la ventana y mirando capturas.

### Qué hay
- `NetDeckWindows.swift`: `previewKeyDown` en la rejilla raíz (fase de túnel, antes de que el terminal reciba la tecla) y
  `shortcut(_:)`:
  - **Ctrl+N**: terminal local nueva (como el botón «Terminal local»). **Ctrl+Mayús+N**: editor de sesión nueva.
  - **Ctrl+W**: cierra la pestaña activa.
  - **Ctrl+Tab / Ctrl+Mayús+Tab**: pestaña siguiente / anterior (da la vuelta).
  - **Ctrl+,**: abre Ajustes.
  - Si hay un panel (editor o ajustes) abierto, N, W y Tab lo cierran y vuelven al terminal.
- Comprobado en la demo: Ctrl+N abre una segunda pestaña, Ctrl+W la cierra, Ctrl+, abre Ajustes; «+ Nueva sesión» abre
  el editor, y Guardar con un nombre añade la sesión a la barra lateral con el aviso «Sesión «x» guardada».

### Notas y problemas conocidos
- **Ctrl+N y Ctrl+W ya no llegan al terminal** (en la shell son «siguiente en el historial» y «borrar palabra»). Es lo que
  pide la tarea; si molesta, cambiar `shortcut(_:)` para exigir además Mayús o reservarlos al terminal.
- El campo Nombre del editor **no recibe el foco** al abrirse (`focus(.programmatic)` no surte efecto, ni diferido con el
  `DispatcherQueue`): hay que hacer clic en él.
- **Las consultas de UI Automation (`FindAll` sobre el árbol de la ventana) cierran la app** con acceso no válido en
  `Microsoft.UI.Xaml.dll` (0xc0000005). Con la app en reposo y con teclas y clics no pasa. Hay que investigarlo antes de
  automatizar pruebas de interfaz con UIA (P8, `windows-desktop-e2e`).
- La lista de sesiones del editor en modo real y el guardado real (`file.save()`, con `ssh -G`) siguen sin probarse.

### Siguiente
Explorador SFTP/FTP, temas de NetDeckCore, MultiExec y Túneles.

## 2026-11-17 · Windows · P8: panel de Ajustes (por Claude)

**Por Claude.** Panel de Ajustes con fuente, tamaño y tema. Compila (`Build complete!`) y la app arranca en modo demo
sin caerse.

### Qué hay
- `windows/Desktop/Sources/NetDeckWindows/PanelAjustes.swift` (nuevo): `AjustesTerminal` (carga y guarda en
  `UserDefaults` con las claves `ndFuente`, `ndTamano` y `ndTema`) y `PanelAjustes`, con ComboBox de fuente (Consolas,
  Courier New, Cascadia Code, Cascadia Mono), Slider de tamaño (10-20 pt) y ComboBox de tema (Sistema (Mica), Claro,
  Oscuro). Botones Guardar y Cancelar. Ids de automatización: `Ajustes_Fuente`, `Ajustes_Tamano`, `Ajustes_Tema`,
  `Ajustes_Guardar`, `Ajustes_Cancelar`.
- `NetDeckWindows.swift`: botón ⚙ (`Ajustes`) en la barra de herramientas; `showPanel(_:)` reparte el área principal entre
  terminal, editor de sesión y ajustes (nunca dos a la vez). Al guardar se aplican fuente y tamaño a `screen`, y el tema a
  la ventana (`requestedTheme`: Claro, Oscuro o el de Windows). Las columnas y filas del terminal se calculan con el tamaño
  de letra elegido.
- `Ingles.swift`: textos nuevos en inglés.

### Notas
- Sin verificar con interfaz real: que los ajustes sobrevivan a un reinicio (`UserDefaults` en Windows) y el aspecto de
  cada tema. La anchura de celda del terminal es aproximada (8,25 px a 15 pt, proporcional) y no se mide por fuente.
- Los temas de color de NetDeckCore (`Theme`) no están conectados todavía: aquí «tema» es sólo claro/oscuro/sistema.

## 2026-11-17 · Windows · P8: editor de sesión (por Claude)

**Por Claude.** Panel para crear y editar sesiones en la ventana WinUI 3. Compila (`Build complete!`) y la app arranca
en modo demo sin caerse.

### Qué hay
- `windows/Desktop/Sources/NetDeckWindows/EditorSesion.swift` (nuevo): `PanelEditorSesion` con nombre, grupo, equipo,
  usuario, puerto, tipo (SSH, Telnet, SFTP, FTP, Serie, Local) y descripción; botones Guardar y Cancelar. Al cambiar el
  tipo, el puerto pasa al del tipo nuevo (`EditableSession.setKind`).
- `NetDeckWindows.swift`: botón «+ Nueva sesión» al pie de la barra lateral y botón ✎ junto a cada sesión. El panel
  sustituye al terminal (`surface.visibility = .collapsed`).
- Guardar valida con `EditableSession.isValidName` y `SessionFile.problems()` (nombre repetido, puerto, etc.) y muestra
  el error en la barra de estado.
  - **Demo** (`NETDECK_DESKTOP_DEMO=1`): sólo en memoria (`library`); la barra lateral se rehace con
    `SessionManager(profiles:)`. No se escribe a disco.
  - **Real**: lee `SessionFile.defaultURL`, sustituye o añade la sesión, `file.save()` y `sessions.load(from:)`. Al
    arrancar, si existe ese archivo se carga en lugar de `~/.ssh/config`.
- `Ingles.swift`: 5 textos nuevos en inglés.

### Notas
- Sin verificar con interfaz real: el guardado real (`file.save()` pasa por `ssh -G`) no se ha probado contra un
  `NETDECK_HOME` temporal; sólo compila y la demo arranca.
- El primer build tras interrumpirse dejó `*.objlib` a medias en `NetDeckDesktopBuild/out/Products` (error «A file with
  the same name already exists»): se resolvió borrando esos `.objlib` y reconstruyendo (unos 5 min).
- Se anonimizó una ruta personal que había en este archivo y hacía fallar `tools/privacidad.sh`.

### Siguiente
Ajustes (fuente, tamaño, tema) y atajos de teclado.

## 2026-11-16 · Windows · P8: bootstrapper corregido, app lanzando (por Claude)

**Por Claude.** La app NetDeckWindows.exe lanza correctamente en modo demo. Dos bugs resueltos.

### Bug 1: SPM rev-parse ^{commit} en Windows

- Causa: SPM pasa args a git por cmd.exe, que trata ^ como escape y lo elimina.
  Git recibe 3.15.1{commit} y falla con "Needed a single revision".
- Fix: --force-resolved-versions en swift build (usa commit hashes de Package.resolved directamente).
- Fix adicional: rutas POSIX en 11 × .git/objects/info/alternates corregidas a rutas Windows
  (/home/<usuario>/ → C:/Users/<usuario>/).

### Bug 2: DDLM de Windows App Runtime 1.5 ausente

- Causa: el bootstrapper MddBootstrapInitialize2 requiere el paquete DDLM además del Framework.
  Solo estaban instalados Framework (5001.373.1736.0) y Main; DDLM ausente.
- Fix: instalado Microsoft.WinAppRuntime.DDLM.5001.373.1736.0-x6 desde
  NuGet microsoft.windowsappsdk/1.5.250108004 MSIX (tools/MSIX/win10-x64/).

### Resultado

- Build complete! (2.15 s — build incremental).
- NetDeckWindows.exe corre sin crash. Info: Unhandled DEC Private Mode Set (DECSET) con 9001
  (normal, es SwiftTerm en modo ConPTY).

### Cambios en este commit (fix-bootstrapper-p8)

- windows/scripts/desktop.ps1:
  - Revertido el bootstrapper lookup para usar el DLL del .bundle (no del paquete instalado).
  - Añadido --force-resolved-versions al comando swift build.
- windows/Desktop/Sources/NetDeckWindows/PestanaTerminal.swift (nuevo):
  - TerminalDelegate que conecta ConPTYProcess con SwiftTerm Terminal.
  - Lectura async del output, write, resize, close.

### Pendiente de P8

- Verificación visual de la barra lateral.
- Editor de sesión, explorador SFTP/FTP, Ajustes, temas, menús y atajos, MultiExec, Túneles.

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
