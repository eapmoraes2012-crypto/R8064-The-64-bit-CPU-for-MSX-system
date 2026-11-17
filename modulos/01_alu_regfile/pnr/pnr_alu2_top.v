// Wrapper ONLY to measure area/timing of the 2-stage ALU (R: alu_prep -> registers; X: alu_core -> registers).
module pnr_alu2_top(input clk, input din, output dout);
    function [63:0] xs(input [63:0] x); reg [63:0] t; begin t = x ^ (x << 13); t = t ^ (t >> 7); xs = t ^ (t << 17); end endfunction
    reg [63:0] la = 64'h1357_9BDF_0246_8ACE, lb = 64'hFEDC_BA98_7654_3211;
    reg [63:0] ar = 0, br = 0; reg [4:0] opr = 0; reg [1:0] szr = 0, sz2 = 0; reg [7:0] finr = 0, fin2 = 0;
    always @(posedge clk) begin
        la <= xs(la) ^ {63'd0, din}; lb <= xs(lb);
        ar <= la; br <= lb; opr <= lb[20:16]; szr <= lb[9:8]; finr <= la[15:8];
    end
    wire [63:0] xa, yb, yy; wire ci; wire [16:0] ctl;
    alu_prep p(.a(ar), .b(br), .op(opr), .sz(szr), .fin(finr), .xa(xa), .yb(yb), .yy(yy), .ci(ci), .ctl(ctl));
    reg [63:0] xa_r = 0, yb_r = 0, yy_r = 0; reg ci_r = 0; reg [16:0] ctl_r = 0;
    always @(posedge clk) begin xa_r <= xa; yb_r <= yb; yy_r <= yy; ci_r <= ci; ctl_r <= ctl; sz2 <= szr; fin2 <= finr; end
    wire [63:0] res; wire [7:0] fo;
    alu_core c(.xa(xa_r), .yb(yb_r), .yy(yy_r), .ci(ci_r), .ctl(ctl_r), .sz(sz2), .fin(fin2), .res(res), .fout(fo));
    reg [63:0] rr = 0; reg [7:0] fr = 0; reg pp = 0;
    always @(posedge clk) begin rr <= res; fr <= fo; pp <= ^{rr, fr}; end
    assign dout = pp;
endmodule
