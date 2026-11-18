#!/usr/bin/env python3
"""Banco de evaluacion de estrategias (Parte C, protocolo C.3).

Corre cada configuracion candidata sobre 56 series de 20.000 ticks:
  ajuste  24 sinteticas (sint00..23): aca se eligen parametros
  prueba  24 sinteticas (sint24..47): confirmacion fuera de muestra
  reales   8 series (Meta y la anterior, con espejo / reversa / ambas)
y reporta por conjunto: exceso sobre comprar y mantener (mediana, peor,
% de series en que gana) y un puntaje tipo competencia: en cada serie, la
fraccion de un pool de rivales a los que supera (comprar y mantener, no
operar, V0, V1, momentum 8/64, nivel lineal), promediada.

Uso (desde la raiz del repo):
  python3 ref/banco.py                         todas las familias
  python3 ref/banco.py -f nivel -f nivrev      solo esas familias
  python3 ref/banco.py --csv docs/informe/datos/banco.csv --top 40
  BANCO_RONDA=2 python3 ref/banco.py ...     grilla de la ronda 2 (refinamiento)
  BANCO_RONDA=4 python3 ref/banco.py ...     robustez: + 64 escenarios por familia y V2 como rival
"""

import argparse
import csv
import itertools
import multiprocessing as mp
import os
import statistics as st
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trader import simular, comprar_y_mantener, V0, V1, V2, CAJA0  # noqa: E402
from series import reales, sinteticas, escenarios, FAMILIAS  # noqa: E402
import estrategias as E  # noqa: E402


def grilla2():
    """Ronda 2: refinamiento de F10/F11 en la version implementable (NivelLote)."""
    g = []
    for forma, a, b, q, extra in itertools.product(("lineal", "cuadratica", "raiz"), (100, 110), (245, 255),
                                                   (10, 20, 30, 40), (0, 4, 8)):
        g.append(("lote", f"lote {forma} {a}-{b} q={q} extra={extra}",
                  (E.NivelLote, dict(forma=forma, a=a, b=b, q=q, extra=extra))))
    for forma, q, Nt, tend in itertools.product(("lineal", "cuadratica", "raiz"), (20, 40), (256, 1024), (8, 16, 32)):
        g.append(("lote_tend", f"lote {forma} 100-255 q={q} tend Nt={Nt} +{tend}",
                  (E.NivelLote, dict(forma=forma, q=q, extra=0, Nt=Nt, tend=tend))))
    for (cls, kw, n) in ((E.Nivel, dict(paso=40, forma="cuadratica"), "nivel 100-255 paso=40 cuadratica (r1)"),
                         (E.Nivel, dict(a=120, b=255, paso=10, forma="raiz"), "nivel 120-255 paso=10 raiz (r1)"),
                         (E.Reversion, dict(), "V1 rev N=16 U=3 lotes=2")):
        g.append(("ref", n, (cls, kw)))
    return g


def grilla3():
    """Ronda 3: version exacta sin division (NivelExacto), q y rango."""
    g = []
    for k, a, b, q in itertools.product((1, 2), (95, 100, 105, 110), (245, 250, 255, 260), (30, 40, 50, 63)):
        g.append(("exacto", f"exacto k={k} {a}-{b} q={q}", (E.NivelExacto, dict(a=a, b=b, q=q, k=k))))
    g.append(("ref", "lote cuadratica 100-255 q=40 extra=0 (r2)", (E.NivelLote, dict(forma="cuadratica", q=40, extra=0))))
    g.append(("ref", "V1 rev N=16 U=3 lotes=2", (E.Reversion, dict())))
    return g


def grilla4():
    """Ronda 4 (robustez, 18/11 tarde): V2 + reversion como desplazamiento del nivel (F12),
    lotes mas chicos, exponente 1 o 2. Se evalua tambien por familia de escenario."""
    g = []
    for q, e in itertools.product((10, 20, 30, 40), (1, 2)):
        g.append(("nivmr", f"nivmr q={q} e={e} k=0", (E.NivelMR, dict(q=q, e=e, k=0))))
        for k, N, U in itertools.product((10, 20, 40), (16, 64), (1, 3)):
            g.append(("nivmr", f"nivmr q={q} e={e} k={k} N={N} U={U}", (E.NivelMR, dict(q=q, e=e, k=k, N=N, U=U))))
    g.append(("ref", "V1 rev N=16 U=3 lotes=2", (E.Reversion, dict())))
    g.append(("ref", "rev N=8 U=5 lotes=2", (E.Reversion, dict(N=8, U=5, lotes=2))))
    return g


