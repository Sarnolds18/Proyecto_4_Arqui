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
make tb_p4 NTICKS=20000                              # ~80 min; luego:
python3 ref/trader.py -n 20000 --compara decisiones.csv
python3 ref/banco.py                                 # exploración (ver 4.1)
bash docs/variantes/medir_variantes.sh               # tabla de LC/fmax (ver 4.3)
python3 ref/mediciones.py v2_20000:sw/trade.s ...    # IC, ciclos, CPI (ver 4.2)
bash scripts/informe.sh                              # este PDF
```

Las versiones de las herramientas están en el README.
