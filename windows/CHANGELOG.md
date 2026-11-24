# Changelog (Windows)

Historial de cambios de la versión de Windows de Terminal NetDeck. Sigue el formato de
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). El de la versión de macOS está en el [CHANGELOG de la raíz](../CHANGELOG.md).

## Sin publicar

<!-- Al publicar, el título pasa a ser «## X.Y.Z» (la versión de Windows es la del repositorio y va en la misma Release que
     el .dmg): windows-release.yml comprueba que existe esa sección. -->

### Añadido

- Selector nativo de importación con vista previa y selección de sesiones. Admite `.mobaconf` y `.mxtsessions` de
  MobaXterm, SecureCRT, PuTTY, electerm, JSON de NetDeck, CSV y OpenSSH.
- Menú «+» con conexión rápida, terminal local, sesiones nuevas, listas, favoritas y grupos desde los que conectar.
- Terminal con historial por rueda y barra, selección normal y rectangular, copia al seleccionar y grabación
  a archivo con indicador ● REC.
- Filtros CRT, LCD, fósforo y holograma. Ajustes de fuente de interfaz, colores de cada tema, importación de `.tema`,
  tema claro u oscuro según Windows, origen y vista previa del resaltado, contraseñas, registro y listas.
- Editor de sesiones con saltos, clave SSH, credencial por nombre, notas, perfil de terminal y parámetros COM.
  Consola serie nativa con envío de BREAK.
- Vista dividida con seis disposiciones y separadores arrastrables. Los espacios de trabajo guardan tamaños y paneles.
- SFTP lateral para terminales SSH, listas de equipos por salto y MultiExec en vivo con exclusión por pestaña.
- Túneles SSH, asistente de primer arranque, edición remota, macros, botones de órdenes y pegado seguro.
- Instalador MSI con WiX 4, Sparse Package y comprobación de Windows App Runtime 1.5. El actualizador verifica
  el SHA-256 y la firma del instalador.
- Asistente de primer arranque de siete pasos, como el del Mac: bienvenida con el logo, tema (se aplica al momento),
  fuentes, contraseñas, resaltado con vista previa, primera sesión y resumen. Se puede reabrir desde el engranaje.
- Arrastre de pestañas: la pestaña sigue al cursor, las vecinas se deslizan al hueco y se reordena al soltar; soltando
  fuera de la ventana se separa en otra, con «Devolver pestaña».
- Logo de NetDeck en el ejecutable (barra de tareas, Alt+Tab, accesos anclados), en el instalador y en el asistente.
- Selector de color propio, con muestras y campo hexadecimal, para los colores de temas y resaltado, y búsqueda en
  todos los registros.
- 76 archivos de fuentes (32 familias monoespaciadas) incluidos con sus licencias OFL/UFL.

### Cambiado

- La barra lateral sigue el orden del Mac, con menús de sesiones, favoritas, recientes y grupos.
- Los atajos que interferían con la entrada de la consola usan Mayús o Alt. Véase la
  [tabla de atajos](README.md#atajos-de-teclado).
- La demo usa `ssh_config` y `known_hosts` temporales. `NETDECK_BUILD_ONLY=1` permite compilar con `-Demo` sin
  abrir la ventana.
- Bordes y líneas más contrastados (botón REC, botones de comandos, tarjetas y barras): con 1 px y el acento al 30 %
  se veían finos y dentados en pantallas sin densidad alta.
- La instalación y la desinstalación ya no abren ventanas de PowerShell.

### Corregido

- El `ssh_config` de NetDeck ya no hereda permisos que OpenSSH rechazaba («Bad owner or permissions»): se protege al
  guardarlo y se repara antes de cada conexión.
- La pestaña elegida ya no se ve gris con el ratón encima y se puede llevar al primer puesto al arrastrarla. El
  arrastre funciona también desde una ventana en segundo plano.
- La ventana de una pestaña separada usa el tema (barra de título y botón).

- El buscador vacío de la barra lateral vuelve a mostrar todas las sesiones.
- Los dispositivos COM válidos llegan a la apertura Win32, aunque no existan como archivos.
- La edición remota comparte ruta y autenticación con el explorador SFTP.

### Seguridad

- El importador sólo conserva opciones SSH seguras y excluye las contraseñas de las sesiones importadas.
- Askpass usa el Administrador de credenciales para las contraseñas guardadas. Al iniciar SSH se limpian las
  variables de entorno de herramientas y ayudantes externos.
- Los enlaces del actualizador se limitan a GitHub y la instalación requiere una firma válida.

El [informe de escritorio](resultados/escritorio-2026-11-19.md) recoge la compilación, las pruebas y la pasada visual
pendiente. El [estado del port](ESTADO.md) documenta la distribución.
