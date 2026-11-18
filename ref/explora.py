#!/usr/bin/env python3
"""Exploracion de estrategias (S2) con validacion por tramos.

Evalua familias de estrategias enteras (implementables en Espino) sobre:
  - la serie de practica vigente (tb/practica_meta.csv) y la anterior
    (tb/practica.csv);
  - sus espejos (p' = min + max - p), que convierten una tendencia al alza en
    una a la baja: una estrategia robusta no deberia depender de la tendencia;
  - tramos de L ticks sin solapamiento (por defecto 2000), porque las series
    de la competencia son periodos ocultos de largo desconocido.

Metrica principal: exceso sobre comprar y mantener (W - W_bh) en cada tramo,
que es contra lo que se puntua la competencia. Se reportan la media, el peor
tramo y la fraccion de tramos en que se gana a comprar y mantener.

Uso (desde la raiz del repo):
  python3 ref/explora.py                  grilla completa, tabla de las mejores
  python3 ref/explora.py -L 5000          tramos de 5000 ticks
  python3 ref/explora.py --csv docs/informe/datos/exploracion.csv
"""

import argparse
import csv
import itertools
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trader import Mercado, leer_serie, simular, comprar_y_mantener  # noqa: E402

COMPRAR, VENDER, MANTENER = 0x40, 0x80, 0x00


# ---------------------------------------------------------------------------
# Familias de estrategias. Todas con aritmetica entera; N potencia de 2 para
# que la media sea una comparacion N*p vs suma (sin dividir).
# ---------------------------------------------------------------------------
class ReversionSMA:
    """V0 generalizada: posicion 0/1 (1 = todo lo que alcance, hasta 2 ordenes
    de 63), compra si p < media - U, vende si p > media + U."""
    def __init__(self, N, U, lotes=1):
        self.N, self.U, self.lotes = N, U, lotes
        self.buf, self.suma, self.n, self.idx = [0] * N, 0, 0, 0
        self.lote = 0          # lotes comprados (0..lotes)

    def _media(self, p):
        if self.n < self.N:
            self.buf[self.n] = p; self.suma += p; self.n += 1
            return self.n == self.N
        self.suma += p - self.buf[self.idx]; self.buf[self.idx] = p
        self.idx = (self.idx + 1) % self.N
        return True

    def decidir(self, p):
        if not self._media(p):
            return MANTENER
        x, b = self.N * p, self.N * self.U
        if self.lote < self.lotes and x + b < self.suma:
            self.lote += 1; return COMPRAR | 63
        if self.lote > 0 and x > self.suma + b:
            self.lote -= 1; return VENDER | 63
        return MANTENER


class ReversionEMA:
    """Reversion a la media sobre una EMA con alfa = 2^-k, en punto fijo:
    S = 2^k * EMA (entero), S += p - S >> k. Compra si 2^k p + 2^k U < S,
    vende si 2^k p > S + 2^k U. El shift a la derecha es la operacion que
    Espino no tiene (motiva el shifter). Posicion 0/1, hasta 'lotes' ordenes."""
    def __init__(self, k, U, lotes=1):
        self.k, self.U, self.lotes = k, U, lotes
        self.S = None
        self.lote = 0

    def decidir(self, p):
        if self.S is None:
            self.S = p << self.k
            return MANTENER
        self.S += p - (self.S >> self.k)
        x, b = p << self.k, self.U << self.k
        if self.lote < self.lotes and x + b < self.S:
            self.lote += 1; return COMPRAR | 63
        if self.lote > 0 and x > self.S + b:
            self.lote -= 1; return VENDER | 63
        return MANTENER


class Momentum:
    """Cruce de medias: comprado si SMA corta > SMA larga + U, en caja si
    SMA corta < SMA larga - U (con N potencias de 2)."""
    def __init__(self, Nc, Nl, U):
        self.c, self.l, self.U = ReversionSMA(Nc, 0), ReversionSMA(Nl, 0), U
        self.pos = 0

    def decidir(self, p):
        a, b = self.c._media(p), self.l._media(p)
        if not (a and b):
            return MANTENER
        xc, xl = self.c.suma * self.l.N, self.l.suma * self.c.N   # mismo denominador
        u = self.U * self.c.N * self.l.N
        if self.pos == 0 and xc > xl + u:
            self.pos = 1; return COMPRAR | 63
        if self.pos == 1 and xc + u < xl:
            self.pos = 0; return VENDER | 63
        return MANTENER


