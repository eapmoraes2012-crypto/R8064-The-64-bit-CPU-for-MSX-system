@echo off
rem Usage: rodar_pnr_soc_pll.bat [SRC]   SRC=0: 27 MHz board clock -> PLL 57.375 MHz | SRC=1: external 3.579545 MHz -> PLL x16 = 57.2727 MHz (default) | SRC=2: 57.27 MHz direct
rem Run INSIDE the OSS CAD Suite terminal. Full SoC with the r8064_clkgen clock generator (rPLL) at 57.28 MHz.
cd /d "%~dp0"
set SRC=%1
if "%SRC%"=="" set SRC=1
echo [1/2] Yosys (SRC=%SRC%)...
powershell -NoProfile -Command "(Get-Content ys_soc_pll.ys) -replace 'chparam -set SRC \d','chparam -set SRC %SRC%' | Set-Content ys_soc_pll_run.ys"
yosys -q -l yosys_soc_pll.log ys_soc_pll_run.ys
findstr /b /c:"ERROR" yosys_soc_pll.log && (echo SYNTHESIS FAILED - see yosys_soc_pll.log & exit /b 1)
echo [2/2] nextpnr
for %%S in (1 2 3 4) do (
  echo [nextpnr seed %%S]
  nextpnr-himbaechel --json gsoc_pll.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=pins_pll_src%SRC%.cst --freq 57.28 --router router2 --parallel-refine --seed %%S --report rep_pll_%%S.json > pnr_pll_s%%S.log 2>&1
  findstr /c:"Max frequency" pnr_pll_s%%S.log
)
echo Done. Send the pnr_pll_s*.log and yosys_soc_pll.log.
