#!/usr/bin/env bash
# Simulacion post-sintesis del SoC completo: corre el tb del curso con el netlist
# que genera yosys para trade_top (LUTs, FFs y SB_RAM40_4K con el programa
# cargado), en lugar del RTL. Confirma que lo que se sintetiza toma las mismas
# decisiones que ref/trader.py.
#
# Uso (desde la raiz del repo, yosys e Icarus >= 13 en el PATH):
#   bash sim/postsintesis_soc.sh [PROGRAMA] [NTICKS] [SERIE]
#   bash sim/postsintesis_soc.sh sw/trade.hex 400 docs/mediciones/estres_serie.csv
#   bash sim/postsintesis_soc.sh sw/trade_v2r.hex 400 docs/mediciones/estres_serie.csv
# Salida: docs/mediciones/postsintesis_soc_<programa>_<serie>.log
#
# El tb del curso mira senales internas del esclavo SPI (dut.u_spi) para medir
# el peor caso; en el netlist no existen, asi que la copia del tb quita ese
# bloque. Por eso los chequeos "escribe DECISION" y "lee todos los precios"
# salen FAIL aqui: lo que vale es la comparacion tick a tick con la referencia.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
PROG=${1:-sw/trade.hex}
NTICKS=${2:-400}
SERIE=${3:-tb/practica_meta.csv}
LOG=$REPO/docs/mediciones/postsintesis_soc_$(basename "$PROG" .hex)_$(basename "$SERIE" .csv).log
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
YOSYS_DAT=$(yosys-config --datdir 2>/dev/null || echo /usr/share/yosys)
cd "$REPO"
python3 sw/assembler.py "${PROG%.hex}.s" "$PROG" 2>/dev/null

# 1) netlist de trade_top con el programa en la BRAM
yosys -q -p "read_verilog rtl/*.v rtl/espino_core/*.v; chparam -set MemFile \"$PROG\" trade_top; \
  synth_ice40 -top trade_top; rename trade_top trade_top_net; write_verilog -noattr $TMP/net.v" > /dev/null

# 2) envoltorio con la interfaz de pochoco_soc (la que instancia el tb)
cat > "$TMP/wrap.v" <<'EOF'
module pochoco_soc #(parameter NumWords = 512, parameter MemFile = "") (
  input wire i_Clk, output wire [3:0] o_LED, input wire [3:0] i_Switch,
  output wire o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D, o_Segment1_E, o_Segment1_F, o_Segment1_G,
  output wire o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D, o_Segment2_E, o_Segment2_F, o_Segment2_G,
  input wire i_SPI_SCLK, input wire i_SPI_MOSI, input wire i_SPI_CS_n, output wire o_SPI_MISO);
  trade_top_net u (.i_Clk(i_Clk), .o_LED(o_LED), .i_Switch(i_Switch),
    .o_Segment1_A(o_Segment1_A), .o_Segment1_B(o_Segment1_B), .o_Segment1_C(o_Segment1_C),
    .o_Segment1_D(o_Segment1_D), .o_Segment1_E(o_Segment1_E), .o_Segment1_F(o_Segment1_F),
    .o_Segment1_G(o_Segment1_G), .o_Segment2_A(o_Segment2_A), .o_Segment2_B(o_Segment2_B),
    .o_Segment2_C(o_Segment2_C), .o_Segment2_D(o_Segment2_D), .o_Segment2_E(o_Segment2_E),
    .o_Segment2_F(o_Segment2_F), .o_Segment2_G(o_Segment2_G),
    .i_SPI_SCLK(i_SPI_SCLK), .i_SPI_MOSI(i_SPI_MOSI), .i_SPI_CS_n(i_SPI_CS_n), .o_SPI_MISO(o_SPI_MISO));
endmodule
EOF

# 3) tb del curso (copia) sin el bloque "always" que mira dentro del dut
awk '/^  always @\(posedge clk\) begin$/ {salta=1} salta && /^  end$/ {salta=0; next} !salta' \
  tb/tb_proyecto_4.sv | sed -E \
  -e "s#(SERIE      = )\"[^\"]*\"#\1\"$SERIE\"#" \
  -e "s#(NTICKS     = )[0-9]+#\1$NTICKS#" > "$TMP/tb.sv"
grep -q "dut\." "$TMP/tb.sv" && { echo "error: el tb todavia mira dentro del dut"; exit 1; }
iverilog -g2012 -s tb_proyecto_4 -o "$TMP/sim" "$YOSYS_DAT/ice40/cells_sim.v" "$TMP/net.v" "$TMP/wrap.v" "$TMP/tb.sv"

mkdir -p "$TMP/run" && ln -s "$REPO/tb" "$TMP/run/tb" && ln -s "$REPO/docs" "$TMP/run/docs"
{
  echo "# post-sintesis del SoC: $PROG, $NTICKS ticks de $SERIE"
  (cd "$TMP/run" && vvp -n ../sim)
  (cd "$TMP/run" && python3 "$REPO/ref/trader.py" -n "$NTICKS" -s "$SERIE" --compara decisiones.csv)
} | tee "$LOG"
