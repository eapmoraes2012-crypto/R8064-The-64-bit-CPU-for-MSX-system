@echo off
rem Z80 simulation: RTL x C model (per-instruction trace). Run in the OSS CAD Suite terminal.
cd /d %~dp0
echo === compiling ===
iverilog -g2012 -Wall -o simz80.vvp tb_z80.v ..\rtl\z80_core.v ..\rtl\z80_ucode.v > compila.log 2>&1
type compila.log
if errorlevel 1 goto fim
del resultado_z80.txt 2>nul
for %%N in (r01 r02 r03 r04 r05 r06 r07 r08 r09 r10 r11 r12) do (
  echo --- %%N >> resultado_z80.txt
  vvp simz80.vvp +mem=vec/%%N_mem.hex +regs=vec/%%N_regs.txt +trace=vec/%%N_trace.txt +n=20000 >> resultado_z80.txt 2>&1
)
echo --- zex >> resultado_z80.txt
vvp simz80.vvp +mem=vec/zex_mem.hex +regs=vec/zex_regs.txt +trace=vec/zex_trace.txt +n=150000 >> resultado_z80.txt 2>&1
echo --- wait=1 r01 >> resultado_z80.txt
vvp simz80.vvp +mem=vec/r01_mem.hex +regs=vec/r01_regs.txt +trace=vec/r01_trace.txt +n=20000 +wait=1 >> resultado_z80.txt 2>&1
echo --- wait=1 zex >> resultado_z80.txt
vvp simz80.vvp +mem=vec/zex_mem.hex +regs=vec/zex_regs.txt +trace=vec/zex_trace.txt +n=60000 +wait=1 >> resultado_z80.txt 2>&1
type resultado_z80.txt
:fim
echo.
echo Finished. Result in resultado_z80.txt and compila.log
pause
