# Mediciones por tick (generado por `ref/mediciones.py`)

Reloj 25 MHz. Ventana por tick: `sim/sonda_p4.sv`. Presupuesto (ciclos) = (T - 9.5 us) x f: ronda 1 = 249.762. ronda 2 = 24.762. ronda 3 = 2.262.

## IC, ciclos, CPI y tiempo por tick

| Variante | Ticks | IC prom | IC peor | Ciclos prom | Ciclos peor | CPI prom | t prom (us) | t peor (us) | Peor / T ronda 3 | Ciclos hasta ultima DECISION (peor) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| v2_20000 | 19998 | 227.34 | 292 | 509.40 | 653 | 2.241 | 20.38 | 26.12 | 28.87 % | 592 |
| v2_estres | 1998 | 235.84 | 326 | 526.99 | 721 | 2.235 | 21.08 | 28.84 | 31.87 % | 716 |
| v2a_20000 | 19998 | 257.48 | 342 | 583.94 | 779 | 2.268 | 23.36 | 31.16 | 34.44 % | 757 |
| v2a_estres | 1998 | 321.13 | 499 | 727.16 | 1133 | 2.264 | 29.09 | 45.32 | 50.09 % | 1129 |
| mul_estres | 1998 | 93.85 | 116 | 231.31 | 286 | 2.465 | 9.25 | 11.44 | 12.64 % | 282 |
| v1_20000 | 19998 | 23.68 | 32 | 54.71 | 72 | 2.311 | 2.19 | 2.88 | 3.18 % | 64 |
| sma_20000 | 19998 | 17.68 | 26 | 42.98 | 60 | 2.432 | 1.72 | 2.40 | 2.65 % | 52 |
| shift | 1998 | 20.85 | 29 | 49.22 | 66 | 2.361 | 1.97 | 2.64 | 2.92 % | 58 |

## Perfil por region: v2_20000 (`sw/trade.s`)

| Region (etiqueta) | Ciclos | % ciclos | Instrucciones | CPI |
|---|---:|---:|---:|---:|
| `espera` | 212403 | 2.1 % | 89931 | 2.36 |
| `lee` | 139986 | 1.4 % | 59994 | 2.33 |
| `cuenta` | 319992 | 3.1 % | 159996 | 2.00 |
| `no_compro` | 79992 | 0.8 % | 39996 | 2.00 |
| `nivel` | 199980 | 2.0 % | 99990 | 2.00 |
| `r_ok` | 439956 | 4.3 % | 219978 | 2.00 |
| `decide` | 148614 | 1.5 % | 74307 | 2.00 |
| `prueba_venta` | 154924 | 1.5 % | 77462 | 2.00 |
| `escribe` | 20 | 0.0 % | 10 | 2.00 |
| `mul` | 239976 | 2.4 % | 119988 | 2.00 |
| `mul_l` | 3206168 | 31.5 % | 1603084 | 2.00 |
| `mul_s` | 2687166 | 26.4 % | 1343583 | 2.00 |
| `mul_fin` | 119988 | 1.2 % | 59994 | 2.00 |
| `mul_d2` | 1196250 | 11.7 % | 598125 | 2.00 |
| burbujas tras saltos | 1041551 | 10.2 % | 0 | - |

CPI por clase de instruccion en el kernel (fuera del bucle de espera):

| Clase | Instrucciones | Ciclos | CPI |
|---|---:|---:|---:|
| alu | 2701173 | 5402346 | 2.00 |
| branch | 1527486 | 3054972 | 2.00 |
| jal | 83930 | 167860 | 2.00 |
| load | 19998 | 59994 | 3.00 |
| otra | 83919 | 167838 | 2.00 |
| store | 40001 | 80002 | 2.00 |

## Perfil por region: v2_estres (`sw/trade.s`)