class Hibrida:
    """Reversion a la media con filtro de tendencia: por defecto comprado
    (como comprar y mantener). Vende si p > EMA_corta + U (sobre-extension) y
    recompra si p < EMA_corta - U o si se cumplen 'espera' ticks fuera."""
    def __init__(self, k, U, espera):
        self.mr = ReversionEMA(k, U)
        self.espera = espera
        self.fuera = 0
        self.pos = 0

    def decidir(self, p):
        mr = self.mr
        if mr.S is None:
            mr.S = p << mr.k
            self.pos = 1
            return COMPRAR | 63
        mr.S += p - (mr.S >> mr.k)
        x, b = p << mr.k, mr.U << mr.k
        if self.pos == 1:
            if x > mr.S + b:
                self.pos, self.fuera = 0, 0
                return VENDER | 63
            return MANTENER
        self.fuera += 1
        if x + b < mr.S or self.fuera >= self.espera:
            self.pos = 1
            return COMPRAR | 63
        return MANTENER


def grilla():
    for N, U, L in itertools.product((4, 8, 16, 32, 64), (0, 1, 2, 3, 4, 6, 8), (1, 2)):
        yield f"sma N={N} U={U} lotes={L}", (lambda N=N, U=U, L=L: ReversionSMA(N, U, L))
    for k, U, L in itertools.product((1, 2, 3, 4, 5, 6), (0, 1, 2, 3, 4, 6, 8), (1, 2)):
        yield f"ema k={k} U={U} lotes={L}", (lambda k=k, U=U, L=L: ReversionEMA(k, U, L))
    for Nc, Nl, U in itertools.product((2, 4, 8), (16, 32, 64, 128), (0, 1, 2)):
        if Nc < Nl:
            yield f"momentum {Nc}/{Nl} U={U}", (lambda a=Nc, b=Nl, U=U: Momentum(a, b, U))
    for k, U, e in itertools.product((2, 3, 4, 5), (1, 2, 3, 4, 6), (16, 64, 256)):
        yield f"hibrida k={k} U={U} espera={e}", (lambda k=k, U=U, e=e: Hibrida(k, U, e))


def espejo(precios):
    a = min(precios) + max(precios)
    return [a - p for p in precios]


def tramos(precios, L):
    return [precios[i:i + L] for i in range(0, len(precios) - L + 1, L)]


def evaluar(fabrica, series, L):
    """Exceso sobre comprar y mantener en cada tramo de cada serie."""
    excesos, completos = [], {}
    for nombre, precios in series.items():
        for t in tramos(precios, L):
            _, m = simular(fabrica(), t, 0)
            excesos.append(m.w - comprar_y_mantener(t)[0])
        _, m = simular(fabrica(), precios, 0)
        completos[nombre] = (m.w, m.ordenes, m.max_dd)
    return excesos, completos


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-L", type=int, default=2000, help="largo de cada tramo")
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--csv", help="guardar todas las configuraciones")
    args = ap.parse_args()

    meta, vieja = leer_serie("tb/practica_meta.csv"), leer_serie("tb/practica.csv")
    series = {"meta": meta, "meta_espejo": espejo(meta),
              "vieja": vieja, "vieja_espejo": espejo(vieja)}

    filas = []
    for nombre, fab in grilla():
        ex, comp = evaluar(fab, series, args.L)
        ganados = sum(e > 0 for e in ex) / len(ex)
        filas.append((nombre, sum(ex) / len(ex), min(ex), ganados,
                      comp["meta"][0], comp["meta"][1], comp["meta"][2],
                      comp["meta_espejo"][0], comp["vieja"][0], comp["vieja_espejo"][0]))

    filas.sort(key=lambda f: -f[1])
    print(f"Tramos de {args.L} ticks, {len(series)} series. Exceso = W - W(comprar y mantener).")
    print(f"{'estrategia':30}{'exc medio':>10}{'peor':>8}{'gana%':>7}"
          f"{'W meta':>8}{'ord':>6}{'dd':>6}{'W meta_e':>9}{'W vieja':>8}{'W vieja_e':>10}")
    for f in filas[:args.top]:
        print(f"{f[0]:30}{f[1]:>10.0f}{f[2]:>8}{100 * f[3]:>6.0f}%"
              f"{f[4]:>8}{f[5]:>6}{f[6]:>6}{f[7]:>9}{f[8]:>8}{f[9]:>10}")
    bh = {k: comprar_y_mantener(v)[0] for k, v in series.items()}
    print("comprar y mantener (serie completa):", bh)

    if args.csv:
        os.makedirs(os.path.dirname(args.csv) or ".", exist_ok=True)
        with open(args.csv, "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["estrategia", "exceso_medio", "peor_tramo", "frac_gana", "W_meta",
                        "ordenes_meta", "maxdd_meta", "W_meta_espejo", "W_vieja", "W_vieja_espejo"])
            w.writerows(filas)


if __name__ == "__main__":
    main()
