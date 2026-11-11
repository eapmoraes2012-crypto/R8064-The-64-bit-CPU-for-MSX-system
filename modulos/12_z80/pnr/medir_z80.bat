@echo off
cd /d %~dp0
del resumo_z80.txt 2>nul
copy /y ..\..\11_fpu_stk\pnr\pins.cst pins.cst >nul
yosys -q -l yosys_z80.log -p "read_verilog ..\rtl\z80_core.v ..\rtl\z80_ucode.v ..\rtl\z80_ce.v ..\rtl\z80_top.v pnr_z80_top.v; synth_gowin -top pnr_z80_top -json z80.json; stat"
findstr /C:"LUT" /C:"ALU" /C:"DFF" /C:"RAM" yosys_z80.log
for %%F in (100 60 40) do (
  nextpnr-himbaechel --json z80.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=pins.cst --freq %%F --router router2 > pnr_z80_%%F.log 2>&1
  findstr /C:"Max frequency" pnr_z80_%%F.log > fmax_%%F.txt
  echo === freq alvo %%F >> resumo_z80.txt
  type fmax_%%F.txt >> resumo_z80.txt
)
type resumo_z80.txt
echo Terminou.
pause
