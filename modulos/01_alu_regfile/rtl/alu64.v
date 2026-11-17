// alu64.v - complete ALU (prep + core, combinational): same contract as the monolithic version (ref/alu64_v1_monolitica.v).
// F = {S,Z,Y,H,X,PV,N,C}. Flag assumptions: see comments in ref/gen_vectors.py (reference model).
module alu64(
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire [4:0]  op,
    input  wire [1:0]  sz,
    input  wire [7:0]  fin,
    output wire [63:0] res,
    output wire [7:0]  fout
);
    wire [63:0] xa, yb, yy; wire ci; wire [16:0] ctl;
    alu_prep p(.a(a), .b(b), .op(op), .sz(sz), .fin(fin), .xa(xa), .yb(yb), .yy(yy), .ci(ci), .ctl(ctl));
    alu_core c(.xa(xa), .yb(yb), .yy(yy), .ci(ci), .ctl(ctl), .sz(sz), .fin(fin), .res(res), .fout(fout));
endmodule
