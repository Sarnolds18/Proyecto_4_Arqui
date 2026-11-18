# Proyecto 4 - Pochoco Trader
#
# trade_sma_shift.s: V1 para las alternativas B + C (pochoco_sma y shifter,
# macros SOC_SMA y ESPINO_SHIFTER). Igual que trade_sma.s, pero 16*p sale
# con un solo SLLI en vez de 4 sumas. Con el core original SLLI se ejecuta
# como ADD y las decisiones serian otras: este programa solo sirve con el
# shifter habilitado.
#
# Validacion:
#   make tb_p4 DEFS="SOC_SMA ESPINO_SHIFTER" PROG=sw/trade_sma_shift.hex && python3 ref/trader.py -e v1 --compara decisiones.csv
#
# Registros:
#   x1  = 0x8001_0000  esclavo SPI (+0 STATUS, +4 PRICE, +8 DECISION, +C SUMA)
#   x2  = 0x8000_0000  perifericos (+0 7 segmentos, +4 LEDs)
#   x3  = temporal
#   x4  = p (precio actual)
#   x5  = suma de los ultimos 16 precios (del periferico)
#   x6  = llenos (0..16)
#   x8  = lotes comprados (0..2)
#   x10 = 16 * p (p << 4)
#   x12 = 16 (N)
#   x13 = 48 (banda = 16 * U, U = 3)
#   x14 = 2 (maximo de lotes)

.section .text
.global _start

_start:
    lui  x1, 0x80010            # x1 = base SPI
    lui  x2, 0x80000            # x2 = base perifericos
    addi x6, x0, 0              # llenos = 0
    addi x8, x0, 0              # lotes = 0
    addi x12, x0, 16            # N
    addi x13, x0, 48            # banda = 16 * U, U = 3
    addi x14, x0, 2             # maximo de lotes

espera:
    lw   x3, 0(x1)              # STATUS: bit0 = precio nuevo
    andi x3, x3, 1
    beq  x3, x0, espera

lee:
    lw   x4, 4(x1)              # p = PRICE (leerlo limpia el bit)
    sw   x0, 8(x1)              # DECISION = MANTENER de inmediato
    sw   x4, 0(x2)              # 7 segmentos: precio en hex

media:
    lw   x5, 12(x1)             # suma de la ventana (pochoco_sma)

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
