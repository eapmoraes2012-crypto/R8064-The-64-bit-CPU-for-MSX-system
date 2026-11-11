`timescale 1ns/1ps
// Teste de alu_core_s (2 estagios) contra os mesmos 148.128 vetores do modulo 01. Rodar na pasta 01_alu_regfile\ref (arquivos .mem).
module tb_alu_s;
    localparam NV = 148128;
    reg clk = 0; always #5 clk = ~clk;
    reg [63:0] va [0:NV-1]; reg [63:0] vb [0:NV-1]; reg [15:0] vc [0:NV-1]; reg [63:0] vr [0:NV-1]; reg [7:0] vf [0:NV-1];
    reg [63:0] a, b; reg [4:0] op; reg [1:0] sz; reg [7:0] fin;
    wire [63:0] xa, yb, yy; wire ci; wire [16:0] ctl;
    alu_prep p(.a(a), .b(b), .op(op), .sz(sz), .fin(fin), .xa(xa), .yb(yb), .yy(yy), .ci(ci), .ctl(ctl));
    reg [63:0] xa_r, yb_r, yy_r; reg ci_r; reg [16:0] ctl_r; reg [1:0] sz_r; reg [7:0] fin_r;
    always @(posedge clk) begin xa_r <= xa; yb_r <= yb; yy_r <= yy; ci_r <= ci; ctl_r <= ctl; sz_r <= sz; fin_r <= fin; end
    wire [63:0] res; wire [7:0] fout;
    alu_core_s c(.clk(clk), .en(1'b1), .xa(xa_r), .yb(yb_r), .yy(yy_r), .ci(ci_r), .ctl(ctl_r), .sz(sz_r), .fin(fin_r), .res(res), .fout(fout));
    integer i, e;
    initial begin
        $readmemh("alu_a.mem", va); $readmemh("alu_b.mem", vb); $readmemh("alu_c.mem", vc); $readmemh("alu_ra.mem", vr); $readmemh("alu_rf.mem", vf);
        e = 0;
        for (i = 0; i < NV; i = i + 1) begin
            @(negedge clk); a = va[i]; b = vb[i]; op = vc[i][14:10]; sz = vc[i][9:8]; fin = vc[i][7:0];
            @(posedge clk); @(posedge clk); #1;
            if (res !== vr[i] || fout !== vf[i]) begin e = e + 1; if (e <= 8) $display("ERRO #%0d op=%0d sz=%0d a=%h b=%h fin=%h: res=%h/%h f=%h/%h", i, op, sz, a, b, fin, res, vr[i], fout, vf[i]); end
        end
        if (va[0] === 64'bx) $display("FAIL: .mem nao carregou (rode em 01_alu_regfile\\ref)");
        else if (e == 0) $display("PASS: alu_core_s %0d vetores, 0 erros", NV); else $display("FAIL: %0d erros", e);
        $finish;
    end
endmodule
