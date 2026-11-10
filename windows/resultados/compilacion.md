# Resultado de P2: compilar NetDeckCore en Windows · sin tocar nada

Fecha: 2026-11-10 · Swift 6.4.2 · Windows 11 AMD64

## Notas de entorno

Para que `swift build` funcione en este PC se necesita el PATH con:
- `C:\Users\<usuario>\AppData\Local\Programs\Swift\Toolchains\6.4.2+Asserts\usr\bin`
- `C:\Users\<usuario>\AppData\Local\Programs\Swift\Runtimes\6.4.2\usr\bin`
- `C:\Users\<usuario>\AppData\Local\Programs\Swift\Toolchains\6.4.2+Asserts\usr\lib\swift\pm\ManifestAPI`
- `C:\Program Files\Git\bin` (antes que el git de DevKitPro, para que SPM lo use)
- `SDKROOT` → `C:\Users\<usuario>\AppData\Local\Programs\Swift\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk`
- Crear `.build\plugins\cache\` y `.build\plugins\outputs\` a mano antes del primer build (bug de SPM en Windows).

Ver `windows/scripts/comun.ps1` para las rutas exactas y cómo exportarlas.

## Resultado inicial (sin `#if !os(Windows)`)

La compilación para en el primer `import Darwin` de `Remote/ChildProcess.swift` y no continúa.
Salida en bruto: `windows/resultados/compilacion-0.txt` (no subido al repo).

## Archivos con dependencias de plataforma (12 archivos)

| Módulo       | Archivos                                                                 | Paso P4 |
|--------------|--------------------------------------------------------------------------|---------|
| `Darwin`     | `Remote/ChildProcess.swift`                                              | P4a     |
|              | `Security/Askpass.swift`                                                 | P4e     |
|              | `Security/CredentialLedger.swift`                                        | P4d     |
|              | `Sessions/JumpSharing.swift`                                             | P4c     |
|              | `Sessions/SerialPort.swift`                                              | P4g     |
|              | `Sessions/Tunnels.swift`                                                 | P4a     |
| `CryptoKit`  | `Remote/Transfer.swift`                                                  | P4h     |
|              | `Security/CredentialLedger.swift`                                        | P4d/P4h |
|              | `Sessions/JumpSharing.swift`                                             | P4c/P4h |
|              | `Support/UpdateCheck.swift`                                              | P4h     |
| `Security`   | `Security/KeychainStore.swift`                                           | P4d     |
| `Network`    | `Remote/FTPClient.swift`                                                 | P4h     |
| `CoreText`   | `Terminal/TerminalFont.swift`                                            | P4h     |
| `CoreGraphics`| `Sessions/OpenWindows.swift`                                            | P4h     |

**Total: 12 archivos únicos** de un núcleo de ~17 000 líneas.

## Lo que sí compila (preliminar)

Los módulos sin dependencias de plataforma (y que deberían compilar sin `#if`):
- Resaltado de sintaxis (`Resaltado/`)
- Pegado seguro (`Security/SafePaster.swift`)
- Formato de sesiones ssh_config (`Sessions/SessionFile.swift`)
- Paquetes SFTP (`Remote/SFTPPacket.swift`, `Remote/SFTPClient.swift`)
- Temas (todos los archivos `.tema` se cargan en runtime)

La medición exacta (P2 tarea 3) está pendiente: hay que envolver los 12 archivos en `#if !os(Windows)` y contar.

## Conclusión para la ADR 0001

- El núcleo tiene **12 archivos con dependencias de plataforma** de un total de ~80 archivos Swift.
- Esto representa una barrera **baja-media** para el camino A (Swift en Windows).
- Los módulos `Foundation`, `Dispatch`, y gran parte de la API son compatibles en Windows.
- Recomendación: continuar con el camino A (Swift nativo) según lo previsto en P3.
