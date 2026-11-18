# Copyright 2026 Universidad de los Andes.
# Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
# you may not use this file except in compliance with the License.
# SPDX-License-Identifier: SHL-0.51
#
# Course: Arquitectura de Computadores (2026)
# 
# Authors:
# - Nicolás Villegas <navillegas@miuandes.cl>

# Configuration
# TOP defaults to trade_top (Proyecto 4, the trading agent, see
# rtl/trade_top.v). Override on the command line to build a different module,
# e.g. `make TOP=pochoco_soc` to build the bare SoC instead.
TOP  ?= trade_top
PCF  := goboard.pcf
# Clock frequency (MHz) nextpnr checks timing against. The Go Board oscillator
# is 25 MHz; without --freq nextpnr only checks its 12 MHz default. Raise it
# if the clock is multiplied with the PLL.
FREQ ?= 25

# RTL Sources
SRC  := $(wildcard ./rtl/*.v ./rtl/**/*.v)

# Variantes de hardware del Proyecto 4 (macros de Verilog, las mismas para
# yosys y para Icarus). Ver docs/informe/4_3_codiseno.md:
#   make DEFS=ESPINO_SHIFTER trade_top.bin     shifter habilitado en la ALU
#   make DEFS=SOC_PLL trade_top.bin FREQ=...   reloj del PLL (solo trade_top)
DEFS ?=
VDEFS := $(addprefix -D,$(DEFS))
# Programa de trade_top: make TRADE_HEX=sw/trade_sma.hex DEFS=SOC_SMA trade_top.bin
CHPARAM_trade_top := $(if $(TRADE_HEX),chparam -set MemFile \"$(TRADE_HEX)\" trade_top;)

# Build Targets
JSON := $(TOP).json
ASC  := $(TOP).asc
BIN  := $(TOP).bin

.PHONY: all prog clean stats

# Default target
all: prog

# Program image baked into the top via $readmemh. Listing it as a
# dependency re-assembles it from its .s (rule sw/%.hex below) and forces a
# re-synthesis when it changes, so the bitstream never boots a stale image.
HEX_trade_top := $(or $(TRADE_HEX),sw/trade.hex)

# Step 1: Synthesis using Yosys
$(JSON): $(SRC) $(HEX_$(TOP))
	yosys -p "read_verilog $(VDEFS) $(SRC); $(CHPARAM_$(TOP)) synth_ice40 -top $(TOP) -json ${TOP}.json; stat"

# Step 2: Place and Route using NextPNR
$(ASC): $(JSON) $(PCF)
	nextpnr-ice40 --hx1k --package vq100 --freq $(FREQ) --json $(JSON) --pcf $(PCF) --asc $(ASC)

# Step 3: Bitstream Generation
$(BIN): $(ASC)
	icepack $(ASC) $(BIN)

# Step 4: Flash the Board
prog: $(BIN)
	iceprog $(BIN)

# Clean up generated files
clean:
	rm -f $(JSON) $(ASC) $(BIN) echo.json echo.asc echo.bin

# echo.bin: SoC con sw/echo.hex (kit de la prueba con la maestra). Usa
# pochoco_soc como top (mismos puertos que trade_top) cambiando MemFile,
# asi rtl/ no cambia. Flashear con: iceprog echo.bin
echo.bin: $(SRC) sw/echo.hex $(PCF)
	yosys -p "read_verilog $(VDEFS) $(SRC); chparam -set MemFile \"sw/echo.hex\" pochoco_soc; synth_ice40 -top pochoco_soc -json echo.json; stat"
	nextpnr-ice40 --hx1k --package vq100 --freq $(FREQ) --json echo.json --pcf $(PCF) --asc echo.asc
	icepack echo.asc echo.bin
# ---------------------------------------------------------------------------
# Proyecto 4: testbench del curso que emula a la FPGA maestra.
#
# tb/tb_proyecto_4.sv y tb/practica.csv son copias EXACTAS de los archivos
# entregados por el curso (no se editan). Para elegir ronda, largo y
# programa, este target genera sim/build/tb_proyecto_4.sv cambiando solo el
# bloque "Configuracion: pueden cambiar estos valores" del original
# (PROGRAMA, SERIE, PERIODO_NS, NTICKS) y lo corre desde la raiz del repo.
#
#   make tb_p4                         ronda 3, 2000 ticks, sw/trade.hex, serie Meta
#   make tb_p4 RONDA=1 NTICKS=50       ronda 1 (T = 10 ms), 50 ticks
#   make tb_p4 PROG=sw/echo.hex        otro programa (se ensambla su .s)
#   make tb_p4 NTICKS=20000            serie completa (~75 min en ronda 3)
#   make tb_p4 SERIE=tb/practica.csv   serie de practica anterior
#
# Detalle por tick en decisiones.csv (raiz del repo, igual que el original).
#
# Requiere Icarus Verilog >= 13: Icarus 12 (el paquete de Ubuntu) no acepta
# un string como argumento de $fgets y el testbench no compila. Ver README.
# ---------------------------------------------------------------------------
RONDA    ?= 3
NTICKS   ?= 2000
PROG     ?= sw/trade.hex
# Serie de practica: tb/practica_meta.csv (Meta 2022, precios 100-255) reemplaza
# a tb/practica.csv. Tiene que coincidir con -s de ref/trader.py.
SERIE    ?= tb/practica_meta.csv
IVERILOG ?= iverilog
VVP      ?= vvp

PERIODO_NS_1 := 10000000
PERIODO_NS_2 := 1000000
PERIODO_NS_3 := 100000
PERIODO_NS   := $(PERIODO_NS_$(RONDA))

TB_P4     := tb/tb_proyecto_4.sv
TB_P4_GEN := sim/build/tb_proyecto_4.sv
TB_P4_OUT := sim/build/tb_p4
# Modelo de simulacion de SB_RAM40_4K. yosys-config no viene en el paquete
# de Ubuntu; en ese caso se usa la ruta estandar /usr/share/yosys.
YOSYS_DAT := $(or $(shell yosys-config --datdir 2>/dev/null),/usr/share/yosys)
CELLS_SIM ?= $(YOSYS_DAT)/ice40/cells_sim.v

define GEN_TB_P4
	@test -n "$(PERIODO_NS)" || { echo "RONDA debe ser 1, 2 o 3"; exit 1; }
	@$(IVERILOG) -V 2>&1 | head -1 | grep -Eq 'version (1[3-9]|[2-9][0-9])' || { \
	  echo "ERROR: hace falta Icarus Verilog >= 13 (encontrado: $$($(IVERILOG) -V 2>&1 | head -1))."; \
	  echo "Ver la seccion 'Proyecto 4: testbench' del README."; exit 1; }
	@mkdir -p sim/build
	sed -E \
	  -e 's#(localparam string PROGRAMA   = )"[^"]*";#\1"$(PROG)";#' \
	  -e 's#(localparam string SERIE      = )"[^"]*";#\1"$(SERIE)";#' \
	  -e 's#(localparam int    PERIODO_NS = )[0-9]+;#\1$(PERIODO_NS);#' \
	  -e 's#(localparam int    NTICKS     = )[0-9]+;#\1$(NTICKS);#' \
	  $(TB_P4) > $(TB_P4_GEN)
	@grep -q 'PROGRAMA   = "$(PROG)";' $(TB_P4_GEN) && \
	 grep -q 'SERIE      = "$(SERIE)";' $(TB_P4_GEN) && \
	 grep -q 'PERIODO_NS = $(PERIODO_NS);' $(TB_P4_GEN) && \
	 grep -q 'NTICKS     = $(NTICKS);' $(TB_P4_GEN) || \
	 { echo "ERROR: no se pudo configurar $(TB_P4_GEN) (cambio el formato del original?)"; exit 1; }
endef

.PHONY: tb_p4
tb_p4: $(PROG) $(SERIE) $(SRC) $(TB_P4)
	$(GEN_TB_P4)
	$(IVERILOG) -g2012 $(VDEFS) -s tb_proyecto_4 -o $(TB_P4_OUT) $(CELLS_SIM) $(SRC) $(TB_P4_GEN)
	$(VVP) -n $(TB_P4_OUT)

# ---------------------------------------------------------------------------
# Mediciones por tick (M3, L1): el mismo tb del curso + sim/sonda_p4.sv, un
# modulo aparte que observa el SoC sin modificar el tb. Guarda en
# docs/mediciones/: <NOMBRE>.log (salida del tb), <NOMBRE>_ticks.csv
# (ciclos, IC y ciclos hasta DECISION por tick), <NOMBRE>_pc.csv (perfil por
# PC) y <NOMBRE>_decisiones.csv (copia de decisiones.csv).
#
#   make medir NOMBRE=sw                          trade.s, ronda 3, 2000 ticks
#   make medir NOMBRE=sw_20000 NTICKS=20000       serie completa (~80 min)
#   make medir NOMBRE=shifter DEFS=ESPINO_SHIFTER PROG=sw/trade_hw.hex
# ---------------------------------------------------------------------------
NOMBRE  ?= sw
SONDA   := sim/sonda_p4.sv
MED_DIR := docs/mediciones

.PHONY: medir
medir: $(PROG) $(SERIE) $(SRC) $(TB_P4) $(SONDA)
	$(GEN_TB_P4)
	@mkdir -p $(MED_DIR)
	$(IVERILOG) -g2012 $(VDEFS) -s tb_proyecto_4 -s sonda_p4 -o sim/build/tb_p4_$(NOMBRE) $(CELLS_SIM) $(SRC) $(TB_P4_GEN) $(SONDA)
	$(VVP) -n sim/build/tb_p4_$(NOMBRE) +TICKS=$(MED_DIR)/$(NOMBRE)_ticks.csv +PC=$(MED_DIR)/$(NOMBRE)_pc.csv | tee $(MED_DIR)/$(NOMBRE).log
	cp decisiones.csv $(MED_DIR)/$(NOMBRE)_decisiones.csv

# Ensamblar cualquier programa: make sw/trade.hex
sw/%.hex: sw/%.s sw/assembler.py
	python3 sw/assembler.py $< $@
