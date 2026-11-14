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
# TOP defaults to game_top (the FPGA top-level for the reflex game, see
# rtl/game_top.v). Override on the command line to build a different module,
# e.g. `make TOP=pochoco_soc` to build the bare SoC instead.
TOP  ?= game_top
PCF  := goboard.pcf

# RTL Sources
SRC  := $(wildcard ./rtl/*.v ./rtl/**/*.v)

# Build Targets
JSON := $(TOP).json
ASC  := $(TOP).asc
BIN  := $(TOP).bin

.PHONY: all prog clean stats

# Default target
all: prog

# Step 1: Synthesis using Yosys
$(JSON): $(SRC)
	yosys -p "read_verilog $(SRC); synth_ice40 -top $(TOP) -json ${TOP}.json; stat"

# Step 2: Place and Route using NextPNR
$(ASC): $(JSON) $(PCF)
	nextpnr-ice40 --hx1k --package vq100 --json $(JSON) --pcf $(PCF) --asc $(ASC)

# Step 3: Bitstream Generation
$(BIN): $(ASC)
	icepack $(ASC) $(BIN)

# Step 4: Flash the Board
prog: $(BIN)
	iceprog $(BIN)

# Clean up generated files
clean:
	rm -f $(JSON) $(ASC) $(BIN)
# ---------------------------------------------------------------------------
# Proyecto 4: testbench del curso que emula a la FPGA maestra.
#
# tb/tb_proyecto_4.sv y tb/practica.csv son copias EXACTAS de los archivos
# entregados por el curso (no se editan). Para elegir ronda, largo y
# programa, este target genera sim/build/tb_proyecto_4.sv cambiando solo el
# bloque "Configuracion: pueden cambiar estos valores" del original
# (PROGRAMA, PERIODO_NS, NTICKS) y lo corre desde la raiz del repo.
#
#   make tb_p4                         ronda 3, 2000 ticks, sw/trade.hex
#   make tb_p4 RONDA=1 NTICKS=50       ronda 1 (T = 10 ms), 50 ticks
#   make tb_p4 PROG=sw/echo.hex        otro programa (se ensambla su .s)
#   make tb_p4 NTICKS=20000            serie completa (~40 min en ronda 3)
#
# Detalle por tick en decisiones.csv (raiz del repo, igual que el original).
#
# Requiere Icarus Verilog >= 13: Icarus 12 (el paquete de Ubuntu) no acepta
# un string como argumento de $fgets y el testbench no compila. Ver README.
# ---------------------------------------------------------------------------
RONDA    ?= 3
NTICKS   ?= 2000
PROG     ?= sw/trade.hex
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

.PHONY: tb_p4
tb_p4: $(PROG) $(SRC) $(TB_P4)
	@test -n "$(PERIODO_NS)" || { echo "RONDA debe ser 1, 2 o 3"; exit 1; }
	@$(IVERILOG) -V 2>&1 | head -1 | grep -Eq 'version (1[3-9]|[2-9][0-9])' || { \
	  echo "ERROR: hace falta Icarus Verilog >= 13 (encontrado: $$($(IVERILOG) -V 2>&1 | head -1))."; \
	  echo "Ver la seccion 'Proyecto 4: testbench' del README."; exit 1; }
	@mkdir -p sim/build
	sed -E \
	  -e 's#(localparam string PROGRAMA   = )"[^"]*";#\1"$(PROG)";#' \
	  -e 's#(localparam int    PERIODO_NS = )[0-9]+;#\1$(PERIODO_NS);#' \
	  -e 's#(localparam int    NTICKS     = )[0-9]+;#\1$(NTICKS);#' \
	  $(TB_P4) > $(TB_P4_GEN)
	@grep -q 'PROGRAMA   = "$(PROG)";' $(TB_P4_GEN) && \
	 grep -q 'PERIODO_NS = $(PERIODO_NS);' $(TB_P4_GEN) && \
	 grep -q 'NTICKS     = $(NTICKS);' $(TB_P4_GEN) || \
	 { echo "ERROR: no se pudo configurar $(TB_P4_GEN) (cambio el formato del original?)"; exit 1; }
	$(IVERILOG) -g2012 -s tb_proyecto_4 -o $(TB_P4_OUT) $(CELLS_SIM) $(SRC) $(TB_P4_GEN)
	$(VVP) -n $(TB_P4_OUT)

# Ensamblar cualquier programa: make sw/trade.hex
sw/%.hex: sw/%.s sw/assembler.py
	python3 sw/assembler.py $< $@
