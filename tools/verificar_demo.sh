#!/bin/bash
# tools/verificar_demo.sh — pasada funcional en la DEMO antes de un commit o tag (ver CLAUDE.md): abre la app con datos
# de ejemplo (NETDECK_HOME temporal con tools/demo, nunca tus sesiones ni el Llavero) en cada pantalla principal
# (terminal, selección rectangular, explorador SFTP, pestañas, temas, resaltado, menús de clic derecho, ajustes) y guarda una captura de cada
# una. Falla si alguna no sale, si un clic derecho no abre menú o si el terminal no muestra la salida de ejemplo.
# Con permiso de grabación de pantalla para la Terminal, la captura es la de la pantalla (con el terminal tal cual se
# ve); sin él, la que hace la app de su ventana, donde SwiftTerm no sale. El menú de un clic derecho, la que hace la
# app de él («-menu.png»: el de la pantalla se cierra si la app deja de estar delante). Hay que mirarlas.
#   tools/verificar_demo.sh [carpeta]        → capturas en esa carpeta (si no, una temporal)
#   SOLO=explorador tools/verificar_demo.sh  → sólo los casos cuyo nombre contenga eso
set -uo pipefail
cd "$(dirname "$0")/.."
# (con pipefail, «swift build | grep error && exit 1» no salía nunca: el estado era el de swift build y se seguía con
# el binario anterior)
if [ -n "${NETDECK_QA_APP:-}" ]; then
  NETDECK_QA_BIN="$NETDECK_QA_APP/Contents/MacOS/TerminalNetDeck"
fi
if [ -z "${NETDECK_QA_BIN:-}" ]; then
if ! log=$(swift build --product TerminalNetDeck 2>&1); then echo "$log" | grep -E "error:" | head -20; echo "✗ no compila"; exit 1; fi
BIN="$(swift build --show-bin-path)/TerminalNetDeck"
else
  BIN="$NETDECK_QA_BIN"
fi
[ -x "$BIN" ] || { echo "✗ binario de QA inexistente: $BIN"; exit 1; }
VENTANA="$(mktemp -d "${TMPDIR:-/tmp}/netdeck-ventana.XXXX")/ventana"
swiftc -O tools/ventana.swift -o "$VENTANA" 2>/dev/null || VENTANA=""
OUT="${1:-$(mktemp -d "${TMPDIR:-/tmp}/netdeck-verificacion.XXXX")}"
mkdir -p "$OUT"
fallos=0

