`timescale 1ns/1ps
// Full SoC + DMA: the core programs channel 0 by MTCR (CR19..21), waits for the end on port EEh and checks that the data cache was invalidated (LD DE,(2000h) returns the new data).
module tb_soc_dma3;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg io_we = 0, io_re = 0; reg [7:0] io_a = 0, io_wd = 0; wire [7:0] io_rd; wire io_oe, iox_we, iox_re; wire [7:0] iox_a, iox_wd;
    wire nat, csel, z80, rom, mbusy, cv, dbg_sig, init_done, fifo_irq, fifo_rst, fbi, fbd, i_fault, d_fault; wire [2:0] ic, dc; wire [63:0] dbg_pc; wire [7:0] dbg_f, fm_rd;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o, mdq;
    reg [31:0] dq_in; always @* dq_in = mdq;
    r8064_soc #(.INIT_CYC(2000)) dut(.clk(clk), .rst(rst), .irq(1'b1),
        .io_we(io_we), .io_re(io_re), .io_a(io_a), .io_wd(io_wd), .io_rd(io_rd), .io_oe(io_oe), .io_x_we(iox_we), .io_x_re(iox_re), .io_x_a(iox_a), .io_x_wd(iox_wd), .io_x_rd(8'h5A), .port_c(8'd0),
        .sb_we(1'b0), .sb_re(1'b0), .sb_a(14'd0), .sb_wd(8'd0), .sb_rd(), .fm_we(1'b0), .fm_re(1'b0), .fm_a(2'd0), .fm_wd(8'd0), .fm_rd(fm_rd), .fifo_irq(fifo_irq), .fifo_rst(fifo_rst),
        .native64(nat), .clk_sel(csel), .is_z80(z80), .is_rom(rom), .mode_busy(mbusy), .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_sig), .gov_cv(cv),
        .fl_busy_i(fbi), .fl_busy_d(fbd), .mmu_en(), .mmu_user(),
        .i_fault(i_fault), .d_fault(d_fault), .i_cause(ic), .d_cause(dc),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a),
        .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(dq_in));
    sdram_model mdl(.clk(clk), .cke(s_cke), .cs_n(s_cs_n), .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm), .ba(s_ba), .a(s_a), .dq_i(s_dq_o), .dq_oe(s_dq_oe), .dq_o(mdq));
    integer nwi = 0, nwd = 0; always @(posedge clk) begin if (dut.u_mem.iw_accept) nwi <= nwi + 1; if (dut.u_mem.dw_accept) nwd <= nwd + 1; end
    integer errs = 0, k, n_ow = 0, n_ir = 0; reg [7:0] lw_a = 0, lw_d = 0; reg [7:0] by [0:511]; integer p; reg [63:0] w, ex;
    always @(posedge clk) begin if (iox_we) begin n_ow <= n_ow + 1; lw_a <= iox_a; lw_d <= iox_wd; end if (iox_re) n_ir <= n_ir + 1; end
    task wio(input [7:0] ad, input [7:0] d); begin @(posedge clk); #1 io_a = ad; io_wd = d; io_we = 1; @(posedge clk); #1 io_we = 0; end endtask
    task chk(input [255:0] nome, input [63:0] got, input [63:0] exp);
        if (got !== exp) begin errs = errs + 1; $display("ERROR %0s: got %h expected %h", nome, got, exp); end
    endtask
    task emit(input [7:0] x); begin by[p] = x; p = p + 1; end endtask
    task ldw(input [2:0] rr, input [15:0] v); begin emit(8'hED); emit(8'h3B); emit(8'h40 | (rr << 3) | 8'h01); emit(v[7:0]); emit(v[15:8]); end endtask
    task lde(input [2:0] rr, input [31:0] v); begin emit(8'hED); emit(8'h39); emit(8'h40 | (rr << 3) | 8'h01); emit(v[7:0]); emit(v[15:8]); emit(v[23:16]); emit(v[31:24]); emit(8'h00); emit(8'h00); emit(8'h00); emit(8'h00); end endtask
    task mtcr(input [4:0] n); begin emit(8'hED); emit(8'h0C); emit(n); end endtask
    function [63:0] rf(input integer n); rf = dut.u_sys.u_cpu.u_core.u_rf1.mem_a[n]; endfunction
    function [63:0] src(input integer i); src = 64'h1111222233334444 + i * 64'h0101010101010101; endfunction
    integer ndma = 0, ninv = 0; always @(posedge clk) begin if (dut.dma_inv) ninv <= ninv + 1; if (dut.u_mem.x_done) ndma <= ndma + 1; end
    initial begin
        for (k = 0; k < 512; k = k + 1) by[k] = 8'h00; p = 0;
        emit(8'h31); emit(8'h00); emit(8'h48); emit(8'hE1);                    // LD BC,(2000h): brings the destination line into the data cache
        ldw(7, 16'h4400); mtcr(5'd28);                                         // SRC0 = 1000h
        ldw(7, 16'h4800); mtcr(5'd29);                                         // DST0 = 2000h
        lde(7, 32'h8000_0008); mtcr(5'd30);                                    // CTRL0: START, mode 0, 8 words
        emit(8'h00); emit(8'h00); emit(8'h00); emit(8'h00); emit(8'h00); emit(8'h00);   // wait: NOPs (the DMA finishes in ~1 us)
        emit(8'h31); emit(8'h00); emit(8'h48); emit(8'hD1);                    // LD DE,(2000h): must see the copied data
        emit(8'h18); emit(8'hFE);
        for (k = 0; k < 64; k = k + 1) begin
            w = {by[8*k+7], by[8*k+6], by[8*k+5], by[8*k+4], by[8*k+3], by[8*k+2], by[8*k+1], by[8*k]};
            mdl.mem[2*k] = w[31:0]; mdl.mem[2*k + 1] = w[63:32];
        end
        for (k = 0; k < 8; k = k + 1) begin
            mdl.mem[2*(16'h880 + k)] = src(k); mdl.mem[2*(16'h880 + k) + 1] = src(k) >> 32;               // source: 1000h
            mdl.mem[2*(16'h900 + k)] = 32'hDEAD5A00 + k; mdl.mem[2*(16'h900 + k) + 1] = 32'hBEEF0000 + k; // destination: 2000h (old value)
        end
        mdl.mem[2*(16'h908)] = 32'h77777777; mdl.mem[2*(16'h908) + 1] = 32'h88888888;                // word right after the destination: intact
        repeat (4) @(posedge clk); rst = 0;
        wait (init_done);
        
        repeat (40000) @(posedge clk);
        
        chk("HL = old value (line entered the cache)", rf(3) & 64'hFFFF, 64'h5A00); chk("DE = new value (cache invalidated)", rf(2) & 64'hFFFF, src(0) & 64'hFFFF);
        for (k = 0; k < 8; k = k + 1) begin w = {mdl.mem[2*(16'h900 + k) + 1], mdl.mem[2*(16'h900 + k)]}; chk("destination", w, src(k)); end
        w = {mdl.mem[2*16'h908 + 1], mdl.mem[2*16'h908]}; chk("next word intact", w, 64'h8888888877777777);
        chk("8 DMA reads + 8 writes", ndma, 16); chk("1 inv pulse", ninv, 1);
        chk("no I fault", i_fault, 0); chk("no D fault", d_fault, 0); chk("SDRAM violations", mdl.viol, 0);
        $display("dbg_pc=%h BC=%h DE=%h", dbg_pc, rf(3), rf(2));
        if (errs == 0) $display("RESULT: SOC+DMA CHANNEL3 OK"); else $display("RESULT: %0d ERRORS", errs);
        $finish;
    end
endmodule
