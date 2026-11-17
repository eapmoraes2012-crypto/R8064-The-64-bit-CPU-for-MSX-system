// vec3d_unit.v (v6, area-optimized) - R8064 3D manipulation unit. Vectors = 4 int16 lanes (x,y,z,w) in a 64-bit register,
// fixed point with output shift "sh" (0..15): product = (a*b + rounding) >>> sh. 10 16x16 multipliers (DSP 18x18), 1 operation per clock, latency 4.
//  op 0 VMUL   : lane_i = sat16((a_i*b_i) >>> sh)
//  op 1 VDOT4  : escalar 64 b = (a0*b0+a1*b1+a2*b2+a3*b3) >>> sh
//  op 2 VDOT3  : same without lane 3 (w)
//  op 3 VCROSS3: (a1*b2-a2*b1, a2*b0-a0*b2, a0*b1-a1*b0, 0) >>> sh, saturado
//  op 4 VADD   : lane_i = sat16(a_i + b_i)     op 5 VSUB: sat16(a_i - b_i)
//  op 6 VMIN   : lane_i = min(a_i,b_i)         op 7 VMAX: max
//  op 8 VSHUF  : lane_i = a[imm[2i+1:2i]]  (permutacao/swizzle; b ignorado)
//  op 9 VNEG   : lane_i = sat16(-a_i)          op 10 VABS: sat16(|a_i|)      (done in the multipliers: a_i * (-1) and a_i * sign(a_i))
module vec3d_unit #(parameter LANE_ALU = 1)(   // LANE_ALU=0: without VADD/VSUB/VMIN/VMAX (those opcodes return 0)
    input  wire        clk,
    input  wire        in_valid,
    input  wire [3:0]  op,
    input  wire [3:0]  sh,
    input  wire [7:0]  imm,
    input  wire [63:0] a, b,
    output reg         out_valid,
    output reg  [63:0] out
);
    function signed [15:0] sat16(input signed [35:0] x);
        sat16 = ((&x[35:15]) || !(|x[35:15])) ? x[15:0] : (x[35] ? 16'sh8000 : 16'sh7fff);   // no comparators: only checks the sign extension
    endfunction
    wire signed [15:0] a0 = a[15:0], a1 = a[31:16], a2 = a[47:32], a3 = a[63:48];
    wire signed [15:0] b0 = b[15:0], b1 = b[31:16], b2 = b[47:32], b3 = b[63:48];
    // ---- S1: products (DSP, straight from the inputs): 4 diagonals (VMUL/DOT/NEG/ABS) + 6 crossed (VCROSS3) ----
    wire un  = (op == 4'd9) || (op == 4'd10);                       // NEG: b := -1 ; ABS: b := +-1 according to the sign of a
    wire neg = (op == 4'd9);
    wire signed [15:0] xb0 = un ? {{15{neg | a0[15]}}, 1'b1} : b0, xb1 = un ? {{15{neg | a1[15]}}, 1'b1} : b1,
                       xb2 = un ? {{15{neg | a2[15]}}, 1'b1} : b2, xb3 = un ? {{15{neg | a3[15]}}, 1'b1} : b3;
    wire signed [15:0] xa3 = (op == 4'd2) ? 16'sd0 : a3;           // DOT3: without lane w
    reg signed [31:0] p0, p1, p2, p3, c0, c1, c2, c3, c4, c5; reg [3:0] o1; reg [3:0] s1; reg [7:0] i1; reg v1; reg [63:0] a1r, b1r;
    always @(posedge clk) begin
        p0 <= a0 * xb0; p1 <= a1 * xb1; p2 <= a2 * xb2; p3 <= xa3 * xb3;
        c0 <= a1 * b2; c1 <= a2 * b1; c2 <= a2 * b0; c3 <= a0 * b2; c4 <= a0 * b1; c5 <= a1 * b0;
        o1 <= op; s1 <= sh; i1 <= imm; v1 <= in_valid; a1r <= a; b1r <= b;
    end
    // ---- S2: sums / differences ----
    reg signed [33:0] r0; reg signed [32:0] r1, r2, r3; reg [3:0] o2; reg [3:0] s2; reg v2;
    wire signed [15:0] ya0 = a1r[15:0], ya1 = a1r[31:16], ya2 = a1r[47:32], ya3 = a1r[63:48];
    wire signed [15:0] yb0 = b1r[15:0], yb1 = b1r[31:16], yb2 = b1r[47:32], yb3 = b1r[63:48];
    // one 17-bit adder/subtractor per lane, shared by VADD/VSUB/VMIN/VMAX
    wire sb = (o1 != 4'd4);                          // add only on VADD
    wire signed [16:0] d0 = !LANE_ALU ? 17'sd0 : sb ? ya0 - yb0 : ya0 + yb0, d1 = !LANE_ALU ? 17'sd0 : sb ? ya1 - yb1 : ya1 + yb1,
                       d2 = !LANE_ALU ? 17'sd0 : sb ? ya2 - yb2 : ya2 + yb2, d3 = !LANE_ALU ? 17'sd0 : sb ? ya3 - yb3 : ya3 + yb3;
    wire mn = (o1 == 4'd6);                          // MIN: d<0 (a<b) -> a ; MAX: d<0 -> b
    always @(posedge clk) begin
        o2 <= o1; s2 <= s1; v2 <= v1;
        case (o1)
          4'd0, 4'd9, 4'd10: begin r0 <= p0; r1 <= p1; r2 <= p2; r3 <= p3; end                      // VMUL / VNEG / VABS
          4'd1, 4'd2: begin r0 <= p0 + p1 + p2 + p3; r1 <= 0; r2 <= 0; r3 <= 0; end                // VDOT4 / VDOT3 (p3 = 0 em DOT3)
          4'd3: begin r0 <= c0 - c1; r1 <= c2 - c3; r2 <= c4 - c5; r3 <= 0; end                    // VCROSS3
          4'd4, 4'd5: begin r0 <= d0; r1 <= d1; r2 <= d2; r3 <= d3; end                            // VADD / VSUB
          4'd6, 4'd7: begin
              r0 <= (d0[16] ^ ~mn) ? ya0 : yb0; r1 <= (d1[16] ^ ~mn) ? ya1 : yb1;
              r2 <= (d2[16] ^ ~mn) ? ya2 : yb2; r3 <= (d3[16] ^ ~mn) ? ya3 : yb3; end              // VMIN / VMAX
          default: begin r0 <= $signed(a1r[16*i1[1:0] +: 16]); r1 <= $signed(a1r[16*i1[3:2] +: 16]); r2 <= $signed(a1r[16*i1[5:4] +: 16]); r3 <= $signed(a1r[16*i1[7:6] +: 16]); end   // VSHUF
        endcase
    end
    // ---- S3: deslocamento aritmetico + bit de arredondamento ----
    wire do_shift = (o2 <= 4'd3);
    wire [3:0] ss = do_shift ? s2 : 4'd0;
    // rounding = bit (ss-1) after the shift: (r + 2^(ss-1)) >>> ss == (r >>> ss) + r[ss-1]
    // lane 0 (also receives the wide VDOT result): full 34-bit shifter
    reg signed [33:0] t0; reg rb0, dot4; reg v3;
    always @(posedge clk) begin
        t0 <= r0 >>> ss; rb0 <= (ss != 0) && r0[ss-1];
        dot4 <= (o2 == 4'd1 || o2 == 4'd2); v3 <= v2;
    end
    // lanes 1-3 (16-bit output): only the window [ss+15:ss] of the shifted value and the "fits in int16" test (r[32:15+ss] all equal, by thermometer) are needed
    wire [16:0] tm;                                                  // tm[j] = (ss > j): positions of r below 15+ss do not enter the test
    genvar gj; generate for (gj = 0; gj < 17; gj = gj + 1) begin : g_tm assign tm[gj] = (ss > gj); end endgenerate
    function [15:0] win16(input [32:0] r, input [3:0] k);              // window r[k+15:k], k = 0..15, in 4 levels (23+19+17+16 multiplexers)
        reg [22:0] w3; reg [18:0] w2; reg [16:0] w1;
        begin
            w3 = k[3] ? r[30:8] : r[22:0];
            w2 = k[2] ? w3[22:4] : w3[18:0];
            w1 = k[1] ? w2[18:2] : w2[16:0];
            win16 = k[0] ? w1[16:1] : w1[15:0];
        end
    endfunction
    reg [15:0] lo1, lo2, lo3; reg rb1, rb2, rb3, eq1, eq2, eq3, sg1, sg2, sg3;
    function eqf(input [32:0] r, input [16:0] m);                      // r[31:15] (each bit or masked) equal to the sign r[32]
        eqf = &(m | ~(r[31:15] ^ {17{r[32]}}));
    endfunction
    always @(posedge clk) begin
        lo1 <= win16(r1, ss); lo2 <= win16(r2, ss); lo3 <= win16(r3, ss);
        rb1 <= (ss != 0) && r1[ss-1]; rb2 <= (ss != 0) && r2[ss-1]; rb3 <= (ss != 0) && r3[ss-1];
        eq1 <= eqf(r1, tm); eq2 <= eqf(r2, tm); eq3 <= eqf(r3, tm);
        sg1 <= r1[32]; sg2 <= r2[32]; sg3 <= r3[32];
    end
    // ---- S4: rounding sum, saturation and packing ----
    wire signed [35:0] q0 = t0 + $signed({1'b0, rb0});               // rb unsigned: extends the sign explicitly
    function [15:0] fin16(input [15:0] lo, input rb, input eq, input sg);
        fin16 = eq ? ((lo == 16'h7fff) ? 16'h7fff : lo + {15'd0, rb}) : (sg ? 16'h8000 : 16'h7fff);
    endfunction
    always @(posedge clk) begin
        out_valid <= v3;
        if (dot4) out <= {{28{q0[35]}}, q0};
        else out <= {fin16(lo3, rb3, eq3, sg3), fin16(lo2, rb2, eq2, sg2), fin16(lo1, rb1, eq1, sg1), sat16(q0)};
    end
endmodule
