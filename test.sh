#!/bin/bash
# Tests del núcleo. Sólo con CommandLineTools, SwiftPM no siempre pasa el plugin de macros de Swift Testing.
set -euo pipefail
cd "$(dirname "$0")"
P="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d $P ]]; then exec swift test -Xswiftc -plugin-path -Xswiftc "$P" "$@"; fi
exec swift test "$@"
