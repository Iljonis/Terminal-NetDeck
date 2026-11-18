# El port de Windows (detalle)

Léelo antes de tocar algo de Windows. Las reglas de trabajo en Windows (Git Bash y PowerShell, comandos, antes de un commit, autor) están en
[`windows/CLAUDE.md`](../../windows/CLAUDE.md) y [`windows/AGENTS.md`](../../windows/AGENTS.md); el estado y el plan, en
[`windows/ESTADO.md`](../../windows/ESTADO.md) y [`windows/PLAN.md`](../../windows/PLAN.md). Esto sólo explica dónde está cada cosa.

## Dónde vive el código
- **Interfaz:** `windows/Desktop/` es un paquete SwiftPM propio (target `NetDeckWindows`, WinUI 3). Todo el código de ventanas, paneles y pestañas
  está en `windows/Desktop/Sources/NetDeckWindows/`. No usa nada de `Sources/TerminalNetDeck` (SwiftUI y AppKit no existen en Windows).
- **Núcleo:** `Sources/NetDeckCore` se comparte con macOS. Lo que sólo vale en Windows va tras `#if os(Windows)` o en un archivo que entero es de Windows
  (por ejemplo `Update/UpdateChecker.swift`); lo de macOS no cambia.
- **Instalador y paquete:** `windows/installer/` (WiX 4 y scripts) y `windows/Desktop/AppxManifest.xml` (Sparse Package).
- **Scripts:** `windows/scripts/` (`desktop.ps1` compila y abre la app, `test.ps1` pasa los tests del núcleo con un `NETDECK_HOME` temporal).
- **Decisiones:** `windows/decisiones/` (ADR).

## Ramas
Los pasos del plan van en ramas `windows/pN-<tema>` que salen de la anterior; el trabajo de Windows no va nunca directamente en `main`:

| Rama | Qué lleva |
|---|---|
| `windows/p8-terminal` | La interfaz (P8): barra lateral, terminal, editor de sesión, ajustes, atajos, SFTP, túneles, asistente |
| `windows/p9-seguridad` | P9: tests de importación y de prefijos peligrosos, entorno de ssh, ADR de credenciales |
| `windows/p10-paquete` | P10 (manifiesto, instalador, actualizador) y la documentación de P11 |

Cada rama parte de la anterior: `p9` sale de `p8` y `p10` sale de `p9`, con `p8` fusionada después (trae la ADR-0003); `p9` no lleva ese commit. La fusión a `main` la decide el autor tras la pasada de siempre en el Mac
(`./test.sh` y la demo): los cambios de `Sources/` no pueden romper macOS.