def grilla():
    """(familia, nombre, fabrica). Las fabricas se llaman en los procesos hijos."""
    g = []
    for N, U, L in itertools.product((8, 16, 32), (2, 3, 4, 5), (1, 2)):
        g.append(("rev", f"rev N={N} U={U} lotes={L}", (E.Reversion, dict(N=N, U=U, lotes=L))))
    for c, l in ((4, 32), (8, 64), (16, 128)):
        g.append(("mom", f"mom {c}/{l}", (E.Momentum, dict(Nc=c, Nl=l))))
    for a, b, paso, forma in itertools.product((100, 110, 120), (235, 245, 255), (5, 10, 20, 40),
                                               ("lineal", "cuadratica", "raiz")):
        g.append(("nivel", f"nivel {a}-{b} paso={paso} {forma}", (E.Nivel, dict(a=a, b=b, paso=paso, forma=forma))))
    for forma, N, U, extra, paso in itertools.product(("lineal", "raiz"), (16, 32), (2, 3, 4),
                                                      (8, 16, 32), (5, 10, 20)):
        g.append(("nivrev", f"nivrev {forma} N={N} U={U} extra={extra} paso={paso}",
                  (E.NivelReversion, dict(forma=forma, N=N, U=U, extra=extra, paso=paso))))
    for gap, pausa in itertools.product((4, 6, 10), (2, 5, 20)):
        g.append(("filtro", f"nivrev+gap lineal N=16 U=3 extra=16 paso=10 gap={gap} pausa={pausa}",
                  (E.NivelReversion, dict(N=16, U=3, extra=16, paso=10, gap=gap, pausa=pausa))))
    for N, er, base in itertools.product((16, 32, 64), (4, 6, 8, 10), (False, True)):
        g.append(("regimen", f"regimen N={N} er={er}/16 base_nivel={base}",
                  (E.Regimen, dict(N=N, er16=er, base_nivel=base))))
    for olv, costo in itertools.product((7, 9, 11), (0, 64, 256)):
        g.append(("sigue", f"sigue olvido={olv} costo={costo}", (E.SigueAlMejor, dict(olvido=olv, costo=costo))))
    return g


SERIES = None
RIVALES = None
GRILLA = None


RONDA = os.environ.get("BANCO_RONDA", "1")


def _cargar():
    global SERIES, RIVALES, GRILLA
    SERIES = {**sinteticas(48), **reales()}
    if RONDA == "4":
        SERIES.update(escenarios(8))
    GRILLA = {"2": grilla2, "3": grilla3, "4": grilla4}.get(RONDA, grilla)()
    rivales = [V0, V1, (E.Momentum, dict(Nc=8, Nl=64)), (E.Nivel, dict())]
    if RONDA == "4":
        rivales.append(V2)
    RIVALES = {}
    for n, p in SERIES.items():
        ws = [comprar_y_mantener(p)[0], CAJA0]
        for r in rivales:
            est = r[0](**r[1]) if isinstance(r, tuple) else r()
            ws.append(simular(est, p, 0)[1].w)
        RIVALES[n] = ws


def conjunto(nombre):
    if nombre.startswith("sint"):
        return "ajuste" if int(nombre[4:]) < 24 else "prueba"
    if nombre.startswith("esc_"):
        return "esc_ajuste" if int(nombre.rsplit("_", 1)[1]) < 4 else "esc_prueba"
    return "reales"


def familia(nombre):
    if nombre.startswith("esc_"):
        return nombre[4:].rsplit("_", 1)[0]
    return "sint" if nombre.startswith("sint") else "reales"


def evaluar(k):
    fam, nombre, (cls, kw) = GRILLA[k]
    por = {"ajuste": [], "prueba": [], "reales": [], "esc_ajuste": [], "esc_prueba": []}
    por_fam = {}
    for n, p in SERIES.items():
        _, m = simular(cls(**kw), p, 0)
        bh = RIVALES[n][0]
        puesto = sum(1.0 if m.w > r else 0.5 if m.w == r else 0.0 for r in RIVALES[n]) / len(RIVALES[n])
        por[conjunto(n)].append((m.w - bh, puesto, m.ordenes, m.max_dd, m.w))
        por_fam.setdefault(familia(n), []).append(puesto)
    por = {c: v for c, v in por.items() if v}
    res = {"familia": fam, "nombre": nombre, "fam": {f: st.mean(v) for f, v in por_fam.items()}}
    for c, v in por.items():
        ex = [x[0] for x in v]
        res[c] = {"mediana": st.median(ex), "media": st.mean(ex), "peor": min(ex),
                  "gana": sum(e > 0 for e in ex) / len(ex), "puesto": st.mean(x[1] for x in v),
                  "ordenes": st.mean(x[2] for x in v), "dd": st.mean(x[3] for x in v)}
    res["reales_w"] = [x[4] for x in por["reales"]]
    return res


