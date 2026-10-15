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
  casa=$(mktemp -d /tmp/netdeck-demo.XXXX)                      # (ruta corta: se ve en el explorador)
  cp -R tools/demo/. "$casa/"
  png="$casa/captura.png"
  # (el explorador: SFTP sin ssh ni red, con el sftp-server del Mac sobre una carpeta de ejemplo)
  mkdir -p "$casa/ficheros/backups" "$casa/ficheros/firmware"
  for e in core-01 core-02 pe-mad-01 sw-acceso-01; do printf 'hostname %s\n!\n' "$e" > "$casa/ficheros/$e.cfg"; done
  for d in 2026-10-13 2026-10-14; do printf 'backup %s\n' "$d" > "$casa/ficheros/backups/core-01-$d.cfg"; done
  dd if=/dev/zero of="$casa/ficheros/firmware/ios-xe-17.12.bin" bs=1024 count=2048 2>/dev/null
  NETDECK_SFTP_SERVER=/usr/libexec/sftp-server NETDECK_SFTP_DIR="$casa/ficheros" \
  NETDECK_HOME="$casa" NETDECK_SAMPLES=1 NETDECK_SNAPSHOT="$png" NETDECK_SNAPSHOT_ACTION="$accion" \
    "$BIN" -idioma "$idioma" -themeID "$TEMA" -themeAuto NO -sshConfigPath "$casa/.ssh/config" -configured YES -asistenteVisto YES \
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
captura pestanas       es "pestañas:9"
captura explorador     es explorador:vista

# (la barra de pestañas, sola: la terminal no sale en estas capturas)
swift tools/recortar.swift "$OUT/pestanas.png" "$OUT/pestanas.png" 72 && echo "✓ $OUT/pestanas.png (barra)"
