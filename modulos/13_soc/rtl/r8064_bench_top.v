// r8064_bench_top.v - TIMING BENCH for the bare Tang Nano 20K (no MSX): clkgen (27 MHz crystal -> 57.375 MHz) + SoC + embedded SDRAM
// + r8064_bench_io (UART to the PC through the board's USB serial, pin 69, 115200 8N1; clock counter driven by the core PC).
// The firmware (modulos/13_soc/bench, image monitor_l0..7.hex) runs every instruction case in a loop, exactly as tb_meas.v does in simulation:
//   per run: the firmware builds the loop at BUILD, writes its address to the bench, arms it (GO) and jumps to it. The bench counts the clocks
//   between the 5th and the 37th arrival of the PC at the loop address (32 loop iterations), stores the count and resets the SoC.
//   Each case takes 2 runs: the loop without the instruction (empty) and with it; clocks/instruction = (T_case - T_empty) * 100 / (32 * copies).
//   After a reset the firmware reads the run number and the result from the bench, prints a line and builds the next run.
// Only the SoC is reset between runs (the bench registers, the PLL and the UART keep running); the KEY1 button (pin 88) restarts everything.
module r8064_bench_top #(parameter [3:0] SDR_PSDA = 4'd4)(
    input  wire        clk27,        // board crystal (pin 4)
    input  wire        btn_rst,      // KEY1 (pin 88), pressed = 1
    output wire        uart_tx,      // pin 69 -> BL616 -> USB serial on the PC
    input  wire        uart_rx,      // pin 70 (not used)
    // embedded SDRAM (fixed GW2AR names)
    output wire        O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n,
    output wire [3:0]  O_sdram_dqm,
    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    inout  wire [31:0] IO_sdram_dq
);
    wire clk, clk_sd, locked, rst_pll;
    r8064_clkgen #(.SRC(0), .SDR_PSDA(SDR_PSDA)) u_clk(.clk_in(clk27), .rst_in(1'b0), .clk(clk), .clk_sdram(clk_sd), .locked(locked), .rst(rst_pll));
    reg [1:0] bs = 2'b00; always @(posedge clk) bs <= {bs[0], btn_rst};
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o;
    r8064_bench #(.BAUD_DIV(498)) u_b(.clk(clk), .rst(rst_pll | bs[1]), .uart_tx(uart_tx),
        .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a),
        .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(IO_sdram_dq));
    assign O_sdram_clk = clk_sd;
    assign O_sdram_cke = s_cke;   assign O_sdram_cs_n = s_cs_n;  assign O_sdram_ras_n = s_ras_n;
    assign O_sdram_cas_n = s_cas_n; assign O_sdram_wen_n = s_we_n;
    assign O_sdram_dqm = s_dqm;   assign O_sdram_addr = s_a;     assign O_sdram_ba = s_ba;
    assign IO_sdram_dq = s_dq_oe ? s_dq_o : 32'bz;
endmodule

// r8064_bench: SoC + bench I/O (no clock generator: the simulation instantiates this module directly).
module r8064_bench #(parameter BAUD_DIV = 498, parameter INIT_CYC = 20000, parameter TMO_BIT = 22)(
    input  wire        clk, rst,
    output wire        uart_tx,
    output wire        s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe,
    output wire [3:0]  s_dqm, output wire [1:0] s_ba, output wire [10:0] s_a, output wire [31:0] s_dq_o, input wire [31:0] s_dq_i
);
    wire soc_rst_req;
    reg  [4:0] rq = 5'd0;                                  // SoC reset pulse after each run (16 clocks)
    always @(posedge clk) if (rst) rq <= 5'd0; else if (soc_rst_req) rq <= 5'd16; else if (rq != 5'd0) rq <= rq - 5'd1;
    wire soc_rst = rst | (rq != 5'd0);

    wire io_oe, iox_we, iox_re, nat, cs, z8, ro, mb, dbg_s, gcv, fbi, fbd, mmu_en, mmu_user, i_fault, d_fault, init_done, fifo_irq, fifo_rst;
    wire [7:0] io_rd, iox_a, iox_wd, iox_rd, fm_rd, sb_rd, dbg_f; wire [63:0] dbg_pc; wire [2:0] ic, dc;
    r8064_soc #(.BOOT_WORDS(2048), .INIT_IMG(1), .INIT_CYC(INIT_CYC)) u_soc(.clk(clk), .rst(soc_rst), .irq(1'b1),
        .io_we(1'b0), .io_re(1'b0), .io_a(8'd0), .io_wd(8'd0), .io_rd(io_rd), .io_oe(io_oe),
        .io_x_we(iox_we), .io_x_re(iox_re), .io_x_a(iox_a), .io_x_wd(iox_wd), .io_x_rd(iox_rd), .port_c(8'd0),
        .fm_we(1'b0), .fm_re(1'b0), .fm_a(2'd0), .fm_wd(8'd0), .fm_rd(fm_rd),
        .sb_we(1'b0), .sb_re(1'b0), .sb_a(14'd0), .sb_wd(8'd0), .sb_rd(sb_rd),
        .fifo_irq(fifo_irq), .fifo_rst(fifo_rst), .native64(nat), .clk_sel(cs), .is_z80(z8), .is_rom(ro), .mode_busy(mb),
        .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_s), .gov_cv(gcv), .fl_busy_i(fbi), .fl_busy_d(fbd),
        .mmu_en(mmu_en), .mmu_user(mmu_user), .i_fault(i_fault), .d_fault(d_fault), .i_cause(ic), .d_cause(dc),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n),
        .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a), .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(s_dq_i));
    r8064_bench_io #(.BAUD_DIV(BAUD_DIV), .TMO_BIT(TMO_BIT)) u_io(.clk(clk), .rst(rst), .we(iox_we), .a(iox_a), .wd(iox_wd), .rd(iox_rd),
        .pc(dbg_pc[31:0]), .soc_rst_req(soc_rst_req), .uart_tx(uart_tx));
