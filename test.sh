#!/bin/bash
# Tests: primero la privacidad (que no se publique nada tuyo: tools/privacidad.sh, y su propia prueba), el formato (sin
# BOM ni CR en Sources, Tests y tools: tools/comprobar_formato.sh, y su prueba), la paridad Mac/Windows (nada copiado entre
# las dos interfaces: tools/comprobar_paridad.sh, y su prueba), la comprobación de OSV y de los informes de QA (sin red), que actualizar no toque tus datos (tools/test_actualizacion.sh) y
# luego los del núcleo.
# Sólo con CommandLineTools, SwiftPM no siempre pasa el plugin de macros de Swift Testing.
set -euo pipefail
cd "$(dirname "$0")"
tools/privacidad.sh
tools/test_privacidad.sh
tools/comprobar_formato.sh
tools/test_formato.sh
tools/comprobar_paridad.sh
tools/test_paridad.sh
tools/test_osv.sh
tools/test_qa.sh
tools/test_actualizacion.sh
# (los tests, con una carpeta personal de prueba: ni su error.log ni sus copias van a las tuyas)
NETDECK_HOME=$(mktemp -d)
export NETDECK_HOME
trap 'rm -rf "$NETDECK_HOME"' EXIT
P="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d $P ]]; then swift test -Xswiftc -plugin-path -Xswiftc "$P" "$@"; else swift test "$@"; fi
