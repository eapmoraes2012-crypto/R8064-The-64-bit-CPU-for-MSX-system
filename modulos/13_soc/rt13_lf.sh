source $HOME/oss/oss-cad-suite/environment
cd $HOME/mnt/Documents/R8064_rtl_pack/modulos/13_soc/sim
R=../../10_mode_gov/rtl; C=../../09_core_min/rtl; S=../rtl
CORE="$R/r8064_cpu_gov.v $R/r8064_msx_sys.v $R/r8064_fifo_if.v $R/r8064_mode.v $R/timing_gov.v $R/mem_class.v ../../10_msx_mem/rtl/msx_mem.v $C/r8064_core_min.v $C/r8064_decode.v $C/r8064_decode_rom.v $C/regfile64.v $C/regmap_b.v $C/regmerge.v $C/alu_prep.v $C/alu_core_s.v ../../03_muldiv/rtl/mul_unit.v ../../03_muldiv/rtl/div_unit.v ../../08_fpu/rtl/fpu_unit.v ../../08_fpu/rtl/fpu_seq.v"
SOC="$S/r8064_soc.v $S/r8064_memsys.v $S/mem_arb5.v $S/r8064_dma.v $S/r8064_xbuf.v $S/cache_dm.v $S/mmu.v $S/sdram_ctrl.v sdram_model.v $CORE"
O=/tmp/o13; mkdir -p $O
iverilog -g2012 -o $O/exc.vvp tb_soc_exc.v $SOC 2>&1 | head -5
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do vvp $O/exc.vvp +sc=$i | grep -h "RESULT\|ERROR"; done > $O/teste_exc.txt
iverilog -g2012 -o $O/soc.vvp tb_soc.v $SOC 2>&1 | head -5; vvp $O/soc.vvp > $O/teste_soc.txt 2>&1
iverilog -g2012 -o $O/sdma.vvp tb_soc_dma.v $SOC 2>&1 | head -5; vvp $O/sdma.vvp > $O/teste_soc_dma.txt 2>&1
iverilog -g2012 -o $O/hi.vvp tb_soc_hi.v $SOC 2>&1 | head -5; vvp $O/hi.vvp > $O/teste_soc_hi.txt 2>&1
iverilog -g2012 -o $O/sdma3.vvp tb_soc_dma3.v $SOC 2>&1 | head -5; vvp $O/sdma3.vvp > $O/teste_soc_dma3.txt 2>&1
iverilog -g2012 -o $O/nat.vvp tb_soc_nat.v $SOC 2>&1 | head -5; vvp $O/nat.vvp > $O/teste_soc_nat.txt 2>&1
grep -H "RESULT\|ERROR\|dbg_pc" $O/teste_*.txt | cut -c1-200
iverilog -g2012 -o $O/dma.vvp tb_dma.v $S/r8064_dma.v $S/mem_arb5.v $S/sdram_ctrl.v sdram_model.v $R/r8064_fifo_if.v 2>&1 | head -5; vvp $O/dma.vvp > $O/teste_dma.txt 2>&1
iverilog -g2012 -o $O/dwin.vvp tb_dma_win.v $S/r8064_dma.v $S/r8064_xbuf.v $S/r8064_slot_dec.v $S/mem_arb5.v $S/sdram_ctrl.v sdram_model.v $R/r8064_fifo_if.v 2>&1 | head -5; vvp $O/dwin.vvp > $O/teste_dma_win.txt 2>&1
grep -H "RESULT\|ERROR" $O/teste_dma.txt $O/teste_dma_win.txt | cut -c1-200
