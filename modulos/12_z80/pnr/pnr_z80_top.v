// Z80 measurement wrapper (core + turbo ce). Inputs from LFSR, output = parity. Not the final design.
module pnr_z80_top(input wire clk, input wire din, output wire dout);
  reg [3:0] rc = 0; reg [63:0] l = 64'h1;
  always @(posedge clk) begin l <= {l[62:0], l[63]^l[62]^l[60]^l[59]^din}; if (rc != 15) rc <= rc + 1; end
  wire [15:0] a; wire [7:0] d; wire mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n, halt_n, busak_n, ce_o, done;
  z80_top u(.clk(clk), .rst_n(rc == 15), .turbo(l[1:0]), .use_ext(1'b0), .ce_ext(l[2]), .msx_w(l[3]), .a(a), .dout(d), .din(l[15:8]),
     .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .m1_n(m1_n), .rfsh_n(rfsh_n), .halt_n(halt_n), .busak_n(busak_n),
     .wait_n(l[4]), .int_n(l[5]), .nmi_n(l[6]), .busrq_n(l[7]), .ce_o(ce_o), .instr_done(done));
  reg p; always @(posedge clk) p <= ^{a, d, mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n, halt_n, busak_n, ce_o, done};
  assign dout = p;
endmodule
