#!/usr/bin/env python3
"""Rechaza informes ausentes, truncados, vacíos o con casos omitidos/fallidos."""
import pathlib
import re
import sys


def comprobar(texto):
    lineas = texto.splitlines()
    resultado = re.fullmatch(r"RESULTADO: comprobaciones=(\d+) fallos=0", lineas[-1] if lineas else "")
    casos = [linea for linea in lineas if linea.startswith("✓ ")]
    return bool(resultado and int(resultado[1]) >= 120
                and int(resultado[1]) == len(casos)
                and not any(linea.startswith("✗ ") for linea in lineas)
                and all(any(nombre in linea for linea in casos)
                        for nombre in ("clic en otra pestaña", "clic en la ✕", "ventana movible=",
                                       "estrechas", "pantalla completa", "controles anclados a la derecha",
                                       "herramientas fijas", "botones de crear fijos", "rellenar",
                                       "ventana nueva", "mover a otra ventana", "arrastre a otra ventana",
                                       "arrastre fuera", "cerrar ventana", "menús de ventana",
                                       "reabrir en sus ventanas", "foco: clic en la pestaña ya elegida",
                                       "foco: clic derecho", "foco: doble clic",
                                       "la app siguió delante")))


def motivos(texto):
    """Lo que ha fallado, para verlo sin abrir el informe (y si otra app se puso delante, que lo invalida)."""
    return [linea for linea in texto.splitlines() if linea.startswith("✗ ") or linea.startswith("· otra app delante")]


if __name__ == "__main__":
    try:
        ruta = pathlib.Path(sys.argv[1])
        texto = ruta.read_text()
    except (IndexError, OSError):
        ruta, texto = None, ""
    # (hay dos baterías, con el tema de siempre y con el de cristal: el nombre del informe dice cuál)
    nombre = f"pestañas ({ruta.stem})" if ruta else "pestañas"
    if not comprobar(texto):
        print(f"✗ {nombre}: informe incompleto o interacción fallida")
        for linea in motivos(texto)[:12]:
            print(f"  {linea}")
        sys.exit(1)
    print(f"✓ {nombre}: clic, cierre y arrastre en ventana, rellenar, pantalla completa, pestañas estrechas y varias ventanas")
