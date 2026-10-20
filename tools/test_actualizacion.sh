#!/bin/bash
# test_actualizacion.sh — una actualización (el mismo paso de install.sh: tools/sustituir_app.sh) en una carpeta
# personal de prueba: la app cambia y tus sesiones, ~/.ssh/config, botones y listas quedan idénticos, con su copia.
# Lo lanza ./test.sh. Nada de tus datos: HOME temporal y direcciones de documentación (RFC 5737).
set -euo pipefail
cd "$(dirname "$0")/.."
raiz=$(mktemp -d)
trap 'rm -rf "$raiz"' EXIT
fallos=0
mal() { echo "✗ test_actualizacion: $*"; fallos=$((fallos + 1)); }

casa="$raiz/casa"
SOPORTE="$casa/Library/Application Support/Terminal NetDeck"
VERSION=9.9.9
mkdir -p "$casa/.config/netdeck" "$casa/.ssh" "$SOPORTE" "$raiz/Applications/Terminal NetDeck.app/Contents" \
         "$raiz/build/Terminal NetDeck.app/Contents"
cat > "$casa/.config/netdeck/ssh_config" <<'EOF'
# @grupo Core
Host core-01
    HostName 192.0.2.11
    User tu.usuario

Host bastion
    HostName 198.51.100.1
EOF
printf 'Include ~/.config/netdeck/ssh_config\n\nHost *\n    ServerAliveInterval 30\n' > "$casa/.ssh/config"
printf '[Cisco]\nshow version\n' > "$casa/.config/netdeck/botones.txt"
printf '{"listas":[]}\n' > "$SOPORTE/listas.json"
for archivo in macros.json tuneles.json espacios.json panel-sftp.json; do
  printf '{"prueba":"conservar"}\n' > "$SOPORTE/$archivo"
  cp -p "$SOPORTE/$archivo" "$raiz/$archivo.antes"
done
chmod 600 "$casa/.config/netdeck/ssh_config" "$casa/.ssh/config"
echo vieja > "$raiz/Applications/Terminal NetDeck.app/Contents/version"
echo nueva > "$raiz/build/Terminal NetDeck.app/Contents/version"
cp -p "$casa/.config/netdeck/ssh_config" "$raiz/sesiones.antes"
cp -p "$casa/.ssh/config" "$raiz/ssh.antes"
cp -p "$casa/.config/netdeck/botones.txt" "$raiz/botones.antes"
cp -p "$SOPORTE/listas.json" "$raiz/listas.antes"

(HOME="$casa"; . tools/sustituir_app.sh; sustituir_app "$raiz/build/Terminal NetDeck.app" "$raiz/Applications") >/dev/null \
  || mal "sustituir_app ha fallado"

