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


FAMILIAS = ("rango", "alza", "baja", "v", "v_inv", "pico_inicial", "caida_rebote", "escalones")


def _escenario(rng, familia):
    """Precio por minuto con la microestructura de _candidata y una forma de
    fondo segun la familia (en log-precio, antes de normalizar):
      rango         reversion lenta a un nivel (Ornstein-Uhlenbeck de dias)
      alza / baja   tendencia sostenida
      v / v_inv     baja y luego sube (o al reves), quiebre al azar
      pico_inicial  salto fuerte en los primeros dias y luego lateral (Netflix de la practica)
      caida_rebote  caida brusca a mitad de la serie y recuperacion parcial
      escalones     saltos de apertura grandes y raros (resultados trimestrales)
    """
    dias, por_dia = 52, 390
    n = dias * por_dia
    vol0 = rng.uniform(4e-4, 1.4e-3)
    micro = rng.uniform(0.0, 0.5)
    gap = rng.uniform(2, 8)
    amp = rng.uniform(0.15, 0.45)                 # amplitud de la forma de fondo (log)
    q = rng.uniform(0.3, 0.7)                     # punto de quiebre
    fondo = []
    for i in range(n):
        u = i / n
        if familia == "alza":
            f = amp * u
        elif familia == "baja":
            f = -amp * u
        elif familia == "v":
            f = -amp * (u / q if u < q else (1 - u) / (1 - q))
        elif familia == "v_inv":
            f = amp * (u / q if u < q else (1 - u) / (1 - q))
        elif familia == "pico_inicial":
            t0 = rng.uniform(0.02, 0.1) if i == 0 else t0  # noqa: F821
            f = amp * min(1.0, max(0.0, (u - t0) / 0.02)) * (1 - 0.4 * max(0.0, u - t0 - 0.03))
        elif familia == "caida_rebote":
            f = -amp * min(1.0, max(0.0, (u - q) / 0.01)) * (1 - 0.6 * max(0.0, u - q) / (1 - q))
        else:
            f = 0.0
        fondo.append(f)
    lv, x, out, ou, k = 0.0, 0.0, [], 0.0, 0
    for d in range(dias):
        lv = 0.7 * lv + rng.gauss(0, 0.35)
        vol = vol0 * math.exp(lv)
        salto = rng.gauss(0, gap * vol)
        if familia == "escalones" and rng.random() < 0.08:
            salto += rng.choice((-1, 1)) * rng.uniform(0.05, 0.15)
        x += salto
        for _ in range(por_dia):
            if familia == "rango":
                ou += -ou / (5 * por_dia) + rng.gauss(0, vol)
                nivel = ou
            else:
                x += rng.gauss(0, vol)
                nivel = x
            out.append(fondo[k] + nivel + rng.gauss(0, micro * vol))
            k += 1
    return normalizar([math.exp(v) for v in out[:NTICKS]])


def escenarios(por_familia=8, semilla=777, banda=None):
    """por_familia series de cada familia que pasan el filtro de realismo."""
    if banda is None:
        banda = {"ceros": (0.40, 0.75), "rebote": (0.18, 0.38), "sigue": (0.05, 0.18)}
    rng = random.Random(semilla)
    out = {}
    for fam in FAMILIAS:
        k = intentos = 0
        while k < por_familia:
            intentos += 1
            p = _escenario(rng, fam)
            e = estadisticas(p)
            if all(lo <= e[c] <= hi for c, (lo, hi) in banda.items()):
                out[f"esc_{fam}_{k}"] = p
                k += 1
            if intentos > 100 * por_familia:
                raise RuntimeError(f"filtro de realismo rechaza la familia {fam}")
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
