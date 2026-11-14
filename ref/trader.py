#!/usr/bin/env python3
"""Referencia del Proyecto 4 (Pochoco Trader).

Reproduce en Python lo que hace tb/tb_proyecto_4.sv (la FPGA maestra):
  - mismo protocolo: la decision que el programa escribe despues de leer
    p[n] sale en la transaccion n+1 y se ejecuta al precio p[n+1]; en el
    tick 0 sale el valor de reset de DECISION (0x00, mantener);
  - misma contabilidad: compra recortada a (caja - C) / p, venta recortada a
    las acciones que se tienen, comision C por orden ejecutada, patrimonio
    W = caja + acciones * p, perdida maxima desde el peak;
  - mismas referencias: no operar y comprar y mantener (formula del tb:
    compra (CAJA0 - C) / p[0] acciones al precio p[0]);
  - mismo arranque: el tb manda el primer precio a los 4 us, pero el reset
    de encendido de pochoco_soc dura 2^12 ciclos (163,84 us) y tambien
    tiene en reset al esclavo SPI, asi que los precios que llegan antes se
    pierden sin que el programa los vea (ver precios_en_reset). En la placa
    real no pasa: la Go Board ya esta configurada cuando parte la maestra.

Ademas define las estrategias en aritmetica entera exacta, para que trade.s
tome exactamente las mismas decisiones (ver la estrategia "v0").

Uso (desde la raiz del repo):
  python3 ref/trader.py                              v0, 2000 ticks
  python3 ref/trader.py -e v0 -n 20000               serie completa
  python3 ref/trader.py -e v0 --compara decisiones.csv   (misma RONDA que el tb)
  python3 ref/trader.py -e v0 -r 1 -n 50 --compara decisiones.csv
  python3 ref/trader.py -e v0 --csv sim/build/ref_v0.csv
"""

import argparse
import csv
import sys

CAJA0 = 10000
COMISION = 5

# Tiempos del tb (ns) para saber que precios llegan durante el reset.
PERIODO_NS = {1: 10_000_000, 2: 1_000_000, 3: 100_000}
INICIO_NS = 4_000                 # #4000 antes del primer tick
PRECIO_LISTO_NS = 9_000           # CS_n baja + 1000 ns + 8 bits de 1000 ns
POR_NS = (1 << 12) * 40           # 4096 ciclos de 40 ns (pochoco_soc.v)

MANTENER = 0x00
COMPRAR = 0x40   # bits [7:6] = 01
VENDER = 0x80    # bits [7:6] = 10


def leer_serie(ruta):
    with open(ruta) as f:
        return [int(fila["price"]) for fila in csv.DictReader(f)]


