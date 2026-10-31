---
name: netdeck-verificar-demo
description: "Use in Terminal NetDeck before any commit, tag or final test report (verificación, demo, capturas, «pasa la demo»): the mandatory functional pass in the DEMO environment (tools/verificar_demo.sh with a temporary NETDECK_HOME, never real data), how to read its screenshots, the known flaky cases and the report the author expects before committing"
---

# Verificación integral en demo (Terminal NetDeck)

Obligatoria antes de un commit, un tag o un informe final de tests (CLAUDE.md). Nunca con los datos reales del
autor: el script ya usa una carpeta temporal con `tools/demo` y `CFFIXED_USER_HOME`; no lo cambies por `~`.

## Pasos

1. `swift build` limpio (el script compila `TerminalNetDeck`; si no compila, para ahí).
2. `./test.sh` (privacidad, prueba de actualización y tests del núcleo). Guarda el resumen.
3. La demo, con las capturas en una carpeta que puedas leer:
   ```bash
   OUT=$(mktemp -d "${TMPDIR:-/tmp}/netdeck-demo.XXXX"); tools/verificar_demo.sh "$OUT"; echo "$OUT"
   ```
   - Un caso suelto mientras arreglas algo: `SOLO=explorador tools/verificar_demo.sh "$OUT"`.
   - El paquete que se distribuye (como en la Release): `./install.sh --dmg` y `tools/verificar_paquete.sh build/qa`.
4. **Mira las capturas con Read**, no basta con «✓». Como mínimo:
   - `portada`, `portada-en`: barra lateral, pestañas, barra de botones; textos en castellano / inglés, sin claves.
   - `terminal-*` (mobaxterm-net, neo-tokyo, papel): la salida de `tools/demo/salida.txt` resaltada y legible en
     tema oscuro y claro (up ≠ down, IPs).
   - `explorador*`, `panel-sftp`, `menu-*`: lista con scroll, menú del archivo frente al del fondo.
   - `pestanas`, `menu-pestana`: 12 pestañas visibles, ninguna aplastada; menú de clic derecho.
   - `ajustes-*`, `password-selector*`, `asistente`, `macros*`, `tuneles`, `espacios*`: nada cortado ni sin traducir.
   - Si sale «sin captura de pantalla (¿permiso de grabación…?)», la captura es la de la app y SwiftTerm no aparece:
     el terminal sólo se ve en `*.txt`/`*.resaltado.txt`. Dilo en el informe.
5. Si hiciste un `.dmg`: `tools/privacidad.sh --binario`. La versión sin `--binario` ya la ejecuta `./test.sh`.

## Si un caso falla
- «✗ … sin captura (¿la app no arranca?)»: mira `$OUT/<caso>-proceso.log` antes de tocar nada.
- «el terminal no muestra…» o «up/down sin resaltar»: compara `*.txt` con `*.resaltado.txt`. Si el texto está pero
  sin color, el fallo está en el resaltado o en el tema, no en el terminal.
- Un menú de clic derecho que no sale o que sale el equivocado: casi siempre son las coordenadas (`CLIC_*`) frente al
  tamaño de la ventana. No muevas el clic para que el test pase sin entender por qué ha cambiado la interfaz.
- NUNCA des por buena una captura que no has abierto, ni hagas el commit con un ✗ que no esté explicado en el informe.

## Casos inestables conocidos

- `pestañas` y `reabrir en sus ventanas` (SnapshotDrags) fallan a veces; en local, un reintento con
  `SOLO=pestanas` suele pasar. Si fallan dos veces seguidas, es un fallo real: no reintentes más, arréglalo.
- En la CI la pantalla es de 1024 px: clics y ventanas de los tests no deben tapar los puntos de arrastre ni caer fuera
  (pasó con `menu-fila-cortada`).
- Si el autor pide «sólo en GitHub», no abras la app ni la demo en su Mac: queda para `release.yml`.

## Informe antes del commit (formato que pide el autor)

```
Problemas detectados: …          (caso y captura, o «ninguno»)
Arreglos aplicados:   …          (archivo:línea)
./test.sh:            ✓ N tests  / ✗ cuáles
tools/privacidad.sh:  ✓ / ✗
Demo:                 ✓ todos los casos (capturas revisadas: …) / ✗ cuáles; inestables reintentados: …
```

No hagas el commit sin haber enseñado este informe.