def informe4(rs, args):
    """Ronda 4: orden por robustez = media del puesto por familia en los conjuntos
    de ajuste (sint ajuste + esc ajuste) + peor familia; se confirma en prueba."""
    for r in rs:
        r["robusto"] = 0.5 * (r["ajuste"]["puesto"] + r["esc_ajuste"]["puesto"]) + 0.5 * min(r["fam"].values())
    rs.sort(key=lambda r: -r["robusto"])
    fams = ["sint", "reales"] + list(FAMILIAS)
    print(f"{len(rs)} configuraciones, {len(SERIES)} series. Puesto (0-1) frente a rivales "
          "(comprar y mantener, no operar, V0, V1, momentum, nivel lineal, V2). Orden: robustez.")
    cab = f"{'configuracion':34}{'robusto':>8}{'aj':>6}{'pr':>6}{'escA':>6}{'escP':>6}" + "".join(f"{f[:7]:>8}" for f in fams)
    print(cab)
    for r in rs[:args.top]:
        print(f"{r['nombre'][:34]:34}{r['robusto']:8.3f}{r['ajuste']['puesto']:6.3f}{r['prueba']['puesto']:6.3f}"
              f"{r['esc_ajuste']['puesto']:6.3f}{r['esc_prueba']['puesto']:6.3f}" + "".join(f"{r['fam'][f]:8.3f}" for f in fams))
    if args.csv:
        os.makedirs(os.path.dirname(args.csv) or ".", exist_ok=True)
        with open(args.csv, "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["configuracion", "robusto"] + [f"{c}_{k}" for c in ("ajuste", "prueba", "esc_ajuste", "esc_prueba", "reales")
                                                        for k in ("puesto", "mediana", "peor", "gana")] + [f"fam_{f}" for f in fams])
            for r in rs:
                w.writerow([r["nombre"], round(r["robusto"], 4)] + [round(r[c][k], 4) for c in ("ajuste", "prueba", "esc_ajuste", "esc_prueba", "reales")
                                                                   for k in ("puesto", "mediana", "peor", "gana")] + [round(r["fam"][f], 4) for f in fams])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-f", "--familia", action="append", help="filtrar familias")
    ap.add_argument("--top", type=int, default=30)
    ap.add_argument("--csv")
    ap.add_argument("-j", type=int, default=os.cpu_count())
    args = ap.parse_args()

    _cargar()
    idx = [k for k, g in enumerate(GRILLA) if not args.familia or g[0] in args.familia]
    with mp.get_context("fork").Pool(args.j) as pool:
        rs = pool.map(evaluar, idx, chunksize=1)

    if RONDA == "4":
        informe4(rs, args)
        return
    # orden: puesto en ajuste (lo que se optimiza); se reporta prueba y reales
    rs.sort(key=lambda r: -r["ajuste"]["puesto"])
    print(f"{len(rs)} configuraciones, {len(SERIES)} series de 20.000 ticks. Orden: puesto en ajuste.")
    print(f"{'configuracion':58}| {'AJUSTE puesto med  peor gana':30}| {'PRUEBA puesto med  peor gana':30}| {'REALES puesto med peor gana ord':34}")
    for r in rs[:args.top]:
        f = lambda c: f"{r[c]['puesto']:.3f} {r[c]['mediana']:>5.0f} {r[c]['peor']:>6.0f} {100 * r[c]['gana']:>3.0f}%"
        print(f"{r['nombre'][:58]:58}| {f('ajuste'):30}| {f('prueba'):30}| {f('reales'):27}{r['reales']['ordenes']:>6.0f}")
    if args.csv:
        os.makedirs(os.path.dirname(args.csv) or ".", exist_ok=True)
        with open(args.csv, "w", newline="") as fh:
            w = csv.writer(fh)
            cols = ["puesto", "mediana", "media", "peor", "gana", "ordenes", "dd"]
            w.writerow(["familia", "configuracion"] + [f"{c}_{k}" for c in ("ajuste", "prueba", "reales") for k in cols]
                       + [f"W_{n}" for n in SERIES if conjunto(n) == "reales"])
            for r in rs:
                w.writerow([r["familia"], r["nombre"]] + [round(r[c][k], 4) for c in ("ajuste", "prueba", "reales") for k in cols]
                           + r["reales_w"])


if __name__ == "__main__":
    main()
