@echo off

rem Run INSIDE the OSS CAD Suite terminal. Full SoC regression (REV43d): DMA (4 channels), 8 MB MMU, mapper/MegaRAM in R800, DMA boot, buffer window.

rem Each test ends with a RESULT: ... OK line; the summary at the end lists only those lines.

cd /d "%~dp0sim"

set R=..\..\10_mode_gov\rtl

set C=..\..\09_core_min\rtl

set CORE=%R%\r8064_cpu_gov.v %R%\r8064_msx_sys.v %R%\r8064_fifo_if.v %R%\r8064_mode.v %R%\timing_gov.v %R%\mem_class.v ..\..\10_msx_mem\rtl\msx_mem.v %C%\r8064_core_min.v %C%\r8064_decode.v %C%\r8064_decode_rom.v %C%\regfile64.v %C%\regmap_b.v %C%\regmerge.v %C%\alu_prep.v %C%\alu_core_s.v ..\..\03_muldiv\rtl\mul_unit.v ..\..\03_muldiv\rtl\div_unit.v ..\..\08_fpu\rtl\fpu_unit.v ..\..\08_fpu\rtl\fpu_seq.v 

set SOC=..\rtl\r8064_soc.v ..\rtl\r8064_memsys.v ..\rtl\mem_arb5.v ..\rtl\r8064_dma.v ..\rtl\r8064_xbuf.v ..\rtl\cache_dm.v ..\rtl\mmu.v ..\rtl\sdram_ctrl.v sdram_model.v %CORE%

del ..\teste_regressao_soc.txt 2>nul

iverilog -g2012 -o soc_dma.vvp tb_soc_dma.v %SOC% && vvp soc_dma.vvp >> ..\teste_regressao_soc.txt 2>&1

iverilog -g2012 -o soc_dma3.vvp tb_soc_dma3.v %SOC% && vvp soc_dma3.vvp >> ..\teste_regressao_soc.txt 2>&1

iverilog -g2012 -o soc_hi.vvp tb_soc_hi.v %SOC% && vvp soc_hi.vvp >> ..\teste_regressao_soc.txt 2>&1

iverilog -g2012 -o soc_nat.vvp tb_soc_nat.v %SOC% && vvp soc_nat.vvp >> ..\teste_regressao_soc.txt 2>&1

iverilog -g2012 -o soc_boot.vvp tb_soc_boot.v %SOC% && vvp soc_boot.vvp >> ..\teste_regressao_soc.txt 2>&1

iverilog -g2012 -o dma.vvp tb_dma.v ..\rtl\r8064_dma.v ..\rtl\mem_arb5.v ..\rtl\sdram_ctrl.v sdram_model.v %R%\r8064_fifo_if.v && vvp dma.vvp >> ..\teste_regressao_soc.txt 2>&1

iverilog -g2012 -o dwin.vvp tb_dma_win.v ..\rtl\r8064_dma.v ..\rtl\r8064_xbuf.v ..\rtl\r8064_slot_dec.v ..\rtl\mem_arb5.v ..\rtl\sdram_ctrl.v sdram_model.v %R%\r8064_fifo_if.v && vvp dwin.vvp >> ..\teste_regressao_soc.txt 2>&1

iverilog -g2012 -o slotif.vvp tb_slot_if.v ..\rtl\r8064_slot_if.v ..\rtl\r8064_slot_dec.v %R%\r8064_fifo_if.v && vvp slotif.vvp >> ..\teste_regressao_soc.txt 2>&1
rem full cartridge top (needs -DSIM for the rPLL model); part 1 = PING/HELLO, part 2 (+p2) = INT and slot /RESET
iverilog -g2012 -DSIM -o cart.vvp tb_cart_mon.v ..\rtl\r8064_cart_top.v ..\rtl\r8064_clkgen.v ..\rtl\r8064_slot_if.v ..\rtl\r8064_slot_dec.v %SOC% && (vvp cart.vvp & vvp cart.vvp +p2) >> ..\teste_regressao_soc.txt 2>&1
echo ===== resumo =====

findstr /i "RESULT ERROR" ..\teste_regressao_soc.txt

