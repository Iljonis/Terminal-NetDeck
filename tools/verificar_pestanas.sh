#!/bin/bash
# Clics, cierre y arrastre por la cola AppKit sobre el ejecutable distribuible, con datos aislados.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=${NETDECK_QA_BIN:?Indica el ejecutable exacto con NETDECK_QA_BIN}
OUT=${1:?Indica la carpeta de informes}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
casa=$(mktemp -d "${TMPDIR:-/tmp}/netdeck-pestanas.XXXX")
pid=""
limpiar() {
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  rm -rf "$casa"
}
trap limpiar EXIT
cp -R tools/demo/. "$casa/"
if [ -n "${NETDECK_QA_APP:-}" ]; then
  mkdir -p "$casa/Applications"
  cp -R "$NETDECK_QA_APP" "$casa/Applications/Terminal NetDeck.app"
  BIN="$casa/Applications/Terminal NetDeck.app/Contents/MacOS/TerminalNetDeck"
fi
informe="$OUT/pestanas-interaccion.txt"
rm -f "$informe" "$OUT/pestanas-interaccion.png"
otool -l "$BIN" | sed -n '/LC_BUILD_VERSION/,+6p' > "$OUT/pestanas-binario.txt"
CFFIXED_USER_HOME="$casa" NETDECK_HOME="$casa" NETDECK_SAMPLES=1 NETDECK_SNAPSHOT="$casa/captura.png" \
NETDECK_SNAPSHOT_DRAGS="$informe" NETDECK_SNAPSHOT_ACTION="pestañas:8" \
  "$BIN" -idioma es -themeID neo-tokyo -themeAuto NO -configured YES -asistenteVisto YES \
  -sshConfigPath "$casa/.ssh/config" -sidebarVisible YES -buttonBar arriba > "$OUT/pestanas-proceso.log" 2>&1 &
pid=$!
# No confundir una captura inicial con la finalización de la batería.
for _ in $(seq 1 1440); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.25
done
if kill -0 "$pid" 2>/dev/null; then echo "✗ pestañas: tiempo agotado"; exit 1; fi
estado=0
wait "$pid" || estado=$?
pid=""
[ "$estado" = 0 ] || { echo "✗ pestañas: proceso terminó con $estado"; exit 1; }
[ -s "$casa/captura.png" ] || { echo "✗ pestañas: sin captura"; exit 1; }
cp "$casa/captura.png" "$OUT/pestanas-interaccion.png"
python3 tools/comprobar_pestanas.py "$informe"
