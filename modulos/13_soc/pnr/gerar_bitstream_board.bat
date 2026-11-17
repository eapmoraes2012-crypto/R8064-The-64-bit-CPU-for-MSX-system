@echo off
rem Generates the board-top bitstream (Tang Nano 20K) and, optionally, programs the board.
rem Usage: gerar_bitstream_board.bat [SRC] [SEED] [gravar]
rem   SRC: 0 = 27 MHz board clock (padrao) | 1 = 3.579545 MHz on clk_ext (pino 13) | 2 = 57.27 MHz (pino 10) | 3 = 14.31818 MHz (pino 80)
rem   SEED: use the one that closed best in PnR (default 3). "gravar" = loads into the FPGA SRAM with openFPGALoader (lost at power-off).
rem Run INSIDE the OSS CAD Suite terminal.
cd /d "%~dp0"
set SRC=%1
if "%SRC%"=="" set SRC=0
set SEED=%2
if "%SEED%"=="" set SEED=3
echo [1/3] Yosys (SRC=%SRC%)...
powershell -NoProfile -Command "(Get-Content ys_board.ys) -replace 'chparam -set SRC \d','chparam -set SRC %SRC%' | Set-Content ys_board_run.ys"
yosys -q -l yosys_board.log ys_board_run.ys
findstr /b /c:"ERROR" yosys_board.log && (echo SYNTHESIS FAILED & exit /b 1)
echo [2/3] nextpnr seed %SEED%
nextpnr-himbaechel --json gboard.json --write board_pnr.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=tangnano20k_src%SRC%.cst --freq 57.28 --router router2 --parallel-refine --seed %SEED% > pnr_board_bits.log 2>&1
findstr /c:"Max frequency" pnr_board_bits.log
echo [3/3] gowin_pack
gowin_pack -d GW2A-18C -o r8064_board_src%SRC%_s%SEED%.fs board_pnr.json
if not exist r8064_board_src%SRC%_s%SEED%.fs (echo PACKING FAILED & exit /b 1)
echo Bitstream: r8064_board_src%SRC%_s%SEED%.fs
if /i "%3"=="gravar" openFPGALoader -b tangnano20k r8064_board_src%SRC%_s%SEED%.fs
