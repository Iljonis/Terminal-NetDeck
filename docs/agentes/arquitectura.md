# Arquitectura (detalle)

Léelo antes de tocar sesiones, ventanas o pestañas, el entorno de ssh, la importación, las actualizaciones o los
errores. Las reglas en corto están en la raíz (CLAUDE.md / AGENTS.md); aquí, el porqué y los nombres.

- **Sesiones:** se guardan en el archivo propio de la app, en formato ssh_config (`SessionFile`, validado con
  `ssh -G`). `~/.ssh/config` sólo recibe un `Include`, y no hay ningún `sesiones.json` aparte: así `ssh core-01` vale
  desde cualquier terminal. Los datos propios de la app van como anotaciones: `# @grupo` (con `/` para carpetas),
  `# @clave`, `# @clave-grupo`, `# @desc`, `# @telnet`, `# @tipo sftp|ftp|serie|local`, `# @serie /dev/cu.x 9600 8N1`
  y `# @antiguo`. El perfil de cada sesión también: `# @tema`, `# @fuente`, `# @scrollback`, `# @teclado`, `# @prompt`.
- **Ventanas:** hay un `AppCore`, común a todas, con los ajustes, temas, sesiones, Llavero, botones, macros, túneles,
  espacios y resaltado, y con un `abiertas.json` por ventana con su marco. Cada ventana tiene su `AppModel`, con sus
  pestañas, vista dividida, MultiExec, hojas y avisos.
  - Lo común se lee con las propiedades de siempre (`model.settings`…), que reenvían a `AppCore`. Lo que afecta a
    todas las pestañas va por `core.allTabs`.
  - Una pestaña pasa de una ventana a otra sin cortar su conexión: `moveTab(_:to:)`, y `wire` la engancha a la nueva.
  - Los menús actúan sobre `core.front` y se refrescan con `MenuRefresh`, porque SwiftUI no los vuelve a evaluar con
    los cambios `@Observable`. Cada acción comprueba `modalOpen` al hacerse.
- **Entorno de las pestañas:** `TerminalEnvironment`. A ssh no le llegan `LANG` ni `LC_*` salvo que se active; sólo
  `LC_CTYPE=C.UTF-8`, sin el que ssh escribe en octal los acentos de los banners.
- **Importar:** `SessionImporter.safeExtra` quita las opciones que ejecutan órdenes. Los nombres, equipos y usuarios que
  empiezan por `-` se rechazan (`SessionManager.route`). Tamaño máximo, 20 MB.
- **Actualizaciones** (`UpdateChecker`, `UpdateCheck`, `Updater`): se buscan una vez al día, en silencio, y sólo se
  aceptan enlaces https de github.com. Nada se instala sin el clic en «Actualizar ahora». Entonces se baja el .dmg y se
  comprueba: el sha256 que publica GitHub, el mismo id, la versión anunciada y `codesign --verify`. Un ayudante
  sustituye la app al cerrarse (si falla, deja la de antes) y la reabre con sus pestañas. Registro:
  `~/Library/Logs/Terminal NetDeck/actualizar.log`.
- **Errores:** `ErrorLog` escribe en `~/Library/Application Support/Terminal NetDeck/logs/error.log`, con nivel y
  detalle, sin secretos.
