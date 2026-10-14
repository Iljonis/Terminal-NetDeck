#!/bin/bash
# tools/privacidad.sh — comprueba que el repositorio y lo que se distribuye (la app compilada y el .dmg) no llevan
# datos personales: IPs privadas, rutas /Users/<alguien>, correos, claves privadas, contraseñas escritas en el código
# ni los equipos de tu propio ~/.ssh/config.
#
#   tools/privacidad.sh              → código, temas, reglas y plantillas (lo que está en git)
#   tools/privacidad.sh --binario    → además la app de build/ y dist/Terminal-NetDeck.dmg si existen
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

# Lo que se publica: archivos de git (menos este script, que contiene los patrones).
archivos=()
while IFS= read -r f; do [ -f "$f" ] && archivos+=("$f"); done < <(git ls-files | grep -vE '^(tools/privacidad\.sh|docs/capturas/.*\.png)$')

buscar() {  # descripción  regex(ERE)  [regex de excepciones]
  local desc=$1 re=$2 excepto=${3:-}
  local hits
  hits=$(grep -nIE -- "$re" "${archivos[@]}" 2>/dev/null | { if [ -n "$excepto" ]; then grep -vE -- "$excepto"; else cat; fi; })
  [ -z "$hits" ] || { aviso "$desc:"; echo "$hits" | head -10 | sed 's/^/    /'; }
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
  while read -r inc; do
    inc=${inc/#\~/$HOME}
    for f in $inc; do [ -f "$f" ] && configs+=("$f"); done
  done < <(grep -iE '^[[:space:]]*Include[[:space:]]' "$c" | sed -E 's/^[[:space:]]*[Ii]nclude[[:space:]]+//')
done
if [ ${#configs[@]} -gt 0 ]; then
  while read -r k v; do
    [ "$(echo "$k" | tr '[:upper:]' '[:lower:]')" = hostname ] || continue
    for x in $v; do
      [[ $x == *[*?%]* || $x =~ ^(127\.|localhost$) || $x != *.* ]] && continue
      propios+=("$x")
      # (y el dominio: «sw1.oficina.empresa.es» → «empresa.es»)
      [[ $x =~ [A-Za-z] ]] && propios+=("$(echo "$x" | awk -F. 'NF>=2 {print $(NF-1)"."$NF}')")
    done
  done < <(cat "${configs[@]}" | sed 's/#.*//')
fi
if [ ${#propios[@]} -gt 0 ]; then
  while IFS= read -r p; do
    if grep -qIF -- "$p" "${archivos[@]}" 2>/dev/null; then
      aviso "aparece un dato tuyo (de tools/privacidad.local o ~/.ssh/config) en: $(grep -lIF -- "$p" "${archivos[@]}" | head -3 | tr '\n' ' ')"
    fi
  done < <(printf '%s\n' "${propios[@]}" | sort -u)
fi

# La app compilada y el .dmg
revisar_app() {  # carpeta .app
  local app=$1 s
  s=$(find "$app" -type f \( -perm -u+x -o -name '*.plist' -o -name '*.tema' -o -name '*.yml' \) -exec strings -a {} + 2>/dev/null)
  if echo "$s" | grep -qE "/Users/$(id -un)([^A-Za-z0-9._-]|$)"; then aviso "$app lleva tu carpeta personal"; fi
  if [ ${#propios[@]} -gt 0 ]; then
    while IFS= read -r p; do
      if echo "$s" | grep -qF -- "$p"; then aviso "$app lleva un dato tuyo («${p:0:2}…»)"; fi
    done < <(printf '%s\n' "${propios[@]}" | sort -u)
  fi
  if find "$app" \( -name '*.json' -o -name 'ssh_config' -o -name 'botones.txt' -o -name 'abiertas*' -o -name '*.log' \) | grep -q .; then
    aviso "$app lleva archivos de datos de usuario"
  fi
}
if [ $binario = 1 ]; then
  if [ -d "build/Terminal NetDeck.app" ]; then revisar_app "build/Terminal NetDeck.app"; fi
  if [ -f dist/Terminal-NetDeck.dmg ]; then
    m=$(mktemp -d)
    if hdiutil attach -nobrowse -readonly -mountpoint "$m" dist/Terminal-NetDeck.dmg >/dev/null 2>&1; then
      revisar_app "$m/Terminal NetDeck.app"
      if /usr/libexec/PlistBuddy -c 'Print NetDeckSource' "$m/Terminal NetDeck.app/Contents/Info.plist" 2>/dev/null | grep -q .; then
        aviso "el .dmg apunta a una carpeta de código de este Mac"
      fi
      extra=$(ls -A "$m" | grep -vxE 'Terminal NetDeck\.app|Applications|\.DS_Store|\.fseventsd|\.Trashes' || true)
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
