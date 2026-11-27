# Changelog (Windows)

Historial de cambios de la versión de Windows de Terminal NetDeck. Sigue el formato de
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). El de la versión de macOS está en el [CHANGELOG de la raíz](../CHANGELOG.md).

## 1.1.1 - 2026-11-27

### Añadido

- **Categorías de botones**, como en el Mac: en el panel de botones, crear, renombrar (si ya existe, se juntan),
  subir, bajar y borrar con sus botones (pide confirmación; queda copia en `botones.txt.anterior`). Cambiar la
  categoría de un botón lo lleva al final de la suya, y uno nuevo entra al final de su categoría. Las operaciones son
  las de `ButtonFile` del núcleo.

### Cambiado

- **Nada que instalar antes:** el Setup.exe, el `.msi` y la portable llevan dentro Windows App Runtime 1.5 (modo «self-contained» de
  Microsoft: sus archivos junto al ejecutable y las clases WinRT en el manifiesto del `.exe`) y el cliente de Win32-OpenSSH 10.4 de
  Microsoft (carpeta `OpenSSH`), como MobaXterm o SecureCRT. La portable se abre sin ser administrador y sin la Microsoft Store, y
  SSH, SFTP y los túneles funcionan aunque el PC no tenga la característica opcional «Cliente OpenSSH».
  - `incluir-dependencias.ps1` los baja de URL fijas con sha256 (`dependencias.json`) y comprueba la firma de Microsoft de cada
    `.exe` y `.dll`; `preparar-instalador.ps1` lo llama.
  - La app usa el runtime incluido si está `Microsoft.WindowsAppRuntime.dll` junto al ejecutable (sin bootstrapper); una compilación
    de desarrollo sigue usando el instalado. `SystemTools` prefiere el `ssh.exe` incluido y la app lo pone delante en el PATH (para
    `-J` y `sftp.exe`).
  - El `.msi` ya no comprueba el runtime ni se niega a instalar, y el Setup.exe ya no instala el redistribuible de Microsoft (el que
    dejó la 1.1.0 se queda en el equipo).
  - El CI prueba la portable y el Setup.exe en un Windows sin el runtime y comprueba que no lo instalan.

## 1.1.0 - 2026-11-26

<!-- La versión de Windows es la del repositorio y va en la misma Release que el .dmg: windows-release.yml comprueba que
     existe la sección «## X.Y.Z» de la versión del tag. Lo nuevo después de publicar va en una sección «## Sin publicar». -->

Primera versión oficial para Windows.

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
- Instalador de un paso, `Terminal-NetDeck-X.Y.Z-Setup.exe` (WiX Burn, en castellano):
  - lleva dentro el redistribuible oficial de Windows App Runtime 1.5 y lo instala en silencio si falta, antes de la app;
  - el CI lo prueba en un Windows sin el runtime;
  - el actualizador de la app prefiere este instalador al `.msi`.
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
- Apariencia más cercana a la del Mac, con la esencia de cada tema:
  - Todos los controles de las ventanas emergentes (botones, campos, desplegables, casillas, interruptores, menús y
    ayudas) usan los colores del tema, no los de Windows.
  - Avisos y confirmaciones como los del Mac: icono, título y explicación; «Cancelar» y el botón de confirmar a la
    derecha, en rojo si no se puede deshacer (borrar, órdenes peligrosas); caja de una línea para renombrar.
  - Pegado seguro: «¿Pegar N líneas?», la pestaña de destino y ⚠ delante de cada orden peligrosa.
  - Barra de estado con las etiquetas del Mac (⬆ versión nueva, MULTIEXEC ×n, modo de las contraseñas), la hora con
    el formato del tema y los avisos importantes (✗ 🔑 ⎋ ⬆) en color.
  - Iconos de la barra de 30×26 con el color del tema al pasar el ratón y estado activo (MultiExec, pantalla
    dividida, SFTP lateral, sesiones).

### Corregido

- El `ssh_config` de NetDeck ya no hereda permisos que OpenSSH rechazaba («Bad owner or permissions»): se protege al
  guardarlo y se repara antes de cada conexión.
- La pestaña elegida ya no se ve gris con el ratón encima y se puede llevar al primer puesto al arrastrarla. El
  arrastre funciona también desde una ventana en segundo plano.
- La ventana de una pestaña separada usa el tema (barra de título y botón).
- Guardar sesiones ya no añade otro bloque «Include» al `~/.ssh/config` cada vez, y se siguen los Include con «~» o
  «C:/…» del `~/.ssh/config` propio.
- Una instalación nueva en un Windows en castellano arranca en castellano (antes, en inglés).
- El explorador SFTP lateral ya no sale vacío.
- La edición remota ya no cierra la app al abrir un archivo.

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
