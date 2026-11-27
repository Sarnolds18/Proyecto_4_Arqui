# Kit para la FPGA maestra (prueba de conexión y competencia)

> **Competencia: viernes 27/11, 16:00.** El SPI ya se probó con la maestra en las prácticas del
> 20/11 y el 25/11, y funcionó. La placa tiene `trade.s` (el que ganó la práctica): el 25/11 se leyó
> la flash con `iceprog -r` y es idéntica bit a bit a `make trade_top.bin` de `main`.
> **Antes de entregar la placa hay que preguntar si reinician las placas entre series** y cargar el
> programa que corresponda (ver "Mañana: qué preguntar y qué cargar"). Los pasos 1 a 3 de "Orden de
> la prueba" son solo por si algo falla.

## Mañana: qué preguntar y qué cargar

Preguntar a los ayudantes, antes de entregar la placa:

1. ¿Aprietan SW1 o desconectan la placa entre una serie y la siguiente?
2. ¿Van a pausar la maestra (BTNC) a mitad de alguna serie? ¿Cuánto rato?

| Respuesta | Qué cargar |
|---|---|
| Sí reinician entre series | `trade.s`: **no hay que flashear nada**, ya está en la placa |
| No reinician, o no saben | `trade_v2r`: se reinicia sola después de 1 s sin precios |
| No reinician y pausan más de 1 s a mitad de serie | Igual `trade_v2r`: un reinicio falso cuesta ~−270 en promedio y no reiniciar ~−2.500 por serie |

Tener los dos `.bin` generados de antemano (no compilar allá), con el `iceprog` probado en el mismo
computador:

```bash
make clean && make trade_top.bin && cp trade_top.bin trade.bin                              # trade.s
make clean && make TRADE_HEX=sw/trade_v2r.hex trade_top.bin && cp trade_top.bin trade_v2r.bin  # v2r
sha256sum trade.bin trade_v2r.bin   # trade.bin = 025901f5... (el de la placa), trade_v2r.bin = b0c38111...
bash scripts/respaldo_placa.sh      # siempre antes de flashear
iceprog trade_v2r.bin               # o: iceprog trade.bin, para volver al de la practica
```

Con `trade_v2r` la placa se reinicia sola cada 1 s mientras no le llegan precios. Eso es normal y no
se ve (el 7-seg sigue con el último precio). Después de flashear, SW1 sigue funcionando igual.

Dos bitstreams, los dos con el mismo SoC (`pochoco_soc`) y distinto programa en la RAM:

| Bitstream | Programa | Qué hace | Para qué sirve |
|---|---|---|---|
| `echo.bin` | `sw/echo.s` | Por cada precio: `DECISION = precio` y lo muestra en el 7-seg | Revisar cables, modo SPI y orden de bits |
| `trade_top.bin` | `sw/trade.s` (**V2, final**) | Exposición por nivel de precio: compra de a 40 acciones cuando el precio baja, vende de a 40 cuando sube | La competencia, si reinician la placa entre series |
| `trade_top.bin` con `TRADE_HEX=sw/trade_v2r.hex` | `sw/trade_v2r.s` | V2 + reinicio automático tras 1 s sin precios | La competencia, si **no** reinician la placa entre series |

Validación en simulación (testbench del curso, ronda 3): `trade.s` (V2) da **4/4 PASS** e
**IGUALES** con `ref/trader.py` en los 20.000 ticks de la serie Meta (`docs/mediciones/v2_20000.log`);
`echo.s` da 4/4 PASS e IGUALES (500 ticks). Peor tick de V2: 653 ciclos de 2.262 (29 %).

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

> ⚠️ **El grupo tiene una sola Go Board, y la tiene Santiago**: él tiene que ir sí o sí.

- [ ] La Go Board y el cable USB
- [ ] 5 cables dupont: SCLK, MOSI, CS_n, MISO **y GND** (la tierra común es obligatoria)
- [ ] Un computador con `iceprog` probado y los dos `.bin` ya generados desde `main`:
      `trade.bin` y `trade_v2r.bin` (ver "Mañana: qué preguntar y qué cargar"). El de Santiago
      compila con los paquetes de apt (Yosys 0.33, nextpnr 0.6, icestorm 20230218) y flashea desde
      WSL con `usbipd` (probado el 25/11).
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
     En simulación (`sim/barrido_spi.sh`) funciona con 40 ns entre CS_n y el primer flanco y
     SCLK de hasta 4 MHz, así que es muy poco probable.
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
4. **Antes de cada ronda, y cada vez que la maestra reinicia la serie (su botón BTNR): apretar
   SW1 (reset)** (con `trade_v2r` no hace falta si pasa más de 1 s entre series). No tocar la placa durante una ronda: un reset a mitad de ronda desincroniza la
   cuenta del programa con la de la maestra. SW1 reinicia el programa (caja 10.000, 0 acciones)
   en 164 µs, igual que la maestra al empezar la ronda. No hace falta volver a flashear. Si la
   maestra solo pausa (BTNC), no hay que hacer nada.
5. **Anotar todo** (va al informe; fotos de la pantalla):
   - [ ] frecuencia real de SCLK
   - [ ] período T que usaron y duración de una transacción
   - [ ] si CS_n baja una vez por tick
   - [ ] caja inicial y comisión definitivas
   - [ ] patrimonio que mostró la maestra con `trade_top.bin`

## Preguntar

- [x] Reset entre rondas en las prácticas: sí, lo hacíamos nosotros con **SW1** (paso 4).
- [ ] **Competencia: ¿reinician ellos las placas entre series?** Preguntado en el Foro el 25/11,
      sin respuesta. Preguntar en persona (ver "Mañana: qué preguntar y qué cargar").
- [x] ¿Se puede usar que cada ronda está normalizada a 100–255? Sí: el anuncio del 17/11 dice que
      las series de la competencia se normalizan igual que `practica_meta.csv` (100–255).
- [x] ¿La competencia usa el mismo conector y los mismos pines? En las prácticas del 20/11 y el
      25/11 se usaron los de `goboard.pcf` y funcionó.
- [x] 20.000 ticks por ronda (confirmado). ¿Las 3 rondas van seguidas?
