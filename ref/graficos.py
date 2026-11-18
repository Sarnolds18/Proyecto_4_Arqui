#!/usr/bin/env python3
"""Graficos del informe (docs/informe/fig/). Todo sale de datos del repo.

  1_precio_patrimonio.png  serie Meta y patrimonio de V2, V1 y comprar y mantener
  2_exceso_por_serie.png   exceso sobre comprar y mantener de V2 y V1 en las 56 series
  3_roofline.png           roofline de Espino con los kernels medidos

Uso (desde la raiz del repo): python3 ref/graficos.py
"""

import csv
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trader import V1, V2, leer_serie, simular, comprar_y_mantener  # noqa: E402
from series import reales, sinteticas  # noqa: E402
import mediciones  # noqa: E402

OUT = "docs/informe/fig"
AZUL, NARANJA, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
GRIS, TINTA, TINTA2, GRILLA = "#8a8984", "#0b0b0b", "#52514e", "#e6e5e0"

plt.rcParams.update({
    "font.size": 10, "axes.edgecolor": GRILLA, "axes.labelcolor": TINTA2,
    "xtick.color": TINTA2, "ytick.color": TINTA2, "axes.grid": True,
    "grid.color": GRILLA, "grid.linewidth": 0.8, "axes.spines.top": False,
    "axes.spines.right": False, "figure.dpi": 150, "savefig.bbox": "tight",
    "lines.linewidth": 1.6,
})


def patrimonio(est, p):
    filas, m = simular(est, p, 0)
    return [f[5] for f in filas], m


def fig_precio_patrimonio():
    p = leer_serie("tb/practica_meta.csv")
    w2, m2 = patrimonio(V2(), p)
    w1, m1 = patrimonio(V1(), p)
    q = (10000 - 5) // p[0]
    wbh = [10000 - 5 - q * p[0] + q * x for x in p]
    fig, (a, b) = plt.subplots(2, 1, figsize=(8, 5.4), sharex=True, gridspec_kw={"height_ratios": [1, 1.4]})
    a.plot(p, color=TINTA2, linewidth=0.8)
    a.set_ylabel("precio (100-255)")
    a.set_title("Serie de practica Meta (20.000 ticks)", loc="left", color=TINTA, fontsize=11)
    for serie, col, nom, m in ((w2, AZUL, "V2", m2), (w1, NARANJA, "V1", m1), (wbh, GRIS, "comprar y mantener", None)):
        b.plot(serie, color=col, linewidth=1.6 if nom != "comprar y mantener" else 1.2,
               linestyle="-" if nom != "comprar y mantener" else "--", label=nom)
        b.annotate(f"{nom}: {serie[-1]:,}".replace(",", "."), (len(serie) - 1, serie[-1]), xytext=(6, 0),
                   textcoords="offset points", va="center", color=TINTA, fontsize=9)
    b.axhline(10000, color=GRILLA, linewidth=1)
    b.set_ylabel("patrimonio ($)")
    b.set_xlabel("tick")
    b.legend(loc="upper left", frameon=False)
    b.set_title("Patrimonio (contabilidad del testbench, sin los 2 precios del reset)", loc="left", color=TINTA, fontsize=11)
    fig.savefig(f"{OUT}/1_precio_patrimonio.png")
    plt.close(fig)


