@echo off
rem Uso: rodar_pnr_soc_pll.bat [SRC]   SRC=0: 27 MHz da placa -> PLL 57,375 MHz | SRC=1: 3,579545 MHz externo -> PLL x16 = 57,2727 MHz (padrao) | SRC=2: 57,27 MHz direto
rem Rode DENTRO do terminal do OSS CAD Suite. SoC completo com o gerador de clock r8064_clkgen (rPLL) a 57,28 MHz.
cd /d "%~dp0"
set SRC=%1
if "%SRC%"=="" set SRC=1
echo [1/2] Yosys (SRC=%SRC%)...
powershell -NoProfile -Command "(Get-Content ys_soc_pll.ys) -replace 'chparam -set SRC \d','chparam -set SRC %SRC%' | Set-Content ys_soc_pll_run.ys"
yosys -q -l yosys_soc_pll.log ys_soc_pll_run.ys
findstr /b /c:"ERROR" yosys_soc_pll.log && (echo SINTESE FALHOU - veja yosys_soc_pll.log & exit /b 1)
echo [2/2] nextpnr
for %%S in (1 2 3 4) do (
  echo [nextpnr semente %%S]
  nextpnr-himbaechel --json gsoc_pll.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=pins_pll_src%SRC%.cst --freq 57.28 --router router2 --parallel-refine --seed %%S --report rep_pll_%%S.json > pnr_pll_s%%S.log 2>&1
  findstr /c:"Max frequency" pnr_pll_s%%S.log
)
echo Pronto. Mande os pnr_pll_s*.log e yosys_soc_pll.log.
