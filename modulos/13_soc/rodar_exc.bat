@echo off
rem Rode no terminal do OSS CAD Suite. Falta de MMU como excecao no nucleo (tb_soc_exc, cenarios 1-8).
cd /d "%~dp0sim"
set R=..\..\10_mode_gov\rtl
set C=..\..\09_core_min\rtl
set CORE=%R%\r8064_cpu_gov.v %R%\r8064_msx_sys.v %R%\r8064_fifo_if.v %R%\r8064_mode.v %R%\timing_gov.v %R%\mem_class.v ..\..\10_msx_mem\rtl\msx_mem.v %C%\r8064_core_min.v %C%\r8064_decode.v %C%\r8064_decode_rom.v %C%\regfile64.v %C%\regmap_b.v %C%\regmerge.v %C%\alu_prep.v %C%\alu_core_s.v %C%\alu_core.v %C%\alu64.v 
iverilog -g2012 -o exc.vvp tb_soc_exc.v ..\rtl\r8064_soc.v ..\rtl\r8064_memsys.v ..\rtl\mem_arb4.v ..\rtl\cache_dm.v ..\rtl\mmu.v ..\rtl\sdram_ctrl.v sdram_model.v %CORE%
vvp exc.vvp +sc=1
vvp exc.vvp +sc=2
vvp exc.vvp +sc=3
vvp exc.vvp +sc=4
vvp exc.vvp +sc=5
vvp exc.vvp +sc=6
vvp exc.vvp +sc=7
vvp exc.vvp +sc=8
