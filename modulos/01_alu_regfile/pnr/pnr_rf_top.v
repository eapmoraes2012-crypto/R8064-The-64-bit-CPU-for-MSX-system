// Wrapper ONLY to measure the register file (addresses/data from an LFSR). Not the final design.
module pnr_rf_top(input clk, input din, output dout);
    function [63:0] xs(input [63:0] x); reg [63:0] t; begin t = x ^ (x << 13); t = t ^ (t >> 7); xs = t ^ (t << 17); end endfunction
    reg [63:0] l = 64'h0BAD_C0DE_1234_5678; reg we = 0; reg [5:0] wa = 0, ra = 0, rb = 0; reg [63:0] wd = 0;
    always @(posedge clk) begin l <= xs(l) ^ {63'd0, din}; we <= l[0]; wa <= l[6:1]; ra <= l[12:7]; rb <= l[18:13]; wd <= {l[31:0], l[63:32]}; end
    wire [63:0] qa, qb;
    regfile64 u(.clk(clk), .we(we), .waddr(wa), .wdata(wd), .raddr_a(ra), .raddr_b(rb), .rdata_a(qa), .rdata_b(qb));
    reg p = 0; always @(posedge clk) p <= ^(qa ^ qb);
    assign dout = p;
endmodule