[ "$(cat "$raiz/Applications/Terminal NetDeck.app/Contents/version" 2>/dev/null)" = nueva ] || mal "la app no se ha cambiado"
cmp -s "$raiz/sesiones.antes" "$casa/.config/netdeck/ssh_config" || mal "las sesiones han cambiado o ya no están"
cmp -s "$raiz/ssh.antes" "$casa/.ssh/config" || mal "~/.ssh/config ha cambiado (¿falta el Include?)"
cmp -s "$raiz/botones.antes" "$casa/.config/netdeck/botones.txt" || mal "los botones han cambiado"
cmp -s "$raiz/listas.antes" "$SOPORTE/listas.json" || mal "las listas han cambiado"
[ "$(stat -f %Lp "$casa/.config/netdeck/ssh_config")" = 600 ] || mal "las sesiones han perdido sus permisos 0600"
copia=$(ls -d "$SOPORTE"/copias/*-instalar-9.9.9 2>/dev/null | head -1)
if [ -z "$copia" ]; then
  mal "no hay copia de antes de cambiar la app"
else
  cmp -s "$raiz/sesiones.antes" "$copia/ssh_config" || mal "la copia de las sesiones no es idéntica"
  cmp -s "$raiz/ssh.antes" "$copia/ssh-config" || mal "la copia de ~/.ssh/config no es idéntica"
  for archivo in macros.json tuneles.json espacios.json panel-sftp.json; do
    cmp -s "$raiz/$archivo.antes" "$SOPORTE/$archivo" || mal "$archivo ha cambiado"
    cmp -s "$raiz/$archivo.antes" "$copia/$archivo" || mal "la copia de $archivo no es idéntica"
  done
  [ "$(stat -f %Lp "$copia")" = 700 ] && [ "$(stat -f %Lp "$copia/ssh_config")" = 600 ] || mal "la copia no es sólo tuya (0700/0600)"
fi

# Lo que no es una .app dentro de una carpeta que existe no se borra nunca.
(HOME="$casa"; . tools/sustituir_app.sh
 sustituir_app "$casa/.config/netdeck" "$raiz/Applications" && exit 1
 sustituir_app "$raiz/build/Terminal NetDeck.app" "" && exit 1
 exit 0) >/dev/null || mal "sustituir_app acepta algo que no es una .app o un destino vacío"
cmp -s "$raiz/sesiones.antes" "$casa/.config/netdeck/ssh_config" || mal "las sesiones han cambiado tras los intentos fallidos"

# Si la copia de la nueva falla a medias, la de antes sigue entera y no quedan carpetas temporales.
mkdir -p "$raiz/rota/Terminal NetDeck.app/Contents"
echo rota > "$raiz/rota/Terminal NetDeck.app/Contents/version"
echo x > "$raiz/rota/Terminal NetDeck.app/Contents/ilegible" && chmod 000 "$raiz/rota/Terminal NetDeck.app/Contents/ilegible"
(HOME="$casa"; . tools/sustituir_app.sh; sustituir_app "$raiz/rota/Terminal NetDeck.app" "$raiz/Applications" && exit 1; exit 0) \
  >/dev/null 2>&1 || mal "sustituir_app da por buena una copia que ha fallado"
[ "$(cat "$raiz/Applications/Terminal NetDeck.app/Contents/version" 2>/dev/null)" = nueva ] \
  || mal "una copia fallida ha borrado o estropeado la app de antes"
[ -z "$(ls -A "$raiz/Applications" | grep -v '^Terminal NetDeck.app$')" ] || mal "quedan restos de la copia fallida en el destino"
chmod 600 "$raiz/rota/Terminal NetDeck.app/Contents/ilegible"

# La primera vez (sin app anterior) también funciona y no deja restos.
mkdir -p "$raiz/Vacia"
(HOME="$casa"; . tools/sustituir_app.sh; sustituir_app "$raiz/build/Terminal NetDeck.app" "$raiz/Vacia") >/dev/null \
  || mal "sustituir_app falla sin app anterior"
[ "$(ls -A "$raiz/Vacia")" = "Terminal NetDeck.app" ] || mal "instalar por primera vez deja restos o no instala"

# Si no se puede poner la nueva, vuelve la de antes y no quedan restos.
mkdir -p "$raiz/Fallo/Terminal NetDeck.app/Contents" && echo vieja > "$raiz/Fallo/Terminal NetDeck.app/Contents/version"
(HOME="$casa"; . tools/sustituir_app.sh
 mv() { [[ $1 == *.nueva.*/"Terminal NetDeck.app" ]] && return 1; command mv "$@"; }
 sustituir_app "$raiz/build/Terminal NetDeck.app" "$raiz/Fallo" && exit 1; exit 0) >/dev/null 2>&1 \
  || mal "sustituir_app da por buena una app nueva que no se ha podido poner"
[ "$(cat "$raiz/Fallo/Terminal NetDeck.app/Contents/version" 2>/dev/null)" = vieja ] || mal "fallar al poner la nueva no ha devuelto la de antes"
[ "$(ls -A "$raiz/Fallo")" = "Terminal NetDeck.app" ] || mal "fallar al poner la nueva deja restos"

# Si tampoco puede volver la de antes, no se borra nada: la nueva y la anterior siguen en la carpeta temporal.
mkdir -p "$raiz/Doble/Terminal NetDeck.app/Contents" && echo vieja > "$raiz/Doble/Terminal NetDeck.app/Contents/version"
(HOME="$casa"; . tools/sustituir_app.sh
 mv() { [[ $1 == *.nueva.* ]] && return 1; command mv "$@"; }
 sustituir_app "$raiz/build/Terminal NetDeck.app" "$raiz/Doble" && exit 1; exit 0) >/dev/null 2>&1 \
  || mal "sustituir_app da por buena una vuelta atrás fallida"
temporal=$(ls -d "$raiz/Doble"/.Terminal\ NetDeck.app.nueva.* 2>/dev/null | head -1 || true)
if [ -z "$temporal" ]; then
  mal "una vuelta atrás fallida ha borrado la carpeta temporal (con la app nueva y la anterior)"
else
  [ "$(cat "$temporal/anterior.app/Contents/version" 2>/dev/null)" = vieja ] || mal "una vuelta atrás fallida ha borrado la app anterior"
  [ "$(cat "$temporal/Terminal NetDeck.app/Contents/version" 2>/dev/null)" = nueva ] || mal "una vuelta atrás fallida ha borrado la app nueva"
