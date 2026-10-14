#!/bin/bash
# Tests: primero la privacidad (que no se publique nada tuyo: tools/privacidad.sh) y luego los del núcleo.
# Sólo con CommandLineTools, SwiftPM no siempre pasa el plugin de macros de Swift Testing.
set -euo pipefail
cd "$(dirname "$0")"
tools/privacidad.sh
P="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d $P ]]; then exec swift test -Xswiftc -plugin-path -Xswiftc "$P" "$@"; fi
exec swift test "$@"
