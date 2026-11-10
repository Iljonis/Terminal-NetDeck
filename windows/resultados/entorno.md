# Resultado de comprobar-entorno.ps1 · P0

Fecha: 2026-11-10 · PC con Windows (AMD64)

```
Sistema
  ✓ Windows 11 (compilación 26300)
  ✓ Arquitectura: AMD64
  · Modo de desarrollador apagado (no es obligatorio)

Herramientas
  ✓ git version 2.49.0
  ✓ Git Bash (para tools/privacidad.sh)
  ✗ No está Swift (guía: https://www.swift.org/install/windows/)
  ✗ Visual Studio sin «Desarrollo para el escritorio con C++»
  ✓ SDK de Windows 10/11
  · No se encuentra «claude» en el PATH

OpenSSH de Windows (el que usaría NetDeck)
  ✓ ssh.exe
  ✓ sftp.exe
  ✓ ssh-keygen.exe
  ✓ Versión: OpenSSH_for_Windows_9.5p2, LibreSSL 3.8.2
  · El «ssh» del PATH no es el de Windows (es otro: Git, MSYS…). NetDeck usaría el de System32.
  ✓ Cliente Telnet

Repositorio
  ✓ Rama: propuesta/windows
  ✓ core.autocrlf = false
  ✓ Skills del proyecto copiadas a .claude\skills

2 cosa(s) por arreglar.
```

## Notas

- El git instalado es el de **DevKitPro/MSYS2** (`c:\devkitPro\msys2\usr\bin\git.exe`), no Git for Windows.
  El script lo detecta bien (v2.49.0) y Git Bash también está disponible vía `%ProgramFiles%\Git\bin\bash.exe`.
  `cygpath.exe` está en `c:\devkitPro\msys2\usr\bin\` y se usa en el script para convertir rutas POSIX.
- Claude Code no aparece en el PATH del proceso PowerShell iniciado por el script; sí está disponible de forma nativa.

## Pendiente para completar P0

1. **Swift 6.2+**: instalar el toolchain desde <https://www.swift.org/install/windows/> (también requiere Visual Studio).
2. **Visual Studio 2022 Build Tools** con «Desarrollo para el escritorio con C++» y el SDK de Windows 11:
   `winget install --id Microsoft.VisualStudio.2022.BuildTools -e`
   Después, en el instalador, marcar: «Desarrollo para el escritorio con C++» + «SDK de Windows 11».
