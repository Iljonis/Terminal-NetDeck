# Plan: Completar el puerto Windows de Terminal NetDeck (P15–P17)

> Plan histórico de Claude Code y Codex. La numeración y las órdenes de este borrador reflejan su momento.
> Para compilar y comprobar la versión actual usa la [guía de Windows](../../docs/agentes/windows.md#compilación-y-pruebas).
> La comprobación de ventana usa clics y capturas. FindFirst y FindAll pueden colgar WinUI.

**Rama**: `windows/p14-escritorio`
**Worktree**: `raíz del repositorio`
**Fecha del plan**: 2026-11-17
**Estado al 2026-11-18**: P15-A, P15-B, P16 y P17 integrados.

- P15-A y P15-B: `1ad4317`. P17: `36a493c`. P16: `6661d2f`.
- Compilación WinUI, arranque de demo, 551 tests secuenciales y privacidad del contenido versionable en verde. Pasaron también 9 tests específicos del actualizador.
- Pendiente: validación con lector de pantalla y prueba interactiva de los atajos. El inspector UIA reprodujo una excepción de WinUI presente ya antes de P17. Ver `windows/ESTADO.md`.

---

## 🚀 División de tareas: Claude Code vs Codex

| Sesión | Herramienta | Por qué |
|---|---|---|
| **P15-A** F-keys + hotkeys | **Codex** | Inserción quirúrgica en 1 función, escapes ANSI bien definidos, sin lógica de seguridad |
| **P15-B** Panel credenciales | **Claude Code** | Archivo nuevo con lógica de seguridad (CredWriteW/CredDeleteW), requiere `/ecc:security-review` |
| **P16** Sidebar búsqueda/★/↻ | **Claude Code** | Refactor cross-file, razonamiento sobre SessionLists API, requiere `/ecc:swift-reviewer` |
| **P17** Auto-update + UIA | **Codex** | Cambio pequeño y bien especificado en 1 archivo, sin dependencias complejas |

P15-A (Codex) y P15-B (Claude) pueden lanzarse **en paralelo** al mismo tiempo.

---

## ▶ CODEX — P15-A: F-keys + hotkeys de botón

**Cuándo**: lanzar primero, en paralelo con P15-B
**Modelo Codex**: `o4-mini` (razonamiento suficiente para escapes ANSI, coste bajo)
**Archivo único**: `windows/Desktop/Sources/NetDeckWindows/NetDeckWindows.swift`

```
Project: Terminal NetDeck – Windows port (WinUI 3 / Swift)
Repo/worktree: raíz del repositorio
Branch: windows/p14-escritorio
Plan file: .claude/plans/windows-p15-p17.plan.md  ← read this first

TASK: Implement section "Sesión P15-A — F-keys + hotkeys de botón" from the plan.

ONLY file to touch: windows/Desktop/Sources/NetDeckWindows/NetDeckWindows.swift

Change 1 — Add F1–F12 cases to keySequence(_ key:tab:).
Find: "case 46: return" and insert BEFORE "default: return nil":

    case 112...123:
        let n = Int(key) - 111
        let shift = GetKeyState(Int32(VK_SHIFT)) < 0
        let ctrl  = GetKeyState(Int32(VK_CONTROL)) < 0
        let alt   = GetKeyState(Int32(VK_MENU)) < 0
        let mod   = (shift ? 1 : 0) | (alt ? 2 : 0) | (ctrl ? 4 : 0)
        let ss3   = ["P","Q","R","S"]
        let csi   = [11,12,13,14,15,17,18,19,20,21,23,24]
        if mod == 0 {
            return n <= 4 ? "\u{1b}O\(ss3[n-1])" : "\u{1b}[\(csi[n-1])~"
        }
        return n <= 4 ? "\u{1b}[1;\(mod+1)\(ss3[n-1])" : "\u{1b}[\(csi[n-1]);\(mod+1)~"

Change 2 — Dispatch button hotkeys. In BOTH surface.keyDown handlers (search for
"self.recordKeys(bytes, tab: tab)" — there are 2 occurrences), insert BEFORE that line:

        if let seq = Array(bytes.utf8) as [UInt8]?,
           let k = FunctionKey.name(seq),
           let btn = self.archivoBotones.button(forKey: k) {
            self.useCommandButton(btn)
            args.handled = true
            return
        }

CONSTRAINTS:
- No BOM on Swift files (they are already saved UTF-8 without BOM — do not change encoding).
- No new UI strings needed for this change.
- Run: swift build --target NetDeckWindows — must compile with 0 errors.
- Run: bash tools/privacidad.sh — must output "sin datos personales".
- Commit message format:
    windows/p15-a: F-keys F1–F12 y hotkeys de botón en el terminal

    keySequence() añade casos 112–123 con modificadores Shift/Ctrl/Alt.
    Los dos handlers keyDown del terminal comprueban FunctionKey.name antes
    de escribir, despachando el botón asignado si coincide el atajo.

- Add entry at TOP of windows/ESTADO.md describing what was done.
```

---

## ▶ CLAUDE CODE — P15-B: Panel de gestión de credenciales

**Cuándo**: lanzar en paralelo con P15-A
**Modelo**: `claude-sonnet-5-5`
**Skills obligatorias**:
- `/ecc:security-review` sobre `PanelLlavero.swift` antes del commit
- `/code-review medium` sobre el diff completo antes del commit
- `/ecc:swift-build-resolver` si hay errores de compilación

```
Eres un agente de implementación para el proyecto Terminal NetDeck (puerto Windows, WinUI 3 / Swift).

PLAN: lee .claude/plans/windows-p15-p17.plan.md
TAREA: implementa únicamente la sección "Sesión P15-B — Panel de gestión de credenciales"

Worktree: raíz del repositorio
Rama: windows/p14-escritorio

SKILLS que debes invocar (en este orden):
1. Al empezar: /ecc:swift-reviewer — para entender los patrones del proyecto antes de escribir.
2. Antes de guardar PanelLlavero.swift: /ecc:security-review — revisar el manejo de credenciales.
3. Antes del commit: /code-review medium — revisar el diff completo.
4. Si falla la compilación: /ecc:swift-build-resolver

Instrucciones obligatorias:
- GateGuard hook activo: antes de cada Write/Edit presenta
  (1) qué archivos importan el que vas a tocar,
  (2) confirma que no hay entrada duplicada,
  (3) estructura de datos afectada,
  (4) instrucción verbatim del usuario.
- NO BOM: archivos Swift nuevos con
  PowerShell: [System.IO.File]::WriteAllText(path, content, (New-Object System.Text.UTF8Encoding $false))
- Toda cadena UI en L("…"); nuevas entradas en Ingles.swift antes del ] final.
- SEGURIDAD: la contraseña NUNCA en texto claro — usa PasswordBox, no TextBox.
  No loggear ni mostrar el secreto en ningún campo ni en status.text.
- bash tools/privacidad.sh antes del commit.
- Commit termina con: Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
- Entrada nueva al principio de windows/ESTADO.md.

Al terminar:
1. swift build --target NetDeckWindows — debe compilar sin errores.
2. swift test --filter IdiomaTests — debe pasar (verifica las nuevas cadenas L()).
3. bash tools/privacidad.sh — debe mostrar "sin datos personales".
4. Commit con el mensaje del plan.
```

---

## ▶ CLAUDE CODE — P16: Sidebar búsqueda + favoritas + recientes

**Cuándo**: después de que P15-A y P15-B estén en verde
**Modelo**: `claude-sonnet-5-5`
**Skills obligatorias**:
- `/ecc:swift-reviewer` al arrancar — para leer los patrones de buildSidebar y SessionLists
- `/code-review medium` antes del commit
- `/ecc:swift-build-resolver` si hay errores de compilación

```
Eres un agente de implementación para el proyecto Terminal NetDeck (puerto Windows, WinUI 3 / Swift).

PLAN: lee .claude/plans/windows-p15-p17.plan.md
TAREA: implementa únicamente la sección "Sesión P16 — Sidebar: búsqueda + favoritas + recientes"

Worktree: raíz del repositorio
Rama: windows/p14-escritorio

PREREQUISITO: ejecuta primero swift build --target NetDeckWindows.
Si hay errores, invoca /ecc:swift-build-resolver y resuélvelos antes de continuar.

SKILLS que debes invocar:
1. Al empezar: /ecc:swift-reviewer — revisar buildSidebar() y SessionLists API antes de tocarlos.
2. Antes del commit: /code-review medium — revisar el diff completo.

Instrucciones obligatorias:
- GateGuard hook activo: presenta los facts antes de cada Write/Edit.
- NO BOM en archivos Swift nuevos.
- Toda cadena UI en L("…"); nuevas entradas en Ingles.swift antes del ] final.
- bash tools/privacidad.sh antes del commit.
- Commit termina con: Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
- Entrada nueva al principio de windows/ESTADO.md.

Nota técnica: comprueba si SessionLists.favoritesURL y SessionLists.recentsURL existen
en NetDeckCore con grep antes de usarlas. Si no existen, usa:
  AppPaths.configDir.appendingPathComponent("favoritas")
  AppPaths.configDir.appendingPathComponent("recientes")

Al terminar:
1. swift build --target NetDeckWindows — sin errores.
2. swift test --filter IdiomaTests — debe pasar.
3. bash tools/privacidad.sh — "sin datos personales".
4. Commit con el mensaje del plan.
```

---

## ▶ CODEX — P17: Auto-update al arrancar + accesibilidad UIA

**Cuándo**: después de que P16 esté en verde
**Modelo Codex**: `o4-mini`
**Archivo único**: `windows/Desktop/Sources/NetDeckWindows/NetDeckWindows.swift`

```
Project: Terminal NetDeck – Windows port (WinUI 3 / Swift)
Repo/worktree: raíz del repositorio
Branch: windows/p14-escritorio
Plan file: .claude/plans/windows-p15-p17.plan.md  ← read this first

PREREQUISITE: run swift build --target NetDeckWindows — must be 0 errors before starting.

TASK: Implement section "Sesión P17 — Auto-comprobación de actualizaciones + accesibilidad UIA".

ONLY file to touch: windows/Desktop/Sources/NetDeckWindows/NetDeckWindows.swift

Change 1 — Auto-check for updates on launch.
Find the app startup code (search for "buildSidebar()") and add immediately after it:

    Task { @MainActor [weak self] in
        guard let self else { return }
        // Check only if >24 h since last check
        let lastKey = "lastUpdateCheck"
        let last = UserDefaults.standard.object(forKey: lastKey) as? Date ?? .distantPast
        guard abs(last.timeIntervalSinceNow) > 86400 else { return }
        UserDefaults.standard.set(Date(), forKey: lastKey)
        if let found = try? await UpdateChecker.shared.check() {
            self.offerUpdate(found)
        }
    }

NOTE: first check if UpdateChecker.shared.checkIfStale() already exists. If it does, use it
instead and skip the UserDefaults logic above.

Change 2 — UIA names for sidebar rows and terminal tabs.
In buildSidebar(), find each AutomationProperties.setAutomationId(btn, ...) call for session
buttons and add directly after it:
    AutomationProperties.setName(btn, perfil.name)

For the ★ favorite button (added in P16), add:
    AutomationProperties.setName(fav, favoritas.contains(perfil.name)
        ? L("Quitar de favoritas") : L("Añadir a favoritas"))

For terminal tab buttons (search for tabButton or the tab strip button creation), add:
    AutomationProperties.setName(tabBtn, tab.title)

CONSTRAINTS:
- No new UI strings needed beyond what P16 already added for favorites.
- Run: swift build --target NetDeckWindows — must compile 0 errors.
- Run: bash tools/privacidad.sh — "sin datos personales".
- Commit message:
    windows/p17: auto-check actualizaciones al arrancar + nombres UIA

    Comprueba actualizaciones silenciosamente al arrancar si han pasado
    más de 24 h desde la última consulta (UserDefaults lastUpdateCheck).
    AutomationProperties.setName en botones del sidebar y pestañas para
    que Narrator anuncie los nombres correctamente.

- Add entry at TOP of windows/ESTADO.md describing what was done.
```

---

## Contexto rápido

El puerto Windows tiene paridad casi total con macOS. Quedan 4 gaps funcionales y 2 de calidad, organizados en 3 sesiones independientes (P15-A y P15-B pueden correr en paralelo).

---

## Reglas que se aplican en TODAS las sesiones

| Regla | Detalle |
|---|---|
| **NO BOM** | Archivos Swift nuevos: `[System.IO.File]::WriteAllText(path, content, (New-Object System.Text.UTF8Encoding $false))` |
| **GateGuard** | Antes de cada Write/Edit presentar: (1) callers/importers, (2) no hay duplicado, (3) estructura de datos tocada, (4) instrucción verbatim del usuario |
| **Traducciones** | Toda cadena UI en `L("…")`. Nuevas entradas en `Ingles.swift` antes del `]` final (línea ~2618 tras P14). `IdiomaTests` verifica cobertura. |
| **Privacidad** | `bash tools/privacidad.sh` antes de cada commit |
| **Commits** | Terminar con `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` |
| **ESTADO.md** | Añadir entrada al principio de `windows/ESTADO.md` con cada commit |

---

## Patrones del código a respetar

| Categoría | Archivo de referencia | Patrón |
|---|---|---|
| Paneles WinUI | `windows/Desktop/Sources/NetDeckWindows/PanelBotones.swift` | `final class Panel*`, en español, `ScrollViewer` como raíz |
| Error handling | `windows/Desktop/Sources/NetDeckWindows/NetDeckWindows.swift:685` | `do { … } catch { status.text = error.localizedDescription }` |
| Automatización activa | `NetDeckWindows.swift` | `automatizacionActiva`, `pararAutomatizacion.visibility` |
| Credenciales (Windows) | `Sources/NetDeckCore/Security/KeychainStore.swift:244` | `KeychainStore().accounts(in: .named)` / `.save` / `.delete` |
| Favoritas / recientes | `Sources/NetDeckCore/Sessions/SessionLists.swift` | `SessionLists.loadFavorites` / `recents` / `saveFavorites` |
| AutomationId | `NetDeckWindows.swift` (varias) | `AutomationProperties.setAutomationId(elem, "Clave_Nombre")` |

---

## Sesión P15-A — F-keys + hotkeys de botón *(independiente, ~25 líneas)*

**Complejidad**: Baja
**Archivo único**: `windows/Desktop/Sources/NetDeckWindows/NetDeckWindows.swift`

### Problema

`keySequence(_ key:tab:)` no tiene casos para F1–F12 (VK_F1=112…VK_F12=123).
Los hotkeys guardados en `CommandButton.hotkey` nunca se despachan.

### APIs clave

```swift
// Ya existe en NetDeckCore:
FunctionKey.name(_ bytes: [UInt8]) -> String?        // "F5", "S-F5", "C-F5", "M-F5"…
ButtonFile.button(forKey: String) -> CommandButton?  // busca por hotkey
archivoBotones: ButtonFile                           // ya cargado en NetDeckWindows
VK_F1=112, VK_F12=123, VK_SHIFT, VK_CONTROL, VK_MENU
```

### Tarea 1 — F-keys en `keySequence`

Insertar antes de `default: return nil` en `keySequence(_ key:tab:)` (buscar `case 46: return`):

```swift
case 112...123:
    let n = Int(key) - 111          // F1=1 … F12=12
    let shift = GetKeyState(Int32(VK_SHIFT)) < 0
    let ctrl  = GetKeyState(Int32(VK_CONTROL)) < 0
    let alt   = GetKeyState(Int32(VK_MENU)) < 0
    let mod   = (shift ? 1 : 0) | (alt ? 2 : 0) | (ctrl ? 4 : 0)
    let ss3   = ["P","Q","R","S"]
    let csi   = [11,12,13,14,15,17,18,19,20,21,23,24]
    if mod == 0 {
        return n <= 4 ? "\u{1b}O\(ss3[n-1])"
                      : "\u{1b}[\(csi[n-1])~"
    }
    return n <= 4 ? "\u{1b}[1;\(mod+1)\(ss3[n-1])"
                  : "\u{1b}[\(csi[n-1]);\(mod+1)~"
```

### Tarea 2 — Despachar hotkeys en `keyDown` del terminal

En **ambos** handlers `surface.keyDown` (grid principal ~línea 225 y ventana separada ~línea 1628), **antes** de `self.recordKeys(bytes, tab: tab)`:

```swift
// Hotkey de botón (F5, S-F5, M-F5, C-F5…)
if let seq = Array(bytes.utf8) as [UInt8]?,
   let k = FunctionKey.name(seq),
   let btn = self.archivoBotones.button(forKey: k) {
    self.useCommandButton(btn)
    args.handled = true
    return
}
```

### Validación

```bash
# Ejecuta las órdenes desde la raíz del repositorio.
swift build --target NetDeckWindows 2>&1 | grep -E "error:|Build complete"
bash tools/privacidad.sh
```

Manual: abrir sesión local → pulsar F3 → debe llegar `^[[13~` al terminal.
Crear botón con atajo `F5` → pulsar F5 en la pestaña → el botón se ejecuta.

---

## Sesión P15-B — Panel de gestión de credenciales *(independiente, ~180 líneas)*

**Complejidad**: Media
**Archivos**:
- CREAR: `windows/Desktop/Sources/NetDeckWindows/PanelLlavero.swift`
- UPDATE: `windows/Desktop/Sources/NetDeckWindows/NetDeckWindows.swift`
- UPDATE: `Sources/NetDeckCore/Support/Ingles.swift`

### Problema

No hay UI para añadir/editar/borrar contraseñas en el Administrador de credenciales. Si `.pass` o `.login` fallan con "no está en el Llavero", el usuario no puede remediarlo desde la app.

### APIs clave

```swift
KeychainStore().accounts(in: .named) throws -> [String]           // lista nombres
KeychainStore().save(_ pw: String, for: CredentialRef) throws     // crear/actualizar
KeychainStore().delete(_ ref: CredentialRef) throws               // borrar
CredentialRef(service: .named, account: nombre)
archivoBotones.buttons.filter { $0.mode == .pass || $0.mode == .login }  // uso
```

### Tarea 1 — `PanelLlavero.swift`

```
final class PanelLlavero
  view: ScrollViewer            (raíz, visibility .collapsed al arrancar)
  var onClose: (() -> Void)?
  var getArchivoBotones: (() -> ButtonFile)?   // inyectado por NetDeckWindows

  UI (StackPanel vertical, spacing 8, maxWidth 580):
    TextBlock "Llavero de Windows" (fontSize 20)
    ComboBox lista (minWidth 300, header "Credencial")  ← KeychainStore().accounts(in: .named)
    TextBox nombre (header "Nombre de la credencial", minWidth 300)
    PasswordBox clave (header "Contraseña", minWidth 300)
    TextBlock uso (opacity 0.6)   ← cuántos botones la usan
    StackPanel horizontal: [guardar, borrar, recargar, cerrar]

  func reload()
    → accounts = try KeychainStore().accounts(in: .named)
    → rellenar ComboBox; seleccionar el primero
    → llamar loadSelected()

  func loadSelected()
    → nombre.text = cuenta seleccionada
    → clave.password = ""   (nunca se muestra la contraseña guardada)
    → uso.text = "Usada por X botón(es): nombre1, nombre2"

  guardar.click
    → validar nombre no vacío
    → KeychainStore().save(clave.password, for: CredentialRef(service: .named, account: nombre.text))
    → status/aviso "Credencial guardada"; reload()

  borrar.click
    → pedir confirmación en status (un segundo clic confirma, igual que PanelMacros.borrar)
    → KeychainStore().delete(CredentialRef(service: .named, account: cuenta))
    → reload()

  lista.selectionChanged → loadSelected()
```

### Tarea 2 — Integrar en `NetDeckWindows.swift`

```swift
// junto al resto de paneles:
private let llavero = PanelLlavero()

// en init(), junto a los otros onClose:
llavero.onClose = { [weak self] in self?.showPanel(nil) }
llavero.getArchivoBotones = { [weak self] in self?.archivoBotones ?? ButtonFile() }

// en showPanel(_:), añadir:
llavero.view.visibility = panel === llavero.view ? .visible : .collapsed

// en shortcut(_:), añadir caso (Ctrl+Shift+K = key 75):
case 75 where shift:
    showLlavero()

// nueva función:
private func showLlavero() {
    llavero.reload()
    showPanel(llavero.view)
}
```

También añadir un botón «Gestionar contraseñas…» en `PanelAjustes` que llame al closure `onManagePasswords`.

### Tarea 3 — Traducciones (`Ingles.swift`)

```swift
"Llavero de Windows": "Windows Credential Store",
"Gestionar contraseñas…": "Manage passwords…",
"Nombre de la credencial": "Credential name",
"Guardar credencial": "Save credential",
"Borrar credencial": "Delete credential",
"Recargar lista": "Reload list",
"Usada por %d botón(es)": "Used by %d button(s)",
"¿Borrar «%@» del Llavero?": "Delete \u{201C}%@\u{201D} from the Credential Store?",
"Credencial guardada": "Credential saved",
"Credencial borrada": "Credential deleted",
"Sin botones que la usen": "Not used by any button",
```

### Validación

```bash
swift build --target NetDeckWindows 2>&1 | grep -E "error:|Build complete"
bash tools/privacidad.sh
```

Manual: Ctrl+Shift+K → panel abre → crear credencial «test-plan» → verificar con `cmdkey /list | findstr test-plan` → borrar desde el panel → confirmar que desaparece.

---

## Sesión P16 — Sidebar: búsqueda + favoritas + recientes *(~120 líneas)*

**Complejidad**: Media
**Depende de**: P15-A y P15-B en verde (no es técnico, solo comodidad)
**Archivos**:
- UPDATE: `windows/Desktop/Sources/NetDeckWindows/NetDeckWindows.swift`
- UPDATE: `Sources/NetDeckCore/Support/Ingles.swift`

### Problema

La barra lateral de Windows es una lista plana. macOS tiene árbol de carpetas, buscador en tiempo real, ★ favoritas, ↻ recientes (top 10), menú contextual.

### APIs clave

```swift
SessionLists.loadFavorites(_ url: URL) throws -> [String]
SessionLists.saveFavorites(_ names: [String], to: URL) throws
SessionLists.recents(_ text: String, limit: Int) -> [String]      // más reciente primero
SessionLists.appending(_ line: String, to: String) -> String
// comprobar si existen SessionLists.favoritesURL y SessionLists.recentsURL en Core
// si no, usar: AppPaths.configDir.appendingPathComponent("favoritas") / "recientes"
```

### Tarea 1 — Cargar favoritas y recientes al arrancar

```swift
// junto a archivoBotones:
private var favoritas: Set<String> = []
private var recientes: [String] = []

// en loadSessions() o equivalente, después de cargar sessions:
favoritas = Set((try? SessionLists.loadFavorites(SessionLists.favoritesURL)) ?? [])
let recText = (try? SafeFile.read(SessionLists.recentsURL)) ?? ""
recientes = SessionLists.recents(recText)
```

Al `openProfile(perfil)`: llamar `SessionLists.saveRecent(perfil.name, to: SessionLists.recentsURL)` y reconstruir la barra.

### Tarea 2 — Campo de búsqueda en el sidebar

```swift
// en buildSidebar(), antes del bucle de grupos:
let buscar = TextBox()
buscar.placeholderText = L("Buscar sesión…")
buscar.margin = Thickness(left: 4, top: 4, right: 4, bottom: 4)
buscar.textChanged.addHandler { [weak self] _, _ in
    self?.buildSidebar(filter: buscar.text)
}
sidebar.children.append(buscar)
```

Añadir parámetro `func buildSidebar(filter: String = "")`. Filtrar: `perfiles.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }`.

### Tarea 3 — Secciones ★ y ↻ en `buildSidebar`

Orden de secciones cuando no hay filtro activo:
1. **↻ Recientes** — `recientes.prefix(10)`, resolviendo cada nombre a su `SessionProfile`
2. **★ Favoritas** — perfiles cuyo `name` está en `favoritas`
3. Grupos existentes (como ahora)

Cada fila añade un botón `★`/`☆` a la derecha (antes del botón de editar):

```swift
let fav = Button()
fav.content = favoritas.contains(perfil.name) ? "★" : "☆"
fav.click.addHandler { [weak self] _, _ in
    guard let self else { return }
    if self.favoritas.contains(perfil.name) { self.favoritas.remove(perfil.name) }
    else { self.favoritas.insert(perfil.name) }
    try? SessionLists.saveFavorites(Array(self.favoritas).sorted(), to: SessionLists.favoritesURL)
    self.buildSidebar()
}
AutomationProperties.setName(fav, favoritas.contains(perfil.name)
    ? L("Quitar de favoritas") : L("Añadir a favoritas"))
```

### Tarea 4 — Traducciones

```swift
"Buscar sesión…": "Search session…",
"↻ Recientes": "↻ Recent",
"★ Favoritas": "★ Favorites",
"Añadir a favoritas": "Add to favorites",
"Quitar de favoritas": "Remove from favorites",
"Duplicar sesión": "Duplicate session",
```

### Validación

```bash
swift build --target NetDeckWindows 2>&1 | grep -E "error:|Build complete"
bash tools/privacidad.sh
```

Manual: abrir dos sesiones → aparecen en ↻ Recientes; marcar una ★ → persiste al relanzar; escribir en el buscador → la lista se filtra en tiempo real.

---

## Sesión P17 — Auto-comprobación de actualizaciones + accesibilidad UIA *(~15 líneas)*

**Complejidad**: Baja
**Depende de**: P16 en verde
**Archivo único**: `windows/Desktop/Sources/NetDeckWindows/NetDeckWindows.swift`

### Tarea 1 — Auto-check al arrancar

Buscar el punto de arranque (justo después de `buildSidebar()`). Añadir:

```swift
Task { @MainActor [weak self] in
    guard let self else { return }
    // checkIfStale() solo consulta la red si han pasado >24 h desde la última vez
    if let found = try? await UpdateChecker.shared.checkIfStale() {
        self.offerUpdate(found)
    }
}
```

> **Nota**: verificar si `UpdateChecker.shared.checkIfStale()` existe.
> Si no existe, guardar `Date()` en `UserDefaults` y comparar al arrancar:
> solo llamar `.check()` si `abs(last.timeIntervalSinceNow) > 86400`.

### Tarea 2 — Nombres UIA en sidebar y pestañas

En `buildSidebar`, junto al `setAutomationId` existente:

```swift
AutomationProperties.setName(btn, perfil.name)
```

En la creación de botones de pestaña (buscar `tabButton` o equivalente):

```swift
AutomationProperties.setName(tabBtn, tab.title)
```

### Traducciones (si se añaden mensajes nuevos)

```swift
"Quitar de favoritas": "Remove from favorites",   // (ya en P16 si se hace antes)
"Añadir a favoritas": "Add to favorites",
```

### Validación

```bash
swift build --target NetDeckWindows 2>&1 | grep -E "error:|Build complete"
bash tools/privacidad.sh
```

Manual: relanzar app → tras ~2 s comprobar que no explota; activar Narrator (Win+Enter) → navegar con Tab por la barra lateral → Narrator anuncia los nombres de las sesiones.

---

## Orden recomendado

```
P15-A (F-keys, ~25 líneas)   ──┐
                                ├──> P16 (Sidebar, ~120 líneas) ──> P17 (Auto-update + UIA, ~15 líneas)
P15-B (Llavero, ~180 líneas) ──┘
```

P15-A y P15-B no tocan los mismos bloques de `NetDeckWindows.swift` y pueden ejecutarse en paralelo en sesiones separadas.

---

## Checklist de cierre de cada sesión

- [ ] `swift build --target NetDeckWindows` sin errores
- [ ] `swift test --filter IdiomaTests` pasa
- [ ] `bash tools/privacidad.sh` → "sin datos personales"
- [ ] Commit con mensaje descriptivo + `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`
- [ ] Entrada nueva al principio de `windows/ESTADO.md`

---

## Tabla resumen: herramienta · modelo · skills · agentes

| Sesión | Herramienta | Modelo | Skills obligatorias | Agente de revisión |
|---|---|---|---|---|
| **P15-A** F-keys | **Codex** | `o4-mini` | — | — (el prompt es prescriptivo) |
| **P15-B** Llavero | **Claude Code** | `claude-sonnet-5-5` | `/ecc:swift-reviewer` al inicio · `/ecc:security-review` sobre PanelLlavero · `/code-review medium` | `ecc:swift-reviewer` + `ecc:security-reviewer` |
| **P16** Sidebar | **Claude Code** | `claude-sonnet-5-5` | `/ecc:swift-reviewer` al inicio · `/code-review medium` | `ecc:swift-reviewer` |
| **P17** Auto-update + UIA | **Codex** | `o4-mini` | — | — (el prompt es prescriptivo) |

### Por qué Codex para P15-A y P17

- Cambios quirúrgicos con el código exacto ya escrito en el prompt → Codex los aplica directamente sin necesidad de razonar sobre el diseño.
- Sin lógica de seguridad ni decisiones cross-file.
- Coste y latencia menores con `o4-mini`.

### Por qué Claude Code para P15-B y P16

- P15-B requiere razonar sobre la API de seguridad (CredWriteW/CredDeleteW), diseñar un panel nuevo de ~180 líneas y pasar `/ecc:security-review`.
- P16 requiere entender y refactorizar `buildSidebar` + integrar `SessionLists` (API del núcleo) + mantener coherencia con el resto del sidebar → tarea cross-file que se beneficia de los agentes ECC.

### Skills de Claude Code disponibles en cualquier sesión

```
/ecc:swift-build-resolver   → errores de compilación Swift/SPM
/ecc:security-review        → revisión de seguridad (obligatorio en P15-B)
/ecc:swift-reviewer         → revisión completa del código Swift añadido
/code-review [low|medium]   → revisión del diff antes del commit
/ecc:plan                   → si necesitas replantear un sub-paso
```
