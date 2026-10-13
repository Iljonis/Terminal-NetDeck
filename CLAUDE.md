# Terminal NetDeck

App nativa de macOS (Swift 6 / SwiftUI + SwiftTerm) para ingenieros de red. Ver README.md para módulos y uso.

## Comandos

- `swift build` · `swift run TerminalNetDeck` (desarrollo; `-idioma en` la abre en inglés)
- `./test.sh` — tests del núcleo (Swift Testing)
- `./install.sh` (instalar) · `./install.sh --dmg` (empaquetar)
- `NETDECK_SNAPSHOT=/ruta.png [NETDECK_SNAPSHOT_ACTION=settings:general|tab:usuario@equipo|split]` → captura de la ventana

## Idiomas (castellano de España e inglés)

- El código está en castellano de España; la interfaz se traduce al inglés. Selector en Ajustes → General → Idioma
  (`AppSettings.language`, clave `idioma` en UserDefaults); se aplica al momento.
- Todo texto visible va con `L("…")` (`NetDeckCore/Support/Idioma.swift`). La clave es el texto en castellano con `%@`
  por cada valor interpolado; su inglés va en `NetDeckCore/Support/Ingles.swift`.
- Nombres que vienen de datos (grupos de temas o de sesiones) se muestran con `L(nombre:)` y se listan en
  `Idioma.nombresConocidos`.
- NO se traduce: registros de depuración (`DebugLog`), claves de UserDefaults, ids, regex, formato del ssh_config o de
  los `.tema`, órdenes ssh, ni valores que se guardan (p. ej. el grupo «General»).
- `IdiomaTests` falla si una `L("…")` no tiene inglés o si los `%@` no cuadran: al añadir o cambiar un texto, añade su
  traducción en `Ingles.swift`.

## Reglas del proyecto

- Repositorio público: nada de IPs, usuarios, hosts ni contraseñas reales. Ejemplos con `192.0.2.x` (RFC 5737),
  `tu.usuario`, `core-01`, `bastion`.
- Contraseñas sólo en el Llavero; regla de usuario estricta (`CredentialPolicy`): nunca se escribe sola la de otro usuario.
- Commits a nombre del autor del repositorio, sin línea de coautor.
