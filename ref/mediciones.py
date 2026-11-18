#!/usr/bin/env python3
"""Analisis de las mediciones por tick (M3, L1, L5).

Lee lo que deja `make medir` en docs/mediciones/ (<nombre>_ticks.csv y
<nombre>_pc.csv) y calcula, sin estimar nada a mano:
  - IC, ciclos, CPI y tiempo por tick: promedio y peor caso, contra el
    presupuesto de cada ronda (ciclos = (T - 9,5 us) / periodo de reloj);
  - perfil por region del programa (etiquetas de su .s) y ley de Amdahl;
  - Ops/s: precios procesados por segundo y operaciones de ALU por segundo;
  - roofline de Espino: intensidad aritmetica del kernel (ops de ALU por
    byte de memoria) y los techos medidos (CPI minimo de ALU y de load/store).

Uso (desde la raiz del repo):
  python3 ref/mediciones.py sw_20000:sw/trade.s sma_20000:sw/trade_sma.s shift:sw/trade_shift.s
  python3 ref/mediciones.py ... --md docs/mediciones/resumen.md

Definiciones:
  - Ventana de un tick (sim/sonda_p4.sv): desde que el precio queda en PRICE
    (byte_done) hasta que el programa vuelve a leer STATUS. Incluye lo que
    tarda el bucle de espera en ver el precio.
  - Kernel = todo lo que no es el bucle de espera (etiqueta `espera` hasta el
    branch que sale de el).
  - Operacion util de ALU = instruccion de tipo OP, OP-IMM, LUI o branch (lo
    que usa la ALU). Bytes de memoria = 4 por cada lw/sw a RAM o MMIO.
"""

import argparse
import csv
import os
import statistics as st
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sw"))
import assembler  # noqa: E402

F_HZ = 25_000_000
SPI_NS = 9_500
PERIODOS_NS = {1: 10_000_000, 2: 1_000_000, 3: 100_000}
DIR = "docs/mediciones"


def presupuesto(ronda, f_hz=F_HZ):
    return (PERIODOS_NS[ronda] - SPI_NS) * f_hz // 1_000_000_000


def etiquetas(ruta_s):
    code = assembler.drop_comments(assembler.code_to_list(assembler.read_file(ruta_s)))
    return assembler.find_labels(code)


def opcodes(ruta_s):
    """pc -> clase de instruccion, decodificando el .hex del programa."""
    ruta_hex = ruta_s[:-2] + ".hex"
    clases = {}
    with open(ruta_hex) as f:
        for i, linea in enumerate(l.strip() for l in f if l.strip()):
            op = int(linea, 16) & 0x7F
            clases[4 * i] = {0x03: "load", 0x23: "store", 0x63: "branch", 0x6F: "jal",
                             0x13: "alu", 0x33: "alu", 0x37: "alu"}.get(op, "otra")
    return clases


def leer_ticks(nombre):
    with open(os.path.join(DIR, f"{nombre}_ticks.csv")) as f:
        return [(int(r["ciclos"]), int(r["ic"]), int(r["ciclos_decision"])) for r in csv.DictReader(f)]


def leer_pc(nombre):
    with open(os.path.join(DIR, f"{nombre}_pc.csv")) as f:
        return {int(r["pc"], 16): (int(r["ciclos"]), int(r["instrucciones"])) for r in csv.DictReader(f)}


def regiones(labels, pc_max):
    orden = sorted(labels.items(), key=lambda kv: kv[1])
    out = []
    for i, (n, a) in enumerate(orden):
        b = orden[i + 1][1] if i + 1 < len(orden) else pc_max + 4
        out.append((n, a, b))
    return out


