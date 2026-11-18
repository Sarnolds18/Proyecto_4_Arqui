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
- **Pendiente:** el SPI con la maestra real no se probó, porque el grupo no pudo ir a la prueba de
  conexión. Todo lo que depende del protocolo está validado con el testbench del curso, que emula a la
  maestra. `kit/CHECKLIST.md` tiene el orden de prueba (primero `echo.bin`) para el día de la
  competencia.

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
