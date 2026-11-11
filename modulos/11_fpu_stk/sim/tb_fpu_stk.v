`timescale 1ns/1ps
// Teste de fpu_stk contra vet_stk.txt (gerado por fpu_stk_ref.py, modelo Python independente). Rodar na pasta sim.
module tb_fpu_stk;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg go = 0; reg [3:0] cmd = 0; reg [2:0] idx = 0; reg [79:0] wdata = 0; reg [5:0] fl = 0; reg [2:0] rai = 0, rbi = 0;
    wire [79:0] ra, rb; wire [1:0] ta, tb; wire [15:0] cw, sw, tw; wire [3:0] fx; wire es, busy;
    fpu_stk dut(.clk(clk), .rst(rst), .go(go), .cmd(cmd), .idx(idx), .wdata(wdata), .flags_in(fl), .ra_idx(rai), .rb_idx(rbi),
                .ra(ra), .rb(rb), .tag_a(ta), .tag_b(tb), .cw(cw), .sw(sw), .tw(tw), .fxam(fx), .es(es), .busy(busy));
    integer fd, n, e, r;
    reg [3:0] g, c4; reg [3:0] i4, a4, b4;
    reg [79:0] w, era, erb; reg [7:0] f8; reg [3:0] eta, etb, f3, f2, f1, f0; reg [15:0] ecw, esw, etw;
    initial begin
        for (r = 0; r < 8; r = r + 1) dut.st[r] = 80'd0;     // memoria nao inicializada: o modelo parte de zeros
        fd = $fopen("vet_stk.txt", "r"); n = 0; e = 0;
        if (fd == 0) begin $display("FAIL: vet_stk.txt nao encontrado (rode na pasta sim)"); $finish; end
        repeat (3) @(negedge clk); rst = 0;
        while (!$feof(fd)) begin
            r = $fscanf(fd, "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n", g, c4, i4, w, f8, a4, b4, era, erb, eta, etb, ecw, esw, etw, f3, f2, f1, f0);
            if (r >= 18) begin
                @(negedge clk); go = 1; cmd = c4; idx = i4[2:0]; wdata = w; fl = f8[5:0]; rai = a4[2:0]; rbi = b4[2:0];
                @(negedge clk); go = 0; while (busy) @(negedge clk); #1;
                n = n + 1;
                if (ra !== era || rb !== erb || ta !== eta[1:0] || tb !== etb[1:0] || cw !== ecw || sw !== esw || tw !== etw || fx !== {f3[0], f2[0], f1[0], f0[0]}) begin
                    e = e + 1;
                    if (e <= 8) $display("ERRO #%0d cmd=%0d idx=%0d: ra=%h/%h rb=%h/%h ta=%0d/%0d cw=%h/%h sw=%h/%h tw=%h/%h fx=%b/%b%b%b%b", n, c4, i4, ra, era, rb, erb, ta, eta, cw, ecw, sw, esw, tw, etw, fx, f3[0], f2[0], f1[0], f0[0]);
                end
            end
        end
        if (e == 0 && n > 0) $display("PASS: fpu_stk %0d vetores, 0 erros", n); else $display("FAIL: %0d erros em %0d vetores", e, n);
        $finish;
    end
endmodule
