@echo off
rem Rode DENTRO do terminal do OSS CAD Suite. Mede o cache de instrucoes de 4 KB (cache_dm WR=0 IDX=7).
cd /d "%~dp0"
yosys -p "read_verilog -sv pnr_icache_top.v ..\rtl\cache_dm.v; synth_gowin -top pnr_icache_top -json ic.json" > yosys_ic.log 2>&1
findstr /r /c:"LUT[1-4]$" /c:" ALU$" /c:"DFF" /c:"RAM16SDP4" /c:"DPX9B" /c:"SDPX9B" /c:"SPX9" yosys_ic.log > resumo_ic.txt
nextpnr-himbaechel --json ic.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=pins.cst --freq 57.28 --router router2 --report rep_ic.json > pnr_ic.log 2>&1
findstr /c:"Max frequency" pnr_ic.log >> resumo_ic.txt
echo Pronto: resumo_ic.txt
