@echo off
rem Gera o bitstream do topo de placa (Tang Nano 20K) e, opcionalmente, grava na placa.
rem Uso: gerar_bitstream_board.bat [SRC] [SEMENTE] [gravar]
rem   SRC: 0 = 27 MHz da placa (padrao) | 1 = 3,579545 MHz em clk_ext (pino 13) | 2 = 57,27 MHz (pino 10) | 3 = 14,31818 MHz (pino 80)
rem   SEMENTE: use a que fechou melhor no PnR (padrao 3). "gravar" = carrega na SRAM da FPGA com openFPGALoader (some ao desligar).
rem Rode DENTRO do terminal do OSS CAD Suite.
cd /d "%~dp0"
set SRC=%1
if "%SRC%"=="" set SRC=0
set SEED=%2
if "%SEED%"=="" set SEED=3
echo [1/3] Yosys (SRC=%SRC%)...
powershell -NoProfile -Command "(Get-Content ys_board.ys) -replace 'chparam -set SRC \d','chparam -set SRC %SRC%' | Set-Content ys_board_run.ys"
yosys -q -l yosys_board.log ys_board_run.ys
findstr /b /c:"ERROR" yosys_board.log && (echo SINTESE FALHOU & exit /b 1)
echo [2/3] nextpnr semente %SEED%
nextpnr-himbaechel --json gboard.json --write board_pnr.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=tangnano20k_src%SRC%.cst --freq 57.28 --router router2 --parallel-refine --seed %SEED% > pnr_board_bits.log 2>&1
findstr /c:"Max frequency" pnr_board_bits.log
echo [3/3] gowin_pack
gowin_pack -d GW2A-18C -o r8064_board_src%SRC%_s%SEED%.fs board_pnr.json
if not exist r8064_board_src%SRC%_s%SEED%.fs (echo FALHOU o empacotamento & exit /b 1)
echo Bitstream: r8064_board_src%SRC%_s%SEED%.fs
if /i "%3"=="gravar" openFPGALoader -b tangnano20k r8064_board_src%SRC%_s%SEED%.fs
