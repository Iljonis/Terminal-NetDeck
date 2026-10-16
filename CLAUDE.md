# Terminal NetDeck

App nativa de macOS (Swift 6 / SwiftUI + SwiftTerm) para ingenieros de red. Ver README.md para funciones y uso.
Repositorio público: https://github.com/Iljonis/Terminal-NetDeck

## Comandos

- `swift build` · `swift run TerminalNetDeck` (desarrollo; `-idioma en` en inglés; cualquier ajuste se puede forzar
  igual: `-sshConfigPath /ruta`, `-themeID neo-tokyo`…)
- `./test.sh` — primero `tools/privacidad.sh` (nada personal en lo que se publica) y luego los tests del núcleo (Swift
  Testing). Siempre en verde antes de un commit. También en GitHub Actions.
- `tools/privacidad.sh [--binario]` — IPs privadas, rutas `/Users/…`, correos, claves, tokens y contraseñas en el código,
  temas, reglas y plantillas; con `--binario` también la app de `build/` y el `.dmg`. Tus direcciones (las de tu
  ssh_config y las de `tools/privacidad.local`, que no se sube) se comprueban sin publicarlas.
- `tools/seguridad_cron.sh` — auditoría periódica: dependencias contra OSV.dev (CVE/GHSA), privacidad, tests y
  endurecimiento; en GitHub, `.github/workflows/seguridad.yml` cada lunes. Informe en `~/Library/Logs/Terminal NetDeck/seguridad.log`.
- `./install.sh` (instalar) · `./install.sh --dmg` (empaquetar) · `./actualizar.sh` (reinstala y reabre con las pestañas)
  · las actualizaciones miran `Iljonis/Terminal-NetDeck` (otro con `NETDECK_REPO=usuario/repo`, ninguno con `NETDECK_REPO=`).
- Capturas: `tools/capturas.sh` (README) o a mano con `NETDECK_HOME=<carpeta temporal con tools/demo>`
  `NETDECK_SNAPSHOT=/ruta.png [NETDECK_SNAPSHOT_ACTION=settings:general|settings:botones|tab:usuario@equipo|setup:0|sesion-nueva|explorador|explorador:vista|pestañas:N]`
  (el explorador, con `NETDECK_SFTP_SERVER=/usr/libexec/sftp-server NETDECK_SFTP_DIR=<carpeta>`: SFTP sin ssh ni red).
  NETDECK_HOME cambia la carpeta personal: nunca captures con tus datos reales (sesiones, recientes, pestañas).

## Idiomas (castellano de España e inglés)

- El código está en castellano de España; la interfaz se traduce al inglés. Selector en Ajustes → General → Idioma
  (`AppSettings.language`, clave `idioma` en UserDefaults); se aplica al momento.
- Todo texto visible va con `L("…")` (`NetDeckCore/Support/Idioma.swift`). La clave es el texto en castellano con `%@`
  por cada valor interpolado; su inglés va en `NetDeckCore/Support/Ingles.swift`. Si cambias un texto, cambia su clave
  y borra la que ya no se use.
- Nombres que vienen de datos (grupos de temas o de sesiones) se muestran con `L(nombre:)` y se listan en
  `Idioma.nombresConocidos`.
- NO se traduce: registros de depuración (`DebugLog`), claves de UserDefaults, ids, regex, formato del ssh_config o de
  los `.tema`, órdenes ssh, ni valores que se guardan (p. ej. el grupo «General»).
- `IdiomaTests` falla si una `L("…")` no tiene inglés o si los `%@` no cuadran.
- Textos neutros: no compararse con «NetDeck» (la herramienta bash anterior); la marca «Terminal NetDeck» sí.

## Arquitectura y reglas que no se rompen

- **Sesiones**: se guardan en el archivo propio de la app en formato ssh_config (`SessionFile`, validado con `ssh -G`);
  `~/.ssh/config` sólo recibe un `Include`. Nada de un `sesiones.json` aparte: así `ssh core-01` vale desde cualquier
  terminal. Datos propios como anotaciones: `# @grupo` (con `/` = carpetas), `# @clave`, `# @clave-grupo`, `# @desc`,
  `# @telnet`, `# @tipo sftp|ftp|serie|local`, `# @serie /dev/cu.x 9600 8N1`, `# @antiguo`.
- **Archivos del usuario** (ssh_config, botones.txt, listas): siempre con `SafeFile` (no se pisa lo que no se puede
  leer; `.anterior` y `.original`; escritura atómica 0600). Carpetas con `AppPaths.ensure` (0700).
- **Contraseñas**: sólo en el Llavero (`KeychainStore` vía `/usr/bin/security`, el secreto por stdin, nunca en
  argumentos ni en `DebugLog`). Regla de usuario estricta (`CredentialPolicy`); un fallo bloquea 15 min en todas las
  pestañas (`CredentialLedger`). Lecturas del Llavero fuera del hilo principal.
- **MultiExec y pegado**: sólo a pestañas ssh/telnet (`route.isLocal` y los tipos sftp/serie/ftp quedan fuera). El
  pegado seguro se para ante errores, paginadores, órdenes peligrosas sin confirmar o un prompt de contraseña.
- **Entorno de las pestañas**: `TerminalEnvironment` (a ssh no le llegan `LANG`/`LC_*` salvo que se active; sólo
  `LC_CTYPE=C.UTF-8`, sin el que ssh escribe los acentos de los banners en octal).
