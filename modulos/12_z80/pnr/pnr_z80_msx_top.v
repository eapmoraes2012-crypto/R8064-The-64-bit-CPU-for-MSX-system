// Measurement wrapper of the Z80 + msx_mem + byte adapter + sdram_ctrl set. Inputs from LFSR, outputs reduced by parity. Not the final design.
module pnr_z80_msx_top(input wire clk, input wire din, output wire dout);
  reg [3:0] rc = 0; reg [63:0] l = 64'h1;
  always @(posedge clk) begin l <= {l[62:0], l[63]^l[62]^l[60]^l[59]^din}; if (rc != 15) rc <= rc + 1; end
  wire xm_rd, xm_wr, xio_rd, xio_wr, xio_ack, halt_n, busak_n, m1_n, rfsh_n, ce_o, done, sdram_ok;
  wire [15:0] xm_addr; wire [7:0] xm_wdata, xio_addr, xio_wdata;
  wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o;
  z80_msx_top u(.clk(clk), .rst_n(rc == 15), .turbo(l[1:0]), .use_ext(1'b0), .ce_ext(l[2]), .msx_w(l[3]),
    .xm_rd(xm_rd), .xm_wr(xm_wr), .xm_addr(xm_addr), .xm_wdata(xm_wdata), .xm_rdata(l[15:8]),
    .xio_rd(xio_rd), .xio_wr(xio_wr), .xio_ack(xio_ack), .xio_addr(xio_addr), .xio_wdata(xio_wdata), .xio_rdata(l[23:16]),
    .x_wait_n(l[4]), .int_n(l[5]), .nmi_n(l[6]), .busrq_n(l[7]),
    .halt_n(halt_n), .busak_n(busak_n), .m1_n(m1_n), .rfsh_n(rfsh_n), .ce_o(ce_o), .instr_done(done), .sdram_ok(sdram_ok),
    .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a),
    .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(l[63:32]));
  reg p; always @(posedge clk) p <= ^{xm_rd, xm_wr, xm_addr, xm_wdata, xio_rd, xio_wr, xio_ack, xio_addr, xio_wdata, halt_n, busak_n, m1_n, rfsh_n, ce_o, done, sdram_ok,
    s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dqm, s_ba, s_a, s_dq_o, s_dq_oe};
  assign dout = p;
endmodule
