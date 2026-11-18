# Proyecto 4 - Pochoco Trader
#
# trade.s V2 (version final, solo software): exposicion por nivel de precio.
# Implementa exactamente la clase V2 de ref/trader.py.
#
# Cada ronda se normaliza a 100..255: cerca de 100 el precio casi no puede
# bajar mas y cerca de 255 casi no puede subir. La fraccion del patrimonio en
# acciones apunta a (r/D)^2, con r = 255 - p y D = 155, y se mueve con
# ordenes de q = 40 acciones:
#
#   por cada precio p:
#     DECISION = MANTENER
#     aplicar la orden anterior al precio p (se ejecuta a este precio):
#       comprar: caja -= 40p + 5, acc += 40;  vender: caja += 40p - 5, acc -= 40
#     r = min(255 - p, 155); V = acc*p; W = caja + V; qp = 40p
#     si caja >= qp + 5 y r*r*W >= 155^2 * (V + qp):  COMPRAR | 40 (0x68)
#     si no, si acc >= 40 y r*r*W <= 155^2 * (V - qp): VENDER  | 40 (0xA8)
#
# Las ordenes nunca piden mas caja ni mas acciones de las que hay, asi que la
# maestra no las recorta y la copia de caja/acciones es exacta.
#
# Sin mul/div/shift: 40p con sumas (32p + 8p), los productos por D^2 = 24025
# con una cadena fija de sumas (mul_d2) y los productos de dos variables con
# la subrutina mul (suma y doble, un bit del multiplicador por vuelta).
# No hay division: la exposicion se compara escalada (r^2 * W vs D^2 * V).
# Los productos se comparan sin signo: no desbordan mientras W < ~170.000
# (validado con la serie de estres, que llega a W = 122.522).
#
# Validacion:
#   make tb_p4 && python3 ref/trader.py --compara decisiones.csv
#
# Registros (RV32E: x0..x15):
#   x1  = 0x8001_0000  esclavo SPI (+0 STATUS, +4 PRICE, +8 DECISION)
#   x2  = 0x8000_0000  perifericos (+0 7 segmentos, +4 LEDs)
#   x3  = temporal / resultado de mul
#   x4  = p
#   x5  = caja
#   x6  = acc (acciones)
#   x7  = decision pendiente (la que se escribio en el tick anterior)
#   x8  = r, despues r*r*W
#   x9  = V = acc * p
#   x10 = mascara de mul
#   x11 = qp = 40 * p
#   x12 = temporal de mul
#   x13 = multiplicando de mul / mul_d2 (se destruye)
#   x14 = multiplicador de mul
#   x15 = direccion de retorno de mul
#
# Memoria: ninguna (todo el estado en registros). Sin pila.

.section .text
.global _start

_start:
    lui  x1, 0x80010            # x1 = base SPI
    lui  x2, 0x80000            # x2 = base perifericos
    lui  x5, 2                  # caja = 8192 + 1808 = 10000
    addi x5, x5, 1808
    addi x6, x0, 0              # acc = 0
    addi x7, x0, 0              # pendiente = MANTENER

espera:
    lw   x3, 0(x1)              # STATUS: bit0 = precio nuevo
    andi x3, x3, 1
    beq  x3, x0, espera

lee:
    lw   x4, 4(x1)              # p = PRICE (leerlo limpia el bit)
    sw   x0, 8(x1)              # DECISION = MANTENER de inmediato
    sw   x4, 0(x2)              # 7 segmentos: precio en hex

cuenta:
    # qp = 40p = 32p + 8p
    add  x11, x4, x4            # 2p
    add  x11, x11, x11          # 4p
    add  x11, x11, x11          # 8p
    add  x3, x11, x11           # 16p
    add  x3, x3, x3             # 32p
    add  x11, x11, x3           # 40p

    # la orden pendiente se ejecuto a este precio: actualizar la copia
    addi x3, x0, 0x68           # COMPRAR | 40
    bne  x7, x3, no_compro
    sub  x5, x5, x11            # caja -= 40p + 5
    addi x5, x5, -5
    addi x6, x6, 40             # acc += 40
    jal  x0, nivel
