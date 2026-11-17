// r8064_slot_dec.v - decoding of the MSX slot I/O ports for the exchange protocol (REV46): 0Bh STATUS/COMMAND, 0Ch DATA, 0Dh LENGTH.
// Converts to the r8064_fifo_if bus (fm_a: 0 DATA, 1 STATUS/CMD, 2 LEN_L, 3 LEN_H). Port 0Dh alternates LEN_L / LEN_H on each access (read or write);
// the pointer returns to LEN_L on reset and on the "clear FIFOs" command (bit 1 of COMMAND). Inputs already synchronized to clk (1-clock pulses; combinational read data).
module r8064_slot_dec #(parameter P_ST = 8'h0B, parameter P_DT = 8'h0C, parameter P_LN = 8'h0D)(
    input  wire       clk, rst,
    input  wire       io_we, io_re, input wire [7:0] io_a, io_wd, output wire [7:0] io_rd, output wire io_hit,
    output wire       fm_we, fm_re, output wire [1:0] fm_a, output wire [7:0] fm_wd, input wire [7:0] fm_rd
);
    reg lp;
    wire is_st = (io_a == P_ST), is_dt = (io_a == P_DT), is_ln = (io_a == P_LN);
    assign io_hit = is_st | is_dt | is_ln;
    assign fm_a   = is_dt ? 2'd0 : is_st ? 2'd1 : {1'b1, lp};
    assign fm_we  = io_we & io_hit;
    assign fm_re  = io_re & io_hit;
    assign fm_wd  = io_wd;
    assign io_rd  = fm_rd;
    always @(posedge clk) begin
        if (rst) lp <= 1'b0;
        else if (io_we && is_st && io_wd[1]) lp <= 1'b0;
        else if ((io_we || io_re) && is_ln) lp <= ~lp;
    end
endmodule
