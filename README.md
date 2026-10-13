# Terminal NetDeck

Terminal nativo de macOS para ingenieros de red: sesiones de tu `ssh_config` con saltos, contraseñas en el Llavero con
una regla de usuario estricta, MultiExec, pegado seguro, resaltado de la salida tipo ChromaTerm y 43 temas.
Swift 6 · SwiftUI · [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). Español (España) e inglés.

*[English below](#english)*

![Portada](docs/capturas/portada.png)

## Qué hace

- **Sesiones** de tu `~/.ssh/config` (comodines, `Include`, `ProxyJump`), por grupos, con favoritas y recientes.
  Anotaciones propias en comentarios: `# @grupo`, `# @clave`, `# @clave-grupo`, `# @desc`, `# @telnet`.
- **Saltos**: `ssh -J`; si el salto no deja reenviar, la app entra en él y escribe `ssh equipo` por ti. Telnet por el salto.
- **Contraseñas sólo en el Llavero** de macOS. La de la sesión entra sola (askpass); las de los equipos, escritas solas,
  sugeridas o nada. **Regla de usuario**: nunca se escribe la contraseña de otro usuario, y si una falla queda bloqueada
  15 min en todas las pestañas (para no bloquear cuentas de AD).
- **MultiExec** y **vista dividida**: lo que escribes va a la vez a varios paneles (excluye los que quieras).
- **Pegado seguro**: línea a línea esperando al prompt; se para ante errores de la CLI, paginadores, órdenes peligrosas
  sin confirmar (`reload`, `delete`…) o si el equipo pide una contraseña.
- **Listas por salto**: la misma orden en muchos equipos detrás de un salto, probando la contraseña de uno en uno.
- **Barra de botones** (órdenes, textos, contraseñas, logins), **registro** de sesiones a texto limpio y **búsqueda**
  en todos los registros (IP, MAC en cualquier formato, interfaz…).
- **Importar** sesiones de SecureCRT, MobaXterm, PuTTY, electerm, CSV u otro `ssh_config` (nunca contraseñas).
- **Resaltado** de la salida con reglas tipo ChromaTerm, con los colores del tema.

| Temas | Resaltado |
|---|---|
| ![Temas](docs/capturas/temas.png) | ![Resaltado](docs/capturas/resaltado.png) |

## Instalar

**Como cualquier app de macOS:** descarga `Terminal-NetDeck.dmg` de
[Releases](https://github.com/Iljonis/Terminal-NetDeck/releases), ábrelo y arrastra **Terminal NetDeck** a
**Aplicaciones**. Sus datos van a `~/Library/Application Support/Terminal NetDeck/` y sus ajustes a las preferencias
del sistema; las contraseñas, sólo al Llavero. Nada se guarda en la carpeta del proyecto.

**Desde el código.** Requisitos: macOS 15 o posterior y Swift 6 (Xcode o las Command Line Tools: `xcode-select --install`).

```bash
git clone https://github.com/Iljonis/Terminal-NetDeck.git
cd Terminal-NetDeck
./install.sh                 # compila y la instala en /Applications (o ~/Applications)
```

| Orden | Para qué |
|---|---|
| `./install.sh --usuario` | Instalarla en `~/Applications` |
| `./install.sh --dmg` | Crear `dist/Terminal-NetDeck.dmg` (doble clic en la app → asistente de instalación) |
| `./install.sh --asistente` | Abrir el asistente sin instalar (para probarlo) |
| `./actualizar.sh` | Actualizar desde el código: compila, sustituye la app y la reabre con tus pestañas |
| `./install.sh --fuente "Kode Mono"` | Instalar una fuente con Homebrew |
| `./desinstalar.sh [--todo]` | Quitar la app (`--todo`: también temas y ajustes; el Llavero no se toca) |

La app no está firmada por Apple: la primera vez que la abras en otro Mac, clic derecho → Abrir.

![Asistente](docs/capturas/asistente.png)

### Actualizaciones

La app busca versiones nuevas en segundo plano, como mucho una vez al día (al arrancar, si ha pasado más de un día, y
luego cada 24 h), sin interrumpir nada. Si hay una, sale un aviso discreto en la barra de estado
(«⬆ Versión X disponible»); al pulsarlo ofrece descargarla. Nunca descarga ni instala nada sola. Se puede desactivar o
buscar a mano en Ajustes → General → Actualizaciones. Mira las releases (o, si no hay, los tags `vX.Y.Z`) del
repositorio que se indica al compilar: `NETDECK_REPO=usuario/repo ./install.sh`.

## Atajos

| | |
|---|---|
| ⌘K | Conectar (sesión o `usuario@equipo[:puerto]`, directo o por un salto) |
| ⇧⌘L | Lista por salto |
| ⇧⌘V | Pegado seguro |
| ⇧⌘M | MultiExec |
| ⌘F / ⇧⌘F | Buscar en la salida / en todos los registros |
| Esc o ⌘. | Cortar cualquier secuencia automática |
| ⌘, | Ajustes |

## Desarrollo

```bash
swift build
swift run TerminalNetDeck              # -idioma en: en inglés
./test.sh                              # tests del núcleo
tools/capturas.sh                      # regenera docs/capturas con datos de ejemplo (tools/demo)
```

| Módulo | Contenido |
|---|---|
| `NetDeckCore/Sessions` | `ssh_config`, saltos, `ssh -J`, telnet por el salto, importadores |
| `NetDeckCore/Security` | Llavero vía `/usr/bin/security`, askpass, regla de usuario, marcas «probando/fallo» compartidas |
| `NetDeckCore/Productivity` | Pegado seguro, MultiExec, listas por salto, barra de botones |
| `NetDeckCore/Highlight` · `Themes` | Resaltado tipo ChromaTerm · formato `.tema` y catálogo |
| `NetDeckCore/Support` | Rutas, registro de depuración, actualizaciones, idiomas (`L("…")` + `Ingles.swift`) |
| `NetDeckSSH` | SSH nativo con SwiftNIO SSH (en preparación) |
| `TerminalNetDeck` | La app (SwiftUI) |
| `Temas/` · `Resaltado/` | Catálogo de temas y reglas de resaltado |

Las convenciones (textos traducibles, datos de ejemplo, contraseñas) están en [CLAUDE.md](CLAUDE.md).

Compatible con NetDeck (bash + tmux): mismo Llavero, mismo `ssh_config` con sus anotaciones, mismos `.tema` y botones;
la primera vez importa `clave.conf` y `tema.conf`.

---

## English

Native macOS terminal for network engineers: sessions from your `ssh_config` with jump hosts, Keychain passwords with a
strict per-user rule, MultiExec, safe paste, ChromaTerm-style output highlighting and 43 themes. The interface is
available in Spanish (Spain) and English: **Settings → General → Language** (applies instantly).

![Home screen](docs/capturas/portada-en.png)

- **Passwords live only in the macOS Keychain.** A password is only typed automatically when it belongs to exactly the
  user being asked for; a failed one is locked for 15 minutes in every tab, so AD accounts don't get locked out.
- **Safe paste** sends line by line, waiting for the prompt, and stops on CLI errors, pagers, unconfirmed dangerous
  commands or a password prompt.
- **MultiExec, split view, lists via a jump host, command buttons, session logging and log search.**
- **Import** sessions from SecureCRT, MobaXterm, PuTTY, electerm, CSV or another `ssh_config` (never passwords).

Install: download `Terminal-NetDeck.dmg` from Releases and drag the app to Applications (data lives in
`~/Library/Application Support/Terminal NetDeck/`, passwords only in the Keychain), or build it with macOS 15+ and
Swift 6: `./install.sh`. New versions are checked silently at most once a day; a discreet status-bar notice offers the
download, nothing is installed automatically. Development: `swift run TerminalNetDeck
-idioma en`, tests with `./test.sh`, screenshots with `tools/capturas.sh`.

![Settings](docs/capturas/ajustes-en.png)
