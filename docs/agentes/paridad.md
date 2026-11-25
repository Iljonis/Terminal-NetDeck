# Paridad Mac ↔ Windows (detalle)

Léelo antes de añadir o cambiar una función visible. El objetivo del autor: **la app de Windows es la misma que la de
Mac**. No lo garantiza la memoria de nadie; lo garantizan estas reglas y `tools/comprobar_paridad.sh` (dentro de
`./test.sh`).

## Reglas
1. **Una lógica, un sitio.** Todo lo que no sea pintar (buscar, validar, decidir, formatear, leer y escribir archivos,
   reglas de pestañas, de contraseñas, de pegado) vive en `Sources/NetDeckCore`, sin AppKit, SwiftUI ni WinUI, con tests
   que corren en macOS. `Sources/TerminalNetDeck` y `windows/Desktop` sólo la llaman y la pintan. Copiar una función de
   una interfaz a la otra está prohibido: `tools/comprobar_paridad.sh` falla si dos funciones de 6 o más líneas tienen el
   mismo cuerpo. Una excepción justificada va en `tools/paridad_permitidos.txt` (nombre y motivo).
2. **Misma entrega, o anotado.** Una función nueva o un cambio visible llega a las dos apps en el mismo PR. Si una no
   puede (no se puede compilar en el equipo del autor, o depende de la plataforma), el PR deja una fila en la matriz de
   abajo con quién la hace y qué falta. Nunca queda sin anotar.
3. **Mismo lenguaje.** Mismos nombres de ajustes, modos y valores por defecto; mismos textos (`L("…")` con una sola
   entrada en `Ingles.swift`); atajos equivalentes (⌘ en Mac ↔ Ctrl o Ctrl+Mayús en Windows) y mismo orden en menús y
   paneles. Las dos apps nombran igual lo que hace lo mismo.
4. **Un arreglo, dos apps.** Al arreglar un fallo en una app, se mira la otra: se arregla o se anota en la matriz.
   Un arreglo de lógica va al núcleo y arregla las dos a la vez.
5. **Las diferencias, con motivo.** Lo que de verdad cambia por la plataforma (ControlMaster no existe en el OpenSSH de
   Windows, Liquid Glass es de macOS, la firma Authenticode frente a `codesign`…) se escribe en la sección «Distinto a
   propósito» con su porqué. Lo demás es una deuda, no una diferencia.
6. **Quien toca el núcleo, prueba el Mac.** Un cambio en `Sources/NetDeckCore` pasa `./test.sh` y la demo en el Mac
   (`tools/verificar_demo.sh`) y, para el código de Windows, `windows/scripts/test.ps1 --no-parallel`. Lo que sólo se
   compila en Windows se marca `// no verificado en Windows` hasta que se pruebe allí.
7. **El PR lo dice.** La plantilla de PR pregunta por la paridad; contéstala.

## Matriz (estado a 2026-11-25, revisada contra el código)
✅ igual · 🟡 parcial · ❌ falta en Windows · ⚙️ lógica ya en el núcleo, falta sólo la interfaz de Windows.

| Función | Estado | Nota |
|---|---|---|
| Buscar en los registros de las sesiones | 🟡→✅ | Un único motor en el núcleo (`LogSearch`); las dos interfaces lo pintan |
| Barra superior configurable (Ajustes → General → «Barra superior») | 🟡→✅ | Catálogo, ids y guardado únicos en `ToolbarLayout`; clave `ndToolbarOcultos`. Un solo botón «Explorador SFTP» (el lateral de la pestaña ssh; editar se hace desde él); los ids antiguos `EditarRemoto` y `PanelSFTP` migran a `ExploradorSFTP`. Windows sin compilar; `PanelEdicionRemota` queda sin botón |
| Foco en la pestaña nueva (botón +, ⌘T, favoritas, conexión rápida) | 🟡→✅ | Un único camino «abrir ⇒ seleccionar ⇒ enfocar» |
| Pestañas: arrastre, mover entre ventanas, devolver | 🟡 | Windows reordena y separa; falta mover a una ventana abierta |
| Reabrir pestañas y ventanas, posición de ventana | ❌ | `OpenWindows` y `WindowPlacement` ya en el núcleo ⚙️ |
| Aviso al cerrar con conexiones abiertas | ❌ | Regla pura por extraer (`CloseGuard`) |
| Menú contextual del terminal, selección por palabra o línea, reporte de ratón | ❌ | Selección y decisión de clic, por extraer al núcleo |
| Suavizado de fuente, efecto CRT | ❌ | Ajustes |
| Gestión de grupos (renombrar, quitar, contraseña de grupo, reordenar) | ❌ | `SessionFile.move` ya en el núcleo ⚙️; el resto, por extraer |
| Exportar sesiones JSON/CSV | ⚙️ | `SessionExport` |
| Importar y exportar `botones.txt`, categorías | ⚙️ | `ButtonFile.merge/renameGroup/moveGroup` |
| Macros: duplicar, subir/bajar, MultiExec | ⚙️ | Operaciones puras por mover a `MacroLibrary` |
| Túneles: saltos y duplicar | ⚙️ | `Tunnel.jump` existe; falta la interfaz |
| SFTP/FTP: selección múltiple, arrastrar y soltar, cola, filtro, ocultos, «Enviar a…», `verifyTransfers` | ❌ | Modelo por extraer (`RemoteListing`, `TransferCenter`) |
| Editor de resaltado con vista previa | 🟡 | Windows edita el YAML; validación y recuento por extraer |
| Temas: 51 y importar `.tema` | ✅ | Falta exportar `.tema` ⚙️ |
| Asistente de primer arranque (7 pasos) | 🟡 | Falta la vista previa al pasar el ratón |
| Credenciales, listas, vista dividida, MultiExec en vivo | ✅ | |
| Accesibilidad | 🟡 | Windows no detecta el alto contraste del sistema |
| Jump List de la barra de tareas | ❌ | Equivalente al menú del Dock |

## Distinto a propósito
- Reutilizar la conexión al salto (`ControlMaster`/`JumpSharing`): el OpenSSH de Windows no lo admite.
- Firma y actualizaciones: `codesign`/`.dmg` frente a Authenticode/MSI.
- Credenciales: Llavero (`/usr/bin/security`) frente al Administrador de credenciales.
- «Nueva ventana» en Windows lanza otro proceso (deuda: no comparten estado; ver la matriz).
