#!/bin/bash
# tools/privacidad.sh — comprueba que el repositorio y lo que se distribuye (la app compilada y el .dmg) no llevan
# datos personales: IPs privadas, rutas /Users/<alguien>, correos, claves privadas, contraseñas escritas en el código
# ni los equipos de tu propio ~/.ssh/config.
#
#   tools/privacidad.sh              → código, temas, reglas y plantillas (lo que está en git y lo nuevo que se subiría:
#                                      todo lo que no ignora .gitignore)
#   tools/privacidad.sh --binario    → además la app de build/ y dist/Terminal-NetDeck.dmg, que tienen que estar: si
#                                      faltan o no se pueden montar, leer o validar, falla (no se da por comprobado)
#
# Tus dominios, nombres de equipo o usuarios propios se comprueban sin publicarlos: escríbelos, uno por línea, en
# tools/privacidad.local (no se sube a git). Y si existe ~/.ssh/config, sus Host/HostName/User también se buscan.
# Las IPs de ejemplo permitidas son las de documentación (RFC 5737: 192.0.2.x, 198.51.100.x, 203.0.113.x).
set -uo pipefail
cd "$(dirname "$0")/.."

binario=0; [ "${1:-}" = --binario ] && binario=1
fallos=0
R=$'\e[38;5;204m'; V=$'\e[38;5;48m'; N=$'\e[0m'

aviso() { echo "${R}✗ $1${N}"; fallos=$((fallos + 1)); }

# (grep sin -q: consume la entrada entera, sin SIGPIPE del productor ni errores tapados por una coincidencia)
filtrar() {
  grep "$@"
  local estado=$?
  [ "$estado" -le 1 ]             # (1 es «sin coincidencias»; cualquier otro fallo invalida la revisión)
}
coincide() {
  local contexto=$1 estado
  shift
  grep "$@" >/dev/null
  estado=$?
  if [ "$estado" -gt 1 ]; then aviso "$contexto: ha fallado el scanner de privacidad (grep)"; fi
  return "$estado"
}

# Lo que se publica: archivos de git y los nuevos que aún no lo están pero se subirían (menos este script, que contiene
# los patrones).
archivos=()
if ! listado=$(git ls-files --cached --others --exclude-standard); then
  aviso "no se pueden enumerar los archivos de git"