def analizar(nombre, ruta_s):
    ticks = leer_ticks(nombre)
    pcs = leer_pc(nombre)
    labels = etiquetas(ruta_s)
    clases = opcodes(ruta_s)
    cic = [t[0] for t in ticks]
    ic = [t[1] for t in ticks]
    dec = [t[2] for t in ticks]
    cpi = [c / i for c, i in zip(cic, ic)]
    peor = max(range(len(ticks)), key=lambda k: cic[k])

    total_c = sum(c for c, _ in pcs.values())
    total_i = sum(i for _, i in pcs.values())
    reg = []
    for n, a, b in regiones(labels, max(pcs)):
        c = sum(pcs[p][0] for p in pcs if a <= p < b)
        i = sum(pcs[p][1] for p in pcs if a <= p < b)
        if c or i:
            reg.append((n, c, i))

    # Clases de instruccion ejecutadas en el kernel (fuera del bucle de espera)
    esp_a = labels["espera"]
    esp_b = esp_a + 12                      # lw STATUS, andi, beq
    kern = {p: v for p, v in pcs.items() if not (esp_a <= p < esp_b)}
    k_ciclos = sum(c for c, _ in kern.values())
    k_instr = sum(i for _, i in kern.values())
    por_clase = {}
    for p, (c, i) in kern.items():
        k = clases.get(p, "otra")
        pc_, pi_ = por_clase.get(k, (0, 0))
        por_clase[k] = (pc_ + c, pi_ + i)
    ops_alu = por_clase.get("alu", (0, 0))[1] + por_clase.get("branch", (0, 0))[1]
    mem_b = 4 * (por_clase.get("load", (0, 0))[1] + por_clase.get("store", (0, 0))[1])
    cpi_clase = {k: (c / i if i else 0) for k, (c, i) in por_clase.items()}

    burbujas = sum(cic) - total_c          # ciclos sin instruccion valida en ID (tras saltos)
    return {
        "nombre": nombre, "programa": ruta_s, "n": len(ticks), "burbujas": burbujas,
        "suma_ciclos": sum(cic), "suma_ic": sum(ic),
        "ciclos_prom": st.mean(cic), "ciclos_peor": max(cic), "ciclos_min": min(cic),
        "ic_prom": st.mean(ic), "ic_peor": max(ic), "ic_en_peor": ic[peor],
        "cpi_prom": sum(cic) / sum(ic), "cpi_peor_tick": cic[peor] / ic[peor],
        "dec_prom": st.mean(dec), "dec_peor": max(dec),
        "regiones": reg, "total_c": total_c, "total_i": total_i,
        "kernel_c": k_ciclos, "kernel_i": k_instr, "por_clase": por_clase, "cpi_clase": cpi_clase,
        "ops_alu": ops_alu, "mem_bytes": mem_b,
    }


def informe(rs):
    L = []
    L.append("# Mediciones por tick (generado por `ref/mediciones.py`)\n")
    L.append(f"Reloj {F_HZ / 1e6:.0f} MHz. Ventana por tick: `sim/sonda_p4.sv`. "
             f"Presupuesto (ciclos) = (T - 9,5 us) x f: ronda 1 = {presupuesto(1):,}, "
             f"ronda 2 = {presupuesto(2):,}, ronda 3 = {presupuesto(3):,}.\n".replace(",", "."))
    L.append("## IC, ciclos, CPI y tiempo por tick\n")
    L.append("| Variante | Ticks | IC prom | IC peor | Ciclos prom | Ciclos peor | CPI prom | t prom (us) | t peor (us) | Peor / T ronda 3 | Ciclos hasta ultima DECISION (peor) |")
    L.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for r in rs:
        tp, tw = r["ciclos_prom"] / F_HZ * 1e6, r["ciclos_peor"] / F_HZ * 1e6
        L.append(f"| {r['nombre']} | {r['n']} | {r['ic_prom']:.2f} | {r['ic_peor']} | {r['ciclos_prom']:.2f} | "
                 f"{r['ciclos_peor']} | {r['cpi_prom']:.3f} | {tp:.2f} | {tw:.2f} | "
                 f"{100 * r['ciclos_peor'] / presupuesto(3):.2f} % | {r['dec_peor']} |")
    L.append("")
    for r in rs:
        L.append(f"## Perfil por region: {r['nombre']} (`{r['programa']}`)\n")
        L.append("| Region (etiqueta) | Ciclos | % ciclos | Instrucciones | CPI |")
        L.append("|---|---:|---:|---:|---:|")
        for n, c, i in r["regiones"]:
            L.append(f"| `{n}` | {c} | {100 * c / r['suma_ciclos']:.1f} % | {i} | {c / i if i else 0:.2f} |")
        L.append(f"| burbujas tras saltos | {r['burbujas']} | {100 * r['burbujas'] / r['suma_ciclos']:.1f} % | 0 | - |")
        L.append("")
        L.append("CPI por clase de instruccion en el kernel (fuera del bucle de espera):\n")
        L.append("| Clase | Instrucciones | Ciclos | CPI |")
        L.append("|---|---:|---:|---:|")
        for k, (c, i) in sorted(r["por_clase"].items()):
            L.append(f"| {k} | {i} | {c} | {c / i if i else 0:.2f} |")
        L.append("")
    return "\n".join(L)


def region(r, nombre):
    for n, c, i in r["regiones"]:
        if n == nombre:
            return c / r["n"]
    return 0.0


