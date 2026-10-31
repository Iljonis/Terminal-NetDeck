# Idiomas: castellano de España e inglés (detalle)

Léelo antes de añadir, cambiar o quitar texto visible. Con Claude, la skill `netdeck-texto-visible` lo amplía con
ejemplos y un script que encuentra las claves sin uso.

- El código está en castellano de España y la interfaz se traduce al inglés. El idioma se elige en Ajustes → General
  → Idioma (`AppSettings.language`, clave `idioma` en UserDefaults) y se aplica al momento.
- Todo texto visible va con `L("…")` (`NetDeckCore/Support/Idioma.swift`). La clave es el texto en castellano, con un
  `%@` por cada valor interpolado; su inglés va en `NetDeckCore/Support/Ingles.swift`. Si cambias un texto, cambia su
  clave y borra la que ya no se use.
- Nombres que vienen de datos (grupos de temas o de sesiones): se muestran con `L(nombre:)` y se listan en
  `Idioma.nombresConocidos`.
- NO se traducen: los registros de depuración (`DebugLog`), las claves de UserDefaults, los ids, las regex, el formato
  del ssh_config y de los `.tema`, las órdenes ssh ni los valores que se guardan (p. ej. el grupo «General»).
- `IdiomaTests` falla si una `L("…")` no tiene inglés o si los `%@` no cuadran. Sólo ve literales: nunca
  `L(variable)`.
- Textos neutros: no compararse con «NetDeck» (la herramienta bash anterior). La marca «Terminal NetDeck» sí.
