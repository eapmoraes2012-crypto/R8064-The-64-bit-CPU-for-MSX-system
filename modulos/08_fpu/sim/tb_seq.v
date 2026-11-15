`timescale 1ns/1ps
// Testbench do nucleo aritmetico COMPACTO da FPU (fpu_seq.v): le vetores (op rc pc A B res flags up cc) gerados pelo modelo exato em Python e confere bit a bit.
module tb_seq;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg start = 0; reg [3:0] op = 0; reg [1:0] rc = 0, pc = 0; reg [79:0] a = 0, b = 0;
    wire busy, done; wire [79:0] res; wire [5:0] flags; wire up; wire [2:0] cc;
    fpu_seq dut(.clk(clk), .rst(rst), .start(start), .op(op), .rc(rc), .pc(pc), .a(a), .b(b), .busy(busy), .done(done), .res(res), .flags(flags), .up(up), .cc(cc));
    integer fd, n, errs = 0, tot = 0, lat, k, r;
    reg [3:0] vop; reg [3:0] vrc, vpc, vcc; reg [79:0] vA, vB, vR; reg [7:0] vfl; reg vup;
    integer lmin [0:15], lmax [0:15], lsum [0:15], lcnt [0:15], eop [0:15];
    reg [1023:0] fname;
    initial begin
        for (k = 0; k < 16; k = k + 1) begin lmin[k] = 99999; lmax[k] = 0; lsum[k] = 0; lcnt[k] = 0; eop[k] = 0; end
        if (!$value$plusargs("vec=%s", fname)) fname = "vetores.txt";
        fd = $fopen(fname, "r");
        repeat (4) @(posedge clk); rst = 0; repeat (2) @(posedge clk);
        while (!$feof(fd)) begin
            r = $fscanf(fd, "%h %h %h %h %h %h %h %h %h\n", vop, vrc, vpc, vA, vB, vR, vfl, vup, vcc);
            if (r == 9) begin
                @(negedge clk); start = 1; op = vop; rc = vrc[1:0]; pc = vpc[1:0]; a = vA; b = vB;
                @(negedge clk); start = 0; lat = 1;
                while (!done) begin @(negedge clk); lat = lat + 1; end
                tot = tot + 1; lcnt[vop] = lcnt[vop] + 1; lsum[vop] = lsum[vop] + lat; if (lat < lmin[vop]) lmin[vop] = lat; if (lat > lmax[vop]) lmax[vop] = lat;
                if (res !== vR || flags !== vfl[5:0] || up !== vup || cc !== vcc[2:0]) begin
                    errs = errs + 1; eop[vop] = eop[vop] + 1;
                    if (errs <= 12) $display("ERRO op=%0d rc=%0d pc=%0d A=%020x B=%020x: dut res=%020x fl=%02x up=%b cc=%b  esperado res=%020x fl=%02x up=%b cc=%b", vop, vrc, vpc, vA, vB, res, flags, up, cc, vR, vfl, vup, vcc[2:0]);
                end
            end
        end
        $display("vetores: %0d  erros: %0d", tot, errs);
        for (k = 0; k < 13; k = k + 1) if (lcnt[k] > 0) $display("  op %0d: %0d vetores, erros %0d, latencia clocks min/med/max = %0d/%0d/%0d", k, lcnt[k], eop[k], lmin[k], lsum[k] / lcnt[k], lmax[k]);
        if (errs == 0) $display("RESULTADO: TODOS OS VETORES PASSARAM"); else $display("RESULTADO: %0d ERROS", errs);
        $finish;
    end
    initial begin #2000000000; $display("TIMEOUT"); $finish; end
endmodule
