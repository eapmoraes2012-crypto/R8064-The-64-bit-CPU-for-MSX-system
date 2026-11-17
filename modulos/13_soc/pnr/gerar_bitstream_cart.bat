@echo off
rem Gera o bitstream do cartucho (r8064_cart_top) e, opcionalmente, grava na SRAM da FPGA (some ao desligar).
rem Uso: gerar_bitstream_cart.bat [SEMENTE] [gravar]    (SEMENTE = a que fechou melhor no rodar_pnr_cart.bat; padrao 3)
cd /d "%~dp0"
set SEED=%1
if "%SEED%"=="" set SEED=3
yosys -q -l yosys_cart.log ys_cart.ys
findstr /b /c:"ERROR" yosys_cart.log && (echo SINTESE FALHOU & exit /b 1)
nextpnr-himbaechel --json gcart.json --write cart_pnr.json --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=tangnano20k_cart.cst --freq 57.28 --router router2 --parallel-refine --seed %SEED% --log pnr_cart_bits.log
findstr /c:"Max frequency" pnr_cart_bits.log
gowin_pack -d GW2A-18C -o r8064_cart_s%SEED%.fs cart_pnr.json
if not exist r8064_cart_s%SEED%.fs (echo FALHOU o empacotamento & exit /b 1)
echo Bitstream: r8064_cart_s%SEED%.fs
if /i "%2"=="gravar" openFPGALoader -b tangnano20k r8064_cart_s%SEED%.fs
