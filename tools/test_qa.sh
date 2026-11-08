#!/bin/bash
# El validador de la demo falla ante informes vacíos, truncados o con casos omitidos.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B - <<'PY'
import importlib.util
spec=importlib.util.spec_from_file_location('qa', 'tools/comprobar_pestanas.py')
qa=importlib.util.module_from_spec(spec); spec.loader.exec_module(qa)
casos=['✓ clic en otra pestaña', '✓ clic en la ✕', '✓ ventana movible=False', '✓ estrechas', '✓ pantalla completa', '✓ controles anclados a la derecha', '✓ herramientas fijas', '✓ botones de crear fijos', '✓ rellenar', '✓ ventana nueva', '✓ mover a otra ventana', '✓ arrastre a otra ventana', '✓ arrastre fuera', '✓ cerrar ventana', '✓ menús de ventana', '✓ reabrir en sus ventanas', '✓ foco: clic en la pestaña ya elegida', '✓ foco: clic derecho', '✓ foco: doble clic', '✓ la app siguió delante toda la batería'] + ['✓ arrastre']*100
valido='\n'.join(casos+['RESULTADO: comprobaciones=120 fallos=0'])
assert qa.comprobar(valido)
for malo in ('', valido.rsplit('\n',1)[0], valido.replace('120','0'), valido.replace('✓ arrastre','✗ arrastre',1), valido.replace('pantalla completa','omitida'), valido.replace('reabrir en sus ventanas','omitida'), valido.replace('foco: doble clic','omitida'), valido.replace('la app siguió delante','omitida')):
    assert not qa.comprobar(malo)
# (otra app delante: falla y lo dice, con la comprobación que no ha valido)
robado=valido.replace('✓ la app siguió delante toda la batería', '· otra app delante: Notas (lo que se compruebe hasta que vuelva ésta no vale)\n✗ foco: clic derecho en la pestaña, con su menú ya cerrado (KeyViewProxy)\n✗ la app dejó de estar delante (Notas)')
assert not qa.comprobar(robado)
assert [m[:3] for m in qa.motivos(robado)] == ['· o', '✗ f', '✗ l']
print('✓ QA: informes incompletos y casos fallidos bloquean la publicación')
PY
