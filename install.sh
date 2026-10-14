#!/bin/bash
# install.sh — monta «Terminal NetDeck.app» (compila en release, la firma ad hoc) y la instala o la empaqueta.
#
#   ./install.sh                 → la instala en /Applications (o ~/Applications) sin preguntar nada
#   ./install.sh --usuario       → en ~/Applications
#   ./install.sh --dmg           → sólo dist/Terminal-NetDeck.dmg: doble clic en la app → asistente de instalación
#                                  (copiarla a Aplicaciones, elegir temas, fuentes, contraseñas y resaltado)
#   ./install.sh --actualizar    → compila, sustituye la instalada, la cierra y la vuelve a abrir con sus pestañas
#                                  (lo mismo que ./actualizar.sh o el menú «Actualizar desde el código…»)
#   ./install.sh --asistente     → abre el asistente sin instalar (para probarlo)
#   ./install.sh --abrir         → y la abre al terminar
#   ./install.sh --fuente "X"…   → instala esas fuentes con Homebrew (los temas ya vienen todos en la app)
#
# Nada de contraseñas en archivos: la app usa el Llavero (las mismas que NetDeck).
set -euo pipefail
cd "$(dirname "$0")"

NOMBRE="Terminal NetDeck"
PRODUCTO=TerminalNetDeck
ANTIGUO=NetDeckProvisional          # (nombre del ejecutable hasta la v0.4)
ID=io.netdeck.terminal
VERSION=0.7.2
# Repositorio de GitHub («usuario/repo») para las actualizaciones; NETDECK_REPO= (vacío) para no buscarlas.
REPO="${NETDECK_REPO-Iljonis/Terminal-NetDeck}"
[[ -z $REPO || $REPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "NETDECK_REPO no válido: «$REPO» (usuario/repo)"; exit 1; }
SOPORTE="$HOME/Library/Application Support/$NOMBRE"
TEMAS_USUARIO="$SOPORTE/Temas"
C=$'\e[38;5;51m'; M=$'\e[38;5;204m'; V=$'\e[38;5;48m'; A=$'\e[38;5;221m'; N=$'\e[0m'

dmg=0; abrir=0; asistente=0; actualizar=0; destino=""
fuentes=()
while [ $# -gt 0 ]; do
  case $1 in
    --usuario) destino="$HOME/Applications" ;;
    --dmg) dmg=1 ;;
    --abrir) abrir=1 ;;
    --asistente) asistente=1 ;;
    --actualizar) actualizar=1 ;;
    --fuente) shift; while [ $# -gt 0 ] && [[ $1 != --* ]]; do fuentes+=("$1"); shift; done; continue ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "No conozco «$1» (./install.sh --help)"; exit 1 ;;
  esac
  shift
done

# ── fuentes (aparte de los temas) ─────────────────────────────────────
instalar_fuente() {                 # como NetDeck: «M PLUS 1 Code» → brew install --cask font-m-plus-1-code
  local familia=$1 cask brew
  if system_profiler SPFontsDataType 2>/dev/null | grep -qi "Family: $familia$"; then return 0; fi
  cask="font-$(echo "$familia" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
  brew=$(command -v brew || ls /opt/homebrew/bin/brew /usr/local/bin/brew 2>/dev/null | head -1 || true)
  [ -n "$brew" ] || { echo "   ${A}(sin Homebrew: la fuente «${familia}», a mano)${N}"; return 0; }
  echo "   fuente «${familia}» ($cask)…"
  "$brew" install --cask "$cask" >/dev/null 2>&1 || echo "   ${A}(no se ha podido instalar «${familia}»)${N}"
}

if [ ${#fuentes[@]} -gt 0 ]; then
  for f in "${fuentes[@]}"; do instalar_fuente "$f"; done
  exit 0
fi

# ── la app ─────────────────────────────────────────────────────────────
if [ $actualizar = 1 ] && [ -z "$destino" ]; then      # donde ya esté instalada
  for d in /Applications "$HOME/Applications"; do [ -d "$d/$NOMBRE.app" ] && destino=$d && break; done
fi
if [ -z "$destino" ]; then
  if [ -w /Applications ]; then destino=/Applications; else destino="$HOME/Applications"; fi
fi
mkdir -p "$destino" build

echo "${C}▚ NETDECK${N} // $NOMBRE $VERSION"
echo "   compilando (release)…"
swift build -c release --product "$PRODUCTO" 2>&1 | grep -E "error|warning: .*Sources" || true
BIN_DIR=$(swift build -c release --show-bin-path)
[ -x "$BIN_DIR/$PRODUCTO" ] || { echo "${M}✗ No se ha compilado${N}"; exit 1; }

echo "   icono…"
if [ ! -f build/AppIcon.icns ] || [ tools/icono.swift -nt build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swiftc -O -o build/icono tools/icono.swift 2>/dev/null && build/icono build/AppIcon.iconset \
    && iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns || echo "   ${A}(sin icono)${N}"
fi

# «Actualizar desde el código…»: la carpeta del código, sólo si se instala desde aquí (nunca en el .dmg)
FUENTE=""; [ $dmg = 1 ] || FUENTE=$(pwd | sed 's/&/\&amp;/g; s/</\&lt;/g')
APP="build/$NOMBRE.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$PRODUCTO" "$APP/Contents/MacOS/$PRODUCTO"
for b in "$BIN_DIR"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
cp -R Temas "$APP/Contents/Resources/Temas"
cp -R Resaltado "$APP/Contents/Resources/Resaltado"
[ -f build/AppIcon.icns ] && cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NOMBRE</string>
  <key>CFBundleDisplayName</key><string>$NOMBRE</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>$PRODUCTO</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>NetDeckRepo</key><string>$REPO</string>
  <key>NetDeckSource</key><string>$FUENTE</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSHumanReadableCopyright</key><string>NetDeck</string>
</dict>
</plist>
PLIST
# Firma ad hoc con «hardened runtime» (sin derechos extra: la app no carga código de fuera, y el askpass, que es el
# mismo ejecutable, no hereda variables DYLD_*)
codesign --force --options runtime --sign - "$APP" >/dev/null 2>&1 || echo "   ${A}(sin firmar)${N}"

if [ $asistente = 1 ]; then
  echo "${V}✓${N} Abriendo el asistente desde build/ (no se instala nada hasta que pulses «Instalar»)"
  open "$APP"
  exit 0
fi

if [ $dmg = 1 ]; then
  echo "   imagen de disco…"
  mkdir -p dist build/dmg
  rm -rf build/dmg/* dist/Terminal-NetDeck.dmg
  cp -R "$APP" build/dmg/
  ln -s /Applications build/dmg/Applications       # arrastrar la app aquí, como cualquier app de macOS
  for _ in 1 2 3; do       # (hdiutil falla a veces con «Resource busy»)
    hdiutil create -volname "Instalar Terminal NetDeck" -srcfolder build/dmg -ov -format UDZO dist/Terminal-NetDeck.dmg >/dev/null 2>&1 && break
    sleep 3
  done
  [ -s dist/Terminal-NetDeck.dmg ] || { echo "${M}✗ No se ha podido crear el .dmg${N}"; exit 1; }
  echo "${V}✓${N} dist/Terminal-NetDeck.dmg — ábrelo y arrastra la app a Aplicaciones (o doble clic en ella → asistente)"
  echo "   (en otro Mac, la primera vez: clic derecho en la app → Abrir, porque no está firmada por Apple)"
  exit 0
fi

abierta=0
for p in "$ANTIGUO" "$PRODUCTO"; do if pgrep -xq "$p"; then PRODUCTO_ABIERTO=$p; fi; done
if [ -n "${PRODUCTO_ABIERTO:-}" ]; then
  abierta=1
  if [ $actualizar = 1 ]; then          # se cierra y se reabre con sus pestañas (la app las guarda al abrir/cerrar)
    echo "   cerrando la app (sus pestañas ya están guardadas)…"
    pkill -TERM -x "$PRODUCTO_ABIERTO" 2>/dev/null || true
    for _ in $(seq 1 40); do pgrep -xq "$PRODUCTO_ABIERTO" || break; sleep 0.25; done
    pkill -KILL -x "$PRODUCTO_ABIERTO" 2>/dev/null || true
  fi
fi
echo "   copiando a ${destino}…"
rm -rf "$destino/$NOMBRE.app"
cp -R "$APP" "$destino/"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$destino/$NOMBRE.app" >/dev/null 2>&1 || true
mkdir -p "$TEMAS_USUARIO" && chmod 700 "$SOPORTE" "$TEMAS_USUARIO"

echo "${V}✓ Instalada:${N} $destino/$NOMBRE.app"
if [ $actualizar = 1 ]; then
  open "$destino/$NOMBRE.app" --args --reabrir
  echo "${V}✓ Actualizada y abierta${N} (con las pestañas que tenías)"
  exit 0
fi
echo "   Temas (vienen todos), fuentes y botones: Ajustes (⌘,) o el asistente (menú Terminal NetDeck)"
[ $abierta = 1 ] && echo "   ${A}Está abierta: ciérrala y vuelve a abrirla (o usa ./actualizar.sh).${N}"
[ $abrir = 1 ] && open "$destino/$NOMBRE.app"
exit 0
