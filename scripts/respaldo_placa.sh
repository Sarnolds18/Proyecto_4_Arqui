#!/usr/bin/env bash
# Respalda la flash de la Go Board con iceprog -r antes de flashear otra cosa.
# Lee dos veces y compara (una lectura mala por usbipd no pasa como respaldo).
#
#   bash scripts/respaldo_placa.sh [salida.bin]     por defecto respaldos/placa_<fecha>.bin
set -euo pipefail

SALIDA=${1:-respaldos/placa_$(date +%Y%m%d_%H%M%S).bin}
mkdir -p "$(dirname "$SALIDA")"

if [ -e "$SALIDA" ]; then
  echo "ERROR: $SALIDA ya existe, no se sobrescribe" >&2; exit 1
fi

iceprog -r "$SALIDA"
iceprog -r "$SALIDA.2"
if ! cmp -s "$SALIDA" "$SALIDA.2"; then
  echo "ERROR: las dos lecturas no coinciden (revisar cable/usbipd). Quedan $SALIDA y $SALIDA.2" >&2
  exit 1
fi
rm "$SALIDA.2"

sha256sum "$SALIDA" | tee "$SALIDA.sha256"
echo "Respaldo OK: $SALIDA ($(stat -c %s "$SALIDA") bytes). Copiarlo tambien fuera del repo."
