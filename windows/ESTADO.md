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
