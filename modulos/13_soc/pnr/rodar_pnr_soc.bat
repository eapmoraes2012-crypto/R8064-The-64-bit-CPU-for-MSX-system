@echo off
rem Run INSIDE the OSS CAD Suite terminal. PnR of the full SoC (core + governor + MMU + caches + arbiter + SDRAM) at 57.28 MHz.
rem Each seed takes several minutes (more than the isolated core). Adjust the seed list if you want.
cd /d "%~dp0"
echo [1/2] Yosys...
yosys -q -l yosys_soc.log ys_soc_top.ys
findstr /b /c:"ERROR" yosys_soc.log && (echo SYNTHESIS FAILED - see yosys_soc.log & exit /b 1)
echo [2/2] nextpnr
for %%S in (1 2 3 4) do (
  echo [nextpnr seed %%S]
  nextpnr-himbaechel --json gsoc.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=pins.cst --freq 57.28 --router router2 --parallel-refine --seed %%S --report rep_soc_%%S.json > pnr_soc_s%%S.log 2>&1
  findstr /c:"Max frequency" pnr_soc_s%%S.log
)
echo Done: the LAST "Max frequency" of each pnr_soc_s*.log is the post-routing value. Send the pnr_soc_s*.log and yosys_soc.log.
