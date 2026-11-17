@echo off
rem Usage: rodar_pnr_board.bat [SRC]  SRC=0: 27 MHz board clock -> 57.375 MHz (default) | 1: 3.579545 MHz on clk_ext (pin 13) x16 | 2: 57.27 MHz direct (pin 10) | 3: 14.31818 MHz (pin 80) x4
rem Run INSIDE the OSS CAD Suite terminal. Full board top (clkgen + SoC + embedded SDRAM) at 57.28 MHz.
cd /d "%~dp0"
set SRC=%1
if "%SRC%"=="" set SRC=0
echo [1/2] Yosys (SRC=%SRC%)...
powershell -NoProfile -Command "(Get-Content ys_board.ys) -replace 'chparam -set SRC \d','chparam -set SRC %SRC%' | Set-Content ys_board_run.ys"
yosys -q -l yosys_board.log ys_board_run.ys
findstr /b /c:"ERROR" yosys_board.log && (echo SYNTHESIS FAILED - see yosys_board.log & exit /b 1)
echo [2/2] nextpnr
for %%S in (1 2 3 4) do (
  echo [nextpnr seed %%S]
  nextpnr-himbaechel --json gboard.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=tangnano20k_src%SRC%.cst --freq 57.28 --router router2 --parallel-refine --seed %%S --report rep_board_%%S.json > pnr_board_s%%S.log 2>&1
  findstr /c:"Max frequency" pnr_board_s%%S.log
)
echo Done. Send the pnr_board_s*.log and yosys_board.log.
