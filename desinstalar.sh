#!/bin/bash
# desinstalar.sh — quita «Terminal NetDeck.app».
#   ./desinstalar.sh          → la app (se quedan tus temas y ajustes)
#   ./desinstalar.sh --todo   → también temas instalados, marcas y ajustes
# El Llavero no se toca: esas contraseñas son también las de NetDeck. Tus sesiones (~/.config/netdeck/ssh_config) y
# las copias de tus datos (Application Support/Terminal NetDeck/copias) tampoco, ni con --todo.
set -euo pipefail
NOMBRE="Terminal NetDeck"
for d in /Applications "$HOME/Applications"; do
  if [ -d "$d/$NOMBRE.app" ]; then rm -rf "$d/$NOMBRE.app" && echo "✓ Quitada $d/$NOMBRE.app"; fi
done
if [ "${1:-}" = --todo ]; then
  soporte="$HOME/Library/Application Support/$NOMBRE"
  if [ -d "$soporte" ]; then
    find "$soporte" -mindepth 1 -maxdepth 1 ! -name copias -exec rm -rf {} +
    rmdir "$soporte" 2>/dev/null || echo "✓ Las copias de tus datos siguen en ~${soporte#"$HOME"}/copias"
  fi
  defaults delete io.netdeck.terminal >/dev/null 2>&1 || true
  echo "✓ Quitados temas instalados, marcas y ajustes"
fi
