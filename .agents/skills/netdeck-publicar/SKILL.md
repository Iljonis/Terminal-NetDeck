---
name: netdeck-publicar
description: "Use in Terminal NetDeck when bumping the version, tagging or publishing a release (vX.Y.Z): every file that carries the version, the checks and reviewers before the tag, how release.yml builds the .dmg, and how to follow and recover a failed Release run without force-pushing"
---

# Publicar una versión (Terminal NetDeck)

Reglas en docs/agentes/publicar.md y en el apartado «Git» de CLAUDE.md. Aquí, el orden y lo que suele fallar.

## 1. Versión en todos los sitios

```bash
V=1.2.3; A=$(grep -E '^VERSION=' install.sh | cut -d= -f2)    # nueva y actual
sed -i '' "s/^VERSION=.*/VERSION=$V/" install.sh
grep -rnE "v?[0-9]+\.[0-9]+\.[0-9]+" README*.md install.sh docs tools | grep -F "$A"   # lo que queda por cambiar
```
- `README.md`: «Versión actual» (enlace y badge) y una sección «Novedades de X.Y.Z» arriba de la anterior.
- `README.en.md`: «Current version», badge y «What's new in X.Y.Z», con el mismo contenido.
- Cuando el último `grep` ya no saca nada de la versión anterior (salvo las secciones de novedades antiguas), está.

## 2. Comprobaciones antes del tag

1. `./test.sh` en verde y la pasada de la skill `netdeck-verificar-demo`, con su informe.
2. `tools/seguridad_cron.sh` (OSV.dev, privacidad, tests, endurecimiento).
3. Agentes de sólo lectura: `ecc:security-reviewer` y `ecc:opensource-sanitizer` sobre `git diff vANTERIOR..HEAD`.
   Se arreglan los hallazgos reales y se descartan los demás, diciendo por qué.

## 3. Commit, tag y push (sólo cuando el autor lo pide)

```bash
git commit -m "Terminal NetDeck $V: resumen corto" -m "- viñeta con el porqué
- otra"                                   # castellano, título + LÍNEA EN BLANCO + viñetas, sin coautor
git push origin main
git tag -a "v$V" -m "Terminal NetDeck $V" && git push origin "v$V"
```

## 4. Lo que hace `release.yml` (no lo repitas a mano)

Comprueba que el tag es igual que `VERSION` → `./test.sh` → `./install.sh --dmg` → `tools/verificar_paquete.sh build/qa`
(demo sobre la `.app` del paquete) → `tools/test_ssh_local.sh` → `tools/privacidad.sh --binario` → `gh release create`,
con las notas sacadas de los commits desde el tag anterior. Seguimiento:
```bash
gh run list -L 4; gh run watch <id> --exit-status; gh release view "v$V"
```
Las capturas y los informes están en el artefacto `qa-paquete` (7 días).

## 5. Si la Release falla

- «install.sh dice X y el tag es vY»: se etiquetó antes de subir `VERSION`. Arregla `install.sh` y vuelve a etiquetar;
  mover el tag también necesita el permiso del autor.
- Mira el paso y descarga `qa-paquete` (`gh run download <id> -n qa-paquete`) para ver las capturas.
- `reabrir en sus ventanas` y `pestañas` son inestables en el runner (pantalla de 1024 px): un `gh run rerun --failed`
  se acepta UNA vez. Si vuelve a fallar, arregla el test.
- Arreglo en un commit nuevo en `main`. Para mover el tag hace falta un `--force`, y eso **sólo si el autor lo pide**:
  `main` está protegida por el ruleset «Protec MAIN». Si no, se sube una versión nueva (X.Y.Z+1) y no se reutiliza el tag.
- Nunca dejes un tag publicado sin Release: o se arregla, o se borra con el permiso del autor.
