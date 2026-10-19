<div align="center">

# Terminal NetDeck

**El terminal de macOS pensado para quien vive entre routers, switches y bastiones.**

Sesiones con saltos, contraseñas que nunca acaban en el equipo equivocado, MultiExec, explorador SFTP/FTP
y 51 temas. Nativo, rápido y en tu idioma.

[![Descargar para macOS](https://img.shields.io/badge/Descargar-Terminal--NetDeck.dmg-ff2e88?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Iljonis/Terminal-NetDeck/releases/latest)

Versión actual: **[v0.9.1](https://github.com/Iljonis/Terminal-NetDeck/releases/tag/v0.9.1)** · macOS 15 o posterior ·
código abierto (MIT)

[![Versión](https://img.shields.io/badge/versión-v0.9.1-ff2e88.svg)](https://github.com/Iljonis/Terminal-NetDeck/releases/tag/v0.9.1)
[![Tests](https://github.com/Iljonis/Terminal-NetDeck/actions/workflows/tests.yml/badge.svg)](https://github.com/Iljonis/Terminal-NetDeck/actions/workflows/tests.yml)
[![Licencia: MIT](https://img.shields.io/badge/licencia-MIT-blue.svg)](LICENSE)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138.svg?logo=swift&logoColor=white)](https://www.swift.org)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000.svg?logo=apple&logoColor=white)](https://www.apple.com/macos/)

**Español** · [English](README.en.md)

![Terminal NetDeck](docs/capturas/portada.png)

</div>

## Por qué Terminal NetDeck

Si administras una red, tu día es abrir veinte sesiones detrás de un bastión, escribir la misma contraseña una y
otra vez, pegar configuraciones con miedo a un `reload` y mover archivos entre servidores. Terminal NetDeck junta
todo eso en una sola app de macOS, con una idea fija: **que nunca te juegue una mala pasada.**

- Tus sesiones son las de tu `ssh_config`: `ssh core-01` sigue funcionando desde cualquier otra terminal.
- Las contraseñas viven sólo en el Llavero y sólo se escriben para el usuario y el equipo que de verdad las piden.
- Si algo sale mal (una contraseña que falla, un servidor que no contesta, una copia que se corta), la app se para,
  te avisa y no deja nada a medias.

## Funciones clave

- **Resaltado de la salida** para Cisco, Juniper, Huawei, Nokia SR-OS y Linux: IPs, interfaces, estados, BGP, alarmas.
- **Explorador SFTP/FTP** con copias atómicas, verificación MD5 integrada y envío de servidor a servidor.
- **Multipestaña** con vista dividida, MultiExec y pegado seguro; **51 temas** con contraste WCAG.
- **Sesiones con saltos** sobre tu `ssh_config` y contraseñas sólo en el Llavero de macOS.

## Requisitos y compatibilidad

- macOS Sequoia (15.0) o posterior.
- Para compilar desde el código: Swift 6 (Xcode o Command Line Tools).

## Instalación y primer uso en macOS 15 (Sequoia)

1. **Descarga** `Terminal-NetDeck.dmg` de la [última versión](https://github.com/Iljonis/Terminal-NetDeck/releases/latest).
2. **Ábrelo** y arrastra **Terminal NetDeck** a **Aplicaciones**.
3. **Autoriza la app una vez.** La app se distribuye con firma *ad hoc* y sin notarizar. El método recomendado es
   retirar el atributo de cuarentena desde Terminal:

   ```bash
   sudo xattr -cr "/Applications/Terminal NetDeck.app"
   ```

   > **Alternativa gráfica:** abre la app una vez y, tras el aviso de macOS, ve a **Ajustes del Sistema → Privacidad y
   > seguridad → Abrir igualmente**.

4. **Ábrela.** El asistente configura sesiones, tema, fuente, contraseñas y resaltado.

Las actualizaciones desde la propia app y las instalaciones con `./install.sh` no necesitan este paso.

Tus datos se quedan en tu Mac: la configuración en `~/Library/Application Support/Terminal NetDeck/`, las sesiones en
formato `ssh_config` y las contraseñas, sólo en el Llavero de macOS. Actualizar sólo sustituye la app: antes se copian
tus sesiones, `~/.ssh/config`, botones y listas en `~/Library/Application Support/Terminal NetDeck/copias/`, y si al
arrancar faltara el archivo de sesiones o su `Include`, la app los recupera sola.

![Asistente de bienvenida](docs/capturas/asistente.png)

### Mantenerla al día

- **Desde la propia app.** Una vez al día comprueba en silencio si hay versión nueva. Si la hay, verás un aviso
  discreto en la barra de estado: pulsa **Actualizar ahora** y se descarga, se comprueba (sha256 publicado por GitHub y
  firma) y se vuelve a abrir con tus pestañas. Nunca se instala nada sin ese clic.
- **Desde el código, en un momento:**

  ```bash
  cd Terminal-NetDeck
  git pull
  ./actualizar.sh        # compila, sustituye la app y la reabre con tus pestañas
  ```

<details>
<summary><b>Instalar desde el código</b> (macOS 15+ y Swift 6)</summary>

```bash
xcode-select --install          # si no tienes Xcode ni las Command Line Tools
git clone https://github.com/Iljonis/Terminal-NetDeck.git
cd Terminal-NetDeck
./install.sh                    # compila y la instala en /Applications (o ~/Applications)
```

| Orden | Para qué |
|---|---|
| `./install.sh --usuario` | Instalarla en `~/Applications` |
| `./install.sh --dmg` | Crear `dist/Terminal-NetDeck.dmg` |
| `./install.sh --asistente` | Abrir el asistente sin instalar (para probarlo) |
| `./install.sh --fuente "Kode Mono"` | Instalar una fuente con Homebrew |
| `./desinstalar.sh [--todo]` | Quitar la app (`--todo`: también temas y ajustes; el Llavero no se toca) |

</details>

## Lo que hace por ti

### 🔐 Contraseñas que no se equivocan de sitio

- **Sólo en el Llavero** de macOS: nunca en archivos, argumentos ni registros.
- **Regla de usuario estricta:** una contraseña sólo se escribe sola si es exactamente del usuario que la pide.
- **Y del equipo correcto:** un servidor que escriba en pantalla un `admin@core-01's password:` falso no se lleva la
  contraseña de core-01; sólo cuentan el destino y los saltos de esa pestaña.
- **Si una falla, se bloquea 15 minutos en todas las pestañas**, para no bloquear tu cuenta de Active Directory.
- **El Llavero nunca congela la app:** se consulta en segundo plano y con un tope de 10 segundos.
- Menú 🔑 para escribir cualquiera a mano, también en prompts raros que la app no reconoce.

### 🛡️ Saltos y bastiones, sin sorpresas

- Tus sesiones con `ProxyJump`, encadenadas, y telnet a través del salto.
- **Una sola conexión al bastión:** las pestañas que pasan por el mismo salto la comparten (como SecureCRT; abierta
  2 min tras cerrar la última) y no se vuelven a autenticar en él. Se desactiva en Ajustes → General → Conexiones.
- **Salto a mano blindado:** si un bastión no deja reenviar (`-J`), la app te pregunta antes de entrar en él, y la
  contraseña del destino sólo se sugiere, nunca se escribe sola por la shell del salto.
- **Nada de inyecciones:** un equipo o usuario que empiece por `-` no llega a ssh como opción, todas las órdenes
  llevan `--` antes del destino y al importar sesiones sólo pasan las opciones de ssh seguras (fuera `ProxyCommand`,
  bloques `Host *`, reenvíos de puertos…).

### 📂 Explorador SFTP/FTP que no pierde archivos

- Árbol y lista con tamaños, permisos, dueño y fecha; subir arrastrando desde el Finder, bajar, renombrar, borrar.
- **Copias atómicas:** se escribe primero en un temporal y sólo al acabar se sustituye el archivo. Una copia que falla
  o cancelas no deja nada a medias ni borra el original, y se conservan sus permisos.
- **Integridad MD5:** cada archivo se vuelve a leer del destino y su MD5 tiene que coincidir con el del origen.
- **De servidor a servidor** («Enviar a…»), SFTP ↔ SFTP o SFTP ↔ FTP, en memoria y sin tocar el disco del Mac.
- **Cancelar es inmediato**, y un servidor que no contesta se corta a los 30 segundos en vez de colgar la ventana.

![Explorador SFTP en vista dividida](docs/capturas/explorador.png)

### ⚡ Trabajar en muchos equipos a la vez

- **MultiExec** y **vista dividida:** lo que escribes va a la vez a varios paneles (excluye los que quieras).
- **Pegado seguro:** línea a línea esperando al prompt; se para ante errores de la CLI, paginadores, órdenes
  peligrosas sin confirmar (`reload`, `delete`…) o una petición de contraseña.
- **Listas de equipos:** la misma orden en muchos equipos detrás de un salto, probando la contraseña de uno en uno.
- **Barra de botones** con categorías, teclas F1–F12 y huecos como `{{vlan=100}}`.

### 🗂️ Pestañas que se adaptan

- Se reparten el ancho de la ventana y, si no caben, se desplazan sin perder de vista la activa.
- El título es sólo el **equipo de destino** (`core-02`, no `core-02 ⟵ bastion`); el camino entero sale al pasar el
  ratón. Si desde una sesión saltas a otro equipo, la pestaña lo refleja.
- Los botones de la barra nunca se salen de la ventana, tengas las pestañas que tengas.

![Pestañas adaptativas](docs/capturas/pestanas.png)

### 🧰 Y además

- **Tipos de sesión:** SSH, Telnet, SFTP, FTP, terminal local y consola serie (`screen`).
- **Gestor de sesiones** con carpetas (`Clientes/Madrid/Core`), favoritas, recientes y botón **Conectar** para probar
  sin guardar.
- **Importar** de SecureCRT, MobaXterm, PuTTY, electerm, CSV u otro `ssh_config`; **exportar** a JSON o CSV.
  Nunca contraseñas.
- **Resaltado de la salida** tipo ChromaTerm (IPs, MAC, interfaces, estados, BGP, dBm, errores…) para Cisco, Juniper,
  Huawei, Nokia SR-OS (prompts clásico y MD-CLI, puertos `1/1/c1/1`, alarmas) y Linux, con los colores del tema,
  editable con vista previa. Puedes elegir qué tono es cada color del resaltado, por tema, sin tocar la interfaz; si
  tienes reglas tuyas, las nuevas de cada versión se añaden con un clic.
- **Selección rectangular:** mantén ⌥ y arrastra para copiar sólo unas columnas (las IP de un `show ip interface
  brief`, sin el resto de la línea).
- **Historial configurable:** 2.500 líneas por pestaña de serie; 1.000, 5.000 o 10.000 en Ajustes → Terminal.
- **Registro** de las sesiones en texto limpio y **búsqueda** en todos ellos (IP, MAC en cualquier formato…).
- **Sin avisos de locale** en servidores Linux: ssh no manda el idioma del Mac salvo que lo actives.
- **Español de España e inglés**, se cambia al momento en Ajustes → General → Idioma.

![Resaltado de la salida](docs/capturas/resaltado.png)

## 🎨 51 temas para cada turno

Desde un NOC de guardia a las tres de la mañana hasta una presentación con proyector. Todos tienen su paleta ANSI y su
fuente, pueden **seguir al modo claro u oscuro del Mac**, y **todos pasan una prueba de contraste WCAG** (texto
≥ 4,5:1). ¿Quieres el tuyo? Copia un archivo `.tema` de `Temas/`, cambia los colores e impórtalo. Además está el de
serie, **NetDeck Cyberpunk**.

![Galería de temas](docs/capturas/temas.png)

<details>
<summary><b>Ver el catálogo completo</b></summary>

| Grupo | Tema | Cómo es |
|---|---|---|
| **Cyberpunk** | **Cyber Neón** | Amarillo eléctrico, cian y rojo neón sobre negro. |
|  | **Corpo rojo** | Negro, rojo corporativo y blanco. Sobrio, con rótulos en kanji. |
|  | **Neo-Tokyo** | Cyberpunk japonés: índigo profundo, magenta y cian. |
|  | **Synthwave** | Atardecer retrowave: rosa, violeta y naranja. |
|  | **Grid** | Negro absoluto con cian eléctrico y naranja (estilo Tron). |
|  | **Vaporwave** | Turquesa y rosa pastel sobre violeta, estética noventera. |
| **Sistemas** | **Liquid Glass** | Como macOS 27: cristal transparente y desenfocado, con los colores del sistema. |
|  | **Liquid Glass Claro** | macOS 27 de día: vidrio claro y desenfocado, texto oscuro bien legible. |
|  | **Windows 11** | Fluent y Mica: gris oscuro translúcido, acento azul, Cascadia Mono y la paleta Campbell. |
|  | **Windows 11 Claro** | Fluent de día: Mica clara, acento azul y la paleta «One Half Light». |
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
|  | **Trigo** | Papel crema con tinta tostada (inspirada en Gruvbox claro): pareja diurna de Otoño retro. |
| **Sobrias** | **Ártico** | Sobria con contraste: hielo, aurora y ámbar. |
|  | **Medianoche** | Azules y violetas suaves (estilo Tokyo Night). |
|  | **Vampiro** | Morado, rosa y verde sobre gris (estilo Dracula). |
|  | **Océano profundo** | Azul abisal con brillos aguamarina y coral. |
|  | **Grafito** | Gris carbón en vez de negro: no deslumbra al pasar de una ventana clara a la terminal. |
|  | **Solar oscuro** | La paleta clásica Solarized en oscuro: descansa la vista en turnos largos. |
|  | **Solar claro** | Solarized en claro: pareja de Solar oscuro (ideal en modo Auto). |
|  | **Moca** | Pasteles suaves sobre fondo oscuro, inspirada en Catppuccin Mocha. |
|  | **Fiordo** | Gris pizarra ártico con azules escarcha (inspirada en Nord): calma para turnos largos. |
|  | **Café con leche** | Clara y cremosa (inspirada en Catppuccin Latte): pareja diurna de Moca. |
|  | **Gran ola** | Tinta índigo, papel envejecido y azules de grabado japonés (inspirada en Kanagawa). |
|  | **Taiga** | Verde bosque apagado con salvia, arena y musgo (inspirada en Everforest). |
| **Prácticas** | **Accesible** | Para daltonismo: bien en azul, mal en naranja. |
|  | **Alto contraste** | Blanco puro sobre negro y colores al máximo. |
|  | **Pro** | El perfil «Pro» de Terminal de macOS. |
|  | **Papel** | Clara y muy legible: oficinas con mucha luz, proyector o compartir pantalla. |
|  | **NOC** | Para pantallas de guardia: lo normal apagado y las alarmas saltando a la vista. |
|  | **Guardia ámbar** | Consola de NOC: ámbar sobre negro cálido, letra grande y estados inconfundibles. |
|  | **Guardia verde** | Consola de NOC: verde suave sobre negro, alarmas en rojo y avisos en ámbar. |
| **Corporativas** | **DIGI** | Azul DIGI Mobil (#1275B7) y el punto rojo del logo, sobre azul marino. |
|  | **Oracle** | Rojo Oracle (#C74634) sobre el gris cálido de Redwood (#312D2A). |
|  | **Cisco** | Azul Cisco (#049FD9) sobre azul noche, con los colores de estado de Cisco. |
|  | **Juniper** | Verde Juniper (#84B135) y lima (#CCDB2A) sobre gris pizarra. |
|  | **Huawei** | Rojo Huawei (#CF0A2C) y su negro (#232527). |
|  | **Ubuntu** | Naranja Ubuntu (#E95420) sobre berenjena (#300A24), como su terminal. |

</details>

## Galería

| | |
|---|---|
| ![Inicio](docs/capturas/portada.png) **Inicio:** tus sesiones a un clic y conexión rápida | ![Explorador](docs/capturas/explorador.png) **Explorador SFTP** en vista dividida |
| ![Temas](docs/capturas/temas.png) **Galería de temas** con vista previa | ![Resaltado](docs/capturas/resaltado.png) **Reglas de resaltado** editables |
| ![Ajustes](docs/capturas/ajustes-en.png) **Ajustes → Terminal:** historial y selección rectangular (aquí, en inglés) | ![Asistente](docs/capturas/asistente.png) **Asistente** de la primera vez |

![Barra de pestañas adaptativas](docs/capturas/pestanas.png)

## Atajos

| Atajo | Qué hace |
|---|---|
| ⌘K | Conectar (sesión o `usuario@equipo[:puerto]`, directo o por un salto) |
| ⌘T | Nueva terminal local |
| ⌥⌘K | Abrir la sesión de inicio |
| ⇧⌘E | Gestor de sesiones |
| ⇧⌘L | Listas de equipos |
| ⇧⌘V | Pegado seguro |
| ⇧⌘M | MultiExec |
| ⌘F / ⇧⌘F | Buscar en la salida / en todos los registros |
| Esc o ⌘. | Cortar cualquier secuencia automática |
| ⌥ + arrastrar | Selección rectangular (sólo esas columnas); ⌘C la copia |
| ⌘, | Ajustes |

## Seguridad y privacidad

- Contraseñas sólo en el Llavero, con la regla de usuario y de equipo, y bloqueo de 15 minutos tras un fallo.
- MultiExec y el pegado seguro sólo llegan a pestañas SSH/Telnet: nunca a una terminal local, SFTP o consola serie.
- Tus archivos (`ssh_config`, botones, listas) nunca se sobrescriben si no se pueden leer, con copia `.anterior` en cada
  guardado; carpetas y archivos de la app sólo para ti (0700/0600).
- Antes de cada actualización y de cada guardado de sesiones, copia fuera de `~/.config/netdeck`; un test comprueba en
  cada cambio que actualizar deja tus sesiones idénticas.
- Actualizaciones sólo de github.com, comprobadas con su sha256 y su firma, y nada se instala sin tu clic.
- Firma ad hoc con hardened runtime.
- Cada cambio pasa una comprobación de privacidad (nada personal en el código, la app ni el `.dmg`) y, cada semana,
  una auditoría de dependencias contra la base de vulnerabilidades OSV.dev.
- Los errores van a `~/Library/Application Support/Terminal NetDeck/logs/error.log` (Ayuda → Abrir el registro de
  errores), nunca con contraseñas.

## Para desarrolladores

```bash
swift build
swift run TerminalNetDeck              # -idioma en: en inglés
./test.sh                              # privacidad + actualizar sin tocar tus datos + tests del núcleo
tools/capturas.sh                      # regenera docs/capturas con datos de ejemplo
tools/verificar_demo.sh                # pasada funcional en la demo antes de un commit o tag
```

| Módulo | Contenido |
|---|---|
| `NetDeckCore/Sessions` | `ssh_config`, saltos, `ssh -J`, telnet por el salto, importadores |
| `NetDeckCore/Security` | Llavero, askpass, regla de usuario, bloqueo compartido tras un fallo |
| `NetDeckCore/Remote` | SFTP y FTP, copias atómicas con MD5, servidor a servidor |
| `NetDeckCore/Productivity` | Pegado seguro, MultiExec, listas por salto, barra de botones |
| `NetDeckCore/Highlight` · `Themes` | Resaltado tipo ChromaTerm · formato `.tema` y catálogo |
| `NetDeckCore/Support` | Rutas, registros, actualizaciones, idiomas (`L("…")` + `Ingles.swift`) |
| `TerminalNetDeck` | La app (SwiftUI) |
| `Temas/` · `Resaltado/` | Catálogo de temas y reglas de resaltado |

Las convenciones del proyecto (textos traducibles, datos de ejemplo, contraseñas, seguridad) y cómo se trabaja con
agentes de revisión están en [CLAUDE.md](CLAUDE.md). Los tests se ejecutan en GitHub Actions en cada push. Para
proponer cambios o avisar de un error, mira [CONTRIBUTING.md](CONTRIBUTING.md).

## Soporte y contribución

- **Errores y peticiones:** [GitHub Issues](https://github.com/Iljonis/Terminal-NetDeck/issues).
- **Contribuir:** consulta [CONTRIBUTING.md](CONTRIBUTING.md).

## Licencia

[MIT](LICENSE) © 2026 Jonay / Iljonis. Hecho con Swift 6, SwiftUI y [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
Las licencias de las dependencias y la atribución de las paletas de color están en
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), que también va dentro de la app.

## Marcas

Cisco, Oracle, Juniper, Huawei, DIGI, Ubuntu, Apple, macOS, Liquid Glass, Microsoft, Windows y el resto de nombres de
empresas, productos, obras o paletas que aparecen en este proyecto son marcas de sus respectivos propietarios. Se citan
sólo para describir combinaciones de colores o la compatibilidad (por ejemplo, «inspirada en» o «estilo»). Terminal
NetDeck es un proyecto independiente: no está afiliado, patrocinado ni respaldado por ninguno de ellos, y no incluye
logotipos ni recursos oficiales suyos.
