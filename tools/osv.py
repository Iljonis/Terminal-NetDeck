#!/usr/bin/env python3
# tools/osv.py — las dependencias de SwiftPM contra OSV.dev, sin dar por buena una comprobación incompleta
# (tools/seguridad_cron.sh; lo prueba tools/test_osv.sh sin red).
#
#   osv.py consulta Package.resolved           → la consulta de querybatch (JSON) por la salida
#   osv.py informe consulta.json respuesta.json → una línea por dependencia con vulnerabilidades; sale con 0 si la
#                                                 respuesta está completa y bien formada (aunque haya vulnerables)
#
# Cualquier cosa rara (un Package.resolved que no se entiende, una dependencia sin versión que no se puede consultar,
# una respuesta sin «results», con otro número de resultados o con campos que no son lo esperado) sale con 2 y dice
# por qué: así nunca figura como «sin vulnerabilidades» lo que no se ha podido comprobar.
import json
import sys


def fail(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def consulta(path):
    try:
        with open(path, encoding="utf-8") as f:
            pins = json.load(f)["pins"]
    except (OSError, ValueError, KeyError, TypeError) as e:
        fail(f"no se entiende {path}: {e}")
    if not isinstance(pins, list) or not pins:
        fail(f"{path} no lista ninguna dependencia")
    q = []
    for p in pins:
        try:
            loc = p["location"].removesuffix(".git").replace("https://", "")
            state = p["state"]
        except (KeyError, TypeError, AttributeError) as e:
            fail(f"dependencia sin ubicación o estado en {path}: {e}")
        v = state.get("version") if isinstance(state, dict) else None
        if not isinstance(v, str) or not v:
            fail(f"{loc} no tiene versión (rama o revisión): OSV no la puede comprobar")
        q.append({"package": {"ecosystem": "SwiftURL", "name": loc}, "version": v})
    print(json.dumps({"queries": q}))


def informe(consulta_path, respuesta_path):
    try:
        with open(consulta_path, encoding="utf-8") as f:
            q = json.load(f)["queries"]
        with open(respuesta_path, encoding="utf-8") as f:
            r = json.load(f)
    except (OSError, ValueError, KeyError, TypeError) as e:
        fail(f"no se puede leer la consulta o la respuesta: {e}")
    if not isinstance(r, dict) or not isinstance(r.get("results"), list):
        fail("la respuesta de OSV no trae «results»")
    results = r["results"]
    if len(results) != len(q):
        fail(f"OSV ha contestado {len(results)} de {len(q)} consultas")
    for qq, rr in zip(q, results):
        name = f'{qq["package"]["name"]} {qq["version"]}'
        if not isinstance(rr, dict):
            fail(f"respuesta de OSV no válida para {name}")
        vulns = rr.get("vulns", [])
        if not isinstance(vulns, list) or any(not isinstance(v, dict) or not isinstance(v.get("id"), str) for v in vulns):
            fail(f"respuesta de OSV no válida para {name}")
        if rr.get("next_page_token"):
            fail(f"OSV no ha dado todas las vulnerabilidades de {name} (hay más páginas)")
        if vulns:
            print(f'{name}: ' + ", ".join(v["id"] for v in vulns))


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == "consulta":
        consulta(a[1])
    elif len(a) == 3 and a[0] == "informe":
        informe(a[1], a[2])
    else:
        fail("uso: osv.py consulta Package.resolved | osv.py informe consulta.json respuesta.json")
