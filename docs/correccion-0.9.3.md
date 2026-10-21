# Corrección de interacción de las pestañas

La revisión de la distribución anterior encontró un defecto en `AppModel.attach`: el monitor local consumía los
clics y llamaba directamente a los métodos del `NSHostingView`, evitando el recorrido normal de AppKit/SwiftUI.
La selección y el cierre podían dejar de responder al ratón.

## Por qué no lo detectaron las comprobaciones anteriores

Los tests del núcleo no ejecutaban la interfaz. La demo guardaba capturas de las pestañas sin exigir cambios de
selección, cierres ni reordenaciones. Además, el binario local declaraba SDK 15.0 y el distribuido SDK 26.5: macOS
aplicaba comportamientos distintos de compatibilidad. En una comparación con los mismos datos de ejemplo, el clic
por coordenadas funcionó en el local y falló en la distribución. Cambiar únicamente la declaración del SDK de una
copia aislada de diagnóstico cambió el resultado. Esa modificación no forma parte del producto.

También se detectó un cálculo circular del ancho en `TopBar`: medía la fila después de encogerse y usaba esa
medida para volver a reducir el espacio de las pestañas. Ahora toma el ancho del contenedor mediante
`GeometryReader`, manteniendo accesibles las pestañas. Los controles de crear, herramientas y ajustes quedan anclados arriba
a la derecha; la batería comprueba su posición después de reordenar y cerrar pestañas.

## Corrección y controles

- El monitor devuelve siempre el evento original. Los gestos abarcan el cuerpo completo de la pestaña para
  seleccionar y reordenar; la X mantiene su botón y su área de 24 × 24 puntos, con resaltado.
- La geometría se actualiza también al desplazar la barra. La instrumentación mantiene la misma estructura de vistas
  que el recorrido normal.
- `tools/verificar_paquete.sh` monta el DMG sin instalarlo, verifica firma, versión y SDK moderno, y ejecuta la demo
  con el ejecutable que contiene. La publicación depende de ese resultado y del QA SSH/SFTP en loopback.
- `tools/verificar_pestanas.sh` exige un informe completo de clics, cierres y arrastres en ventana, pantalla completa
  y pestañas estrechas. `tools/test_qa.sh` comprueba que los informes incompletos o fallidos se rechazan.
- MultiExec excluye de la línea los destinos que dejan de aceptar teclado durante una automatización: liberar una
  reserva no los reincorpora al sufijo de esa orden.
- Las copias de edición remota se publican sin reemplazar archivos existentes. Los servidores sin esa garantía
  conservan la copia local y requieren confirmar expresamente una sobrescritura. Los guardados fallidos se reintentan
  al disponer de conexión, con espera progresiva y sin necesitar otro guardado en el editor.

Las comprobaciones usan carpetas personales temporales y ejemplos; no requieren sesiones ni credenciales reales.
