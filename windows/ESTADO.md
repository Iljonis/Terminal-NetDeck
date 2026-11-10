# Estado del trabajo de Windows

Cada sesión añade una entrada **arriba**, con fecha, dónde (Mac o Windows), qué se ha hecho, qué ha fallado y el
siguiente paso. Sin datos reales.

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
