@echo off
rem Run INSIDE the OSS CAD Suite terminal. PnR of core + governor + mode (pnr_gov_top). Takes several minutes per seed.
cd /d "%~dp0"
echo [1/3] Yosys...
yosys -q -l yosys.log y.ys
findstr /c:"ERROR" yosys.log && (echo SYNTHESIS FAILED - see yosys.log & exit /b 1)
for %%S in (1 2 3 4 5 6) do (
  echo [nextpnr seed %%S]
  nextpnr-himbaechel --json g.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=pins.cst --freq 57.28 --router router2 --parallel-refine --seed %%S --report rep_%%S.json > pnr_s%%S.log 2>&1
  findstr /c:"Max frequency" pnr_s%%S.log
)
echo Done: the LAST "Max frequency" of each pnr_s*.log is the post-routing value. Send the pnr_s*.log, yosys.log and rep_*.json files.
