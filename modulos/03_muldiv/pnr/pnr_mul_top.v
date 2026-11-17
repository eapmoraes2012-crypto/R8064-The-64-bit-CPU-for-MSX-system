// Wrapper ONLY to measure area/timing of the multiplier (LFSR inputs, output reduced to 1 bit). Not the final design.
module pnr_mul_top(input clk, input din, output dout);
    function [63:0] xs(input [63:0] x); reg [63:0] t; begin t = x ^ (x << 13); t = t ^ (t >> 7); xs = t ^ (t << 17); end endfunction
    reg [63:0] la = 64'h1357_9BDF_0246_8ACE, lb = 64'hFEDC_BA98_7654_3211; reg [63:0] a = 0, b = 0; reg [1:0] sz = 0; reg sg = 0, v = 0;
    always @(posedge clk) begin la <= xs(la) ^ {63'd0, din}; lb <= xs(lb); a <= la; b <= lb; sz <= lb[9:8]; sg <= lb[20]; v <= lb[30]; end
    wire rdy, ov; wire [127:0] p;
    mul_unit u(.clk(clk), .rst(1'b0), .in_valid(v), .sz(sz), .sgn(sg), .a(a), .b(b), .ready(rdy), .out_valid(ov), .prod(p));
    reg pp = 0; always @(posedge clk) pp <= ^p ^ ov ^ rdy;
    assign dout = pp;
endmodule
