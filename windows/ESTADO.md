# Estado del trabajo de Windows

Cada sesión añade una entrada **arriba**, con fecha, dónde (Mac o Windows), qué se ha hecho, qué ha fallado y el
siguiente paso. Sin datos reales.

## 2026-11-10 · Windows · P0: comprobación del entorno

- Hecho: clonado el repo en Windows, configurado `core.autocrlf false` y autor git (`Jonay <jonayrr.jr@gmail.com>`),
  skills copiadas a `.claude\skills\`, ejecutado `comprobar-entorno.ps1`.
- Corregidos tres bugs del script para PowerShell 5.1 en Windows: `$min:` interpretado como unidad de disco,
  NativeCommandError con `ssh -V 2>&1`, y rutas POSIX de git de MSYS2/DevKitPro (corregido con `cygpath`).
- Resultado: 2 fallos. Ver `windows/resultados/entorno.md`.
- **Pendiente para cerrar P0:** instalar Swift 6.2+ y Visual Studio 2022 Build Tools con «Desarrollo para el
  escritorio con C++». Sin esto no se puede hacer P2.
- **Siguiente paso:** instalar Swift + VS Build Tools (el autor, a mano), ejecutar el script de nuevo hasta 0 fallos,
  y luego P1 y P2 en paralelo.

## 2026-11-10 · Mac · Propuesta inicial
- Hecho: estudio de viabilidad ([ESTUDIO.md](ESTUDIO.md)), comparación con otras apps, plan por pasos
  ([PLAN.md](PLAN.md)), ADR 0001 en estado «propuesta», scripts de comprobación para Windows y borrador de CI.
- Comprobado en el Mac: `./test.sh` en verde (705 tests) y `tools/privacidad.sh` en verde. No se ha tocado `Sources/`.
- Sin comprobar: nada se ha ejecutado aún en Windows; los scripts de `scripts/` no se han probado en un Windows real.
- **Siguiente paso:** P0 (preparar el PC con Windows) y después P1 y P2, que se pueden hacer en paralelo.
