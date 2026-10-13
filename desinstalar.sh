#!/bin/bash
# desinstalar.sh — quita «Terminal NetDeck.app».
#   ./desinstalar.sh          → la app (se quedan tus temas y ajustes)
#   ./desinstalar.sh --todo   → también temas instalados, marcas y ajustes
# El Llavero no se toca: esas contraseñas son también las de NetDeck.
set -euo pipefail
NOMBRE="Terminal NetDeck"
for d in /Applications "$HOME/Applications"; do
  if [ -d "$d/$NOMBRE.app" ]; then rm -rf "$d/$NOMBRE.app" && echo "✓ Quitada $d/$NOMBRE.app"; fi
done
if [ "${1:-}" = --todo ]; then
  rm -rf "$HOME/Library/Application Support/$NOMBRE"
  defaults delete io.netdeck.terminal >/dev/null 2>&1 || true
  echo "✓ Quitados temas instalados, marcas y ajustes"
fi
