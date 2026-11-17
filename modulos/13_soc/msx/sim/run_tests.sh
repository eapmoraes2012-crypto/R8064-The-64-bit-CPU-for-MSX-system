#!/bin/sh
# run_tests.sh - builds R8064.COM and the simulator, then runs R8064.COM against the cartridge model.
# Needs: sjasmplus (or SJASM=/path/to/sjasmplus), gcc, python3.   Use: sh run_tests.sh
set -e
H=$(cd "$(dirname "$0")" && pwd); SJ=${SJASM:-sjasmplus}; W=${TMPDIR:-/tmp}/r8064_msx_test; rm -rf "$W"; mkdir -p "$W"
cd "$H/.." && $SJ --raw="$W/R8064.COM" r8064.asm >/dev/null
cd "$H" && $SJ --raw="$W/TPROG.BIN" tprog.asm >/dev/null
python3 mk_core.py ../../../12_z80/ref/z80ref.c "$W/z80core.c" && cp msxsim.c "$W/" && gcc -O2 -w -o "$W/msxsim" "$W/msxsim.c"
cd "$W"; python3 -c "import random; random.seed(7); open('DATA.BIN','wb').write(bytes(random.randrange(256) for _ in range(5000)))"
M="./msxsim -sd sd.img"; F=0
ok() { if grep -q "$2" out.txt; then echo "PASS  $1"; else echo "FAIL  $1"; cat out.txt; F=1; fi; }
$M R8064.COM I > out.txt 2>&1;                       ok "HELLO"                 "Features: window EXEC CRC"
$M R8064.COM P > out.txt 2>&1;                       ok "PING"                  "PING ok"
$M -nocard R8064.COM I > out.txt 2>&1;               ok "no card"               "No R8064 cartridge"
$M R8064.COM S 5000 DATA.BIN > out.txt 2>&1;         ok "send 5000 bytes + CRC" "CRC ok: 5C4D"
$M R8064.COM G 5000 1388 BACK.BIN > out.txt 2>&1;    cmp -s DATA.BIN BACK.BIN && echo "File identical" >> out.txt; ok "get 5000 bytes" "File identical"
$M R8064.COM S 600003 DATA.BIN > out.txt 2>&1;       ok "send unaligned"        "CRC check skipped"
$M R8064.COM G 600003 1388 BACK2.BIN > out.txt 2>&1; cmp -s DATA.BIN BACK2.BIN && echo "File identical" >> out.txt; ok "get unaligned" "File identical"
$M R8064.COM D 5000 13 > out.txt 2>&1;               ok "dump"                  "005010 D9 1E 3F"
$M R8064.COM R 4000 TPROG.BIN 1 1000 > out.txt 2>&1; ok "send + exec"           "exit code 0000D4BCh"
$M R8064.COM D 4100 2 > out.txt 2>&1;                ok "program result"        "004100 BC D4"
$M R8064.COM X 4000 3 10 > out.txt 2>&1;             ok "exec R800 DRAM mode"   "exit code 0000062Dh"
$M -lose 2 R8064.COM S 5000 DATA.BIN > out.txt 2>&1; ok "lost message, retry"   "CRC ok: 5C4D"
$M -evt 2 R8064.COM D 5000 4 > out.txt 2>&1;         ok "unsolicited EVT"       "005000 A5 4D CA 18"
$M R8064.COM B > out.txt 2>&1;                       ok "restart"               "monitor answering"
$M -dead R8064.COM P > out.txt 2>&1;                 ok "timeout after retries" "does not answer"
$M R8064.COM X 10000 > out.txt 2>&1;                 ok "entry check"           "below 10000h"
$M R8064.COM S 800000 DATA.BIN > out.txt 2>&1;       ok "address check"         "outside the 8 MB"
[ $F = 0 ] && echo "ALL TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
