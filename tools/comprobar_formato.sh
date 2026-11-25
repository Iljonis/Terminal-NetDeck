#!/bin/bash
# tools/comprobar_formato.sh — falla si en Sources/, Tests/, tools/, .github/ o windows/ hay un archivo de texto con BOM UTF-8
# (EF BB BF: lo mete el editor de Windows y rompe diffs, shebangs y `import` de la primera línea) o con CR (CRLF: los .sh
# no arrancan y el diff entero sale cambiado). Mira lo que está en git y lo nuevo que se subiría. Lo lanza ./test.sh.
# Excepción: tools/demo/salida.txt lleva CRLF a propósito (la manda así un equipo de red; .gitattributes lo marca -text).
# Los .ps1 son al revés: con algún carácter fuera de ASCII (acentos, «—») TIENEN que llevar BOM (PowerShell 5.1 los lee como
# ANSI sin él y salen «estÃ¡»); sin él y sólo ASCII, también valen. En los .ps1 el CR sigue prohibido.
set -uo pipefail
cd "$(dirname "$0")/.."

fallos=0
R=$'\e[38;5;204m'; V=$'\e[38;5;48m'; N=$'\e[0m'
aviso() { echo "${R}✗ $1${N}"; fallos=$((fallos + 1)); }

revisados=0
if ! listado=$(git ls-files -z --cached --others --exclude-standard -- Sources Tests tools .github windows | tr '\0' '\n'); then
  aviso "no se pueden enumerar los archivos de git"
fi
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$f" = tools/demo/salida.txt ] && continue
  [ -f "$f" ] || continue
  grep -qI . "$f" 2>/dev/null || continue                        # (los binarios y los archivos vacíos, fuera)
  revisados=$((revisados + 1))
  bom=no; [ "$(head -c3 "$f" | od -An -tx1 | tr -d ' \n')" = efbbbf ] && bom=si
  case "$f" in
    *.ps1)
      if [ "$bom" = no ] && [ -n "$(LC_ALL=C tr -d '\000-\177' < "$f" | head -c1)" ]; then
        aviso "$f tiene acentos u otros caracteres no ASCII pero no BOM (PowerShell 5.1 los leería como ANSI: añade EF BB BF)"
      fi ;;
    *) if [ "$bom" = si ]; then aviso "$f empieza con BOM UTF-8 (quítalo: los 3 primeros bytes)"; fi ;;
  esac
  grep -q $'\r' "$f"; estado=$?
  if [ "$estado" -eq 0 ]; then aviso "$f tiene CR (fin de línea CRLF: tiene que ser LF)"
  elif [ "$estado" -gt 1 ]; then aviso "$f: ha fallado la lectura (grep)"; fi
done <<< "$listado"
[ "$revisados" -gt 0 ] || aviso "no se ha encontrado ningún archivo que revisar (¿fuera de git?)"

if [ $fallos = 0 ]; then echo "${V}✓ Formato: sin BOM ni CR${N} ($revisados archivos de Sources, Tests, tools, .github y windows)"; fi
exit $((fallos > 0))
