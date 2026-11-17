`timescale 1ns/1ps
// Test of the 2-channel DMA (r8064_dma) against the 5-master arbiter + SDRAM controller + SDRAM model (with protocol checker) and the real FIFO (r8064_fifo_if).
module tb_dma;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    // ---- DMA ----
    reg cr_we = 0; reg [3:0] cr_idx = 0; reg [63:0] cr_wd = 0;
    reg io_we = 0, io_re = 0; reg [7:0] io_a = 0, io_wd = 0; wire [7:0] io_rd; wire io_sel;
    wire m_req, m_we, m_acc, m_done; wire [19:0] m_addr; wire [63:0] m_wd, m_rd; wire [7:0] m_be;
    wire a_avail, b_space, d_pop, d_push; wire [7:0] a_q, d_wd; wire irq, inv;
    r8064_dma dma(.clk(clk), .rst(rst), .cr_we(cr_we), .cr_idx(cr_idx), .cr_wd(cr_wd), .io_we(io_we), .io_re(io_re), .io_a(io_a), .io_wd(io_wd), .io_rd(io_rd), .io_sel(io_sel),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wd(m_wd), .m_be(m_be), .m_acc(m_acc), .m_done(m_done), .m_rd(m_rd),
        .a_avail(a_avail), .a_q(a_q), .b_space(b_space), .d_pop(d_pop), .d_push(d_push), .d_wd(d_wd), .b_ok(1'b0), .b_re(), .b_we(), .b_a(), .b_wd(), .b_q(64'd0), .irq(irq), .inv(inv));
    // ---- FIFO (MSX side controlled by the test) ----
    reg fm_we = 0, fm_re = 0; reg [1:0] fm_a = 0; reg [7:0] fm_wd = 0; wire [7:0] fm_rd; wire fm_irq, fm_rst, r_hit; wire [7:0] r_rd;
    r8064_fifo_if fifo(.clk(clk), .rst(rst), .r_we(1'b0), .r_re(1'b0), .r_a(8'd0), .r_wd(8'd0), .r_rd(r_rd), .r_hit(r_hit),
        .m_we(fm_we), .m_re(fm_re), .m_a(fm_a), .m_wd(fm_wd), .m_rd(fm_rd), .m_irq(fm_irq), .r8064_rst(fm_rst),
        .d_pop(d_pop), .d_push(d_push), .d_wd(d_wd), .a_avail(a_avail), .a_q(a_q), .b_space(b_space));
    // ---- memory ----
    wire [4:0] acc, done; wire [63:0] arb_rd; wire c_req, c_we, c_ready, c_rvalid, c_wdone; wire [19:0] c_addr; wire [63:0] c_wd, c_rd; wire [7:0] c_be;
    mem_arb5 arb(.clk(clk), .rst(rst), .req({m_req, 4'b0}), .we({m_we, 4'b0}), .addr({m_addr, 80'd0}), .wdata({m_wd, 256'd0}), .be({m_be, 32'd0}),
        .acc(acc), .done(done), .rdata(arb_rd), .c_req(c_req), .c_we(c_we), .c_addr(c_addr), .c_wdata(c_wd), .c_be(c_be), .c_ready(c_ready), .c_rvalid(c_rvalid), .c_rdata(c_rd), .c_wdone(c_wdone));
    assign m_acc = acc[4]; assign m_done = done[4]; assign m_rd = arb_rd;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe, init_done; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o, mdq;
    sdram_ctrl #(.INIT_CYC(2000)) sd(.clk(clk), .rst(rst), .req(c_req), .we(c_we), .addr(c_addr), .wdata(c_wd), .be(c_be), .ready(c_ready), .rvalid(c_rvalid), .rdata(c_rd), .wdone(c_wdone),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a), .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(mdq));
    sdram_model mdl(.clk(clk), .cke(s_cke), .cs_n(s_cs_n), .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm), .ba(s_ba), .a(s_a), .dq_i(s_dq_o), .dq_oe(s_dq_oe), .dq_o(mdq));
    // ---- utilities ----
    integer errs = 0, i, ninv = 0, t0;
    always @(posedge clk) if (inv) begin ninv <= ninv + 1; if ($test$plusargs("v")) $display("inv em %0t", $time); end
    task crw(input [3:0] idx, input [63:0] v); begin @(posedge clk); #1 cr_idx = idx; cr_wd = v; cr_we = 1; @(posedge clk); #1 cr_we = 0; end endtask
    task iow(input [7:0] a, input [7:0] d); begin @(posedge clk); #1 io_a = a; io_wd = d; io_we = 1; @(posedge clk); #1 io_we = 0; end endtask
    task ior(input [7:0] a, output [7:0] d); begin @(posedge clk); #1 io_a = a; #1 d = io_rd; end endtask
    task fmw(input [7:0] d); begin @(posedge clk); #1 fm_a = 0; fm_wd = d; fm_we = 1; @(posedge clk); #1 fm_we = 0; end endtask
    reg [7:0] fmr;
    task fmrd; begin @(posedge clk); #1 fm_a = 0; fm_re = 1; #1 fmr = fm_rd; @(posedge clk); #1 fm_re = 0; end endtask
    task wait_done(input integer ch, input integer maxclk); integer c; reg [7:0] s; begin
        c = 0; s = 0; while (!(s[ch*4+1]) && c < maxclk) begin ior(8'hEE, s); c = c + 1; end
        if (c >= maxclk) begin errs = errs + 1; $display("ERROR: timeout waiting for channel %0d", ch); end
        repeat (4) @(posedge clk);   // posted write: the 2nd beat of the last access reaches the SDRAM up to 3 clocks after DONE (the read-back by the core goes through the controller, in order)
    end endtask
    task chk(input [255:0] nome, input [63:0] got, input [63:0] exp);
        if (got !== exp) begin errs = errs + 1; $display("ERROR %0s: got %h expected %h", nome, got, exp); end
    endtask
    function [63:0] mw(input integer w); mw = {mdl.mem[2*w+1], mdl.mem[2*w]}; endfunction
    function [63:0] pat(input integer w); pat = {32'hA5A50000 + w[15:0], 32'h12340000 ^ (w[15:0] * 16'h0101)} ^ 64'h0123456789ABCDEF; endfunction
    reg [7:0] st; reg [63:0] exp;
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin mdl.mem[2*i] = pat(i); mdl.mem[2*i+1] = pat(i) >> 32; end
        repeat (4) @(posedge clk); rst = 0;
        wait (init_done); repeat (10) @(posedge clk);
        // ---- 1) channel 0, memory -> memory: 16 words from 0x000 to 0x400 (word 128) ----
        crw(0, 64'h0000); crw(1, 64'h0400); crw(2, 64'h8000_0010);
        wait_done(0, 4000);
        ior(8'hEE, st); chk("status ch0 done without error", st, 8'h02);
        for (i = 0; i < 16; i = i + 1) chk("copy mem->mem", mw(128 + i), pat(i));
        chk("next word intact", mw(144), pat(144));
        chk("inv after mem->mem", ninv, 1);
        iow(8'hEE, 8'h01); ior(8'hEE, st); chk("clears done", st, 8'h00);
        // ---- 2) two simultaneous channels ----
        ninv = 0;
        crw(0, 64'h0000); crw(1, 64'h0800); crw(2, 64'h8000_0020);      // ch0: words 0..31 -> 256..287 (0x800/8=256)
        crw(3, 64'h1000); crw(4, 64'h2000); crw(5, 64'h8000_0020);      // ch1: words 512..543 -> 1024..
        ior(8'hEE, st); chk("both active", st & 8'h11, 8'h11);
        wait_done(0, 8000); wait_done(1, 8000);
        for (i = 0; i < 32; i = i + 1) begin chk("ch0 copy", mw(256 + i), pat(i)); chk("ch1 copy", mw(1024 + i), pat(512 + i)); end
        repeat (4) @(posedge clk); chk("2 inv pulses", ninv, 2);
        iow(8'hEE, 8'h11);
        // ---- 3) memory -> FIFO (mode 1): 4 words from 0x0 ----
        crw(0, 64'h0); crw(2, 64'h8008_0004);
        wait_done(0, 4000);
        for (i = 0; i < 32; i = i + 1) begin
            fm_a = 1; @(posedge clk); #1; fmrd; exp = pat(i / 8) >> (8 * (i % 8));
            chk("byte no FIFO (little-endian)", fmr, exp[7:0]);
        end
        iow(8'hEE, 8'h01);
        // ---- 4) FIFO -> memory (mode 2): MSX pushes 24 bytes, DMA moves 3 words to 0x6000 ----
        for (i = 0; i < 24; i = i + 1) fmw(i * 7 + 3);
        crw(4, 64'h6000); crw(5, 64'h8010_0003);
        wait_done(1, 4000);
        for (i = 0; i < 3; i = i + 1) begin
            exp = 0; for (t0 = 0; t0 < 8; t0 = t0 + 1) exp = exp | (((i * 8 + t0) * 7 + 3) & 255) << (8 * t0);
            chk("FIFO->mem", mw(3072 + i), exp);
        end
        iow(8'hEE, 8'h10);
        // ---- 4b) mode 2 waits for the FIFO: DMA starts with an empty FIFO, then the MSX pushes ----
        crw(4, 64'h6100); crw(5, 64'h8010_0001);
        repeat (50) @(posedge clk); ior(8'hEE, st); chk("still active waiting for the FIFO", st[4], 1);
        for (i = 0; i < 8; i = i + 1) fmw(8'h10 + i);
        wait_done(1, 4000); chk("FIFO->mem after wait", mw(3104), 64'h1716151413121110); iow(8'hEE, 8'h10);
        // ---- 5) errors ----
        crw(2, 64'h8018_0004); ior(8'hEE, st); chk("mode 3: done+error", st & 8'h07, 8'h06); iow(8'hEE, 8'h01);
        crw(1, 64'h100_0000); crw(2, 64'h8000_0004); ior(8'hEE, st); chk("destination >= 16 MB: error", st & 8'h07, 8'h06); iow(8'hEE, 8'h01);
        crw(1, 64'h400); crw(2, 64'h8000_0000); ior(8'hEE, st); chk("count 0: done without error", st & 8'h07, 8'h02); iow(8'hEE, 8'h01);
        // ---- 6) abort ----
        ninv = 0; crw(0, 64'h0); crw(1, 64'h8000); crw(2, 64'h8000_0100); repeat (200) @(posedge clk);
        ior(8'hEE, st); chk("long one active", st[0], 1); iow(8'hEE, 8'h02); repeat (60) @(posedge clk);
        ior(8'hEE, st); chk("aborted: stopped with done+error", st & 8'h07, 8'h06); chk("inv on abort", ninv, 1);
        iow(8'hEE, 8'h01);
        // ---- 7) IRQ ----
        iow(8'hEF, 8'h01); crw(0, 64'h0); crw(1, 64'h400); crw(2, 64'h8000_0002);
        chk("no irq before", irq, 0); wait_done(0, 4000); chk("irq at the end", irq, 1); ior(8'hEF, st); chk("IE readable", st, 8'h01);
        ior(8'hEE, st); chk("irq bit in status", st[3], 1); iow(8'hEE, 8'h01); chk("irq cleared", irq, 0); iow(8'hEF, 8'h00);
        // ---- 8) new start on an active channel is ignored ----
        crw(0, 64'h0); crw(1, 64'hC000); crw(2, 64'h8000_0040); repeat (5) @(posedge clk); crw(2, 64'h8000_0001);
        wait_done(0, 8000); for (i = 0; i < 64; i = i + 1) chk("long copy intact", mw(6144 + i), pat(i));
        // ---- 9) four simultaneous channels (mem->mem, 24 words each), individual IRQs ----
        repeat (8) @(posedge clk); ninv = 0; iow(8'hEF, 8'h0F);
        for (i = 0; i < 4; i = i + 1) begin crw(3*i + 0, 64'h4000 + i * 64'h200); crw(3*i + 1, 64'h10000 + i * 64'h1000); crw(3*i + 2, 64'h8000_0018); end
        ior(8'hEE, st); chk("ch0 and ch1 active", st & 8'h11, 8'h11); ior(8'hED, st); chk("ch2 and ch3 active", st & 8'h11, 8'h11);
        begin : w4 integer c; reg [7:0] s0, s1; c = 0; s0 = 0; s1 = 0;
            while (!(s0[1] && s0[5] && s1[1] && s1[5]) && c < 4000) begin ior(8'hEE, s0); ior(8'hED, s1); c = c + 1; end
            if (c >= 4000) begin errs = errs + 1; $display("ERROR: timeout 4 channels"); end repeat (4) @(posedge clk); end
        for (i = 0; i < 24; i = i + 1) begin chk("c0", mw(8192 + i), pat(2048 + i)); chk("c1", mw(8192 + 512 + i), pat(2112 + i)); chk("c2", mw(8192 + 1024 + i), pat(2176 + i)); chk("c3", mw(8192 + 1536 + i), pat(2240 + i)); end
        repeat (4) @(posedge clk); chk("4 inv pulses", ninv, 4); chk("irq with 4 completed", irq, 1);
        iow(8'hEE, 8'h11); chk("irq still from ch2/3", irq, 1); iow(8'hED, 8'h11); chk("irq cleared", irq, 0); iow(8'hEF, 8'h00);
        ior(8'hED, st); chk("status2 cleared", st, 8'h00);
        // aborts channel 3 (mode 1 with a full FIFO is not necessary: long mem->mem)
        crw(9, 64'h0); crw(10, 64'h10000); crw(11, 64'h8000_0100); repeat (30) @(posedge clk); iow(8'hED, 8'h20); ior(8'hED, st); chk("ch3 aborted: active=0 done+error", st & 8'h70, 8'h60);
        // ---- 10) DMA reaches the 8 MB: copies 16 words from 0 to 0x700000 (word 0xE0000) and from 0x7FFF80 to 0x1000 ----
        crw(0, 64'h0); crw(1, 64'h70_0000); crw(2, 64'h8000_0010); wait_done(0, 4000); iow(8'hEE, 8'h01);
        for (i = 0; i < 16; i = i + 1) chk("copy to 7 MB", mw(20'hE0000 + i), pat(i));
        chk("alias below 4 MB intact (word 0x20000)", mw(20'h20000), 64'h0);
        crw(0, 64'h7F_FF80); crw(1, 64'h1_0000); crw(2, 64'h8000_0010); wait_done(0, 4000); iow(8'hEE, 8'h01);
        for (i = 0; i < 16; i = i + 1) chk("copy from the top (8 MB)", mw(20'h2000 + i), mw(20'hFFFF0 + i));
        crw(0, 64'h0); crw(1, 64'h100_0000); crw(2, 64'h8000_0001); ior(8'hEE, st); chk("destination = 16 MB: error", st & 8'h07, 8'h06); iow(8'hEE, 8'h01);
        chk("SDRAM violations", mdl.viol, 0);
        if (errs == 0) $display("RESULT: DMA OK"); else $display("RESULT: %0d ERRORS", errs);
        $finish;
    end
    initial begin #50000000; $display("RESULT: TIMEOUT GLOBAL"); $finish; end
endmodule
