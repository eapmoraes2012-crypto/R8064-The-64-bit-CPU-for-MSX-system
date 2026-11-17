// vec3d_unit.v - R8064 3D manipulation unit (measurement prototype). Vectors = 4 int16 lanes (x,y,z,w) in a 64-bit register,
// fixed point with output shift "sh" (Qn): product = (a*b + rounding) >>> sh. 6 16x16 multipliers (DSP 18x18), 1 operation per clock, latency 4.
//  op 0 VMUL   : lane_i = sat16((a_i*b_i) >>> sh)
//  op 1 VDOT4  : escalar 64 b = (a0*b0+a1*b1+a2*b2+a3*b3) >>> sh
//  op 2 VDOT3  : same without lane 3 (w)
//  op 3 VCROSS3: (a1*b2-a2*b1, a2*b0-a0*b2, a0*b1-a1*b0, 0) >>> sh, saturado
//  op 4 VADD   : lane_i = sat16(a_i + b_i)     op 5 VSUB: sat16(a_i - b_i)
//  op 6 VMIN   : lane_i = min(a_i,b_i)         op 7 VMAX: max
//  op 8 VSHUF  : lane_i = a[imm[2i+1:2i]]  (permutacao/swizzle; b ignorado)
//  op 9 VNEG   : lane_i = sat16(-a_i)          op 10 VABS: sat16(|a_i|)
module vec3d_unit(
    input  wire        clk,
    input  wire        in_valid,
    input  wire [3:0]  op,
    input  wire [4:0]  sh,
    input  wire [7:0]  imm,
    input  wire [63:0] a, b,
    output reg         out_valid,
    output reg  [63:0] out
);
    function signed [15:0] sat16(input signed [35:0] x);
        sat16 = (x > 36'sd32767) ? 16'sh7fff : (x < -36'sd32768) ? 16'sh8000 : x[15:0];
    endfunction
    wire signed [15:0] a0 = a[15:0], a1 = a[31:16], a2 = a[47:32], a3 = a[63:48];
    wire signed [15:0] b0 = b[15:0], b1 = b[31:16], b2 = b[47:32], b3 = b[63:48];
    wire is_cr = (op == 4'd3);
    // ---- S1: seleciona operandos e multiplica (DSP) ----
    reg signed [15:0] xa0, xb0, xa1, xb1, xa2, xb2, xa3, xb3, xa4, xb4, xa5, xb5;
    reg [3:0] o1; reg [4:0] s1; reg [7:0] i1; reg v1; reg [63:0] a1r, b1r;
    always @(posedge clk) begin
        xa0 <= is_cr ? a1 : a0;  xb0 <= is_cr ? b2 : b0;
        xa1 <= is_cr ? a2 : a1;  xb1 <= is_cr ? b1 : b1;
        xa2 <= is_cr ? a2 : a2;  xb2 <= is_cr ? b0 : b2;
        xa3 <= is_cr ? a0 : a3;  xb3 <= is_cr ? b2 : b3;
        xa4 <= a0;  xb4 <= b1;
        xa5 <= a1;  xb5 <= b0;
        o1 <= op; s1 <= sh; i1 <= imm; v1 <= in_valid; a1r <= a; b1r <= b;
    end
    // ---- S2: produtos ----
    reg signed [31:0] p0, p1, p2, p3, p4, p5; reg [3:0] o2; reg [4:0] s2; reg [7:0] i2; reg v2; reg [63:0] a2r, b2r;
    always @(posedge clk) begin
        p0 <= xa0 * xb0; p1 <= xa1 * xb1; p2 <= xa2 * xb2; p3 <= xa3 * xb3; p4 <= xa4 * xb4; p5 <= xa5 * xb5;
        o2 <= o1; s2 <= s1; i2 <= i1; v2 <= v1; a2r <= a1r; b2r <= b1r;
    end
    // ---- S3: sums / differences ----
    reg signed [35:0] r0, r1, r2, r3; reg [3:0] o3; reg [4:0] s3; reg [7:0] i3; reg v3;
    wire signed [15:0] ya0 = a2r[15:0], ya1 = a2r[31:16], ya2 = a2r[47:32], ya3 = a2r[63:48];
    wire signed [15:0] yb0 = b2r[15:0], yb1 = b2r[31:16], yb2 = b2r[47:32], yb3 = b2r[63:48];
    // one 17-bit adder/subtractor per lane, shared by VADD/VSUB/VMIN/VMAX/VNEG/VABS
    wire un = (o2 == 4'd9) || (o2 == 4'd10);        // NEG / ABS: 0 - a
    wire sb = (o2 != 4'd4);                          // add only on VADD
    wire signed [16:0] ex0 = un ? 17'sd0 : ya0, ey0 = un ? ya0 : yb0, ex1 = un ? 17'sd0 : ya1, ey1 = un ? ya1 : yb1,
                       ex2 = un ? 17'sd0 : ya2, ey2 = un ? ya2 : yb2, ex3 = un ? 17'sd0 : ya3, ey3 = un ? ya3 : yb3;
    wire signed [16:0] d0 = sb ? ex0 - ey0 : ex0 + ey0, d1 = sb ? ex1 - ey1 : ex1 + ey1, d2 = sb ? ex2 - ey2 : ex2 + ey2, d3 = sb ? ex3 - ey3 : ex3 + ey3;
    wire mn = (o2 == 4'd6);                          // MIN: d<0 (a<b) -> a ; MAX: d<0 -> b
    always @(posedge clk) begin
        o3 <= o2; s3 <= s2; i3 <= i2; v3 <= v2;
        case (o2)
          4'd0: begin r0 <= p0; r1 <= p1; r2 <= p2; r3 <= p3; end                                  // VMUL
          4'd1: begin r0 <= p0 + p1 + p2 + p3; r1 <= 0; r2 <= 0; r3 <= 0; end                      // VDOT4
          4'd2: begin r0 <= p0 + p1 + p2;      r1 <= 0; r2 <= 0; r3 <= 0; end                      // VDOT3
          4'd3: begin r0 <= p0 - p1; r1 <= p2 - p3; r2 <= p4 - p5; r3 <= 0; end                    // VCROSS3
          4'd4, 4'd5, 4'd9: begin r0 <= d0; r1 <= d1; r2 <= d2; r3 <= d3; end                      // VADD / VSUB / VNEG
          4'd6, 4'd7: begin
              r0 <= (d0[16] ^ ~mn) ? ya0 : yb0; r1 <= (d1[16] ^ ~mn) ? ya1 : yb1;
              r2 <= (d2[16] ^ ~mn) ? ya2 : yb2; r3 <= (d3[16] ^ ~mn) ? ya3 : yb3; end              // VMIN / VMAX
          4'd8: begin r0 <= $signed(a2r[16*i2[1:0] +: 16]); r1 <= $signed(a2r[16*i2[3:2] +: 16]); r2 <= $signed(a2r[16*i2[5:4] +: 16]); r3 <= $signed(a2r[16*i2[7:6] +: 16]); end
          default: begin r0 <= ya0[15] ? d0 : ya0; r1 <= ya1[15] ? d1 : ya1; r2 <= ya2[15] ? d2 : ya2; r3 <= ya3[15] ? d3 : ya3; end   // VABS
        endcase
    end
    // ---- S4: arredondamento, deslocamento, saturacao, empacotamento ----
    wire do_shift = (o3 <= 4'd3);
    wire [4:0] ss = do_shift ? s3 : 5'd0;
    // rounding = bit (ss-1) after the shift: (r + 2^(ss-1)) >>> ss == (r >>> ss) + r[ss-1]
    wire signed [35:0] t0 = r0 >>> ss, t1 = r1 >>> ss, t2 = r2 >>> ss, t3 = r3 >>> ss;
    wire rb0 = (ss != 0) && r0[ss-1], rb1 = (ss != 0) && r1[ss-1], rb2 = (ss != 0) && r2[ss-1], rb3 = (ss != 0) && r3[ss-1];
    wire signed [35:0] q0 = t0 + rb0, q1 = t1 + rb1, q2 = t2 + rb2, q3 = t3 + rb3;
    always @(posedge clk) begin
        out_valid <= v3;
        if (o3 == 4'd1 || o3 == 4'd2) out <= {{28{q0[35]}}, q0};
        else out <= {sat16(q3), sat16(q2), sat16(q1), sat16(q0)};
    end
endmodule
