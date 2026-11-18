# Proyecto 4 - Pochoco Trader
#
# trade_v0.s: version v0 (kit de la prueba con la maestra). Reversion a la
# media sobre la media movil de los ultimos N = 16 precios, umbral U = 2,
# ordenes de 63 acciones. Implementa exactamente la clase V0 de
# ref/trader.py (solo sumas, restas y comparaciones: Espino no tiene
# shifts, mul ni div).
#
#   por cada precio p:
#     suma += p - buf[idx]; buf[idx] = p; idx = (idx + 1) & 15
#     si llenos < 16: llenos += 1; si llenos < 16: MANTENER
#     x = 16 * p
#     si pos == 0 y x + 16*U < suma:  COMPRAR | 63 (0x7F), pos = 1
#     si pos == 1 y x > suma + 16*U:  VENDER  | 63 (0xBF), pos = 0
#     si no: MANTENER (0x00)
#
# Durante el calentamiento buf[] esta en cero, asi que "suma += p - buf[idx]"
# equivale a "suma += p" y el puntero idx da la vuelta a 0 justo cuando
# llenos llega a 16 (igual que la referencia).
#
# DECISION = 0 se escribe apenas se lee el precio: si el calculo no alcanzara
# a terminar antes del siguiente tick, la maestra recibe "mantener" y no una
# orden vieja.
#
# Validacion:
#   make tb_p4 PROG=sw/trade_v0.hex && python3 ref/trader.py -e v0 --compara decisiones.csv
#
# Registros:
#   x1  = 0x8001_0000  esclavo SPI (+0 STATUS, +4 PRICE, +8 DECISION)
#   x2  = 0x8000_0000  perifericos (+0 7 segmentos)
#   x3  = temporal
#   x4  = p (precio actual)
#   x5  = suma de los ultimos 16 precios
#   x6  = llenos (0..16)
#   x7  = idx en bytes (0, 4, ..., 60)
#   x8  = posicion (0 = en caja, 1 = comprado)
#   x9  = base de buf[] en RAM (0x700, fuera del programa)
#   x10 = 16 * p
#   x11 = temporal
#   x12 = 16 (N)
#   x13 = 32 (banda = 16 * U)

.section .text
.global _start

_start:
    lui  x1, 0x80010            # x1 = base SPI
    lui  x2, 0x80000            # x2 = base perifericos
    addi x5, x0, 0              # suma = 0
    addi x6, x0, 0              # llenos = 0
    addi x7, x0, 0              # idx = 0
    addi x8, x0, 0              # posicion = 0
    addi x9, x0, 0x700          # buf en 0x700..0x73F
    addi x12, x0, 16            # N
    addi x13, x0, 32            # banda = 16 * U, U = 2

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

    lw   x4, 4(x1)              # p = PRICE (leerlo limpia el bit)
    sw   x0, 8(x1)              # DECISION = MANTENER de inmediato
    sw   x4, 0(x2)              # 7 segmentos: precio en hex

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
    add  x10, x4, x4            # 2p
    add  x10, x10, x10          # 4p
    add  x10, x10, x10          # 8p
    add  x10, x10, x10          # 16p

    bne  x8, x0, en_bolsa

    # en caja: comprar si 16p + banda < suma
    add  x3, x10, x13
    bge  x3, x5, espera         # no: MANTENER
    addi x3, x0, 0x7F           # COMPRAR | 63
    sw   x3, 8(x1)
    addi x8, x0, 1
    jal  x0, espera

en_bolsa:
    # comprado: vender si 16p > suma + banda
    add  x3, x5, x13
    bge  x3, x10, espera        # no: MANTENER
    addi x3, x0, 0xBF           # VENDER | 63
    sw   x3, 8(x1)
    addi x8, x0, 0
    jal  x0, espera
