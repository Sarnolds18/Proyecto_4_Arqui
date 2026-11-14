# Pochoco SoC & Espino Core

> **Proyecto 4 — Pochoco Trader** (Arquitectura de Computadores, Uniandes, 2026-2):
> agente de inversión que recibe un precio por SPI en cada tick y responde comprar,
> vender o mantener, corriendo en Espino sobre la Go Board. Este repo parte de la
> entrega del Proyecto 2 (commit `bb042a1`). El juego de reflejos del Proyecto 2 ya no
> está aquí: sigue en [`Sarnolds18/Proyecto_2_Arqui`](https://github.com/Sarnolds18/Proyecto_2_Arqui),
> rama `proyecto2` (tag `p2-entrega`), y en el historial de este repo hasta `bb042a1`.

> Meet Pochoco SoC and Espino Core. Inspired by the native flora of the Pochoco trails, it is an entry-level, highly efficient architecture designed to flourish in resource-constrained environments.

![Pochoco SoC Architecture](pochoco_soc.svg)

Welcome to the repository! This project contains the RTL for a custom 32-bit processor and its surrounding System-on-Chip (SoC) designed for FPGA deployment. The design is kept straightforward to help explore and understand computer architecture fundamentals.

This is meant to be forked, not just cloned. You'll be poking around the RTL, so make it your own, we won't judge (we might even be a little proud).

## Repository Structure

The hardware is written in Verilog and divided into these main categories:

* **The Espino Core**: The central processing unit. It includes all standard pipeline stages like instruction fetch, instruction decode, an ALU for execution, a register file, a load/store unit for memory operations, and a pipeline controller. It implements [RV32E](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html) with a catch you might want to check out the code for.
* **The Pochoco SoC**: The top-level system wrapper. It connects the CPU core to a unified instruction/data RAM, physical board peripherals (like LEDs, switches, and displays), and an external SPI slave interface.
* **Build Files**: Constraints to map the design to the physical FPGA pins, and automation scripts for synthesis, routing, and flashing using an open-source toolchain.

## Memory Map

The SoC routes memory and data requests using a hardcoded address decoding scheme based on the highest bits of the 32-bit address.

* **`0x0000_0000` - Unified RAM**: The shared memory space for both instructions and data.
* **`0x8000_0000` - Board Peripherals**: Memory-mapped I/O for the physical board.
  * `Offset 0x00`: 7-Segment Displays
  * `Offset 0x04`: LEDs
  * `Offset 0x08`: Button Inputs (read-only)
  * `Offset 0x0C`: Cycle Counter — free-running 32-bit counter, increments every
    clock cycle from reset. Reading it returns the current count; writing any
    value to it reloads the counter to that value (write 0 to restart it from a
    known point, e.g. at the start of a timing window).
* **`0x8001_0000` - SPI Slave**: Custom SPI interface routing.
  * `Offset 0x00`: SPI Status (Chip Select state, New Data flag)
  * `Offset 0x04`: Received "Price" byte (from external master)
  * `Offset 0x08`: "Decision" byte (written by CPU to transmit)

Dive into the source code to see exactly how these components and connections are built under the hood!

## Proyecto 4: testbench del curso

`tb/tb_proyecto_4.sv` emula a la FPGA maestra: envía la serie `tb/practica.csv` por
SPI, lee el byte `DECISION` y lleva la contabilidad. Ambos archivos son **copias
exactas de los entregados por el curso y no se editan**.

```bash
make tb_p4                         # ronda 3 (T = 0,1 ms), 2000 ticks, sw/trade.hex
make tb_p4 RONDA=1 NTICKS=50       # ronda 1 (10 ms) o 2 (1 ms), otro largo
make tb_p4 PROG=sw/echo.hex        # otro programa (se ensambla su .s con sw/assembler.py)
make tb_p4 NTICKS=20000            # serie completa (~40 min en ronda 3)
```

El target genera `sim/build/tb_proyecto_4.sv`, una copia del original donde solo
cambian los valores del bloque *"Configuración: pueden cambiar estos valores"*
(`PROGRAMA`, `PERIODO_NS`, `NTICKS`), y lo corre desde la raíz del repo. El detalle por
tick queda en `decisiones.csv`. Referencia: 2000 ticks de la ronda 3 tardan ~4 min.

**Requiere Icarus Verilog ≥ 13.** Con Icarus 12, el paquete de Ubuntu, el testbench no
compila (`$fgets's first argument must be a reg`), porque esa versión no acepta un
`string` como argumento de `$fgets`. El Makefile revisa la versión y avisa. Opciones:

* **Con LibreLane instalado (Proyecto 3)**: su `nix-shell` trae Icarus 13.0 (devel,
  snapshot `s20250103`):

  ```bash
  nix-shell ~/librelane/shell.nix --run "make tb_p4"
  ```

* **Sin LibreLane**: compilar Icarus desde el código fuente (instala en `~/.local`,
  no toca el del sistema):

  ```bash
  sudo apt install build-essential autoconf gperf flex bison
  git clone https://github.com/steveicarus/iverilog.git ~/iverilog && cd ~/iverilog
  sh autoconf.sh && ./configure --prefix=$HOME/.local && make -j$(nproc) && make install
  ~/.local/bin/iverilog -V | head -1          # debe decir version 13.x
  ```

  y luego, desde el repo: `make tb_p4 IVERILOG=~/.local/bin/iverilog VVP=~/.local/bin/vvp`.

## How to Build

To synthesize and program the trader onto the Go Board, you will need the open-source FPGA toolchain.

1. Install the tools by following the instructions at the [oss-cad-suite-build repository](https://github.com/yosyshq/oss-cad-suite-build).
2. Once installed, ~~blindly copy-paste~~ (we strongly encourage reading the Makefile first to make sure we aren't deleting your home directory) the following command in the project root to synthesize, place & route, pack and flash the bitstream:

```bash
make all
```

**Proyecto 4:** `TOP` defaults to `trade_top` (`rtl/trade_top.v`, the trading agent, boots `sw/trade.hex`), so `make all` alone builds and programs the trader. The Makefile also exposes the individual steps if you only need one of them:

```bash
make trade_top.json        # synthesis only (yosys)
make trade_top.asc         # + place & route (nextpnr-ice40, timing checked at FREQ=25 MHz)
make trade_top.bin         # + pack the bitstream (icepack)
make prog                  # (re-)flash an already-built trade_top.bin (iceprog)
make clean                 # remove build/synthesis artifacts
make FREQ=36 all           # check timing at another clock (e.g. with the PLL)
```

The program image is a dependency of the synthesis step: `make` re-assembles `sw/trade.hex` from `sw/trade.s` with `sw/assembler.py` and re-synthesizes whenever it changes, since the `.hex` is baked into the bitstream via `$readmemh`. If `sw/trade.s` does not exist yet, the build stops with `No rule to make target 'sw/trade.hex'`.

### Flashing from WSL

Under WSL2 the Go Board's USB has to be passed through from Windows first (admin PowerShell, [usbipd-win](https://github.com/dorssel/usbipd-win)):

```powershell
usbipd list                        # find the FTDI device (VID 0403)
usbipd bind --busid <X-Y>          # first time only
usbipd attach --wsl --busid <X-Y>  # again after every unplug
```

If `iceprog` then reports `Can't find iCE FTDI USB device` even though `lsusb` lists `0403:6010`, your user lacks write access to the USB device. Either flash with `sudo ~/oss-cad-suite/bin/iceprog trade_top.bin`, or add a udev rule once:

```bash
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6010", MODE="0666"' | sudo tee /etc/udev/rules.d/53-goboard.rules
sudo service udev restart          # then replug + usbipd attach again
```

`iceprog` may print `flash ID: 0xFF 0xFF 0xFF 0xFF` under usbipd; as long as it ends with `VERIFY OK`, the board was programmed correctly.

### Power-on reset

`pochoco_soc.v` holds the CPU in reset for 2^12 clock cycles (~164 µs) after configuration. The original 15-cycle reset let the core start before the iCE40 block RAMs (program memory and register file) returned valid data. On the board this showed up as `00` on the displays and no LEDs, while simulation, which models ideal RAM, worked fine. The counter is 13 bits wide, and its MSB is used directly as `rst_ni`, so no comparator is needed. That matters because the design uses ~98% of the HX1K's logic cells.

## Software

The `sw/` folder holds RV32E assembly programs for the Espino Core. There are two separate toolchains in play here, used for two different purposes — do not mix them up:

* **`sw/trade.s` → `sw/trade.hex` (the Proyecto 4 program) — assembled with our own assembler, `sw/assembler.py`.** This is a from-scratch RV32E assembler written in plain Python 3 (standard library only, no dependencies) that does **not** invoke any external RISC-V assembler at any point.
* **`blink.s`, `7seg.s`, `buttons_leds.s` (example programs from the base repo, kept for reference) — assembled with a real RISC-V toolchain via `sw/Makefile`**, as described below. `sw/Makefile`'s generic `%.hex: %.s` rule shells out to `riscv64-unknown-elf-{as,ld,objcopy}`, so **never run `make trade` (or any target matching `trade.*`) inside `sw/`** — it would (re)assemble `trade.hex` with that external toolchain instead of `assembler.py`. Use the root Makefile or the explicit command below instead.

### Regenerating `sw/trade.hex` from `sw/trade.s`

From the repo root, `make sw/trade.hex` (the bitstream and `make tb_p4` targets already do it on their own), or by hand:

```bash
python3 sw/assembler.py sw/trade.s sw/trade.hex
```

No install step and no RISC-V toolchain needed — `assembler.py` only needs a Python 3 interpreter. It prints nothing on a clean assembly; warnings (e.g. a shift instruction, which this core executes as `ADD`, see the CATCH below) go to stderr, and any syntax/encoding error is reported compiler-style (file:line:column, with the offending source line underlined) and aborts without writing the `.hex`.

To check the assembler itself (pure `unittest`, no external RISC-V assembler involved):

```bash
cd sw
python3 -m unittest test_assembler.py -v
```

Besides the unit tests, `TestReferencePrograms` re-assembles `blink.s`, `7seg.s` and `buttons_leds.s` and compares them byte for byte with the `.hex` files of the base repo, which were built with the GNU RISC-V toolchain — an oracle independent of `assembler.py`. `TestTradeHexInSync` checks that a committed `sw/trade.hex` matches `sw/trade.s` (skipped while they don't exist).

### The other example programs (`blink.s`, `7seg.s`, `buttons_leds.s`)

These come from the base repo and are kept only as reference programs; they are **not** part of the deliverable and are still assembled with a real RISC-V toolchain, via `sw/Makefile`.

You'll need a RISC-V toolchain on your `PATH` (`riscv64-unknown-elf-{as,ld,objcopy}` on Debian/Ubuntu/WSL via `sudo apt install gcc-riscv64-unknown-elf`, or `brew install riscv64-unknown-elf-gcc` on macOS). If your toolchain uses a different prefix, override it on the command line rather than editing the Makefile:

```bash
cd sw
make blink                        # assembles blink.s -> blink.hex
make PREFIX=riscv64-elf- blink    # if your toolchain uses a different prefix
```

Drop a new `<name>.s` file in `sw/` and `make <name>` picks it up automatically, no `Makefile` changes needed (except for `trade.s`, see above). Don't forget to change the MemFile in `trade_top.v` if you want to boot a different image.

**CATCH:** The core implements [RV32E](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html), with one thing worth knowing: shift instructions (`SLL`/`SRL`/`SRA`/`SLLI`/`SRLI`/`SRAI`) are decoded correctly but disabled in the ALU to save LUTs on the target FPGA, so they currently execute as `ADD` instead. Avoid shifts in your assembly, or design your own shifter...
