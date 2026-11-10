# Resultados de las pruebas en Windows

Aquí van las salidas de los pasos P0, P1 y P2 de [PLAN.md](../PLAN.md), **sin datos reales**: nada de IPs, nombres de
equipos, usuarios ni rutas personales (se sustituyen por `192.0.2.x`, `core-01`, `bastion`, `tu.usuario`,
`C:\Users\<usuario>`). Antes de cada commit, `bash tools/privacidad.sh` desde Git Bash.

| Archivo | Paso | Qué lleva |
|---|---|---|
| `entorno.md` | P0 | Salida de `comprobar-entorno.ps1` |
| `ssh-windows.md` | P1 | Tabla de `prueba-ssh.ps1` y `prueba-askpass.ps1`, y la prueba en Windows Terminal |
| `compilacion.md` | P2 | Errores al compilar `NetDeckCore`, por archivo y causa, antes y después de apartar lo de plataforma |
