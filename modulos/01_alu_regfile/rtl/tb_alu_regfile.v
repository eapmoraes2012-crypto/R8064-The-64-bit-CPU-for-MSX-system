`timescale 1ns/1ps
// Testbench: ALU (148k vectors, independent Python model), regmap, regmerge and register file.
module tb_alu_regfile;
    localparam NV = 148128;
    reg clk = 0; always #5 clk = ~clk;
    // ---- ALU
    reg [63:0] va [0:NV-1]; reg [63:0] vb [0:NV-1]; reg [15:0] vc [0:NV-1]; reg [63:0] vr [0:NV-1]; reg [7:0] vf [0:NV-1];
    reg [63:0] a, b; reg [4:0] op; reg [1:0] sz; reg [7:0] fin; wire [63:0] res; wire [7:0] fout;
    alu64 dut(.a(a), .b(b), .op(op), .sz(sz), .fin(fin), .res(res), .fout(fout));
    integer i, e_alu, e_map, e_mrg, e_rf;
    // ---- regmap
    reg [7:0] mexp [0:31]; reg [2:0] rr; reg sm, sa; wire [5:0] idx; wire valid;
    regmap rm(.rr(rr), .swap_main(sm), .swap_af(sa), .idx(idx), .valid(valid));
    // ---- regmerge
    reg [63:0] mo [0:4999]; reg [63:0] mn [0:4999]; reg [3:0] mcw [0:4999]; reg [63:0] me [0:4999];
    reg [63:0] old_v, new_v; reg [2:0] wsz; wire [63:0] mout;
    regmerge mg(.old(old_v), .newv(new_v), .wsz(wsz), .out(mout));
    // ---- register file
    reg we; reg [5:0] wa, ra, rb; reg [63:0] wd; wire [63:0] qa, qb;
    regfile64 rf(.clk(clk), .we(we), .waddr(wa), .wdata(wd), .raddr_a(ra), .raddr_b(rb), .rdata_a(qa), .rdata_b(qb));
    reg [63:0] model [0:63]; reg [63:0] exp_a, exp_b; reg [63:0] lf;
    function [63:0] nxt(input [63:0] x); reg [63:0] t; begin t = x ^ (x << 13); t = t ^ (t >> 7); nxt = t ^ (t << 17); end endfunction
    initial begin
        $readmemh("alu_a.mem", va); $readmemh("alu_b.mem", vb); $readmemh("alu_c.mem", vc); $readmemh("alu_ra.mem", vr); $readmemh("alu_rf.mem", vf);
        $readmemh("regmap_exp.mem", mexp); $readmemh("merge_old.mem", mo); $readmemh("merge_new.mem", mn); $readmemh("merge_c.mem", mcw); $readmemh("merge_exp.mem", me);
        e_alu = 0; e_map = 0; e_mrg = 0; e_rf = 0;
        for (i = 0; i < NV; i = i + 1) begin
            a = va[i]; b = vb[i]; op = vc[i][14:10]; sz = vc[i][9:8]; fin = vc[i][7:0]; #1;
            if (res !== vr[i] || fout !== vf[i]) begin
                e_alu = e_alu + 1;
                if (e_alu <= 8) $display("ERROR ALU #%0d op=%0d sz=%0d a=%h b=%h fin=%h: res=%h/%h f=%h/%h", i, op, sz, a, b, fin, res, vr[i], fout, vf[i]);
            end
        end
        for (i = 0; i < 32; i = i + 1) begin
            rr = i[2:0]; sm = i[3]; sa = i[4]; #1;
            if ({valid, idx} !== {mexp[i][6], mexp[i][5:0]} || (!valid && 0)) begin
                if (valid !== mexp[i][6] || (valid && idx !== mexp[i][5:0])) begin e_map = e_map + 1; $display("ERROR regmap i=%0d", i); end
            end
        end
        for (i = 0; i < 5000; i = i + 1) begin
            old_v = mo[i]; new_v = mn[i]; wsz = mcw[i][2:0]; #1;
            if (mout !== me[i]) begin e_mrg = e_mrg + 1; if (e_mrg <= 5) $display("ERROR merge #%0d wsz=%0d", i, wsz); end
        end
        // register file: random writes/reads against the model (synchronous read with write forwarding)
        for (i = 0; i < 64; i = i + 1) model[i] = 64'd0;
        we = 0; wa = 0; ra = 0; rb = 0; wd = 0; lf = 64'h1234_5678_9ABC_DEF1; exp_a = 0; exp_b = 0;
        repeat (3) @(posedge clk);
        for (i = 0; i < 40000; i = i + 1) begin
            lf = nxt(lf);
            we = lf[0]; wa = lf[6:1]; ra = lf[12:7]; rb = lf[18:13]; wd = nxt(lf);
            @(negedge clk);
            // expected values on the next edge: the memory is read-first, but regfile64 forwards the same-clock write
            // (registered bypass wq_d/byp_*): reading the address being written returns the NEW value; otherwise, the stored value.
            exp_a = (we && wa == ra) ? wd : model[ra]; exp_b = (we && wa == rb) ? wd : model[rb];
            @(posedge clk); #1;
            if (we) model[wa] = wd;
            if (qa !== exp_a || qb !== exp_b) begin e_rf = e_rf + 1; if (e_rf <= 5) $display("ERROR regfile i=%0d ra=%0d: %h/%h rb=%0d: %h/%h", i, ra, qa, exp_a, rb, qb, exp_b); end
        end
        $display("ALU: %0d vectors, %0d errors | regmap: %0d errors | regmerge: %0d errors | regfile: %0d errors", NV, e_alu, e_map, e_mrg, e_rf);
        if (e_alu == 0 && e_map == 0 && e_mrg == 0 && e_rf == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
