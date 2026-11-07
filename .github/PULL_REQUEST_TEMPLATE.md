<!-- Castellano o inglés · Spanish or English. Sin datos reales: 192.0.2.x, tu.usuario, core-01 · No real data. -->

## Qué cambia y por qué · What changes and why



## Cómo se ha probado · How it was tested

- [ ] `./test.sh` en verde · green
- [ ] Si toca la interfaz: `tools/verificar_demo.sh` y he mirado las capturas · If it touches the UI: ran the demo pass
      and checked the screenshots
- [ ] Capturas de antes y después (con datos de la demo) · Before/after screenshots (demo data)

## Lista de comprobación · Checklist

- [ ] Textos visibles con `L("…")` y su inglés en `Ingles.swift` · Visible text via `L("…")` with its English entry
- [ ] Contraseñas sólo en el Llavero, nunca en argumentos, archivos ni registros · Passwords only in the Keychain
- [ ] Archivos del usuario con `SafeFile` · User files through `SafeFile`
- [ ] MultiExec y pegado sólo a pestañas SSH/Telnet · MultiExec and paste only to SSH/Telnet tabs
- [ ] Sin datos reales en código, tests ni capturas · No real data in code, tests or screenshots
- [ ] Una línea en `[Unreleased]` de `CHANGELOG.md` si el cambio se nota · A `CHANGELOG.md` line if user-visible
