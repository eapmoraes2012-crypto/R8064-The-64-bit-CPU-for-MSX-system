// r8064_xbuf.v - 16 KB buffer of the MSX <-> R8064 exchange window (REV46). 8 lanes of 2048 x 8 bits (8 BSRAM), single port per lane.
// Buffer owner (win): win = 1 -> MSX (byte by byte, A[13:0] of page 2) | win = 0 -> R8064 DMA (64-bit words, 1 per clock).
// Ownership is exclusive (half-duplex), so a single port per lane is enough: address and data are multiplexed by win.
// MSX side: the address s_a must stay stable >= 1 clock BEFORE the s_re pulse (the BSRAM read has 1 clock of latency); with win = 0 the read returns FFh and the write is ignored.
// DMA side: d_a/d_wd/d_we are valid only with win = 0; d_q is valid 1 clock after d_a (r8064_dma does this in the E_RWB wait).
// INIT_IMG=1: initial content = monitor image, 8 files <INIT_PFX><lane>.hex (1 byte per line, 2048 lines), copied to the SDRAM at boot (r8064_soc, BOOT_WORDS).
// Initial content (FPGA configuration): signature "R8064", protocol version (1), 0, 0 in the first 8 bytes. The monitor must redo it at start.
module r8064_xbuf #(parameter INIT_IMG = 0, parameter INIT_PFX = "monitor_l")(
    input  wire        clk,
    input  wire        win,
    input  wire        s_we, s_re, input wire [13:0] s_a, input wire [7:0] s_wd, output wire [7:0] s_rd,
    input  wire        d_re, d_we, input wire [10:0] d_a, input wire [63:0] d_wd, output wire [63:0] d_q
);
    reg [2:0] lane_q; always @(posedge clk) lane_q <= s_a[2:0];
    wire [7:0] q [0:7];
    genvar g;
    generate for (g = 0; g < 8; g = g + 1) begin : lane
        reg [7:0] mem [0:2047];
        reg [7:0] qr;
        if (INIT_IMG) begin : img
            // one literal suffix per lane: Gowin EDA does not evaluate a file name built by arithmetic (8'h30 + g) and then leaves
            // the memory empty without any message (the same problem as EX0205 in r8064_clkgen)
            if (g == 0) initial $readmemh({INIT_PFX, "0.hex"}, mem);
            if (g == 1) initial $readmemh({INIT_PFX, "1.hex"}, mem);
            if (g == 2) initial $readmemh({INIT_PFX, "2.hex"}, mem);
            if (g == 3) initial $readmemh({INIT_PFX, "3.hex"}, mem);
            if (g == 4) initial $readmemh({INIT_PFX, "4.hex"}, mem);
            if (g == 5) initial $readmemh({INIT_PFX, "5.hex"}, mem);
            if (g == 6) initial $readmemh({INIT_PFX, "6.hex"}, mem);
            if (g == 7) initial $readmemh({INIT_PFX, "7.hex"}, mem);
        end else begin : sig
        initial begin
            mem[0] = (g == 0) ? 8'h52 : (g == 1) ? 8'h38 : (g == 2) ? 8'h30 : (g == 3) ? 8'h36 : (g == 4) ? 8'h34 : (g == 5) ? 8'h01 : 8'h00;   // 'R','8','0','6','4',1,0,0
        end
        end
        wire [10:0] a  = win ? s_a[13:3] : d_a;
        wire        we = win ? (s_we && s_a[2:0] == g) : d_we;
        wire [7:0]  wd = win ? s_wd : d_wd[8*g +: 8];
        always @(posedge clk) begin
            if (we) mem[a] <= wd;
            qr <= mem[a];
        end
        assign q[g] = qr;
    end endgenerate
    assign s_rd = win ? q[lane_q] : 8'hFF;
    assign d_q  = {q[7], q[6], q[5], q[4], q[3], q[2], q[1], q[0]};
endmodule
