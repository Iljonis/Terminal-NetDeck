#!/bin/bash
# Verifica el contenido del DMG que se publicará, sin instalarlo y sin datos personales.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-build/qa}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
raiz=$(mktemp -d "${TMPDIR:-/tmp}/netdeck-dmg-qa.XXXX")
montado=0
limpiar() {
  if [ "$montado" = 1 ]; then hdiutil detach "$raiz/imagen" -quiet || true; fi
  rmdir "$raiz" 2>/dev/null || true
}
trap limpiar EXIT
hdiutil attach dist/Terminal-NetDeck.dmg -readonly -nobrowse -mountpoint "$raiz/imagen" -quiet
montado=1
APP="$raiz/imagen/Terminal NetDeck.app"
codesign --verify --strict "$APP"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
esperada=$(sed -n 's/^VERSION=//p' install.sh)
[ "$version" = "$esperada" ] || { echo "✗ versión del DMG distinta de install.sh"; exit 1; }
BIN="$APP/Contents/MacOS/TerminalNetDeck"
otool -l "$BIN" > "$OUT/paquete-mach-o.txt"
# Un SDK antiguo activaba otro recorrido de eventos: no sirve como sustituto del paquete moderno.
python3 - "$OUT/paquete-mach-o.txt" <<'PY'
import pathlib, re, sys
texto=pathlib.Path(sys.argv[1]).read_text()
sdks=re.findall(r'\bsdk\s+(\d+(?:\.\d+)*)',texto)
if not sdks or any(int(s.split('.')[0]) < 26 for s in sdks):
    sys.exit('✗ el paquete no declara SDK 26 o posterior: no reproduce el entorno distribuido')
print('✓ SDK del paquete: '+', '.join(sdks))
PY
shasum -a 256 dist/Terminal-NetDeck.dmg > "$OUT/paquete-sha256.txt"
NETDECK_QA_APP="$APP" tools/verificar_demo.sh "$OUT"
