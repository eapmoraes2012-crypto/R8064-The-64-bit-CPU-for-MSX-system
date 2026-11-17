@echo off
rem Generates the cartridge bitstream (r8064_cart_top) and, optionally, programs the FPGA SRAM (lost at power-off).
rem Usage: gerar_bitstream_cart.bat [SEED] [gravar]    (SEED = the one that closed best in rodar_pnr_cart.bat; default 3)
cd /d "%~dp0"
set SEED=%1
if "%SEED%"=="" set SEED=3
yosys -q -l yosys_cart.log ys_cart.ys
findstr /b /c:"ERROR" yosys_cart.log && (echo SYNTHESIS FAILED & exit /b 1)
nextpnr-himbaechel --json gcart.json --write cart_pnr.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=tangnano20k_cart.cst --freq 57.28 --router router2 --parallel-refine --seed %SEED% --log pnr_cart_bits.log
findstr /c:"Max frequency" pnr_cart_bits.log
gowin_pack -d GW2A-18C -o r8064_cart_s%SEED%.fs cart_pnr.json
if not exist r8064_cart_s%SEED%.fs (echo PACKING FAILED & exit /b 1)
echo Bitstream: r8064_cart_s%SEED%.fs
if /i "%2"=="gravar" openFPGALoader -b tangnano20k r8064_cart_s%SEED%.fs
