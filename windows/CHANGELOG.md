# Changelog (Windows)

Historial de cambios de la versión de Windows de Terminal NetDeck. Sigue el formato de
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). El de la versión de macOS está en el [CHANGELOG de la raíz](../CHANGELOG.md).

## 0.9.0 (próxima versión)

Todavía no hay release pública. La versión 0.9.0 es la de `AppxManifest.xml`, `NetDeckWindows.wxs` y `UpdateChecker.currentVersion`; hay que
decidir si la de Windows sigue el 1.0.0 de macOS antes de publicarla (ver [ESTADO.md](ESTADO.md)).

### Añadido

- Terminal SSH con ConPTY y múltiples pestañas
- Explorador SFTP (listar, descargar, subir)
- Túneles SSH (crear, iniciar, parar)
- Editor de sesiones (nombre, grupo, equipo, usuario, puerto, tipo)
- Ajustes (fuente, tamaño, tema: Mica / Claro / Oscuro)
- Pegado seguro con confirmación
- MultiExec: escribir en todas las pestañas a la vez
- Asistente de primer arranque
- Actualizador: busca nuevas versiones en GitHub y comprueba el sha256 y la firma antes de instalar
- Almacén de credenciales Windows (Administrador de credenciales)
- Atajos de teclado: `Ctrl+N`, `Ctrl+W`, `Ctrl+Tab`, `Ctrl+T` y `Ctrl+,`
- Instalador `.msi` (WiX 4) y Sparse Package; compila, pero todavía no se ha probado instalado ni está firmado
- El instalador comprueba que está el Windows App Runtime 1.5 y, si falta, se detiene con el enlace para instalarlo (no lo incluye)

### Seguridad

- La importación de sesiones sigue quitando las opciones que ejecutan órdenes, también con rutas de Windows
- `ssh.exe` ya no hereda `SSH_ASKPASS`, `GIT_SSH` ni variables parecidas del proceso padre
- El actualizador sólo acepta enlaces https de `github.com` del repositorio y rechaza instaladores sin firma válida

### Notas

- Primera versión pública de Windows. La versión macOS es 1.0.0.
- Limitaciones conocidas: la contraseña por teclado en las conexiones de la app necesita el askpass de Windows (de momento, claves y agente); FTP aún
  no está disponible; la terminal pinta texto plano; los 85 temas de macOS no están.
