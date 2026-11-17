#!/bin/bash
# Generates random programs and runs the core test in Z80 mode (Linux/WSL: gcc, python3, iverilog).
# usage: ./gerar_vetores.sh <pages> <N> <seed> [seed...]     pages: 1 CB + 2 DD/FD + 4 ED (7 = all) ; N = instructions per program
set -e
cd "$(dirname "$0")"; S=../sim; R=../rtl; W=${TMPDIR:-/tmp}/z80core; mkdir -p $W
PG=$1; N=$2; shift 2
gcc -O2 -w -o $W/z80trace z80trace.c
(cd $S && python3 gen_roms.py)
cp $S/uop.mem $S/mainctrl.mem $S/rom_ed_a.mem $S/rom_ed_b.mem $S/amb_idx.mem $S/ctrl.mem $S/ctrl_b.mem $W
iverilog -g2012 -o $W/z.vvp tb_z80core.v $R/r8064_core_min.v $R/r8064_decode.v $R/r8064_decode_rom.v $R/regfile64.v $R/regmap_b.v $R/regmerge.v $R/alu_prep.v $R/alu_core_s.v
for s in "$@"; do
  python3 gen_z80_prog.py $s $W/p$s.bin $PG
  $W/z80trace $W/p$s.bin $N $PG > $W/t$s.txt
  (cd $W && vvp -n z.vvp +hex=p$s.bin.hex +trace=t$s.txt +fim=p$s.bin.fim | grep -E "DIVERG|core:|model:|MEMORY|instructions|RESULT")
done
