---
name: netdeck-run
description: "Run, launch or start Terminal NetDeck (also what /run should use here) to see a change working or take a screenshot (settings, a tab, the SFTP explorer, the terminal, menus) — ALWAYS with demo data in a temporary NETDECK_HOME, never the author's real sessions, recents, tabs or Keychain"
---

# Arrancar y ver Terminal NetDeck (sólo con datos de demo)

**Nunca** arranques la app sin `NETDECK_HOME` temporal: así no salen ni se tocan tus sesiones, recientes, pestañas
(`abiertas.json`) ni ajustes. Tampoco `swift run` a secas ni la app instalada. La prueba completa antes de un commit
es otra skill: `netdeck-verificar-demo`.

## Una captura
```bash
swift build --product TerminalNetDeck && BIN="$(swift build --show-bin-path)/TerminalNetDeck"
casa=$(mktemp -d /tmp/netdeck-demo.XXXX); cp -R tools/demo/. "$casa/"; png="$casa/captura.png"
CFFIXED_USER_HOME="$casa" NETDECK_HOME="$casa" NETDECK_SAMPLES=1 \
NETDECK_SNAPSHOT="$png" NETDECK_SNAPSHOT_ACTION=settings:general \
  "$BIN" -idioma es -themeAuto NO -sshConfigPath "$casa/.ssh/config" -configured YES -asistenteVisto YES \
  >"$casa/proceso.log" 2>&1 &
pid=$!; for _ in $(seq 1 60); do [ -s "$png" ] && break; sleep 0.25; done; sleep 0.3
kill $pid; wait $pid 2>/dev/null; ls -la "$png"
```
Después, **mira la imagen con Read** (no basta con que exista). Copia antes la imagen a tu carpeta de trabajo si vas
a borrar `$casa`. `tools/demo` trae un `.ssh/config` con 8 sesiones de ejemplo (IPs RFC 5737) y `salida.txt`.

## Qué capturar (`NETDECK_SNAPSHOT_ACTION`)
| Acción | Qué sale |
|---|---|
| `settings:general`, `settings:botones` | una sección de Ajustes |
| `tab:usuario@equipo` | una pestaña con esa conexión |
| `setup:0` · `sesion-nueva` | el asistente · el editor de sesión |
| `explorador` · `explorador:vista` | el explorador SFTP (más abajo) |
| `pestañas:N` | N pestañas abiertas |
| `terminal` | pestaña local con `salida.txt` resaltada; también deja `$png.txt` y `$png.resaltado.txt` |

Más variables: `NETDECK_SNAPSHOT_CLICK=x,y` (clic derecho sintético; el menú sale en `captura-1.png`),
`NETDECK_SNAPSHOT_WAIT=s`, y con el explorador `NETDECK_SNAPSHOT_MD5=1` o `NETDECK_SNAPSHOT_DOWNLOAD=carpeta`.

## Variantes
- **Inglés:** `-idioma en`. **Tema:** `-themeID neo-tokyo` (con `-themeAuto NO`). Cualquier ajuste se fuerza igual
  (`-clave valor`). Para el resaltado: `-highlightEnabled YES -highlightSource app`.
- **Explorador SFTP sin ssh ni red:** `NETDECK_SFTP_SERVER=/usr/libexec/sftp-server NETDECK_SFTP_DIR="$casa/ficheros"`
  (crea antes unos archivos de ejemplo en esa carpeta).
- **Ventana real con el terminal:** en la captura que hace la app no sale lo que pinta SwiftTerm. Para verlo,
  `tools/verificar_demo.sh` usa `screencapture -l <ventana>` (con `tools/ventana.swift`), que necesita permiso de
  grabación de pantalla para la Terminal; si no hay permiso, mira `$png.txt`.
- **Probar a mano:** el mismo arranque sin `NETDECK_SNAPSHOT*`, y ciérrala con `kill $pid` al terminar.

## Reglas
- Con `NETDECK_SNAPSHOT`, la terminal local arranca `/bin/sh` sin login y con un prompt de ejemplo, así no salen tu
  usuario ni el nombre del Mac. Si aparecen en una captura, algo va mal: no la enseñes ni la guardes.
- Las pestañas de las capturas no se guardan ni se reabren.
- Capturas para el README: `tools/capturas.sh`, no a mano.
- Borra la carpeta temporal (`rm -rf "$casa"`) cuando ya no la necesites.
