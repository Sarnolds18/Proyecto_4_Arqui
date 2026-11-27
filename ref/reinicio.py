#!/usr/bin/env python3
"""Compara reinicio.csv (sim/tb_reinicio.sv) con la referencia V2.

El tb manda la serie A, hace una pausa y manda la serie B; la maestra reinicia
su contabilidad al empezar B pero la placa no se toca. Con sw/trade_v2r.s:
  - si la pausa supera el timeout, el programa se reinicia solo: B tiene que
    coincidir con V2 recien creada (caja 10.000, 0 acciones, DECISION = 0);
  - si no (--sin-reinicio), B tiene que coincidir con V2 que sigue con la copia
    de caja y acciones de A (lo que pasa con trade.s sin apretar SW1).

Uso (desde la raiz del repo):
  python3 ref/reinicio.py reinicio.csv [--sin-reinicio] [-r 3]
"""

import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trader import V2, Mercado, MANTENER, precios_en_reset  # noqa: E402


def modelo(filas_a, filas_b, reinicia, ronda):
    """Decisiones esperadas tick a tick (mismo protocolo que simular())."""
    esp = []
    est, m, pend = V2(), Mercado(), MANTENER
    perdidos = precios_en_reset(ronda)
    for n, p in enumerate(filas_a):
        esp.append(("A", n, pend))
        m.ejecutar(pend, p)
        if n >= perdidos:
            pend = est.decidir(p)
    if reinicia:
        est, pend = V2(), MANTENER
    m = Mercado()
    for n, p in enumerate(filas_b):
        esp.append(("B", n, pend))
        m.ejecutar(pend, p)
        pend = est.decidir(p)
    return esp, m.w


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--sin-reinicio", action="store_true")
    ap.add_argument("-r", "--ronda", type=int, default=3)
    a = ap.parse_args()
    filas = list(csv.DictReader(open(a.csv)))
    pa = [int(f["precio"]) for f in filas if f["serie"] == "A"]
    pb = [int(f["precio"]) for f in filas if f["serie"] == "B"]
    esp, w_b = modelo(pa, pb, not a.sin_reinicio, a.ronda)
    malos = [(f["serie"], f["tick"], f["decision"], e[2])
             for f, e in zip(filas, esp) if int(f["decision"], 16) != e[2]]
    w_tb = int(filas[-1]["patrimonio"])
    modo = "sin reinicio" if a.sin_reinicio else "con reinicio"
    print(f"Serie A: {len(pa)} ticks, serie B: {len(pb)} ticks, modelo {modo}")
    print(f"Patrimonio final B: tb {w_tb}, referencia {w_b}")
    if malos:
        print(f"DISTINTAS: {len(malos)} decisiones, la primera {malos[0]} (serie, tick, tb, ref)")
        sys.exit(1)
    print(f"IGUALES: los {len(filas)} ticks coinciden con la referencia")


if __name__ == "__main__":
    main()
