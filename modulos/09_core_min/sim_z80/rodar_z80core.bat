@echo off
rem Rode DENTRO do terminal do OSS CAD Suite. Nucleo R8064 com o microcodigo do Z80 (uop_z80.mem) contra o modelo de referencia, instrucao a instrucao.
rem Usa os vetores ja gerados em vec\ (2 programas aleatorios com todas as paginas + inicio do ZEXDOC). Para gerar outros: gerar_vetores.sh (precisa de gcc e python3).
cd /d "%~dp0"
set S=..\sim
set R=..\rtl
copy /y %S%\uop_z80.mem . >nul
copy /y %S%\mainctrl_z80.mem . >nul
for %%F in (rom_ed_a.mem rom_ed_b.mem amb_idx.mem ctrl.mem ctrl_b.mem) do copy /y %S%\%%F . >nul
iverilog -g2012 -o z80core.vvp tb_z80core.v %R%\r8064_core_min.v %R%\r8064_decode.v %R%\r8064_decode_rom.v %R%\regfile64.v %R%\regmap_b.v %R%\regmerge.v %R%\alu_prep.v %R%\alu_core_s.v
if errorlevel 1 (echo COMPILACAO FALHOU & exit /b 1)
del resultado_z80core.txt 2>nul
for %%V in (r53 r56 zex) do (
  echo --- %%V >> resultado_z80core.txt
  vvp -n z80core.vvp +hex=vec/%%V_mem.hex +trace=vec/%%V_trace.txt +fim=vec/%%V_fim.hex >> resultado_z80core.txt 2>&1
)
type resultado_z80core.txt
