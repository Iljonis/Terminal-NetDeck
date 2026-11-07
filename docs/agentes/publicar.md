# Publicar una versión (detalle)

Léelo antes de cambiar el número de versión, etiquetar o publicar. Con Claude, la skill `netdeck-publicar` añade el
seguimiento de la Release y qué hacer si falla.

**OBLIGATORIO en cada cambio de versión:** antes de etiquetar o publicar, actualiza `README.md`, `README.en.md`,
`install.sh` y cualquier otro archivo de documentación o script que lleve el número de versión actual. Compruébalo con
`grep -rnE "v?[0-9]+\.[0-9]+\.[0-9]+" README*.md install.sh docs tools`: ninguno puede quedarse en la versión anterior.

1. Sube `VERSION` en `install.sh`, «Versión actual» en `README.md` y «Current version» en `README.en.md`. Los README
   sólo llevan las novedades de la versión actual («Novedades de X.Y.Z» / «New in X.Y.Z», que sustituyen a las de la
   anterior); el historial va en `CHANGELOG.md` (en inglés, Keep a Changelog): pasa lo de `[Unreleased]` a una sección
   `[X.Y.Z] - fecha` y añade su enlace de comparación al final. Después:
   `./test.sh`, `tools/seguridad_cron.sh` y una pasada de `ecc:security-reviewer` y `ecc:opensource-sanitizer`.
2. Commit, push, `git tag -a vX.Y.Z -m "Terminal NetDeck X.Y.Z"` y `git push origin vX.Y.Z`.
3. Nada más. `.github/workflows/release.yml` comprueba que el tag y `VERSION` coinciden, pasa los tests, hace el
   .dmg, ejecuta `tools/privacidad.sh --binario` y crea la Release con el .dmg. La app se la ofrece («Actualizar
   ahora») a quien tenga una versión anterior, también a tu copia instalada.
