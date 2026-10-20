#!/bin/bash
# tools/seguridad_cron.sh — auditoría periódica de seguridad (para cron, launchd o GitHub Actions):
#   1. Dependencias de SwiftPM (Package.resolved) contra la base de vulnerabilidades OSV.dev (CVE/GHSA).
#   2. Privacidad: nada personal en el código ni en lo que se distribuye (tools/privacidad.sh).
#   3. Tests del núcleo (./test.sh).
#   4. Endurecimiento de la app compilada (build/Terminal NetDeck.app, si existe): firma con hardened runtime, sin
#      excepciones de red en el Info.plist, y carpetas de la app sólo para ti.
# Sale con 0 si todo está bien y con 1 si hay algo que mirar; el informe va a la salida y a
# ~/Library/Logs/Terminal NetDeck/seguridad.log.
#
#   tools/seguridad_cron.sh                 → todo
#   tools/seguridad_cron.sh --sin-tests     → sin compilar ni pasar tests (más rápido)
#
# Cada lunes a las 9:00 con cron (crontab -e):
#   0 9 * * 1  cd "$HOME/Documents/Terminal-NetDeck" && tools/seguridad_cron.sh >/dev/null 2>&1
# En GitHub, .github/workflows/seguridad.yml lo lanza cada semana.
set -uo pipefail
cd "$(dirname "$0")/.."

tests=1; [ "${1:-}" = --sin-tests ] && tests=0
LOG="${NETDECK_HOME:-$HOME}/Library/Logs/Terminal NetDeck/seguridad.log"
mkdir -p "$(dirname "$LOG")" && chmod 700 "$(dirname "$LOG")" 2>/dev/null
problemas=0
salida() { echo "$*"; echo "$*" >>"$LOG"; }
mal() { salida "✗ $*"; problemas=$((problemas + 1)); }
bien() { salida "✓ $*"; }

salida "=== $(date '+%F %T') · auditoría de seguridad ($(git rev-parse --short HEAD 2>/dev/null))"

# ── 1. Dependencias contra OSV.dev ─────────────────────────────────────
# (tools/osv.py comprueba la consulta y la respuesta entera: una comprobación incompleta nunca sale como correcta)
osvdir=$(mktemp -d)
if ! python3 tools/osv.py consulta Package.resolved >"$osvdir/consulta.json" 2>"$osvdir/error"; then
  mal "dependencias no comprobadas: $(cat "$osvdir/error")"
elif ! curl -sf --max-time 30 -H 'Content-Type: application/json' -d @"$osvdir/consulta.json" \
       https://api.osv.dev/v1/querybatch >"$osvdir/respuesta.json"; then
  mal "dependencias no comprobadas: no se ha podido consultar OSV.dev (¿sin red?)"
elif ! vulnerables=$(python3 tools/osv.py informe "$osvdir/consulta.json" "$osvdir/respuesta.json" 2>"$osvdir/error"); then
  mal "dependencias no comprobadas: $(cat "$osvdir/error")"
else
  total=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["queries"]))' "$osvdir/consulta.json")
  if [ -z "$vulnerables" ]; then
    bien "dependencias: $total sin vulnerabilidades conocidas (OSV.dev)"
  else
    while IFS= read -r l; do mal "dependencia con vulnerabilidades: $l (https://osv.dev)"; done <<<"$vulnerables"
  fi
fi
rm -rf "$osvdir"

# ── 2. Privacidad ──────────────────────────────────────────────────────
if out=$(tools/privacidad.sh --binario 2>&1); then bien "privacidad: ${out#*✓ }"; else mal "privacidad:"; salida "$out"; fi

# ── 3. Tests ───────────────────────────────────────────────────────────
if [ $tests = 1 ]; then
  if out=$(./test.sh 2>&1); then
    bien "tests: $(echo "$out" | grep -oE 'Test run with [0-9]+ tests' | tail -1 | grep -oE '[0-9]+') en verde"
  else
    mal "tests en rojo:"; salida "$(echo "$out" | grep -E '✘|error:' | head -15)"
  fi
fi

# ── 4. Endurecimiento de la app compilada ─────────────────────────────
APP="build/Terminal NetDeck.app"
if [ -d "$APP" ]; then
  flags=$(codesign -dv "$APP" 2>&1 | grep -o 'flags=[^ ]*' || true)
  if [[ $flags == *runtime* ]]; then bien "firma con hardened runtime ($flags)"; else mal "la app no tiene hardened runtime ($flags)"; fi
  if codesign -d --entitlements - "$APP" 2>/dev/null | grep -qE 'allow-dyld-environment|disable-library-validation|allow-unsigned-executable-memory|get-task-allow'; then
    mal "la app tiene derechos que debilitan el hardened runtime"
  else
    bien "sin derechos que debiliten el hardened runtime"
  fi
  if /usr/libexec/PlistBuddy -c 'Print NSAppTransportSecurity' "$APP/Contents/Info.plist" >/dev/null 2>&1; then
    mal "el Info.plist tiene excepciones de red (NSAppTransportSecurity)"
  else
    bien "sin excepciones de red en el Info.plist"
  fi
else
  salida "· sin build/Terminal NetDeck.app: endurecimiento no comprobado (./install.sh --dmg para crearla)"
fi
SOPORTE="${NETDECK_HOME:-$HOME}/Library/Application Support/Terminal NetDeck"
if [ -d "$SOPORTE" ]; then
  abiertas=$(find "$SOPORTE" \( -type d -perm -o=r -o -type f -perm -o=r \) 2>/dev/null | head -5)
  if [ -z "$abiertas" ]; then bien "datos de la app sólo para ti"; else mal "archivos de la app legibles por otros:"; salida "$abiertas"; fi
fi

if [ $problemas = 0 ]; then salida "=== todo en orden"; else salida "=== $problemas cosas que mirar"; fi
exit $((problemas > 0))
