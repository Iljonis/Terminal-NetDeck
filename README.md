# Terminal NetDeck

Terminal nativo de macOS para ingenieros de red: sesiones de tu `ssh_config` con saltos, contraseñas en el Llavero con
una regla de usuario estricta, MultiExec, pegado seguro, resaltado de la salida tipo ChromaTerm y 51 temas.
Swift 6 · SwiftUI · [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). Español (España) e inglés.

*[English below](#english)*

![Portada](docs/capturas/portada.png)

## Qué hace

- **Sesiones** de tu `~/.ssh/config` (comodines, `Include`, `ProxyJump`), por grupos (con `/`, carpetas dentro de
  carpetas: `Clientes/Madrid/Core`), con favoritas y recientes. Se crean, editan, duplican, borran y ordenan en el gestor.
  Anotaciones propias en comentarios: `# @grupo`, `# @clave`, `# @clave-grupo`, `# @desc`, `# @telnet`,
  `# @tipo sftp|ftp|serie|local`, `# @serie /dev/cu.usbserial-0001 9600 8N1`.
- **Tipos de sesión**: SSH, Telnet, SFTP (`/usr/bin/sftp` con el mismo alias y saltos), FTP (en el Finder, sólo
  lectura: macOS no trae cliente), terminal local y consola por puerto serie (`/usr/bin/screen`).
- **Saltos**: `ssh -J`; si el salto no deja reenviar, la app entra en él y escribe `ssh equipo` por ti. Telnet por el salto.
- **Contraseñas sólo en el Llavero** de macOS. La de la sesión entra sola (askpass); las de los equipos, escritas solas,
  sugeridas o nada. **Regla de usuario**: nunca se escribe la contraseña de otro usuario, y si una falla queda bloqueada
  15 min en todas las pestañas (para no bloquear cuentas de AD). Se ven, se editan y se borran en Ajustes → Contraseñas
  (con qué sesiones y grupos las usan), y desde el menú 🔑 se escribe cualquiera en la pestaña activa, también «sin
  esperar a que la pida» para prompts que la app no reconoce.
- **MultiExec** y **vista dividida**: lo que escribes va a la vez a varios paneles (excluye los que quieras).
- **Pegado seguro**: línea a línea esperando al prompt; se para ante errores de la CLI, paginadores, órdenes peligrosas
  sin confirmar (`reload`, `delete`…) o si el equipo pide una contraseña.
- **Listas de equipos** (Herramientas → Listas de equipos, ⇧⌘L): la misma orden en muchos equipos detrás de un salto,
  probando la contraseña de uno en uno.
- **Terminal local** (⌘T) y **sesión de inicio** (clic derecho → Abrir al arrancar; ⌥⌘K para abrirla).
- **Barra de botones** personalizable: categorías (crear, renombrar, ordenar, borrar) y botones de orden, texto,
  contraseña o login (eligiendo la contraseña del Llavero de una lista), sesión; con teclas F1–F12 y huecos `{{vlan=100}}`.
- **Registro** de sesiones a texto limpio y **búsqueda** en todos los registros (IP, MAC en cualquier formato, interfaz…).
- **Servidores Linux sin avisos de locale**: por defecto ssh no manda el idioma del Mac (`LANG`, `LC_*`); se puede
  activar en Ajustes → General → Conexiones.
- **Importar** sesiones de SecureCRT, MobaXterm, PuTTY, electerm, CSV u otro `ssh_config` (nunca contraseñas).
  **Exportar** todas o unos grupos a JSON (todos los campos) o CSV, sin contraseñas; el JSON se vuelve a importar.
- **Resaltado** de la salida con reglas tipo ChromaTerm, con los colores del tema.
- **51 temas** en 8 grupos (galería en Ajustes → Temas), con su paleta ANSI y su fuente; pueden **seguir al Mac**
  (uno claro y otro oscuro) y se importan los tuyos (`.tema`). Todos pasan una prueba de contraste WCAG.
- **Actualizaciones** comprobadas en silencio una vez al día (nunca se instala nada sola) e **idioma** de la interfaz
  en español o inglés (Ajustes → General → Idioma), al momento.

| Temas | Resaltado |
|---|---|
| ![Temas](docs/capturas/temas.png) | ![Resaltado](docs/capturas/resaltado.png) |

## Temas

Cada tema es un archivo `.tema` de texto en `Temas/` (`clave = valor`: colores, fuentes, paleta ANSI…); para crear el
tuyo copia uno, cambia los colores e impórtalo. Todos cumplen un contraste mínimo (WCAG): texto ≥ 4,5:1, texto
apagado ≥ 3:1, pestaña activa ≥ 4,5:1 y colores ANSI ≥ 3:1 (lo comprueba `ThemeTests`). Además está la de serie,
**NetDeck Cyberpunk**.

| Grupo | Tema | Cómo es |
|---|---|---|
| **Cyberpunk** | **Neón 2077** | Amarillo portada, cian y rojo neón. |
|  | **Corpo rojo** | Negro, rojo corporativo y blanco. Sobrio, con rótulos en kanji. |
|  | **Neo-Tokyo** | Cyberpunk japonés: índigo profundo, magenta y cian. |
|  | **Synthwave** | Atardecer retrowave: rosa, violeta y naranja. |
|  | **Grid** | Negro absoluto con cian eléctrico y naranja (estilo Tron). |
|  | **Vaporwave** | Turquesa y rosa pastel sobre violeta, estética noventera. |
| **Sistemas** | **Liquid Glass** | Como macOS 27: cristal transparente y desenfocado, con los colores del sistema. Legible sobre cualquier fondo. |
|  | **Liquid Glass Claro** | macOS 27 de día: vidrio claro y desenfocado, texto oscuro bien legible. |
|  | **Windows 11** | Fluent y Mica: gris oscuro con un toque translúcido, acento azul, Cascadia Mono y la paleta Campbell de Windows Terminal. |
|  | **Windows 11 Claro** | Fluent de día: Mica clara, acento azul y la paleta «One Half Light» de Windows Terminal (legible en claro). |
| **Anime y cine** | **Unidad-01** | Morado y verde neón, avisos en naranja (estilo EVA-01). |
|  | **Unidad-02** | Rojo y naranja intensos con verde lima (estilo EVA-02). |
|  | **Neo-Tokio rojo** | Rojo moto, negro y blanco con kanji (estilo Akira). |
|  | **Fantasma rojo** | Rojo, negro y blanco con contraste brutal (estilo Persona 5). |
|  | **Replicante** | Neblina naranja y azul petróleo (estilo Blade Runner). |
|  | **Sección 9** | Verde agua y blanco sobre pizarra (estilo Ghost in the Shell). |
|  | **Bosque** | Verdes musgo, cielo y tonos cálidos (estilo Ghibli). |
|  | **Andén** | Panel LED naranja de estación japonesa. |
| **Kawaii** | **Kawaii futurista** | Lavanda oscuro, rosa, menta y lila. Detalles ♡ ✧. |
|  | **Sakura** | Clara y suave, para fondo blanco. |
|  | **Alba rosa** | Clara de amanecer: crema, rosa viejo, lirio y pino (inspirada en Rosé Pine Dawn). |
| **Retro** | **Fósforo** | Monitor clásico de fósforo verde. |
|  | **Ámbar** | Terminal ámbar de los 80, cálida para muchas horas. |
|  | **Otoño retro** | Cálida y con poco azul, inspirada en Gruvbox: buena para la noche. |
|  | **Monokai** | La de los editores de siempre: verde, amarillo y rosa intensos sobre gris oliva. |
|  | **Trigo** | Papel crema con tinta tostada y colores de tierra (inspirada en Gruvbox claro): pareja diurna de Otoño retro. |
| **Sobrias** | **Ártico** | Sobria con contraste: hielo, aurora y ámbar. |
|  | **Medianoche** | Azules y violetas suaves (estilo Tokyo Night). |
|  | **Vampiro** | Morado, rosa y verde sobre gris (estilo Dracula). |
|  | **Océano profundo** | Azul abisal con brillos aguamarina y coral. |
|  | **Grafito** | Oscura suave para trabajar con el Mac en modo claro: gris carbón en vez de negro, no deslumbra al pasar de una ventana clara a la terminal. |
|  | **Solar oscuro** | La paleta clásica Solarized en oscuro: poco contraste, descansa la vista en turnos largos. |
|  | **Solar claro** | La misma paleta Solarized en claro: pareja de Solar oscuro (ideal en modo Auto). |
|  | **Moca** | Pasteles suaves sobre fondo oscuro, inspirada en Catppuccin Mocha. |
|  | **Fiordo** | Gris pizarra ártico con azules escarcha y aurora tenue (inspirada en Nord): calma para turnos largos. |
|  | **Café con leche** | Clara y cremosa con pasteles con cuerpo (inspirada en Catppuccin Latte): pareja diurna de Moca. |
|  | **Gran ola** | Tinta índigo, papel envejecido y azules de grabado japonés (inspirada en Kanagawa). |
|  | **Taiga** | Verde bosque apagado con salvia, arena y musgo (inspirada en Everforest): suave y muy cálida. |
| **Prácticas** | **Accesible** | Para daltonismo: bien en azul, mal en naranja. |
|  | **Alto contraste** | Blanco puro sobre negro y colores al máximo. |
|  | **Pro** | El perfil «Pro» de Terminal de macOS: texto claro sobre negro y los colores brillantes de siempre. |
|  | **Papel** | Clara y muy legible: para oficinas con mucha luz, el proyector o compartir pantalla en una reunión. |
|  | **NOC** | Para pantallas de guardia: todo lo normal en tonos apagados y las alarmas (down, errores, pérdidas) saltando a la vista. |
|  | **Guardia ámbar** | Consola de NOC muy legible: ámbar sobre negro cálido, letra grande y estados en colores inconfundibles. |
|  | **Guardia verde** | Consola de NOC muy legible: verde suave sobre negro, alarmas en rojo y avisos en ámbar. |
| **Corporativas** | **DIGI** | Azul DIGI Mobil (#1275B7) y el punto rojo del logo, sobre azul marino. |
|  | **Oracle** | Rojo Oracle (#C74634) sobre el gris cálido de Redwood (#312D2A). |
|  | **Cisco** | Azul Cisco (#049FD9) sobre azul noche, con los colores de estado de Cisco. |
|  | **Juniper** | Verde Juniper (#84B135) y lima (#CCDB2A) sobre gris pizarra. |
|  | **Huawei** | Rojo Huawei (#CF0A2C) y su negro (#232527). |
|  | **Ubuntu** | Naranja Ubuntu (#E95420) sobre berenjena (#300A24), como su terminal. |

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
| `./install.sh --dmg` | Crear `dist/Terminal-NetDeck.dmg` (arrastrar la app a Aplicaciones, o doble clic → asistente) |
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

## Seguridad

- Contraseñas sólo en el Llavero (nunca en archivos, argumentos ni registros); la regla de usuario y el bloqueo de
  15 min tras un fallo evitan bloquear cuentas de AD.
- MultiExec y el pegado seguro sólo llegan a pestañas ssh/telnet: nunca a una terminal local, SFTP o consola serie.
- Al importar sesiones se quitan las opciones de ssh que ejecutan órdenes (`ProxyCommand`, `LocalCommand`, `Match`…);
  nombres, equipos o usuarios que empiezan por `-` se rechazan.
- Tus archivos (`ssh_config`, `botones.txt`, listas) nunca se sobrescriben si no se pueden leer; copia `.anterior` en
  cada guardado y `.original` la primera vez. Carpetas y archivos de la app sólo para ti (0700/0600).
- Actualizaciones: sólo enlaces https de github.com, y nada se descarga ni instala sin que lo pidas.
- Firma ad hoc con hardened runtime.

## Atajos

| | |
|---|---|
| ⌘K | Conectar (sesión o `usuario@equipo[:puerto]`, directo o por un salto) |
| ⌘T | Nueva terminal local |
| ⌥⌘K | Abrir la sesión de inicio |
| ⇧⌘L | Listas de equipos |
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

Las convenciones (textos traducibles, datos de ejemplo, contraseñas, seguridad) y cómo se trabaja con agentes de
revisión están en [CLAUDE.md](CLAUDE.md). Los tests se ejecutan en GitHub Actions en cada push.

Archivos de configuración en `~/.config/netdeck/` (`ssh_config` de sesiones, `botones.txt`, temas
`.tema`); la primera vez se leen `clave.conf` y `tema.conf` si existen.

---

## English

Native macOS terminal for network engineers: sessions from your `ssh_config` with jump hosts, Keychain passwords with a
strict per-user rule, MultiExec, safe paste, ChromaTerm-style output highlighting and 51 themes. The interface is
available in Spanish (Spain) and English: **Settings → General → Language** (applies instantly).

![Home screen](docs/capturas/portada-en.png)

- **Passwords live only in the macOS Keychain.** A password is only typed automatically when it belongs to exactly the
  user being asked for; a failed one is locked for 15 minutes in every tab, so AD accounts don't get locked out.
- **Safe paste** sends line by line, waiting for the prompt, and stops on CLI errors, pagers, unconfirmed dangerous
  commands or a password prompt.
- **MultiExec, split view, device lists via a jump host, command buttons, session logging and log search.**
- **Local terminal** (⌘T) and a **startup session** that opens at launch (⌥⌘K opens it on demand).
- **Session types:** SSH, Telnet, SFTP, FTP (in Finder), local shell and serial console (`screen`), organised in nested
  folders (`Clients/Madrid/Core`), with a full session manager (create, edit, duplicate, reorder, delete).
- **Import** sessions from SecureCRT, MobaXterm, PuTTY, electerm, CSV or another `ssh_config`, and **export** them to
  JSON/CSV to share (never passwords; imported files can't bring command-running ssh options).
- **Customisable button bar** with categories; password and login buttons pick the Keychain entry from a list.
- **No locale warnings on Linux servers:** ssh doesn't send the Mac's `LANG`/`LC_*` unless you enable it.
- **ChromaTerm-style highlighting** in the theme's colours.
- **51 themes** in 8 groups (Cyberpunk, Systems, Anime & film, Kawaii, Retro, Subdued, Practical, Corporate; full
  list in the [Temas](#temas) table): Liquid Glass and Windows 11 looks, Solarized-, Nord-, Gruvbox-, Catppuccin-,
  Kanagawa- and Everforest-inspired palettes, high-legibility NOC consoles and vendor colours (Cisco, Juniper, Huawei…).
  They can follow the Mac's light/dark mode, you can import your own `.tema` files, and every theme passes a WCAG
  contrast test (text ≥ 4.5:1, dim text ≥ 3:1).

Install: download `Terminal-NetDeck.dmg` from Releases and drag the app to Applications (data lives in
`~/Library/Application Support/Terminal NetDeck/`, passwords only in the Keychain), or build it with macOS 15+ and
Swift 6: `./install.sh`. New versions are checked silently at most once a day; a discreet status-bar notice offers the
download, nothing is installed automatically. Development: `swift run TerminalNetDeck
-idioma en`, tests with `./test.sh`, screenshots with `tools/capturas.sh`.

![Settings](docs/capturas/ajustes-en.png)
