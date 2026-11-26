# ADR-0003: Paquete, firma y actualizaciones para Windows

**Fecha:** 2026-11-17
**Estado:** propuesta
**Deciden:** el autor (Jonay), con el contexto de P10

## Contexto

Terminal NetDeck para Windows necesita un instalador, firma de código y un mecanismo de actualización seguro. En macOS hay un `.dmg` verificado con sha256, `codesign --verify` y `Sparkle` (actualización solo con clic del usuario). En Windows hay dos grandes opciones de empaquetado y varias de firma.

La app usa **Sparse Package** (una identidad de paquete sin instalación de MSIX completo) para acceder al Windows App Runtime sin necesidad de un paquete completo. Esto restringe las opciones de distribución.

## Opciones de empaquetado

### Opción A: MSIX completo
- **Descripción:** se genera un `.msix` que se instala desde la tienda o con un clic. La app vive en `C:\Program Files\WindowsApps\…` (sandbox de AppX).
- **A favor:** integración con Microsoft Store, actualización automática opcional, firma fácil con Azure Code Signing.
- **En contra:** las apps MSIX están sandboxed: `ssh.exe`, `C:\Users\%USERNAME%\.ssh\config` y la escritura libre de archivos pueden verse restringidos. Requiere validación de que `ChildProcess` y `ConPTYProcess` funcionan dentro del sandbox de AppX. No hay precedente claro de apps de terminal en MSIX sin permisos especiales.

### Opción B: Instalador WiX / NSIS + Sparse Package (recomendada)
- **Descripción:** instalador `.exe` o `.msi` generado con **WiX Toolset 4** (Microsoft, código abierto). La app se instala en `C:\Program Files\Terminal NetDeck\`. El Sparse Package se registra durante la instalación para activar WinAppRuntime sin sandbox de AppX.
- **A favor:** sin restricciones de sandbox, `ChildProcess`/`ConPTY`/`ssh.exe` funcionan igual que hoy. Control total sobre el directorio de instalación. WiX es el estándar de Windows para instaladores `.msi`. Fácil integración en el workflow de Release de GitHub Actions (`windows-latest` incluye WiX 4).
- **En contra:** no hay entrada automática en Microsoft Store. El actualizador hay que implementarlo.
- **Riesgo:** Sparse Package requiere el `AppxManifest.xml` correcto y ejecutar `Add-AppxPackage --ExternalLocation` durante la instalación. Ya hay precedente en P8 (DDLM se instala así).

## Firma Authenticode

- **Sin certificado:** SmartScreen bloqueará la instalación con «Windows protegió tu PC». Inaceptable para distribución pública.
- **Opción 1 — Certificado OV (organización verificada):** unos 200-400 €/año. Tras ~50 instalaciones limpias, SmartScreen deja de avisar («reputación acumulada»). Se firma con `signtool.exe` en el workflow de Release.
- **Opción 2 — Azure Code Signing (ACS):** Plan de Microsoft; desde ~10 $/mes. Firma con reputación inmediata (EV equivalente) mediante una identidad verificada en Azure. Se integra en GitHub Actions con la action `azure/trusted-signing-action`. **Recomendado para lanzamiento público.**
- **Opción 3 — Certificado autofirmado:** solo para pruebas internas. No válido para distribución.

**Decisión propuesta:** Opción 2 (Azure Code Signing) para el lanzamiento público; Opción 3 para las builds de CI/pruebas internas mientras no hay suscripción.

## Mecanismo de actualización

Mismas reglas que macOS:
- Solo URLs `https://github.com/Iljonis/Terminal-NetDeck/releases/…`
- Verificar sha256 del instalador descargado antes de ejecutarlo.
- Verificar firma Authenticode con `WinVerifyTrust` antes de ejecutar.
- El instalador solo se lanza con el clic explícito del usuario («Instalar actualización»).
- Sin actualizaciones silenciosas, sin auto-reinicio.

Implementación: un `UpdateChecker` en `Sources/NetDeckCore` (con `#if os(Windows)`) que:
1. Consulta `https://api.github.com/repos/Iljonis/Terminal-NetDeck/releases/latest`.
2. Compara la versión del campo `tag_name` con `Bundle.main.infoDictionary["CFBundleShortVersionString"]`.
3. Si hay actualización, muestra el aviso en la interfaz con el changelog y el botón «Descargar e instalar».
4. Descarga el `.msi`/`.exe` a una carpeta temporal, verifica sha256 y firma, y lo lanza con `ShellExecuteW` a `runas` para que el UAC pida la elevación necesaria.

## Manifiesto de winget (opcional)

Publicar en el repositorio `winget-pkgs` de Microsoft permite instalar con `winget install TerminalNetDeck`. Requiere que la release de GitHub sea pública y el instalador tenga firma válida. Puede hacerse tras el primer lanzamiento público.

## Decisión

**Opción B** (WiX + Sparse Package) para el primer lanzamiento. Firma con certificado autofirmado en CI/pruebas; Azure Code Signing para el lanzamiento público (decisión económica del autor). Actualizador propio siguiendo las reglas de seguridad de macOS.

## Consecuencias

- P10 implementa el `.wxs` de WiX, el `AppxManifest.xml` del Sparse Package y el `UpdateChecker`.
- El workflow de Release en `.github/workflows/` (que gestiona Codex) firma con Azure Code Signing cuando la variable `AZURE_TENANT_ID` esté configurada en los secretos del repo; si no, produce un instalador sin firma (solo para pruebas).
- P4e (SSH_ASKPASS.exe) debe estar en el instalador antes del lanzamiento.

## Referencias

- [WiX Toolset 4](https://wixtoolset.org/)
- [Sparse Package](https://learn.microsoft.com/windows/apps/desktop/modernize/sparse-packages-overview)
- [Azure Trusted Signing](https://learn.microsoft.com/azure/trusted-signing/)
- [ADR-0001](0001-camino-para-windows.md) — decisión de camino A (Swift + WinUI 3)
- [ADR-0002](0002-credenciales-windows.md) — credenciales CredReadW
