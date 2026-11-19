# Terminal NetDeck en Windows · 2026-11-19

Rama `windows/p14-escritorio`. La última compilación se preparó sin abrir la ventana. Las capturas corresponden a
pasadas anteriores de la demo con datos ficticios. La [referencia de macOS](../../docs/capturas/portada-liquid-glass.png)
usa Liquid Glass. WinUI usa superficies opacas con los colores del tema.

## Compilación y pruebas del núcleo

| Comprobación | Resultado |
|---|---|
| `desktop.ps1 -Demo` con `NETDECK_BUILD_ONLY=1` | Compilación correcta. SwiftPM emitió un aviso sobre el enlace de la carpeta de salida. |
| `windows/scripts/test.ps1 --no-parallel` | 553 pruebas correctas en 93 suites. En una ejecución paralela anterior hubo bloqueos de escritura de archivos temporales. |
| Importación de MobaXterm | La prueba recuperó los marcadores de un `.mobaconf` ficticio detrás de más de 20 000 caracteres de configuración e ignoró la sección de contraseñas. |
| Consola serie | La prueba confirmó que la validación previa acepta COM42 aunque el puerto no exista como archivo. Windows anunciaba COM1. |
| SFTP local | OpenSSH de Windows listó un archivo y una carpeta ficticios en un servidor temporal en `127.0.0.1`. |

Las órdenes y la limpieza previa del build están en la [referencia de Windows](../../docs/agentes/windows.md#compilación-y-pruebas).

## Pruebas con la ventana

- **Importación:** se abrió el diálogo nativo desde la tarjeta. En una pasada de CSV, la vista previa mostró dos
  sesiones y la barra lateral sólo añadió la marcada.
- **Sesiones:** se abrió el menú «+». Después de corregir el filtro vacío de la barra lateral, volvieron a verse
  todos los grupos y sesiones de ejemplo. Se detectó un recorte en el submenú de grupo y se ajustó su ancho.
- **Terminal:** se vieron las líneas y la viñeta del CRT, el desplazamiento del historial con la rueda y la
  marca ● REC. El archivo de registro contenía la salida ficticia tras cerrar la sesión.

## Pendiente en la última compilación

- Importar un `.mobaconf` desde el diálogo hasta que aparezcan sus sesiones en la barra lateral. Revisar el ancho
  del submenú «+» y la apertura desde favoritas y grupos.
- Comparar CRT, LCD, fósforo y holograma con la referencia de macOS. Probar la barra del historial, selección
  normal y rectangular, copia y copia al seleccionar.
- Recorrer Contraseñas, Temas, Fuentes, Resaltado, Terminal → Historial, Registro y Listas. Comprobar en el editor
  los saltos, la clave, las notas, la credencial, el perfil por sesión y la configuración en serie.
- Abrir un grupo en vista dividida, arrastrar sus separadores y guardar y restaurar un espacio. Comprobar menús
  contextuales y atajos sin interferir con la entrada del terminal.
- Probar BREAK en un puerto COM real, SFTP lateral contra un servidor local de prueba y el envío y la exclusión
  de participantes en Listas y MultiExec.

El [plan de Windows](../PLAN.md#paridad-restante-y-distribución) mantiene abierta la pasada visual.
