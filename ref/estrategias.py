#!/usr/bin/env python3
"""Estrategias candidatas (Parte C del plan). Todas en aritmetica entera.

Cada estrategia es una clase con decidir(p) -> byte DECISION, llamada una vez
por precio, en orden (mismo contrato que ref/trader.py). Las que necesitan
saber cuanta caja y cuantas acciones tienen llevan una copia propia de la
contabilidad (Contable): la decision que devuelven tras ver p[n] se ejecuta
al precio p[n+1], que es justo el siguiente precio que reciben, asi que la
copia es exacta (mismas reglas que la maestra: recorte por caja y acciones,
comision de 5 por orden ejecutada).

Familias (ver plan_p4.md, C.4):
  F1  Reversion        reversion a la media sobre SMA de N (V1 es N=16, U=3, 2 lotes)
  F3  Momentum         cruce de medias
  F10 Nivel            exposicion objetivo segun el nivel del precio en 100..255
  F11 NivelReversion   F10 + desplazamiento de la exposicion por desviacion de la SMA
  F5  (dentro de F11)  tamano: lotes, paso de rebalanceo
  F8  filtro de saltos parametro 'gap' de F11: tras un salto grande no se opera
  F4  Regimen          eficiencia de Kaufman: tendencia -> momentum, ruido -> reversion
  F7  SigueAlMejor     carteras virtuales de K sub-estrategias, se sigue a la mejor

Costo en Espino (sin mul/div/shift): sumas, restas, comparaciones y
multiplicaciones por constantes son baratas. Una multiplicacion de dos
variables (acciones * p) es un bucle de ~8 iteraciones (~80 ciclos). Una
division se evita comparando escalado.
"""

from trader import Mercado, COMPRAR, VENDER, MANTENER

LO, HI = 100, 255            # rango de la normalizacion del curso


class SMA:
    """Suma movil de N precios (N potencia de 2). lista() es True con N precios."""
    def __init__(self, N):
        self.N, self.buf, self.suma, self.n, self.i = N, [0] * N, 0, 0, 0

    def push(self, p):
        self.suma += p - self.buf[self.i]
        self.buf[self.i] = p
        self.i = (self.i + 1) % self.N
        if self.n < self.N:
            self.n += 1
        return self.n == self.N


class Contable:
    """Copia propia de caja y acciones."""
    def __init__(self):
        self.m = Mercado()
        self.pend = MANTENER

    def ver(self, p):
        self.m.ejecutar(self.pend, p)

    def hacia(self, objetivo, paso):
        """Orden hacia 'objetivo' acciones si la diferencia es >= paso."""
        d = objetivo - self.m.acciones
        if d >= paso:
            self.pend = COMPRAR | min(63, d)
        elif -d >= paso:
            self.pend = VENDER | min(63, -d)
        else:
            self.pend = MANTENER
        return self.pend


# --------------------------------------------------------------------- F1
class Reversion:
    """V1 generalizada: hasta 'lotes' ordenes de 63; compra si p < media - U,
    vende un lote si p > media + U."""
    def __init__(self, N=16, U=3, lotes=2):
        self.s, self.U, self.lotes, self.l = SMA(N), U, lotes, 0

    def decidir(self, p):
        if not self.s.push(p):
            return MANTENER
        x, b = self.s.N * p, self.s.N * self.U
        if self.l < self.lotes and x + b < self.s.suma:
            self.l += 1
            return COMPRAR | 63
        if self.l > 0 and x > self.s.suma + b:
            self.l -= 1
            return VENDER | 63
        return MANTENER


# --------------------------------------------------------------------- F3
class Momentum:
    def __init__(self, Nc=8, Nl=64, U=0):
        self.c, self.l, self.U, self.pos = SMA(Nc), SMA(Nl), U, 0

    def decidir(self, p):
        a, b = self.c.push(p), self.l.push(p)
        if not (a and b):
            return MANTENER
        xc, xl, u = self.c.suma * self.l.N, self.l.suma * self.c.N, self.U * self.c.N * self.l.N
        if xc > xl + u:
            self.pos = 1
            return COMPRAR | 63
        if xc + u < xl:
            self.pos = 0
            return VENDER | 63
        return MANTENER