no_compro:
    addi x3, x0, 0xA8           # VENDER | 40
    bne  x7, x3, nivel
    add  x5, x5, x11            # caja += 40p - 5
    addi x5, x5, -5
    addi x6, x6, -40            # acc -= 40

nivel:
    addi x7, x0, 0              # pendiente = MANTENER salvo que se decida otra cosa
    addi x8, x0, 255
    sub  x8, x8, x4             # r = 255 - p (p <= 255)
    addi x3, x0, 155
    bge  x3, x8, r_ok           # r <= 155
    addi x8, x0, 155            # p < 100: r = D
r_ok:
    addi x13, x4, 0             # V = p * acc
    addi x14, x6, 0
    jal  x15, mul
    addi x9, x3, 0

    addi x13, x8, 0             # r * r
    addi x14, x8, 0
    jal  x15, mul

    addi x14, x3, 0             # r*r * W, W = caja + V
    add  x13, x5, x9
    jal  x15, mul
    addi x8, x3, 0              # x8 = r*r*W

decide:
    # comprar si caja >= qp + 5 y r*r*W >= D^2 * (V + qp)
    addi x3, x11, 5
    blt  x5, x3, prueba_venta
    add  x13, x9, x11           # D^2 * (V + qp)
    jal  x15, mul_d2
    bltu x8, x3, prueba_venta
    addi x7, x0, 0x68           # COMPRAR | 40
    jal  x0, escribe

prueba_venta:
    # vender si acc >= 40 y r*r*W <= D^2 * (V - qp)
    addi x3, x0, 40
    blt  x6, x3, espera         # sin 40 acciones: MANTENER (ya escrito)
    sub  x13, x9, x11           # D^2 * (V - qp), V - qp >= 0 porque acc >= 40
    jal  x15, mul_d2
    bltu x3, x8, espera         # D^2 * (V - qp) < r*r*W: MANTENER
    addi x7, x0, 0xA8           # VENDER | 40

escribe:
    sw   x7, 8(x1)              # DECISION
    jal  x0, espera

# x3 = x13 * x14 (sin signo). Un bit de x14 por vuelta, de menor a mayor:
# termina cuando la mascara supera a x14. Usa x10 y x12; destruye x13.
mul:
    addi x3, x0, 0
    addi x10, x0, 1             # mascara
mul_l:
    bltu x14, x10, mul_fin      # mascara > multiplicador: listo
    and  x12, x14, x10
    beq  x12, x0, mul_s
    add  x3, x3, x13            # bit en 1: sumar el multiplicando desplazado
mul_s:
    add  x13, x13, x13          # multiplicando * 2
    add  x10, x10, x10          # mascara * 2
    bne  x10, x0, mul_l
mul_fin:
    jalr x0, 0(x15)

# x3 = x13 * 24025 (D^2), sin bucle: 24025 = 2^14 + 2^12 + 2^11 + 2^10 + 2^8
# + 2^7 + 2^6 + 2^4 + 2^3 + 2^0, una suma por bit en 1. Usa x12.
mul_d2:
    addi x3, x13, 0             # bit 0
    add  x12, x13, x13          # 2x
    add  x12, x12, x12          # 4x
    add  x12, x12, x12          # 8x
    add  x3, x3, x12            # bit 3
    add  x12, x12, x12          # 16x
    add  x3, x3, x12            # bit 4
    add  x12, x12, x12          # 32x
    add  x12, x12, x12          # 64x
    add  x3, x3, x12            # bit 6
    add  x12, x12, x12          # 128x
    add  x3, x3, x12            # bit 7
    add  x12, x12, x12          # 256x
    add  x3, x3, x12            # bit 8
    add  x12, x12, x12          # 512x
    add  x12, x12, x12          # 1024x
    add  x3, x3, x12            # bit 10
    add  x12, x12, x12          # 2048x
    add  x3, x3, x12            # bit 11
    add  x12, x12, x12          # 4096x
    add  x3, x3, x12            # bit 12
    add  x12, x12, x12          # 8192x
    add  x12, x12, x12          # 16384x
    add  x3, x3, x12            # bit 14
    jalr x0, 0(x15)
