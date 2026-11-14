// alu64.v - ALU completa (prep + nucleo, combinacional): mesmo contrato da versao monolitica (ref/alu64_v1_monolitica.v).
// F = {S,Z,Y,H,X,PV,N,C}. Premissas de flags: ver comentarios em ref/gen_vectors.py (modelo de referencia).
module alu64(
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire [4:0]  op,
    input  wire [1:0]  sz,
    input  wire [7:0]  fin,
    output wire [63:0] res,
    output wire [7:0]  fout
);
    wire [63:0] xa, yb, yy; wire ci; wire [21:0] ctl0; wire [16:0] ctl = ctl0[16:0];   // alu_core (1 estagio) so conhece as operacoes originais
    alu_prep p(.a(a), .b(b), .op(op), .sz(sz), .fin(fin), .xa(xa), .yb(yb), .yy(yy), .ci(ci), .ctl(ctl0));
    alu_core c(.xa(xa), .yb(yb), .yy(yy), .ci(ci), .ctl(ctl), .sz(sz), .ctl_n(~ctl), .sz_n(~sz), .fin(fin), .res(res), .fout(fout));
endmodule
