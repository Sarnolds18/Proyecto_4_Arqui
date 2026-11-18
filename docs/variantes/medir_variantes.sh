#!/usr/bin/env bash
# Sintesis + place & route de cada variante de hardware (L5). Cada variante
# se arma en docs/variantes/<variante>/ con su yosys.log y nextpnr.log, y el
# resumen queda en docs/variantes/variantes.txt (LC, BRAM, fmax, PASS/FAIL a
# la frecuencia objetivo). No modifica rtl/: las variantes se eligen con
# macros (DEFS) y parametros (chparam), igual que el Makefile.
#
# Uso (desde la raiz del repo, con yosys y nextpnr-ice40 en el PATH):
#   bash docs/variantes/medir_variantes.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$REPO/docs/variantes
cd "$REPO"
SRC=$(ls rtl/*.v rtl/espino_core/*.v | tr '\n' ' ')
SEED=1

# nombre | macros | programa | frecuencia objetivo (MHz) | chparam extra
VARIANTES=(
  "con_contador||sw/trade.hex|25|chparam -set CYCLE_COUNTER 1 pochoco_periph;"
  "v2_sw||sw/trade.hex|25|"
  "v2_sw_nrw|RAM_NO_RW_CHECK|sw/trade.hex|25|"
  "d_mul|SOC_MUL|sw/trade_mul.hex|25|"
  "d_mul_nrw|SOC_MUL RAM_NO_RW_CHECK|sw/trade_mul.hex|25|"
  "v1_sw||sw/trade_v1.hex|25|"
  "b_sma|SOC_SMA|sw/trade_sma.hex|25|"
  "b_sma_nrw|SOC_SMA RAM_NO_RW_CHECK|sw/trade_sma.hex|25|"
  "c_shift_nrw|ESPINO_SHIFTER RAM_NO_RW_CHECK|sw/trade_shift.hex|25|"
  "c_full_nrw|ESPINO_SHIFTER_FULL RAM_NO_RW_CHECK|sw/trade_shift.hex|25|"
  "bc_nrw|SOC_SMA ESPINO_SHIFTER RAM_NO_RW_CHECK|sw/trade_sma_shift.hex|25|"
)
# El PLL (alternativa A) no se puede colocar en la HX1K VQ100 de la Go Board:
# ver docs/variantes/pll_vq100/.

for f in trade trade_v1 trade_mul trade_sma trade_shift trade_sma_shift; do
  python3 sw/assembler.py sw/$f.s sw/$f.hex 2>/dev/null
done

construir() {
  IFS='|' read -r v defs hex freq extra <<< "$1"
  D=$OUT/$v; mkdir -p "$D"
  vdefs=""; for d in $defs; do vdefs="$vdefs -D$d"; done
  yosys -l "$D/yosys.log" -q -p "read_verilog $vdefs $SRC; $extra \
    chparam -set MemFile \"$hex\" trade_top; synth_ice40 -top trade_top -json $D/trade_top.json; \
    tee -q -o $D/stat.txt stat" > /dev/null
  nextpnr-ice40 --hx1k --package vq100 --freq "$freq" --seed $SEED \
    --json "$D/trade_top.json" --pcf goboard.pcf --asc "$D/trade_top.asc" > "$D/nextpnr.log" 2>&1 \
    && icepack "$D/trade_top.asc" "$D/trade_top.bin" || echo "FALLA: $v (ver $D/nextpnr.log)" >&2
}

for v in "${VARIANTES[@]}"; do construir "$v" & done
wait

{
  echo "# $(yosys -V)"
  echo "# $(nextpnr-ice40 --version 2>&1 | head -1)"
  echo "# commit base $(git rev-parse --short HEAD) (+ working tree), nextpnr --hx1k --package vq100 --seed $SEED"
  printf "%-14s %-40s %-24s %6s %10s %7s %9s %s\n" variante macros programa f_MHz LC BRAM fmax_MHz timing
  for v in "${VARIANTES[@]}"; do
    IFS='|' read -r n defs hex freq extra <<< "$v"
    L=$OUT/$n/nextpnr.log
    lc=$(grep -E "ICESTORM_LC: +[0-9]+/" "$L" | tail -1 | awk '{print $3}' | tr -d / || true)
    ram=$(grep -E "ICESTORM_RAM: +[0-9]+/" "$L" | tail -1 | awk '{print $3}' | tr -d / || true)
    fm=$(grep "Max frequency" "$L" | tail -1 | sed -E 's/.*: ([0-9.]+) MHz.*/\1/' || true)
    ok=$(grep "Max frequency" "$L" | tail -1 | grep -oE "PASS|FAIL" || echo "ERROR")
    printf "%-14s %-40s %-24s %6s %10s %7s %9s %s\n" "$n" "${defs:--}" "$hex" "$freq" "${lc:-?}/1280" "${ram:-?}/16" "${fm:-?}" "$ok"
  done
} > "$OUT/variantes.txt"
cat "$OUT/variantes.txt"
