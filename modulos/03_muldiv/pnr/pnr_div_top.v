// Invólucro SÓ para medir area/timing do divisor (entradas por LFSR, saida reduzida a 1 bit). Nao e o projeto final.
module pnr_div_top(input clk, input din, output dout);
    function [63:0] xs(input [63:0] x); reg [63:0] t; begin t = x ^ (x << 13); t = t ^ (t >> 7); xs = t ^ (t << 17); end endfunction
    reg [63:0] la = 64'h1357_9BDF_0246_8ACE, lb = 64'hFEDC_BA98_7654_3211, lc = 64'h0F0F_1234_5678_9ABC;
    reg [63:0] h = 0, l = 0, d = 0; reg [1:0] sz = 0; reg sg = 0, st = 0;
    always @(posedge clk) begin la <= xs(la) ^ {63'd0, din}; lb <= xs(lb); lc <= xs(lc); h <= la; l <= lb; d <= lc; sz <= lb[9:8]; sg <= lb[20]; st <= lc[5] & lc[9]; end
    wire busy, done, err; wire [63:0] q, r;
    div_unit u(.clk(clk), .rst(1'b0), .start(st), .sz(sz), .sgn(sg), .hi(h), .lo(l), .d(d), .busy(busy), .done(done), .q(q), .r(r), .err(err));
    reg pp = 0; always @(posedge clk) pp <= ^q ^ ^r ^ busy ^ done ^ err;
    assign dout = pp;
endmodule
