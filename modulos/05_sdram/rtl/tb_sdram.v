`timescale 1ns/1ps
// SDRAM controller testbench: traffic generator (64-bit write/read with byte-enable) + SDRAM model with protocol checker + shadow memory.
module tb_sdram;
    parameter INIT_CYC = 2000, REF_INT = 700;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg req = 0, we = 0; reg [18:0] addr = 0; reg [63:0] wdata = 0; reg [7:0] be = 8'hFF;
    wire ready, rvalid, wdone, init_done; wire [63:0] rdata;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o; wire [31:0] mdq;
    wire [31:0] dq = s_dq_oe ? s_dq_o : mdq;
    sdram_ctrl #(.INIT_CYC(INIT_CYC), .REF_INT(REF_INT)) dut(.clk(clk), .rst(rst), .req(req), .we(we), .addr(addr), .wdata(wdata), .be(be), .ready(ready), .rvalid(rvalid), .rdata(rdata), .wdone(wdone),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a), .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(dq));
    sdram_model mdl(.clk(clk), .cke(s_cke), .cs_n(s_cs_n), .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm), .ba(s_ba), .a(s_a), .dq_i(dq), .dq_oe(s_dq_oe), .dq_o(mdq));
    reg acc = 0; always @(posedge clk) acc <= req && ready;
    reg [63:0] shadow [0:524287]; integer mism = 0, nops = 0;
    // statistics: [category 0=hit,1=closed bank,2=conflict][0=read,1=write]
    integer sum [0:5], mn [0:5], mx [0:5], cnt [0:5], refl [0:5];
    integer ii;
    initial for (ii = 0; ii < 6; ii = ii + 1) begin sum[ii] = 0; mn[ii] = 9999; mx[ii] = 0; cnt[ii] = 0; refl[ii] = 0; end
    integer mxref = 0; integer lat, cat, bk, rw_, nref0, k; reg [63:0] rd_v, x, y;
    task access(input w, input [18:0] ad, input [63:0] wd, input [7:0] bev);
        begin
            bk = ad[8:7]; rw_ = ad[18:9];
            cat = dut.open_r[bk] ? ((dut.orow_v[11*bk +: 11] == rw_) ? 0 : 2) : 1;
            nref0 = mdl.nref;
            @(negedge clk); req = 1; we = w; addr = ad; wdata = wd; be = bev; lat = 0;
            @(negedge clk); lat = 1; while (!acc) begin @(negedge clk); lat = lat + 1; end
            req = 0;   // accepted on the previous posedge; lat counts from it
            lat = 1;
            if (w) begin while (!wdone) begin @(negedge clk); lat = lat + 1; end end
            else begin while (!rvalid) begin @(negedge clk); lat = lat + 1; end rd_v = rdata; end
            if (w) begin
                for (k = 0; k < 8; k = k + 1) if (bev[k]) shadow[ad][k*8 +: 8] = wd[k*8 +: 8];
            end else if (rd_v !== shadow[ad]) begin mism = mism + 1; if (mism <= 5) $display("ERROR read ad=%h got=%h expected=%h", ad, rd_v, shadow[ad]); end
            nops = nops + 1;
            if (mdl.nref == nref0) begin
                sum[cat*2 + w] = sum[cat*2 + w] + lat; cnt[cat*2 + w] = cnt[cat*2 + w] + 1;
                if (lat < mn[cat*2 + w]) mn[cat*2 + w] = lat; if (lat > mx[cat*2 + w]) mx[cat*2 + w] = lat;
            end else begin refl[cat*2 + w] = refl[cat*2 + w] + 1; if (lat > mxref) mxref = lat; end
        end
    endtask
    function [63:0] pat(input [18:0] ad, input integer salt); reg [63:0] t; begin t = {ad, 13'd0, ad, 13'd0} ^ (salt * 64'h9E3779B97F4A7C15); t = t ^ (t >> 29); pat = t * 64'hBF58476D1CE4E5B9; end endfunction
    integer i, j, n; reg [18:0] ad;
    initial begin
        for (ii = 0; ii < 524288; ii = ii + 1) shadow[ii] = 64'd0;
        repeat (5) @(posedge clk); #1 rst = 0;
        wait (init_done); repeat (3) @(posedge clk);
        $display("INIT completed at cycle %0d: initialization refreshes=%0d mode programmed=%0d", mdl.cyc, mdl.refs_init, mdl.mode_set);
        // A) sequential: write and read 8192 64-bit words
        for (i = 0; i < 8192; i = i + 1) access(1, i, pat(i, 1), 8'hFF);
        for (i = 0; i < 8192; i = i + 1) access(0, i, 0, 8'hFF);
        // B) byte-enable
        for (i = 0; i < 2000; i = i + 1) begin ad = $urandom % 4096; access(1, ad, {$urandom, $urandom}, $urandom); access(0, ad, 0, 8'hFF); end
        // C) row conflict in the same bank (alternates 2 rows of bank 0)
        for (i = 0; i < 300; i = i + 1) begin access(1, (i[0] ? 19'h200 : 19'h000) + (i % 8), pat(i, 2), 8'hFF); access(0, (i[0] ? 19'h200 : 19'h000) + (i % 8), 0, 8'hFF); end
        // D) 4 interleaved banks (each with its row open)
        for (i = 0; i < 400; i = i + 1) begin access(0, (i % 4) * 128 + 19'h1000 + (i / 4) % 100, 0, 8'hFF); end
        // E) random in 4 MB, 70% read (only reads what was already written or zero)
        for (i = 0; i < 30000; i = i + 1) begin
            ad = $urandom % 524288;
            if (($urandom % 100) < 30) access(1, ad, {$urandom, $urandom}, ($urandom % 3 == 0) ? 8'hFF : $urandom);
            else access(0, ad, 0, 8'hFF);
        end
        // F) idle for 40 us and then accesses (the refresh must have happened by itself)
        repeat (4000) @(posedge clk);
        for (i = 0; i < 50; i = i + 1) access(0, i * 977, 0, 8'hFF);
        // G) final verification sweep: 20000 random words
        for (i = 0; i < 20000; i = i + 1) begin ad = $urandom % 524288; access(0, ad, 0, 8'hFF); end
        repeat (20) @(posedge clk);
        $display("ACCESSES: %0d | data divergences=%0d | model violations=%0d | refreshes=%0d, longest interval between refreshes=%0d clocks | commands ACT=%0d RD=%0d WR=%0d PRE=%0d",
            nops, mism, mdl.viol, mdl.nref, mdl.max_gap, mdl.nact, mdl.nrd, mdl.nwr, mdl.npre);
        $display("LATENCY (clocks from the acceptance clock to rvalid/wdone), with no refresh in between:");
        for (i = 0; i < 6; i = i + 1)
            if (cnt[i] > 0) $display("  %-22s %-8s n=%6d min=%2d avg=%5.2f max=%3d (with refresh: %0d)", (i/2 == 0) ? "open page (hit)" : (i/2 == 1) ? "closed bank" : "other row (conflict)", (i % 2) ? "write" : "read", cnt[i], mn[i], sum[i] * 1.0 / cnt[i], mx[i], refl[i]);
        $display("  pior latencia de um acesso atrasado por refresh: %0d clocks", mxref);
        if (mism == 0 && mdl.viol == 0 && mdl.max_gap <= 800 && mdl.refs_init == 2) $display("PASS"); else $display("FAIL");
        $finish;
    end
    initial begin #400000000; $display("TIMEOUT"); $finish; end
endmodule
