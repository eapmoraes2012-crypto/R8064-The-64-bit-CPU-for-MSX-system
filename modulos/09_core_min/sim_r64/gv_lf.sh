#!/bin/bash
# Generates random programs of the R8064 16/32/64-bit instructions and compares the core with the model (Linux/WSL: python3, iverilog).
# usage: ./gerar_vetores.sh <N> <seed> [seed...]
set -e
cd "$(dirname "$0")"; S=../sim; R=../rtl; W=${TMPDIR:-/tmp}/r64core; mkdir -p $W; N=$1; shift
cp $S/uop.mem $S/mainctrl.mem $S/rom_ed_a.mem $S/rom_ed_b.mem $S/amb_idx.mem $S/ctrl.mem $S/ctrl_b.mem $W
iverilog -g2012 -o $W/r.vvp tb_r64core.v $R/r8064_core_min.v $R/r8064_decode.v $R/r8064_decode_rom.v $R/regfile64.v $R/regmap_b.v $R/regmerge.v $R/alu_prep.v $R/alu_core_s.v
for s in "$@"; do
  python3 gen_r64_prog.py $s $W/p$s $N
  (cd $W && vvp -n r.vvp +hex=p${s}_mem.hex +trace=p${s}_trace.txt +fim=p${s}_fim.hex | grep -E "DIVERG|core:|model:|MEMORY|instructions|RESULT")
done