caso() {   # nombre idioma tema acción [clic x,y] [subcarpeta del explorador] [menú esperado: archivo|fondo]
  local nombre=$1 idioma=$2 tema=$3 accion=$4 clic=${5:-} sub=${6:-} menu=${7:-} casa png
  [ -n "${SOLO:-}" ] && [[ "$nombre" != *"$SOLO"* ]] && return
  casa=$(mktemp -d /tmp/netdeck-demo.XXXX)                      # (ruta corta: se ve en el explorador)
  cp -R tools/demo/. "$casa/"
  local bin="$BIN"
  if [ -n "${NETDECK_QA_APP:-}" ]; then
    mkdir -p "$casa/Applications"
    cp -R "$NETDECK_QA_APP" "$casa/Applications/Terminal NetDeck.app"
    bin="$casa/Applications/Terminal NetDeck.app/Contents/MacOS/TerminalNetDeck"
  fi
  png="$casa/captura.png"
  rm -f "$OUT/$nombre.png" "$OUT/$nombre-menu.png" "$OUT/$nombre-ventana.png"
  # (explorador: SFTP sin ssh ni red sobre una carpeta de ejemplo; con más archivos de los que caben, para el scroll)
  mkdir -p "$casa/ficheros/backups" "$casa/ficheros/firmware"
  for i in $(seq -w 1 30); do printf 'hostname sw-%s\n!\n' "$i" > "$casa/ficheros/sw-acceso-$i.cfg"; done
  printf 'backup\n' > "$casa/ficheros/backups/core-01-2026-10-14.cfg"
  dd if=/dev/zero of="$casa/ficheros/firmware/ios-xe-17.12.bin" bs=1024 count=512 2>/dev/null
  NETDECK_SFTP_SERVER=/usr/libexec/sftp-server NETDECK_SFTP_DIR="$casa/ficheros${sub:+/$sub}" \
  CFFIXED_USER_HOME="$casa" NETDECK_HOME="$casa" NETDECK_SAMPLES=1 NETDECK_SNAPSHOT="$png" NETDECK_SNAPSHOT_ACTION="$accion" \
  NETDECK_SNAPSHOT_CLICK="$clic" NETDECK_SNAPSHOT_BLOCK="${BLOQUE:-}" \
    "$bin" -idioma "$idioma" -themeID "$tema" -themeAuto NO -sshConfigPath "$casa/.ssh/config" -configured YES \
           -asistenteVisto YES -sidebarVisible YES -buttonBar arriba -highlightEnabled YES -highlightSource app \
           -highlightDisabled '()' -highlightThemeColors YES >"$OUT/$nombre-proceso.log" 2>&1 &
  local pid=$!
  for _ in $(seq 1 60); do [ -s "$png" ] && break; sleep 0.25; done
  sleep 0.3
  local win real=0
  # (sólo la ventana de la app, por su número: nunca un rectángulo de la pantalla, que podría llevar otras apps)
  win=$([ -n "$VENTANA" ] && "$VENTANA" "$pid")
  [[ $win =~ ^[0-9]+$ ]] && screencapture -x -o -l "$win" "$OUT/$nombre.png" 2>/dev/null && [ -s "$OUT/$nombre.png" ] && real=1
  [ $real = 0 ] && echo "  · $nombre: sin captura de pantalla (¿permiso de grabación para la Terminal?); va la de la app"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  local ok=1
  if [ -s "$png" ]; then
    [ $real = 1 ] || cp "$png" "$OUT/$nombre.png"
    # (la 2.ª ventana: con clic, el menú que abre; sin clic, una hoja o un tooltip que esté a la vista, no un menú)
    local otra=ventana; [ -n "$clic" ] && otra=menu
    [ -s "$casa/captura-1.png" ] && cp "$casa/captura-1.png" "$OUT/$nombre-$otra.png"
    [ -n "$clic" ] && [ ! -s "$casa/captura-1.png" ] && { echo "✗ $nombre: el clic derecho no abre ningún menú"; ok=0; }
    # (el del archivo, con sus 8 filas, es mucho más alto que el del fondo de la lista, con 3: así se sabe cuál ha salido.
    # En proporción a la ventana: en una pantalla sin Retina las dos imágenes salen con la mitad de píxeles, y con un
    # tope fijo el del archivo, de 232 px, pasaba por el del fondo según en qué pantalla se abriera la ventana)
    if [ -n "$menu" ] && [ -s "$casa/captura-1.png" ]; then
      local alto ventana rel
      alto=$(sips -g pixelHeight "$casa/captura-1.png" | awk '/pixelHeight/ {print $2}')
      ventana=$(sips -g pixelHeight "$png" | awk '/pixelHeight/ {print $2}')
      rel=$((alto * 1000 / ventana))                             # (archivo ≈ 270 ‰, fondo ≈ 100 ‰)
      [ "$menu" = archivo ] && [ "$rel" -lt 175 ] && { echo "✗ $nombre: sale el menú del fondo, no el del archivo"; ok=0; }
      [ "$menu" = fondo ] && [ "$rel" -ge 175 ] && { echo "✗ $nombre: sale el menú de un archivo, no el del fondo"; ok=0; }
    fi
  else
    echo "✗ $nombre: sin captura (¿la app no arranca?)"; ok=0
  fi
  if [ "$accion" = terminal ]; then
    cp "$png.txt" "$OUT/$nombre.txt" 2>/dev/null
    for t in "GigabitEthernet0/0/0" "file-fl.cfg" "fi fl ffi ffl" "configuración"; do
      grep -qF "$t" "$png.txt" 2>/dev/null || { echo "✗ $nombre: el terminal no muestra «${t}»"; ok=0; }
    done
    # (el resaltado, tal como sale hacia el terminal: «up» y «down» con color, y distintos; las IPs también)
    cp "$png.resaltado.txt" "$OUT/$nombre.resaltado.txt" 2>/dev/null
    local r
    r=$(python3 -I - "$png.resaltado.txt" <<'PY' 2>&1
import re, sys
try: data = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except OSError: print("sin salida del resaltado"); sys.exit()
def color(word):                     # la última secuencia SGR antes de la palabra, en su misma línea
    for line in data.split("\n"):
        m = re.search(r"((?:\x1b\[[0-9;]*m)+)" + re.escape(word) + r"(?![\w.])", line)
        if m: return m.group(1)
    return None
up, down, ip = color("up"), color("down"), color("192.0.2.11")
fallos = []
if not up or not down or up == down: fallos.append(f"up/down sin resaltar o iguales (up={up!r} down={down!r})")
if not ip: fallos.append("la IP 192.0.2.11 sin resaltar")
print("; ".join(fallos))
PY
)
    [ -n "$r" ] && { echo "✗ $nombre: $r"; ok=0; }
    # (⌥ + arrastrar: sólo la columna de las IP; y la 1.ª fila, la misma celda de partida que la selección de SwiftTerm)
    if [ -n "${BLOQUE:-}" ]; then
      cp "$png.bloque.txt" "$OUT/$nombre.bloque.txt" 2>/dev/null
      [ "$(cat "$png.bloque.txt" 2>/dev/null)" = "$(printf 'IP-Address\n192.0.2.11\n198.51.100.1\n203.0.113.5')" ] \
        || { echo "✗ $nombre: la selección rectangular no es la columna de las IP: «$(tr '\n' '|' < "$png.bloque.txt" 2>/dev/null)»"; ok=0; }
      [[ "$(cat "$png.linea.txt" 2>/dev/null)" == IP-Address* ]] \
        || { echo "✗ $nombre: la celda de la app no es la de SwiftTerm («$(cat "$png.linea.txt" 2>/dev/null)»)"; ok=0; }
    fi
  fi
  if [ "$accion" = "espacios:verificar" ]; then
    cp "$png.espacios.txt" "$OUT/$nombre.espacios.txt" 2>/dev/null
    grep -q '^OK espacios:' "$png.espacios.txt" 2>/dev/null || { echo "✗ $nombre: falla el flujo de espacios"; ok=0; }
  fi
  if [ "$ok" = 0 ]; then
    local errores="$casa/Library/Application Support/Terminal NetDeck/logs/error.log"
    [ ! -f "$errores" ] || cp "$errores" "$OUT/$nombre-error.log"
  fi
  [ $ok = 1 ] && echo "✓ $nombre" || fallos=$((fallos + 1))
  rm -rf "$casa"
}

