@echo off
rem Rode DENTRO do terminal do OSS CAD Suite. Instrucoes R8064 de 16/32/64 bits (ver ..\PREMISSAS_R8064.txt):
rem  1) teste de fumaca (21 instrucoes, valores calculados a mao) ; 2) dois programas aleatorios de vec\ contra o modelo em Python, instrucao a instrucao.
rem Para gerar outros programas: gerar_vetores.sh (Linux/WSL) ou  python gen_r64_prog.py <semente> <prefixo> [N]
cd /d "%~dp0"
set S=..\sim
set R=..\rtl
set SRC=%R%\r8064_core_min.v %R%\r8064_decode.v %R%\r8064_decode_rom.v %R%\regfile64.v %R%\regmap_b.v %R%\regmerge.v %R%\alu_prep.v %R%\alu_core_s.v
for %%F in (uop.mem mainctrl.mem rom_ed_a.mem rom_ed_b.mem amb_idx.mem ctrl.mem ctrl_b.mem) do copy /y %S%\%%F . >nul
iverilog -g2012 -o r64.vvp tb_r64_fumaca.v %SRC%
if errorlevel 1 (echo COMPILACAO FALHOU & exit /b 1)
vvp -n r64.vvp
iverilog -g2012 -o r64core.vvp tb_r64core.v %SRC%
if errorlevel 1 (echo COMPILACAO FALHOU & exit /b 1)
for %%V in (q1 q2) do vvp -n r64core.vvp +hex=vec/%%V_mem.hex +trace=vec/%%V_trace.txt +fim=vec/%%V_fim.hex