| Region (etiqueta) | Ciclos | % ciclos | Instrucciones | CPI |
|---|---:|---:|---:|---:|
| `espera` | 21150 | 2.0 % | 8974 | 2.36 |
| `lee` | 13986 | 1.3 % | 5994 | 2.33 |
| `cuenta` | 32832 | 3.1 % | 16416 | 2.00 |
| `no_compro` | 8202 | 0.8 % | 4101 | 2.00 |
| `nivel` | 20120 | 1.9 % | 10060 | 2.00 |
| `r_ok` | 43956 | 4.2 % | 21978 | 2.00 |
| `decide` | 17790 | 1.7 % | 8895 | 2.00 |
| `prueba_venta` | 15688 | 1.5 % | 7844 | 2.00 |
| `escribe` | 860 | 0.1 % | 430 | 2.00 |
| `mul` | 23976 | 2.3 % | 11988 | 2.00 |
| `mul_l` | 322562 | 30.6 % | 161281 | 2.00 |
| `mul_s` | 270498 | 25.7 % | 135249 | 2.00 |
| `mul_fin` | 11988 | 1.1 % | 5994 | 2.00 |
| `mul_d2` | 144000 | 13.7 % | 72000 | 2.00 |
| burbujas tras saltos | 105319 | 10.0 % | 0 | - |

CPI por clase de instruccion en el kernel (fuera del bucle de espera):

| Clase | Instrucciones | Ciclos | CPI |
|---|---:|---:|---:|
| alu | 283945 | 567890 | 2.00 |
| branch | 153897 | 307794 | 2.00 |
| jal | 9305 | 18610 | 2.00 |
| load | 1998 | 5994 | 3.00 |
| otra | 8874 | 17748 | 2.00 |
| store | 4211 | 8422 | 2.00 |

## Perfil por region: v2a_20000 (`sw/trade_v2a.s`)

| Region (etiqueta) | Ciclos | % ciclos | Instrucciones | CPI |
|---|---:|---:|---:|---:|
| `espera` | 212290 | 1.8 % | 90042 | 2.36 |
| `lee` | 139986 | 1.2 % | 59994 | 2.33 |
| `cuenta` | 319992 | 2.7 % | 159996 | 2.00 |
| `no_compro` | 79992 | 0.7 % | 39996 | 2.00 |
| `nivel` | 199980 | 1.7 % | 99990 | 2.00 |
| `r_ok` | 439956 | 3.8 % | 219978 | 2.00 |
| `decide` | 194354 | 1.7 % | 97177 | 2.00 |
| `prueba_venta` | 204884 | 1.8 % | 102442 | 2.00 |
| `escribe` | 20 | 0.0 % | 10 | 2.00 |
| `mul` | 335676 | 2.9 % | 167838 | 2.00 |
| `mul_l` | 4378720 | 37.5 % | 2189360 | 2.00 |
| `mul_s` | 3676524 | 31.5 % | 1838262 | 2.00 |
| `mul_fin` | 167838 | 1.4 % | 83919 | 2.00 |
| burbujas tras saltos | 1327508 | 11.4 % | 0 | - |

CPI por clase de instruccion en el kernel (fuera del bucle de espera):

| Clase | Instrucciones | Ciclos | CPI |
|---|---:|---:|---:|
| alu | 2785024 | 5570048 | 2.00 |
| branch | 2046090 | 4092180 | 2.00 |
| jal | 83930 | 167860 | 2.00 |
| load | 19998 | 59994 | 3.00 |
| otra | 83919 | 167838 | 2.00 |
| store | 40001 | 80002 | 2.00 |

## Perfil por region: v2a_estres (`sw/trade_v2a.s`)

| Region (etiqueta) | Ciclos | % ciclos | Instrucciones | CPI |
|---|---:|---:|---:|---:|
| `espera` | 21170 | 1.5 % | 8977 | 2.36 |
| `lee` | 13986 | 1.0 % | 5994 | 2.33 |
| `cuenta` | 32832 | 2.3 % | 16416 | 2.00 |
| `no_compro` | 8202 | 0.6 % | 4101 | 2.00 |
| `nivel` | 20120 | 1.4 % | 10060 | 2.00 |
| `r_ok` | 43956 | 3.0 % | 21978 | 2.00 |
| `decide` | 24034 | 1.7 % | 12017 | 2.00 |
| `prueba_venta` | 20964 | 1.4 % | 10482 | 2.00 |
| `escribe` | 860 | 0.1 % | 430 | 2.00 |
| `mul` | 35496 | 2.4 % | 17748 | 2.00 |
| `mul_l` | 567594 | 39.1 % | 283797 | 2.00 |
| `mul_s` | 481506 | 33.1 % | 240753 | 2.00 |
| `mul_fin` | 17748 | 1.2 % | 8874 | 2.00 |
| burbujas tras saltos | 164400 | 11.3 % | 0 | - |

