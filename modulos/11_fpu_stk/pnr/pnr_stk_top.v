// Measurement wrapper (fpu_stk) - commands from LFSR, output = parity. Not the final design.
module pnr_stk_top(input wire clk, input wire din, output wire dout);
    reg [3:0] rc = 0; reg [63:0] l = 64'h1; reg [63:0] m = 64'hACE1;
    always @(posedge clk) begin l <= {l[62:0], l[63]^l[62]^l[60]^l[59]^din}; m <= {m[62:0], m[63]^m[61]^m[60]^m[58]}; end
    always @(posedge clk) if (rc != 15) rc <= rc + 1;
    wire [79:0] ra, rb; wire [1:0] ta, tb; wire [15:0] cw, sw, tw; wire [3:0] fx; wire es, busy;
    fpu_stk u(.clk(clk), .rst(rc != 15), .go(l[0]), .cmd(l[4:1]), .idx(l[7:5]), .wdata({m[15:0], l}), .flags_in(l[13:8]), .ra_idx(m[18:16]), .rb_idx(m[21:19]),
              .ra(ra), .rb(rb), .tag_a(ta), .tag_b(tb), .cw(cw), .sw(sw), .tw(tw), .fxam(fx), .es(es), .busy(busy));
    reg p; always @(posedge clk) p <= ^{ra, rb, ta, tb, cw, sw, tw, fx, es, busy};
    assign dout = p;
endmodule
