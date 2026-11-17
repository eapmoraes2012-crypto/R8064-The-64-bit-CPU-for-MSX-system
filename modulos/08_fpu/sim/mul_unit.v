// mul_unit.v - multiplicador do R8064 (4 multiplicadores 18x18 em paralelo, em DSP).
//   sz: 0=8, 1=16, 2=32, 3=64 bits; sgn: 1 = signed.
//   sz<=2 : 2*sz-bit product in ONE pass (pipeline, 1 operation per clock). sz=3: 4 passes (16x64 per pass), 128 bits.
//   Stages: S1 (operand mux, 18-bit x/y) -> S2 (4 36-bit products, DSP) -> S3a (partial sums) -> S3b (84-bit weighted sum) -> S3c (85-bit accumulator shifted 16 bits per pass) -> prod/out_valid.
//   Latency (operation accepted at cycle 0 until out_valid): small ones 5 clocks, 64 bits 8 clocks. ready drops for 3 clocks after a 64-bit one.
module mul_unit(
    input  wire         clk, rst,
    input  wire         in_valid,
    input  wire [1:0]   sz,
    input  wire         sgn,
    input  wire [63:0]  a, b,
    output wire         ready,
    output reg          out_valid,
    output reg  [127:0] prod
);
    // REV47: with R8064_NO_MD64 (Tang Nano 20K builds) MLTSQ/MLTUQ (64x64->128) do not exist: no 4-pass path (sz <= 2 only).
`ifdef R8064_NO_MD64
    localparam BIG = 1'b0;
`else
    localparam BIG = 1'b1;
`endif
    reg        busy_big; reg [1:0] jc; reg [63:0] ra, rb; reg rsgn;
    assign ready = !busy_big;
    wire issue = in_valid && ready;
    wire [63:0] ca = busy_big ? ra : a;
    wire [63:0] cb = busy_big ? rb : b;
    wire        cs = busy_big ? rsgn : sgn;
    wire        cbig = busy_big ? 1'b1 : ((sz == 2'd3) && BIG);
    wire [1:0]  cj = busy_big ? jc : 2'd0;
    wire        cv = busy_big | issue;

    // extension to 32 bits for small operations
    wire [31:0] a32 = (sz == 2'd0) ? {{24{cs & ca[7]}},  ca[7:0]}  :
                      (sz == 2'd1) ? {{16{cs & ca[15]}}, ca[15:0]} : ca[31:0];
    wire [31:0] b32 = (sz == 2'd0) ? {{24{cs & cb[7]}},  cb[7:0]}  :
                      (sz == 2'd1) ? {{16{cs & cb[15]}}, cb[15:0]} : cb[31:0];
    // 16-bit limbs (18 bits when signed): signed top if cs
    function [17:0] ext(input [15:0] v, input s); ext = s ? {{2{v[15]}}, v} : {2'b00, v}; endfunction
    reg signed [17:0] xn [0:3]; reg signed [17:0] yn [0:3];
    always @* begin
        if (cbig) begin
            xn[0] = ext(ca[15:0], 0);  xn[1] = ext(ca[31:16], 0); xn[2] = ext(ca[47:32], 0); xn[3] = ext(ca[63:48], cs);
            case (cj)
                2'd0: begin yn[0] = ext(cb[15:0], 0);  end
                2'd1: begin yn[0] = ext(cb[31:16], 0); end
                2'd2: begin yn[0] = ext(cb[47:32], 0); end
                default: begin yn[0] = ext(cb[63:48], cs); end
            endcase
            yn[1] = yn[0]; yn[2] = yn[0]; yn[3] = yn[0];
        end else begin
            xn[0] = ext(a32[15:0], 0); xn[1] = ext(a32[31:16], cs); xn[2] = ext(a32[15:0], 0); xn[3] = ext(a32[31:16], cs);
            yn[0] = ext(b32[15:0], 0); yn[1] = ext(b32[15:0], 0);   yn[2] = ext(b32[31:16], cs); yn[3] = ext(b32[31:16], cs);
        end
    end
    reg signed [17:0] x1 [0:3]; reg signed [17:0] y1 [0:3]; reg v1, big1; reg [1:0] j1;
    reg signed [35:0] p2 [0:3]; reg v2, big2; reg [1:0] j2;
    reg signed [84:0] acc; reg [47:0] plo;   // REV47: acc = partial product >> (16*pass) (85 bits) + low limbs already final
    integer k;
    // S3a: partial sums; S3b: weighted sum (84 bits); S3c: accumulator (85 bits, shifted right 16 bits per pass)
    reg signed [51:0] t01, t23; reg v3, big3; reg [1:0] j3;
    reg signed [83:0] sw; reg v4, big4; reg [1:0] j4;
    wire signed [51:0] w01 = $signed(p2[0]) + ($signed(p2[1]) <<< 16);
    wire signed [51:0] w23 = $signed(p2[2]) + ($signed(p2[3]) <<< 16);
    wire signed [83:0] w_sum = t01 + (big3 ? (t23 <<< 32) : (t23 <<< 16));
    // REV47: instead of shifting each pass to its weight and adding to a 128-bit accumulator, the accumulator is shifted right by 16
    //   each pass (its 16 low bits are already final): an 85-bit adder and no 128-bit barrel shifter.
    wire signed [84:0] acc_n = ((j4 == 2'd0) ? 85'sd0 : (acc >>> 16)) + $signed({sw[83], sw});
    always @(posedge clk) begin
        if (rst) begin
            busy_big <= 0; jc <= 0; v1 <= 0; v2 <= 0; v3 <= 0; v4 <= 0; out_valid <= 0; acc <= 0;
            big1 <= 0; big2 <= 0; big3 <= 0; big4 <= 0; j1 <= 0; j2 <= 0; j3 <= 0; j4 <= 0;
        end else begin
            if (issue && sz == 2'd3 && BIG) begin busy_big <= 1; jc <= 2'd1; ra <= a; rb <= b; rsgn <= sgn; end
            else if (busy_big) begin
                jc <= jc + 1; if (jc == 2'd3) busy_big <= 0;
            end
            v1 <= cv; big1 <= cbig; j1 <= cj;
            for (k = 0; k < 4; k = k + 1) begin x1[k] <= xn[k]; y1[k] <= yn[k]; end
            v2 <= v1; big2 <= big1; j2 <= j1;
            for (k = 0; k < 4; k = k + 1) p2[k] <= x1[k] * y1[k];
            v3 <= v2; big3 <= big2; j3 <= j2; t01 <= w01; t23 <= w23;
            v4 <= v3; big4 <= big3; j4 <= j3; sw <= w_sum;
            out_valid <= 0;
            if (v4) begin
                if (big4) begin
                    acc <= acc_n;
                    case (j4) 2'd0: plo[15:0] <= acc_n[15:0]; 2'd1: plo[31:16] <= acc_n[15:0]; 2'd2: plo[47:32] <= acc_n[15:0]; default: ; endcase
                    if (j4 == 2'd3) begin prod <= {acc_n[79:0], plo}; out_valid <= 1; end
                end else begin prod <= {{44{sw[83]}}, sw}; out_valid <= 1; end
            end
        end
    end
endmodule
