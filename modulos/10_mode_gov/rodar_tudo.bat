@echo off
rem Rode DENTRO do terminal do OSS CAD Suite. Modulo 10: registrador de modo + governador de tempo Z80/R800.
cd /d "%~dp0sim"
set R=..\rtl
set C=..\..\09_core_min
set CORE=%R%\r8064_cpu_gov.v %R%\r8064_mode.v %R%\timing_gov.v %R%\mem_class.v %C%\rtl\r8064_core_min.v %C%\rtl\r8064_decode.v %C%\rtl\r8064_decode_rom.v %C%\rtl\regfile64.v %C%\rtl\regmap_b.v %C%\rtl\regmerge.v %C%\rtl\alu_prep.v %C%\rtl\alu_core_s.v %C%\rtl\alu_core.v %C%\rtl\alu64.v 
rem arquivos .mem do nucleo (uop, mainctrl, ctrl_b, rom_ed_*, amb_idx, prog) ficam em 09_core_min\sim
copy /y %C%\sim\*.mem . >nul
copy /y %C%\sim\gen_roms.py . >nul
rem Python: tenta o lancador 'py', depois python3, depois python (o 'python' do Windows pode ser so o atalho da Microsoft Store, que da erro)
set PY=
py -3 -c "import sys" >nul 2>&1 && set PY=py -3
if not defined PY python3 -c "import sys" >nul 2>&1 && set PY=python3
if not defined PY python -c "import sys" >nul 2>&1 && set PY=python
rem if defined PY (%PY% gen_gov_rom.py ..\..\..\ref\z80_classico_tstates.csv) else echo AVISO: Python nao encontrado - usando o gov_rom.mem que ja existe em sim
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
echo Pronto: teste_sistema_seq.txt teste_sistema.txt teste_modo.txt teste_governador.txt teste_cpu_gov.txt
rem FIFO MSX<->R8064 (portas E8h-ECh)
iverilog -g2012 -o t.vvp tb_fifo.v %R%\r8064_fifo_if.v && vvp t.vvp > ..\teste_fifo.txt 2>&1
iverilog -g2012 -o t.vvp tb_sys_fifo.v %SYS% && vvp t.vvp > ..\teste_sys_fifo.txt 2>&1
rem EXINI: volta o grupo principal e AF para o estado de reset
iverilog -g2012 -o t.vvp tb_exini.v %CORE% && vvp t.vvp > ..\teste_exini.txt 2>&1
iverilog -g2012 -o cn.vvp tb_cplneg.v %CORE% && vvp cn.vvp > ..\teste_cplneg.txt 2>&1
type ..\teste_fifo.txt ..\teste_sys_fifo.txt ..\teste_exini.txt | findstr /i "RESULTADO OK ERRO erro"
echo ===== resumo dos testes =====
findstr /i "RESULTADO ERRO" ..\teste_modo.txt ..\teste_classificador.txt ..\teste_governador.txt ..\teste_cpu_gov.txt ..\teste_sistema.txt ..\teste_sistema_seq.txt ..\teste_tempo_ldir.txt ..\teste_tempo_irq.txt ..\teste_cruzamento.txt ..\teste_fifo.txt ..\teste_sys_fifo.txt ..\teste_exini.txt ..\teste_cplneg.txt
