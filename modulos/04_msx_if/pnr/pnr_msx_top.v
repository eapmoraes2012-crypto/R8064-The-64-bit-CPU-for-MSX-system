// Wrapper ONLY to measure area/timing of the MSX interface (LFSR inputs, outputs reduced to 1 bit). Not the final design.
module pnr_msx_top(input clk, input din, output dout);
    reg [63:0] l = 64'h1357_9BDF_0246_8ACE; always @(posedge clk) l <= {l[62:0], l[63] ^ l[62] ^ l[60] ^ l[59] ^ din};
    wire [7:0] d_out; wire u3_oe_n, u3_dir, wait_buf, int_buf, busdir_buf, r_reset; wire [7:0] r_rdata;
    msx_if u(.clk(clk), .rst_n(1'b1), .iorq_n(l[0] | l[5]), .rd_n(l[1] | l[6]), .wr_n(l[2] | l[7]), .m1_n(l[3] | l[8] | l[9]), .reset_n(1'b1 ^ (l[12] & l[13] & l[14] & l[15] & l[16] & l[17])),
        .a({l[40:35], l[21:20]}), .d_in(l[31:24]), .d_out(d_out), .u3_oe_n(u3_oe_n), .u3_dir(u3_dir), .wait_buf(wait_buf), .int_buf(int_buf), .busdir_buf(busdir_buf),
        .r_port({4'hF, l[48:45]}), .r_rd(l[50] & l[51]), .r_wr(l[52] & l[53]), .r_wdata(l[63:56]), .r_rdata(r_rdata), .r_reset(r_reset));
    reg pp = 0; always @(posedge clk) pp <= ^{d_out, u3_oe_n, u3_dir, wait_buf, int_buf, busdir_buf, r_reset, r_rdata};
    assign dout = pp;
endmodule
