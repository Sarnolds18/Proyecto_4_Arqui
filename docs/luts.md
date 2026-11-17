# Desglose de LUTs por módulo (A6)

Base para L2 (liberar LUTs). Este documento no cambia el RTL: las variantes se arman en copias
temporales.

**Fuente de cada número:**

- `docs/luts/stat_jerarquico.txt`: `yosys stat` por módulo, con `synth_ice40 -noflatten`.
- `docs/luts/variantes.txt`: yosys + nextpnr (`--hx1k --package vq100 --freq 25 --seed 1`)
  para cada variante.

Los dos archivos se regeneran con `bash docs/luts/medir_luts.sh`, desde la raíz y con yosys
y nextpnr en el `PATH`.

- **Herramientas:** Yosys 0.69+276 y nextpnr-0.11.1-59 (oss-cad-suite). Commit `1982fe6`.
- **Programa:** `sw/blink.hex`, porque `sw/trade.hex` todavía no existe. El programa solo
  cambia el contenido de la BRAM, no la lógica.
- `trade_top` solo cablea pines, así que se mide `pochoco_soc`.

## 1. Total (síntesis plana, el flujo de `make`)

| LC | BRAM | SB_LUT4 | SB_CARRY | FF | fmax |
|---|---|---|---|---|---|
| **1.275/1.280 (99 %)** | 12/16 | 1.068 | 208 | 354 | 44,81 MHz |

El plan anota 1.270 LC y 38,6 MHz, medidos por Santiago. La diferencia probablemente viene
de otra versión de yosys o nextpnr, o de otro `.hex`. Sus versiones quedan pendientes de
confirmar. Todos los deltas de abajo se calculan contra los 1.275 medidos acá.

## 2. Por módulo (síntesis jerárquica)

Las celdas son locales a cada módulo, sin contar sus submódulos. Sin aplanar, yosys no
optimiza a través de las fronteras entre módulos, así que la suma (1.121 LUT4) es mayor que la
síntesis plana (1.068). Sirve para ver proporciones; el ahorro real está en la sección 3.

| Módulo | Qué es | SB_LUT4 | SB_CARRY | FF | BRAM |
|---|---|---:|---:|---:|---:|
| `espino_alu` | ALU (shifts ya deshabilitados) | 252 | 63 | 0 | 0 |
| `espino_id_stage` (local) | sumadores PC+imm (saltos) y PC+4 (link), muxes de operandos y de write-back | 225 | 59 | 1 | 0 |
| `espino_load_store_unit` | alineación de bytes/halfwords en loads y stores | 118 | 0 | 1 | 0 |
| `espino_decoder` | decodificador RV32E | 93 | 0 | 0 | 0 |
| `espino_if_stage` | PC, PC+4, registro de instrucción | 62 | 28 | 65 | 0 |
| `espino_controller` | | 3 | 0 | 0 | 0 |
| `espino_register_file` | 2 bancos en BRAM | 2 | 0 | 0 | 4 |
| **subtotal `espino_core`** | | **755** | **150** | **67** | **4** |
| `pochoco_periph` (local) | LEDs, registro del 7-seg + decodificador, **contador de ciclos de 32 bits**, mux de lectura | 118 | 30 | 76 | 0 |
| `debounce_bank` | debouncer de los 4 botones | 22 | 16 | 27 | 0 |
| `pochoco_ram` | RAM de programa/datos 512×32, 2 puertos | **90** | 0 | **117** | 8 |
| `pochoco_soc` (local) | POR de 13 bits, decodificación de direcciones, mux de lectura | 98 | 11 | 15 | 0 |
| `pochoco_spi_slave` | esclavo SPI (necesario) | 38 | 2 | 52 | 0 |
| **Total** | | **1.121** | **209** | **354** | **12** |

Los 90 LUT4 y 117 FF de `pochoco_ram` no son la memoria, que está en las 8 BRAM. Son lógica
que agrega yosys: el log de síntesis muestra `emulate_read_first` y `emulate_transparency`.
En el iCE40, leer y escribir la misma dirección en el mismo ciclo da un dato indefinido, y
yosys lo emula con registros del dato y la dirección escritos, comparadores y un mux por bit.

## 3. Qué se puede sacar (medido con place & route)

| Variante | LC | Δ LC | FF | fmax (MHz) |
|---|---:|---:|---:|---:|
| base | 1.275 | — | 354 | 44,81 |
| sin debouncer (botones leen 0) | 1.237 | −38 | 327 | 44,81 |
| sin contador de ciclos (offset `0x0C` lee 0) | 1.111 | −164 | 294 | 41,89 |
| sin decodificador del 7-seg | 1.244 | −31 | 346 | 43,88 |
| sin LEDs | 1.251 | −24 | 350 | 42,34 |
| sin `pochoco_periph` completo | 1.055 | −220 | 251 | 43,51 |
| RAM con `(* no_rw_check *)` | 1.054 | −221 | 237 | 46,26 |
| sin debouncer ni contador | **1.079** | **−196** | 263 | 42,92 |
| sin debouncer ni contador + `no_rw_check` | **908** | **−367** | 146 | 48,74 |
| sin `pochoco_periph` + `no_rw_check` | 876 | −399 | 134 | 47,43 |

Todas las variantes ocupan 12/16 BRAM y pasan timing a 25 MHz. Los ahorros no se suman
exactamente porque el empaquetado en LC cambia con cada variante. Por eso las combinaciones se
midieron aparte.

### Comentarios por candidato

- **Debouncer y botones (−38):** el trader no usa los botones. Sacarlos no tiene riesgo.
- **Contador de ciclos (−164):** es lo que más cuesta del periférico: 32 FF, un sumador de
  32 bits, la carga por escritura y el ancho de 32 bits del mux de lectura. M3 mide los ciclos
  con sondas en el testbench, no con este contador, así que el trader no lo necesita.
  **Antes de sacarlo, confirmar con Matias** que `trade.s` y `echo.s` no leen `0x8000_000C`.
- **7-seg (−31) y LEDs (−24):** cuestan poco y sirven para depurar: el paso 1 del checklist
  de la prueba con la maestra usa el 7-seg para ver el precio. **Conviene mantenerlos.**
- **`no_rw_check` en la RAM (−221):** es el ahorro más grande sin perder funciones. Le dice a
  yosys que no emule las colisiones de lectura y escritura en la misma dirección y el mismo
  ciclo. Con Espino eso no debería pasar:
  - en el puerto B, un `sw` no usa el dato leído en ese ciclo, y un load posterior lee en otro
    ciclo;
  - en el puerto A, solo habría colisión si el programa se modificara a sí mismo.

  **Riesgo:** la simulación del RTL con Icarus ignora el atributo, así que no sirve para
  validarlo. Hay que simular **después de la síntesis** (netlist de yosys con `write_verilog`
  más `cells_sim.v`, con `tb_p4`) y probarlo en la placa. Pendiente para L2.

## 4. Propuesta para L2 (decidir con el grupo)

1. **Ahora, sin riesgo:** sacar el debouncer, los botones y el contador de ciclos.
   Queda en **1.079 LC (84 %)**, con 201 LC libres, y se mantienen el 7-seg y los LEDs.
2. **Si pasa la simulación post-síntesis:** agregar `(* no_rw_check *)` a `pochoco_ram`.
   Queda en **908 LC (71 %)**, con 372 LC libres para la alternativa B de L4.
3. El PLL (L3) no usa LC. La fmax de la base es 44,81 MHz, lo que da una idea del margen.
   La frecuencia definitiva se valida en L3.
