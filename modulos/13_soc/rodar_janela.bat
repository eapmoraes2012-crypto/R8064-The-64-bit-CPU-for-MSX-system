@echo off
rem Rodar DENTRO do terminal do OSS CAD Suite. Teste da janela de troca MSX <-> R8064 (REV46): portas 0Bh/0Ch/0Dh, buffer de 16 KB e DMA com abertura de endereco (bit 23).
cd /d "%~dp0sim"
iverilog -g2012 -o dwin.vvp tb_dma_win.v ..\rtl\r8064_dma.v ..\rtl\r8064_xbuf.v ..\rtl\r8064_slot_dec.v ..\rtl\mem_arb5.v ..\rtl\sdram_ctrl.v sdram_model.v ..\..\10_mode_gov\rtl\r8064_fifo_if.v
vvp dwin.vvp > teste_dma_win.txt 2>&1
iverilog -g2012 -o dma.vvp tb_dma.v ..\rtl\r8064_dma.v ..\rtl\mem_arb5.v ..\rtl\sdram_ctrl.v sdram_model.v ..\..\10_mode_gov\rtl\r8064_fifo_if.v
vvp dma.vvp > teste_dma.txt 2>&1
findstr /i "RESULTADO ERRO" teste_dma_win.txt teste_dma.txt
