@echo off
rem Rode DENTRO do terminal do OSS CAD Suite. Topo de CARTUCHO (r8064_cart_top) para a placa V9968_Cartridge (Tang Nano 20K), clock de 14,31818 MHz da placa x4 = 57,2727 MHz.
rem Sintese + nextpnr com 4 sementes; mostra o Fmax de cada uma. Mande os pnr_cart_s*.log e yosys_cart.log.
cd /d "%~dp0"
echo [1/2] Yosys...
yosys -q -l yosys_cart.log ys_cart.ys
findstr /b /c:"ERROR" yosys_cart.log && (echo SINTESE FALHOU - veja yosys_cart.log & exit /b 1)
echo [2/2] nextpnr
for %%S in (1 2 3 4) do (
  echo [nextpnr semente %%S]
  nextpnr-himbaechel --json gcart.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=tangnano20k_cart.cst --freq 57.28 --router router2 --parallel-refine --seed %%S --report rep_cart_%%S.json --log pnr_cart_s%%S.log
  findstr /c:"Max frequency" pnr_cart_s%%S.log
)
echo Pronto.
