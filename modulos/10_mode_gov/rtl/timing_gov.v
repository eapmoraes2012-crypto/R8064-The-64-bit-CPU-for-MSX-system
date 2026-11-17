// timing_gov.v - R8064 timing governor in the Z80 / R800 modes (ROM or DRAM). Holds the ISSUE of the next instruction until the
// original time of the previous one has elapsed. Units: pipeline clock = 57.2727 MHz (3.579545 MHz x 16; REV23).
//   Z80  : 1 T-state = CPT clocks   (16) -> 3,579545 MHz
//   R800 : 1 cycle   = CPT/2 clocks  (8) -> 7.15909 MHz
// CPT = pipeline clocks per Z80 T-state (even). Other clocks: 114.56 MHz -> 32 ; 85.92 MHz -> 24.
// clk_sel (CLK bits of port 3EH) stayed RESERVED: with a single pipeline clock it no longer changes the scale.
// Time of an instruction (original units):
//   Z80  : table T-states + (2-byte M1 ? 2 : 1) * M1_WAIT                    (same in ROM and DRAM)
//   R800 : total DRAM cycles of the table + (ROM mode ? WAIT_ROM : 0) + c_xcyc (dynamic extra: page break, external memory)
//   alternative path ("alt"): false condition / last iteration -> alt_ev shortens the already loaded time
// R800 extras: refresh (REF_CYC cycles every REF_PER cycles) and an 8 us pause between accesses to ports 98H-9BH.
// Native 64-bit mode: go = 1 (no governor).
module timing_gov #(
    parameter ROM_FILE = "gov_rom.mem",
    parameter CPT      = 16,          // pipeline clocks per Z80 T-state (57.2727 MHz / 3.579545 MHz)
    parameter M1_WAIT  = 1,
    parameter WAIT_ROM = 3,
    parameter REF_CYC  = 25,
    parameter REF_PER  = 210
)(
    input  wire        clk, rst,
    input  wire        native64, is_z80, is_rom, clk_sel,
    // candidate instruction (stable before commit; the table is read in 1 clock)
    input  wire [2:0]  c_page,        // 0 principal, 1 CB, 2 ED, 3 DD, 4 FD, 5 DDCB, 6 FDCB
    input  wire [7:0]  c_op,
    input  wire [7:0]  c_port,        // I/O port of the instruction (IN/OUT)
    input  wire [3:0]  c_xcyc,        // dynamic extra cycles of the fetch (emulated CPU units): external memory, page break
    input  wire        c_romw,        // the fetch is made from ROM (in ROM mode applies WAIT_ROM); without a classifier, tie to 1
    input  wire        add_ev,        // late event: data access with extra cycles
    input  wire [4:0]  add_n,         // extra cycles of that access
    output wire        phase,         // parity of the R800 cycle (alignment with the external 3.58 MHz bus)
    input  wire        cv,            // commit: the candidate instruction was issued on this clock
    input  wire        alt_ev,        // false condition / end of repeat of the instruction in progress
    output wire        go,            // 1 = pode emitir
    output wire [12:0] dbg_rem
);
    reg [31:0] rom [0:2047];
    initial $readmemh(ROM_FILE, rom);
    reg [31:0] rw;
    always @(posedge clk) rw <= rom[{c_page, c_op}];
    wire [5:0] z_t = rw[5:0], z_a = rw[11:6], r_t = rw[17:12], r_a = rw[23:18];
    wire m1x2 = rw[24], isio = rw[25];
    // time in original units
    wire [6:0] zadd = m1x2 ? (M1_WAIT * 2) : M1_WAIT;
    wire [6:0] radd = ((is_rom && c_romw) ? WAIT_ROM : 0) + {3'd0, c_xcyc};
    wire [6:0] n_p  = is_z80 ? ({1'b0, z_t} + zadd) : ({1'b0, r_t} + radd);
    wire [6:0] n_a  = is_z80 ? ((z_a == 0) ? n_p : ({1'b0, z_a} + zadd)) : ((r_a == 0) ? n_p : ({1'b0, r_a} + radd));
    wire [6:0] dlt_u = n_p - n_a;
    localparam CPC = CPT / 2;                                  // clocks per R800 cycle
    function [12:0] scale(input [6:0] n, input z);             // n * (clocks por unidade)
        scale = z ? (n * CPT) : (n * CPC);
    endfunction
    // 2nd and 3rd register stages (cut ROM -> adders -> counter): n_p/dlt_u/VDP flag, then time in clocks.
    // Latency candidate -> go/commit: 3 clocks (the core uses an extra decode phase in the governed modes).
    reg [6:0] n_pq, dltq; reg zq;
    reg [12:0] n_clk, d_clk; reg vdp_port;
    always @(posedge clk) begin
        n_pq <= n_p; dltq <= dlt_u; zq <= is_z80;
        vdp_port <= isio && (c_port[7:2] == 6'b100110);   // 98H-9BH
        n_clk <= scale(n_pq, zq);
        d_clk <= scale(dltq, zq);
    end
    // VDP pause (R800 only)
    localparam VDP_CLK = (CPT * 229) / 8;    // 8 us: 458 clocks at 57.27 MHz (916 with CPT=32, 687 with CPT=24)
    reg [10:0] vdp_cnt;
    wire vdp_blk  = !is_z80 && vdp_port && (vdp_cnt < VDP_CLK);
    reg [12:0] rem, dlt; reg [12:0] rfs, rfc; reg rf_pend;
    wire [12:0] ref_per_clk = REF_PER * CPC;   // 210 cycles = 1680 clocks
    wire [12:0] ref_len_clk = REF_CYC * CPC;   // 25 cycles = 200 clocks
    // registered go (takes the rem/VDP comparison off the core issue path); the +1 clock latency is compensated in the counters
    reg av1, av2; reg [4:0] an1; reg [12:0] add_clk;   // data event in 2 stages: ..., then added to the remaining time
    wire go_c = (rem == 0) && (rfs == 0) && !rf_pend && !vdp_blk && !av1 && !av2;
    // R800 cycle phase: toggles every 'unit' (CPC clocks)
    reg [4:0] ph_cnt; reg ph;
    assign phase = ph;
    always @(posedge clk) begin
        if (rst || ph_cnt == CPC - 1) begin ph_cnt <= 0; if (!rst) ph <= ~ph; else ph <= 0; end
        else ph_cnt <= ph_cnt + 5'd1;
    end
    reg go_r;
    assign go = native64 | go_r;
    assign dbg_rem = rem;
    wire commit = cv && go_r && !native64;
    always @(posedge clk) begin
        if (rst || native64) begin go_r <= 0; av1 <= 0; av2 <= 0; add_clk <= 0; rem <= 0; dlt <= 0; rfs <= 0; rfc <= 0; rf_pend <= 0; vdp_cnt <= 11'd1023; end
        else begin
            go_r <= go_c && !commit;
            if (vdp_cnt != 11'd1023) vdp_cnt <= vdp_cnt + 11'd1;
            // refresh (R800)
            if (!is_z80) begin
                if (rfc >= ref_per_clk) rf_pend <= 1'b1; else rfc <= rfc + 13'd1;
                if (rf_pend && rem == 0 && rfs == 0) begin rfs <= ref_len_clk; rf_pend <= 1'b0; rfc <= 0; end
            end else begin rfc <= 0; rf_pend <= 0; end
            if (rfs != 0) rfs <= rfs - 13'd1;
            // data event (2 stages) -> add_clk
            av1 <= add_ev && !is_z80; an1 <= add_n; av2 <= av1; add_clk <= av1 ? scale({2'd0, an1}, 1'b0) : 13'd0;
            // instruction time
            if (commit) begin
                rem <= n_clk - 13'd2; dlt <= d_clk;
                if (!is_z80 && vdp_port) vdp_cnt <= 11'd0;
            end else begin
                rem <= ((alt_ev && rem != 0) ? ((rem > dlt) ? (rem - dlt - 13'd1) : 13'd0) : (rem != 0) ? (rem - 13'd1) : 13'd0)
                       + (av2 ? add_clk : 13'd0);
            end
        end
    end
endmodule
