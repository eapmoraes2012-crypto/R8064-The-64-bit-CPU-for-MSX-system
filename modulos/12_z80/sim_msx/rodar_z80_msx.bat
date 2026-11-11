@echo off
rem Integracao Z80 + memoria MSX (mapper/MegaRAM) + SDRAM: 4 modos de turbo. Rode no terminal do OSS CAD Suite.
cd /d %~dp0
set R=..\rtl
set M=..\..\10_msx_mem\rtl\msx_mem.v
set S=..\..\05_sdram\rtl
echo === compilando ===
iverilog -g2012 -Wall -o simmsx.vvp tb_z80_msx.v %R%\z80_msx_top.v %R%\z80_msx_sys.v %R%\sdram_byte_if.v %R%\z80_top.v %R%\z80_ce.v %R%\z80_core.v %R%\z80_ucode.v %M% %S%\sdram_ctrl.v %S%\sdram_model.v > compila_msx.log 2>&1
type compila_msx.log
if errorlevel 1 goto fim
del resultado_msx.txt 2>nul
for %%T in (0 1 2 3) do (
  echo --- turbo %%T >> resultado_msx.txt
  vvp simmsx.vvp +hex=t_msx.hex +turbo=%%T >> resultado_msx.txt 2>&1
)
type resultado_msx.txt
:fim
echo.
echo Terminou. Resultado em resultado_msx.txt e compila_msx.log
pause
