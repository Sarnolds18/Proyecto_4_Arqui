# 4.4 Validación, placa y reproducibilidad

## Validaciones

| Qué | Cómo | Resultado | Evidencia |
|---|---|---|---|
| `trade.s` (V2) = referencia, serie Meta completa | `make medir NOMBRE=v2_20000 NTICKS=20000` + `--compara` | 4/4 PASS, IGUALES en los 20.000 ticks | `docs/mediciones/v2_20000.log`, `v2_20000_compara.txt` |
| `trade.s` (V2) bajo estrés (215 órdenes, W hasta 122.522) | `make medir NOMBRE=v2_estres SERIE=…estres…` | 4/4 PASS, IGUALES | `v2_estres_compara.txt` |
| `trade_v2a.s` (primera versión de V2, sin `mul_d2`) | ídem, Meta 20.000 y estrés | 4/4 PASS, IGUALES en ambas | `v2a_20000_compara.txt`, `v2a_estres_compara.txt` |
| `trade_mul.s` + multiplicador (D) | ídem con `DEFS=SOC_MUL` | 4/4 PASS, IGUALES | `mul_estres_compara.txt` |
| V1 (respaldo), serie Meta completa | `make medir NOMBRE=sw_20000` cuando `trade.s` era V1 (archivos renombrados a `v1_20000_*`) | 4/4 PASS, IGUALES en los 20.000 ticks | `v1_20000.log`, `v1_20000_compara.txt` |
| V1 + suma móvil (B), serie Meta completa | `DEFS=SOC_SMA` | 4/4 PASS, IGUALES en los 20.000 ticks | `sma_20000_compara.txt` |
| V1 + shifter (C) | `DEFS=ESPINO_SHIFTER`, 2.000 ticks | 4/4 PASS, IGUALES | `shift_compara.txt` |
| RAM con `RAM_NO_RW_CHECK` (post-síntesis) | `sim/postsintesis_ram.sh` | 4/4 PASS, IGUALES | `postsintesis_*.log` |
| Módulos nuevos | `sim/tb_pochoco_mul.v`, `tb_pochoco_sma.v`, `tb_espino_alu_shift.v`, `tb_reset_boton.v` | PASS; cada tb falla con una mutación del RTL | README, sección de testbenches |
| `trade_v2r.s` (V2 + reinicio automático) = referencia | `make tb_p4 PROG=sw/trade_v2r.hex`, Meta 20.000, estrés, rondas 1 y 2 | 4/4 PASS, IGUALES; mismas decisiones que `trade.s` | `v2r_20000.log`, `v2r_estres.log` |
| Reinicio entre series sin SW1 | `sim/tb_reinicio.sv` + `ref/reinicio.py`: serie A, pausa sin SPI, serie B | v2r: pausa de 1,3 s → se reinicia a los 0,987 s y B es IGUAL a una placa nueva; pausa de 0,95 s → no se reinicia. `trade.s`: no se reinicia | `reinicio_*.log` |
| SoC completo después de la síntesis | `sim/postsintesis_soc.sh` (netlist de yosys en lugar del RTL), serie de estrés | IGUALES con `trade.s` y con `trade_v2r.s` | `postsintesis_soc_*.log` |
| Margen del SPI | `sim/barrido_spi.sh`: `echo.s` con SCLK de 1 a 8 MHz y CS_n→primer flanco de 40 a 1000 ns | IGUALES hasta 4 MHz con cualquier tiempo de CS_n; falla desde 5 MHz (el enunciado fija ≤ 1 MHz) | `spi_barrido.txt` |
| Bitstreams | `scripts/compara_bin.sh` contra la flash de la placa | `trade.s`: idéntico bit a bit. `trade_v2r`: misma lógica y ruteo (`.asc` sin la BRAM idéntico), solo cambia el programa | — |

Todas las simulaciones usan el testbench del curso **sin modificar** (`tb/tb_proyecto_4.sv`). El
Makefile genera una copia que cambia solo el bloque de configuración (programa, serie, período y
ticks) y agrega la sonda como un módulo aparte. En la simulación se pierden los 2 primeros precios
por el reset de encendido (164 µs); `ref/trader.py -r` lo modela. En la placa no pasa.

## En la placa

- **Botón de reset (SW1):** repite el reset de encendido. Así cada ronda parte con caja 10.000 y 0
  acciones, igual que la contabilidad de la maestra. Testbench: `sim/tb_reset_boton.v`.
- El 7 segmentos muestra el último precio en hexadecimal (`64` = 100, `FF` = 255).
- **SPI con la maestra real: probado.** En las prácticas del 20/11 y el 25/11 la placa se conectó a
  la maestra con los pines de `goboard.pcf` y el protocolo funcionó sin cambios (modo 0, MSB
  primero, decisión del tick n−1 ejecutada al precio del tick n). Lo validado antes con el testbench
  del curso se confirmó en hardware. El orden de prueba está en `kit/CHECKLIST.md`.
