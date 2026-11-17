// r8064_fifo_if.v - MSX <-> R8064 FIFO interface through I/O registers (protocol of the "MSX Pinout" tab, section 3).
//
// R8064 side (ports BASE..BASE+4, default BASE = E8h; the old ports F0h-F4h collided with F3h = MSX2+ screen mode and F4h = initialization flag):
//   BASE+0 DATA     : IN = next byte of the MSX->R8064 FIFO | OUT = pushes into the R8064->MSX FIFO
//   BASE+1 STATUS   : IN: b0 has data to read (MSX->R8064 FIFO not empty), b1 has space to write (R8064->MSX FIFO not full)
//   BASE+2 LEN_L    : block length, low byte (shared with the MSX)
//   BASE+3 LEN_H    : high byte
//   BASE+4 FLAGS    : IN: b0 START received, b1 busy, b2 DONE, b3 WINDOW (1 = the 16 KB buffer belongs to the MSX) | OUT: b0=1 clears START; b1 = value of "busy"; b2=1 marks DONE (and returns the window to the MSX)
// MSX side (offset 0..3 = DATA, STATUS/CMD, LEN_L, LEN_H; the base in the MSX slot is chosen outside, in the port decoding):
//   DATA   : IN = next byte of the R8064->MSX FIFO | OUT = pushes into the MSX->R8064 FIFO
//   STATUS : IN: b0 has data to read, b1 has space to write, b2 R8064 busy, b3 DONE, b4 IRQ pending, b5 WINDOW (MSX's), b6 ERROR (FIFO overflow/underflow; cleared by CMD.b1), b7 = 0
//   CMD    : OUT: b0 START (in the same cycle: busy = 1, DONE = 0, WINDOW = 0), b1 clears the FIFOs and the ERROR, b2 enables IRQ, b3 resets the R8064 (pulse; returns the window), b7 clears DONE/IRQ
// WINDOW (REV46): ownership register of the 16 KB buffer (r8064_xbuf). Reset = 1 (MSX). START clears it; the R8064's DONE or R8064 reset return it to 1.
// DMA device port (REV43): d_pop/d_push/d_wd/a_avail/a_q/b_space use the same FIFOs (modes 1 and 2 of r8064_dma).
// The input ports must be read in the SAME phase as the *_re pulse (combinational data); each FIFO has 2048 bytes (1 BSRAM each).
module r8064_fifo_if #(parameter BASE = 8'hE8, parameter AW = 11)(
    input  wire       clk, rst,
    // R8064 side (system I/O bus)
    input  wire       r_we, r_re, input wire [7:0] r_a, r_wd, output reg [7:0] r_rd, output wire r_hit,
    // lado MSX (slot, ja sincronizado ao clk)
    input  wire       m_we, m_re, input wire [1:0] m_a, input wire [7:0] m_wd, output reg [7:0] m_rd,
    output wire       m_irq,        // slot INT line (open collector outside)
    output reg        r8064_rst,    // R8064 restart pulse (CMD.b3)
    output wire       win,          // 1 = the 16 KB buffer belongs to the MSX (WINDOW)
    // DMA device port (the same FIFOs; the DMA only requests d_pop with a_avail and d_push with b_space)
    input  wire       d_pop, d_push, input wire [7:0] d_wd, output wire a_avail, output wire [7:0] a_q, output wire b_space
);
    localparam DEPTH = 1 << AW;
    // BASE must be a multiple of 8 (E8h, F0h...): decoding by 5-bit + 3-bit comparison (no subtractor)
    wire [2:0] off3 = r_a[2:0];
    wire sel = (r_a[7:3] == BASE[7:3]);
    assign r_hit = sel && (off3 < 3'd5);
    wire off0 = sel && off3 == 3'd0, off1 = sel && off3 == 3'd1, off2 = sel && off3 == 3'd2, off3_ = sel && off3 == 3'd3, off4 = sel && off3 == 3'd4;
    // ---- FIFO A: MSX -> R8064 | FIFO B: R8064 -> MSX ----  (occupancy kept by incremental pointers; full/non-empty flags registered)
    reg [7:0] ma [0:DEPTH-1]; reg [7:0] mb [0:DEPTH-1];
    reg [AW:0] wa, ra, wb, rb;     // pointers with an extra bit: empty = equal; full = equal except the extra bit
    reg full_a, nz_a, nz_a_d, full_b, nz_b, nz_b_d;      // *_d: delayed by 1 clock (the memory reads with 1 clock of latency)
    reg [7:0] qa, qb;
    wire clr = m_we && m_a == 2'd1 && m_wd[1];
    wire avail_a = nz_a && nz_a_d;
    wire avail_b = nz_b && nz_b_d;
    wire pop_a  = (r_re && off0 && avail_a) || (d_pop && avail_a);
    wire push_a = m_we && m_a == 2'd0 && !full_a;
    wire push_b = (r_we && off0 && !full_b) || (d_push && !full_b);
    assign a_avail = avail_a; assign a_q = qa; assign b_space = !full_b;
    wire pop_b  = m_re && m_a == 2'd0 && avail_b;
    wire [AW:0] wa_n = push_a ? wa + 1'b1 : wa, ra_n = pop_a ? ra + 1'b1 : ra;
    wire [AW:0] wb_n = push_b ? wb + 1'b1 : wb, rb_n = pop_b ? rb + 1'b1 : rb;
    wire emp_a_n = (wa_n == ra_n), fl_a_n = (wa_n[AW-1:0] == ra_n[AW-1:0]) && (wa_n[AW] != ra_n[AW]);
    wire emp_b_n = (wb_n == rb_n), fl_b_n = (wb_n[AW-1:0] == rb_n[AW-1:0]) && (wb_n[AW] != rb_n[AW]);
    always @(posedge clk) begin
        if (push_a) ma[wa[AW-1:0]] <= m_wd;
        if (push_b) mb[wb[AW-1:0]] <= d_push ? d_wd : r_wd;
        qa <= ma[ra_n[AW-1:0]];
        qb <= mb[rb_n[AW-1:0]];
    end
    always @(posedge clk) begin
        if (rst || clr) begin
            wa <= 0; ra <= 0; wb <= 0; rb <= 0;
            full_a <= 0; nz_a <= 0; nz_a_d <= 0; full_b <= 0; nz_b <= 0; nz_b_d <= 0;
        end else begin
            wa <= wa_n; ra <= ra_n; wb <= wb_n; rb <= rb_n;
            full_a <= fl_a_n; nz_a <= !emp_a_n; nz_a_d <= nz_a;
            full_b <= fl_b_n; nz_b <= !emp_b_n; nz_b_d <= nz_b;
        end
    end
    // ---- registradores compartilhados ----
    reg [7:0] len_l, len_h; reg start_p, busy, done, irq_en, wnd, err;
    wire irq_pend = done && irq_en;
    always @(posedge clk) begin
        if (rst) begin len_l <= 0; len_h <= 0; start_p <= 0; busy <= 0; done <= 0; irq_en <= 0; r8064_rst <= 0; wnd <= 1; end
        else begin
            r8064_rst <= 1'b0;
            if (m_we && m_a == 2'd2) len_l <= m_wd;
            if (r_we && off2) len_l <= r_wd;
            if (m_we && m_a == 2'd3) len_h <= m_wd;
            if (r_we && off3_) len_h <= r_wd;
            if (m_we && m_a == 2'd1) begin
                if (m_wd[0]) begin start_p <= 1'b1; done <= 1'b0; busy <= 1'b1; wnd <= 1'b0; end
                irq_en <= m_wd[2];
                if (m_wd[3]) begin r8064_rst <= 1'b1; wnd <= 1'b1; end
                if (m_wd[7]) done <= 1'b0;
            end
            if (r_we && off4) begin
                if (r_wd[0]) start_p <= 1'b0;
                busy <= r_wd[1];
                if (r_wd[2]) begin done <= 1'b1; busy <= 1'b0; wnd <= 1'b1; end
            end
        end
    end
    // ERROR: overflow (write with FIFO full) or underflow (read with FIFO empty); only CMD.b1 (clears FIFOs) erases it
    wire ovf_a = m_we && m_a == 2'd0 && full_a, ovf_b = r_we && off0 && full_b;
    wire und_a = r_re && off0 && !avail_a, und_b = m_re && m_a == 2'd0 && !avail_b;
    always @(posedge clk) begin
        if (rst || clr) err <= 1'b0;
        else if (ovf_a || ovf_b || und_a || und_b) err <= 1'b1;
    end
    assign win = wnd;
    assign m_irq = irq_pend;
    // ---- reads (combinational) ----
    always @* begin
        case (off3)
            3'd0: r_rd = avail_a ? qa : 8'h00;
            3'd1: r_rd = {6'd0, !full_b, avail_a};
            3'd2: r_rd = len_l;
            3'd3: r_rd = len_h;
            default: r_rd = {4'd0, wnd, done, busy, start_p};
        endcase
        case (m_a)
            2'd0: m_rd = avail_b ? qb : 8'h00;
            2'd1: m_rd = {1'b0, err, wnd, irq_pend, done, busy, !full_a, avail_b};
            2'd2: m_rd = len_l;
            default: m_rd = len_h;
        endcase
    end
endmodule
