// msx_if.v - MSX slot <-> R8064 interface (option A: 4 I/O ports) - registers, 2 FIFOs of 2 KB, synchronizers, data buffer control.
// MSX side (signals already converted to 3.3 V by the 74LVC245): iorq_n, rd_n, wr_n, m1_n, reset_n, a[7:0], d_in[7:0]; outputs: d_out[7:0], u3_oe_n, u3_dir,
//   wait_buf/int_buf/busdir_buf (inputs of the open-collector buffers: 0 = pulls the line low, 1 = high impedance).
// R8064 side (8-bit I/O ports; 1-clock access, no wait): r_port, r_rd, r_wr, r_wdata, r_rdata.
//   F0 DATA (read: MSX->R8064 FIFO; write: R8064->MSX FIFO) | F1 QUEUES (read: b0 has data to read, b1 has space to write) | F2/F3 LEN_L/LEN_H (read: MSX len; write: result len)
//   F4 FLAGS (read: b0 START received, b1 busy; write: b0=1 acknowledges START, b2=1 DONE)
// MSX (base+0..3): DATA, STATUS/CMD, LEN_L, LEN_H.
//   STATUS: b0 has data to read, b1 has space to write, b2 R8064 busy, b3 DONE, b4 IRQ pending, b5 overflow (MSX wrote with FIFO full), b6 underflow (MSX read empty FIFO)
//   CMD:    b0 START, b1 clears FIFOs and errors, b2 enables IRQ, b3 restarts the R8064 (pulse), b7 clears DONE/IRQ
// MSX write: the data is confirmed when the cycle (IORQ, WR, address) stays stable for 3 samples of 100 MHz (it does not wait for WR to rise).
// MSX read: data presented while IORQ+RD+address are stable; the pop occurs when RD ends.
module msx_if #(parameter [7:0] BASE = 8'h40, parameter PORT_BASE = 8'hF0)(
    input  wire       clk, rst_n,
    input  wire       iorq_n, rd_n, wr_n, m1_n, reset_n,
    input  wire [7:0] a, d_in,
    output reg  [7:0] d_out,
    output wire       u3_oe_n, u3_dir,
    output wire       wait_buf, int_buf, busdir_buf,
    input  wire [7:0] r_port, input wire r_rd, r_wr, input wire [7:0] r_wdata, output reg [7:0] r_rdata,
    output reg        r_reset
);
    // ---- synchronizers (2 FF) + data sample
    reg [1:0] s_iorq = 2'b11, s_rd = 2'b11, s_wr = 2'b11, s_m1 = 2'b11, s_rst = 2'b00;
    reg [7:0] s_a0, s_a1, s_d0, s_d1;
    always @(posedge clk) begin
        s_iorq <= {s_iorq[0], iorq_n}; s_rd <= {s_rd[0], rd_n}; s_wr <= {s_wr[0], wr_n}; s_m1 <= {s_m1[0], m1_n}; s_rst <= {s_rst[0], reset_n};
        s_a0 <= a; s_a1 <= s_a0; s_d0 <= d_in; s_d1 <= s_d0;
    end
    wire io_cycle = !s_iorq[1] && s_m1[1];                       // I/O (M1 active + IORQ = interrupt ack: ignored)
    wire match    = (s_a1[7:2] == BASE[7:2]);
    wire [1:0] reg_sel = s_a1[1:0];
    wire rd_raw = io_cycle && match && !s_rd[1];
    wire wr_raw = io_cycle && match && !s_wr[1];
    reg [1:0] rd_cnt = 0, wr_cnt = 0; reg rd_q = 0, wr_q = 0;
    always @(posedge clk) begin
        rd_cnt <= rd_raw ? (rd_cnt == 2'd3 ? 2'd3 : rd_cnt + 1) : 2'd0;
        wr_cnt <= wr_raw ? (wr_cnt == 2'd3 ? 2'd3 : wr_cnt + 1) : 2'd0;
        rd_q <= (rd_cnt == 2'd3); wr_q <= (wr_cnt == 2'd3);
    end
    wire rd_ok = (rd_cnt == 2'd3);                                // stable read
    wire wr_commit = (wr_cnt == 2'd3) && !wr_q;                   // 1 pulse per write cycle
    wire rd_end = rd_q && !rd_ok;                                 // end of read -> pop
    reg [1:0] sel_l;                                               // register of the read cycle in progress (frozen)
    always @(posedge clk) if (rd_raw && rd_cnt < 2'd3) sel_l <= reg_sel;

    // ---- FIFOs
    wire [7:0] fi_q, fo_q; wire fi_empty, fi_full, fo_empty, fo_full; wire [11:0] fi_lvl, fo_lvl;
    reg clr_f;
    wire msx_push = wr_commit && (reg_sel == 2'd0);
    wire msx_pop  = rd_end && (sel_l == 2'd0);
    wire r_pop    = r_rd && (r_port == PORT_BASE + 8'd0);
    wire r_push   = r_wr && (r_port == PORT_BASE + 8'd0);
    wire rst = !rst_n || !s_rst[1];
    fifo2k fi(.clk(clk), .rst(rst), .clr(clr_f), .push(msx_push), .din(s_d1), .pop(r_pop), .dout(fi_q), .empty(fi_empty), .full(fi_full), .level(fi_lvl));
    fifo2k fo(.clk(clk), .rst(rst), .clr(clr_f), .push(r_push), .din(r_wdata), .pop(msx_pop), .dout(fo_q), .empty(fo_empty), .full(fo_full), .level(fo_lvl));

    // ---- registradores
    reg [15:0] len_in, len_out; reg start_f, busy, done, irq_en, irq_p, ovf, unf;
    wire [7:0] status = {1'b0, unf, ovf, irq_p, done, busy, !fi_full, !fo_empty};
    always @(posedge clk) begin
        r_reset <= 0; clr_f <= 0;
        if (rst) begin len_in <= 0; len_out <= 0; start_f <= 0; busy <= 0; done <= 0; irq_en <= 0; irq_p <= 0; ovf <= 0; unf <= 0; end
        else begin
            if (wr_commit) case (reg_sel)
                2'd0: if (fi_full) ovf <= 1;
                2'd1: begin
                    if (s_d1[0]) begin start_f <= 1; busy <= 1; done <= 0; irq_p <= 0; end
                    if (s_d1[1]) begin clr_f <= 1; ovf <= 0; unf <= 0; end
                    irq_en <= s_d1[2];
                    if (s_d1[3]) r_reset <= 1;
                    if (s_d1[7]) begin done <= 0; irq_p <= 0; end
                end
                2'd2: len_in[7:0] <= s_d1;
                2'd3: len_in[15:8] <= s_d1;
            endcase
            if (rd_end && sel_l == 2'd0 && fo_empty) unf <= 1;
            if (r_wr) case (r_port)
                PORT_BASE + 8'd2: len_out[7:0] <= r_wdata;
                PORT_BASE + 8'd3: len_out[15:8] <= r_wdata;
                PORT_BASE + 8'd4: begin
                    if (r_wdata[0]) start_f <= 0;
                    if (r_wdata[2]) begin busy <= 0; done <= 1; if (irq_en) irq_p <= 1; end
                end
                default: ;
            endcase
        end
    end
    always @* begin
        case (r_port)
            PORT_BASE + 8'd0: r_rdata = fi_q;
            PORT_BASE + 8'd1: r_rdata = {6'd0, !fo_full, !fi_empty};
            PORT_BASE + 8'd2: r_rdata = len_in[7:0];
            PORT_BASE + 8'd3: r_rdata = len_in[15:8];
            PORT_BASE + 8'd4: r_rdata = {6'd0, busy, start_f};
            default: r_rdata = 8'h00;
        endcase
    end
    // ---- data to the MSX (never driven outside a stable read)
    always @* begin
        case (sel_l)
            2'd0: d_out = fo_empty ? 8'h00 : fo_q;
            2'd1: d_out = status;
            2'd2: d_out = len_out[7:0];
            default: d_out = len_out[15:8];
        endcase
    end
    assign u3_oe_n    = !rd_ok;
    assign u3_dir     = rd_ok;                 // 1 = FPGA -> MSX
    assign busdir_buf = !rd_ok;                // 0 = pulls BUSDIR low only when delivering data
    assign int_buf    = !(irq_p && irq_en);
    assign wait_buf   = 1'b1;                  // WAIT not used (high impedance)
endmodule
