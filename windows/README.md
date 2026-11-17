# Terminal NetDeck para Windows

Gestor de sesiones **SSH, SFTP y túneles** con terminal, para Windows. Es la versión de Windows de [Terminal NetDeck](../README.md): lee y
escribe las sesiones en el mismo formato de `ssh_config` que la de macOS.

> **Estado: versión 0.9.0, en preparación.** Todavía **no hay una release pública** de Windows ni un instalador firmado (ver
> [ESTADO.md](ESTADO.md)). Esta guía describe cómo será la instalación y lo que ya funciona al compilar desde el código fuente.

## Requisitos

- **Windows 10 versión 2004 (10.0.19041) o superior**, 64 bits (x64). Windows 11 funciona igual y usa el fondo Mica.
- **Cliente OpenSSH** (`ssh.exe`), que Windows trae de serie en *Configuración → Aplicaciones → Características opcionales*. Las sesiones SSH, el
  explorador SFTP y los túneles lo usan.
- **Windows App Runtime 1.5 (x64)** (el Framework y su DDLM): la interfaz lo necesita. **El instalador no lo incluye, pero lo comprueba**: si falta, se
  detiene antes de copiar nada y muestra un aviso con el enlace de descarga
  (<https://aka.ms/windowsappsdk/1.5/latest/windowsappruntimeinstall-x64.exe>). Instálalo y vuelve a ejecutar el instalador. Si la comprobación
  fallara en tu equipo, se salta con `SKIP_WINAPPRUNTIME_CHECK=1` al instalar por línea de órdenes.

## Instalación

1. Descarga `Terminal-NetDeck-<versión>.msi` de la [página de Releases](https://github.com/Iljonis/Terminal-NetDeck/releases).
2. Ejecútalo y acepta el aviso de administrador (UAC): se instala en `C:\Program Files\Terminal NetDeck`.
3. Abre **Terminal NetDeck** desde el menú Inicio. El acceso del escritorio es opcional (`ADDLOCAL=Principal,AccesoEscritorio` al instalar por línea de órdenes).

Mientras no haya firma, Windows (SmartScreen) puede avisar de que el instalador es de un editor desconocido.

## Primera vez

Si no tienes sesiones guardadas, **el asistente aparece solo**: una bienvenida, un formulario para tu primera sesión (nombre y equipo; usuario
y puerto, opcionales) y un «todo listo». Puedes saltártelo con «Omitir» y añadir sesiones luego con **+ Nueva sesión**.

## Funciones principales

- **Barra lateral de sesiones**, agrupadas, leídas de `%USERPROFILE%\.config\netdeck\ssh_config` (o de `~/.ssh/config` si no existe). **+ Nueva sesión** y el
  lápiz ✎ abren el editor: nombre, grupo, equipo, usuario, puerto, tipo (SSH, Telnet, SFTP, FTP, serie o local) y descripción.
- **Terminal con pestañas**: una shell local o una sesión SSH, sobre ConPTY y `ssh.exe`. «Conectar» abre un destino escrito al momento (`usuario@equipo`).
- **Vista dividida** (`Ctrl+Mayús+D`): con dos pestañas abiertas, muestra ambas a la vez. Haz clic en un panel o elige su pestaña para enviarle el teclado. Ajustes permite colocar los paneles en paralelo o uno encima del otro y cambiar el interlineado.
- **Espacios de trabajo** (`Ctrl+Mayús+E`): guardan las pestañas abiertas y la disposición de dos paneles. Al restaurar se abren pestañas nuevas y se conservan las que ya estaban abiertas. Se restauran terminales locales y sesiones SSH.
- **Buscar en el historial** (`Ctrl+F`): encuentra texto en el búfer disponible de la pestaña, aunque la línea ya no esté visible.
- **Contraseñas SSH**: las pestañas pueden usar una contraseña de esa cuenta guardada en el Administrador de credenciales de Windows.
  Si falta o falla, puedes escribirla en la pestaña sin eco y elegir si se guarda. [ADR-0004](decisiones/0004-credenciales-p9.md).
- **Explorador SFTP** (el botón 📂 de cada sesión): lista, entra en carpetas, descarga con doble clic a *Descargas* y sube un archivo escribiendo su ruta.
  Permite renombrar, borrar, crear carpetas y, desde el menú contextual, mover, calcular MD5 y editar archivos UTF-8. Si la versión remota cambia durante la edición, conserva la copia local.
- **Explorador FTP**: acceso directo con usuario y contraseña, navegación, descarga y operaciones de carpeta. El panel avisa de que FTP transmite la contraseña sin cifrar.
- **Túneles SSH** (botón «Túneles», `Ctrl+T`): reenvío local, remoto o SOCKS; se inician y se paran uno a uno y se guardan en `%APPDATA%\Terminal NetDeck\tuneles.json`.
- **Pegado seguro** (`Ctrl+Mayús+V`): revisa las líneas y envíalas una a una en SSH o Telnet. Se detiene ante errores, paginadores o solicitudes de contraseña.
- **Macros** (`Ctrl+M`): guarda una lista de órdenes, una por línea, y reprodúcela en la pestaña SSH o Telnet activa desde su prompt.
  Pide confirmación para órdenes peligrosas y se detiene al detectar un error, un paginador o una petición de contraseña. Esc o «Detener envío» interrumpen la reproducción.
- **MultiExec**: un mismo comando a todas las pestañas SSH y Telnet abiertas.
- **Ajustes** (`Ctrl+,`): fuente (Consolas, Courier New, Cascadia Code o Cascadia Mono), tamaño de letra, tema de la ventana (sistema con Mica, claro u oscuro) y **colores del terminal**: los 85 temas de NetDeck (fondo, texto y los 16 colores ANSI; «(Predeterminado)» deja los del sistema).
- **Actualizaciones**: «Buscar actualizaciones» en Ajustes consulta la última release de GitHub. Nada se comprueba ni se instala sin tu clic y el instalador
  se descarga solo de `github.com`, con comprobación del sha256 y de la firma antes de lanzarlo.

## Atajos de teclado

| Atajo | Qué hace |
|---|---|
| `Ctrl+N` | Abre una terminal local nueva |
| `Ctrl+Mayús+N` | Abre el editor de una sesión nueva |
| `Ctrl+W` | Cierra la pestaña activa |
| `Ctrl+Tab` · `Ctrl+Mayús+Tab` | Pestaña siguiente · anterior |
| `Ctrl+Mayús+D` | Activa o cierra la vista dividida |
| `Ctrl+Mayús+E` | Abre los espacios de trabajo |
| `Ctrl+F` | Busca en el historial de la pestaña |
| `Ctrl+M` | Abre el panel de macros |
| `Ctrl+T` | Abre los túneles SSH |
| `Ctrl+,` | Abre los ajustes |

`Ctrl+N` y `Ctrl+W` los coge la aplicación y **no llegan a la shell** (en ella son «historial siguiente» y «borrar palabra»).

## Limitaciones de esta versión

- Las contraseñas asistidas están disponibles en las pestañas SSH. El explorador SFTP y los túneles quedan fuera de este flujo.
- El panel de macros permite crear listas de órdenes y reproducir macros del formato de NetDeck. Quedan pendientes la grabación y la edición de macros en Windows.
- En FTP, la subida y el renombrado están pendientes de un mecanismo que evite sobrescribir otro archivo.
- La terminal pinta texto: con un tema de colores, cada trozo con su color de texto, pero sin fondo por celda, negrita ni subrayado, y sin colores si no eliges tema.
- Los 85 temas de la versión de macOS sólo se aplican a los colores del terminal; la interfaz sigue siendo Mica, claro u oscuro.

## Desinstalar

*Panel de control → Programas → Desinstalar un programa → Terminal NetDeck* (o *Configuración → Aplicaciones*). Tus sesiones, ajustes y túneles
quedan en tu carpeta de usuario y no se borran.

## Compilar desde el código fuente

Hace falta el toolchain de Swift para Windows (6.4.x), Git y OpenSSH. El detalle por pasos está en [PLAN.md](PLAN.md) (P0 prepara el PC):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/desktop.ps1 -Demo   # compila y abre la app con datos de ejemplo
powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/test.ps1            # los tests del núcleo (con un NETDECK_HOME temporal)
```

El instalador (`windows/installer/`) se prepara con `preparar-instalador.ps1` y se compila con WiX 4; ver [ESTADO.md](ESTADO.md).

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
| [decisiones/](decisiones/README.md) | Decisiones de arquitectura (ADR); la 0001, qué camino seguir, está «propuesta» |
| [scripts/](scripts/) | PowerShell para comprobar el entorno, probar el ssh de Windows (askpass, `ssh -G`, `-J`, sftp) y pasar los tests con un `NETDECK_HOME` temporal (`test.ps1`) |
| [ci/windows-nucleo.yml](ci/windows-nucleo.yml) | Borrador de GitHub Actions para compilar el núcleo en Windows (sin activar) |
| [resultados/](resultados/) | Lo que salga de las pruebas en Windows (lo rellenan los pasos P1 y P2) |

### Empezar a desarrollar en Windows

1. Instala Git for Windows, el toolchain de Swift para Windows y Claude Code (detalle en [PLAN.md, paso P0](PLAN.md#p0--preparar-el-pc-con-windows)).
2. Clona el repositorio **sin conversión de fin de línea** y cámbiate a la rama de la propuesta:

   ```powershell
   git clone -c core.autocrlf=false https://github.com/Iljonis/Terminal-NetDeck.git
   cd Terminal-NetDeck
   git switch propuesta/windows
   ```

3. Comprueba el entorno:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/comprobar-entorno.ps1
   ```

4. Abre Claude Code en la raíz del repositorio (no dentro de `windows\`) y dile:

   > Continúa con el plan de Windows: lee windows/CLAUDE.md y windows/ESTADO.md y sigue por el siguiente paso.

Nada de esta carpeta cambia la app de macOS: el código de `Sources/` sigue igual hasta el paso P4.
