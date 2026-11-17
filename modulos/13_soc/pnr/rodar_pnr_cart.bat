@echo off
rem Run INSIDE the OSS CAD Suite terminal. CARTRIDGE top (r8064_cart_top) for the V9968_Cartridge board (Tang Nano 20K), 14.31818 MHz board clock x4 = 57.2727 MHz.
rem Synthesis + nextpnr with 4 seeds; shows the Fmax of each one. Send the pnr_cart_s*.log and yosys_cart.log.
cd /d "%~dp0"
echo [1/2] Yosys...
yosys -q -l yosys_cart.log ys_cart.ys
findstr /b /c:"ERROR" yosys_cart.log && (echo SYNTHESIS FAILED - see yosys_cart.log & exit /b 1)
echo [2/2] nextpnr
for %%S in (1 2 3 4) do (
  echo [nextpnr seed %%S]
  nextpnr-himbaechel --json gcart.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=tangnano20k_cart.cst --freq 57.28 --router router2 --parallel-refine --seed %%S --report rep_cart_%%S.json --log pnr_cart_s%%S.log
  findstr /c:"Max frequency" pnr_cart_s%%S.log
)
echo Done.
