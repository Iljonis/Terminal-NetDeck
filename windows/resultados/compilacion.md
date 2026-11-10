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

## Resultado con `#if !os(Windows)` (tarea 3) · 2026-11-10

Los 12 archivos envueltos; compilación avanza a [34/41] antes de que fallen los que dependen de ellos.

### Errores de cascada (6 archivos adicionales, 11 errores)

| Archivo                              | Tipo no encontrado   | Viene de               |
|--------------------------------------|----------------------|------------------------|
| `Productivity/JumpBatch.swift`       | `CredentialLedger`   | `Security/CredentialLedger.swift` |
| `Remote/RemoteEdit.swift`            | `RemoteFileVersion`  | `Remote/Transfer.swift` |
| `Remote/SFTPClient.swift`            | `ChildProcess`       | `Remote/ChildProcess.swift` |
| `Security/PasswordAutomation.swift`  | `CredentialLedger`   | `Security/CredentialLedger.swift` |
| `Sessions/ConnectionRoute.swift`     | `JumpSharing`        | `Sessions/JumpSharing.swift` |
| `Sessions/TerminalProfile.swift`     | `TerminalFont`       | `Terminal/TerminalFont.swift` |

### Avisos de Foundation en Windows (no fatales, pero a resolver en P4)

| Archivo                          | Aviso                                              |
|----------------------------------|----------------------------------------------------|
| `Productivity/Macros.swift:250,254` | `FileManager.replaceItemAt` — no implementado en Windows |
| `Support/AppPaths.swift:19`      | `getpid()` — usar `_getpid()` en Windows           |

`FileManager.replaceItemAt` se usa en la escritura atómica de `SafeFile`; necesitará una alternativa en P4.

### Lo que sí compila sin cambios

- `Resaltado/` completo (resaltado de sintaxis)
- `Security/SafePaster.swift` (pegado seguro)
- `Sessions/SessionFile.swift` (formato ssh_config)
- `Remote/SFTPPacket.swift` (paquetes SFTP)
- `Support/AppPaths.swift`, `DebugLog.swift`, `ErrorLog.swift`, `SafeFile.swift` (con avisos menores)
- Temas (`.tema`, carga en runtime)

`Remote/SFTPClient.swift` **no** compila sin cambios porque depende de `ChildProcess`.

## Conclusión para la ADR 0001

- **12 archivos con `import` de plataforma** + **6 archivos de cascada** = **18 archivos** con trabajo pendiente
  de un total de ~80 archivos Swift (~22%).
- **~62 archivos** (~78%) compilan en Windows sin ningún cambio.
- Barrera **baja-media** confirmada para el camino A (Swift nativo en Windows).
- Los módulos `Foundation`, `Dispatch`, y gran parte de la API son compatibles; sólo `FileManager.replaceItemAt`
  no está implementado en la versión actual de swift-corelibs-foundation para Windows.
- Recomendación: continuar con el camino A (Swift nativo) según lo previsto en P3.
