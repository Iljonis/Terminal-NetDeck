#!/bin/bash
# test_privacidad.sh — tools/privacidad.sh en un repositorio de prueba (carpeta temporal, HOME de mentira): revisa
# también lo nuevo que aún no está en git y, con --binario, falla si falta la app o el .dmg o no se pueden montar o
# leer (nunca da por comprobado lo que no ha podido comprobar). Lo lanza ./test.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
raiz=$(mktemp -d)
trap 'rm -rf "$raiz"' EXIT
fallos=0
mal() { echo "✗ test_privacidad: $*"; fallos=$((fallos + 1)); }

repo="$raiz/repo"
mkdir -p "$repo/tools" "$raiz/casa"
cp tools/privacidad.sh "$repo/tools/"
(cd "$repo" && git init -q && git add tools/privacidad.sh && echo "hola" > LEEME && git add LEEME) >/dev/null
priv() { (cd "$repo" && HOME="$raiz/casa" tools/privacidad.sh "$@") >"$raiz/salida" 2>&1; }

priv || mal "un repositorio limpio no pasa: $(cat "$raiz/salida")"
# (un archivo nuevo, sin añadir a git, con una IP privada: también se publicaría)
ip="10.20.$((15 * 2)).40"                                   # (formada aquí: que no salga en el código)
echo "let equipo = \"$ip\"" > "$repo/Nuevo.swift"
priv && mal "no revisa los archivos nuevos que aún no están en git"
rm "$repo/Nuevo.swift"
# (--binario sin app ni .dmg: no se da por comprobado)
priv --binario && mal "--binario pasa sin la app ni el .dmg"
grep -q "falta dist/Terminal-NetDeck.dmg" "$raiz/salida" || mal "--binario no dice que falta el .dmg"
# (una app sin ejecutable y un .dmg que no se puede montar)
mkdir -p "$repo/build/Terminal NetDeck.app/Contents" "$repo/dist"
echo "no soy una imagen de disco" > "$repo/dist/Terminal-NetDeck.dmg"
priv --binario && mal "--binario pasa con un .dmg que no se puede montar"
grep -q "no se puede montar" "$raiz/salida" || mal "--binario no dice que el .dmg no se puede montar"
grep -q "no tiene el ejecutable" "$raiz/salida" || mal "--binario no dice que a la app le falta el ejecutable"

# (app sintética e imagen simulada: la prueba del scanner no necesita montar volúmenes ni compilar la app)
cat > "$repo/.gitignore" <<'IGNORADOS'
build/
dist/
tools/privacidad.local
IGNORADOS
app="$repo/build/Terminal NetDeck.app"
mkdir -p "$app/Contents/MacOS" "$raiz/bin"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.example.TerminalNetDeck</string>
<key>NetDeckSource</key><string></string>
</dict></plist>
PLIST
printf '#!/bin/sh\nexit 0\n' > "$app/Contents/MacOS/TerminalNetDeck"
chmod +x "$app/Contents/MacOS/TerminalNetDeck"
cat > "$raiz/bin/hdiutil" <<'MONTAJE'
#!/bin/bash
if [ "$1" = attach ]; then
  shift
  while [ "$#" -gt 0 ]; do
    if [ "$1" = -mountpoint ]; then cp -R "$PRIVACIDAD_APP" "$2/"; exit $?; fi
    shift
  done
  exit 2
fi
[ "$1" = detach ] && exit 0
exit 2
MONTAJE
# (los envoltorios permiten simular un fallo real del scanner, después de producir salida o coincidencias)
cat > "$raiz/bin/grep" <<'SCANNER'
#!/bin/bash
/usr/bin/grep "$@"
estado=$?
case "${PRIVACIDAD_FALLO:-}" in
  grep) exit 2 ;;
  grep_binario) for arg in "$@"; do [ "$arg" = -F ] && exit 2; done ;;
esac
exit "$estado"
SCANNER
cat > "$raiz/bin/strings" <<'LECTURA'
#!/bin/bash
/usr/bin/strings "$@"
estado=$?
[ "${PRIVACIDAD_FALLO:-}" = strings ] && exit 2
exit "$estado"
LECTURA
cat > "$raiz/bin/find" <<'ENUMERACION'
#!/bin/bash
/usr/bin/find "$@"
estado=$?
[ "${PRIVACIDAD_FALLO:-}" = find ] && exit 2
if [ "${PRIVACIDAD_FALLO:-}" = find_datos ]; then
  for arg in "$@"; do [ "$arg" = -exec ] && exit "$estado"; done
  exit 2
