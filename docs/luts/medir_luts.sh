#!/usr/bin/env bash
# Desglose de LUTs del SoC (tarea A6). No modifica rtl/: cada variante se
# arma en una copia temporal, se sintetiza (yosys) y se coloca (nextpnr, HX1K,
# 25 MHz, seed 1). Escribe en docs/luts/:
#   stat_jerarquico.txt  yosys stat por modulo (synth_ice40 -noflatten)
#   variantes.txt        LC, BRAM, celdas y fmax de cada variante
# Uso (desde la raiz del repo):  bash docs/luts/medir_luts.sh
# El programa cargado no cambia los LUTs (solo el contenido de la BRAM), asi
# que se usa sw/blink.hex mientras no exista sw/trade.hex.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$REPO/docs/luts
HEX=sw/blink.hex
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

srcs() { ls rtl/*.v rtl/espino_core/*.v | tr '\n' ' '; }

# --- Ediciones de cada variante (sobre la copia en $1/rtl) -----------------
ed_base() { :; }
ed_sin_debouncer() {
  python3 - "$1/rtl/pochoco_periph.v" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read()
i=s.index("  debounce_bank #"); j=s.index(");", i)+2
open(p,"w").write(s[:i]+"  assign btn_estable = 4'b0;"+s[j:])
EOF
}
ed_sin_contador() {
  python3 - "$1/rtl/pochoco_periph.v" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read()
i=s.index("  always @(posedge clk_i or negedge rst_ni) begin\n    if (!rst_ni) cyc_q")
j=s.index("  end\n", i)+6
open(p,"w").write(s[:i]+"  always @* cyc_q = 32'b0;\n"+s[j:])
EOF
}
ed_sin_7seg() {
  sed -i -E "s/assign seg(1|2)_o = hex2seg\(.*\);/assign seg\1_o = 7'b0;/" "$1/rtl/pochoco_periph.v"
}
ed_sin_leds() {
  sed -i "s/assign leds_o = led_q;/assign leds_o = 4'b0;/" "$1/rtl/pochoco_periph.v"
}
ed_sin_periph() {
  python3 - "$1/rtl/pochoco_soc.v" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read()
i=s.index("  pochoco_periph u_periph ("); j=s.index(");", i)+2
open(p,"w").write(s[:i]+"  assign o_LED = 4'b0;\n  assign seg1 = 7'b0;\n  assign seg2 = 7'b0;\n  assign per_rdata = 32'b0;"+s[j:])
EOF
}
ed_ram_no_rw_check() {
  sed -i 's/^  reg \[31:0\] mem \[0:NumWords-1\];/  (* no_rw_check *)\n  reg [31:0] mem [0:NumWords-1];/' "$1/rtl/pochoco_ram.v"
}
ed_sin_periph_y_no_rw_check() { ed_sin_periph "$1"; ed_ram_no_rw_check "$1"; }
ed_sin_debouncer_ni_contador() { ed_sin_debouncer "$1"; ed_sin_contador "$1"; }
ed_sin_debouncer_ni_contador_y_no_rw_check() { ed_sin_debouncer_ni_contador "$1"; ed_ram_no_rw_check "$1"; }

VARIANTES="base sin_debouncer sin_contador sin_7seg sin_leds sin_periph ram_no_rw_check sin_periph_y_no_rw_check \
  sin_debouncer_ni_contador sin_debouncer_ni_contador_y_no_rw_check"

# --- Desglose jerarquico ----------------------------------------------------
cd "$REPO"
yosys -q -p "read_verilog $(srcs); chparam -set MemFile \"$HEX\" pochoco_soc; \
  synth_ice40 -noflatten -top pochoco_soc; tee -q -o $OUT/stat_jerarquico.txt stat -top pochoco_soc" >/dev/null

# --- Variantes --------------------------------------------------------------
{
  echo "# $(yosys -V)"
  echo "# $(nextpnr-ice40 --version 2>&1 | head -1)"
  echo "# commit $(git rev-parse --short HEAD), programa $HEX, nextpnr --hx1k --package vq100 --freq 25 --seed 1"
  printf "%-42s %10s %7s %6s %6s %5s %10s\n" variante LC BRAM LUT4 CARRY FF fmax_MHz
} > "$OUT/variantes.txt"

for v in $VARIANTES; do
  D=$TMP/$v; mkdir -p "$D"; cp -r rtl goboard.pcf "$D/"; mkdir -p "$D/sw"; cp "$HEX" "$D/sw/"
  "ed_$v" "$D"
  ( cd "$D"
    if [ "$v" != base ] && diff -rq "$REPO/rtl" rtl >/dev/null; then
      echo "ERROR: la edicion de $v no cambio nada" >&2; exit 1; fi
    yosys -q -p "read_verilog $(srcs); chparam -set MemFile \"$HEX\" pochoco_soc; \
      synth_ice40 -top pochoco_soc -json soc.json; tee -q -o stat.txt stat" >/dev/null
    nextpnr-ice40 --hx1k --package vq100 --freq 25 --seed 1 \
      --json soc.json --pcf goboard.pcf --asc soc.asc > pnr.log 2>&1
    lc=$(grep -E "ICESTORM_LC: +[0-9]+/" pnr.log | tail -1 | awk '{print $3}' | tr -d /)
    ram=$(grep -E "ICESTORM_RAM: +[0-9]+/" pnr.log | tail -1 | awk '{print $3}' | tr -d /)
    fm=$(grep "Max frequency" pnr.log | tail -1 | sed -E 's/.*: ([0-9.]+) MHz.*/\1/')
    lut=$(awk '/SB_LUT4/{print $1}' stat.txt); car=$(awk '/SB_CARRY/{print $1}' stat.txt)
    ff=$(awk '/SB_DFF/{s+=$1} END{print s}' stat.txt)
    printf "%-42s %10s %7s %6s %6s %5s %10s\n" "$v" "$lc/1280" "$ram/16" "$lut" "$car" "$ff" "$fm"
  ) >> "$OUT/variantes.txt"
done
cat "$OUT/variantes.txt"
