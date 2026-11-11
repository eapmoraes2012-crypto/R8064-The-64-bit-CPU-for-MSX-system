#!/bin/bash
# uso: ys_unit.sh arquivo.v -> LUT (1+2+3+4) + ALU = area em LUT4-eq, FF, DSP da unidade isolada (as 'LUT4' do relatorio do nextpnr contam LUT1..LUT4)
export PATH=$HOME/oss/oss-cad-suite/bin:$PATH
f=$1; t=${2:-/tmp/yu}
yosys -q -p "read_verilog -sv $f; synth_gowin -top vec3d_unit -json $t.json; tee -o $t.stat stat" >/dev/null 2>&1
awk '/ ALU$/{alu=$1} / DFF/{ff+=$1} / LUT[1-4]$/{lut+=$1} /MULT18X18/{m=$1} /MUX2_LUT/{mx+=$1} END{printf "LUT=%d ALU=%d  TOTAL=%d  FF=%d DSP=%d (MUX2_LUT=%d)\n", lut, alu, lut+alu, ff, m, mx}' $t.stat
