@echo off
rem Rode DENTRO do terminal do OSS CAD Suite. Teste de fumaca das instrucoes R8064 de 16/32/64 bits (ver ..\PREMISSAS_R8064.txt).
cd /d "%~dp0"
set S=..\sim
set R=..\rtl
for %%F in (uop.mem mainctrl.mem rom_ed_a.mem rom_ed_b.mem amb_idx.mem ctrl.mem ctrl_b.mem) do copy /y %S%\%%F . >nul
iverilog -g2012 -o r64.vvp tb_r64_fumaca.v %R%\r8064_core_min.v %R%\r8064_decode.v %R%\r8064_decode_rom.v %R%\regfile64.v %R%\regmap_b.v %R%\regmerge.v %R%\alu_prep.v %R%\alu_core_s.v
if errorlevel 1 (echo COMPILACAO FALHOU & exit /b 1)
vvp -n r64.vvp
