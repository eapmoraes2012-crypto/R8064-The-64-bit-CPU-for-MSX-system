// z80_msx_top.v - Z80 + MSX mem + byte adapter + SDRAM controller (embedded SDRAM pins). Z80 stays in reset until the SDRAM init_done.
module z80_msx_top #(
    parameter [31:0] STEP_BASE = 32'd268435456,
    parameter INIT_CYC = 20000, REF_INT = 400,
    parameter MAP_BITS = 6, MEGA_BITS = 7
)(
    input  wire        clk, rst_n,
    input  wire [1:0]  turbo,
    input  wire        use_ext, ce_ext, msx_w,
    output wire        xm_rd, xm_wr, output wire [15:0] xm_addr, output wire [7:0] xm_wdata, input wire [7:0] xm_rdata,
    output wire        xio_rd, xio_wr, xio_ack, output wire [7:0] xio_addr, output wire [7:0] xio_wdata, input wire [7:0] xio_rdata,
    input  wire        x_wait_n, int_n, nmi_n, busrq_n,
    output wire        halt_n, busak_n, m1_n, rfsh_n, ce_o, instr_done, sdram_ok,
    output wire        s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n,
    output wire [3:0]  s_dqm, output wire [1:0] s_ba, output wire [10:0] s_a,
    output wire [31:0] s_dq_o, output wire s_dq_oe, input wire [31:0] s_dq_i
);
    wire mp_req, mp_we, mp_ack; wire [23:0] mp_addr; wire [7:0] mp_wdata, mp_rdata;
    wire q_req, q_we, q_ready, q_rvalid, q_wdone, init_done; wire [18:0] q_addr; wire [63:0] q_wdata, q_rdata; wire [7:0] q_be;
    assign sdram_ok = init_done;
    z80_msx_sys #(.STEP_BASE(STEP_BASE), .MAP_BITS(MAP_BITS), .MEGA_BITS(MEGA_BITS)) u_sys(.clk(clk), .rst_n(rst_n & init_done), .turbo(turbo), .use_ext(use_ext), .ce_ext(ce_ext), .msx_w(msx_w),
        .mp_req(mp_req), .mp_we(mp_we), .mp_addr(mp_addr), .mp_wdata(mp_wdata), .mp_rdata(mp_rdata), .mp_ack(mp_ack),
        .xm_rd(xm_rd), .xm_wr(xm_wr), .xm_addr(xm_addr), .xm_wdata(xm_wdata), .xm_rdata(xm_rdata),
        .xio_rd(xio_rd), .xio_wr(xio_wr), .xio_ack(xio_ack), .xio_addr(xio_addr), .xio_wdata(xio_wdata), .xio_rdata(xio_rdata), .x_wait_n(x_wait_n),
        .int_n(int_n), .nmi_n(nmi_n), .busrq_n(busrq_n), .halt_n(halt_n), .busak_n(busak_n), .m1_n(m1_n), .rfsh_n(rfsh_n), .ce_o(ce_o), .instr_done(instr_done));
    sdram_byte_if u_bi(.clk(clk), .rst(~rst_n), .req(mp_req), .we(mp_we), .addr(mp_addr), .wdata(mp_wdata), .rdata(mp_rdata), .ack(mp_ack),
        .s_req(q_req), .s_we(q_we), .s_addr(q_addr), .s_wdata(q_wdata), .s_be(q_be), .s_ready(q_ready), .s_rvalid(q_rvalid), .s_rdata(q_rdata), .s_wdone(q_wdone));
    sdram_ctrl #(.INIT_CYC(INIT_CYC), .REF_INT(REF_INT)) u_sd(.clk(clk), .rst(~rst_n), .req(q_req), .we(q_we), .addr(q_addr), .wdata(q_wdata), .be(q_be),
        .ready(q_ready), .rvalid(q_rvalid), .rdata(q_rdata), .wdone(q_wdone), .init_done(init_done),
        .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a), .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(s_dq_i));
endmodule
