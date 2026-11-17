@echo off
rem Run INSIDE the OSS CAD Suite terminal. Module 10: mode register + Z80/R800 timing governor.
cd /d "%~dp0sim"
set R=..\rtl
set C=..\..\09_core_min
set CORE=%R%\r8064_cpu_gov.v %R%\r8064_mode.v %R%\timing_gov.v %R%\mem_class.v %C%\rtl\r8064_core_min.v %C%\rtl\r8064_decode.v %C%\rtl\r8064_decode_rom.v %C%\rtl\regfile64.v %C%\rtl\regmap_b.v %C%\rtl\regmerge.v %C%\rtl\alu_prep.v %C%\rtl\alu_core_s.v ..\..\03_muldiv\rtl\mul_unit.v ..\..\03_muldiv\rtl\div_unit.v ..\..\08_fpu\rtl\fpu_unit.v ..\..\08_fpu\rtl\fpu_seq.v 
rem the core's .mem files (uop, mainctrl, ctrl_b, rom_ed_*, amb_idx, prog) stay in 09_core_min\sim
copy /y %C%\sim\*.mem . >nul
copy /y %C%\sim\gen_roms.py . >nul
copy /y %C%\sim\gen_z80_rom.py . >nul
rem Python: try the 'py' launcher, then python3, then python (Windows' 'python' may be just the Microsoft Store shortcut, which gives an error)
set PY=
py -3 -c "import sys" >nul 2>&1 && set PY=py -3
if not defined PY python3 -c "import sys" >nul 2>&1 && set PY=python3
if not defined PY python -c "import sys" >nul 2>&1 && set PY=python
rem gen_gov_rom.py now generates all 2048 words (includes page 7 = IRQ) and reproduces the versioned gov_rom.mem
if defined PY (%PY% gen_gov_rom.py ..\..\..\ref\z80_classico_tstates.csv) else echo WARNING: Python not found - using the gov_rom.mem that already exists in sim
rem the core RTL exists in 09_core_min\rtl (used here) and in 10_mode_gov\rtl (used by the synthesis .ys files): the copies MUST be equal
for %%F in (r8064_core_min.v r8064_decode.v r8064_decode_rom.v alu_core_s.v) do fc /b %C%\rtl\%%F %R%\%%F >nul || echo ERROR: %%F differs between 09_core_min\rtl and 10_mode_gov\rtl
iverilog -g2012 -o mode.vvp tb_mode.v %R%\r8064_mode.v && vvp mode.vvp > ..\teste_modo.txt 2>&1
iverilog -g2012 -o mem.vvp tb_mem.v %R%\mem_class.v && vvp mem.vvp > ..\teste_classificador.txt 2>&1
iverilog -g2012 -o gov.vvp tb_gov.v %R%\timing_gov.v && vvp gov.vvp > ..\teste_governador.txt 2>&1
iverilog -g2012 -o cg.vvp tb_cpu_gov.v %CORE% && (vvp cg.vvp +native & vvp cg.vvp & vvp cg.vvp +r800 & vvp cg.vvp +r800 +ext) > ..\teste_cpu_gov.txt 2>&1
set SYS=%R%\r8064_msx_sys.v %R%\r8064_fifo_if.v %C%\..\10_msx_mem\rtl\msx_mem.v %CORE%
iverilog -g2012 -o sys.vvp tb_sys.v %SYS% && (vvp sys.vvp & vvp sys.vvp +r800) > ..\teste_sistema.txt 2>&1
iverilog -g2012 -o ss.vvp tb_sys_seq.v %SYS% && (vvp ss.vvp & vvp ss.vvp +r800) > ..\teste_sistema_seq.txt 2>&1
iverilog -g2012 -o sl.vvp tb_sys_ldir.v %SYS% && (vvp sl.vvp & vvp sl.vvp +r800) > ..\teste_tempo_ldir.txt 2>&1
iverilog -g2012 -o si.vvp tb_sys_irq.v %SYS% && (vvp si.vvp & vvp si.vvp +r800) > ..\teste_tempo_irq.txt 2>&1
iverilog -g2012 -o sx.vvp tb_xing.v %CORE% && vvp sx.vvp > ..\teste_cruzamento.txt 2>&1
echo Done: teste_sistema_seq.txt teste_sistema.txt teste_modo.txt teste_governador.txt teste_cpu_gov.txt
rem FIFO MSX<->R8064 (ports E8h-ECh)
iverilog -g2012 -o t.vvp tb_fifo.v %R%\r8064_fifo_if.v && vvp t.vvp > ..\teste_fifo.txt 2>&1
iverilog -g2012 -o t.vvp tb_sys_fifo.v %SYS% && vvp t.vvp > ..\teste_sys_fifo.txt 2>&1
rem EXINI: returns the main group and AF to the reset state
iverilog -g2012 -o t.vvp tb_exini.v %CORE% && vvp t.vvp > ..\teste_exini.txt 2>&1
iverilog -g2012 -o cn.vvp tb_cplneg.v %CORE% && vvp cn.vvp > ..\teste_cplneg.txt 2>&1
rem core tests that were outside the regression: blocks, I/O (C), interrupts (legacy, IM1, IM2, EI delay), LD A,I and sequencer
del ..\teste_nucleo.txt 2>nul
for %%T in (blk io irq irq3 ldai seq) do (iverilog -g2012 -o t.vvp tb_%%T.v %CORE% && vvp t.vvp >> ..\teste_nucleo.txt 2>&1)
iverilog -g2012 -o t.vvp tb_irq2.v %CORE% && (vvp t.vvp & vvp t.vvp +im2) >> ..\teste_nucleo.txt 2>&1
type ..\teste_fifo.txt ..\teste_sys_fifo.txt ..\teste_exini.txt | findstr /i "RESULT OK ERROR error"
echo ===== test summary =====
findstr /i "RESULT ERROR" ..\teste_modo.txt ..\teste_classificador.txt ..\teste_governador.txt ..\teste_cpu_gov.txt ..\teste_sistema.txt ..\teste_sistema_seq.txt ..\teste_tempo_ldir.txt ..\teste_tempo_irq.txt ..\teste_cruzamento.txt ..\teste_fifo.txt ..\teste_sys_fifo.txt ..\teste_exini.txt .