# Los clics y arrastres se prueban sobre EL MISMO ejecutable; el informe ausente o incompleto bloquea la demo.
if [ -z "${SOLO:-}" ] || [[ pestanas-interaccion == *"$SOLO"* ]]; then
  NETDECK_QA_BIN="$BIN" tools/verificar_pestanas.sh "$OUT" || fallos=$((fallos + 1))
fi

caso portada               es neo-tokyo     ""
caso portada-en            en neo-tokyo     ""
caso terminal-mobaxterm    es mobaxterm-net terminal
caso terminal-neo-tokyo    es neo-tokyo     terminal
caso terminal-papel        es papel         terminal
BLOQUE=1,23,4,35 caso terminal-bloque es neo-tokyo terminal
caso pestanas              es neo-tokyo     "pestañas:12"
caso explorador            es mobaxterm-net explorador
caso explorador-vista      es neo-tokyo     explorador:vista
caso explorador-md5        es neo-tokyo     explorador:md5
caso panel-sftp            es neo-tokyo     panel-sftp
caso macros                es neo-tokyo     macros
caso macros-en             en neo-tokyo     macros
caso tuneles               es neo-tokyo     tuneles
caso espacios              es neo-tokyo     espacios:verificar
caso espacios-en           en neo-tokyo     espacios:verificar
caso sesion-nueva          es neo-tokyo     sesion-nueva
caso ajustes-general       en neo-tokyo     settings:general
caso ajustes-terminal      es neo-tokyo     settings:terminal
caso ajustes-temas         es neo-tokyo     settings:temas
caso ajustes-resaltado     es neo-tokyo     settings:resaltado
caso ajustes-botones       es neo-tokyo     settings:botones
caso asistente             es neo-tokyo     setup:0
# (menús de clic derecho: puntos de la ventana de 1512×860, desde arriba a la izquierda; «fila-cortada», la última,
# que asoma a medias por abajo; «fondo-lista», la zona vacía de una carpeta con un solo archivo)
caso menu-archivo          es neo-tokyo     explorador "${CLIC_ARCHIVO:-700,300}" ""       archivo
caso menu-fila-cortada     es neo-tokyo     explorador "${CLIC_CORTADA:-700,806}" ""       archivo
caso menu-fondo-lista      es neo-tokyo     explorador "${CLIC_FONDO:-700,600}"   firmware fondo
caso menu-pestana          es neo-tokyo     "pestañas:3" "${CLIC_PESTANA:-330,20}"
caso menu-sesion           es neo-tokyo     "" "${CLIC_SESION:-90,208}"

echo "Capturas: $OUT"
[ $fallos = 0 ] && echo "✓ demo: todo responde (mira las capturas)" || { echo "✗ demo: $fallos caso(s) con fallos"; exit 1; }
