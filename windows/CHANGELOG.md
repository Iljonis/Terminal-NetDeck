# Changelog (Windows)

Historial de cambios de la versión de Windows de Terminal NetDeck. Sigue el formato de
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). El de la versión de macOS está en el [CHANGELOG de la raíz](../CHANGELOG.md).

## 0.9.0 (en desarrollo)

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

### Cambiado

- La barra lateral sigue el orden del Mac, con menús de sesiones, favoritas, recientes y grupos.
- Los atajos que interferían con la entrada de la consola usan Mayús o Alt. Véase la
  [tabla de atajos](README.md#atajos-de-teclado).
- La demo usa `ssh_config` y `known_hosts` temporales. `NETDECK_BUILD_ONLY=1` permite compilar con `-Demo` sin
  abrir la ventana.

### Corregido

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
