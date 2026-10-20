#!/bin/bash
# test_osv.sh — tools/osv.py con respuestas de OSV.dev preparadas (sin red): sólo una respuesta completa y bien formada
# cuenta como comprobada; lo demás sale con error, nunca como «sin vulnerabilidades». Lo lanza ./test.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
fallos=0
mal() { echo "✗ test_osv: $*"; fallos=$((fallos + 1)); }

cat > "$d/Package.resolved" <<'J'
{"pins": [{"location": "https://github.com/apple/swift-nio.git", "state": {"version": "2.0.0"}},
          {"location": "https://github.com/apple/swift-log", "state": {"version": "1.5.0"}}]}
J
python3 tools/osv.py consulta "$d/Package.resolved" > "$d/q.json" || mal "no monta la consulta de un Package.resolved correcto"
informe() { printf '%s' "$1" > "$d/r.json"; python3 tools/osv.py informe "$d/q.json" "$d/r.json" 2>/dev/null; }

out=$(informe '{"results": [{}, {}]}') || mal "una respuesta completa sin vulnerabilidades da error"
[ -z "$out" ] || mal "una respuesta sin vulnerabilidades lista alguna: $out"
out=$(informe '{"results": [{"vulns": [{"id": "GHSA-xxxx"}]}, {}]}') || mal "una respuesta con vulnerabilidades da error"
[[ $out == *"swift-nio 2.0.0: GHSA-xxxx"* ]] || mal "no dice cuál es la vulnerable: $out"
informe '{}' && mal "una respuesta sin «results» cuenta como comprobada"
informe '{"results": [{}]}' && mal "una respuesta con menos resultados que consultas cuenta como comprobada"
informe '{"results": [{}, "x"]}' && mal "un resultado que no es un objeto cuenta como comprobado"
informe '{"results": [{"vulns": [{"sin_id": 1}]}, {}]}' && mal "una vulnerabilidad sin id cuenta como comprobada"
informe '{"results": [{"vulns": [], "next_page_token": "t"}, {}]}' && mal "una respuesta con más páginas cuenta como completa"
informe 'esto no es json' && mal "una respuesta que no es JSON cuenta como comprobada"
printf '{"pins": [{"location": "https://github.com/x/y", "state": {"branch": "main"}}]}' > "$d/rama.resolved"
python3 tools/osv.py consulta "$d/rama.resolved" >/dev/null 2>&1 && mal "una dependencia sin versión se da por consultable"
printf 'roto' > "$d/roto.resolved"
python3 tools/osv.py consulta "$d/roto.resolved" >/dev/null 2>&1 && mal "un Package.resolved roto se da por bueno"

[ $fallos = 0 ] && echo "✓ OSV: sólo una respuesta completa cuenta como comprobada"
exit $((fallos > 0))
