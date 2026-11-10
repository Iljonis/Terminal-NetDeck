# ADR-0001: Qué camino seguir para la versión de Windows

**Fecha:** 2026-11-10
**Estado:** propuesta
**Deciden:** el autor (Jonay), con el estudio de [ESTUDIO.md](../ESTUDIO.md)

## Contexto

Terminal NetDeck es una app nativa de macOS: el núcleo `NetDeckCore` (Swift, sin interfaz, 705 tests) y la app
`TerminalNetDeck` (SwiftUI + AppKit + la vista de SwiftTerm). Lanza el OpenSSH del sistema y guarda las sesiones en
ssh_config. En Windows no existen SwiftUI ni AppKit, SwiftTerm no tiene vista, y el OpenSSH de Windows no tiene
ControlMaster. Hay que elegir con qué se hace la interfaz y la terminal, y cuánto núcleo se comparte con macOS.

## Decisión (propuesta)

**Camino A** si el paso P2 muestra que el núcleo compila en Windows con cambios acotados (que los errores salgan sólo
de los archivos de plataforma de [ESTUDIO.md](../ESTUDIO.md#qué-hay-que-reescribir-en-el-núcleo)). Si no, **camino B**.
En los dos casos se sigue usando el OpenSSH del sistema; un SSH propio queda fuera de la primera versión.

## Alternativas

### A: Swift en Windows, interfaz WinUI 3 con swift-winrt (como Arc)
- **A favor:** el mismo `NetDeckCore` en los dos sistemas, con sus tests; un solo lenguaje; aspecto nativo (Mica).
- **En contra:** las herramientas de Swift para la interfaz de Windows están verdes; hay que escribir la vista de
  terminal; swift-winrt depende de una empresa que ya sólo mantiene Arc.
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

## Datos (se rellena en P1 y P2)

| Pregunta | Resultado |
|---|---|
| ¿`ssh.exe` respeta `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force`, sin terminal y con ConPTY? | pendiente (P1) |
| ¿Funciona `ssh -G` con `Include`? | pendiente (P1) |
| ¿Hay ControlMaster? | pendiente (P1; se espera que no) |
| ¿Funciona `ssh -s … sftp`? | pendiente (P1) |
| Errores al compilar `NetDeckCore` sin cambios / con los archivos de plataforma fuera | pendiente (P2) |
| ¿Compila el motor de SwiftTerm sin vista? | pendiente (P2) |

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
