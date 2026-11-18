#!/usr/bin/env bash
# Validacion post-sintesis de RAM_NO_RW_CHECK (L2).
#
# Icarus ignora (* no_rw_check *), asi que simular el RTL no prueba nada.
# Este script sintetiza solo pochoco_ram con yosys (synth_ice40, con el
# atributo y el programa ya cargado en las SB_RAM40_4K), lo envuelve en un
# modulo con la interfaz original y corre el testbench del curso con ese
# netlist en lugar de rtl/pochoco_ram.v. El resto del SoC queda en RTL.
# Luego compara las decisiones con ref/trader.py.
#
# Uso (desde la raiz del repo, yosys e Icarus >= 13 en el PATH):
#   bash sim/postsintesis_ram.sh [PROGRAMA] [NTICKS] [DEFS] [SERIE]
#   bash sim/postsintesis_ram.sh sw/trade.hex 500
#   bash sim/postsintesis_ram.sh sw/trade_mul.hex 500 SOC_MUL docs/mediciones/estres_serie.csv
# Salida: docs/mediciones/postsintesis_<programa>.log
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
PROG=${1:-sw/trade.hex}
NTICKS=${2:-500}
DEFS=${3:-}
SERIE=${4:-tb/practica_meta.csv}
NOMBRE=$(basename "$PROG" .hex)$( [ "$SERIE" = tb/practica_meta.csv ] || echo "_$(basename "$SERIE" .csv)")
LOG=$REPO/docs/mediciones/postsintesis_$NOMBRE.log
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$REPO"
python3 sw/assembler.py "${PROG%.hex}.s" "$PROG" 2>/dev/null

# 1) netlist de la RAM con no_rw_check y el programa cargado
yosys -q -l "$TMP/yosys.log" -p "read_verilog -DRAM_NO_RW_CHECK rtl/pochoco_ram.v; \
  chparam -set NumWords 512 -set MemFile \"$PROG\" pochoco_ram; \
  synth_ice40 -top pochoco_ram; rename pochoco_ram pochoco_ram_net; \
  write_verilog -noattr $TMP/ram_net.v" > /dev/null
grep -q SB_RAM40_4K "$TMP/ram_net.v"
EMUL=$(grep -c "emulate" "$TMP/yosys.log" || true)

# 2) envoltorio con la interfaz de rtl/pochoco_ram.v
cat > "$TMP/ram_wrap.v" <<'EOF'
module pochoco_ram #(parameter NumWords = 512, parameter MemFile = "") (
  input wire clk_i, input wire a_req_i, input wire [31:0] a_addr_i, output wire [31:0] a_rdata_o,
  input wire b_req_i, input wire b_we_i, input wire [3:0] b_be_i, input wire [31:0] b_addr_i,
  input wire [31:0] b_wdata_i, output wire [31:0] b_rdata_o);
  pochoco_ram_net u (.clk_i(clk_i), .a_req_i(a_req_i), .a_addr_i(a_addr_i), .a_rdata_o(a_rdata_o),
    .b_req_i(b_req_i), .b_we_i(b_we_i), .b_be_i(b_be_i), .b_addr_i(b_addr_i),
    .b_wdata_i(b_wdata_i), .b_rdata_o(b_rdata_o));
endmodule
EOF

# 3) tb del curso (copia configurada) con el netlist de la RAM
sed -E -e "s#(localparam string PROGRAMA   = )\"[^\"]*\";#\1\"$PROG\";#" \
       -e "s#(localparam string SERIE      = )\"[^\"]*\";#\1\"$SERIE\";#" \
       -e "s#(localparam int    NTICKS     = )[0-9]+;#\1$NTICKS;#" \
       tb/tb_proyecto_4.sv > "$TMP/tb.sv"
RTL=$(ls rtl/*.v rtl/espino_core/*.v | grep -v pochoco_ram.v)
VD=""; for d in $DEFS; do VD="$VD -D$d"; done
CELLS=$(yosys-config --datdir)/ice40/cells_sim.v
iverilog -g2012 $VD -s tb_proyecto_4 -o "$TMP/sim" "$CELLS" $RTL "$TMP/ram_wrap.v" "$TMP/ram_net.v" "$TMP/tb.sv"
mkdir -p "$TMP/run" && ln -s "$REPO/sw" "$TMP/run/sw" && ln -s "$REPO/tb" "$TMP/run/tb" && ln -s "$REPO/docs" "$TMP/run/docs"
{
  echo "# post-sintesis de pochoco_ram con RAM_NO_RW_CHECK, programa $PROG, serie $SERIE, $NTICKS ticks, ronda 3, macros: ${DEFS:--}"
  echo "# $(yosys -V); lineas 'emulate' en el log de yosys: $EMUL (0 = sin logica de emulacion)"
  (cd "$TMP/run" && vvp -n "$TMP/sim")
  python3 ref/trader.py -n "$NTICKS" -s "$SERIE" --compara "$TMP/run/decisiones.csv"
} 2>&1 | tee "$LOG"
