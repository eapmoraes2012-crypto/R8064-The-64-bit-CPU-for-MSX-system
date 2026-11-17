// r8064_board_top.v - bring-up top for the Tang Nano 20K (GW2AR-18, embedded 32-bit SDRAM): clkgen + SoC + SDRAM + button reset.
// The external MSX bus (io_*, fm_*, io_x_*) is NOT yet connected to pins: inputs at 0. Observation outputs on 4 free pins.
// SRC (clock): 0 = board 27 MHz (pin 4) -> 57.375 MHz | 1 = 3.579545 MHz on clk_ext (pin 13, LPLL2_T_in) x16 | 2 = 57.27 MHz on clk_ext (pin 10, GCLKT_6)
//              3 = 14.31818 MHz on clk_ext (e.g. clk14m, pin 80) x4.   Pins per the pin report of a VDP cartridge for Tang Nano 20K (see tangnano20k_*.cst).
module r8064_board_top #(parameter SRC = 0, parameter [3:0] SDR_PSDA = 4'd4, parameter BOOT = 1)(   // BOOT=1: the monitor (monitor_l0..7.hex, 16 KB) is copied from the buffer to SDRAM 0 before the core leaves reset
    input  wire        clk27,        // board crystal (pin 4)
    input  wire        clk_ext,      // external clock (depends on SRC)
    input  wire        btn_rst,      // button (active high, pressed = 1)
    output wire        dbg_init, dbg_lock, dbg_sig, dbg_hb,
    // embedded SDRAM (fixed GW2AR names: the placer places them by itself)
    output wire        O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n,
    output wire [3:0]  O_sdram_dqm,
    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    inout  wire [31:0] IO_sdram_dq
);
    wire clk_in = (SRC == 0) ? clk27 : clk_ext;
    wire clk, clk_sd, locked, rst_pll;
    r8064_clkgen #(.SRC(SRC), .SDR_PSDA(SDR_PSDA)) u_clk(.clk_in(clk_in), .rst_in(1'b0), .clk(clk), .clk_sdram(clk_sd), .locked(locked), .rst(rst_pll));

    // synchronized button
    reg [1:0] bs = 2'b00; always @(posedge clk) bs <= {bs[0], btn_rst};
    wire rst = rst_pll | bs[1];

    wire io_oe, iox_we, iox_re, nat, cs, z8, ro, mb, dbg_s, gcv, fifo_irq, fifo_rst, fbi, fbd, mmu_en, mmu_user, i_fault, d_fault, init_done;
    wire [7:0] io_rd, iox_a, iox_wd, fm_rd, sb_rd, dbg_f; wire [63:0] dbg_pc; wire [2:0] ic, dc;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o;
    r8064_soc #(.BOOT_WORDS(BOOT ? 2048 : 0), .INIT_IMG(BOOT)) u_soc(.clk(clk), .rst(rst), .irq(1'b0),
        .io_we(1'b0), .io_re(1'b0), .io_a(8'd0), .io_wd(8'd0), .io_rd(io_rd), .io_oe(io_oe),
        .io_x_we(iox_we), .io_x_re(iox_re), .io_x_a(iox_a), .io_x_wd(iox_wd), .io_x_rd(8'd0), .port_c(8'd0),
        .fm_we(1'b0), .fm_re(1'b0), .fm_a(2'd0), .fm_wd(8'd0), .fm_rd(fm_rd),
        .sb_we(1'b0), .sb_re(1'b0), .sb_a(14'd0), .sb_wd(8'd0), .sb_rd(sb_rd),
        .fifo_irq(fifo_irq), .fifo_rst(fifo_rst), .native64(nat), .clk_sel(cs), .is_z80(z8), .is_rom(ro), .mode_busy(mb),
        .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_s), .gov_cv(gcv), .fl_busy_i(fbi), .fl_busy_d(fbd),
        .mmu_en(mmu_en), .mmu_user(mmu_user), .i_fault(i_fault), .d_fault(d_fault), .i_cause(ic), .d_cause(dc),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n),
        .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a), .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(IO_sdram_dq));

    assign O_sdram_clk = clk_sd;
    assign O_sdram_cke = s_cke;   assign O_sdram_cs_n = s_cs_n;  assign O_sdram_ras_n = s_ras_n;
    assign O_sdram_cas_n = s_cas_n; assign O_sdram_wen_n = s_we_n;
    assign O_sdram_dqm = s_dqm;   assign O_sdram_addr = s_a;     assign O_sdram_ba = s_ba;
    assign IO_sdram_dq = s_dq_oe ? s_dq_o : 32'bz;

    // observation: keeps the core alive in synthesis and gives a heartbeat
    reg [24:0] hb = 25'd0; always @(posedge clk) hb <= hb + 25'd1;
    reg sig_r = 1'b0;
    always @(posedge clk) sig_r <= dbg_s ^ i_fault ^ d_fault ^ (^dbg_pc[15:0]) ^ (^dbg_f) ^ io_oe ^ iox_we ^ iox_re ^ nat ^ cs ^ z8 ^ ro ^ mb ^ gcv ^ fifo_irq ^ fbi ^ fbd ^ mmu_en ^ mmu_user ^ (^io_rd) ^ (^fm_rd) ^ (^sb_rd) ^ (^iox_a) ^ (^iox_wd) ^ (^ic) ^ (^dc) ^ fifo_rst;
    assign dbg_init = init_done;
    assign dbg_lock = locked;
    assign dbg_sig  = sig_r;
    assign dbg_hb   = hb[24];
endmodule
