#!/bin/bash
# El validador de la demo falla ante informes vacíos, truncados o con casos omitidos.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B - <<'PY'
import importlib.util
spec=importlib.util.spec_from_file_location('qa', 'tools/comprobar_pestanas.py')
qa=importlib.util.module_from_spec(spec); spec.loader.exec_module(qa)
casos=['✓ clic en otra pestaña', '✓ clic en la ✕', '✓ ventana movible=False', '✓ estrechas', '✓ pantalla completa', '✓ controles anclados a la derecha', '✓ herramientas fijas', '✓ botones de crear fijos'] + ['✓ arrastre']*112
valido='\n'.join(casos+['RESULTADO: comprobaciones=120 fallos=0'])
assert qa.comprobar(valido)
for malo in ('', valido.rsplit('\n',1)[0], valido.replace('120','0'), valido.replace('✓ arrastre','✗ arrastre',1), valido.replace('pantalla completa','omitida')):
    assert not qa.comprobar(malo)
print('✓ QA: informes incompletos y casos fallidos bloquean la publicación')
PY