CPI por clase de instruccion en el kernel (fuera del bucle de espera):

| Clase | Instrucciones | Ciclos | CPI |
|---|---:|---:|---:|
| alu | 345981 | 691962 | 2.00 |
| branch | 262281 | 524562 | 2.00 |
| jal | 9305 | 18610 | 2.00 |
| load | 1998 | 5994 | 3.00 |
| otra | 8874 | 17748 | 2.00 |
| store | 4211 | 8422 | 2.00 |

## Perfil por region: mul_estres (`sw/trade_mul.s`)

| Region (etiqueta) | Ciclos | % ciclos | Instrucciones | CPI |
|---|---:|---:|---:|---:|
| `espera` | 21180 | 4.6 % | 8972 | 2.36 |
| `lee` | 13986 | 3.0 % | 5994 | 2.33 |
| `cuenta` | 32832 | 7.1 % | 16416 | 2.00 |
| `no_compro` | 8202 | 1.8 % | 4101 | 2.00 |
| `nivel` | 20120 | 4.4 % | 10060 | 2.00 |
| `r_ok` | 43956 | 9.5 % | 21978 | 2.00 |
| `decide` | 24034 | 5.2 % | 12017 | 2.00 |
| `prueba_venta` | 20964 | 4.5 % | 10482 | 2.00 |
| `escribe` | 860 | 0.2 % | 430 | 2.00 |
| `mul` | 53244 | 11.5 % | 26622 | 2.00 |
| `mul_w` | 176100 | 38.1 % | 70440 | 2.50 |
| burbujas tras saltos | 46684 | 10.1 % | 0 | - |

CPI por clase de instruccion en el kernel (fuera del bucle de espera):

| Clase | Instrucciones | Ciclos | CPI |
|---|---:|---:|---:|
| alu | 62184 | 124368 | 2.00 |
| branch | 39000 | 78000 | 2.00 |
| jal | 9305 | 18610 | 2.00 |
| load | 37218 | 111654 | 3.00 |
| otra | 8874 | 17748 | 2.00 |
| store | 21959 | 43918 | 2.00 |

## Perfil por region: v1_20000 (`sw/trade_v1.s`)

| Region (etiqueta) | Ciclos | % ciclos | Instrucciones | CPI |
|---|---:|---:|---:|---:|
| `espera` | 210427 | 19.2 % | 89984 | 2.34 |
| `lee` | 139986 | 12.8 % | 59994 | 2.33 |
| `media` | 340030 | 31.1 % | 160016 | 2.12 |
| `decide` | 249920 | 22.8 % | 124960 | 2.00 |
| `no_compra` | 77086 | 7.0 % | 38543 | 2.00 |
| burbujas tras saltos | 76679 | 7.0 % | 0 | - |

CPI por clase de instruccion en el kernel (fuera del bucle de espera):

| Clase | Instrucciones | Ciclos | CPI |
|---|---:|---:|---:|
| alu | 201695 | 403390 | 2.00 |
| branch | 81276 | 162552 | 2.00 |
| jal | 184 | 368 | 2.00 |
| load | 39996 | 119988 | 3.00 |
| store | 60362 | 120724 | 2.00 |

## Perfil por region: sma_20000 (`sw/trade_sma.s`)

| Region (etiqueta) | Ciclos | % ciclos | Instrucciones | CPI |
|---|---:|---:|---:|---:|
| `espera` | 214497 | 25.0 % | 89976 | 2.38 |
| `lee` | 139986 | 16.3 % | 59994 | 2.33 |
| `media` | 100054 | 11.6 % | 40028 | 2.50 |
| `decide` | 249920 | 29.1 % | 124960 | 2.00 |
| `no_compra` | 77086 | 9.0 % | 38543 | 2.00 |
| burbujas tras saltos | 78047 | 9.1 % | 0 | - |

CPI por clase de instruccion en el kernel (fuera del bucle de espera):

