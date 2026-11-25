#!/bin/bash
# tools/comprobar_paridad.sh — mantiene a Mac y Windows «en la misma línea»: la lógica va UNA vez en NetDeckCore y las
# dos interfaces sólo la pintan (docs/agentes/paridad.md). Falla si una función de 6 o más líneas tiene el MISMO cuerpo en
# Sources/TerminalNetDeck (SwiftUI/AppKit) y en windows/Desktop/Sources (WinUI): es lógica copiada, y la próxima corrección
# llegará a una sola. También avisa (sin fallar) de las que sólo comparten nombre: suelen ser el mismo concepto escrito dos
# veces. Excepciones: un archivo tools/paridad_permitidos.txt con un nombre de función por línea y el motivo detrás de «#».
# Lo lanza ./test.sh (y tests.yml, en macOS); necesita python3. NETDECK_PARIDAD_RAIZ cambia la carpeta a revisar (pruebas).
set -uo pipefail
cd "$(dirname "$0")/.."
raiz="${NETDECK_PARIDAD_RAIZ:-.}"
R=$'\e[38;5;204m'; V=$'\e[38;5;48m'; A=$'\e[38;5;221m'; N=$'\e[0m'

command -v python3 >/dev/null || { echo "${R}✗ Paridad: falta python3${N}"; exit 1; }
permitidos="$raiz/tools/paridad_permitidos.txt"
[ -f "$permitidos" ] || permitidos=/dev/null

salida=$(python3 -I - "$raiz" "$permitidos" <<'PY'
import glob, hashlib, re, sys
raiz, permitidos = sys.argv[1], sys.argv[2]
ok = {l.split('#')[0].strip() for l in open(permitidos, encoding='utf-8')} - {''}
DECL = re.compile(r'^[ \t]*(?:@\w+\s+)*(?:(?:public|internal|private|fileprivate|static|final|nonisolated|override|mutating)\s+)*func\s+([A-Za-z_]\w*)\s*[<(]', re.M)

def cuerpos(carpeta):
    out = {}
    for f in sorted(glob.glob(f'{raiz}/{carpeta}/**/*.swift', recursive=True)):
        t = open(f, encoding='utf-8-sig', errors='replace').read()
        for m in DECL.finditer(t):
            i = t.find('{', m.end())
            if i < 0:
                continue
            prof, j = 0, i
            while j < len(t):
                prof += (t[j] == '{') - (t[j] == '}')
                if prof == 0:
                    break
                j += 1
            cuerpo = t[i:j + 1]
            if cuerpo.count('\n') >= 6:
                h = hashlib.md5(re.sub(r'\s+', '', cuerpo).encode()).hexdigest()
                out.setdefault(m.group(1), []).append((f.replace(raiz + '/', ''), h))
    return out

mac, win = cuerpos('Sources/TerminalNetDeck'), cuerpos('windows/Desktop/Sources')
iguales, parecidas = [], []
for n in sorted((set(mac) & set(win)) - ok):
    hm = {h for _, h in mac[n]}
    mismos = [(a, b) for a, ha in mac[n] for b, hb in win[n] if ha == hb]
    (iguales if mismos else parecidas).append((n, mismos[0] if mismos else (mac[n][0][0], win[n][0][0])))
for n, (a, b) in iguales:
    print(f'FALLO {n}: mismo cuerpo en {a} y {b}')
for n, (a, b) in parecidas:
    print(f'AVISO {n}: existe en {a} y en {b}')
print(f'TOTAL {len(mac)} {len(win)}')
PY
) || { echo "${R}✗ Paridad: no se ha podido analizar${N}"; exit 1; }

fallos=$(grep -c '^FALLO' <<< "$salida")
while IFS= read -r l; do
  case "$l" in
    FALLO*) echo "${R}✗ Paridad: ${l#FALLO } → muévela a NetDeckCore (con test) y que las dos interfaces la llamen${N}" ;;
    AVISO*) [ -n "${NETDECK_PARIDAD_VERBOSE:-}" ] && echo "${A}· ${l#AVISO }${N}" ;;
  esac
done <<< "$salida"
avisos=$(grep -c '^AVISO' <<< "$salida")
if [ "$fallos" = 0 ]; then
  echo "${V}✓ Paridad: sin lógica copiada entre Mac y Windows${N} ($avisos nombres comunes de función; NETDECK_PARIDAD_VERBOSE=1 los lista)"
fi
exit $((fallos > 0))
