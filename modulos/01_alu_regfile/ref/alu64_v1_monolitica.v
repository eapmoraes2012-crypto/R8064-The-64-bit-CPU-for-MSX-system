// alu64.v - ALU do R8064 (combinacional): 8/16/32/64 bits.
// Semantica de flags (PREMISSAS minhas, extensao natural do Z80; confirmar - pendencia P03/P28):
//   F = {S,Z,Y,H,X,PV,N,C}  (bits 7..0, as in the "Registers and codes" tab)
//   ADD/ADC/SUB/SBC/CP/INC/DEC/NEG: C=carry (borrow on subtraction), H=carry from bit 3 to 4,
//     PV=signed overflow at the operation size, N=0 (add) or 1 (subtract), S=msb, Z=zero result.
//   INC/DEC preserve C. CP: the SUB result is not written (the caller discards it); X,Y come from operand b.
//   AND/OR/XOR: C=0, N=0, H=1 only on AND, PV=even parity of the low byte.
//   SHL/SHR/SAR/ROL/ROR (1 bit): C=bit shifted out, N=0, H=0, PV=parity of the low byte.
//   CPL: preserva S,Z,PV,C; H=1, N=1.
//   X and Y = copy of bits 3 and 5 of the result.
module alu64(
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire [4:0]  op,
    input  wire [1:0]  sz,      // 0=8 bits, 1=16, 2=32, 3=64
    input  wire [7:0]  fin,
    output reg  [63:0] res,
    output reg  [7:0]  fout
);
    localparam ADD=5'd0, ADC=5'd1, SUB=5'd2, SBC=5'd3, AND_=5'd4, OR_=5'd5, XOR_=5'd6, CP=5'd7,
               INC=5'd8, DEC=5'd9, NEG=5'd10, CPL=5'd11, SHL=5'd12, SHR=5'd13, SAR=5'd14, ROL=5'd15, ROR=5'd16;

    wire [63:0] m   = (sz == 2'd0) ? 64'h0000_0000_0000_00FF :
                      (sz == 2'd1) ? 64'h0000_0000_0000_FFFF :
                      (sz == 2'd2) ? 64'h0000_0000_FFFF_FFFF : 64'hFFFF_FFFF_FFFF_FFFF;
    wire [5:0]  msb = (sz == 2'd0) ? 6'd7 : (sz == 2'd1) ? 6'd15 : (sz == 2'd2) ? 6'd31 : 6'd63;
    wire [63:0] am  = a & m;
    wire [63:0] bm  = b & m;

    reg  [63:0] x, y, bop;
    reg         ci;
    reg         is_arith, is_sub;
    always @* begin
        x = am; y = bm; bop = bm; ci = 1'b0; is_arith = 1'b1; is_sub = 1'b0;
        case (op)
            ADD: begin end
            ADC: ci = fin[0];
            SUB, CP: begin y = ~bm & m; ci = 1'b1; is_sub = 1'b1; end
            SBC: begin y = ~bm & m; ci = ~fin[0]; is_sub = 1'b1; end
            INC: begin y = 64'd1; bop = 64'd1; end
            DEC: begin bop = 64'd1; y = ~64'd1 & m; ci = 1'b1; is_sub = 1'b1; end
            NEG: begin x = 64'd0; bop = am; y = ~am & m; ci = 1'b1; is_sub = 1'b1; end
            default: is_arith = 1'b0;
        endcase
    end

    wire [64:0] sum  = {1'b0, x} + {1'b0, y} + {64'd0, ci};
    wire [63:0] sres = sum[63:0] & m;
    wire        cout = (sz == 2'd0) ? sum[8] : (sz == 2'd1) ? sum[16] : (sz == 2'd2) ? sum[32] : sum[64];
    wire        xs = x[msb], ys = y[msb], rs = sres[msb];
    wire        ovf = (xs == ys) && (rs != xs);
    wire        hc  = x[4] ^ bop[4] ^ sres[4];

    reg  [63:0] r;
    reg         c, n, h, pv;
    reg         sh_out;
    always @* begin
        r = 64'd0; c = 1'b0; n = 1'b0; h = 1'b0; pv = 1'b0; sh_out = 1'b0;
        case (op)
            ADD, ADC, SUB, SBC, CP, INC, DEC, NEG: begin
                r = sres; c = is_sub ? ~cout : cout; n = is_sub; h = hc; pv = ovf;
                if (op == INC || op == DEC) c = fin[0];
            end
            AND_: begin r = am & bm; h = 1'b1; end
            OR_:  begin r = am | bm; end
            XOR_: begin r = am ^ bm; end
            CPL:  begin r = ~am & m; h = 1'b1; n = 1'b1; end
            SHL:  begin sh_out = am[msb]; r = (am << 1) & m; end
            SHR:  begin sh_out = am[0];   r = am >> 1; end
            SAR:  begin sh_out = am[0];   r = (am >> 1) | ({63'd0, am[msb]} << msb); end
            ROL:  begin sh_out = am[msb]; r = ((am << 1) & m) | {63'd0, am[msb]}; end
            ROR:  begin sh_out = am[0];   r = (am >> 1) | ({63'd0, am[0]} << msb); end
            default: r = 64'd0;
        endcase
        if (op >= SHL && op <= ROR) c = sh_out;
    end

    wire par = ~^r[7:0];     // even parity of the low byte
    wire zf  = ((r & m) == 64'd0);
    always @* begin
        res = r & m;
        fout[7] = r[msb];                       // S
        fout[6] = zf;                           // Z
        fout[5] = (op == CP) ? bop[5] : r[5];   // Y
        fout[4] = h;                            // H
        fout[3] = (op == CP) ? bop[3] : r[3];   // X
        fout[2] = (op >= AND_ && op <= XOR_ || op >= SHL && op <= ROR) ? par :
                  (op == CPL) ? fin[2] : pv;    // PV
        fout[1] = n;                            // N
        fout[0] = (op == CPL) ? fin[0] : c;     // C
        if (op == CPL) begin fout[7] = fin[7]; fout[6] = fin[6]; end
        if (op > ROR) fout = fin;               // undefined operation: preserves
    end
endmodule