def div_trunc(a, b):
    """Division entera de SystemVerilog (trunca hacia cero, no hacia -inf)."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


# ---------------------------------------------------------------------------
# Contabilidad: copia de la tarea ejecutar() de tb/tb_proyecto_4.sv
# ---------------------------------------------------------------------------
class Mercado:
    def __init__(self):
        self.caja = CAJA0
        self.acciones = 0
        self.w = CAJA0
        self.peak = CAJA0
        self.max_dd = 0
        self.ordenes = 0

    def ejecutar(self, decision, p):
        q = decision & 0x3F
        accion = (decision >> 6) & 0x3
        if accion == 1:                                   # comprar lo que alcance
            q = min(q, div_trunc(self.caja - COMISION, p))
            if q > 0:
                self.caja -= q * p + COMISION
                self.acciones += q
                self.ordenes += 1
        elif accion == 2:                                 # vender lo que se tenga
            q = min(q, self.acciones)
            if q > 0 and self.caja + q * p >= COMISION:
                self.caja += q * p - COMISION
                self.acciones -= q
                self.ordenes += 1
        # 00 y 11: mantener
        self.w = self.caja + self.acciones * p
        self.peak = max(self.peak, self.w)
        self.max_dd = max(self.max_dd, self.peak - self.w)


# ---------------------------------------------------------------------------
# Estrategias: objeto con decidir(p) -> byte DECISION, llamado una vez por
# precio recibido, en orden. Solo ven la serie hasta el precio actual.
# ---------------------------------------------------------------------------
class Mantener:
    """Siempre 0x00. Sirve para probar el protocolo."""
    def decidir(self, p):
        return MANTENER


class Echo:
    """DECISION = precio recibido (igual que sw/echo.s). Prueba de protocolo
    y, de paso, de la contabilidad: genera compras y ventas de todo tamano."""
    def decidir(self, p):
        return p & 0xFF


class V0:
    """Version 0 (kit para la FPGA maestra): reversion a la media sobre la
    media movil de los ultimos N = 16 precios. Solo sumas, restas y
    comparaciones (Espino no tiene shifts, mul ni div):

      estado: buf[16] (ultimos 16 precios, circular), suma = sum(buf),
              llenos (0..16), idx (0..15), posicion (0 = en caja, 1 = comprado)

      por cada precio p:
        si llenos < 16:                       # calentamiento
            buf[llenos] = p; suma += p; llenos += 1
            si llenos < 16: decision = MANTENER y terminar
        si no:
            suma += p - buf[idx]; buf[idx] = p; idx = (idx + 1) & 15
        x = 16 * p                            # 4 sumas: p+p, *2, *2, *2
        si posicion == 0 y x + 16*U < suma:   # p < media - U
            decision = COMPRAR | 63; posicion = 1
        si no, si posicion == 1 y x > suma + 16*U:   # p > media + U
            decision = VENDER | 63; posicion = 0
        si no:
            decision = MANTENER

    Cuando llenos llega a 16 se decide en ese mismo tick (el buffer ya tiene
    16 precios); idx parte en 0, que es el precio mas antiguo.
    Con 63 acciones por orden y comprando solo desde posicion 0, nunca se
    tienen mas de 63 acciones, asi que VENDER | 63 vende todo.
    """
    N = 16

    def __init__(self, umbral=2):
        self.U = umbral
        self.buf = [0] * self.N
        self.suma = 0
        self.llenos = 0
        self.idx = 0
        self.posicion = 0

    def decidir(self, p):
        if self.llenos < self.N:
            self.buf[self.llenos] = p
            self.suma += p
            self.llenos += 1
            if self.llenos < self.N:
                return MANTENER
        else:
            self.suma += p - self.buf[self.idx]
            self.buf[self.idx] = p
            self.idx = (self.idx + 1) & (self.N - 1)
        x = self.N * p
        banda = self.N * self.U
        if self.posicion == 0 and x + banda < self.suma:
            self.posicion = 1
            return COMPRAR | 63
        if self.posicion == 1 and x > self.suma + banda:
            self.posicion = 0
            return VENDER | 63
        return MANTENER


ESTRATEGIAS = {"mantener": Mantener, "echo": Echo, "v0": V0}


# ---------------------------------------------------------------------------
# Simulacion con el mismo protocolo que el tb
# ---------------------------------------------------------------------------
def precios_en_reset(ronda):
    """Cuantos precios del tb terminan de llegar antes de que se libere el
    reset de encendido (el programa no los ve). Ronda 3: 2, rondas 1 y 2: 1."""
    T = PERIODO_NS[ronda]
    n = 0
    while INICIO_NS + n * T + PRECIO_LISTO_NS < POR_NS:
        n += 1
    return n


def simular(estrategia, precios, en_reset=0):
    """Devuelve (filas, mercado). filas = (tick, precio, decision, caja,
    acciones, patrimonio), igual que decisiones.csv del tb. Los primeros
    en_reset precios no llegan al programa."""
    m = Mercado()
    filas = []
    pendiente = MANTENER                     # valor de reset de DECISION
    for n, p in enumerate(precios):
        decision = pendiente                 # sale en la transaccion n
        m.ejecutar(decision, p)              # y se ejecuta al precio p[n]
        filas.append((n, p, decision, m.caja, m.acciones, m.w))
        if n >= en_reset:
            pendiente = estrategia.decidir(p)    # el programa lee p[n] y decide
    return filas, m


def comprar_y_mantener(precios):
    """Referencia del tb: compra (CAJA0 - C) / p[0] al precio p[0] y no
    vuelve a operar. Devuelve (patrimonio final, ordenes, comisiones, max_dd)."""
    q = div_trunc(CAJA0 - COMISION, precios[0])
    caja = CAJA0 - COMISION - q * precios[0]
    peak, max_dd = CAJA0, 0
    for p in precios:
        w = caja + q * p
        peak = max(peak, w)
        max_dd = max(max_dd, peak - w)
    return caja + q * precios[-1], 1, COMISION, max_dd


def comparar(filas, ruta):
    """Compara tick a tick con decisiones.csv del tb. Devuelve el numero de
    ticks distintos (imprime los primeros)."""
    with open(ruta) as f:
        tb = [(int(r["tick"]), int(r["precio"]), int(r["decision"], 16),
               int(r["caja"]), int(r["acciones"]), int(r["patrimonio"]))
              for r in csv.DictReader(f)]
    if len(tb) != len(filas):
        print(f"ERROR: el tb tiene {len(tb)} ticks y la referencia {len(filas)}")
        return max(len(tb), len(filas))
    distintos = [(a, b) for a, b in zip(filas, tb) if a != b]
    for a, b in distintos[:10]:
        print(f"  tick {a[0]}: referencia {a}  tb {b}")
    return len(distintos)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-e", "--estrategia", default="v0", choices=ESTRATEGIAS)
    ap.add_argument("-u", "--umbral", type=int, default=2, help="U de v0 (default 2)")
    ap.add_argument("-n", "--nticks", type=int, default=2000)
    ap.add_argument("-r", "--ronda", type=int, default=3, choices=(1, 2, 3),
                    help="ronda del tb (define cuantos precios caen en el reset)")
    ap.add_argument("-s", "--serie", default="tb/practica.csv")
    ap.add_argument("--csv", help="guardar el detalle por tick (formato decisiones.csv)")
    ap.add_argument("--compara", help="decisiones.csv del tb para comparar tick a tick")
    args = ap.parse_args()

    precios = leer_serie(args.serie)[:args.nticks]
    est = V0(args.umbral) if args.estrategia == "v0" else ESTRATEGIAS[args.estrategia]()
    filas, m = simular(est, precios, precios_en_reset(args.ronda))

    bh_w, bh_ord, bh_com, bh_dd = comprar_y_mantener(precios)
    print(f"Serie: {args.serie}, {len(precios)} ticks, ronda {args.ronda}"
          f" ({precios_en_reset(args.ronda)} precios en reset), estrategia: {args.estrategia}"
          + (f" (U = {args.umbral})" if args.estrategia == "v0" else ""))
    print(f"{'':22}{'patrimonio':>11}{'ordenes':>9}{'comisiones':>12}{'perdida max':>13}")
    print(f"{args.estrategia:22}{m.w:>11}{m.ordenes:>9}{m.ordenes * COMISION:>12}{m.max_dd:>13}")
    print(f"{'no operar':22}{CAJA0:>11}{0:>9}{0:>12}{0:>13}")
    print(f"{'comprar y mantener':22}{bh_w:>11}{bh_ord:>9}{bh_com:>12}{bh_dd:>13}")

    if args.csv:
        with open(args.csv, "w") as f:
            f.write("tick,precio,decision,caja,acciones,patrimonio\n")
            for n, p, d, c, a, w in filas:
                f.write(f"{n},{p},{d:02x},{c},{a},{w}\n")

    if args.compara:
        malos = comparar(filas, args.compara)
        if malos:
            print(f"DISTINTOS: {malos} ticks no coinciden con {args.compara}")
            sys.exit(1)
        print(f"IGUALES: los {len(filas)} ticks coinciden con {args.compara}")


if __name__ == "__main__":
    main()
