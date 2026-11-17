@echo off
rem Measures area (Yosys) and Fmax (nextpnr) of the Z80 + MSX mem + SDRAM set. Run in the OSS CAD Suite terminal.
del resumo_z80_msx.txt 2>nul
cd /d %~dp0
copy /y ..\..\11_fpu_stk\pnr\pins.cst pins.cst >nul
set R=..\rtl
yosys -q -l yosys_z80_msx.log -p "read_verilog %R%\z80_core.v %R%\z80_ucode.v %R%\z80_ce.v %R%\z80_top.v %R%\z80_msx_sys.v %R%\sdram_byte_if.v %R%\z80_msx_top.v ..\..\10_msx_mem\rtl\msx_mem.v ..\..\05_sdram\rtl\sdram_ctrl.v pnr_z80_msx_top.v; synth_gowin -top pnr_z80_msx_top -json z80_msx.json; stat"
findstr /C:"LUT" /C:"ALU" /C:"DFF" /C:"RAM" yosys_z80_msx.log
del resumo_z80_msx.txt 2>nul
rem 57.28 = system clock (3.58 MHz x 16): it is the target that matters
for %%F in (100 57.28 40) do (
  nextpnr-himbaechel --json z80_msx.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=pins.cst --freq %%F --router router2 > pnr_z80_msx_%%F.log 2>&1
  findstr /C:"Max frequency" pnr_z80_msx_%%F.log > fmax_msx_%%F.txt
  echo === target freq %%F >> resumo_z80_msx.txt
  type fmax_msx_%%F.txt >> resumo_z80_msx.txt
)
type resumo_z80_msx.txt
echo Finished.
pause
