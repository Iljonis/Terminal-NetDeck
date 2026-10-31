# Agentes y skills (detalle)

Léelo antes de encargar trabajo a un agente o de fusionar su rama. Los agentes se usan para el trabajo grande y para
las revisiones; los arreglos pequeños se hacen directamente.

## Agentes
Los de este proyecto están en `.claude/agents/` (Claude) y `.codex/agents/` (Codex) y conocen ya las reglas. Los de
ECC (plugin) se usan para auditorías de sólo lectura.

| Agente | Para qué | Cómo |
|---|---|---|
| `netdeck-implementador` | Funciones nuevas o cambios grandes | En `isolation: worktree`. Deja su trabajo en una rama con commits; luego se revisa y se fusiona a `main` |
| `netdeck-auditor` | Revisar un cambio: errores, seguridad y estabilidad con las reglas de la raíz | Sólo lectura; informe con archivo:línea y arreglo |
| `ecc:security-reviewer` | Secretos, datos personales, Llavero, inyección de órdenes, actualizaciones, scripts | Sólo lectura, antes de cada versión |
| `ecc:code-reviewer` | Errores reales en el diff (`git diff <base>..HEAD`) | Sólo lectura |
| `ecc:silent-failure-hunter` | Errores tragados, pérdida de datos, procesos bloqueados | Sólo lectura |
| `ecc:performance-optimizer` | Fugas de memoria, congelaciones del hilo principal, CPU | Sólo lectura |
| `ecc:swift-reviewer` · `ecc:swift-build-resolver` | Revisión idiomática de Swift · arreglar compilaciones rotas | Según haga falta |
| `ecc:opensource-sanitizer` | Comprobar que el repo público no lleva nada privado | Antes de publicar una versión |

Cómo se trabaja con ellos:
1. Encargo preciso: qué archivos tocar, qué reglas aplican y qué no tocar si hay otro trabajo en paralelo.
2. La implementación, en una worktree. Si dos agentes tocan `Ingles.swift` o los mismos archivos de Ajustes, mejor uno
   detrás del otro. Al fusionar, los conflictos de «añadidos al final» se resuelven quedándose con los dos lados.
3. Revisión del diff antes de fusionar, sobre todo de contraseñas, MultiExec, archivos del usuario y textos sin
   traducir.
4. Tras fusionar, `swift build` y `./test.sh` en verde. Si hay interfaz nueva, una captura con un `NETDECK_HOME` de
   ejemplo.
5. Una pasada de `netdeck-auditor` o de los agentes de ECC. Se arreglan los hallazgos reales y se descartan, con su
   motivo, los que no lo son.

## Skills
Las del proyecto están en `.agents/skills/` (Codex, en el repo) y, con el mismo contenido, en `.claude/skills/`
(Claude, local: el `.gitignore` global del autor excluye `.claude/`). Si cambias una, copia el archivo a la otra.
- `terminal-netdeck-patterns`: mapa, archivos que cambian juntos y reglas aprendidas de regresiones (contraseñas, ratón,
  tests en la CI).
- `netdeck-verificar-demo`: antes de un commit o un tag.
- `netdeck-publicar`: versión, tag y Release.
- `netdeck-texto-visible`: `L("…")` e `Ingles.swift`.
- `netdeck-run`: arrancar la app y hacer capturas con datos de demo.

De ECC, cuando el trabajo lo pida:
- `swiftui-patterns`: vistas y `@Observable`.
- `swift-protocol-di-testing`: tests sin Llavero, ssh ni red.
- `swift-actor-persistence`: estado compartido y archivos.
- `cisco-ios-patterns`, `network-config-validation` y `network-interface-health`: reglas de resaltado y órdenes
  peligrosas del pegado seguro.
- `accessibility`: contraste de los temas y VoiceOver.
- `security-review`: contraseñas, askpass, actualizaciones.
- `liquid-glass-design`: está escrita para iOS 26; en macOS, sólo tras `if #available(macOS 26, *)`.

Instaladas para el usuario (`~/.claude/skills`, no en el repo), si están:
- `swiftui-pro` (twostraws): revisión de SwiftUI moderna, rendimiento, accesibilidad y localización.
- `appkit-swiftui-bridge` y `ui-review-tahoe` (rshankras): puente AppKit-SwiftUI (SwiftTerm, `NSPanel`, monitores
  de ratón) y revisión de interfaz para macOS Tahoe (HIG, Liquid Glass).
- `systematic-debugging` y `receiving-code-review` (obra/superpowers): buscar la causa antes de arreglar, y comprobar
  cada hallazgo de una revisión (de Codex o del auditor) antes de aplicarlo.