@echo off
rem Rode DENTRO do terminal do OSS CAD Suite. PnR do SoC completo (nucleo + governador + MMU + caches + arbitro + SDRAM) a 57,28 MHz.
rem Cada semente leva varios minutos (mais que o nucleo isolado). Ajuste a lista de sementes se quiser.
cd /d "%~dp0"
echo [1/2] Yosys...
yosys -q -l yosys_soc.log ys_soc_top.ys
findstr /b /c:"ERROR" yosys_soc.log && (echo SINTESE FALHOU - veja yosys_soc.log & exit /b 1)
echo [2/2] nextpnr
for %%S in (1 2 3 4) do (
  echo [nextpnr semente %%S]
  nextpnr-himbaechel --json gsoc.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=pins.cst --freq 57.28 --router router2 --parallel-refine --seed %%S --report rep_soc_%%S.json > pnr_soc_s%%S.log 2>&1
  findstr /c:"Max frequency" pnr_soc_s%%S.log
)
echo Pronto: o ULTIMO "Max frequency" de cada pnr_soc_s*.log e o valor pos-roteamento. Mande os pnr_soc_s*.log e yosys_soc.log.
