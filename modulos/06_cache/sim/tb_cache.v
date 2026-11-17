`timescale 1ns/1ps
// 8+8 KB cache testbench: 2 CPU generators (D and I) -> cache8k x2 -> mem_arb -> sdram_ctrl -> sdram_model; shadow memory to check every read.
module cpu_drv #(parameter REGION = 0, parameter CANWRITE = 1)(
    input wire clk, rst,
    output reg req, we, output reg [18:0] addr, output reg [63:0] wd, output reg [7:0] be,
    input wire ready, rvalid, input wire [63:0] rdata);
    integer errs = 0, nrd = 0, nwr = 0, acc_cyc = 0, rv_cyc = 0, cyc = 0, k;
    reg [18:0] qa [0:4095]; reg [63:0] qd [0:4095]; reg [7:0] qb [0:4095]; reg qw [0:4095]; integer qh = 0, qt = 0;
    reg [63:0] ed [0:4095]; integer eh = 0, et = 0;
    reg rand_en = 0; integer g_sets = 8, g_tags = 4, p_wr = 30, p_idle = 10, set_base = 0, seq_en = 0, seq_ptr = 0, seq_len = 256;
    task push(input w, input [18:0] a, input [63:0] d, input [7:0] b);
        begin qa[qt % 4096] = a; qd[qt % 4096] = d; qb[qt % 4096] = b; qw[qt % 4096] = w; qt = qt + 1; end
    endtask
    wire quiet = (qh == qt) && !req && (eh == et) && !rand_en;
    reg [18:0] ga; reg gw; reg [7:0] gb; reg [63:0] gd;
    initial begin req = 0; we = 0; addr = 0; wd = 0; be = 0; end
    always @(posedge clk) begin
        cyc = cyc + 1;
        if (rst) begin req <= 0; end
        else begin
            if (rvalid) begin
                if (eh == et) begin errs = errs + 1; $display("ERROR(%0d): rvalid without pending read t=%0t", REGION, $time); end
                else begin
                    if (rdata !== ed[eh % 4096]) begin errs = errs + 1; if (errs < 10) $display("ERROR(%0d): data %h expected %h t=%0t", REGION, rdata, ed[eh % 4096], $time); end
                    eh = eh + 1; rv_cyc = cyc; nrd = nrd + 1;
                end
            end
            if (!req || ready) begin
                if (req && ready) begin
                    acc_cyc = cyc;
                    if (!we) begin ed[et % 4096] = tb_cache.shadow[addr]; et = et + 1; end
                    else begin for (k = 0; k < 8; k = k + 1) if (be[k]) tb_cache.shadow[addr][k*8 +: 8] = wd[k*8 +: 8]; nwr = nwr + 1; end
                end
                if (qh != qt) begin
                    req <= 1; we <= qw[qh % 4096]; addr <= qa[qh % 4096]; wd <= qd[qh % 4096]; be <= qb[qh % 4096]; qh = qh + 1;
                end else if (rand_en && ($urandom % 100 >= p_idle)) begin
                    if (seq_en) begin ga = {REGION[0], 18'd0} | (seq_ptr % seq_len); seq_ptr = seq_ptr + 1; gw = 0; end
                    else begin
                        ga = 19'd0; ga[18] = REGION[0]; ga[8:2] = (set_base + $urandom % g_sets) & 127; ga[1:0] = $urandom;
                        ga[17:9] = (($urandom % g_tags) * 5 + 1) & 511; gw = CANWRITE && ($urandom % 100 < p_wr);
                    end
                    gb = $urandom; if (gb == 0) gb = 8'hFF; gd = {$urandom, $urandom};
                    req <= 1; we <= gw; addr <= ga; wd <= gd; be <= gb;
                end else req <= 0;
            end
        end
    end
endmodule

module tb_cache;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg inv_d = 0, inv_i = 0;
    reg [63:0] shadow [0:524287];
    wire d_req, d_we, d_ready, d_rvalid; wire [18:0] d_addr; wire [63:0] d_wd, d_rdata; wire [7:0] d_be;
    wire i_req, i_we, i_ready, i_rvalid; wire [18:0] i_addr; wire [63:0] i_wd, i_rdata; wire [7:0] i_be;
    cpu_drv #(.REGION(0), .CANWRITE(1)) dd(clk, rst, d_req, d_we, d_addr, d_wd, d_be, d_ready, d_rvalid, d_rdata);
    cpu_drv #(.REGION(1), .CANWRITE(0)) di(clk, rst, i_req, i_we, i_addr, i_wd, i_be, i_ready, i_rvalid, i_rdata);
    wire dm_req, dm_we, dm_acc, dm_done; wire [18:0] dm_addr; wire [63:0] dm_wd; wire [7:0] dm_be;
    wire im_req, im_we, im_acc, im_done; wire [18:0] im_addr; wire [63:0] im_wd; wire [7:0] im_be;
    wire [63:0] mrd;
    wire [31:0] dh, dmi, dw, dwh, ih, imi, iw, iwh;
    cache8k #(.WR(1)) dc(.clk(clk), .rst(rst), .inv(inv_d), .req(d_req), .we(d_we), .addr(d_addr), .wdata(d_wd), .be(d_be), .ready(d_ready), .rvalid(d_rvalid), .rdata(d_rdata),
        .m_req(dm_req), .m_we(dm_we), .m_addr(dm_addr), .m_wdata(dm_wd), .m_be(dm_be), .m_accept(dm_acc), .m_done(dm_done), .m_rdata(mrd), .st_rd_hit(dh), .st_rd_miss(dmi), .st_wr(dw), .st_wr_hit(dwh));
    cache8k #(.WR(0)) ic(.clk(clk), .rst(rst), .inv(inv_i), .req(i_req), .we(i_we), .addr(i_addr), .wdata(i_wd), .be(i_be), .ready(i_ready), .rvalid(i_rvalid), .rdata(i_rdata),
        .m_req(im_req), .m_we(im_we), .m_addr(im_addr), .m_wdata(im_wd), .m_be(im_be), .m_accept(im_acc), .m_done(im_done), .m_rdata(mrd), .st_rd_hit(ih), .st_rd_miss(imi), .st_wr(iw), .st_wr_hit(iwh));
    wire c_req, c_we, c_ready, c_rvalid, c_wdone, init_done; wire [18:0] c_addr; wire [63:0] c_wdata, c_rdata; wire [7:0] c_be;
    mem_arb arb(.clk(clk), .rst(rst), .d_req(dm_req), .d_we(dm_we), .d_addr(dm_addr), .d_wdata(dm_wd), .d_be(dm_be), .d_accept(dm_acc), .d_done(dm_done),
        .i_req(im_req), .i_we(im_we), .i_addr(im_addr), .i_wdata(im_wd), .i_be(im_be), .i_accept(im_acc), .i_done(im_done), .rdata(mrd),
        .c_req(c_req), .c_we(c_we), .c_addr(c_addr), .c_wdata(c_wdata), .c_be(c_be), .c_ready(c_ready), .c_rvalid(c_rvalid), .c_rdata(c_rdata), .c_wdone(c_wdone));
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o, mdq; wire [31:0] dq = s_dq_oe ? s_dq_o : mdq;
    sdram_ctrl #(.INIT_CYC(2000), .REF_INT(700)) sc(.clk(clk), .rst(rst), .req(c_req), .we(c_we), .addr(c_addr), .wdata(c_wdata), .be(c_be), .ready(c_ready), .rvalid(c_rvalid), .rdata(c_rdata), .wdone(c_wdone),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a), .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(dq));
    sdram_model mdl(.clk(clk), .cke(s_cke), .cs_n(s_cs_n), .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm), .ba(s_ba), .a(s_a), .dq_i(dq), .dq_oe(s_dq_oe), .dq_o(mdq));

    integer a, errs, t0, t1, n, ph;
    reg [63:0] hv;
    task waitq; begin @(negedge clk); while (!(dd.quiet && di.quiet)) @(negedge clk); repeat (3) @(negedge clk); while (!(dd.quiet && di.quiet)) @(negedge clk); end endtask
    task drain; begin waitq; while (dc.wb_cnt != 0 || dc.ds != 0 || arb.busy) @(posedge clk); repeat (3) @(posedge clk); end endtask
    task bk_write(input [18:0] ad, input [63:0] v); begin shadow[ad] = v; mdl.mem[{ad, 1'b0}] = v[31:0]; mdl.mem[{ad, 1'b1}] = v[63:32]; end endtask
    task check_mem(input [255:0] nome); integer bad; begin
        bad = 0;
        for (a = 0; a < 524288; a = a + 1)
            if ({mdl.mem[{a[18:0], 1'b1}], mdl.mem[{a[18:0], 1'b0}]} !== shadow[a]) begin bad = bad + 1; if (bad < 5) $display("  MEM differs at %h: sdram=%h shadow=%h", a, {mdl.mem[{a[18:0], 1'b1}], mdl.mem[{a[18:0], 1'b0}]}, shadow[a]); end
        if (bad) begin errs = errs + 1; $display("FAIL %0s: %0d different words", nome, bad); end else $display("ok   %0s: SDRAM memory == shadow", nome);
    end endtask
    task rep(input [255:0] nome); begin
        if (dd.errs + di.errs) begin errs = errs + 1; $display("FAIL %0s: errors D=%0d I=%0d", nome, dd.errs, di.errs); end else $display("ok   %0s (D: %0d rd %0d wr | I: %0d rd)", nome, dd.nrd, dd.nwr, di.nrd);
    end endtask
    initial begin
        errs = 0;
        for (a = 0; a < 524288; a = a + 1) begin hv = {a[18:0], 13'h1ace, a[18:0], 13'h0bad} ^ (a * 64'h9E3779B97F4A7C15); shadow[a] = hv; mdl.mem[{a[18:0], 1'b0}] = hv[31:0]; mdl.mem[{a[18:0], 1'b1}] = hv[63:32]; end
        repeat (4) @(posedge clk); rst = 0;
        wait (init_done); repeat (3) @(posedge clk);
        // T1: miss and hit latency (D)
        dd.push(0, 19'h00100, 0, 0); waitq; $display("T1 read miss latency (accept->rvalid) D: %0d clocks", dd.rv_cyc - dd.acc_cyc);
        dd.push(0, 19'h00101, 0, 0); waitq; $display("T1 hit latency (same line) D: %0d clock(s)", dd.rv_cyc - dd.acc_cyc);
        di.push(0, 19'h40100, 0, 0); waitq; $display("T1 read miss latency I: %0d clocks", di.rv_cyc - di.acc_cyc);
        rep("T1");
        // T2: hit throughput - sweeps 256 words (2 KB) twice; the 2nd pass must be 1 access/clock
        for (n = 0; n < 256; n = n + 1) dd.push(0, n, 0, 0); waitq;
        dd.push(0, 19'h0, 0, 0); // first item of the 2nd pass
        t0 = dd.cyc; for (n = 1; n < 256; n = n + 1) dd.push(0, n, 0, 0); waitq; t1 = dd.rv_cyc;
        $display("T2 2nd pass of 256 hit reads: %0d clocks (expected ~256)", t1 - t0);
        rep("T2");
        // T3: writes (byte-enable) on a present and an absent line, then read
        dd.push(1, 19'h00005, 64'hAABBCCDD11223344, 8'b00001111); dd.push(0, 19'h00005, 0, 0);
        dd.push(1, 19'h00006, 64'h0123456789ABCDEF, 8'b10000001); dd.push(0, 19'h00006, 0, 0);
        dd.push(1, 19'h20050, 64'hDEADBEEFCAFEF00D, 8'hF0); dd.push(0, 19'h20050, 0, 0);   // write without allocate + read (miss)
        dd.push(1, 19'h20051, 64'h1111111111111111, 8'hFF); dd.push(0, 19'h20051, 0, 0);   // same line now present
        waitq; rep("T3"); drain; check_mem("T3");
        // T4: set conflict (3 addresses, 2 ways) and LRU
        for (n = 0; n < 40; n = n + 1) begin dd.push(0, 19'h00080 | ((n % 3) << 9), 0, 0); end
        dd.push(0, 19'h00080, 0, 0); dd.push(0, 19'h00280, 0, 0); dd.push(0, 19'h00080, 0, 0); dd.push(0, 19'h00480, 0, 0); dd.push(0, 19'h00280, 0, 0);
        waitq; rep("T4");
        // T4b: exact LRU (A B A C A -> 3 misses; then B -> miss)
        n = dc.st_rd_miss;
        dd.push(0, 19'h01490, 0, 0); dd.push(0, 19'h01690, 0, 0); dd.push(0, 19'h01490, 0, 0); dd.push(0, 19'h01890, 0, 0); dd.push(0, 19'h01490, 0, 0); waitq;
        if (dc.st_rd_miss - n != 3) begin errs = errs + 1; $display("FAIL T4b LRU: %0d misses (expected 3)", dc.st_rd_miss - n); end else $display("ok   T4b LRU keeps A (3 misses)");
        n = dc.st_rd_miss; dd.push(0, 19'h01690, 0, 0); waitq;
        if (dc.st_rd_miss - n != 1) begin errs = errs + 1; $display("FAIL T4b LRU: B should have been evicted"); end else $display("ok   T4b LRU evicted B");
        // T5: coherence - external change + inv
        dd.push(0, 19'h00300, 0, 0); waitq; bk_write(19'h00300, 64'h5555AAAA5555AAAA); dd.push(0, 19'h00300, 0, 0); waitq;
        $display("T5 without inv: read returned the old cache value (expected: deliberate coherence error: %0d)", dd.errs);
        dd.errs = 0; dd.eh = dd.et; // discards
        @(posedge clk); inv_d <= 1; @(posedge clk); inv_d <= 0; repeat (200) @(posedge clk);
        dd.push(0, 19'h00300, 0, 0); waitq; if (dd.errs) begin errs = errs + 1; $display("FAIL T5: after inv still the old value"); end else $display("ok   T5 inv returns the new value");
        // T6: simultaneous I-cache and D-cache, random, many conflicts
        dd.set_base = 0; dd.g_sets = 4; dd.g_tags = 5; dd.p_wr = 35; dd.p_idle = 20; di.g_sets = 4; di.g_tags = 4; di.p_idle = 10;
        dd.rand_en = 1; di.rand_en = 1; repeat (60000) @(posedge clk); dd.rand_en = 0; di.rand_en = 0; waitq; rep("T6 random conflicting"); drain; check_mem("T6");
        // T7: random with more sets, heavy writes, no idle
        dd.g_sets = 64; dd.g_tags = 3; dd.p_wr = 50; dd.p_idle = 0; di.g_sets = 128; di.g_tags = 2; di.p_idle = 0;
        dd.rand_en = 1; di.rand_en = 1; repeat (80000) @(posedge clk); dd.rand_en = 0; di.rand_en = 0; waitq; rep("T7 random heavy write"); drain; check_mem("T7");
        // T8: working set that fits (high hit rate)
        dd.g_sets = 32; dd.g_tags = 2; dd.p_wr = 20; dd.p_idle = 0; di.g_sets = 100; di.g_tags = 1; di.p_idle = 0;
        dd.rand_en = 1; di.rand_en = 1; repeat (40000) @(posedge clk); dd.rand_en = 0; di.rand_en = 0; waitq; rep("T8 working set fits"); drain; check_mem("T8");
        $display("Statistics D: rd hit=%0d miss=%0d | wr=%0d hit=%0d", dc.st_rd_hit, dc.st_rd_miss, dc.st_wr, dc.st_wr_hit);
        $display("Statistics I: rd hit=%0d miss=%0d", ic.st_rd_hit, ic.st_rd_miss);
        $display("SDRAM: model timing violations = %0d", mdl.viol);
        if (mdl.viol) errs = errs + 1;
        if (errs == 0) $display("RESULT: ALL TESTS PASSED"); else $display("RESULT: %0d FAILURES", errs);
        $finish;
    end
    initial begin #400000000; $display("TIMEOUT"); $finish; end
endmodule