fi
while IFS= read -r f; do
  case "$f" in tools/privacidad.sh|docs/capturas/*.png) continue ;; esac
  [ -f "$f" ] && archivos+=("$f")
done <<< "$listado"
[ ${#archivos[@]} -gt 0 ] || aviso "no se ha encontrado ningún archivo que revisar (¿fuera de git?)"

buscar() {  # descripción  regex(ERE)  [regex de excepciones]
  local desc=$1 re=$2 excepto=${3:-}
  local hits
  [ ${#archivos[@]} -gt 0 ] || return
  if ! hits=$(filtrar -nIE -- "$re" "${archivos[@]}" 2>/dev/null \
    | { if [ -n "$excepto" ]; then filtrar -vE -- "$excepto"; else cat; fi; }); then
    aviso "$desc: ha fallado el scanner de privacidad (grep)"
  fi
  [ -z "$hits" ] || { aviso "$desc:"; printf '%s\n' "$hits" | sed -n '1,10{s/^/    /;p;}'; }
}

# IPs privadas (RFC 1918) y de carrier-grade NAT: en el código sólo valen las de documentación.
buscar "IPs privadas" '(^|[^0-9.])(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7]))\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'
# Rutas personales (los ejemplos usan ~ o /Users/x en tests)
buscar "rutas de una carpeta personal" '/Users/[A-Za-z0-9._-]{2,}' '/Users/(x|usuario|tu\.usuario)([^A-Za-z0-9._-]|$)'
# Correos (salvo los de ejemplo o de GitHub)
buscar "correos" '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.(com|es|net|org|eu|io|dev|ro|de|fr|it|pt|co|uk)([^A-Za-z]|$)' '@(example\.(com|org)|users\.noreply\.github\.com|anthropic\.com)|git@github\.com|jonayrr\.jr@gmail\.com'
# Claves privadas y tokens
buscar "claves privadas" 'BEGIN [A-Z ]*PRIVATE KEY'
buscar "tokens" '(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,})'
# Contraseñas escritas en el código: una variable/constante «…password… = "literal"» o una clave de configuración
# «password: valor» (no los textos que la piden, como «admin@equipo's password:»).
buscar "contraseñas en el código" '(let|var)[[:space:]]+[A-Za-z_]*([Pp]assword|[Pp]asswd|[Ss]ecret)[A-Za-z_]*[[:space:]]*(:[[:space:]]*String)?[[:space:]]*=[[:space:]]*"[^"]{4,}"' '"(secreto|prueba|x+|abc[0-9]*|1234[0-9]*)"'
buscar "contraseñas en archivos de configuración" '^[[:space:]]*(password|passwd|secret)[[:space:]]*[:=][[:space:]]*[^[:space:]]{4,}'

# Lo tuyo, sin publicarlo: tools/privacidad.local y los equipos de tu ~/.ssh/config.
propios=()
if [ -f tools/privacidad.local ]; then
  while IFS= read -r l; do
    l=${l%%#*}; l=$(echo "$l" | xargs); [ -n "$l" ] && propios+=("$l")
  done < tools/privacidad.local
fi
# (de ~/.ssh/config sólo las direcciones reales: las IPs y los nombres con dominio de HostName, y sus dominios; los
# alias de sesión y los usuarios suelen ser palabras corrientes: si quieres comprobarlos, ponlos en privacidad.local)
configs=()
for c in "$HOME/.ssh/config" "$HOME/.config/netdeck/ssh_config"; do [ -f "$c" ] && configs+=("$c"); done
# (y los que incluyen: «Include ~/.config/…»)
for c in "${configs[@]:-}"; do
  [ -n "$c" ] || continue
  if ! incluidos=$(filtrar -iE '^[[:space:]]*Include[[:space:]]' "$c" | sed -E 's/^[[:space:]]*[Ii]nclude[[:space:]]+//'); then
    aviso "no se pueden comprobar los Include del ssh_config"
  fi
  while read -r inc; do
    inc=${inc/#\~/$HOME}
    for f in $inc; do [ -f "$f" ] && configs+=("$f"); done
  done <<< "$incluidos"
done
if [ ${#configs[@]} -gt 0 ]; then
  if ! contenido=$(sed 's/#.*//' "${configs[@]}"); then aviso "no se pueden leer los ssh_config para comprobar datos propios"; fi
  while read -r k v; do
    [ "$(echo "$k" | tr '[:upper:]' '[:lower:]')" = hostname ] || continue
    for x in $v; do
      [[ $x == *[*?%]* || $x =~ ^(127\.|localhost$) || $x != *.* ]] && continue
      propios+=("$x")
      # (y el dominio: «sw1.oficina.empresa.es» → «empresa.es»)
      [[ $x =~ [A-Za-z] ]] && propios+=("$(echo "$x" | awk -F. 'NF>=2 {print $(NF-1)"."$NF}')")
    done
  done <<< "$contenido"