def fig_exceso():
    S = {**sinteticas(48), **reales()}
    nombres = list(S)
    ex2 = [patrimonio(V2(), S[n])[1].w - comprar_y_mantener(S[n])[0] for n in nombres]
    ex1 = [patrimonio(V1(), S[n])[1].w - comprar_y_mantener(S[n])[0] for n in nombres]
    orden = sorted(range(len(nombres)), key=lambda k: ex2[k])
    fig, ax = plt.subplots(figsize=(8, 4))
    x = range(len(orden))
    ax.axhline(0, color=TINTA2, linewidth=1)
    reales_ = [i for i, k in enumerate(orden) if not nombres[k].startswith("sint")]
    sint_ = [i for i, k in enumerate(orden) if nombres[k].startswith("sint")]
    for idx, mk, sz, tag in ((sint_, "o", 20, "sintetica"), (reales_, "D", 34, "real")):
        ax.scatter(idx, [ex1[orden[i]] for i in idx], s=sz, marker=mk, color=NARANJA, zorder=3,
                   edgecolors="white", linewidths=0.6, label=f"V1, serie {tag}")
        ax.scatter(idx, [ex2[orden[i]] for i in idx], s=sz, marker=mk, color=AZUL, zorder=4,
                   edgecolors="white", linewidths=0.6, label=f"V2, serie {tag}")
    gana2 = sum(e > 0 for e in ex2)
    gana1 = sum(e > 0 for e in ex1)
    ax.set_title(f"Exceso sobre comprar y mantener en 56 series de 20.000 ticks (V2 gana en {gana2}, V1 en {gana1})",
                 loc="left", color=TINTA, fontsize=11)
    ax.set_ylabel("W final - W comprar y mantener ($)")
    ax.set_xlabel("series ordenadas por el exceso de V2 (48 sinteticas + 8 reales)")
    ax.legend(frameon=False, loc="upper left", ncol=2, fontsize=8)
    fig.savefig(f"{OUT}/2_exceso_por_serie.png")
    plt.close(fig)


def fig_roofline(medidas):
    rs = [mediciones.analizar(n, s) for n, s, _ in medidas]
    r0 = rs[0]
    f = mediciones.F_HZ
    pico = f / r0["cpi_clase"]["alu"]
    bw = 4 * f / r0["cpi_clase"]["load"]
    fig, ax = plt.subplots(figsize=(7, 4.4))
    xs = [0.05 * 1.1 ** i for i in range(80)]
    ax.plot(xs, [min(pico, bw * x) / 1e6 for x in xs], color=TINTA2, linewidth=1.6)
    ax.annotate(f"computo: {pico / 1e6:.1f} Mops/s (CPI ALU = 2)", (0.6, pico / 1e6), xytext=(0, 6),
                textcoords="offset points", ha="left", fontsize=8, color=TINTA2)
    ax.annotate(f"memoria: {bw / 1e6:.1f} MB/s (CPI lw = 3)", (0.08, bw * 0.08 / 1e6), xytext=(4, 0),
                textcoords="offset points", fontsize=8, color=TINTA2, rotation=27)
    for r, (_, _, (col, etiqueta)) in zip(rs, medidas):
        ops, by, kc = r["ops_alu"], r["mem_bytes"], r["kernel_c"]
        I, P = ops / by, ops / (kc / f) / 1e6
        ax.scatter([I], [P], s=60, color=col, edgecolors="white", linewidths=1.5, zorder=4)
        ax.annotate(f"{etiqueta}\n({I:.2f} ops/B, {P:.1f} Mops/s)", (I, P), xytext=(-8 if I > 10 else 8, -14 if I > 10 else -4),
                    textcoords="offset points", fontsize=8, color=TINTA, ha="right" if I > 10 else "left")
    ax.set_xscale("log")
    ax.set_yscale("log")
    from matplotlib.ticker import FuncFormatter, FixedLocator
    ax.yaxis.set_major_locator(FixedLocator([2, 4, 6, 8, 10, 12.5]))
    ax.yaxis.set_minor_locator(FixedLocator([]))
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:g}"))
    ax.xaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:g}"))
    ax.set_xlabel("intensidad aritmetica (ops de ALU por byte de lw/sw)")
    ax.set_ylabel("rendimiento (Mops/s)")
    ax.set_title("Roofline de Espino a 25 MHz (techos medidos con el CPI por clase)", loc="left", color=TINTA, fontsize=11)
    fig.savefig(f"{OUT}/3_roofline.png")
    plt.close(fig)


def main():
    os.makedirs(OUT, exist_ok=True)
    fig_precio_patrimonio()
    fig_exceso()
    medidas = [("v2_estres", "sw/trade.s", (AZUL, "V2 solo SW")),
               ("mul_estres", "sw/trade_mul.s", (AQUA, "V2 + multiplicador (D)")),
               ("v1_20000", "sw/trade_v1.s", (NARANJA, "V1 solo SW"))]
    medidas = [m for m in medidas if os.path.exists(f"docs/mediciones/{m[0]}_ticks.csv")]
    fig_roofline(medidas)
    print("figuras en", OUT, ":", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
