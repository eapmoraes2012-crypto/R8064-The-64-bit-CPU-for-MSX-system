// fpu_alu P&R wrapper: inputs from LFSR, output = registered parity (not the final design).
module pnr_half_top(input wire clk, input wire din, output wire dout);
    reg [127:0] l = 128'h1; reg [63:0] m = 64'hACE1; reg [3:0] rc = 0; wire rstw = (rc != 15);
    always @(posedge clk) begin if (rc != 15) rc <= rc + 1; l <= {l[126:0], l[127]^l[126]^l[125]^l[120]^din}; m <= {m[62:0], m[63]^m[61]^m[60]^m[58]}; end
    reg st_r = 0; wire busy, done; wire [79:0] res; wire [5:0] fl; wire up; wire [2:0] cc;
    reg start = 0; always @(posedge clk) start <= !busy && l[7] && !rstw;
    fpu_half u(.clk(clk), .rst(rstw), .start(start), .op(l[3:0] % 4'd13), .rc(l[5:4]), .pc(l[7:6]), .a({l[79:0]}), .b({l[127:64], m[15:0]}), .busy(busy), .done(done), .res(res), .flags(fl), .up(up), .cc(cc));
    reg [79:0] res_r; reg [5:0] fl_r; reg up_r, d_r, b_r; reg [2:0] cc_r; always @(posedge clk) begin res_r <= res; fl_r <= fl; up_r <= up; cc_r <= cc; d_r <= done; b_r <= busy; end
    reg p; always @(posedge clk) p <= ^{res_r, fl_r, up_r, cc_r, d_r, b_r};
    assign dout = p;
endmodule