fi
datos_propios=""
if [ ${#propios[@]} -gt 0 ]; then
  if ! datos_propios=$(printf '%s\n' "${propios[@]}" | sort -u); then aviso "no se puede preparar la lista de datos propios"; fi
  while IFS= read -r p; do
    [ ${#archivos[@]} -gt 0 ] || break
    if ! hits=$(filtrar -lIF -- "$p" "${archivos[@]}" 2>/dev/null); then
      aviso "ha fallado el scanner de datos propios (grep)"
    fi
    if [ -n "$hits" ]; then
      aviso "aparece un dato tuyo (de tools/privacidad.local o ~/.ssh/config) en: $(printf '%s\n' "$hits" | sed -n '1,3p' | tr '\n' ' ')"
    fi
  done <<< "$datos_propios"
fi

# La app compilada y el .dmg
revisar_app() {  # carpeta .app [local: la de install.sh, que apunta a tu carpeta del código a propósito]
  local app=$1 s
  # (sin el ejecutable y el Info.plist no es la app que se publica: no se da por revisada)
  if [ ! -x "$app/Contents/MacOS/TerminalNetDeck" ] || ! /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist" >/dev/null 2>&1; then
    aviso "$app no tiene el ejecutable o el Info.plist: no se puede comprobar"
    return
  fi
  if ! s=$(find "$app" -type f \( -perm -u+x -o -name '*.plist' -o -name '*.tema' -o -name '*.yml' \) -exec strings -a {} +) || [ -z "$s" ]; then
    aviso "$app no se ha podido leer entera: no se puede comprobar"
    return
  fi
  # (`NetDeckSource` sólo lo lleva la instalación local, para «Actualizar» desde el código; el .dmg lo lleva vacío y se
  # comprueba aparte: sin esto, cada ./install.sh daba un falso aviso que tapaba los de verdad)
  if [ "${2:-}" = local ]; then
    if ! s=$(filtrar -v '<key>NetDeckSource</key>' <<< "$s"); then
      aviso "$app: ha fallado el scanner de privacidad (grep)"
      return
    fi
  fi
  local usuario datos
  if ! usuario=$(id -un) || [ -z "$usuario" ]; then
    aviso "$app: no se puede identificar la carpeta personal"
  elif coincide "$app" -E "/Users/$usuario([^A-Za-z0-9._-]|$)" <<< "$s"; then
    aviso "$app lleva tu carpeta personal"
  fi
  if [ ${#propios[@]} -gt 0 ]; then
    while IFS= read -r p; do
      if coincide "$app" -F -- "$p" <<< "$s"; then aviso "$app lleva un dato tuyo («${p:0:2}…»)"; fi
    done <<< "$datos_propios"
  fi
  if ! datos=$(find "$app" \( -name '*.json' -o -name 'ssh_config' -o -name 'botones.txt' -o -name 'abiertas*' -o -name '*.log' \)); then
    aviso "$app no se ha podido enumerar entera: no se puede comprobar"
  elif [ -n "$datos" ]; then
    aviso "$app lleva archivos de datos de usuario"
  fi
}
if [ $binario = 1 ]; then
  if [ -d "build/Terminal NetDeck.app" ]; then revisar_app "build/Terminal NetDeck.app" local
  else aviso "falta build/Terminal NetDeck.app (./install.sh --dmg): no se puede comprobar"; fi
  if [ ! -f dist/Terminal-NetDeck.dmg ]; then
    aviso "falta dist/Terminal-NetDeck.dmg (./install.sh --dmg): no se puede comprobar"
  else
    m=$(mktemp -d)
    if ! hdiutil attach -nobrowse -readonly -mountpoint "$m" dist/Terminal-NetDeck.dmg >/dev/null 2>&1; then
      aviso "dist/Terminal-NetDeck.dmg no se puede montar: no se puede comprobar"
    elif [ ! -d "$m/Terminal NetDeck.app" ]; then
      aviso "dist/Terminal-NetDeck.dmg no lleva «Terminal NetDeck.app»"
      hdiutil detach "$m" >/dev/null 2>&1
    else
      revisar_app "$m/Terminal NetDeck.app"
      if ! fuente=$(/usr/libexec/PlistBuddy -c 'Print NetDeckSource' "$m/Terminal NetDeck.app/Contents/Info.plist" 2>/dev/null); then
        aviso "el .dmg no permite comprobar NetDeckSource"
      elif [ -n "$fuente" ]; then
        aviso "el .dmg apunta a una carpeta de código de este Mac"
      fi
      if ! extra=$(ls -A "$m" | filtrar -vxE 'Terminal NetDeck\.app|Applications|\.DS_Store|\.fseventsd|\.Trashes'); then
        aviso "el .dmg no se ha podido enumerar entero: no se puede comprobar"
      fi
      [ -z "$extra" ] || aviso "el .dmg lleva más cosas que la app: $(echo "$extra" | tr '\n' ' ')"
      hdiutil detach "$m" >/dev/null 2>&1
    fi
    rmdir "$m" 2>/dev/null
  fi
fi

if [ $fallos = 0 ]; then
  echo "${V}✓ Privacidad: sin datos personales${N} (${#archivos[@]} archivos$([ $binario = 1 ] && echo ', app y .dmg'); ${#propios[@]} datos tuyos comprobados)"
fi
exit $((fallos > 0))
