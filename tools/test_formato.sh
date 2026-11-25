#!/bin/bash
# test_formato.sh — tools/comprobar_formato.sh en un repositorio de prueba (carpeta temporal): falla con un BOM o un CR
# en Sources/, Tests/, tools/, .github/ o windows/ (también en archivos nuevos sin añadir a git), deja pasar el CRLF de
# tools/demo/salida.txt, los .ps1 de windows/ con BOM y los binarios, y no da por bueno lo que no puede enumerar.
# Lo lanza ./test.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
raiz=$(mktemp -d)
trap 'rm -rf "$raiz"' EXIT
fallos=0
mal() { echo "✗ test_formato: $*"; fallos=$((fallos + 1)); }

repo="$raiz/repo"
mkdir -p "$repo/tools/demo" "$repo/Sources/NetDeckCore" "$repo/Tests" "$repo/.github/workflows" "$repo/windows/scripts"
cp tools/comprobar_formato.sh "$repo/tools/"
printf 'import Foundation\n' > "$repo/Sources/NetDeckCore/A.swift"
printf 'import Testing\n' > "$repo/Tests/ATests.swift"
printf '#!/bin/bash\necho hola\n' > "$repo/tools/x.sh"
printf 'name: ci\n' > "$repo/.github/workflows/ci.yml"
printf 'linea\r\notra\r\n' > "$repo/tools/demo/salida.txt"                 # (CRLF a propósito: pasa)
printf '\xEF\xBB\xBFWrite-Host "ñ"\n' > "$repo/windows/scripts/a.ps1"          # (un .ps1 con acentos y BOM: pasa)
printf 'Write-Host "solo ascii"\n' > "$repo/windows/scripts/b.ps1"                  # (un .ps1 sólo ASCII sin BOM: pasa)
printf '# texto\n' > "$repo/windows/README.md"
printf '\xEF\xBB\xBF\r\n\x00\x01' > "$repo/tools/icono.bin"                    # (binario: no se mira)
(cd "$repo" && git init -q && git add -A) >/dev/null
comprobar() { (cd "$repo" && tools/comprobar_formato.sh) >"$raiz/salida" 2>&1; }

comprobar || mal "un repositorio limpio no pasa: $(cat "$raiz/salida")"

# (un BOM, un CRLF y un CR suelto en cada carpeta vigilada: todos fallan y dicen cuál)
for ruta in Sources/NetDeckCore/A.swift Tests/ATests.swift tools/x.sh .github/workflows/ci.yml; do
  cp "$repo/$ruta" "$raiz/original"
  { printf '\xEF\xBB\xBF'; cat "$raiz/original"; } > "$repo/$ruta"
  comprobar && mal "no detecta el BOM en $ruta"
  grep -q "$ruta empieza con BOM" "$raiz/salida" || mal "no dice qué archivo lleva BOM ($ruta)"
  awk '{ printf "%s\r\n", $0 }' "$raiz/original" > "$repo/$ruta"
  comprobar && mal "no detecta el CRLF en $ruta"
  grep -q "$ruta tiene CR" "$raiz/salida" || mal "no dice qué archivo lleva CR ($ruta)"
  { cat "$raiz/original"; printf 'una\rmezcla\n'; } > "$repo/$ruta"
  comprobar && mal "no detecta un CR suelto en $ruta"
  cp "$raiz/original" "$repo/$ruta"
done
comprobar || mal "no vuelve a pasar con los archivos restaurados: $(cat "$raiz/salida")"

# (un .ps1 con acentos sin BOM falla; con BOM, pasa; un BOM o un CR en otro archivo de windows/ también falla)
printf 'Write-Host "ñ"\n' > "$repo/windows/scripts/c.ps1"
comprobar && mal "no detecta un .ps1 con acentos sin BOM"
grep -q "windows/scripts/c.ps1 tiene acentos" "$raiz/salida" || mal "no dice qué .ps1 le falta el BOM"
printf '\xEF\xBB\xBFWrite-Host "ñ"\n' > "$repo/windows/scripts/c.ps1"
comprobar || mal "no deja pasar un .ps1 con acentos y BOM: $(cat "$raiz/salida")"
printf '\xEF\xBB\xBFWrite-Host "ñ"\r\n' > "$repo/windows/scripts/c.ps1"
comprobar && mal "no detecta el CR en un .ps1"
rm "$repo/windows/scripts/c.ps1"
printf '\xEF\xBB\xBF# texto\n' > "$repo/windows/README.md"
comprobar && mal "no detecta el BOM en un .md de windows/"
printf '# texto\n' > "$repo/windows/README.md"

# (un archivo nuevo, sin añadir a git, también se publicaría)
printf '\xEF\xBB\xBFimport Foundation\n' > "$repo/Sources/NetDeckCore/Nuevo.swift"
comprobar && mal "no revisa los archivos nuevos que aún no están en git"
rm "$repo/Sources/NetDeckCore/Nuevo.swift"

# (sin poder enumerar los archivos no se da por comprobado)
mkdir "$raiz/fuera"; cp -R "$repo/tools" "$raiz/fuera/"
(cd "$raiz/fuera" && GIT_CEILING_DIRECTORIES="$raiz" tools/comprobar_formato.sh) >"$raiz/salida" 2>&1 && mal "pasa fuera de un repositorio de git"
grep -q "no se pueden enumerar" "$raiz/salida" || mal "no avisa de que no puede enumerar los archivos"

[ $fallos = 0 ] && echo "✓ Formato: detecta BOM y CR en Sources, Tests, tools y .github, y deja pasar sus excepciones"
exit $((fallos > 0))
