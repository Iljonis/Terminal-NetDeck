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
                                       "herramientas fijas", "botones de crear fijos")))


if __name__ == "__main__":
    try:
        texto = pathlib.Path(sys.argv[1]).read_text()
    except (IndexError, OSError):
        texto = ""
    if not comprobar(texto):
        print("✗ pestañas: informe incompleto o interacción fallida")
        sys.exit(1)
    print("✓ pestañas: clic, cierre y arrastre en ventana, pantalla completa y pestañas estrechas")
