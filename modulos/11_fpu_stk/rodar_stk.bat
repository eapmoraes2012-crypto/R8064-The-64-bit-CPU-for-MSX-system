@echo off
rem Rode DENTRO do terminal do OSS CAD Suite.
cd /d "%~dp0\sim"
iverilog -g2012 -o stk.vvp tb_fpu_stk.v ..\rtl\fpu_stk.v > ..\resultado_stk.txt 2>&1
vvp stk.vvp >> ..\resultado_stk.txt 2>&1
cd ..\pnr
yosys -p "read_verilog -sv pnr_stk_top.v ..\rtl\fpu_stk.v; synth_gowin -top pnr_stk_top -json s.json" > yosys_stk.log 2>&1
nextpnr-himbaechel --json s.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=pins.cst --freq 57.28 --router router2 --report rep_stk.json > pnr_stk.log 2>&1
findstr /c:"Max frequency" pnr_stk.log >> ..\resultado_stk.txt
echo Pronto: resultado_stk.txt yosys_stk.log
