# ADR-0001: Qué camino seguir para la versión de Windows

**Fecha:** 2026-11-10
**Estado:** aceptada · 2026-11-10 (con datos de P2; P1 pendiente, ver sección «Datos»)
**Deciden:** el autor (Jonay), con el estudio de [ESTUDIO.md](../ESTUDIO.md)

## Contexto

Terminal NetDeck es una app nativa de macOS: el núcleo `NetDeckCore` (Swift, sin interfaz, 705 tests) y la app
`TerminalNetDeck` (SwiftUI + AppKit + la vista de SwiftTerm). Lanza el OpenSSH del sistema y guarda las sesiones en
ssh_config. En Windows no existen SwiftUI ni AppKit, SwiftTerm no tiene vista, y el OpenSSH de Windows no tiene
ControlMaster. Hay que elegir con qué se hace la interfaz y la terminal, y cuánto núcleo se comparte con macOS.

## Decisión (propuesta)

**Camino A** si el paso P2 muestra que el núcleo compila en Windows con cambios acotados. Umbral: con los stubs de
plataforma de P2 puestos, **ningún error** en los archivos «puros» (resaltado, `SafePaster`, `SessionFile`,
`SessionImporter`, `SFTPPacket`, temas) y **menos de 50** errores en total que no sean de los archivos de plataforma de
[ESTUDIO.md](../ESTUDIO.md#qué-hay-que-reescribir-en-el-núcleo). Si no, **camino B**.
En los dos casos se sigue usando el OpenSSH del sistema; un SSH propio queda fuera de la primera versión.

## Alternativas

### A: Swift en Windows, interfaz WinUI 3 con swift-winrt (como Arc)
- **A favor:** el mismo `NetDeckCore` en los dos sistemas, con sus tests; un solo lenguaje; aspecto nativo (Mica).
- **En contra:** las herramientas de Swift para la interfaz de Windows están verdes; hay que escribir la vista de
  terminal; swift-winrt lo mantenía la empresa de Arc, que ahora se centra en Dia (comprobar su actividad en GitHub).
- **Riesgo y mitigación:** si swift-winrt se abandona, la interfaz se puede rehacer sobre la API en C del núcleo
  (camino C) sin tirar el núcleo.

### B: App aparte con Tauri + xterm.js (Rust), porta el núcleo con los tests como especificación
- **A favor:** xterm.js y ConPTY ya están resueltos; Tauri vale también para Linux; mucho más ligero que Electron.
- **En contra:** dos bases de código (Swift y Rust/TypeScript) que hay que mantener iguales; la interfaz no es nativa.
- **Por qué no la primera:** duplicar el núcleo es justo lo que el modelo de Royal TS/TSX y Arc evita.

### C: Núcleo en Swift como DLL con una API en C, interfaz en .NET (WinUI 3 o WPF)
- **A favor:** interfaz de Windows con herramientas maduras; el núcleo se comparte.
- **En contra:** cada función nueva necesita su puente C ↔ C#; dos lenguajes y dos depuradores.
- **Por qué no la primera:** el coste del puente se paga en cada cambio. Queda como salida si A se atasca en la interfaz.

### D: Electron (como Termius, Tabby o electerm)
- **Por qué no:** pesa mucho y no es nativa, que es lo que distingue a NetDeck.

### E: SSH propio (como SecureCRT)
- **Por qué no ahora:** son meses de trabajo y romperían la regla de que las sesiones sean ssh_config validado por
  `ssh -G`. Se reconsidera si P1 demuestra que el askpass no funciona en Windows.

## Datos (P2 completado; P1 pendiente de equipo de laboratorio)

| Pregunta | Resultado |
|---|---|
| ¿`ssh.exe` respeta `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force`, con consola, sin consola y en ConPTY? | pendiente (P1) |
| ¿Llega el askpass al ssh hijo de un salto `-J`? | pendiente (P1) |
| ¿Funciona `ssh -G` con `Include` absoluto, con `~/` y relativo? ¿Comprueba permisos? | pendiente (P1) |
| ¿Hay ControlMaster? | pendiente (P1; se espera que no) |
| ¿Funciona `ssh -s … sftp`? | pendiente (P1) |
| Errores al compilar `NetDeckCore` **sin cambios** | Compilation para en el primer `import Darwin` (`ChildProcess.swift`). |
| Errores al compilar `NetDeckCore` **con `#if !os(Windows)` en los 12 archivos de plataforma** | 11 errores en 6 archivos de cascada; **0 errores en los archivos puros** (resaltado, `SafePaster`, `SessionFile`, `SFTPPacket`, temas). Total < 50. **Umbral del camino A cumplido.** Ver `windows/resultados/compilacion.md`. |
| Aviso de Foundation en Windows | `FileManager.replaceItemAt` no implementado (usado en la escritura atómica de `SafeFile`). A resolver en P4 con una alternativa Windows. |
| ¿Compila el motor de SwiftTerm sin vista? | pendiente (P2 tarea 4, no ejecutada por falta de equipo para validar) |

### Decisión tomada con datos de P2

El umbral del camino A está cumplido: 0 errores en archivos puros y solo 11 errores de cascada (< 50).
**Se elige el camino A: Swift en Windows con interfaz WinUI 3.**

Los datos de P1 (askpass, ssh -G, ControlMaster) no cambian la elección A/B; afectan únicamente a la
implementación de credenciales en P4e y a la nota sobre ControlMaster en la sección «Consecuencias».
Cuando P1 esté disponible, actualizar esta tabla y la nota de ControlMaster.

## Consecuencias

### Positivas
- Con A, toda mejora del núcleo (resaltado, pegado seguro, credenciales, ssh_config) llega a los dos sistemas a la vez.
- Las reglas de seguridad se escriben una vez y los tests las comprueban en los dos.

### Negativas
- En Windows no se comparte la conexión al bastión mientras no haya ControlMaster ni un SSH propio.
- La interfaz se hace dos veces (SwiftUI y la de Windows) y cada función visible hay que llevarla a mano.
- La CI dobla: macOS y Windows.

### Riesgos
- **Askpass:** si no funciona en Windows, la contraseña automática de las sesiones tiene que ir por la propia pestaña
  (como el autopass ante el prompt) → se mide en P1 antes de decidir.
- **Firma:** sin un certificado de firma de código, la instalación asusta → decisión y coste en P10.
- **Askpass empaquetado:** con MSIX puede que ssh.exe no pueda lanzar el ejecutable de la app por su ruta → valorar un
  `netdeck-askpass.exe` de consola aparte (P4e) y comprobarlo en P10.
