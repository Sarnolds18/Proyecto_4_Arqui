#!/usr/bin/env bash
# Barrido de tiempos del SPI: corre sw/echo.s con el tb del curso cambiando solo
# la velocidad de SCLK y el tiempo entre que baja CS_n y el primer flanco, y
# compara con ref/trader.py -e echo. Sirve para saber cuanto margen hay si la
# maestra de la competencia usa otro SCLK (el enunciado dice <= 1 MHz).
#
# Uso (desde la raiz del repo, Icarus >= 13 en el PATH):
#   bash sim/barrido_spi.sh [NTICKS]          # por defecto 300 ticks por punto
# Salida: docs/mediciones/spi_barrido.txt
#
# El tb original (tb/tb_proyecto_4.sv) no se toca: se genera una copia por punto
# en un directorio temporal cambiando las lineas "#1000;" (CS_n -> primer
# flanco) y "#500 sclk" (medio periodo de SCLK).
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
NTICKS=${1:-300}
OUT=$REPO/docs/mediciones/spi_barrido.txt
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
YOSYS_DAT=$(yosys-config --datdir 2>/dev/null || echo /usr/share/yosys)
CELLS=$YOSYS_DAT/ice40/cells_sim.v
cd "$REPO"
python3 sw/assembler.py sw/echo.s sw/echo.hex 2>/dev/null
grep -q '^    #1000;$' tb/tb_proyecto_4.sv && grep -q '#500 sclk = 1;' tb/tb_proyecto_4.sv \
  || { echo "error: cambio el formato del tb del curso"; exit 1; }

punto() {   # punto C H: C = ns de CS_n al primer flanco, H = medio periodo de SCLK en ns
  local C=$1 H=$2 W=$TMP/c${1}_h${2}
  mkdir -p "$W"; ln -s "$REPO/sw" "$W/sw"; ln -s "$REPO/tb" "$W/tb"
  sed -E -e "s/^    #1000;$/    #$C;/" -e "s/#500 sclk = /#$H sclk = /" \
    -e 's#(PROGRAMA   = )"[^"]*"#\1"sw/echo.hex"#' \
    -e 's#(SERIE      = )"[^"]*"#\1"tb/practica_meta.csv"#' \
    -e "s#(NTICKS     = )[0-9]+#\1$NTICKS#" tb/tb_proyecto_4.sv > "$W/tb.sv"
  iverilog -g2012 -s tb_proyecto_4 -o "$W/sim" "$CELLS" rtl/*.v rtl/espino_core/*.v "$W/tb.sv"
  (cd "$W" && vvp -n sim > run.log 2>&1)
  local r; r=$(cd "$W" && python3 "$REPO/ref/trader.py" -e echo -n "$NTICKS" --compara decisiones.csv | tail -1)
  printf "SCLK %5s MHz  CS->flanco %4s ns  tb %s/4 PASS  %s\n" \
    "$(python3 -c "print(round(500/$H, 2))")" "$C" "$(grep -c ^PASS "$W/run.log")" "$r"
}
export -f punto; export TMP REPO NTICKS CELLS

{
  echo "# sim/barrido_spi.sh: echo.s, $NTICKS ticks de practica_meta, ronda 3"
  for H in 500 250 166 125 100 83 62; do for C in 1000 200 120 80 40; do echo "$C $H"; done; done \
    | xargs -P "$(nproc)" -n 2 bash -c 'punto "$0" "$1"' | sort -k2,2n -k5,5nr
} | tee "$OUT"
