#!/usr/bin/env python3
"""Series de precios para evaluar estrategias (Parte C del plan).

No hay datos gratuitos de 1 minuto de 2022-2024 para Apple, Netflix, AMD o
Tesla, asi que se usan dos fuentes:

  reales(): las dos series de practica (Meta y la anterior) y 3
            transformaciones de cada una:
              espejo   p' = min + max - p (invierte la tendencia)
              reversa  la serie al reves (invierte la tendencia, conserva
                       volatilidad y autocorrelacion)
              ambas    espejo de la reversa (misma tendencia, otro camino)
  sinteticas(n, semilla): series de 20.000 ticks generadas con un modelo
            simple de precio por minuto y normalizadas igual que las del
            curso (min-max a 100..255 y redondeo a entero):
              - 51 "dias" de 390 minutos con salto de apertura entre dias;
              - volatilidad por dia con agrupamiento (log-normal AR(1));
              - tendencia de la serie al azar (alcista, bajista o lateral);
              - ruido de microestructura (rebote entre bid y ask).
            Se aceptan solo series cuyas estadisticas caen en la banda de
            las reales: % de ticks sin cambio y probabilidad de rebote
            inmediato P(+1 | -1). Asi el set sintetico se parece en lo que
            importa a las series de practica, pero con otras tendencias y
            volatilidades.

Uso:
  python3 ref/series.py            estadisticas de las reales y de 12 sinteticas
  python3 ref/series.py --estres docs/mediciones/estres_serie.csv   escribir la serie de estres
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trader import leer_serie  # noqa: E402

RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NTICKS = 20000


def espejo(p):
    a = min(p) + max(p)
    return [a - x for x in p]


def reales():
    out = {}
    for nombre, ruta in (("meta", "tb/practica_meta.csv"), ("vieja", "tb/practica.csv")):
        p = leer_serie(os.path.join(RAIZ, ruta))
        out[nombre] = p
        out[nombre + "_espejo"] = espejo(p)
        out[nombre + "_reversa"] = p[::-1]
        out[nombre + "_ambas"] = espejo(p[::-1])
    return out


def normalizar(x, lo=100, hi=255):
    a, b = min(x), max(x)
    return [int(round(lo + (hi - lo) * (v - a) / (b - a))) for v in x]


def estadisticas(p):
    d = [b - a for a, b in zip(p, p[1:])]
    n = len(d)
    ceros = sum(1 for x in d if x == 0) / n
    tras = [d[i + 1] for i in range(n - 1) if d[i] == -1]
    rebote = sum(1 for x in tras if x == 1) / max(1, len(tras))
    sigue = sum(1 for x in tras if x == -1) / max(1, len(tras))
    bh = p[-1] / p[0] - 1
    return {"ceros": ceros, "rebote": rebote, "sigue": sigue, "bh": bh, "inicio": p[0], "fin": p[-1]}


def _candidata(rng):
    dias, por_dia = 52, 390
    mu = rng.choice((-1, 0, 1)) * rng.uniform(0.1, 0.6) * 1e-5 + rng.gauss(0, 2e-6)
    vol0 = rng.uniform(4e-4, 1.6e-3)
    gap = rng.uniform(2, 12)                     # salto de apertura, en sigmas por minuto
    micro = rng.uniform(0.0, 0.6)                # ruido bid-ask, en sigmas por minuto
    lv = 0.0
    x, s, out = 0.0, [], []
    for _ in range(dias):
        lv = 0.7 * lv + rng.gauss(0, 0.35)
        vol = vol0 * math.exp(lv)
        x += rng.gauss(0, gap * vol)
        for _ in range(por_dia):
            x += mu + rng.gauss(0, vol)
            s.append(x + rng.gauss(0, micro * vol))
    s = s[:NTICKS]
    return normalizar([math.exp(v) for v in s])


def sinteticas(n=48, semilla=2026, banda=None):
    """n series que pasan el filtro de realismo. Deterministas por semilla."""
    if banda is None:
        banda = {"ceros": (0.45, 0.70), "rebote": (0.20, 0.34), "sigue": (0.08, 0.17)}
    rng = random.Random(semilla)
    out, intentos = {}, 0
    while len(out) < n:
        intentos += 1
        p = _candidata(rng)
        e = estadisticas(p)
        if all(lo <= e[k] <= hi for k, (lo, hi) in banda.items()):
            out[f"sint{len(out):02d}"] = p
        if intentos > 200 * n:
            raise RuntimeError("el filtro de realismo rechaza casi todo: revisar el modelo")
    return out


def estres(n=NTICKS, semilla=7):
    """Serie de estres para validar trade.s (no es de practica ni se usa para
    elegir el algoritmo): oscila entre ~90 y 255 con periodo variable y ruido,
    para que V2 opere cientos de veces y el patrimonio llegue a >100.000
    (prueba los productos grandes de la comparacion sin signo)."""
    rng = random.Random(semilla)
    return [max(1, min(255, int(round(177.5 + 77.5 * math.sin(2 * math.pi * i / (150 + 50 * math.sin(i / 700)))
                                      + rng.gauss(0, 4))))) for i in range(n)]


def main():
    print(f"{'serie':16}{'ceros':>7}{'P(+1|-1)':>10}{'P(-1|-1)':>10}{'BH %':>8}{'inicio':>8}{'fin':>6}")
    for nombre, p in list(reales().items()) + list(sinteticas(12).items()):
        e = estadisticas(p)
        print(f"{nombre:16}{100 * e['ceros']:>6.1f}%{100 * e['rebote']:>9.1f}%{100 * e['sigue']:>9.1f}%"
              f"{100 * e['bh']:>7.1f}%{e['inicio']:>8}{e['fin']:>6}")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--estres":
        with open(sys.argv[2], "w") as f:
            f.write("tick,price\n" + "".join(f"{i},{x}\n" for i, x in enumerate(estres())))
    else:
        main()
