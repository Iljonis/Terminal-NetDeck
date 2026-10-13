#!/bin/bash
# actualizar.sh — de momento, la forma de actualizar: compila este código, sustituye la app instalada, la cierra
# (guarda sus pestañas) y la vuelve a abrir con ellas. Lo mismo desde la app: menú Terminal NetDeck → Actualizar
# desde el código… (lo que pasa queda en ~/Library/Logs/Terminal NetDeck/actualizar.log).
cd "$(dirname "$0")" || exit 1
echo "=== $(date '+%F %T') · actualizar"
exec ./install.sh --actualizar "$@"
