`timescale 1ns/1ps
// Full SoC: sequence program (LD SP/PUSH/POP/CALL/RET/OUT/IN) executed from the SDRAM (model with protocol checking) through MMU (bypass) + caches + arbiters.
module tb_soc_hi;
    wire mmu_en_w, mmu_user_w; integer sc = 1; integer nfi = 0, nfd = 0; reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg io_we = 0, io_re = 0; reg [7:0] io_a = 0, io_wd = 0; wire [7:0] io_rd; wire io_oe, iox_we, iox_re; wire [7:0] iox_a, iox_wd;
    wire nat, csel, z80, rom, mbusy, cv, dbg_sig, init_done, fifo_irq, fifo_rst, fbi, fbd, i_fault, d_fault; wire [2:0] ic, dc; wire [63:0] dbg_pc; wire [7:0] dbg_f, fm_rd;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o, mdq;
    reg [31:0] dq_in; always @* dq_in = mdq;
    r8064_soc #(.INIT_CYC(2000)) dut(.clk(clk), .rst(rst), .irq(1'b1),
        .io_we(io_we), .io_re(io_re), .io_a(io_a), .io_wd(io_wd), .io_rd(io_rd), .io_oe(io_oe), .io_x_we(iox_we), .io_x_re(iox_re), .io_x_a(iox_a), .io_x_wd(iox_wd), .io_x_rd(8'h5A), .port_c(8'd0),
        .sb_we(1'b0), .sb_re(1'b0), .sb_a(14'd0), .sb_wd(8'd0), .sb_rd(), .fm_we(1'b0), .fm_re(1'b0), .fm_a(2'd0), .fm_wd(8'd0), .fm_rd(fm_rd), .fifo_irq(fifo_irq), .fifo_rst(fifo_rst),
        .native64(nat), .clk_sel(csel), .is_z80(z80), .is_rom(rom), .mode_busy(mbusy), .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_sig), .gov_cv(cv),
        .fl_busy_i(fbi), .fl_busy_d(fbd), .mmu_en(mmu_en_w), .mmu_user(mmu_user_w),
        .i_fault(i_fault), .d_fault(d_fault), .i_cause(ic), .d_cause(dc),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a),
        .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(dq_in));
    sdram_model mdl(.clk(clk), .cke(s_cke), .cs_n(s_cs_n), .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm), .ba(s_ba), .a(s_a), .dq_i(s_dq_o), .dq_oe(s_dq_oe), .dq_o(mdq));
    integer nwi = 0, nwd = 0; always @(posedge clk) begin if (dut.u_mem.iw_accept) nwi <= nwi + 1; if (dut.u_mem.dw_accept) nwd <= nwd + 1; end
    integer errs = 0, k, n_ow = 0, n_ir = 0; reg [15:0] retpc = 0; reg [7:0] lw_a = 0, lw_d = 0; reg [63:0] pm [0:511];
    always @(posedge clk) begin if (iox_we) begin n_ow <= n_ow + 1; lw_a <= iox_a; lw_d <= iox_wd; end if (iox_re) n_ir <= n_ir + 1; end
    task wio(input [7:0] ad, input [7:0] d); begin @(posedge clk); #1 io_a = ad; io_wd = d; io_we = 1; @(posedge clk); #1 io_we = 0; end endtask
    task chk(input [255:0] nome, input [63:0] got, input [63:0] exp);
        if (got !== exp) begin errs = errs + 1; $display("ERROR %0s: got %h expected %h", nome, got, exp); end
    endtask
    reg [7:0] by [0:511]; reg [63:0] w; integer p;
    task emit(input [7:0] x); begin by[p] = x; p = p + 1; end endtask
    task ldrr(input [2:0] rr, input [15:0] v); begin emit(8'hED); emit(8'h3B); emit(8'h40 | (rr << 3) | 8'h01); emit(v[7:0]); emit(v[15:8]); end endtask
    task mtcr(input [4:0] n); begin emit(8'hED); emit(8'h0C); emit(n); end endtask
    task mfcr(input [4:0] n); begin emit(8'hED); emit(8'h0A); emit(n); end endtask
    function [63:0] rf(input integer n); rf = dut.u_sys.u_cpu.u_core.u_rf1.mem_a[n]; endfunction
    always @(posedge clk) begin if (i_fault) nfi <= nfi + 1; if (d_fault) nfd <= nfd + 1; end
    wire [63:0] r43 = dut.u_sys.u_cpu.u_core.u_rf1.mem_a[43], r44 = dut.u_sys.u_cpu.u_core.u_rf1.mem_a[44], r45 = dut.u_sys.u_cpu.u_core.u_rf1.mem_a[45];
    initial begin
        if (!$value$plusargs("sc=%d", sc)) sc = 1;
        for (k = 0; k < 512; k = k + 1) by[k] = 8'h00; p = 0;
        ldrr(7, 16'h0100); mtcr(5'd15); ldrr(7, 16'h0001); mtcr(5'd14);      // root = PPN 100h; MMU on
        emit(8'h31); emit(8'h00); emit(8'h48); ldrr(0, 16'h1234); emit(8'hC5); emit(8'hD1);   // LD SP,4800h (VA 4000h -> PA 700000h) ; BC=1234 ; PUSH BC ; POP DE
        emit(8'h31); emit(8'h00); emit(8'h40); emit(8'hC1);                                    // LD SP,4000h ; POP BC (le 4000h = PA 700000h)
        emit(8'h18); emit(8'hFE);
        for (k = 0; k < 64; k = k + 1) begin
            w = {by[8*k+7], by[8*k+6], by[8*k+5], by[8*k+4], by[8*k+3], by[8*k+2], by[8*k+1], by[8*k]};
            mdl.mem[2*k] = w[31:0]; mdl.mem[2*k + 1] = w[63:32];
        end
        mdl.mem[2*(24'h100000>>3)] = 32'h00040401; mdl.mem[2*(24'h101000>>3)] = 32'h00040801;
        mdl.mem[2*(24'h102000>>3)] = 32'h000000CF; mdl.mem[2*((24'h102000>>3)+4)] = 32'h001C00CF;   // VA 0000h and 4000h mapped; 1000h-3FFFh invalid
        repeat (4) @(posedge clk); rst = 0;
        wait (init_done);
        repeat (60000) @(posedge clk);
        w = {mdl.mem[2*24'h0E00FF + 1], mdl.mem[2*24'h0E00FF]};
        chk("PUSH wrote to PA 7007FE (MMU reaches >4 MB)", w >> 48, 64'h1234);
        chk("DE (POP = PUSH, via cache)", rf(2), 64'h1234);
        chk("BC (POP de PA 700000h)", rf(1), 64'h0);
        chk("SP", rf(11), 64'h4002);
        w = {mdl.mem[2*24'h0008FF + 1], mdl.mem[2*24'h0008FF]}; chk("PA 47F8 (4 MB alias) intact", w, 64'h0);
        chk("no I fault", nfi, 0); chk("no D fault", nfd, 0); chk("SDRAM violations", mdl.viol, 0);
        $display("pc=%h", dbg_pc);
        if (errs == 0) $display("RESULT: MMU 8MB OK"); else $display("RESULT: %0d ERRORS", errs);
        $finish;
    end
endmodule
