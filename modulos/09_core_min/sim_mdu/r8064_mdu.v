// r8064_mdu.v - iterative multiplication and division unit (MLTUx/MLTSx/DIVUx/DIVSx), 1 bit per clock, single shared 66-bit adder.
// Width W = 8 << d_w (from the last ld_b). Multiplication: A (d_a) * B (b_q) -> 2W-bit product.
// Division: 2W-bit dividend = {h_q, d_a} (only W = 16 and 64 use h_q; W = 8: d_a[15:0]; W = 32: d_a[63:0]) / B -> W-bit quotient in r[W-1:0], remainder in r[2W-1:W].
// inv = division by zero or out-of-range quotient (operands must stay unchanged; the core returns the old value of the destination).
// fl = {S,Z,Y,H,X,PV,N,C}; each operation lasts approximately W + 8 clocks.
module r8064_mdu(
    input  wire clk, rst,
    input  wire ld_b, ld_h, input wire [63:0] d_ld, input wire [1:0] d_w,
    input  wire start, input wire [1:0] op,      // op: 0 MULU, 1 MULS, 2 DIVU, 3 DIVS
    input  wire [63:0] d_a,
    output reg  busy,
    output reg  [127:0] r, output reg [63:0] rhi, output reg [7:0] fl, output reg inv
);
    reg [63:0] b_q, h_q; reg [1:0] w_q;
    always @(posedge clk) begin
        if (ld_b) begin b_q <= d_ld; w_q <= d_w; end
        if (ld_h) h_q <= d_ld;
    end
    // everything that depends on the width W (8/16/32/64) is tabulated by w_q (no 128-bit shifters)
    wire [6:0]  W  = 7'd8 << w_q;
    wire [63:0] mW = (w_q == 2'd0) ? 64'hFF : (w_q == 2'd1) ? 64'hFFFF : (w_q == 2'd2) ? 64'hFFFF_FFFF : 64'hFFFF_FFFF_FFFF_FFFF;
    wire [127:0] m2 = (w_q == 2'd0) ? 128'hFFFF : (w_q == 2'd1) ? 128'hFFFF_FFFF : (w_q == 2'd2) ? 128'hFFFF_FFFF_FFFF_FFFF : {128{1'b1}};   // mascara de 2W bits
    function bitw(input [63:0] x, input [1:0] w); bitw = (w == 2'd0) ? x[7] : (w == 2'd1) ? x[15] : (w == 2'd2) ? x[31] : x[63]; endfunction   // bit W-1
    reg [3:0] st; reg [6:0] cnt;
    reg [63:0] rA, rH, rB, rQ, rR; reg aneg, bneg, sg, dv, c;
    // single adder: s = x + y + ci (66 bits)
    reg [65:0] ax, ay; reg aci; wire [65:0] asum = ax + ay + {65'd0, aci};
    localparam IDLE=0, ABSA0=1, ABSA1=2, ABSB=3, PRE=4, LOOPM=5, MFIN=6, NEGP0=7, NEGP1=8, LOOPD=9, QFIX=10, NEGQ=11, NEGR=12, FIN=13;
    always @* begin
        ax = 66'd0; ay = 66'd0; aci = 1'b0;
        case (st)
            ABSA0: begin ax = {2'b0, ~rA}; aci = 1'b1; end
            ABSA1: begin ax = {2'b0, ~rH}; aci = c; end
            ABSB:  begin ax = {2'b0, ~rB}; aci = 1'b1; end
            LOOPM: begin ax = {2'b0, rH}; ay = rQ[0] ? {2'b0, rA} : 66'd0; end
            NEGP0: begin ax = {2'b0, ~r[63:0]}; aci = 1'b1; end
            NEGP1: begin ax = {2'b0, ~r[127:64]}; aci = c; end
            LOOPD: begin ax = {1'b0, rR, bitw(rQ, w_q)}; ay = ~{2'b0, rB}; aci = 1'b1; end   // t - rB (66 bits)
            NEGQ:  begin ax = {2'b0, ~rQ}; aci = 1'b1; end
            NEGR:  begin ax = {2'b0, ~rR}; aci = 1'b1; end
            default: ;
        endcase
    end
    // sign and extension
    function [63:0] sx(input [63:0] x, input [1:0] w); sx = bitw(x, w) ? (x | ~mW) : (x & mW); endfunction
    // dividend of 2W bits: W=8: d_a[15:0] | W=16: {h_q[15:0], d_a[15:0]} | W=32: d_a | W=64: {h_q, d_a}
    wire [127:0] Dr = (w_q == 2'd0) ? {112'd0, d_a[15:0]} : (w_q == 2'd1) ? {96'd0, h_q[15:0], d_a[15:0]} : (w_q == 2'd2) ? {64'd0, d_a} : {h_q, d_a};
    wire dsg = (w_q == 2'd0) ? Dr[15] : (w_q == 2'd1) ? Dr[31] : (w_q == 2'd2) ? Dr[63] : Dr[127];      // sign of the dividend (bit 2W-1)
    wire [127:0] Ds = (op[0] && dsg) ? (Dr | ~m2) : Dr;
    wire sa_m = bitw(d_a, w_q), sb = bitw(b_q, w_q);
    wire [63:0] rem0 = (w_q == 2'd0) ? {56'd0, rA[15:8]} : (w_q == 2'd1) ? {48'd0, rA[31:16]} : (w_q == 2'd2) ? {32'd0, rA[63:32]} : rH;   // ({rH,rA} >> W) & mW
    wire [63:0] msb = (w_q == 2'd0) ? 64'h80 : (w_q == 2'd1) ? 64'h8000 : (w_q == 2'd2) ? 64'h8000_0000 : 64'h8000_0000_0000_0000;      // 2^(W-1)
    wire [63:0] lim = (aneg ^ bneg) ? msb : (msb - 64'd1);
    wire [127:0] r2 = r & m2;
    wire [63:0] hi2 = (w_q == 2'd0) ? {56'd0, r2[15:8]} : (w_q == 2'd1) ? {48'd0, r2[31:16]} : (w_q == 2'd2) ? {32'd0, r2[63:32]} : r2[127:64];
    wire [63:0] lo2 = r2[63:0] & mW;
    wire ovf = sg ? (hi2 != (bitw(lo2, w_q) ? mW : 64'd0)) : (hi2 != 64'd0);
    wire [63:0] qm = rQ & mW, rm = rR & mW;
    wire [127:0] qr = (w_q == 2'd0) ? {112'd0, rm[7:0], qm[7:0]} : (w_q == 2'd1) ? {96'd0, rm[15:0], qm[15:0]} : (w_q == 2'd2) ? {64'd0, rm[31:0], qm[31:0]} : {rm, qm};
    always @(posedge clk) begin
        if (rst) begin st <= IDLE; busy <= 1'b0; inv <= 1'b0; end
        else case (st)
            IDLE: if (start) begin
                busy <= 1'b1; inv <= 1'b0; sg <= op[0]; dv <= op[1];
                if (op[1]) begin rA <= Ds[63:0]; rH <= Ds[127:64]; aneg <= op[0] && dsg; end
                else begin rA <= op[0] ? sx(d_a, w_q) : (d_a & mW); rH <= 64'd0; aneg <= op[0] && sa_m; end
                rB <= op[0] ? sx(b_q, w_q) : (b_q & mW); bneg <= op[0] && sb; st <= ABSA0;
            end
            ABSA0: begin if (aneg) begin rA <= asum[63:0]; c <= asum[64]; end else c <= 1'b0; st <= ABSA1; end
            ABSA1: begin if (aneg && dv) rH <= asum[63:0]; st <= ABSB; end
            ABSB:  begin if (bneg) rB <= asum[63:0]; st <= PRE; end
            PRE: begin
                if (dv) begin
                    if (rB == 64'd0 || rem0 >= rB) begin inv <= 1'b1; st <= FIN; end
                    else begin rR <= rem0; rQ <= rA & mW; cnt <= W; st <= LOOPD; end
                end else begin rQ <= rB; rB <= rB; rH <= 64'd0; cnt <= W; st <= LOOPM; end
            end
            LOOPM: begin
                rH <= asum[64:1]; rQ <= (rQ >> 1) | ((w_q == 2'd0) ? {56'd0, asum[0], 7'd0} : (w_q == 2'd1) ? {48'd0, asum[0], 15'd0} : (w_q == 2'd2) ? {32'd0, asum[0], 31'd0} : {asum[0], 63'd0});
                cnt <= cnt - 7'd1; if (cnt == 7'd1) st <= MFIN;
            end
            MFIN: begin r <= (w_q == 2'd0) ? {112'd0, rH[7:0], rQ[7:0]} : (w_q == 2'd1) ? {96'd0, rH[15:0], rQ[15:0]} : (w_q == 2'd2) ? {64'd0, rH[31:0], rQ[31:0]} : {rH, rQ}; st <= (aneg ^ bneg) ? NEGP0 : FIN; end
            NEGP0: begin r[63:0] <= asum[63:0]; c <= asum[64]; st <= NEGP1; end
            NEGP1: begin r[127:64] <= asum[63:0]; st <= FIN; end
            LOOPD: begin
                if (!asum[65]) begin rR <= asum[63:0]; rQ <= ((rQ << 1) | 64'd1) & mW; end
                else begin rR <= {rR[62:0], bitw(rQ, w_q)}; rQ <= (rQ << 1) & mW; end
                cnt <= cnt - 7'd1; if (cnt == 7'd1) st <= QFIX;
            end
            QFIX: begin
                if (sg && rQ > lim) begin inv <= 1'b1; st <= FIN; end else st <= NEGQ;
            end
            NEGQ: begin if (aneg ^ bneg) rQ <= asum[63:0] & mW; st <= NEGR; end
            NEGR: begin if (aneg) rR <= asum[63:0] & mW; st <= FIN; end
            FIN: begin
                busy <= 1'b0; st <= IDLE;
                if (dv) begin
                    r <= qr; rhi <= rm;
                    fl <= inv ? 8'b0000_0100 : {1'b0, (qm == 64'd0), 6'b000000};
                end else begin
                    r <= r2; rhi <= hi2;
                    fl <= {(w_q == 2'd0) ? r2[15] : (w_q == 2'd1) ? r2[31] : (w_q == 2'd2) ? r2[63] : r2[127], (r2 == 128'd0), 3'b000, sg & ovf, 1'b0, ovf};
                end
            end
            default: st <= IDLE;
        endcase
    end
endmodule
