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
  [ "$(stat -f %Lp "$copia")" = 700 ] && [ "$(stat -f %Lp "$copia/ssh_config")" = 600 ] || mal "la copia no es sólo tuya (0700/0600)"
fi

# Lo que no es una .app dentro de una carpeta que existe no se borra nunca.
(HOME="$casa"; . tools/sustituir_app.sh
 sustituir_app "$casa/.config/netdeck" "$raiz/Applications" && exit 1
 sustituir_app "$raiz/build/Terminal NetDeck.app" "" && exit 1
 exit 0) >/dev/null || mal "sustituir_app acepta algo que no es una .app o un destino vacío"
cmp -s "$raiz/sesiones.antes" "$casa/.config/netdeck/ssh_config" || mal "las sesiones han cambiado tras los intentos fallidos"

[ $fallos = 0 ] && echo "✓ Actualizar conserva las sesiones, ~/.ssh/config, botones y listas (con su copia)"
exit $((fallos > 0))
