@echo off
rem Rode DENTRO do terminal do OSS CAD Suite.
cd /d "%~dp0"
set R=..\rtl
set M1=..\..\01_alu_regfile\rtl
echo [0/4] Teste do modulo 01 com a ALU nova (Z paralelo)...
cd ..\..\01_alu_regfile\ref
set M1=..\rtl
set R=..\..\09_core_min\rtl
iverilog -g2012 -o t01.vvp ..\..\01_alu_regfile\rtl\tb_alu_regfile.v ..\..\01_alu_regfile\rtl\alu_core.v ..\..\01_alu_regfile\rtl\alu64.v ..\..\01_alu_regfile\rtl\alu_prep.v ..\..\01_alu_regfile\rtl\regfile64.v ..\..\01_alu_regfile\rtl\regmap.v ..\..\01_alu_regfile\rtl\regmerge.v > ..\..\09_core_min\pnr\teste01.txt 2>&1
vvp t01.vvp >> ..\..\09_core_min\pnr\teste01.txt 2>&1
cd ..\..\09_core_min\pnr
set R=..\rtl
echo [0a/4] Teste da ALU de 2 estagios (alu_core_s)...
cd ..\..\01_alu_regfile\ref
iverilog -g2012 -o ts.vvp ..\..\09_core_min\sim\tb_alu_s.v ..\..\09_core_min\rtl\alu_core_s.v ..\rtl\alu_prep.v > ..\..\09_core_min\pnr\teste_alu_s.txt 2>&1
vvp ts.vvp >> ..\..\09_core_min\pnr\teste_alu_s.txt 2>&1
cd ..\..\09_core_min\pnr
echo [0b/4] Teste do nucleo...
cd ..\sim
iverilog -g2012 -o core.vvp tb_core.v %R%\alu_core_s.v %R%\alu_prep.v %R%\r8064_core_min.v %R%\r8064_decode.v %R%\r8064_decode_rom.v %R%\regfile64.v %R%\regmap_b.v %R%\regmerge.v > ..\pnr\testecore.txt 2>&1
iverilog -g2012 -o bank.vvp tb_bank.v %R%\alu_core_s.v %R%\alu_prep.v %R%\r8064_core_min.v %R%\r8064_decode.v %R%\r8064_decode_rom.v %R%\regfile64.v %R%\regmap_b.v %R%\regmerge.v > ..\pnr\testebanco.txt 2>&1
vvp bank.vvp >> ..\pnr\testebanco.txt 2>&1
iverilog -g2012 -o seq.vvp tb_seq.v %R%\alu_core_s.v %R%\alu_prep.v %R%\r8064_core_min.v %R%\r8064_decode.v %R%\r8064_decode_rom.v %R%\regfile64.v %R%\regmap_b.v %R%\regmerge.v > ..\pnr\testeseq.txt 2>&1
vvp seq.vvp >> ..\pnr\testeseq.txt 2>&1
vvp core.vvp >> ..\pnr\testecore.txt 2>&1
cd ..\pnr
echo [1/4] PnR: o invólucro antigo pnr_core_top.v foi aposentado (nao tinha as portas novas do nucleo e a sintese falhava, deixando c.json velho).
echo Use o fluxo do modulo 10 (nucleo + governador + modo, o que o orcamento mede): 10_mode_gov\pnr\rodar_pnr.bat
