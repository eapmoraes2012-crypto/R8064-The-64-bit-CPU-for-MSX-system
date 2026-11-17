@echo off
rem Run INSIDE the OSS CAD Suite terminal. R8064 16/32/64-bit instructions (see ..\PREMISSAS_R8064.txt):
rem  1) smoke test (21 instructions, hand-computed values) ; 2) two random programs from vec\ against the Python model, instruction by instruction (includes system: ..\MODELO_PRIVILEGIO.txt).
rem To generate other programs: gerar_vetores.sh (Linux/WSL) or  python gen_r64_prog.py <seed> <prefix> [N]
cd /d "%~dp0"
set S=..\sim
set R=..\rtl
set SRC=%R%\r8064_core_min.v %R%\r8064_decode.v %R%\r8064_decode_rom.v %R%\regfile64.v %R%\regmap_b.v %R%\regmerge.v %R%\alu_prep.v %R%\alu_core_s.v ..\..\03_muldiv\rtl\mul_unit.v ..\..\03_muldiv\rtl\div_unit.v ..\..\08_fpu\rtl\fpu_unit.v ..\..\08_fpu\rtl\fpu_seq.v
for %%F in (uop.mem mainctrl.mem rom_ed_a.mem rom_ed_b.mem amb_idx.mem ctrl.mem ctrl_b.mem) do copy /y %S%\%%F . >nul
iverilog -g2012 -o r64.vvp tb_r64_fumaca.v %SRC%
if errorlevel 1 (echo COMPILATION FAILED & exit /b 1)
vvp -n r64.vvp
iverilog -g2012 -o r64core.vvp tb_r64core.v %SRC%
if errorlevel 1 (echo COMPILATION FAILED & exit /b 1)
for %%V in (q1 q2) do vvp -n r64core.vvp +hex=vec/%%V_mem.hex +trace=vec/%%V_trace.txt +fim=vec/%%V_fim.hex +fpu=vec/%%V_fpu.hex
rem the same programs with the core free-running (instructions glued into the pipeline): compares the final state
for %%V in (q1 q2) do vvp -n r64core.vvp +hex=vec/%%V_mem.hex +trace=vec/%%V_trace.txt +fim=vec/%%V_fim.hex +fpu=vec/%%V_fpu.hex +livre
