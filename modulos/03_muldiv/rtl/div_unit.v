// div_unit.v - iterative divider, 1 bit per clock (restoring), unsigned and signed.
//   Dividend of 2*sz bits = {hi,lo}, divisor d of sz bits; sz: 0=8,1=16,2=32,3=64. Quotient and remainder of sz bits.
//   Unsigned: takes sz+2 clocks (LOAD + sz iterations + DONE). Signed: sz+7 (PRE, PRE2, PRE3 + LOAD + sz + POST, POST2 + DONE):
//   REV44: ONE single 64-bit negator (before there were 5) serves the 3 input negations and the 2 output ones, one per clock (+3 clocks only on signed division).
//   err = 1 on divide by zero or quotient out of range (overflow). On error, it finishes earlier.
//   Signed: quotient truncated toward zero; remainder with the sign of the dividend.
module div_unit(
    input  wire        clk, rst,
    input  wire        start,
    input  wire [1:0]  sz,
    input  wire        sgn,
    input  wire [63:0] hi, lo, d,
    output wire        busy,
    output wire        done,       // 1 clock
    output reg  [63:0] q, r,
    output reg         err
);
    localparam IDLE = 4'd0, PRE = 4'd1, LOAD = 4'd2, ITER = 4'd3, POST = 4'd4, DONE = 4'd5, PRE2 = 4'd6, PRE3 = 4'd7, POST2 = 4'd8;
    reg [3:0] st; reg [1:0] s; reg sg; reg [63:0] rh, rl, rd; reg sd, sv; reg [6:0] cnt; reg rlz;
    reg [64:0] rem; reg [63:0] ql;
    assign busy = (st != IDLE) && (st != DONE);
    assign done = (st == DONE);
    function [63:0] mask(input [1:0] z); mask = (z == 2'd0) ? 64'hFF : (z == 2'd1) ? 64'hFFFF : (z == 2'd2) ? 64'hFFFF_FFFF : 64'hFFFF_FFFF_FFFF_FFFF; endfunction
    function [6:0] nbits(input [1:0] z); nbits = (z == 2'd0) ? 7'd8 : (z == 2'd1) ? 7'd16 : (z == 2'd2) ? 7'd32 : 7'd64; endfunction
    wire [63:0] M = mask(s);
    wire        msb_lo = (s == 2'd0) ? ql[7] : (s == 2'd1) ? ql[15] : (s == 2'd2) ? ql[31] : ql[63];
    wire [64:0] nr   = {rem[63:0], msb_lo};
    // REV44: a single 66-bit subtractor serves the iteration and the LOAD overflow check (rh >= rd); before there were 2 comparators + 1 subtractor
    wire [65:0] dif  = ((st == LOAD) ? {2'b00, rh} : {1'b0, nr}) - {2'b00, rd};
    wire        ge   = ~dif[65];
    wire [64:0] rem_n = ge ? dif[64:0] : nr;
    wire [63:0] ql_n  = ((ql << 1) | {63'd0, ge}) & M;
    // PRE: absolute value
    wire        top_hi = (s == 2'd0) ? rh[7] : (s == 2'd1) ? rh[15] : (s == 2'd2) ? rh[31] : rh[63];
    wire        top_d  = (s == 2'd0) ? rd[7] : (s == 2'd1) ? rd[15] : (s == 2'd2) ? rd[31] : rd[63];
    // single negator: 2's complement of nin (with carry-in cin; the dividend high part uses rlz = "low was zero")
    wire [63:0] nin  = (st == PRE) ? rl : (st == PRE2) ? rh : (st == PRE3) ? rd : (st == POST) ? ql : rem[63:0];
    wire        ncin = (st == PRE2) ? rlz : 1'b1;
    wire [63:0] nout = (~nin + {63'd0, ncin}) & M;
    // POST
    wire        qneg = sd ^ sv;
    wire [63:0] half = (s == 2'd0) ? 64'h80 : (s == 2'd1) ? 64'h8000 : (s == 2'd2) ? 64'h8000_0000 : 64'h8000_0000_0000_0000;
    wire        qtop = (s == 2'd0) ? ql[7] : (s == 2'd1) ? ql[15] : (s == 2'd2) ? ql[31] : ql[63];   // ql >= half  <=>  bit alto do tamanho
    wire        qlow = |(ql & (M >> 1));                                                            // ql >  half  <=>  high bit and some bit below
    wire        qbad = qtop & (qneg ? qlow : 1'b1);
    always @(posedge clk) begin
        if (rst) begin st <= IDLE; err <= 0; q <= 0; r <= 0; end
        else case (st)
            IDLE, DONE: begin
                if (start) begin
                    s <= sz; sg <= sgn; rh <= hi & mask(sz); rl <= lo & mask(sz); rlz <= ((lo & mask(sz)) == 64'd0); rd <= d & mask(sz); err <= 0;
                    st <= sgn ? PRE : LOAD;
                end else st <= IDLE;
            end
            PRE: begin                       // signs + negates the low part of the dividend
                sd <= top_hi; sv <= top_d;
                if (top_hi) rl <= nout;
                st <= PRE2;
            end
            PRE2: begin if (sd) rh <= nout; st <= PRE3; end      // nega o alto (carry = baixo era zero)
            PRE3: begin if (sv) rd <= nout; st <= LOAD; end      // nega o divisor
            LOAD: begin
                cnt <= nbits(s); rem <= {1'b0, rh}; ql <= rl;
                if (rd == 64'd0 || ge) begin err <= 1; q <= 0; r <= 0; st <= DONE; end
                else st <= ITER;
            end
            ITER: begin
                rem <= rem_n; ql <= ql_n; cnt <= cnt - 1;
                if (cnt == 7'd1) begin
                    if (sg) st <= POST;
                    else begin q <= ql_n; r <= rem_n[63:0]; st <= DONE; end
                end
            end
            POST: begin
                if (qbad) begin err <= 1; q <= 0; r <= 0; st <= DONE; end
                else begin q <= qneg ? nout : ql; st <= POST2; end
            end
            POST2: begin r <= sd ? nout : rem[63:0]; st <= DONE; end
            default: st <= IDLE;
        endcase
    end
endmodule