def amdahl(base, var, reg_base, reg_var):
    """Speedup medido vs predicho por Amdahl al acelerar una region."""
    t_base = base["suma_ciclos"] / base["n"]
    c_b, c_v = sum(region(base, x) for x in reg_base), sum(region(var, x) for x in reg_var)
    p = c_b / t_base
    s = c_b / c_v if c_v else float("inf")
    pred = 1 / ((1 - p) + p / s)
    medido = t_base / (var["suma_ciclos"] / var["n"])
    return p, s, pred, medido, 1 / (1 - p)


def rendimiento(rs, luts):
    L = ["## Ops/s y roofline\n"]
    L.append("Operacion util (1): **precio procesado** (un tick completo). Capacidad = f / ciclos del peor tick.")
    L.append("Operacion util (2), para el roofline: **instruccion de ALU** (OP, OP-IMM, LUI o branch) del kernel, "
             "es decir, fuera del bucle de espera. Trafico: 4 bytes por cada lw/sw (RAM o MMIO).\n")
    L.append("| Variante | LC | Precios/s (peor tick) | Ops ALU por tick | Bytes por tick | Intensidad (ops/B) | Ciclos kernel por tick | Ops ALU/s en el kernel |")
    L.append("|---|---:|---:|---:|---:|---:|---:|---:|")
    for r in rs:
        ops_t, b_t, kc = r["ops_alu"] / r["n"], r["mem_bytes"] / r["n"], r["kernel_c"] / r["n"]
        L.append(f"| {r['nombre']} | {luts.get(r['nombre'], '-')} | {F_HZ / r['ciclos_peor']:,.0f} | {ops_t:.2f} | {b_t:.2f} | "
                 f"{ops_t / b_t:.3f} | {kc:.2f} | {ops_t / (kc / F_HZ) / 1e6:.2f} M |".replace(",", "."))
    r0 = rs[0]
    cpi_alu = r0["cpi_clase"].get("alu", 2)
    cpi_ld, cpi_st = r0["cpi_clase"].get("load", 3), r0["cpi_clase"].get("store", 2)
    pico = F_HZ / cpi_alu
    bw = 4 * F_HZ / cpi_ld
    L.append("")
    L.append(f"Techos de Espino (medidos con el CPI por clase): computo = f / CPI_ALU = {pico / 1e6:.2f} Mops/s "
             f"(CPI_ALU = {cpi_alu:.2f}); ancho de banda = 4 B x f / CPI_lw = {bw / 1e6:.2f} MB/s (CPI_lw = {cpi_ld:.2f}; "
             f"CPI_sw = {cpi_st:.2f}). Punto de quiebre = {pico / bw:.3f} ops/B: un kernel con menos intensidad queda "
             "limitado por memoria y uno con mas, por computo. Como Espino no solapa instrucciones, en la practica cada "
             "kernel queda bajo la linea t = n_alu * CPI_ALU + n_mem * CPI_mem.")
    return "\n".join(L) + "\n"


def main():
    global DIR
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("medidas", nargs="+", help="nombre:programa.s")
    ap.add_argument("--dir", default=DIR)
    ap.add_argument("--md", help="escribir el resumen en markdown")
    ap.add_argument("--luts", help="docs/variantes/variantes.txt para la columna LC")
    ap.add_argument("--amdahl", action="append", default=[],
                    help="base:variante:regiones_base:regiones_var (regiones separadas por +)")
    args = ap.parse_args()
    DIR = args.dir
    rs = [analizar(*m.split(":")) for m in args.medidas]
    texto = informe(rs)
    luts = {}
    if args.luts:
        for linea in open(args.luts):
            if not linea.startswith("#") and "/1280" in linea:
                c = linea.split()
                luts[c[0]] = next(x for x in c if x.endswith("/1280"))
    por = {r["nombre"]: r for r in rs}
    if args.amdahl:
        T = ["## Ley de Amdahl: speedup predicho vs medido\n",
             "| Base -> variante | Region acelerada | Fraccion p | Speedup de la region s | Predicho 1/((1-p)+p/s) | Medido | Limite 1/(1-p) |",
             "|---|---|---:|---:|---:|---:|---:|"]
        for a in args.amdahl:
            b, v, rb, rv = a.split(":")
            p, s_, pred, med, lim = amdahl(por[b], por[v], rb.split("+"), rv.split("+"))
            T.append(f"| {b} -> {v} | {rb} | {p:.3f} | {s_:.2f} | {pred:.3f} | {med:.3f} | {lim:.3f} |")
        texto += "\n" + "\n".join(T) + "\n"
    texto += "\n" + rendimiento(rs, luts)
    print(texto)
    if args.md:
        with open(args.md, "w") as f:
            f.write(texto + "\n")


if __name__ == "__main__":
    main()