fi
exit "$estado"
ENUMERACION
chmod +x "$raiz/bin/"*
export PATH="$raiz/bin:$PATH" PRIVACIDAD_APP="$app"
priv --binario || mal "una app limpia con imagen simulada no pasa: $(cat "$raiz/salida")"

# (fuga al principio de varios MB: el echo | grep -q anterior terminaba con SIGPIPE 141 y daba falso verde)
dato="equipo-sintetico.$((9000 + 92)).invalid"
printf '%s\n' "$dato" > "$repo/tools/privacidad.local"
grande="$app/Contents/MacOS/grande"
printf '%s\n' "$dato" > "$grande"
awk 'BEGIN { for (i = 0; i < 65536; i++) print "relleno-sintetico-para-la-regresion-del-scanner-00000000000000000000" }' >> "$grande"
chmod +x "$grande"
priv --binario && mal "--binario da verde con una fuga temprana en varios MB"
grep -q "lleva un dato tuyo" "$raiz/salida" || mal "no detecta la fuga propia al principio de la app grande"
printf '/Users/%s/prueba\n' "$(id -un)" > "$grande"
awk 'BEGIN { for (i = 0; i < 65536; i++) print "relleno-sintetico-para-la-regresion-del-scanner-00000000000000000000" }' >> "$grande"
priv --binario && mal "--binario da verde con la carpeta personal al principio de varios MB"
grep -q "lleva tu carpeta personal" "$raiz/salida" || mal "no detecta la ruta propia al principio de la app grande"
rm "$grande" "$repo/tools/privacidad.local"

# (un error de grep no significa «sin coincidencias», ni siquiera después de una coincidencia)
PRIVACIDAD_FALLO=grep priv && mal "el scanner de código pasa si grep falla"
grep -q "ha fallado el scanner" "$raiz/salida" || mal "no informa del error del scanner de código"
printf '%s\n' "$dato" > "$repo/tools/privacidad.local"
PRIVACIDAD_FALLO=grep_binario priv --binario && mal "el scanner binario pasa si grep falla"
grep -q "ha fallado el scanner" "$raiz/salida" || mal "no informa del error del scanner binario"
printf '%s\n' "$dato" > "$app/Contents/MacOS/coincidencia"
chmod +x "$app/Contents/MacOS/coincidencia"
PRIVACIDAD_FALLO=grep_binario priv --binario && mal "el scanner pasa si grep encuentra y después falla"
grep -q "ha fallado el scanner" "$raiz/salida" || mal "una coincidencia tapa el error del scanner"
rm "$repo/tools/privacidad.local" "$app/Contents/MacOS/coincidencia"
for fallo in strings find; do
  PRIVACIDAD_FALLO=$fallo priv --binario && mal "--binario pasa si $fallo produce salida parcial y falla"
  grep -q "no se ha podido leer entera" "$raiz/salida" || mal "no informa del fallo de $fallo"
done
PRIVACIDAD_FALLO=find_datos priv --binario && mal "--binario pasa si falla la enumeración de archivos de usuario"
grep -q "no se ha podido enumerar entera" "$raiz/salida" || mal "no informa del error al enumerar archivos de usuario"

# (el otro find | grep -q tenía el mismo corte anticipado con muchos archivos de usuario)
mkdir "$app/Contents/datos"
for ((i = 0; i < 2048; i++)); do : > "$app/Contents/datos/dato-sintetico-para-la-regresion-del-scanner-$i.json"; done
priv --binario && mal "--binario pasa con muchos archivos de datos de usuario"
grep -q "lleva archivos de datos de usuario" "$raiz/salida" || mal "no detecta un inventario grande de archivos de usuario"
rm -r "$app/Contents/datos"
priv --binario || mal "una app limpia no pasa tras las regresiones: $(cat "$raiz/salida")"

[ $fallos = 0 ] && echo "✓ Privacidad revisa lo nuevo, detecta fugas tempranas grandes y falla ante errores del scanner"
exit $((fallos > 0))