- **El bitstream de la placa es el del repo.** El 25/11 se leyó la flash con `iceprog -r`
  (`scripts/respaldo_placa.sh`) y se comparó con `make trade_top.bin` de `main`
  (`scripts/compara_bin.sh`): son idénticos bit a bit. Si el ruteo cambiara con otra versión de las
  herramientas, el script compara además el programa dentro de la BRAM.

## Dos programas para la competencia: con y sin reinicio automático

En la competencia cada equipo entrega su placa y el curso la conserva durante las 3 series, así que
no podemos apretar SW1 entre una serie y otra. V2 lleva su propia copia de caja y acciones: si la
maestra empieza una serie nueva (caja 10.000, 0 acciones) y la placa no se reinicia, la copia queda
desincronizada. Con ventanas de datos reales de Apple, Meta, Netflix y Tesla, la suma de las 3 series
cae de 47.148 a 39.700 en promedio (−15,8 %).

Por eso hay dos programas con **el mismo algoritmo y el mismo hardware**:

| Programa | Qué hace | Cuándo se usa |
|---|---|---|
| `sw/trade.s` | V2 (el que ganó la ronda de práctica) | Si la organización aprieta SW1 o desconecta la placa entre series |
| `sw/trade_v2r.s` | V2 + reinicio automático: si pasa **1 s sin precio nuevo** (100 veces el período más lento, 10 ms), vuelve a caja 10.000 y 0 acciones y deja DECISION = MANTENER, igual que SW1 | Si no reinician la placa entre series, o no se sabe |

El contador usa el registro de la máscara de `mul` (`x10`), que está libre mientras el programa
espera un precio. Dentro de una serie las decisiones son idénticas a las de `trade.s` (mismas
validaciones de arriba), y el peor tick sube de 653 a 657 ciclos. El costo es un reinicio falso si
la maestra se pausa más de 1 s a mitad de una serie: la placa vuelve a caja 10.000 mientras la
maestra conserva las acciones. Con datos reales eso cuesta −270 en promedio (en el 30 % de los casos,
nada), contra −2.500 por serie si no hay reinicio. Además limpia cualquier pulso falso al conectar
los cables antes de la primera serie.

El programa se elige al entregar la placa, según lo que diga la organización. Los dos bitstreams
se generan desde este repo (`kit/CHECKLIST.md`).

## Ronda de práctica con la maestra

Serie de Apple (julio de 2022, unos 52 días intradía), 7 grupos con $10.000 cada uno. Los valores se
tomaron de fotos y videos de la pantalla de la maestra, así que pueden tener errores menores.

| Puesto | Grupo | Patrimonio final | Contra comprar y mantener |
|---|---|---:|---:|
| **1º** | **Nosotros (V2)** | **$15.610** | **+41,1 %** |
| 2º | Fila 3 | $14.310 | +29,3 % |
| 3º | Fila 4 | $13.783 | +24,5 % |
| 4º | Fila 6 | $13.770 | +24,4 % |
| 5º | Fila 5 | $11.275 | +1,9 % |
| 6º–7º | Filas 2 y 7 | $10.000 | −9,7 % (no operaron) |
| — | Comprar y mantener | $11.063 | — |

El resultado se parece a lo que predijo el banco de 4.1:

- **Subida (días 1–25, el precio casi se duplica):** V2 baja la exposición a medida que el precio
  sube, así que captura solo parte de la subida. En el día 25 iba −20,5 % contra comprar y mantener,
  aunque primero entre los grupos.
- **Caída (días 25–52, casi hasta el nivel inicial):** V2 conserva lo que ganó en la subida y vuelve
  a comprar en las bajadas. Termina primero, con 12 puntos de ventaja sobre el segundo.

## Reproducir todo

```bash
make trade_top.bin                                   # bitstream final (V2, 25 MHz)
make clean && make TRADE_HEX=sw/trade_v2r.hex trade_top.bin   # V2 con reinicio automatico
make tb_p4 NTICKS=20000                              # ~80 min; luego:
python3 ref/trader.py -n 20000 --compara decisiones.csv
bash sim/postsintesis_soc.sh sw/trade_v2r.hex 400 docs/mediciones/estres_serie.csv
bash sim/barrido_spi.sh                              # margen de SCLK
python3 ref/banco.py                                 # exploración (ver 4.1)
bash docs/variantes/medir_variantes.sh               # tabla de LC/fmax (ver 4.3)
python3 ref/mediciones.py v2_20000:sw/trade.s ...    # IC, ciclos, CPI (ver 4.2)
bash scripts/informe.sh                              # este PDF
```

Las versiones de las herramientas están en el README.
