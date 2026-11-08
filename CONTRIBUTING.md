# Cómo contribuir a Terminal NetDeck

¡Gracias por tu interés! Errores, ideas y cambios son bienvenidos.
*English: issues and pull requests in English are welcome too; the code and its comments are in Spanish.
[Jump to the English version](#contributing-to-terminal-netdeck).*

Al participar aceptas el [código de conducta](CODE_OF_CONDUCT.md).

## Avisar de un error o proponer algo

Abre un [issue](https://github.com/Iljonis/Terminal-NetDeck/issues/new/choose) con su formulario: la versión (Ajustes →
General), la de macOS y los pasos para reproducirlo. **No pegues datos reales**: ni IPs, ni nombres de equipos, ni
usuarios, ni contraseñas. Usa los de ejemplo: `192.0.2.x`, `198.51.100.x`, `203.0.113.x` (RFC 5737), `tu.usuario`,
`core-01`, `bastion`.

Si es un fallo de seguridad, no abras un issue público: usa
[Security → Report a vulnerability](https://github.com/Iljonis/Terminal-NetDeck/security/advisories/new)
(más en [SECURITY.md](SECURITY.md)).

## Preparar el entorno

Necesitas macOS 15 o posterior y Xcode 26 (Swift 6.2).

```bash
swift build
swift run TerminalNetDeck            # -idioma en para verla en inglés
./test.sh                            # privacidad + tests del núcleo; tiene que salir en verde
```

`swift run` arranca con tus datos reales (sesiones, ajustes y Llavero). Para verla con datos de ejemplo, usa
`tools/verificar_demo.sh`, que la abre con una carpeta temporal y las sesiones de `tools/demo`.

## Antes de abrir un pull request

- `./test.sh` en verde (lo comprueba también GitHub Actions).
- Si tocas la interfaz: `tools/verificar_demo.sh` con datos de ejemplo, nunca con los tuyos. Mira las capturas.
- **Textos visibles** con `L("…")`. Su inglés va en `Sources/NetDeckCore/Support/Ingles.swift`; `IdiomaTests` falla si
  falta.
- **Contraseñas** sólo en el Llavero, nunca en argumentos, archivos ni registros.
- **Archivos del usuario** (ssh_config, listas, botones) siempre con `SafeFile`.
- La lógica que se pueda probar va en `NetDeckCore`, con tests en `Tests/NetDeckCoreTests` (Swift Testing).
- El código, los comentarios y los mensajes de commit van en castellano: un título corto y viñetas con el porqué.
- Si el cambio se nota, añade una línea a `[Unreleased]` en [CHANGELOG.md](CHANGELOG.md).

En [CLAUDE.md](CLAUDE.md) están el resto de reglas de la arquitectura (sesiones, MultiExec, pegado seguro,
actualizaciones).

## Licencia

Al contribuir aceptas que tu aportación se publique bajo la [licencia MIT](LICENSE) del proyecto.

---

# Contributing to Terminal NetDeck

Thanks for your interest! Bug reports, ideas and changes are welcome. By taking part you agree to the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting a bug or suggesting something

Open an [issue](https://github.com/Iljonis/Terminal-NetDeck/issues/new/choose) with its form: the version (Settings →
General), your macOS version and the steps to reproduce it. **Don't paste real data**: no IPs, device names, users or
passwords. Use the sample ones: `192.0.2.x`, `198.51.100.x`, `203.0.113.x` (RFC 5737), `tu.usuario`, `core-01`,
`bastion`.

For a security issue, don't open a public issue: use
[Security → Report a vulnerability](https://github.com/Iljonis/Terminal-NetDeck/security/advisories/new)
(see [SECURITY.md](SECURITY.md)).

## Setting up

You need macOS 15 or later and Xcode 26 (Swift 6.2). Run `swift build` and `./test.sh` (it must be green).
`swift run TerminalNetDeck -idioma en` starts the app in English **with your real data** (sessions, settings,
Keychain); to see it with sample data, use `tools/verificar_demo.sh`, which runs it in a temporary folder with the
sessions from `tools/demo`.

## Before opening a pull request

- `./test.sh` green (GitHub Actions checks it too).
- If you touch the interface, run `tools/verificar_demo.sh` with sample data, never yours, and look at the screenshots.
- **Visible text** goes through `L("…")` with the Spanish text as the key, and its English in
  `Sources/NetDeckCore/Support/Ingles.swift`; `IdiomaTests` fails if it's missing.
- **Passwords** only in the Keychain, never in arguments, files or logs. **User files** always through `SafeFile`.
- Code, comments and commit messages are in Spanish (Spain). If that's a problem, write in English and we'll help.
- For a visible change, add a line under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md).

The rest of the architecture rules are in [CLAUDE.md](CLAUDE.md) (in Spanish).

## License

By contributing you agree that your work is published under the project's [MIT license](LICENSE).
