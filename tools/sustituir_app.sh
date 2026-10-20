#!/bin/bash
# sustituir_app.sh — se carga con «source» (install.sh y tools/test_actualizacion.sh). Cambiar la app no toca nunca tus
# datos: ni ~/.config/netdeck (sesiones, botones), ni ~/.ssh/config, ni Application Support (listas, temas, copias).
#
#   copiar_datos SOPORTE ETIQUETA   → copia de sesiones, ~/.ssh/config, botones, listas, macros y túneles en
#                                     SOPORTE/copias/AAAAMMDD-HHMMSS-ETIQUETA (0700; los archivos, 0600); falla si
#                                     no se puede crear la carpeta o copiar alguno de los que existen
#   sustituir_app NUEVA DESTINO     → copia y luego cambia DESTINO/<nombre>.app por NUEVA (sólo esa .app; atómico:
#                                     si falla, se queda la de antes). Sin la copia de tus datos, no se cambia nada.

copiar_datos() {
  local soporte=$1 etiqueta=$2 copia par origen fallos=0
  [ -n "$soporte" ] || { echo "   (sin carpeta de copias)"; return 1; }
  copia="$soporte/copias/$(date +%Y%m%d-%H%M%S)-$etiqueta"
  mkdir -p "$copia" && chmod 700 "$soporte" "$soporte/copias" "$copia" || { echo "   (sin carpeta de copias)"; return 1; }
  for par in "ssh_config:$HOME/.config/netdeck/ssh_config" "ssh-config:$HOME/.ssh/config" \
             "botones.txt:$HOME/.config/netdeck/botones.txt" "listas.json:$soporte/listas.json" \
             "macros.json:$soporte/macros.json" "tuneles.json:$soporte/tuneles.json" \
             "espacios.json:$soporte/espacios.json" "panel-sftp.json:$soporte/panel-sftp.json"; do
    origen=${par#*:}
    if [ -f "$origen" ]; then
      cp -L "$origen" "$copia/${par%%:*}" && chmod 600 "$copia/${par%%:*}" \
        || { echo "   (sin copia de ~${origen#"$HOME"})"; fallos=$((fallos + 1)); }
    fi
  done
  rmdir "$copia" 2>/dev/null || echo "   copia de tus datos: ~${copia#"$HOME"}"
  [ $fallos = 0 ]
}

sustituir_app() {
  local nueva=$1 destino=$2 nombre temporal
  nombre=$(basename "$nueva")
  # (sólo una «X.app» dentro de DESTINO: nunca una ruta vacía ni una carpeta de datos)
  [[ $nombre == ?*.app && -d $nueva && -n $destino && -d $destino ]] || { echo "✗ sustituir_app: «${nueva}» → «${destino}» no vale"; return 1; }
  # (antes de cambiar una app ya instalada, la copia de tus datos: si no se puede hacer, no se toca nada)
  if [ -d "$destino/$nombre" ] && ! copiar_datos "${SOPORTE:-}" "instalar-$VERSION"; then
    echo "✗ sustituir_app: no se ha podido copiar tus datos antes de cambiar la app: no se cambia nada (sigue la de antes)"
    return 1
  fi
  echo "   copiando a ${destino}…"
  # Atómico: la nueva, entera, en una carpeta temporal del mismo destino; sólo entonces se aparta la de antes y se
  # cambian de nombre (si algo falla, vuelve la de antes). Nunca se borra la anterior antes de tener la nueva lista.
  temporal=$(mktemp -d "$destino/.$nombre.nueva.XXXXXX") || { echo "✗ sustituir_app: sin carpeta temporal en ${destino}"; return 1; }
  if ! cp -R "$nueva" "$temporal/$nombre"; then
    rm -rf "${temporal:?}"; echo "✗ sustituir_app: no se ha podido copiar la app nueva (sigue la de antes)"; return 1
  fi
  if [ -e "$destino/$nombre" ] && ! mv "$destino/$nombre" "$temporal/anterior.app"; then
    rm -rf "${temporal:?}"; echo "✗ sustituir_app: no se ha podido apartar la app de antes (sigue en su sitio)"; return 1
  fi
  if ! mv "$temporal/$nombre" "$destino/$nombre"; then
    if [ -d "$temporal/anterior.app" ] && ! mv "$temporal/anterior.app" "$destino/$nombre"; then
      # (ni la nueva ni la anterior en su sitio: no se borra nada; las dos siguen en la carpeta temporal)
      echo "✗ sustituir_app: no se ha podido poner la app nueva ni volver a la de antes: las dos están en ${temporal} (la anterior es «anterior.app»)"
      return 1
    fi
    rm -rf "${temporal:?}"; echo "✗ sustituir_app: no se ha podido poner la app nueva (sigue la de antes)"; return 1
  fi
  rm -rf "${temporal:?}"
}
