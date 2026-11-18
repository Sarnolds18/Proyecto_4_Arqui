# Proyecto 4 - Pochoco Trader
#
# trade_shift.s: V1 para la alternativa de hardware C (shifter, macro
# ESPINO_SHIFTER). Igual que trade_v1.s, pero 16*p sale con un solo SLLI en vez
# de 4 sumas. Con el core original SLLI se ejecuta como ADD y las decisiones
# serian otras: este programa solo sirve con el shifter habilitado.
#
#   por cada precio p:
#     DECISION = MANTENER
#     suma += p - buf[idx]; buf[idx] = p; idx = (idx + 1) & 15
#     si llenos < 16: llenos += 1; si llenos < 16: MANTENER
#     x = 16 * p
#     si lotes < 2 y x + 16*U < suma:  COMPRAR | 63 (0x7F), lotes += 1
#     si lotes > 0 y x > suma + 16*U:  VENDER  | 63 (0xBF), lotes -= 1
#     si no: MANTENER
#
# Durante el calentamiento buf[] esta en cero, asi que "suma += p - buf[idx]"
# equivale a "suma += p" y el puntero idx da la vuelta a 0 justo cuando
# llenos llega a 16 (igual que la referencia).
#
# DECISION = 0 se escribe apenas se lee el precio: si el calculo no alcanzara
# a terminar antes del siguiente tick, la maestra recibe "mantener" y no una
# orden vieja. El 7-seg muestra el precio (hex) y los LEDs los lotes (0..2).
#
# Punto fijo: no hace falta. Todo se compara escalado por N = 16 (enteros de
# hasta 16 * 255 = 4080), sin redondeo.
#
# Validacion:
#   make tb_p4 DEFS=ESPINO_SHIFTER PROG=sw/trade_shift.hex && python3 ref/trader.py -e v1 --compara decisiones.csv
#
# Registros:
#   x1  = 0x8001_0000  esclavo SPI (+0 STATUS, +4 PRICE, +8 DECISION)
#   x2  = 0x8000_0000  perifericos (+0 7 segmentos, +4 LEDs)
#   x3  = temporal
#   x4  = p (precio actual)
#   x5  = suma de los ultimos 16 precios
#   x6  = llenos (0..16)
#   x7  = idx en bytes (0, 4, ..., 60)
#   x8  = lotes comprados (0..2)
#   x9  = base de buf[] en RAM (0x700, fuera del programa)
#   x10 = 16 * p (p << 4)
#   x11 = temporal
#   x12 = 16 (N)
#   x13 = 48 (banda = 16 * U, U = 3)
#   x14 = 2 (maximo de lotes)
#
# Memoria: solo buf[0..15] en 0x700..0x73F (16 palabras). Sin pila.

.section .text
.global _start

_start:
    lui  x1, 0x80010            # x1 = base SPI
    lui  x2, 0x80000            # x2 = base perifericos
    addi x5, x0, 0              # suma = 0
    addi x6, x0, 0              # llenos = 0
    addi x7, x0, 0              # idx = 0
    addi x8, x0, 0              # lotes = 0
    addi x9, x0, 0x700          # buf en 0x700..0x73F
    addi x12, x0, 16            # N
    addi x13, x0, 48            # banda = 16 * U, U = 3
    addi x14, x0, 2             # maximo de lotes

    # buf[0..15] = 0 (la RAM fuera del programa parte indefinida)
    addi x3, x9, 0
    addi x11, x9, 64
limpia:
    sw   x0, 0(x3)
    addi x3, x3, 4
    bne  x3, x11, limpia

espera:
    lw   x3, 0(x1)              # STATUS: bit0 = precio nuevo
    andi x3, x3, 1
    beq  x3, x0, espera

lee:
    lw   x4, 4(x1)              # p = PRICE (leerlo limpia el bit)
    sw   x0, 8(x1)              # DECISION = MANTENER de inmediato
    sw   x4, 0(x2)              # 7 segmentos: precio en hex

media:
    # ventana movil: suma += p - buf[idx]; buf[idx] = p; idx = (idx+1) & 15
    add  x11, x9, x7            # &buf[idx]
    lw   x3, 0(x11)             # precio que sale
    sub  x5, x5, x3
    add  x5, x5, x4
    sw   x4, 0(x11)
    addi x7, x7, 4
    andi x7, x7, 63

    # calentamiento: hasta tener 16 precios no se decide
    beq  x6, x12, decide        # llenos == 16: ventana llena
    addi x6, x6, 1
    bne  x6, x12, espera        # llenos < 16: MANTENER (ya escrito)

decide:
    slli x10, x4, 4             # 16p (shifter, ESPINO_SHIFTER)

    # comprar si lotes < 2 y 16p + banda < suma
    bge  x8, x14, no_compra
    add  x3, x10, x13
    bge  x3, x5, no_compra
    addi x3, x0, 0x7F           # COMPRAR | 63
    sw   x3, 8(x1)
    addi x8, x8, 1
    sw   x8, 4(x2)              # LEDs = lotes
    jal  x0, espera

no_compra:
    # vender si lotes > 0 y 16p > suma + banda
    beq  x8, x0, espera         # sin lotes: MANTENER
    add  x3, x5, x13
    bge  x3, x10, espera        # no: MANTENER
    addi x3, x0, 0xBF           # VENDER | 63
    sw   x3, 8(x1)
    addi x8, x8, -1
    sw   x8, 4(x2)              # LEDs = lotes
    jal  x0, espera