- **Importar**: `SessionImporter.safeExtra` quita opciones que ejecutan órdenes; nombres/equipos/usuarios que empiezan
  por `-` se rechazan (`SessionManager.route`); 20 MB máximo.
- **Pestañas al arrancar**: no se guardan ni reabren las de loopback (127.x/localhost) ni las de las capturas.
- **Actualizaciones** (`UpdateChecker`/`UpdateCheck`/`Updater`): se buscan una vez al día, en silencio; sólo enlaces
  https de github.com. Nada se instala sin el clic en «Actualizar ahora»: entonces se baja el .dmg, se comprueba
  (sha256 que publica GitHub, mismo id, versión anunciada, `codesign --verify`), un ayudante sustituye la app al
  cerrarse (si falla, deja la de antes) y la reabre con sus pestañas. Registro: `~/Library/Logs/Terminal NetDeck/actualizar.log`.
- **Errores**: `ErrorLog` (`~/Library/Application Support/Terminal NetDeck/logs/error.log`, nivel y detalle, sin
  secretos); los mensajes al usuario van por `model.status` y sólo los que empiezan por ✗ 🔑 ⎋ ⬆ salen como aviso.
- **Rutas en pantalla**: siempre con `AppPaths.tilde(…)` (la carpeta personal como «~»; así tampoco salen en capturas).
- Ejemplos y tests sin datos reales: IPs `192.0.2.x` / `198.51.100.x` / `203.0.113.x` (RFC 5737), `tu.usuario`,
  `core-01`, `bastion`.

## Git

- Autor: `Jonay <jonayrr.jr@gmail.com>` (git config local del repo). Nunca el correo corporativo. Sin línea de coautor.
- Mensajes de commit en castellano: título corto y viñetas con el porqué.
- Forzar un push (`--force`) sólo si el autor lo pide expresamente.

## Agentes

Para trabajo grande o revisiones se usan agentes; los de este proyecto están en `.claude/agents/` y conocen ya estas
reglas. Los de ECC (plugin) se usan para auditorías de sólo lectura.

| Agente | Para qué | Cómo |
|---|---|---|
| `netdeck-implementador` (proyecto) | Funciones nuevas o cambios grandes | En `isolation: worktree`; deja su trabajo en una rama con commits; luego se revisa y se fusiona a `main` |
| `netdeck-auditor` (proyecto) | Revisión de un cambio: errores, seguridad y estabilidad con las reglas de arriba | Sólo lectura; informe con archivo:línea y arreglo |
| `ecc:security-reviewer` | Secretos, datos personales, Llavero, inyección de órdenes, actualizaciones, scripts | Sólo lectura, antes de cada versión |
| `ecc:code-reviewer` | Errores reales en el diff (`git diff <base>..HEAD`) | Sólo lectura |
| `ecc:silent-failure-hunter` | Errores tragados, pérdida de datos, bloqueos de procesos | Sólo lectura |
| `ecc:performance-optimizer` | Fugas de memoria, congelaciones del hilo principal, CPU | Sólo lectura |
| `ecc:swift-reviewer` · `ecc:swift-build-resolver` | Revisión idiomática de Swift · arreglar compilaciones rotas | Según haga falta |
| `ecc:opensource-sanitizer` | Comprobar que el repo público no lleva nada privado | Antes de publicar una versión |

Cómo se trabaja con ellos:
1. Encargo preciso: qué archivos tocar, qué reglas aplican (este archivo), qué no tocar si hay otro trabajo en paralelo.
2. Implementación en worktree; dos agentes que tocan `Ingles.swift` o los mismos archivos de Ajustes, mejor uno detrás
   del otro (al fusionar, los conflictos de «añadidos al final» se resuelven quedándose con ambos lados).
3. Revisión del diff (sobre todo contraseñas, MultiExec, archivos del usuario y textos sin traducir) antes de fusionar.
4. `swift build` + `./test.sh` en verde tras fusionar; si hay interfaz nueva, una captura con `NETDECK_HOME` de ejemplo.
5. Tras la implementación, una pasada de `netdeck-auditor` o de los de ECC; se arreglan los hallazgos reales y se
   descartan con motivo los que no lo son.

## Publicar una versión

**OBLIGATORIO en cada cambio de versión**: actualizar siempre `README.md`, `README.en.md`, `install.sh` y todos los
ficheros de documentación o scripts que contengan el número de versión actual antes de etiquetar (tag) o publicar una
release. Compruébalo con `grep -rnE "v?[0-9]+\.[0-9]+\.[0-9]+" README*.md install.sh docs tools` y que ninguno se quede
en la versión anterior.

1. `VERSION` en `install.sh`; «Versión actual» en `README.md` y «Current version» en `README.en.md`; `./test.sh`; `tools/seguridad_cron.sh`; pasada de `ecc:security-reviewer` /
   `ecc:opensource-sanitizer`.
2. Commit, push, `git tag -a vX.Y.Z -m "Terminal NetDeck X.Y.Z"` y `git push origin vX.Y.Z`.
3. Nada más: `.github/workflows/release.yml` comprueba que el tag y `VERSION` coinciden, pasa los tests, hace el .dmg,
   `tools/privacidad.sh --binario` y crea la Release con el .dmg. La app se la ofrece («Actualizar ahora») a quien
   tenga una versión anterior; tu copia instalada también.
