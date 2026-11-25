#!/usr/bin/env bash
# Compara un respaldo de la placa (iceprog -r) con un bitstream compilado.
#
#   bash scripts/compara_bin.sh respaldos/placa.bin trade_top.bin
#
# 1. Bit a bit: el respaldo trae la flash entera, asi que se comparan solo los
#    primeros N bytes (N = largo del compilado) y se informa si el resto es 0xFF.
# 2. Si no son iguales, compara la BRAM (programa de Espino) de los dos con
#    iceunpack: no depende de la version del toolchain, asi que dice si el
#    programa es el mismo aunque el ruteo haya cambiado.
set -euo pipefail

PLACA=$1
BIN=$2
N=$(stat -c %s "$BIN")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

head -c "$N" "$PLACA" > "$TMP/placa.bin"
tail -c +"$((N + 1))" "$PLACA" | tr -d '\377' | wc -c > "$TMP/resto"
echo "Compilado: $N bytes. Bytes distintos de 0xFF despues de eso en la placa: $(cat "$TMP/resto")"

if cmp -s "$TMP/placa.bin" "$BIN"; then
  echo "IDENTICOS: la placa tiene exactamente $BIN"
  exit 0
fi
echo "DISTINTOS bit a bit ($(cmp -l "$TMP/placa.bin" "$BIN" | wc -l) bytes difieren). Comparando la BRAM..."

iceunpack "$TMP/placa.bin" "$TMP/placa.asc"
iceunpack "$BIN" "$TMP/bin.asc"

# Bloques .ram_data <x> <y> (16 lineas cada uno). Con otra version u otra
# semilla de nextpnr el mismo contenido puede quedar en otra BRAM, asi que se
# compara tambien el conjunto de contenidos sin posicion.
python3 -I - "$TMP/placa.asc" "$TMP/bin.asc" <<'PY'
import sys

def bram(ruta):
    bloques, actual = {}, None
    for linea in open(ruta):
        linea = linea.strip()
        if linea.startswith("."):
            actual = linea[len(".ram_data "):] if linea.startswith(".ram_data") else None
            if actual is not None:
                bloques[actual] = []
        elif actual is not None and linea:
            bloques[actual].append(linea)
    return {k: "".join(v) for k, v in bloques.items()}

placa, comp = bram(sys.argv[1]), bram(sys.argv[2])
usados = lambda b: sorted(v for v in b.values() if v.strip("0"))
print(f"BRAM con datos: placa {len(usados(placa))}, compilado {len(usados(comp))}")
if placa == comp:
    print("BRAM IGUAL (mismas posiciones): mismo programa; lo que cambia es la logica (ruteo, version del toolchain o variante DEFS)")
elif usados(placa) == usados(comp):
    print("BRAM IGUAL (en otras posiciones): mismo programa; lo que cambia es la logica (ruteo, version del toolchain o variante DEFS)")
else:
    print("BRAM DISTINTA: la placa tiene otro programa (u otra variante de hardware)")
    sys.exit(2)
PY
