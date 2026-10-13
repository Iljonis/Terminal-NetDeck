# Terminal NetDeck

App nativa de macOS (Swift 6 / SwiftUI + SwiftTerm) que sustituirá a NetDeck (bash + tmux). Respeta lo de NetDeck:
mismo Llavero, mismo `ssh_config` con sus anotaciones, mismas temáticas `.tema`, y la primera vez importa
`clave.conf` y `tema.conf`.

```
./install.sh --dmg              # dist/Terminal-NetDeck.dmg: doble clic en la app → asistente (instalar, temas, fuentes…)
./install.sh                    # instalarla sin preguntas (--usuario: en ~/Applications · --asistente: probar el asistente)
./install.sh --temas            # catálogo de temas (● = instalado)
./install.sh --tema neo-tokyo   # un tema, por su cuenta
./install.sh --fuente "Kode Mono"  # una fuente, con Homebrew (aparte de los temas)
./desinstalar.sh [--todo]       # quita la app (--todo: también temas, marcas y ajustes; el Llavero no se toca)
swift run TerminalNetDeck    # desarrollo
./test.sh                       # tests del núcleo
```

| Módulo | Contenido |
|---|---|
| `NetDeckCore/Sessions` | `ssh_config` (comodines, Include, `# @grupo/@clave/@clave-grupo/@desc/@telnet`), saltos, `ssh -J`, telnet por el salto |
| `NetDeckCore/Security` | Llavero vía `/usr/bin/security` (sin avisos de permisos), **askpass** (contraseña de sesión automática), regla de usuario, marcas «probando/fallo» compartidas, autocompletado de equipos |
| `NetDeckCore/Themes` | Formato `.tema` de NetDeck, paleta ANSI, catálogo e instalación tema a tema, rótulo 5×5 |
| `NetDeckCore/Highlight` | Resaltado tipo ChromaTerm: lee el `chromaterm.yml` de NetDeck (o el de la app, o uno propio) con los colores del tema |
| `NetDeckCore/Input` · `Productivity` | Esc / Ctrl+C, pegado seguro, MultiExec, listas por salto |
| `NetDeckSSH` | SSH nativo con SwiftNIO SSH (fase 2) |
| `TerminalNetDeck` | La app: barra superior, sesiones, pestañas, portada, Ajustes (⌘,) |
| `Temas/` | Catálogo (no se instala nada hasta que lo pides) |
| `Resaltado/` | Reglas de la app (las de NetDeck) |

Contraseñas, por separado:
- **Sesión** (su login y sus saltos): el propio ejecutable hace de `SSH_ASKPASS`. Un intento por contraseña; si falla,
  bloqueada 15 min en todas partes y te la pide en la pestaña (`[NetDeck] …`, Esc cancela) ofreciendo guardarla.
- **Equipos** (`ssh`/`telnet` desde una sesión): escribir sola, sugerir o nada (Ajustes → Contraseñas).
- Siempre la regla de usuario: sólo una contraseña de ese mismo usuario (`ssh root@…`, `Username: pepe`, `(admin@equipo) Password:`).
  Estricta: con un `Password:` a secas sin usuario conocido no se escribe nada, y si la orden dice `ssh root@…` el
  prompt no puede pedir la de otro usuario (salvo los saltos explícitos de la orden: `ssh -J tu.usuario@bastion …`).

Ajustes (⌘,): Contraseñas · Temas · Fuentes (terminal e interfaz, aparte de los temas) · Resaltado · General.

Desarrollo: `NETDECK_SNAPSHOT=/ruta.png` guarda una imagen de las ventanas (con `NETDECK_SNAPSHOT_ACTION=settings`,
`setup:N` o `tab:usuario@equipo`).
