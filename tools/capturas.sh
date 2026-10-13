#!/bin/bash
# tools/capturas.sh — regenera las capturas del README (docs/capturas) con datos de ejemplo (tools/demo), sin tocar
# tus sesiones, ajustes ni el Llavero: la app arranca con NETDECK_HOME en una carpeta temporal.
#   tools/capturas.sh            → todas
#   TEMA=neo-tokyo tools/capturas.sh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product TerminalNetDeck 2>&1 | grep -E "error" && exit 1
BIN="$(swift build --show-bin-path)/TerminalNetDeck"
OUT=docs/capturas
TEMA="${TEMA:-neo-tokyo}"
mkdir -p "$OUT"

captura() {   # nombre idioma acción
  local nombre=$1 idioma=$2 accion=$3 casa png
  casa=$(mktemp -d)
  cp -R tools/demo/. "$casa/"
  png="$casa/captura.png"
  NETDECK_HOME="$casa" NETDECK_SAMPLES=1 NETDECK_SNAPSHOT="$png" NETDECK_SNAPSHOT_ACTION="$accion" \
    "$BIN" -idioma "$idioma" -themeID "$TEMA" -themeAuto NO -sshConfigPath "$casa/.ssh/config" -configured YES \
           -sidebarVisible YES -buttonBar arriba >/dev/null 2>&1 &
  local pid=$!
  for _ in $(seq 1 60); do [ -s "$png" ] && break; sleep 0.25; done
  sleep 0.5
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  if [ -s "$png" ]; then
    sips --resampleWidth 1600 "$png" --out "$OUT/$nombre.png" >/dev/null
    echo "✓ $OUT/$nombre.png"
  else
    echo "✗ $nombre (sin captura)"
  fi
  rm -rf "$casa"
}

captura portada        es ""
captura portada-en     en ""
captura temas          es settings:temas
captura resaltado      es settings:resaltado
captura ajustes-en     en settings:general
captura asistente      es setup:0
