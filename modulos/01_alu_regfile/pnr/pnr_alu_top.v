// Invólucro SÓ para medir area/timing da ALU (entradas por LFSR, saida reduzida a 1 bit). Nao e o projeto final.
module pnr_alu_top(input clk, input din, output dout);
    function [63:0] xs(input [63:0] x); reg [63:0] t; begin t = x ^ (x << 13); t = t ^ (t >> 7); xs = t ^ (t << 17); end endfunction
    reg [63:0] la = 64'h1357_9BDF_0246_8ACE, lb = 64'hFEDC_BA98_7654_3211;
    reg [63:0] ar = 0, br = 0; reg [4:0] opr = 0; reg [1:0] szr = 0; reg [7:0] finr = 0;
    always @(posedge clk) begin
        la <= xs(la) ^ {63'd0, din}; lb <= xs(lb);
        ar <= la; br <= lb; opr <= lb[20:16]; szr <= lb[9:8]; finr <= la[15:8];
    end
    wire [63:0] res; wire [7:0] fo;
    alu64 u(.a(ar), .b(br), .op(opr), .sz(szr), .fin(finr), .res(res), .fout(fo));
    reg [63:0] rr = 0; reg [7:0] fr = 0; reg p = 0;
    always @(posedge clk) begin rr <= res; fr <= fo; p <= ^{rr, fr}; end
    assign dout = p;
endmodule
