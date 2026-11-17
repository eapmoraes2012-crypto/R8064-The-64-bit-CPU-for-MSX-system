`timescale 1ns/1ps
// Boot: the buffer image (boot_l0..7.hex) is copied to SDRAM 0 before the core leaves reset. (derived from tb_soc_dma)
// Full SoC + DMA: the core programs channel 0 by MTCR (CR19..21), waits for the end on port EEh and checks that the data cache was invalidated (LD DE,(2000h) returns the new data).
module tb_soc_boot;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg io_we = 0, io_re = 0; reg [7:0] io_a = 0, io_wd = 0; wire [7:0] io_rd; wire io_oe, iox_we, iox_re; wire [7:0] iox_a, iox_wd;
    wire nat, csel, z80, rom, mbusy, cv, dbg_sig, init_done, fifo_irq, fifo_rst, fbi, fbd, i_fault, d_fault; wire [2:0] ic, dc; wire [63:0] dbg_pc; wire [7:0] dbg_f, fm_rd;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o, mdq;
    reg [31:0] dq_in; always @* dq_in = mdq;
    r8064_soc #(.INIT_CYC(2000), .BOOT_WORDS(2048), .INIT_IMG(1)) dut(.clk(clk), .rst(rst), .irq(1'b1),
        .io_we(io_we), .io_re(io_re), .io_a(io_a), .io_wd(io_wd), .io_rd(io_rd), .io_oe(io_oe), .io_x_we(iox_we), .io_x_re(iox_re), .io_x_a(iox_a), .io_x_wd(iox_wd), .io_x_rd(8'h5A), .port_c(8'd0),
        .sb_we(1'b0), .sb_re(1'b0), .sb_a(14'd0), .sb_wd(8'd0), .sb_rd(), .fm_we(1'b0), .fm_re(1'b0), .fm_a(2'd0), .fm_wd(8'd0), .fm_rd(fm_rd), .fifo_irq(fifo_irq), .fifo_rst(fifo_rst),
        .native64(nat), .clk_sel(csel), .is_z80(z80), .is_rom(rom), .mode_busy(mbusy), .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_sig), .gov_cv(cv),
        .fl_busy_i(fbi), .fl_busy_d(fbd), .mmu_en(), .mmu_user(),
        .i_fault(i_fault), .d_fault(d_fault), .i_cause(ic), .d_cause(dc),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a),
        .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(dq_in));
    defparam dut.u_xbuf.INIT_PFX = "boot_l";
    sdram_model mdl(.clk(clk), .cke(s_cke), .cs_n(s_cs_n), .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm), .ba(s_ba), .a(s_a), .dq_i(s_dq_o), .dq_oe(s_dq_oe), .dq_o(mdq));
    integer nwi = 0, nwd = 0; always @(posedge clk) begin if (dut.u_mem.iw_accept) nwi <= nwi + 1; if (dut.u_mem.dw_accept) nwd <= nwd + 1; end
    integer errs = 0, k; reg [31:0] w;
    integer tb0 = 0; always @(posedge clk) if (!dut.boot_busy && tb0 == 0) begin tb0 <= 1; $display("boot terminou em %0t (init_done=%b)", $time, init_done); end
    initial begin
        repeat (4) @(posedge clk); rst = 0;
        wait (init_done);
        repeat (20000) @(posedge clk);
        $display("mem0=%h mem1=%h mem2=%h xb0=%h", mdl.mem[0], mdl.mem[1], mdl.mem[2], {dut.u_xbuf.lane[7].mem[0],dut.u_xbuf.lane[6].mem[0],dut.u_xbuf.lane[5].mem[0],dut.u_xbuf.lane[4].mem[0],dut.u_xbuf.lane[3].mem[0],dut.u_xbuf.lane[2].mem[0],dut.u_xbuf.lane[1].mem[0],dut.u_xbuf.lane[0].mem[0]});
        if (mdl.mem[0][7:0] !== 8'h31) begin errs = errs + 1; $display("ERROR imagem[0] = %h", mdl.mem[0]); end
        if ({mdl.mem[2*16'h7FF+1], mdl.mem[2*16'h7FF]} !== 64'h214B_5241_4D44_4E45) begin errs = errs + 1; $display("ERROR end = %h %h", mdl.mem[2*16'h7FF+1], mdl.mem[2*16'h7FF]); end
        if (dut.u_sys.u_cpu.u_core.u_rf1.mem_a[0][7:0] !== 8'h5A) begin errs = errs + 1; $display("ERROR A=%h", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[0]); end
        if (dut.u_sys.u_cpu.u_core.u_rf1.mem_a[1][15:8] !== 8'h5B) begin errs = errs + 1; $display("ERROR B=%h", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[1]); end
        $display("mem[C000]=%h", mdl.mem[16'h3000]);
        $display("RESULT boot: errors=%0d dbg_pc=%h boot_busy=%b", errs, dbg_pc, dut.boot_busy);
        $finish;
    end
endmodule