| Clase | Instrucciones | Ciclos | CPI |
|---|---:|---:|---:|
| alu | 101705 | 203410 | 2.00 |
| branch | 81276 | 162552 | 2.00 |
| jal | 184 | 368 | 2.00 |
| load | 39996 | 119988 | 3.00 |
| store | 40364 | 80728 | 2.00 |

## Perfil por region: shift (`sw/trade_shift.s`)

| Region (etiqueta) | Ciclos | % ciclos | Instrucciones | CPI |
|---|---:|---:|---:|---:|
| `espera` | 21576 | 21.9 % | 9221 | 2.34 |
| `lee` | 13986 | 14.2 % | 5994 | 2.33 |
| `media` | 34030 | 34.6 % | 16016 | 2.12 |
| `decide` | 13762 | 14.0 % | 6881 | 2.00 |
| `no_compra` | 7094 | 7.2 % | 3547 | 2.00 |
| burbujas tras saltos | 7895 | 8.0 % | 0 | - |

CPI por clase de instruccion en el kernel (fuera del bucle de espera):

| Clase | Instrucciones | Ciclos | CPI |
|---|---:|---:|---:|
| alu | 14224 | 28448 | 2.00 |
| branch | 8170 | 16340 | 2.00 |
| jal | 18 | 36 | 2.00 |
| load | 3996 | 11988 | 3.00 |
| store | 6030 | 12060 | 2.00 |

## Ley de Amdahl: speedup predicho vs medido

| Base -> variante | Region acelerada | Fraccion p | Speedup de la region s | Predicho 1/((1-p)+p/s) | Medido | Limite 1/(1-p) |
|---|---|---:|---:|---:|---:|---:|
| v2_estres -> mul_estres | mul+mul_l+mul_s+mul_fin+mul_d2 | 0.734 | 3.37 | 2.068 | 2.278 | 3.762 |
| v2a_estres -> v2_estres | mul+mul_l+mul_s+mul_fin | 0.759 | 1.43 | 1.293 | 1.380 | 4.145 |
| v1_20000 -> sma_20000 | media | 0.311 | 3.40 | 1.281 | 1.273 | 1.451 |
| v1_20000 -> shift | decide | 0.228 | 1.81 | 1.114 | 1.112 | 1.296 |

## Ops/s y roofline

Operacion util (1): **precio procesado** (un tick completo). Capacidad = f / ciclos del peor tick.
Operacion util (2), para el roofline: **instruccion de ALU** (OP, OP-IMM, LUI o branch) del kernel, es decir, fuera del bucle de espera. Trafico: 4 bytes por cada lw/sw (RAM o MMIO).

| Variante | LC | Precios/s (peor tick) | Ops ALU por tick | Bytes por tick | Intensidad (ops/B) | Ciclos kernel por tick | Ops ALU/s en el kernel |
|---|---:|---:|---:|---:|---:|---:|---:|
| v2_20000 | - | 38.285 | 211.45 | 12.00 | 17.620 | 446.70 | 11.83 M |
| v2_estres | - | 34.674 | 219.14 | 12.43 | 17.629 | 463.69 | 11.81 M |
| v2a_20000 | - | 32.092 | 241.58 | 12.00 | 20.130 | 506.95 | 11.91 M |
| v2a_estres | - | 22.065 | 304.44 | 12.43 | 24.491 | 634.28 | 12.00 M |
| mul_estres | - | 87.413 | 50.64 | 118.47 | 0.427 | 197.35 | 6.42 M |
| v1_20000 | - | 347.222 | 14.15 | 20.07 | 0.705 | 40.36 | 8.77 M |
| sma_20000 | - | 416.667 | 9.15 | 16.07 | 0.569 | 28.36 | 8.07 M |
| shift | - | 378.788 | 11.21 | 20.07 | 0.558 | 34.47 | 8.13 M |

Techos de Espino (medidos con el CPI por clase): computo = f / CPI_ALU = 12.50 Mops/s (CPI_ALU = 2.00); ancho de banda = 4 B x f / CPI_lw = 33.33 MB/s (CPI_lw = 3.00; CPI_sw = 2.00). Punto de quiebre = 0.375 ops/B: un kernel con menos intensidad queda limitado por memoria y uno con mas, por computo. Como Espino no solapa instrucciones, en la practica cada kernel queda bajo la linea t = n_alu * CPI_ALU + n_mem * CPI_mem.