# --------------------------------------------------------------------- F10
def exposicion(p, a, b, forma):
    """Fraccion objetivo en acciones, en 1/64 (0..64), segun el nivel."""
    if p <= a:
        return 64
    if p >= b:
        return 0
    if forma == "lineal":
        return (64 * (b - p)) // (b - a)
    if forma == "cuadratica":          # mas agresiva abajo, mas cauta arriba
        t = (64 * (b - p)) // (b - a)
        return (t * t) // 64
    if forma == "raiz":                # invierte antes
        t = 64 - (64 * (p - a)) // (b - a)
        return 64 - ((64 - t) * (64 - t)) // 64
    raise ValueError(forma)


class Nivel(Contable):
    """F10: acciones objetivo = expo(p) * W / p, rebalanceo si difiere en >= paso."""
    def __init__(self, a=LO, b=HI, paso=10, forma="lineal"):
        super().__init__()
        self.a, self.b, self.paso, self.forma = a, b, paso, forma

    def decidir(self, p):
        self.ver(p)
        w = self.m.caja + self.m.acciones * p
        obj = (exposicion(p, self.a, self.b, self.forma) * w) // (64 * p)
        return self.hacia(obj, self.paso)


# --------------------------------------------------------------------- F11
class NivelReversion(Contable):
    """F11: exposicion base por nivel (F10) + desplazamiento por reversion:
    si p < media - U se suma 'extra' (en 1/64 de W), si p > media + U se resta.
    Filtro de saltos (F8): si |p - p_anterior| >= gap, no se opera por
    'pausa' ticks."""
    def __init__(self, a=LO, b=HI, paso=10, forma="lineal", N=16, U=3, extra=16,
                 gap=0, pausa=0):
        super().__init__()
        self.a, self.b, self.paso, self.forma = a, b, paso, forma
        self.s, self.U, self.extra = SMA(N), U, extra
        self.gap, self.pausa, self.espera, self.prev = gap, pausa, 0, None

    def decidir(self, p):
        self.ver(p)
        listo = self.s.push(p)
        if self.gap and self.prev is not None and abs(p - self.prev) >= self.gap:
            self.espera = self.pausa
        self.prev = p
        if self.espera:
            self.espera -= 1
            self.pend = MANTENER
            return MANTENER
        e = exposicion(p, self.a, self.b, self.forma)
        if listo:
            x, bnd = self.s.N * p, self.s.N * self.U
            if x + bnd < self.s.suma:
                e += self.extra
            elif x > self.s.suma + bnd:
                e -= self.extra
        e = max(0, min(64, e))
        w = self.m.caja + self.m.acciones * p
        return self.hacia((e * w) // (64 * p), self.paso)


# --------------------------------------------------------------------- F4
class Regimen(Contable):
    """F4: eficiencia de Kaufman sobre N ticks: ER = |p - p_-N| / sum|dp|.
    ER >= umbral (en 1/16) -> sigue la tendencia (todo adentro si sube, afuera si
    baja); si no, reversion a la media de la SMA (todo adentro bajo la banda,
    afuera sobre la banda). Con base de nivel opcional."""
    def __init__(self, N=32, er16=6, U=3, base_nivel=False, paso=10):
        super().__init__()
        self.N, self.er16, self.U, self.base, self.paso = N, er16, U, base_nivel, paso
        self.p = [0] * N
        self.d = [0] * N
        self.sd, self.i, self.n, self.prev = 0, 0, 0, None
        self.s = SMA(16)
        self.expo = 0

    def decidir(self, p):
        self.ver(p)
        listo = self.s.push(p)
        dp = 0 if self.prev is None else abs(p - self.prev)
        self.prev = p
        viejo = self.p[self.i]
        self.sd += dp - self.d[self.i]
        self.d[self.i], self.p[self.i] = dp, p
        self.i = (self.i + 1) % self.N
        self.n = min(self.N + 1, self.n + 1)
        if self.n <= self.N or not listo:
            return self.hacia(0, self.paso) if not self.base else MANTENER
        neto = p - viejo
        tendencia = 16 * abs(neto) >= self.er16 * max(1, self.sd)
        x, bnd = 16 * p, 16 * self.U
        if tendencia:
            self.expo = 64 if neto > 0 else 0
        elif x + bnd < self.s.suma:
            self.expo = 64
        elif x > self.s.suma + bnd:
            self.expo = 0
        e = self.expo
        if self.base:
            e = (e + exposicion(p, LO, HI, "lineal")) // 2
        w = self.m.caja + self.m.acciones * p
        return self.hacia((e * w) // (64 * p), self.paso)


# --------------------------------------------------------------------- F7
class SigueAlMejor(Contable):
    """F7: K sub-estrategias de exposicion (0..64) llevan un puntaje virtual
    score += expo_anterior * dp - costo si cambia, con olvido exponencial
    (score -= score >> k, en software es una resta del score escalado). Se
    sigue la exposicion de la de mejor puntaje."""
    def __init__(self, olvido=9, costo=64, paso=10, miembros=("nivel", "rev", "mom", "bh")):
        super().__init__()
        self.olvido, self.costo, self.paso = olvido, costo, paso
        self.miembros = list(miembros)
        self.score = [0] * len(self.miembros)
        self.expo = [0] * len(self.miembros)
        self.s16, self.s8, self.s64 = SMA(16), SMA(8), SMA(64)
        self.prev = None

    def _expos(self, p, l16, l8, l64):
        out = []
        for k, nombre in enumerate(self.miembros):
            e = self.expo[k]
            if nombre == "nivel":
                e = exposicion(p, LO, HI, "lineal")
            elif nombre == "rev" and l16:
                if 16 * p + 48 < self.s16.suma:
                    e = 64
                elif 16 * p > self.s16.suma + 48:
                    e = 0
            elif nombre == "mom" and l8 and l64:
                e = 64 if self.s8.suma * 8 > self.s64.suma else 0
            elif nombre == "bh":
                e = 64
            out.append(e)
        return out

    def decidir(self, p):
        self.ver(p)
        l16, l8, l64 = self.s16.push(p), self.s8.push(p), self.s64.push(p)
        if self.prev is not None:
            dp = p - self.prev
            for k in range(len(self.miembros)):
                self.score[k] += self.expo[k] * dp
                self.score[k] -= self.score[k] >> self.olvido
        self.prev = p
        nuevas = self._expos(p, l16, l8, l64)
        for k in range(len(self.miembros)):
            if nuevas[k] != self.expo[k]:
                self.score[k] -= self.costo
            self.expo[k] = nuevas[k]
        mejor = max(range(len(self.miembros)), key=lambda k: self.score[k])
        w = self.m.caja + self.m.acciones * p
        return self.hacia((self.expo[mejor] * w) // (64 * p), self.paso)


class CompraYMantiene:
    def __init__(self):
        self.listo = False

    def decidir(self, p):
        return COMPRAR | 63


# --------------------------------------------------------------------- F11b
class NivelLote:
    """F11b: F11 sin division y con lote fijo de q acciones (version para Espino).

    Exposicion objetivo en unidades de 1/(64*D), D = b - a:
        t = 64 * clamp(b - p, 0, D)  (+ extra*D si p < media - U, - extra*D si p > media + U)
        t = clamp(t, 0, 64*D)
    Con W = caja + acc*p y V = acc*p (valor en acciones):
        compra q si  t*W >= 64*D*(V + q*p)   y  caja >= q*p + C   (nunca se recorta)
        vende  q si  t*W <= 64*D*(V - q*p)   y  acc >= q
    La banda muerta entre las dos condiciones es de q acciones (histeresis).
    Como las ordenes nunca se recortan, la copia de caja/acciones es exacta:
    caja -= q*p + C, acc += q (o al reves). Productos de hasta 30 bits.
    """
    def __init__(self, a=LO, b=HI, q=10, N=16, U=3, extra=16, inicio=0,
                 forma="lineal", Nt=0, tend=0):
        self.a, self.b, self.D, self.q = a, b, b - a, q
        self.s, self.U, self.extra = SMA(N), U, extra
        self.forma = forma
        # tendencia (opcional): si p > media de Nt ticks, se suma 'tend' (1/64)
        self.st, self.tend = (SMA(Nt) if Nt else None), tend
        self.caja, self.acc, self.pend = 10000, 0, MANTENER
        self.inicio = inicio          # ticks sin operar al principio

    def decidir(self, p):
        a, q = self.pend >> 6, self.pend & 63          # aplica la orden anterior al precio p
        if a == 1:
            self.caja -= q * p + 5; self.acc += q
        elif a == 2:
            self.caja += q * p - 5; self.acc -= q
        listo = self.s.push(p)
        listo_t = self.st.push(p) if self.st else False
        if self.inicio:
            self.inicio -= 1
            self.pend = MANTENER
            return MANTENER
        D, q = self.D, self.q
        r = min(max(self.b - p, 0), D)          # 0..D
        if self.forma == "lineal":
            t = 64 * r
        elif self.forma == "cuadratica":        # 64 * r^2 / D  (r*r y comparar escalado en Espino)
            t = (64 * r * r) // D
        else:                                   # raiz: 64 * (1 - (1 - r/D)^2) * D
            t = 64 * D - (64 * (D - r) * (D - r)) // D
        if listo_t and self.tend and self.st.N * p > self.st.suma:
            t += self.tend * D
        if listo and self.extra:
            x, bnd = self.s.N * p, self.s.N * self.U
            if x + bnd < self.s.suma:
                t += self.extra * D
            elif x > self.s.suma + bnd:
                t -= self.extra * D
        t = min(max(t, 0), 64 * D)
        V = self.acc * p
        tw = t * (self.caja + V)
        qp = q * p
        if tw >= 64 * D * (V + qp) and self.caja >= qp + 5:
            self.pend = COMPRAR | q
        elif tw <= 64 * D * (V - qp) and self.acc >= q:
            self.pend = VENDER | q
        else:
            self.pend = MANTENER
        return self.pend


# --------------------------------------------------------------------- F10 exacta
class NivelExacto:
    """F10 sin division ni redondeo (la que se implementa en trade.s).

    r = clamp(b - p, 0, D), D = b - a, exposicion objetivo = (r/D)^k, k = 1 o 2.
    Con W = caja + acc*p, V = acc*p, qp = q*p (enteros sin signo, < 2^31):
        compra q si  caja >= qp + C  y  r^k * W >= D^k * (V + qp)
        vende  q si  acc >= q        y  r^k * W <= D^k * (V - qp)
    Las ordenes nunca se recortan, asi que la copia de caja/acciones es exacta.
    """
    def __init__(self, a=LO, b=HI, q=40, k=2):
        self.a, self.b, self.D, self.q, self.k = a, b, b - a, q, k
        self.caja, self.acc, self.pend = 10000, 0, MANTENER

    def decidir(self, p):
        a, q = self.pend >> 6, self.pend & 63
        if a == 1:
            self.caja -= q * p + 5; self.acc += q
        elif a == 2:
            self.caja += q * p - 5; self.acc -= q
        r = min(max(self.b - p, 0), self.D)
        rk, Dk = (r, self.D) if self.k == 1 else (r * r, self.D * self.D)
        V, qp = self.acc * p, self.q * p
        tw = rk * (self.caja + V)
        if self.caja >= qp + 5 and tw >= Dk * (V + qp):
            self.pend = COMPRAR | self.q
        elif self.acc >= self.q and tw <= Dk * (V - qp):
            self.pend = VENDER | self.q
        else:
            self.pend = MANTENER
        return self.pend
