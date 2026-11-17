# Proyecto 4 - Pochoco Trader
#
# echo.s: prueba de protocolo SPI con la FPGA maestra. Por cada precio que
# llega, lo devuelve tal cual como DECISION y lo muestra en hexadecimal en
# los dos displays de 7 segmentos.
#
# Validacion:
#   make tb_p4 PROG=sw/echo.hex && python3 ref/trader.py -e echo --compara decisiones.csv
#
# Registros:
#   x1 = 0x8001_0000  esclavo SPI (+0 STATUS, +4 PRICE, +8 DECISION)
#   x2 = 0x8000_0000  perifericos (+0 7 segmentos)
#   x3 = STATUS / bit "precio nuevo"
#   x4 = precio recibido

.section .text
.global _start

_start:
    lui  x1, 0x80010            # x1 = base SPI
    lui  x2, 0x80000            # x2 = base perifericos

espera:
    lw   x3, 0(x1)              # STATUS: bit0 = precio nuevo
    andi x3, x3, 1
    beq  x3, x0, espera

    lw   x4, 4(x1)              # PRICE (leerlo limpia el bit "precio nuevo")
    sw   x4, 8(x1)              # DECISION = precio (primero: es lo que mide el tb)
    sw   x4, 0(x2)              # 7 segmentos: precio en hex
    jal  x0, espera
