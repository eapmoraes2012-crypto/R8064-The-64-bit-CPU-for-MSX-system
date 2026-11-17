// r8064_decode.v - R8064 ED page decoder (GENERATED from spreadsheet rev. 5).
// WAS NOT COMPILED OR SIMULATED in the environment where it was generated (no Icarus/Verilator/Yosys).
//
// Latencies (from the cycle in which b2/b3 are stable before the clock edge):
//   +1 clock : id and illegal valid      (ROM_A and ROM_B read in parallel; amb_idx is combinational logic)
//   +2 clocks: control fields valid (control ROM read with the id)
// ATTENTION: these two serial reads may not fit in the D stage of the 7-stage pipeline
// (the spreadsheet cycle model assumes D in 1 clock). Decide between splitting D, or reading the
// control in stage R. See the README.
module r8064_decode #(
    parameter ROM_A_FILE = "rom_ed_a.mem",
    parameter ROM_B_FILE = "rom_ed_b.mem",
    parameter AMB_FILE   = "amb_idx.mem",
    parameter CTRL_FILE  = "ctrl.mem"
)(
    input  wire       clk,
    input  wire [7:0] b2,        // second byte (after the ED prefix)
    input  wire [7:0] b3,        // third byte (only counts on the ambiguous pages)
    output wire [9:0] id,        // instruction number (0 = illegal)
    output wire       illegal,
    output wire [3:0] len,       // instruction bytes
    output wire [4:0] nr,        // data reads (64-bit accesses)
    output wire [4:0] nw,        // data writes
    output wire [1:0] nio,       // acessos de E/S
    output wire [7:0] ex,        // occupancy of the X stage (clocks)
    output wire [1:0] pen_code,  // 0 none, 1 BR_D, 2 BR_X, 3 BR_M
    output wire       has_cond,  // existe variante "condicao falsa"
    output wire       is_z80     // Z80 ED instruction (Z80 mode)
);
    localparam NPAGES = 33;
    localparam PW     = 6;

    reg [11:0] rom_a [0:255];
    reg [7:0]  amb   [0:255];
    reg [9:0]  rom_b [0:NPAGES*256-1];
    reg [31:0] ctrl  [0:511];
    initial begin
        $readmemh(ROM_A_FILE, rom_a);
        $readmemh(AMB_FILE,   amb);
        $readmemh(ROM_B_FILE, rom_b);
        $readmemh(CTRL_FILE,  ctrl);
    end

    // ROM_B page: combinational logic from b2 (256 x PW bits)
    wire [7:0]    amb_w = amb[b2];
    wire [PW-1:0] page  = amb_w[PW-1:0];

    reg [11:0] a_q;
    reg [9:0]  b_q;
    always @(posedge clk) begin
        a_q <= rom_a[b2];
        b_q <= rom_b[{page, b3}];
    end

    assign id      = a_q[10] ? b_q : a_q[9:0];
    assign illegal = (id == 10'd0);

    reg [31:0] c_q;
    always @(posedge clk) c_q <= ctrl[id[8:0]];

    assign len      = c_q[3:0];
    assign nr       = c_q[8:4];
    assign nw       = c_q[13:9];
    assign nio      = c_q[15:14];
    assign ex       = c_q[23:16];
    assign pen_code = c_q[25:24];
    assign has_cond = c_q[26];
    assign is_z80   = c_q[27];
endmodule
