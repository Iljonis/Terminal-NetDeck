# Cómo contribuir a Terminal NetDeck

¡Gracias por tu interés! Errores, ideas y cambios son bienvenidos.
*English: issues and pull requests in English are welcome too; the code and its comments are in Spanish.*

## Avisar de un error o proponer algo

Abre un [issue](https://github.com/Iljonis/Terminal-NetDeck/issues) con la versión (Ajustes → General), la de macOS
y los pasos para reproducirlo. **No pegues datos reales**: ni IPs, ni nombres de equipos, ni usuarios, ni
contraseñas. Usa los de ejemplo: `192.0.2.x`, `198.51.100.x`, `203.0.113.x` (RFC 5737), `tu.usuario`, `core-01`,
`bastion`.

Si es un fallo de seguridad, no abras un issue público: usa
[Security → Report a vulnerability](https://github.com/Iljonis/Terminal-NetDeck/security/advisories/new).

## Preparar el entorno

Necesitas macOS 15 o posterior y Xcode (Swift 6).

```bash
swift build
swift run TerminalNetDeck            # -idioma en para verla en inglés
./test.sh                            # privacidad + tests del núcleo; tiene que salir en verde
```

## Antes de abrir un pull request

- `./test.sh` en verde (lo comprueba también GitHub Actions).
- Si tocas la interfaz: `tools/verificar_demo.sh` con datos de ejemplo, nunca con los tuyos. Mira las capturas.
- **Textos visibles** con `L("…")`. Su inglés va en `Sources/NetDeckCore/Support/Ingles.swift`; `IdiomaTests` falla si
  falta.
- **Contraseñas** sólo en el Llavero, nunca en argumentos, archivos ni registros.
- **Archivos del usuario** (ssh_config, listas, botones) siempre con `SafeFile`.
- El código, los comentarios y los mensajes de commit van en castellano: un título corto y viñetas con el porqué.

En [CLAUDE.md](CLAUDE.md) están el resto de reglas de la arquitectura (sesiones, MultiExec, pegado seguro,
actualizaciones).

## Licencia

Al contribuir aceptas que tu aportación se publique bajo la [licencia MIT](LICENSE) del proyecto.
