// div_unit.v - divisor iterativo de 1 bit por clock (restaurador), sem sinal e com sinal.
//   Dividendo de 2*sz bits = {hi,lo}, divisor d de sz bits; sz: 0=8,1=16,2=32,3=64. Quociente e resto de sz bits.
//   Sem sinal: ocupa sz+2 clocks (LOAD + sz iteracoes + DONE). Com sinal: sz+4 (PRE + LOAD + sz + POST + DONE).
//   err = 1 em divisao por zero ou quociente fora da faixa (estouro). Em erro, termina mais cedo.
//   Com sinal: quociente truncado para zero; resto com o sinal do dividendo.
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
    localparam IDLE = 3'd0, PRE = 3'd1, LOAD = 3'd2, ITER = 3'd3, POST = 3'd4, DONE = 3'd5;
    reg [2:0] st; reg [1:0] s; reg sg; reg [63:0] rh, rl, rd; reg sd, sv; reg [6:0] cnt; reg rlz;
    reg [64:0] rem; reg [63:0] ql;
    assign busy = (st != IDLE) && (st != DONE);
    assign done = (st == DONE);
    function [63:0] mask(input [1:0] z); mask = (z == 2'd0) ? 64'hFF : (z == 2'd1) ? 64'hFFFF : (z == 2'd2) ? 64'hFFFF_FFFF : 64'hFFFF_FFFF_FFFF_FFFF; endfunction
    function [6:0] nbits(input [1:0] z); nbits = (z == 2'd0) ? 7'd8 : (z == 2'd1) ? 7'd16 : (z == 2'd2) ? 7'd32 : 7'd64; endfunction
    wire [63:0] M = mask(s);
    wire        msb_lo = (s == 2'd0) ? ql[7] : (s == 2'd1) ? ql[15] : (s == 2'd2) ? ql[31] : ql[63];
    wire [64:0] nr   = {rem[63:0], msb_lo};
    // REV44: um unico subtrator de 66 bits serve a iteracao e a checagem de estouro do LOAD (rh >= rd); antes eram 2 comparadores + 1 subtrator
    wire [65:0] dif  = ((st == LOAD) ? {2'b00, rh} : {1'b0, nr}) - {2'b00, rd};
    wire        ge   = ~dif[65];
    wire [64:0] rem_n = ge ? dif[64:0] : nr;
    wire [63:0] ql_n  = ((ql << 1) | {63'd0, ge}) & M;
    // PRE: valor absoluto
    wire        top_hi = (s == 2'd0) ? rh[7] : (s == 2'd1) ? rh[15] : (s == 2'd2) ? rh[31] : rh[63];
    wire        top_d  = (s == 2'd0) ? rd[7] : (s == 2'd1) ? rd[15] : (s == 2'd2) ? rd[31] : rd[63];
    wire [63:0] lo_neg = (~rl + 64'd1) & M;
    wire [63:0] hi_neg = (~rh + {63'd0, rlz}) & M;
    wire [63:0] d_neg  = (~rd + 64'd1) & M;
    // POST
    wire        qneg = sd ^ sv;
    wire [63:0] half = (s == 2'd0) ? 64'h80 : (s == 2'd1) ? 64'h8000 : (s == 2'd2) ? 64'h8000_0000 : 64'h8000_0000_0000_0000;
    wire        qtop = (s == 2'd0) ? ql[7] : (s == 2'd1) ? ql[15] : (s == 2'd2) ? ql[31] : ql[63];   // ql >= half  <=>  bit alto do tamanho
    wire        qlow = |(ql & (M >> 1));                                                            // ql >  half  <=>  bit alto e algum bit abaixo
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
            PRE: begin
                sd <= top_hi; sv <= top_d;
                if (top_hi) begin rl <= lo_neg; rh <= hi_neg; end
                if (top_d) rd <= d_neg;
                st <= LOAD;
            end
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
                if (qbad) begin err <= 1; q <= 0; r <= 0; end
                else begin
                    q <= qneg ? ((~ql + 64'd1) & M) : ql;
                    r <= sd ? ((~rem[63:0] + 64'd1) & M) : rem[63:0];
                end
                st <= DONE;
            end
            default: st <= IDLE;
        endcase
    end
endmodule
