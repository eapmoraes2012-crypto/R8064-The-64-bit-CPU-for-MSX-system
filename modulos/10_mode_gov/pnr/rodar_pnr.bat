@echo off
rem Rode DENTRO do terminal do OSS CAD Suite. PnR do nucleo + governador + modo (pnr_gov_top). Demora varios minutos por semente.
cd /d "%~dp0"
echo [1/3] Yosys...
yosys -q -l yosys.log y.ys
findstr /c:"ERROR" yosys.log && (echo SINTESE FALHOU - veja yosys.log & exit /b 1)
for %%S in (1 2 3 4 5 6) do (
  echo [nextpnr semente %%S]
  nextpnr-himbaechel --json g.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=pins.cst --freq 57.28 --router router2 --parallel-refine --seed %%S --report rep_%%S.json > pnr_s%%S.log 2>&1
  findstr /c:"Max frequency" pnr_s%%S.log
)
echo Pronto: o ULTIMO "Max frequency" de cada pnr_s*.log e o valor pos-roteamento. Mande os pnr_s*.log, yosys.log e rep_*.json.