endmodule

// r8064_bench_io: I/O ports of the bench (external ports of the SoC, io_x_*):
//   90h  OUT: byte to the UART            IN: b0 = UART busy
//   91h  OUT: loop address, one byte per write, low byte first (4 writes)
//   92h  OUT: GO (arms the counter; data = divider shift: 9 = 32 iterations x 16 copies, 5 = 32 x 1)    IN: run number, low byte
//   9Ah  IN : run number, high byte
//   93h/94h IN: result of the last two runs = (T_last - T_previous) * 100 >> shift, saturated to 0..FFFFh (hundredths of a clock)
//   95h  IN : b0 = one of the last two runs timed out, b1 = T_last < T_previous
//   96h..99h IN/OUT: free scratch bytes kept across the SoC reset (the firmware keeps its OK / DIF counters there)
//   other ports: IN = 5Ah (as tb_meas), OUT ignored (the IN/OUT instructions under test use port 00h)
module r8064_bench_io #(parameter BAUD_DIV = 498, parameter TMO_BIT = 22)(
    input  wire        clk, rst,
    input  wire        we, input wire [7:0] a, input wire [7:0] wd, output reg [7:0] rd,
    input  wire [31:0] pc,
    output reg         soc_rst_req,
    output wire        uart_tx
);
    // ---- UART TX 8N1
    reg [9:0] tsh = 10'h3FF; reg [3:0] tbit = 4'd0; reg [15:0] tdiv = 16'd0; reg tbusy = 1'b0;
    always @(posedge clk) begin
        if (rst) begin tsh <= 10'h3FF; tbit <= 4'd0; tdiv <= 16'd0; tbusy <= 1'b0; end
        else if (!tbusy) begin
            if (we && a == 8'h90) begin tsh <= {1'b1, wd, 1'b0}; tbit <= 4'd0; tdiv <= 16'd0; tbusy <= 1'b1; end
        end else if (tdiv == BAUD_DIV - 1) begin
            tdiv <= 16'd0; tsh <= {1'b1, tsh[9:1]};
            if (tbit == 4'd9) tbusy <= 1'b0; else tbit <= tbit + 4'd1;
        end else tdiv <= tdiv + 16'd1;
    end
    assign uart_tx = tsh[0];

    // ---- measurement
    reg [31:0] lp = 32'd0, ppc = 32'd0, cyc = 32'd0, t0 = 32'd0, tl = 32'd0, tp = 32'd0, tcnt = 32'd0;
    reg [5:0] nit = 6'd0; reg armed = 1'b0; reg [3:0] sh = 4'd9, shl = 4'd9; reg tmo_l = 1'b0, tmo_p = 1'b0; reg [15:0] run = 16'd0;
    reg [7:0] scr [0:3];
    wire hit = armed && (pc == lp) && (ppc != lp);
    always @(posedge clk) begin
        cyc <= cyc + 32'd1; ppc <= pc; soc_rst_req <= 1'b0;
        if (rst) begin armed <= 1'b0; run <= 16'd0; tl <= 32'd0; tp <= 32'd0; tmo_l <= 1'b0; tmo_p <= 1'b0;
                       scr[0] <= 8'd0; scr[1] <= 8'd0; scr[2] <= 8'd0; scr[3] <= 8'd0; end
        else begin
            if (we && a == 8'h91) lp <= {wd, lp[31:8]};
            if (we && a == 8'h92) begin armed <= 1'b1; nit <= 6'd0; tcnt <= 32'd0; sh <= wd[3:0]; end
            if (we && a >= 8'h96 && a <= 8'h99) scr[a[1:0] - 2'd2] <= wd;
            if (armed) begin
                tcnt <= tcnt + 32'd1;
                if (hit) begin nit <= nit + 6'd1; if (nit == 6'd4) t0 <= cyc; end
                if ((hit && nit == 6'd36) || tcnt[TMO_BIT]) begin
                    armed <= 1'b0; soc_rst_req <= 1'b1; run <= run + 16'd1;
                    tp <= tl; tl <= tcnt[TMO_BIT] ? 32'hFFFFFFFF : cyc - t0; tmo_p <= tmo_l; tmo_l <= tcnt[TMO_BIT]; shl <= sh;
                end
            end
        end
    end
    // result, pipelined (read long after the run): (tl - tp) * 100 >> shl, saturated
    reg [31:0] dl; reg neg; reg [39:0] m100; reg [15:0] res;
    always @(posedge clk) begin
        dl <= tl - tp; neg <= (tl < tp);
        m100 <= {dl, 6'd0} + {1'b0, dl, 5'd0} + {4'd0, dl, 2'd0};
        if (neg) res <= 16'd0;
        else if (shl == 4'd5) res <= (|m100[39:21]) ? 16'hFFFF : m100[20:5];
        else res <= (|m100[39:25]) ? 16'hFFFF : m100[24:9];
    end
    always @* begin
        case (a)
            8'h90: rd = {7'd0, tbusy};
            8'h92: rd = run[7:0];
            8'h9A: rd = run[15:8];
            8'h93: rd = res[7:0];
            8'h94: rd = res[15:8];
            8'h95: rd = {6'd0, neg, tmo_l | tmo_p};
            8'h96, 8'h97, 8'h98, 8'h99: rd = scr[a[1:0] - 2'd2];
            default: rd = 8'h5A;
        endcase
    end
endmodule
