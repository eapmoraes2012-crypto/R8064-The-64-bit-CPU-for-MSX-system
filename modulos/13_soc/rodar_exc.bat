@echo off
rem Run in the OSS CAD Suite terminal. MMU fault as a core exception (tb_soc_exc, scenarios 1-8), basic SoC (tb_soc, bypass and +mmu) and clock generator (tb_clkgen).
cd /d "%~dp0sim"
set R=..\..\10_mode_gov\rtl
set C=..\..\09_core_min\rtl
set CORE=%R%\r8064_cpu_gov.v %R%\r8064_msx_sys.v %R%\r8064_fifo_if.v %R%\r8064_mode.v %R%\timing_gov.v %R%\mem_class.v ..\..\10_msx_mem\rtl\msx_mem.v %C%\r8064_core_min.v %C%\r8064_decode.v %C%\r8064_decode_rom.v %C%\regfile64.v %C%\regmap_b.v %C%\regmerge.v %C%\alu_prep.v %C%\alu_core_s.v ..\..\03_muldiv\rtl\mul_unit.v ..\..\03_muldiv\rtl\div_unit.v ..\..\08_fpu\rtl\fpu_unit.v ..\..\08_fpu\rtl\fpu_seq.v 
iverilog -g2012 -o exc.vvp tb_soc_exc.v ..\rtl\r8064_soc.v ..\rtl\r8064_memsys.v ..\rtl\mem_arb5.v ..\rtl\r8064_dma.v ..\rtl\r8064_xbuf.v ..\rtl\cache_dm.v ..\rtl\mmu.v ..\rtl\sdram_ctrl.v sdram_model.v %CORE%
vvp exc.vvp +sc=1
vvp exc.vvp +sc=2
vvp exc.vvp +sc=3
vvp exc.vvp +sc=4
vvp exc.vvp +sc=5
vvp exc.vvp +sc=6
vvp exc.vvp +sc=7
vvp exc.vvp +sc=8
rem privilege model (09_core_min\MODELO_PRIVILEGIO.txt): 9 user mode with MMU, 10 interrupt in user mode, 11 PROT + RESET, 12 STDBY
vvp exc.vvp +sc=9
vvp exc.vvp +sc=10
vvp exc.vvp +sc=11
vvp exc.vvp +sc=12
rem SoC: sequence program from the SDRAM, MMU in bypass and on
iverilog -g2012 -o soc.vvp tb_soc.v ..\rtl\r8064_soc.v ..\rtl\r8064_memsys.v ..\rtl\mem_arb5.v ..\rtl\r8064_dma.v ..\rtl\r8064_xbuf.v ..\rtl\cache_dm.v ..\rtl\mmu.v ..\rtl\sdram_ctrl.v sdram_model.v %CORE%
vvp soc.vvp
vvp soc.vvp +mmu
rem clock generator (rPLL simulation model: needs -DSIM)
iverilog -g2012 -DSIM -o ck.vvp tb_clkgen.v ..\rtl\r8064_clkgen.v
vvp ck.vvp
