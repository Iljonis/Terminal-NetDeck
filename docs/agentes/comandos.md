# Comandos y capturas (detalle)

Léelo cuando vayas a ejecutar algo más que `swift build` / `./test.sh`, o a hacer capturas.

## Qué hace cada orden
- `./test.sh`: primero `tools/privacidad.sh` (nada personal en lo que se publica), luego `tools/test_actualizacion.sh`
  y por último los tests del núcleo (Swift Testing, con `NETDECK_HOME` temporal). `tools/test_actualizacion.sh` prueba
  el paso de install.sh que cambia la app (`tools/sustituir_app.sh`) y comprueba que deja idénticos las sesiones,
  `~/.ssh/config`, los botones y las listas. También se ejecuta en GitHub Actions.
- `tools/privacidad.sh [--binario]`: busca IPs privadas, rutas `/Users/…`, correos, claves, tokens y contraseñas en el
  código, los temas, las reglas y las plantillas (en todo lo que git sube o podría subir). Con `--binario` revisa
  también la app de `build/` y el `.dmg`. Tus direcciones (las de tu ssh_config y las de `tools/privacidad.local`, que
  no se sube) se comprueban sin publicarlas.
- `tools/seguridad_cron.sh`: auditoría periódica que revisa las dependencias contra OSV.dev (CVE/GHSA), la privacidad,
  los tests y el endurecimiento. En GitHub la lanza `.github/workflows/seguridad.yml` cada lunes. El informe queda en
  `~/Library/Logs/Terminal NetDeck/seguridad.log`.
- `./install.sh` instala, `./install.sh --dmg` empaqueta y `./actualizar.sh` reinstala y reabre la app con sus
  pestañas. Las actualizaciones se buscan en `Iljonis/Terminal-NetDeck`; con `NETDECK_REPO=usuario/repo` se buscan en
  otro repositorio, y con `NETDECK_REPO=` no se buscan.
- `swift run TerminalNetDeck` (sólo el autor, con sus datos): `-idioma en` la arranca en inglés, y cualquier ajuste se
  fuerza igual (`-sshConfigPath /ruta`, `-themeID neo-tokyo`…). Un agente nunca la arranca así: usa la skill
  `netdeck-run` o lo de abajo.

## Capturas (siempre con datos de demo)
- Las del README se hacen con `tools/capturas.sh`. A mano: `NETDECK_HOME=<carpeta temporal con tools/demo>`
  `NETDECK_SNAPSHOT=/ruta.png` y, si hace falta, `NETDECK_SNAPSHOT_ACTION=` con uno de estos valores:
  `settings:general`, `settings:botones`, `tab:usuario@equipo`, `setup:0`, `sesion-nueva`, `explorador`,
  `explorador:vista`, `pestañas:N`, `terminal`, `pegar` (la revisión antes de pegar) o `settings:terminal:pegar`
  (Ajustes → Terminal, abajo). `NETDECK_HOME` cambia la carpeta personal: nunca captures con tus
  datos reales (sesiones, recientes, pestañas).
- La imagen social de GitHub (1280 × 640, Settings → Social preview) sale de la portada en inglés:
  `swift tools/imagen_social.swift` → `docs/capturas/social-preview.png`. `tools/capturas.sh` la rehace con la
  portada; si cambia, el autor la vuelve a subir.
- Explorador sin ssh ni red: `NETDECK_SFTP_SERVER=/usr/libexec/sftp-server NETDECK_SFTP_DIR=<carpeta>`.
- Con `NETDECK_SNAPSHOT`, la terminal local arranca `/bin/sh` sin login y con un prompt de ejemplo
  (`TerminalSession.launch`): una de login enseñaría tu usuario y el nombre del Mac. La demo de espacios falla si
  aparecen.
- `terminal`: abre una pestaña local con `tools/demo/salida.txt` resaltada y deja `.txt` y `.resaltado.txt`.
  `NETDECK_SNAPSHOT_CLICK=x,y` hace un clic derecho sintético (el menú sale en `-1.png`). `NETDECK_SNAPSHOT_WAIT=s`
  espera antes de capturar. En el explorador, `NETDECK_SNAPSHOT_MD5=1` o `NETDECK_SNAPSHOT_DOWNLOAD=carpeta`.
- Filtro de pantalla: `-screenFilter crt|lcd|fosforo|holograma|ninguno|auto` (y `-screenFilterIntensity 0.1…1`).
  `FILTRO=lcd` lo pasa en `tools/capturas.sh` y `tools/verificar_demo.sh` (casos `filtro-lcd` y `filtro-crt`).
- La imagen que hace la app no incluye lo que pinta SwiftTerm. `tools/verificar_demo.sh` usa `screencapture` si la
  Terminal tiene permiso de grabación de pantalla.
