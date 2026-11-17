// r8064_slot_if.v - MSX slot cartridge interface by I/O PORTS (no memory access): synchronizes /IORQ, /RD, /WR and A0-A7 to the SoC clock,
// recognizes the I/O cycles on ports 0Bh (status/command), 0Ch (data) and 0Dh (length) and converts them to the FIFO bus (fm_*) of r8064_fifo_if,
// through r8064_slot_dec. Written for the V9968_Cartridge board (Tang Nano 20K + 3 x SN74LVC8T245 + 3 MOSFET), which only connects to the FPGA:
//   A0-A7, D0-D7, /IORQ, /RD, /WR, /RESET (inputs), and WAIT, INT, data bus DIR (outputs; WAIT/INT/BUSDIR go through a MOSFET: 1 = activates the slot line).
// Polarity on the board: data_dir = 1 -> the FPGA drives the bus (MSX read) and the same signal pulls /BUSDIR low; data_dir = 0 -> MSX -> cartridge.
//
// Read (MSX reads the port): on seeing /IORQ and /RD active with address 0Bh..0Dh the block generates ONE fm_re pulse (side effect: DATA pops a byte from the FIFO),
//   captures fm_rd (combinational in the same phase as the pulse) and drives the bus (d_oe = 1, data_dir = 1) until /IORQ or /RD return to 1.
//   Latency: 2 synchronization clocks + 1 = about 52 ns at 57 MHz, well within the Z80 I/O cycle (>= 2 T-states + 1 MSX wait ~ 840 ns).
// Write: the data is sampled 8 clocks (about 140 ns) after the synchronized /WR falls, because some bits are still rising right after the /WR edge
//   (effect observed on real MSX machines with the reference board); generates ONE fm_we pulse per cycle. The Z80 write cycle lasts >= 400 ns.
// WAIT: not used (the state is queried by polling); the output exists and stays at 0 (reserved, e.g. FIFO full).
// INT : irq (fifo_irq, level) -> slot_int (1 = INT active on the slot).
// Outside ports 0Bh..0Dh the block drives neither the bus nor the DIR line (the cycle belongs to another device).
module r8064_slot_if #(parameter P_ST = 8'h0B, parameter P_DT = 8'h0C, parameter P_LN = 8'h0D, parameter WR_DLY = 8)(
    input  wire       clk, rst,
    // slot (asynchronous, already at the 3.3 V level through the converters)
    input  wire       slot_iorq_n, slot_rd_n, slot_wr_n,
    input  wire [7:0] slot_a,
    input  wire [7:0] slot_d_i,
    output wire [7:0] slot_d_o,
    output wire       slot_d_oe,
    output wire       slot_data_dir,
    output wire       slot_wait,
    output wire       slot_int,
    // FIFO side (m_*) of r8064_fifo_if
    output wire       fm_we, fm_re, output wire [1:0] fm_a, output wire [7:0] fm_wd, input wire [7:0] fm_rd,
    input  wire       irq
);
    // 2-FF synchronizers (idle value: inactive)
    reg [1:0] sio = 2'b11, srd = 2'b11, swr = 2'b11;
    reg [7:0] a_s1 = 8'd0, a_s = 8'd0;
    always @(posedge clk) begin
        sio <= {sio[0], slot_iorq_n}; srd <= {srd[0], slot_rd_n}; swr <= {swr[0], slot_wr_n};
        a_s1 <= slot_a; a_s <= a_s1;
    end
    wire iorq = ~sio[1], rd = ~srd[1], wr = ~swr[1];

    // port decoding (combinational over the synchronized address)
    reg [3:0] wc = 4'd0; reg we_p = 1'b0; reg [7:0] d_l = 8'd0; reg drv = 1'b0; reg [7:0] rd_lat = 8'd0;
    wire d_re, d_we; wire [1:0] d_a; wire [7:0] d_wd; wire hit; wire [7:0] d_rdv;
    wire act_rd = iorq & rd & ~wr & hit;
    wire act_wr = iorq & wr & ~rd & hit;
    wire re_p = act_rd & ~drv;                    // one pulse per read cycle
    r8064_slot_dec #(.P_ST(P_ST), .P_DT(P_DT), .P_LN(P_LN)) u_dec(.clk(clk), .rst(rst),
        .io_we(we_p), .io_re(re_p), .io_a(a_s), .io_wd(d_l), .io_rd(d_rdv), .io_hit(hit),
        .fm_we(fm_we), .fm_re(fm_re), .fm_a(fm_a), .fm_wd(fm_wd), .fm_rd(fm_rd));
    always @(posedge clk) begin
        if (rst) begin wc <= 4'd0; we_p <= 1'b0; drv <= 1'b0; end
        else begin
            drv <= act_rd;
            if (re_p) rd_lat <= d_rdv;
            we_p <= 1'b0;
            if (!act_wr) wc <= 4'd0;
            else if (wc < WR_DLY) begin
                wc <= wc + 4'd1;
                if (wc == WR_DLY - 1) begin d_l <= slot_d_i; we_p <= 1'b1; end
            end
        end
    end
    assign slot_d_o      = rd_lat;
    assign slot_d_oe     = drv & act_rd & ~slot_iorq_n & ~slot_rd_n;   // releases the bus at the same instant /RD or /IORQ rise (without waiting for the synchronizer)
    assign slot_data_dir = slot_d_oe;
    assign slot_wait     = 1'b0;
    assign slot_int      = irq;
endmodule
