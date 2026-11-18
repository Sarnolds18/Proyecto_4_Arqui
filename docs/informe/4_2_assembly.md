# 4.2 Implementación en assembly

`sw/trade.s` implementa la clase `V2` de `ref/trader.py`. Se ensambla con nuestro assembler
(`python3 sw/assembler.py sw/trade.s sw/trade.hex`; el Makefile lo hace solo). Ocupa 75 palabras.
Las mediciones salen de `docs/mediciones/resumen.md`, generado con `ref/mediciones.py` a partir de
`make medir`.

## Estructura del ciclo principal

```
_start   bases de SPI y periféricos, caja = 10.000, acc = 0, pendiente = MANTENER
espera   leer STATUS hasta que bit0 = 1 (precio nuevo)
lee      p = PRICE; DECISION = 0 de inmediato; 7 segmentos = p
cuenta   qp = 40p (32p + 8p con sumas)
         aplicar la orden pendiente al precio p (la maestra la ejecutó a este precio):
         comprar: caja -= qp + 5, acc += 40;  vender: caja += qp - 5, acc -= 40
nivel    r = min(255 - p, 155)
r_ok     V = p·acc;  r²;  r²·W con W = caja + V
decide   comprar si caja ≥ qp + 5 y r²·W ≥ 155²·(V + qp)
prueba_venta  si no: vender si acc ≥ 40 y r²·W ≤ 155²·(V − qp)
escribe  DECISION = 0x68 (comprar 40) o 0xA8 (vender 40) → volver a espera
mul      subrutina: x3 = x13 · x14 (sin signo)
```

Hay dos decisiones de diseño que vienen de la consigna:

- **DECISION = 0 apenas se lee el precio.** Si un tick no alcanzara a terminar, la maestra repite
  "mantener", no una compra vieja.
- **Copia exacta de caja y acciones.** El programa nunca pide más de lo que tiene, así que la maestra
  no recorta sus órdenes y la copia coincide siempre con la contabilidad oficial. La decisión del tick
  n se aplica al leer el precio n+1, que es justo el precio al que la ejecutó la maestra.

## Registros y memoria

| Registro | Uso |
|---|---|
| x1 / x2 | base del esclavo SPI `0x8001_0000` / de los periféricos `0x8000_0000` |
| x3 | temporal y resultado de `mul` |
| x4 | p |
| x5 / x6 | caja / acc (acciones) |
| x7 | decisión pendiente (la escrita en el tick anterior) |
| x8 | r, después r²·W |
| x9 | V = acc·p |
| x11 | qp = 40p |
| x10, x12, x13, x14 | máscara, temporal y operandos de `mul` |
| x15 | dirección de retorno de `mul` (`jal x15, mul` / `jalr x0, 0(x15)`) |

Espino es RV32E: 16 registros, y alcanzan para todo el estado. **No usa memoria de datos ni pila**:
la RAM solo guarda el programa. V1, en cambio, guardaba los últimos 16 precios en `0x700–0x73F`.

## Punto fijo y lo que Espino no tiene

- **Sin punto fijo:** todo es entero. La exposición (r/D)² no se calcula; se compara escalada:
  `r²·W` contra `D²·(V ± qp)`. Así no hay división ni redondeo, y el resultado es exacto, igual que
  en la referencia.
- **Sin multiplicación:** las constantes se arman con sumas (40p = 2p → 4p → 8p, 16p, 32p; 32p + 8p).
  Los productos de dos variables (p·acc, r·r, r²·W y D²·(V ± qp)) usan la subrutina `mul`, que hace
  suma y doble: recorre los bits del multiplicador de menor a mayor con una máscara que se duplica
  (`and` + `add x, x, x`) y termina cuando la máscara supera al multiplicador. Así tarda bits(B)
  vueltas, no 32.
- **Sin shifts:** dobles con `add x, x, x`; los bits se prueban con `and` contra la máscara.
- **Sin división:** se reemplaza por comparación escalada.
- **Rango:** los productos se comparan sin signo (`bltu`). No desbordan mientras W < ~170.000.
  Validado con la serie de estrés, que llega a W = 122.522.

## Mismas decisiones que la referencia

| Serie | Ticks | Órdenes | Testbench del curso | `--compara` |
|---|---:|---:|---|---|
| Meta (práctica), ronda 3 | 20.000 | 5 | 4/4 PASS | **IGUALES en los 20.000** |
| Estrés (`docs/mediciones/estres_serie.csv`) | 2.000 | 215 | 4/4 PASS | IGUALES |

Con Meta, V2 opera solo 5 veces. Por eso agregamos la serie de estrés: oscila entre 87 y 255 para
que el programa compre y venda cientos de veces y recorra todos sus caminos, incluidos los productos
grandes. Patrimonio final con Meta en el testbench: **17.095**, contra 9.695 de comprar y mantener.

## IC, ciclos, CPI y tiempo por tick

La ventana de un tick va desde que el precio queda en PRICE hasta que el programa vuelve a leer
STATUS. Incluye lo que tarda el bucle de espera en ver el precio. A 25 MHz:

| Serie | Ticks | IC prom. | IC peor | Ciclos prom. | Ciclos peor | CPI | t prom. | t peor |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Meta | 19.998 | 257,5 | 342 | 583,9 | 779 | 2,27 | 23,4 µs | 31,2 µs |
| Estrés | 1.998 | 321,1 | 499 | 727,2 | 1.133 | 2,26 | 29,1 µs | 45,3 µs |

Contra el período de cada ronda (ciclos disponibles = (T − 9,5 µs) · 25 MHz):

| Ronda | T | Ciclos disponibles | Peor tick Meta | Peor tick estrés |
|---|---|---:|---:|---:|
| 1 | 10 ms | 249.762 | 0,3 % | 0,5 % |
| 2 | 1 ms | 24.762 | 3,1 % | 4,6 % |
| 3 | 0,1 ms | 2.262 | **34,4 %** | **50,1 %** |

El CPI por clase es fijo:

- ALU, branch y `jal`: 2 ciclos;
- `sw`: 2;
- `lw`: 3.

El CPI promedio (2,27) sube un poco por las burbujas de los saltos tomados, que son el 11,4 % de
los ciclos. El 73,3 % del tick se va en `mul` (ver 4.3).

Nota sobre el "peor caso precio→decision" que imprime el testbench (18 ciclos): mide hasta la
**primera** escritura de DECISION, que es el `0` inmediato. Hasta la **última** escritura, el peor
caso con Meta es 757 ciclos (columna `ciclos_decision` de la sonda).

## Programas de las variantes

| Programa | Algoritmo | Hardware | Diferencia con `trade.s` |
|---|---|---|---|
| `sw/trade_mul.s` | V2 | D, multiplicador (`SOC_MUL`) | `mul` escribe A y B en el periférico, espera y lee P |
| `sw/trade_v1.s` | V1 | — | respaldo: reversión a la media, buffer de 16 precios en RAM |
| `sw/trade_sma.s` | V1 | B, suma móvil (`SOC_SMA`) | lee la suma en SPI + 0x0C en vez de mantener el buffer |
| `sw/trade_shift.s`, `sw/trade_sma_shift.s` | V1 | C, shifter | 16p con un `slli` |
| `sw/trade_v0.s`, `sw/echo.s` | v0, eco | — | kit de la prueba de conexión |
