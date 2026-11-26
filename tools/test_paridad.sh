#!/bin/bash
# test_paridad.sh — tools/comprobar_paridad.sh en una carpeta temporal: falla con una función de 6 o más líneas con el mismo
# cuerpo en Sources/TerminalNetDeck y en windows/Desktop/Sources (aunque cambien los espacios), deja pasar las que sólo
# comparten nombre, las cortas y las de tools/paridad_permitidos.txt. Lo lanza ./test.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
raiz=$(mktemp -d)
trap 'rm -rf "$raiz"' EXIT
fallos=0
mal() { echo "✗ test_paridad: $*"; fallos=$((fallos + 1)); }

mkdir -p "$raiz/Sources/TerminalNetDeck" "$raiz/windows/Desktop/Sources/NetDeckWindows" "$raiz/tools"
cat > "$raiz/Sources/TerminalNetDeck/A.swift" <<'SW'
struct A {
    func patron(_ q: String) -> String? {
        let hex = q.lowercased()
        guard hex.count == 12 else { return nil }
        let c = Array(hex)
        let a = String(c[0...1])
        return a
    }
    func corta() { print("a") }
    func parecida() {
        let x = 1
        let y = 2
        let z = 3
        print(x + y + z)
        print("mac")
    }
}
SW
cat > "$raiz/windows/Desktop/Sources/NetDeckWindows/B.swift" <<'SW'
final class B {
    func patron(_ q: String) -> String? {
        let hex   = q.lowercased()
        guard hex.count == 12 else { return nil }
        let c = Array(hex)
        let a = String(c[0...1])
        return a
    }
    func corta() { print("a") }
    func parecida() {
        let x = 1
        let y = 2
        let z = 3
        print(x + y + z)
        print("windows")
    }
}
SW
comprobar() { NETDECK_PARIDAD_RAIZ="$raiz" tools/comprobar_paridad.sh >"$raiz/salida" 2>&1; }

comprobar && mal "no detecta una función copiada entre Mac y Windows"
grep -q "patron" "$raiz/salida" || mal "no dice qué función está copiada"
grep -q "parecida\|corta" "$raiz/salida" && mal "da por copiadas funciones distintas o cortas: $(cat "$raiz/salida")"

printf 'patron  # motivo de la excepción\n' > "$raiz/tools/paridad_permitidos.txt"
comprobar || mal "no respeta tools/paridad_permitidos.txt: $(cat "$raiz/salida")"
rm "$raiz/tools/paridad_permitidos.txt"

sed -i.bak 's/hex.count == 12/hex.count == 13/' "$raiz/windows/Desktop/Sources/NetDeckWindows/B.swift"
comprobar || mal "no pasa cuando las dos funciones ya difieren: $(cat "$raiz/salida")"
grep -q "sin lógica copiada" "$raiz/salida" || mal "no dice que está todo en orden"

[ "$fallos" = 0 ] && echo "✓ Paridad revisa lo copiado entre Mac y Windows, deja pasar lo distinto y respeta sus excepciones"
exit $((fallos > 0))
