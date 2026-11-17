# Kit para la prueba con la FPGA maestra

Dos bitstreams, los dos con el mismo SoC (`pochoco_soc`) y distinto programa en la RAM:

| Bitstream | Programa | Qué hace | Para qué sirve |
|---|---|---|---|
| `echo.bin` | `sw/echo.s` | Por cada precio: `DECISION = precio` y lo muestra en el 7-seg | Revisar cables, modo SPI y orden de bits |
| `trade_top.bin` | `sw/trade.s` (v0) | Reversión a la media de 16 precios, umbral 2, órdenes de 63 | Ver compras y ventas reales en la pantalla de la maestra |

Validación en simulación (testbench del curso, ronda 3, 2.000 ticks, commit `0786599`):
los dos dan **4/4 PASS** y **IGUALES** con `ref/trader.py`.

## Generar los bitstreams (desde la raíz del repo)

```bash
git pull
make trade_top.bin      # sw/trade.hex -> trade_top.bin (no flashea)
make echo.bin           # sw/echo.hex  -> echo.bin
```

Las dos salidas tienen que decir `PASS at 25.00 MHz` y ~1.260–1.275/1.280 LC. Los `.bin`
no se versionan (`.gitignore`): se regeneran desde el repo.

Flashear: `iceprog echo.bin` o `iceprog trade_top.bin`. Desde WSL, antes hay que conectar
la placa con `usbipd attach` (ver README, "Flashing from WSL").

## Llevar

> ⚠️ **Lucas tiene que ir sí o sí**: su Go Board es la única del grupo.

- [ ] La Go Board de Lucas y el cable USB
- [ ] 5 cables dupont: SCLK, MOSI, CS_n, MISO **y GND** (la tierra común es obligatoria)
- [ ] El notebook de Lucas con `iceprog` probado el mar 17, y `echo.bin` y `trade_top.bin`
      ya generados
- [ ] Respaldo: el notebook de Santiago. Con su toolchain los dos bitstreams compilan
      (Yosys 0.33, nextpnr 0.6, 1.270 y 1.256 LC); para flashear desde WSL hace falta
      `usbipd`.
- [ ] Este checklist

## Conexión (PMOD, según `goboard.pcf`)

| Señal | Pin FPGA | Dirección |
|---|---|---|
| SCLK | 62 | maestra → placa |
| MISO | 63 | placa → maestra |
| MOSI | 64 | maestra → placa |
| CS_n | 65 | maestra → placa |
| GND | GND del PMOD | común |

Confirmar contra el conector de la maestra antes de enchufar. Las dos placas trabajan a 3,3 V.

## Orden de la prueba

1. **Flashear `echo.bin`** antes de conectar los cables de señal.
   - Al recibir precios, el 7-seg debe cambiar en cada tick.
   - ⚠️ **El 7-seg muestra el precio en hexadecimal.** Para pasarlo a decimal: 16 × primer
     dígito + segundo dígito. Por ejemplo, `97` = 151, `48` = 72, `BE` = 190.
   - Si no cambia: revisar GND, CS_n y SCLK.
2. **Revisar el byte que recibe la maestra** (pedir que lo muestre). En el tick n tiene que
   ser **el precio del tick n−1**, porque el byte sale al comenzar la transacción.
   - Si sale el mismo número pero desplazado un bit, o con los bits al revés: es un problema
     de modo SPI (tiene que ser modo 0) o de orden de bits (MSB primero).
   - Si sale siempre `0x00`: revisar MISO (pin 63).
   - Con echo, la maestra va a ejecutar compras y ventas "al azar" (los bits [7:6] del precio).
     Es esperado.
3. **Flashear `trade_top.bin`.**
   - Durante los primeros 16 ticks solo mantiene (`0x00`): está llenando la media.
   - Después manda `0x7F` (comprar 63) cuando el precio está más de 2 bajo la media, y `0xBF`
     (vender 63) cuando está más de 2 sobre la media. Nunca tiene más de 63 acciones.
   - En la pantalla de la maestra deberían verse compras y ventas, y el patrimonio cambiando.
   - El 7-seg también muestra el precio en hexadecimal.
4. **Anotar todo** (va al informe; fotos de la pantalla):
   - [ ] frecuencia real de SCLK
   - [ ] período T que usaron y duración de una transacción
   - [ ] si CS_n baja una vez por tick
   - [ ] caja inicial y comisión definitivas
   - [ ] patrimonio que mostró la maestra con `trade_top.bin`

## Preguntar

- [ ] **¿Se resetea la placa entre rondas?** ¿Cómo empieza cada ronda? Nuestro SoC no tiene
      reset externo: el reset de encendido solo actúa al configurar la FPGA. Sin reset,
      `trade.s` arrastra su media y su posición (0/1) de una ronda a la siguiente. Si hay que
      reiniciar: ¿se re-flashea, se desenchufa o se puede usar un botón? (Esto decide si se
      mantienen los botones en L2; ver `docs/luts.md`.)
- [ ] ¿La competencia del 24/11 usa el mismo conector y los mismos pines?
- [ ] ¿Las 3 rondas van seguidas? ¿Cuántos ticks tiene cada una?
