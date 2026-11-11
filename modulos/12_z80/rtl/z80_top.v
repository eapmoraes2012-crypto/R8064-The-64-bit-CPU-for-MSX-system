// z80_top.v - Z80 independente: clock-enable (normal/turbo) + nucleo. Sinais de barramento ativos em nivel baixo (convencao Z80).
module z80_top #(parameter [31:0] STEP_BASE = 32'd268435456)(
  input  wire        clk,
  input  wire        rst_n,
  input  wire [1:0]  turbo,
  input  wire        use_ext, input wire ce_ext,
  input  wire        msx_w,
  output wire [15:0] a,
  output wire [7:0]  dout,
  input  wire [7:0]  din,
  output wire        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n, halt_n, busak_n,
  input  wire        wait_n, int_n, nmi_n, busrq_n,
  output wire        ce_o,
  output wire        instr_done
);
  wire ce;
  wire mreq, rd, wr, iorq, m1, rfsh, halt, busak;
  z80_ce #(.STEP_BASE(STEP_BASE)) u_ce(.clk(clk), .rst_n(rst_n), .turbo(turbo), .use_ext(use_ext), .ce_ext(ce_ext), .ce(ce));
  z80_core u_core(.clk(clk), .ce(ce), .rst_n(rst_n), .addr(a), .dout(dout), .din(din), .mreq(mreq), .rd(rd), .wr(wr), .iorq(iorq),
    .m1(m1), .rfsh(rfsh), .wait_n(wait_n), .int_n(int_n), .nmi_n(nmi_n), .busrq_n(busrq_n), .msx_w(msx_w),
    .halt(halt), .busak(busak), .bus_oe(), .instr_done(instr_done), .tick());
  assign mreq_n=~mreq; assign iorq_n=~iorq; assign rd_n=~rd; assign wr_n=~wr; assign m1_n=~m1; assign rfsh_n=~rfsh;
  assign halt_n=~halt; assign busak_n=~busak; assign ce_o=ce;
endmodule
