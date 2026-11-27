# Terminal NetDeck para Windows

Cliente SSH para Windows 10 y Windows 11 hecho para ingenieros de red: gestor de sesiones SSH, Telnet, SFTP, FTP y
consola serie (COM), con saltos por bastión, MultiExec y pegado seguro, y resaltado de la salida de Cisco, Juniper,
Huawei y Nokia. Gratis y de código abierto (MIT): una alternativa a SecureCRT y a MobaXterm. Comparte con
[Terminal NetDeck para macOS](../README.md) el formato `ssh_config`, los temas `.tema` y el núcleo de conexiones.

[![Descargar para Windows](https://img.shields.io/badge/Descargar-Setup.exe_para_Windows-0078D4?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/Iljonis/Terminal-NetDeck/releases/latest)

> **Versión 1.1.0, la primera oficial para Windows.** Aún sin firma de código: SmartScreen avisa al abrir el instalador.
> Consulta el [estado del port](ESTADO.md) y el [informe de verificación](resultados/escritorio-2026-11-19.md) para ver
> qué se ha probado en la ventana y qué queda pendiente.

## Requisitos

- **Windows 10 versión 2004 (10.0.19041) o superior**, 64 bits (x64). Compatible con Windows 11.
- **Cliente OpenSSH** (`ssh.exe`), que Windows trae de serie en *Configuración → Aplicaciones → Características opcionales*. Las sesiones SSH, el
  explorador SFTP y los túneles lo usan.
- **Windows App Runtime 1.5 (x64)** (el Framework y su DDLM): la interfaz lo necesita. **`Terminal-NetDeck-<versión>-Setup.exe` lo incluye y lo
  instala solo** si falta (el redistribuible oficial de Microsoft, en silencio). No hace falta red: va dentro del instalador. Desinstalar
  NetDeck no lo quita, porque es un componente de Windows que usan otras apps.
  - El `.msi` suelto no lo incluye, pero lo comprueba: si falta, se detiene antes de copiar nada y avisa con el enlace de descarga
    (<https://aka.ms/windowsappsdk/1.5/latest/windowsappruntimeinstall-x64.exe>). Si la comprobación fallara en tu equipo, se salta con
    `SKIP_WINAPPRUNTIME_CHECK=1` al instalar por línea de órdenes.
  - La versión portable (`.zip`) tampoco lo lleva. Si falta, Windows lo avisa al abrirla y ofrece descargarlo.

## Instalación desde una release

Las descargas de Windows están en la [última versión](https://github.com/Iljonis/Terminal-NetDeck/releases/latest),
junto al `.dmg` de macOS.

1. Descarga `Terminal-NetDeck-<versión>-Setup.exe` (unos 120 MB: lleva dentro Windows App Runtime 1.5).
2. Ejecútalo, marca «Acepto la licencia», pulsa **Instalar** y acepta el aviso de administrador (UAC). Instala el runtime si falta y
   la app en `C:\Program Files\Terminal NetDeck`. Sin otros pasos.
3. Abre **Terminal NetDeck** desde el menú Inicio.

Otras descargas de la misma Release:

- **`Terminal-NetDeck-<versión>.msi`:** para despliegues gestionados (`msiexec /i … /qn`) en equipos que ya tienen el runtime.
  El acceso del escritorio es opcional (`ADDLOCAL=Principal,AccesoEscritorio`).
- **`Terminal-NetDeck-<versión>-portable-x64.zip`:** sin instalar. Los datos se guardan junto al ejecutable. Necesita el runtime ya instalado.
- En silencio con el Setup.exe: `Terminal-NetDeck-<versión>-Setup.exe /quiet` (con `/log archivo.txt` para el registro).

El actualizador de la app descarga el Setup.exe de la versión nueva y comprueba su SHA-256 y su firma.

Mientras no haya firma, Windows (SmartScreen) puede avisar de que el instalador es de un editor desconocido.

## Primera vez

Si no tienes sesiones guardadas, **el asistente aparece solo**: una bienvenida, un formulario para tu primera sesión (nombre y equipo; usuario
y puerto, opcionales) y un «todo listo». Puedes saltártelo con «Omitir» y añadir sesiones luego con **+ Nueva sesión**.

## Sesiones e importación

- **Barra lateral:** selecciona una sesión con un clic y conéctala con doble clic o Intro. Busca por nombre, equipo,
  IP, usuario, tipo, descripción o grupo. El menú contextual permite editar, duplicar, marcar como favorita,
  elegir la sesión de arranque y abrir sesiones o grupos en vista dividida.
- **Menú «+»:** abre «Conectar / Salto…», una terminal local, el editor de sesiones o las listas de equipos. Desde
  «Favoritas» o «Grupos» puedes abrir una sesión directamente. «Abrir todas» abre los terminales del grupo juntos.
- **Editor:** configura el destino, los saltos, el archivo de clave SSH, la credencial por nombre, las notas y el perfil
  de terminal de la sesión. Para consola serie, elige el puerto COM, la velocidad y la trama. «Enviar BREAK (consola
  serie)» está en el menú contextual de la pestaña.
- **Listas de equipos:** en Ajustes → Listas o con `Ctrl+Mayús+L`, guarda un salto SSH y sus destinos. «Abrir» inicia
  el lote y presenta las pestañas juntas cuando se abren varias. Las conexiones fallidas quedan excluidas de MultiExec.

En el pie de la barra lateral, pulsa **Importar** y elige **Elegir archivo…** o **Elegir carpeta…** para SecureCRT.
El selector de archivos de Windows admite estos formatos:

| Origen | Archivo |
|---|---|
| MobaXterm | `.mobaconf` con sesiones, `.mxtsessions` o `MobaXterm.ini` |
| SecureCRT | `.ini` o carpeta `Sessions` |
| PuTTY | `.reg` |
| electerm o exportación de NetDeck | `.json` |
| Inventario | `.csv` |
| OpenSSH | `ssh_config` o `config` |

Revisa la vista previa y marca las sesiones que quieras añadir. Las carpetas pasan a ser grupos y las contraseñas de
MobaXterm y de los demás formatos se omiten. Las sesiones se guardan en `%USERPROFILE%\.config\netdeck\ssh_config`.

## Terminal, registro y conexiones

- **Historial:** usa la rueda o la barra para recorrer la salida. Arrastra el ratón para seleccionar y mantén Alt
  para seleccionar un rectángulo. Copia con `Ctrl+C` si hay una selección, o con `Ctrl+Mayús+C`. En Ajustes →
  Terminal → Historial puedes cambiar el número de líneas guardadas y activar «Copiar al seleccionar».
- **Registro:** en Ajustes → Registro puedes activar la grabación a archivo y elegir su carpeta. Desde la marca ● REC
  de una pestaña, abre el registro, muestra su carpeta o para la grabación.
- **Pestañas y vista dividida:** arrastra una pestaña para reordenarla; suéltala fuera de la ventana para separarla.
  Con el puntero sobre la barra, usa la rueda para desplazarte horizontalmente cuando haya más pestañas que espacio.
  También puedes usar el menú de una pestaña para moverla a otra ventana.
  El botón de vista dividida ofrece dos paneles en horizontal o vertical, tres columnas, uno más dos, cuatro
  paneles o todas en cuadrícula. Arrastra los separadores para ajustar el tamaño. Los espacios guardan la disposición
  y las proporciones, y restauran las conexiones en pestañas nuevas.
- **MultiExec:** mientras está activo, envía la entrada a las sesiones SSH y Telnet incluidas. En vista dividida
  actúa sobre los paneles visibles. Excluye pestañas por separado desde su menú contextual o su cabecera.
- **SFTP:** abre el explorador desde la barra lateral o muestra el panel junto a una terminal SSH con `Ctrl+Mayús+B`.
  El explorador permite listar, transferir, gestionar y editar archivos UTF-8. Si cambia el archivo remoto durante
  la edición se conserva la copia local.
- **FTP:** acceso directo con usuario y contraseña, navegación, descarga y operaciones de carpeta. FTP transmite la
  contraseña sin cifrar. Para transferir por SSH usa SFTP.
- **Túneles SSH:** reenvíos locales, remotos o SOCKS. Se guardan en `%APPDATA%\Terminal NetDeck\tuneles.json`.
- **Pegado seguro, macros y botones de órdenes:** revisa el pegado, graba o reproduce secuencias y crea accesos
  para escribir órdenes, ejecutarlas con revisión o abrir sesiones. Los botones se guardan en `botones.txt`.

## Ajustes

| Sección | Qué puedes configurar |
|---|---|
| Contraseñas | Credenciales del Administrador de credenciales de Windows, opciones «Al conectar» y credencial «Por defecto» vinculada al usuario exacto |
| Temas | Galería, «Personalizar colores…», «Importar .tema…» y «Seguir a Windows (claro / oscuro)» con un tema para cada modo |
| Fuentes | Fuente de interfaz y del terminal, tamaño e interlineado |
| Resaltado | Origen de las reglas, vista previa y colores |
| Terminal | Historial, selección y copia, filtros CRT, LCD, fósforo y holograma, e intensidad |
| Registro | Grabación de sesiones, carpeta y acceso a los archivos de registro |
| Listas | Equipos, salto SSH, usuario y credencial para los lotes |

Para los detalles de seguridad de las contraseñas, consulta la [ADR de credenciales](decisiones/0004-credenciales-p9.md).
La comprobación de actualizaciones verifica el SHA-256 y la firma antes de ejecutar el instalador.

## Atajos de teclado

| Atajo | Qué hace |
|---|---|
| `Ctrl+Mayús+T` | Abre una terminal local nueva |
| `Ctrl+Mayús+N` | Abre una ventana nueva, con sus propias pestañas (⌘N en el Mac) |
| `Ctrl+Mayús+K` | Abre Conectar / Salto |
| `Ctrl+Mayús+W` | Cierra la pestaña activa |
| `Ctrl+Tab` · `Ctrl+Mayús+Tab` | Pestaña siguiente · anterior |
| `Ctrl+Alt+D` | Activa o cierra la vista dividida |
| `Ctrl+Alt+E` | Abre los espacios de trabajo |
| `Ctrl+Mayús+C` | Copia la selección del terminal |
| `Ctrl+Mayús+D` | Clona la pestaña activa |
| `Ctrl+Mayús+E` | Abre el gestor de sesiones |
| `Ctrl+Mayús+F` | Busca en el historial de la pestaña |
| `Ctrl+Alt+Mayús+F` | Busca en todos los registros de sesión (una IP, una MAC en cualquier formato, un texto…) |
| `Ctrl+Alt+F` | Activa o apaga el filtro de pantalla |
| `Ctrl+Mayús+H` | Activa o apaga el resaltado |
| `Ctrl+Mayús+L` | Abre las listas de equipos |
| `Ctrl+Mayús+B` | Muestra u oculta SFTP lateral cuando está disponible, o abre los botones de órdenes |
| `Ctrl+Mayús+M` | Activa o apaga MultiExec |
| `Ctrl+Mayús+P` | Abre Contraseñas |
| `Ctrl+Mayús+R` | Reconecta la pestaña activa |
| `Ctrl+Alt+Mayús+R` | Recarga el ssh_config |
| `Ctrl+Mayús+S` | Muestra u oculta la barra lateral de sesiones |
| `Ctrl+Mayús+V` | Abre el pegado seguro |
| `Ctrl+1` a `Ctrl+8` · `Ctrl+9` | Va a una pestaña por número o a la última |
| `Ctrl+Alt+M` | Abre el panel de macros |
| `Ctrl+Alt+T` | Abre los túneles SSH |
| `Ctrl+.` | Cancela automatizaciones y lotes en curso |
| `Ctrl+,` | Abre los ajustes |

## Limitaciones de esta versión

- Las contraseñas asistidas están disponibles en las pestañas SSH y en el explorador SFTP. Siguen pendientes en túneles.
- El panel de macros permite grabar y editar listas de órdenes. Los pasos avanzados se pueden reproducir y se conservan al editar el nombre. Los modos de contraseña y login de los botones siguen pendientes.
- En FTP, la subida y el renombrado están pendientes de un mecanismo que evite sobrescribir otro archivo.
- La interfaz de Windows usa los colores del tema sobre superficies opacas de WinUI. El desenfoque Liquid Glass es propio de macOS.

## Desinstalar

*Panel de control → Programas → Desinstalar un programa → Terminal NetDeck* (o *Configuración → Aplicaciones*). Tus sesiones, ajustes y túneles
quedan en tu carpeta de usuario y no se borran. Windows App Runtime 1.5 también se queda (lo usan otras apps). Se quita aparte, en
*Configuración → Aplicaciones*, si ya no lo necesitas.

## Compilar desde el código fuente

Desde la raíz del repositorio, usa el script de escritorio con el toolchain de Swift para Windows (6.4.x), Git y OpenSSH.
Antes de recompilar, cierra NetDeck y limpia los `*.objlib` de la carpeta de productos Debug del build. El script prepara
el plugin de SwiftTerm y el runtime. Sigue el [procedimiento de compilación y pruebas de Windows](../docs/agentes/windows.md#compilación-y-pruebas).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\scripts\desktop.ps1 -Demo
powershell -NoProfile -ExecutionPolicy Bypass -File windows\scripts\test.ps1 --no-parallel
```

Para compilar con la primera orden sin abrir la ventana, establece `$env:NETDECK_BUILD_ONLY = '1'` antes de ejecutarla.
El instalador (`windows/installer/`) se prepara con `preparar-instalador.ps1` y WiX 4. Consulta el [estado del paquete](ESTADO.md).

---

## Para quien desarrolla

Esta carpeta recoge también el estudio de viabilidad, cómo lo hacen otras apps (SecureCRT, Royal TS/TSX, Arc, Warp, Termius, Tabby), las
decisiones de arquitectura y el plan por fases. Está pensada para seguir el trabajo desde un PC con Windows y Claude Code (o Codex).

| Archivo | Qué es |
|---|---|
| [CLAUDE.md](CLAUDE.md) · [AGENTS.md](AGENTS.md) | Instrucciones para el agente que siga el trabajo en Windows (las dos iguales) |
| [PLAN.md](PLAN.md) | El plan por pasos (P0…P14), cada uno con contexto, tareas, comprobación y criterio de salida |
| [ESTADO.md](ESTADO.md) | Dónde se quedó el trabajo: cada sesión lo actualiza al terminar |
| [ESTUDIO.md](ESTUDIO.md) | Viabilidad: qué se aprovecha del núcleo, qué hay que reescribir y qué hacen otros, con fuentes |
| [decisiones/](decisiones/README.md) | Decisiones de arquitectura (ADR); la 0001, qué camino seguir, está aceptada (camino A, WinUI 3) |
| [scripts/](scripts/) | PowerShell para comprobar el entorno, probar el ssh de Windows (askpass, `ssh -G`, `-J`, sftp) y pasar los tests con un `NETDECK_HOME` temporal (`test.ps1`) |
| [resultados/](resultados/README.md) | Evidencia de compilación, pruebas del núcleo y comprobaciones con la demo |

### Empezar a desarrollar en Windows

1. Instala Git for Windows, el toolchain de Swift para Windows y Claude Code (detalle en [PLAN.md, paso P0](PLAN.md#p0--preparar-el-pc-con-windows)).
2. Clona el repositorio **sin conversión de fin de línea** (la rama `main` ya trae la versión de Windows):

   ```powershell
   git clone -c core.autocrlf=false https://github.com/Iljonis/Terminal-NetDeck.git
   cd Terminal-NetDeck
   ```

3. Comprueba el entorno:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/comprobar-entorno.ps1
   ```

4. Abre Claude Code en la raíz del repositorio (no dentro de `windows\`) y dile:

   > Continúa con el plan de Windows: lee windows/CLAUDE.md y windows/ESTADO.md y sigue por el siguiente paso.

La [referencia técnica de Windows](../docs/agentes/windows.md) explica qué partes se comparten con macOS.
