# El port de Windows (detalle)

Léelo antes de tocar algo de Windows. Las reglas de trabajo en Windows (Git Bash y PowerShell, comandos, antes de un commit, autor) están en
[`windows/CLAUDE.md`](../../windows/CLAUDE.md) y [`windows/AGENTS.md`](../../windows/AGENTS.md); el estado y el plan, en
[`windows/ESTADO.md`](../../windows/ESTADO.md) y [`windows/PLAN.md`](../../windows/PLAN.md). Esto sólo explica dónde está cada cosa.

## Dónde vive el código

- **Interfaz:** `windows/Desktop/` es un paquete SwiftPM propio. El target `NetDeckWindows` usa WinUI 3 con
  swift-winui. Antes de cambiar una vista, compara su comportamiento, textos y orden con la vista correspondiente
  de `Sources/TerminalNetDeck` (SwiftUI). La [portada Liquid Glass](../capturas/portada-liquid-glass.png) es la
  referencia visual de macOS.
- **Ventana y estilo:** `NetDeckWindows.swift` monta las pestañas, la barra lateral, la vista dividida y los paneles
  en `contenidoTarjeta` / `capaEmergente`, sobre el terminal. Los colores de interfaz vienen de `EstiloMac` y del
  tema activo. Las superficies Liquid Glass se pintan opacas en Windows.
- **Sesiones:** `MenuNuevo` y `EditorSesion` llaman a la ventana. `ImportadorSesiones` abre el selector nativo
  `SelectorArchivos` con el HWND de la ventana y delega los formatos en `SessionImporter`. En un `.mobaconf` sólo se
  leen las sesiones. El núcleo valida y guarda en formato `ssh_config` con `SessionFile` y `SafeFile`.
- **Terminal:** `PestanaTerminal` alimenta SwiftTerm desde ConPTY o `SerialPort`. `VistaTerminal` pinta la salida,
  selección, barra de historial y marca REC. `FiltroTerminal` consume el `ScreenLook` resuelto del tema o del perfil.
  La grabación usa `SessionLogger` y BREAK usa el puerto Win32.
- **Conexiones:** `PanelListas` usa `JumpBatchRunner`. `MultiExecGroup` comparte entrada entre pestañas SSH/Telnet
  elegibles. El explorador lateral usa `SFTPPanel` para resolver la ruta y `ExploradorSFTP` para la interfaz.
- **Ajustes y traducciones:** `PanelAjustes` y `PanelLlavero` separan apariencia y credenciales. Usa `L("…")` y
  revisa que su clave en `Sources/NetDeckCore/Support/Ingles.swift` no esté duplicada, incluidas formas equivalentes
  como `\u{00F3}` y `ó`. Guarda los nuevos Swift como UTF-8 sin BOM. Las contraseñas se introducen con `PasswordBox` cuando hay un formulario y se guardan en el
  Administrador de credenciales. Los registros y el texto de estado excluyen secretos.
- **Instalador:** `windows/installer/` (WiX 4) y `windows/Desktop/AppxManifest.xml` (Sparse Package).

## Compilación y pruebas

Desde la raíz del repo, cierra `NetDeckWindows.exe` antes de recompilar. La siguiente limpieza sólo actúa sobre
`*.objlib` en el directorio de productos Debug del build por defecto. El bloqueo que evita suele indicar
`dummy.o already exists`.

```powershell
$productos = Join-Path $env:LOCALAPPDATA 'NetDeckDesktopBuild\out\Products\Debug-windows-x86_64'
if (Test-Path -LiteralPath $productos -PathType Container) {
    $raiz = (Resolve-Path -LiteralPath $productos).Path
    foreach ($obj in (Get-ChildItem -LiteralPath $raiz -Filter '*.objlib')) {
        $ruta = (Resolve-Path -LiteralPath $obj.FullName).Path
        if ((Split-Path -Parent $ruta) -ne $raiz -or ($obj.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Ruta inesperada al limpiar los productos de NetDeck.'
        }
        Remove-Item -LiteralPath $ruta -Recurse
    }
}
powershell -NoProfile -ExecutionPolicy Bypass -File windows\scripts\desktop.ps1 -Demo
```

El script prepara el plugin de SwiftTerm, los recursos y Windows App Runtime. Compila siempre con el script de
escritorio. Para compilar sin abrir NetDeck, establece antes `$env:NETDECK_BUILD_ONLY = '1'` en esa sesión de
PowerShell. Para volver a abrir la demo desde la misma sesión, quita la variable con
`Remove-Item Env:NETDECK_BUILD_ONLY`. La demo mantiene las sesiones de ejemplo, el registro, el `ssh_config` y
`known_hosts` en un perfil temporal.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\scripts\test.ps1 --no-parallel
```

El script de tests usa un `NETDECK_HOME` temporal. `--no-parallel` evitó los fallos intermitentes de escritura
observados en archivos temporales durante la pasada de escritorio.

### Verificación de la ventana

- Usa clics reales y capturas de la ventana con el escritorio disponible. Para reproducir entradas desde un
  script se usaron `SetForegroundWindow`, `SetCursorPos` y `mouse_event`. `FindFirst` / `FindAll` de UI Automation
  pueden colgar WinUI.
- Si la app se cierra al arrancar, mira el backtrace en la salida del script. Una clave repetida en `Ingles.swift`
  puede producir el cierre antes de que aparezca la ventana.
- Apunta qué flujos se observaron con capturas, el resultado de los tests y lo pendiente en
  [resultados](../../windows/resultados/README.md). Sólo usa sesiones y archivos de prueba.

## Ramas
Los pasos del plan van en ramas `windows/pN-<tema>` que salen de la anterior; el trabajo de Windows no va nunca directamente en `main`:

| Rama | Qué lleva |
|---|---|
| `windows/p8-terminal` | La interfaz (P8): barra lateral, terminal, editor de sesión, ajustes, atajos, SFTP, túneles, asistente |
| `windows/p9-seguridad` | P9: tests de importación y de prefijos peligrosos, entorno de ssh, ADR de credenciales |
| `windows/p10-paquete` | P10 (manifiesto, instalador, actualizador) y la documentación de P11 |
| `windows/p14-escritorio` | P14 y trabajo de paridad de escritorio. Véase el [estado](../../windows/ESTADO.md) |

Cada rama parte de la anterior: `p9` sale de `p8` y `p10` sale de `p9`, con `p8` fusionada después (trae la ADR-0003); `p9` no lleva ese commit. La fusión a `main` la decide el autor tras la pasada de siempre en el Mac
(`./test.sh` y la demo): los cambios de `Sources/` no pueden romper macOS.