fi

# Sin la copia de tus datos no se cambia la app: un archivo que no se puede leer, o ninguna carpeta de copias.
mkdir -p "$raiz/SinCopia/Terminal NetDeck.app/Contents" && echo vieja > "$raiz/SinCopia/Terminal NetDeck.app/Contents/version"
chmod 000 "$casa/.config/netdeck/botones.txt"
(HOME="$casa"; . tools/sustituir_app.sh; sustituir_app "$raiz/build/Terminal NetDeck.app" "$raiz/SinCopia" && exit 1; exit 0) \
  >"$raiz/sincopia.salida" 2>&1 || mal "sustituir_app cambia la app aunque no haya podido copiar tus datos"
chmod 600 "$casa/.config/netdeck/botones.txt"
[ "$(cat "$raiz/SinCopia/Terminal NetDeck.app/Contents/version" 2>/dev/null)" = vieja ] || mal "sin copia de tus datos se ha cambiado la app"
grep -q "no se cambia nada" "$raiz/sincopia.salida" || mal "sustituir_app no dice que no ha podido copiar tus datos"
[ "$(ls -A "$raiz/SinCopia")" = "Terminal NetDeck.app" ] || mal "sin copia de tus datos quedan restos en el destino"
(HOME="$casa"; SOPORTE=""; . tools/sustituir_app.sh; sustituir_app "$raiz/build/Terminal NetDeck.app" "$raiz/SinCopia" && exit 1; exit 0) \
  >/dev/null 2>&1 || mal "sustituir_app cambia la app sin carpeta de copias"
[ "$(cat "$raiz/SinCopia/Terminal NetDeck.app/Contents/version" 2>/dev/null)" = vieja ] || mal "sin carpeta de copias se ha cambiado la app"

# install.sh entero (en una copia, con swift/codesign de mentira): si no compila o no se firma, se para sin instalar,
# aunque quede el ejecutable de una compilación anterior.
inst="$raiz/inst"
mkdir -p "$inst/repo/tools" "$inst/repo/Temas" "$inst/repo/Resaltado" "$inst/falsos" "$inst/release"
cp install.sh "$inst/repo/" && cp tools/sustituir_app.sh "$inst/repo/tools/"
touch "$inst/repo/LICENSE" "$inst/repo/THIRD_PARTY_NOTICES.md"
printf '#!/bin/sh\necho viejo\n' > "$inst/release/TerminalNetDeck"
printf '#!/bin/sh\nexit 1\n' > "$inst/falsos/swiftc"
printf '#!/bin/sh\nexit 1\n' > "$inst/falsos/pgrep"
instalar() {   # $1: 0 compila / 1 no · $2: 0 firma / 1 no → la carpeta personal de la prueba (+ « ok» si acabó bien)
  printf '#!/bin/bash\ncase "$*" in *--show-bin-path*) echo "%s" ;; *) [ %s = 0 ] && exit 0; echo "error: roto" >&2; exit 1 ;; esac\n' \
    "$inst/release" "$1" > "$inst/falsos/swift"
  printf '#!/bin/sh\nexit %s\n' "$2" > "$inst/falsos/codesign"
  chmod +x "$inst/falsos/"* "$inst/release/TerminalNetDeck"
  local h; h=$(mktemp -d "$inst/casa.XXXXXX")
  if (cd "$inst/repo" && HOME="$h" PATH="$inst/falsos:$PATH" ./install.sh --usuario) >"$h.salida" 2>&1; then echo "$h ok"; else echo "$h"; fi
}
r=$(instalar 1 0)
[[ $r != *" ok" ]] || mal "install.sh sigue aunque no compile"
[ ! -e "${r% ok}/Applications/Terminal NetDeck.app" ] || mal "install.sh instala el binario de una compilación anterior"
grep -q "No se ha compilado" "${r% ok}.salida" || mal "install.sh no dice que no ha compilado"
r=$(instalar 0 1)
[[ $r != *" ok" ]] || mal "install.sh sigue aunque no se pueda firmar"
[ ! -e "${r% ok}/Applications/Terminal NetDeck.app" ] || mal "install.sh instala una app sin firmar"
grep -q "No se ha podido firmar" "${r% ok}.salida" || mal "install.sh no dice que no ha podido firmar"

[ $fallos = 0 ] && echo "✓ Actualizar conserva las sesiones, ~/.ssh/config, botones y listas (con su copia)"
exit $((fallos > 0))
