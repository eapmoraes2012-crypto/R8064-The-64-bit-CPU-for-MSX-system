#!/usr/bin/env bash
# Reproduz a simulacao e a sintese do decodificador ED. Requer o OSS CAD Suite no PATH (source oss-cad-suite/environment).
# Uso: na pasta R8064_rtl_pack:  bash scripts/simular_e_sintetizar.sh
set -e
W=$(mktemp -d); cp rom/*.mem ref/*.mem rtl/*.v pnr/pnr_top.v pnr/pnr_top.cst "$W"; cd "$W"
echo "== Icarus (RTL)";      iverilog -g2012 -o sim tb_r8064_decode.v r8064_decode.v && vvp sim | grep -E "Vetores|PASS|FAIL"
echo "== Verilator (RTL)";   verilator --binary --timing -Wno-fatal --top-module tb_r8064_decode tb_r8064_decode.v r8064_decode.v >/dev/null 2>&1 && ./obj_dir/Vtb_r8064_decode | grep -E "Vetores|PASS|FAIL"
echo "== Netlist sem BSRAM (portas logicas)"
SIMLIB=$(find "$(dirname "$(which yosys)")/../share/yosys/gowin" -name cells_sim.v | head -1)
yosys -q -p "read_verilog -sv r8064_decode.v; synth_gowin -top r8064_decode -nobram; write_verilog -noattr net.v"
iverilog -g2012 -o simnet tb_r8064_decode.v net.v "$SIMLIB" && vvp simnet | grep -E "Vetores|PASS|FAIL"
echo "== Sintese com BSRAM";  yosys -q -p "read_verilog -sv r8064_decode.v; synth_gowin -top r8064_decode; tee -o stat.txt stat" && grep -E "SPX9|LUT[1-4]|DFF" stat.txt
echo "== Place-and-route (GW2AR-LV18QN88C8/I7, 57,28 MHz = alvo atual; pinos so do invólucro de teste)"
yosys -q -p "read_verilog -sv r8064_decode.v pnr_top.v; synth_gowin -top pnr_top -json pt.json"
nextpnr-himbaechel --json pt.json --write pt_pnr.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=pnr_top.cst --freq 57.28 --timing-allow-fail 2>&1 | grep -E "Max frequency|BSRAM:|LUT4:"
