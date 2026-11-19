#!/bin/sh
# run_tests.sh - checks the instruction table against the RTL and sjasmplus, rebuilds R8064AS.COM and
# cross-tests it (Z80 code run in the MSX-DOS model) against the host reference assembler asmref.py.
# Needs: python3, gcc, sjasmplus (or SJASM=/path/to/sjasmplus).   Use: sh run_tests.sh
set -e
H=$(cd "$(dirname "$0")" && pwd); SJ=${SJASM:-sjasmplus}; W=${TMPDIR:-/tmp}/r8064as_test; rm -rf "$W"; mkdir -p "$W"
cd "$H"
python3 verify_rom.py
python3 verify_z80.py "$SJ" | tail -1
python3 gen_table.py
$SJ --nologo --raw=R8064AS.COM r8064as.asm | tail -1
python3 ../sim/mk_core.py ../../../12_z80/ref/z80ref.c "$W/z80core.c" && cp ../sim/msxsim.c "$W/" && gcc -O2 -w -o "$W/msxsim" "$W/msxsim.c"
python3 crosstest.py "$W/msxsim" R8064AS.COM "$W/ct"
mkdir -p "$W/go" && cp R8064AS.COM tests_go/HELLO.ASM "$W/go/" && cd "$W/go" && ./../msxsim R8064AS.COM HELLO /G | grep -q "exit code 000013BAh" && echo "PASS  /G: HELLO.ASM sent and run, exit code 13BAh"
