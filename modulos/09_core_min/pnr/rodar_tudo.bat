@echo off
rem Run INSIDE the OSS CAD Suite terminal.
cd /d "%~dp0"
set R=..\rtl
set M1=..\..\01_alu_regfile\rtl
echo [0/4] Module 01 test with the new ALU (parallel Z)...
cd ..\..\01_alu_regfile\ref
set M1=..\rtl
set R=..\..\09_core_min\rtl
iverilog -g2012 -o t01.vvp ..\..\01_alu_regfile\rtl\tb_alu_regfile.v ..\..\01_alu_regfile\rtl\alu_core.v ..\..\01_alu_regfile\rtl\alu64.v ..\..\01_alu_regfile\rtl\alu_prep.v ..\..\01_alu_regfile\rtl\regfile64.v ..\..\01_alu_regfile\rtl\regmap.v ..\..\01_alu_regfile\rtl\regmerge.v > ..\..\09_core_min\pnr\teste01.txt 2>&1
vvp t01.vvp >> ..\..\09_core_min\pnr\teste01.txt 2>&1
cd ..\..\09_core_min\pnr
set R=..\rtl
echo [0a/4] 2-stage ALU test (alu_core_s)...
cd ..\..\01_alu_regfile\ref
iverilog -g2012 -o ts.vvp ..\..\09_core_min\sim\tb_alu_s.v ..\..\09_core_min\rtl\alu_core_s.v ..\rtl\alu_prep.v > ..\..\09_core_min\pnr\teste_alu_s.txt 2>&1
vvp ts.vvp >> ..\..\09_core_min\pnr\teste_alu_s.txt 2>&1
cd ..\..\09_core_min\pnr
echo [0b/4] Core test...
cd ..\sim
iverilog -g2012 -o core.vvp tb_core.v %R%\alu_core_s.v %R%\alu_prep.v %R%\r8064_core_min.v %R%\r8064_decode.v %R%\r8064_decode_rom.v %R%\regfile64.v %R%\regmap_b.v %R%\regmerge.v > ..\pnr\testecore.txt 2>&1
iverilog -g2012 -o bank.vvp tb_bank.v %R%\alu_core_s.v %R%\alu_prep.v %R%\r8064_core_min.v %R%\r8064_decode.v %R%\r8064_decode_rom.v %R%\regfile64.v %R%\regmap_b.v %R%\regmerge.v > ..\pnr\testebanco.txt 2>&1
vvp bank.vvp >> ..\pnr\testebanco.txt 2>&1
iverilog -g2012 -o seq.vvp tb_seq.v %R%\alu_core_s.v %R%\alu_prep.v %R%\r8064_core_min.v %R%\r8064_decode.v %R%\r8064_decode_rom.v %R%\regfile64.v %R%\regmap_b.v %R%\regmerge.v > ..\pnr\testeseq.txt 2>&1
vvp seq.vvp >> ..\pnr\testeseq.txt 2>&1
vvp core.vvp >> ..\pnr\testecore.txt 2>&1
cd ..\pnr
echo [1/4] PnR: the old wrapper pnr_core_top.v was retired (it did not have the core's new ports and synthesis failed, leaving a stale c.json).
echo Use the module 10 flow (core + governor + mode, what the budget measures): 10_mode_gov\pnr\rodar_pnr.bat
