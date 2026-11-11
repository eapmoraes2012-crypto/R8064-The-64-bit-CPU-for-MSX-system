@echo off
rem Uso: rodar_pnr_board.bat [SRC]  SRC=0: 27 MHz da placa -> 57,375 MHz (padrao) | 1: 3,579545 MHz em clk_ext (pino 13) x16 | 2: 57,27 MHz direto (pino 10) | 3: 14,31818 MHz (pino 80) x4
rem Rode DENTRO do terminal do OSS CAD Suite. Topo de placa completo (clkgen + SoC + SDRAM embutida) a 57,28 MHz.
cd /d "%~dp0"
set SRC=%1
if "%SRC%"=="" set SRC=0
echo [1/2] Yosys (SRC=%SRC%)...
powershell -NoProfile -Command "(Get-Content ys_board.ys) -replace 'chparam -set SRC \d','chparam -set SRC %SRC%' | Set-Content ys_board_run.ys"
yosys -q -l yosys_board.log ys_board_run.ys
findstr /b /c:"ERROR" yosys_board.log && (echo SINTESE FALHOU - veja yosys_board.log & exit /b 1)
echo [2/2] nextpnr
for %%S in (1 2 3 4) do (
  echo [nextpnr semente %%S]
  nextpnr-himbaechel --json gboard.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=tangnano20k_src%SRC%.cst --freq 57.28 --router router2 --parallel-refine --seed %%S --report rep_board_%%S.json > pnr_board_s%%S.log 2>&1
  findstr /c:"Max frequency" pnr_board_s%%S.log
)
echo Pronto. Mande os pnr_board_s*.log e yosys_board.log.
