# Kit para la FPGA maestra (prueba de conexión y competencia)

Dos bitstreams, los dos con el mismo SoC (`pochoco_soc`) y distinto programa en la RAM:

| Bitstream | Programa | Qué hace | Para qué sirve |
|---|---|---|---|
| `echo.bin` | `sw/echo.s` | Por cada precio: `DECISION = precio` y lo muestra en el 7-seg | Revisar cables, modo SPI y orden de bits |
| `trade_top.bin` | `sw/trade.s` (**V2, final**) | Exposición por nivel de precio: compra de a 40 acciones cuando el precio baja, vende de a 40 cuando sube | La competencia |

Validación en simulación (testbench del curso, ronda 3): `trade.s` (V2) da **4/4 PASS** e
**IGUALES** con `ref/trader.py` en los 20.000 ticks de la serie Meta (`docs/mediciones/v2_20000.log`);
`echo.s` da 4/4 PASS e IGUALES (500 ticks). Peor tick de V2: 779 ciclos de 2.262 (34 %).

## Generar los bitstreams (desde la raíz del repo)

```bash
git pull
make trade_top.bin      # sw/trade.hex -> trade_top.bin (no flashea)
make echo.bin           # sw/echo.hex  -> echo.bin
```

Las dos salidas tienen que decir `PASS at 25.00 MHz` (trade_top: ~1.183/1.280 LC; echo: ~1.108).
Los `.bin` no se versionan (`.gitignore`): se regeneran desde el repo. Si antes se armó una
variante con `DEFS=...`, hacer `make clean` primero.

Flashear: `iceprog echo.bin` o `iceprog trade_top.bin`. Desde WSL, antes hay que conectar
la placa con `usbipd attach` (ver README, "Flashing from WSL").

## Llevar

> ⚠️ **Lucas tiene que ir sí o sí**: su Go Board es la única del grupo.

- [ ] La Go Board de Lucas y el cable USB
- [ ] 5 cables dupont: SCLK, MOSI, CS_n, MISO **y GND** (la tierra común es obligatoria)
- [ ] El notebook de Lucas con `iceprog` probado el mar 17, y `echo.bin` y `trade_top.bin`
      ya generados
- [ ] Respaldo: el notebook de Santiago (también tiene Go Board). Con su toolchain los dos
      bitstreams compilan (Yosys 0.33, nextpnr 0.6); para flashear desde WSL hace falta
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
     dígito + segundo dígito. Por ejemplo, `64` = 100, `A5` = 165, `FF` = 255.
   - Si no cambia: revisar GND, CS_n y SCLK.
2. **Revisar el byte que recibe la maestra** (pedir que lo muestre). En el tick n tiene que
   ser **el precio del tick n−1**, porque el byte sale al comenzar la transacción.
   - Si sale el mismo número pero desplazado un bit, o con los bits al revés: es un problema
     de modo SPI (tiene que ser modo 0) o de orden de bits (MSB primero).
   - Si sale siempre `0x00`: revisar MISO (pin 63).
   - **Si sale bien salvo el bit 7** (precios ≥ 128 llegan como precio − 128): la maestra da
     el primer flanco de SCLK muy pronto. El esclavo carga el bit 7 en MISO ~3 ciclos
     (~120 ns) después de que baja CS_n. Preguntar el tiempo entre CS_n y el primer flanco.
   - Con echo, la maestra va a ejecutar compras y ventas "al azar" (los bits [7:6] del precio).
     Es esperado. Con precios de 100 a 255 (serie Meta): de 100 a 127 compra, de 128 a 191
     vende y de 192 a 255 mantiene (bits `11`).
3. **Flashear `trade_top.bin`** (V2).
   - Manda `0x68` (comprar 40) o `0xA8` (vender 40), y si no, `0x00`. **Opera poco**: unas 5
     órdenes en 20.000 ticks en la serie de práctica. Que pasen cientos de ticks sin órdenes es
     normal.
   - Compra cuando el precio baja (más fuerte cerca de 100) y vende cuando sube (cerca de 255 queda
     sin acciones). Arranca en caja: con el precio en la mitad del rango puede no comprar al
     principio.
   - El 7-seg muestra el precio en hexadecimal.
4. **Antes de cada ronda: apretar SW1 (reset).** Reinicia el programa (caja 10.000, 0 acciones)
   en 164 µs, igual que la maestra al empezar la ronda. No hace falta volver a flashear.
5. **Anotar todo** (va al informe; fotos de la pantalla):
   - [ ] frecuencia real de SCLK
   - [ ] período T que usaron y duración de una transacción
   - [ ] si CS_n baja una vez por tick
   - [ ] caja inicial y comisión definitivas
   - [ ] patrimonio que mostró la maestra con `trade_top.bin`

## Preguntar

- [x] Reset entre rondas: sí (confirmado). Lo hacemos con **SW1** (botón de reset, ver paso 4).
- [ ] ¿Se puede usar que cada ronda está normalizada a 100–255? V2 se basa en eso. Respaldo si no:
      `make clean && make TRADE_HEX=sw/trade_v1.hex trade_top.bin` (V1).
- [ ] ¿La competencia del 24/11 usa el mismo conector y los mismos pines?
- [x] 20.000 ticks por ronda (confirmado). ¿Las 3 rondas van seguidas?
