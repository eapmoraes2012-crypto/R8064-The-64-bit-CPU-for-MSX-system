`timescale 1ns/1ps
// Teste de integracao: Z80 + msx_mem + adaptador + sdram_ctrl + sdram_model. ROM de teste no slot 0 (nao mapeado). +turbo=N  +hex=arquivo
module tb_z80_msx;
  reg clk = 0, rst_n = 0; always #5 clk = ~clk;
  reg [1:0] turbo = 0; integer tv;
  reg [7:0] rom [0:65535];
  wire xm_rd, xm_wr, xio_rd, xio_wr, xio_ack, halt_n, busak_n, m1_n, rfsh_n, ce_o, instr_done, sdram_ok;
  wire [15:0] xm_addr; wire [7:0] xm_wdata, xio_addr, xio_wdata; reg [7:0] xm_rdata, xio_rdata;
  wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o, mdq;
  wire [31:0] dq = s_dq_oe ? s_dq_o : mdq;
  z80_msx_top #(.INIT_CYC(400), .REF_INT(400)) dut(.clk(clk), .rst_n(rst_n), .turbo(turbo), .use_ext(1'b0), .ce_ext(1'b0), .msx_w(1'b0),
    .xm_rd(xm_rd), .xm_wr(xm_wr), .xm_addr(xm_addr), .xm_wdata(xm_wdata), .xm_rdata(xm_rdata),
    .xio_rd(xio_rd), .xio_wr(xio_wr), .xio_ack(xio_ack), .xio_addr(xio_addr), .xio_wdata(xio_wdata), .xio_rdata(xio_rdata), .x_wait_n(1'b1),
    .int_n(1'b1), .nmi_n(1'b1), .busrq_n(1'b1), .halt_n(halt_n), .busak_n(busak_n), .m1_n(m1_n), .rfsh_n(rfsh_n), .ce_o(ce_o), .instr_done(instr_done), .sdram_ok(sdram_ok),
    .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a), .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(dq));
  sdram_model mdl(.clk(clk), .cke(s_cke), .cs_n(s_cs_n), .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm), .ba(s_ba), .a(s_a), .dq_i(dq), .dq_oe(s_dq_oe), .dq_o(mdq));
  always @(xm_addr or xm_rd) xm_rdata = rom[xm_addr];
  initial xio_rdata = 8'hFF;
  reg [7:0] res = 0, tnum = 0; reg done = 0;
  always @(posedge clk) if (xio_wr) begin
    if (xio_addr == 8'hE1) tnum <= xio_wdata;
    if (xio_addr == 8'hE0) begin res <= xio_wdata; done <= 1; end
  end
  integer k; reg [8*200-1:0] fh;
  initial begin
    for (k = 0; k < 65536; k = k + 1) rom[k] = 8'h00;
    if (!$value$plusargs("hex=%s", fh)) fh = "t_msx.hex";
    if (!$value$plusargs("turbo=%d", tv)) tv = 0;
    turbo = tv[1:0];
    $readmemh(fh, rom);
    repeat (8) @(posedge clk); #1 rst_n = 1;
    wait (done);
    repeat (50) @(posedge clk);
    if (res == 8'h01 && mdl.viol == 0) $display("PASS: integracao Z80+MSX+SDRAM (turbo=%0d) tempo=%0t violacoes SDRAM=%0d", tv, $time, mdl.viol);
    else $display("FAIL: resultado=%h teste=%0d violacoes SDRAM=%0d", res, tnum, mdl.viol);
    $finish;
  end
  initial begin #400000000; $display("TIMEOUT (done=%b pc=%h)", done, dut.u_sys.u_z80.u_core.dbg_pc); $finish; end
endmodule
