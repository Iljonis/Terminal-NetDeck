---
name: netdeck-texto-visible
description: "Use in Terminal NetDeck whenever you add, change or remove user-visible text (labels, buttons, menus, alerts, model.status messages, help text): L(\"…\") keys in Spanish with %@, the English table in Ingles.swift, L(nombre:) for data names, what must not be translated, unused keys and IdiomaTests"
---

# Texto visible en Terminal NetDeck

## Regla
Todo texto que ve el usuario va con `L("…")` (`Sources/NetDeckCore/Support/Idioma.swift`). La **clave es el texto en
castellano de España** tal como se escribe, con `%@` por cada valor interpolado y `%%` por cada `%` literal. Su inglés
va en `Sources/NetDeckCore/Support/Ingles.swift` (`Ingles.textos`); lo que falte sale en castellano.

```swift
Text(L("Recargar ssh_config"))
message = L("\(ids.count) importadas: revísalas y pulsa «Guardar»")   // clave: "%@ importadas: revísalas y pulsa «Guardar»"
```
```swift
// Ingles.swift (clave con 8 espacios; el valor en la misma línea o en la siguiente)
        "%@ importadas: revísalas y pulsa «Guardar»":
            "%@ imported: review them and press “Save”",
```
- Mismo número de `%@` en las dos lenguas. Para cambiar el orden en inglés: `%2$@`, `%1$@`.
- Comillas: «…» en castellano, “…” en inglés.
- **Si cambias un texto, cambias su clave**: hay que poner la nueva en `Ingles.swift` y borrar la vieja.
- NUNCA `L(variable)` ni `L("a" + b)`: `IdiomaTests.todoElCodigoEstaTraducido` sólo encuentra literales, así que un
  texto armado así queda en castellano sin que ningún test falle. Para nombres que vienen de datos, `L(nombre:)`.
- NUNCA traduzcas un texto que se guarda o se compara (un grupo, una anotación `# @…`): al cambiar de idioma dejaría
  de coincidir con lo guardado.

## Nombres que vienen de datos
Los nombres de grupos de temas o de sesiones se muestran con `L(nombre: grupo)`. Sólo se traducen los que están en
`Idioma.nombresConocidos` (`Theme.groups` + «Sin grupo», «General», «Importadas»), y cada uno necesita su inglés.
Los que pone el usuario se dejan tal cual. Lo que se **guarda** (p. ej. el grupo «General» en el ssh_config) va
siempre en castellano.

## Lo que NO se traduce
`DebugLog`/`ErrorLog`, claves de UserDefaults, ids, regex, el formato del ssh_config y de los `.tema`, órdenes ssh y
valores que se guardan. El nombre de cada idioma en su selector tampoco («Español (España)», «English»).

## Mensajes, rutas y tono
- Avisos al usuario por `model.status`. Sólo salen como aviso los que empiezan por `✗` (error), `🔑` (contraseña),
  `⎋` (cancelado) o `⬆` (actualización); el resto se queda en la barra.
- Rutas en pantalla siempre con `AppPaths.tilde(…)` («~/…»), nunca la ruta completa.
- Textos neutros: nada de compararse con «NetDeck» (la herramienta bash anterior). La marca «Terminal NetDeck» sí.
- Ejemplos en los textos: `tu.usuario`, `core-01`, `bastion` e IPs `192.0.2.x`/`198.51.100.x`/`203.0.113.x`.

## Comprobar
1. `swift test --filter IdiomaTests`: falla si una `L("…")` no tiene inglés, si los `%@` no cuadran o si falta un
   nombre conocido.
2. Claves que ya nadie usa (el test no las detecta). Sólo lista lo que no aparece en el código; antes de borrar una
   clave, búscala con `grep -rnF`, porque puede estar armada de otra forma:
```bash
python3 -I - <<'PY'
import re, pathlib
ing = pathlib.Path("Sources/NetDeckCore/Support/Ingles.swift").read_text()
src = "\n".join(p.read_text() for p in pathlib.Path("Sources").rglob("*.swift") if p.name != "Ingles.swift")
for c in re.findall(r'^ {8}"((?:[^"\\]|\\.)*)":', ing, re.M):
    patron = r'\\\(.*?\)'.join(re.escape(t.replace("%%", "%")) for t in c.split("%@"))
    if not re.search('"' + patron + '"', src): print(c)
PY
```
3. Interfaz nueva: una captura en inglés (`-idioma en`) con la skill `netdeck-run` y mirarla. Que no corte el texto, que
   no quede nada en castellano.
