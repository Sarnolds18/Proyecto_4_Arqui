#!/usr/bin/env python3
"""Tablas del informe 4.1 (salida en docs/informe/datos/resumen_algoritmo.txt).

Uso (desde la raiz del repo): python3 ref/resumen_algoritmo.py > docs/informe/datos/resumen_algoritmo.txt
"""
import os
import sys
import statistics as st

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trader import V0, V1, V2, Mantener, simular, comprar_y_mantener, leer_serie, CAJA0, COMISION  # noqa: E402
from series import reales, sinteticas  # noqa: E402

print("# Generado por ref/resumen_algoritmo.py")
print("\n## 1. Serie de practica Meta completa (20.000 ticks, sin precios en reset = placa real)\n")
p = leer_serie("tb/practica_meta.csv")
print("| Estrategia | Patrimonio final | Ordenes | Comisiones | Perdida maxima |")
print("|---|---:|---:|---:|---:|")
for nom, cls in (("V2 (final)", V2), ("V1", V1), ("V0 (kit)", V0)):
    _, m = simular(cls(), p, 0)
    print(f"| {nom} | {m.w} | {m.ordenes} | {m.ordenes * COMISION} | {m.max_dd} |")
print(f"| No operar | {CAJA0} | 0 | 0 | 0 |")
w, o, c, dd = comprar_y_mantener(p)
print(f"| Comprar y mantener | {w} | {o} | {c} | {dd} |")

print("\n## 2. Las 8 series reales (Meta y la anterior con espejo, reversa y ambas)\n")
print("| Serie | Comprar y mantener | V2 | ordenes V2 | perdida max V2 | V1 | V0 |")
print("|---|---:|---:|---:|---:|---:|---:|")
for n, s in reales().items():
    _, m2 = simular(V2(), s, 0)
    _, m1 = simular(V1(), s, 0)
    _, m0 = simular(V0(), s, 0)
    print(f"| {n} | {comprar_y_mantener(s)[0]} | {m2.w} | {m2.ordenes} | {m2.max_dd} | {m1.w} | {m0.w} |")

print("\n## 3. Exceso sobre comprar y mantener por conjunto (W - W_bh)\n")
S = {**sinteticas(48), **reales()}
conj = {"ajuste (sint00-23)": [n for n in S if n.startswith("sint") and int(n[4:]) < 24],
        "prueba (sint24-47)": [n for n in S if n.startswith("sint") and int(n[4:]) >= 24],
        "reales (8)": [n for n in S if not n.startswith("sint")]}
print("| Conjunto | Estrategia | Mediana | Media | Peor | Mejor | Gana a comprar y mantener | Ordenes (media) |")
print("|---|---|---:|---:|---:|---:|---:|---:|")
for c, ns in conj.items():
    for nom, cls in (("V2", V2), ("V1", V1), ("V0", V0)):
        ex, ords = [], []
        for n in ns:
            _, m = simular(cls(), S[n], 0)
            ex.append(m.w - comprar_y_mantener(S[n])[0])
            ords.append(m.ordenes)
        print(f"| {c} | {nom} | {st.median(ex):.0f} | {st.mean(ex):.0f} | {min(ex)} | {max(ex)} | "
              f"{sum(e > 0 for e in ex)}/{len(ex)} | {st.mean(ords):.0f} |")
