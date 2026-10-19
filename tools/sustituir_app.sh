#!/bin/bash
# sustituir_app.sh — se carga con «source» (install.sh y tools/test_actualizacion.sh). Cambiar la app no toca nunca tus
# datos: ni ~/.config/netdeck (sesiones, botones), ni ~/.ssh/config, ni Application Support (listas, temas, copias).
#
#   copiar_datos SOPORTE ETIQUETA   → copia de sesiones, ~/.ssh/config, botones y listas en
#                                     SOPORTE/copias/AAAAMMDD-HHMMSS-ETIQUETA (0700; los archivos, 0600)
#   sustituir_app NUEVA DESTINO     → copia y luego cambia DESTINO/<nombre>.app por NUEVA (sólo esa .app)

copiar_datos() {
  local soporte=$1 etiqueta=$2 copia par
  copia="$soporte/copias/$(date +%Y%m%d-%H%M%S)-$etiqueta"
  mkdir -p "$copia" && chmod 700 "$soporte" "$soporte/copias" "$copia" || { echo "   (sin carpeta de copias)"; return 1; }
  for par in "ssh_config:$HOME/.config/netdeck/ssh_config" "ssh-config:$HOME/.ssh/config" \
             "botones.txt:$HOME/.config/netdeck/botones.txt" "listas.json:$soporte/listas.json"; do
    if [ -f "${par#*:}" ]; then
      cp -L "${par#*:}" "$copia/${par%%:*}" && chmod 600 "$copia/${par%%:*}" || echo "   (sin copia de ${par#*:})"
    fi
  done
  rmdir "$copia" 2>/dev/null || echo "   copia de tus datos: ~${copia#"$HOME"}"
}

sustituir_app() {
  local nueva=$1 destino=$2 nombre
  nombre=$(basename "$nueva")
  # (sólo una «X.app» dentro de DESTINO: nunca una ruta vacía ni una carpeta de datos)
  [[ $nombre == ?*.app && -d $nueva && -n $destino && -d $destino ]] || { echo "✗ sustituir_app: «${nueva}» → «${destino}» no vale"; return 1; }
  if [ -d "$destino/$nombre" ]; then copiar_datos "$SOPORTE" "instalar-$VERSION" || true; fi   # (sin copia también se sigue: sólo cambia la app)
  echo "   copiando a ${destino}…"
  rm -rf "${destino:?}/$nombre"
  cp -R "$nueva" "$destino/"
}
