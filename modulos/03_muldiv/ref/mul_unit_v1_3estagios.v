// mul_unit.v - R8064 multiplier (4 18x18 multipliers in parallel, in DSP).
//   sz: 0=8, 1=16, 2=32, 3=64 bits; sgn: 1 = signed.
//   sz<=2 : 2*sz-bit product in ONE pass (pipeline, 1 operation per clock). sz=3: 4 passes (16x64 per pass), 128 bits.
//   Stages: S1 (operand mux, registers 18-bit x/y) -> S2 (4 36-bit products) -> S3 (weighted sum and accumulator) -> prod/out_valid.
//   Latency (operation accepted at cycle 0 until out_valid): small ones 3 clocks, 64 bits 6 clocks. ready drops for 3 clocks after a 64-bit one.
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
    reg        busy_big; reg [1:0] jc; reg [63:0] ra, rb; reg rsgn;
    assign ready = !busy_big;
    wire issue = in_valid && ready;
    wire [63:0] ca = busy_big ? ra : a;
    wire [63:0] cb = busy_big ? rb : b;
    wire        cs = busy_big ? rsgn : sgn;
    wire        cbig = busy_big ? 1'b1 : (sz == 2'd3);
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
    reg signed [127:0] acc;
    integer k;
    wire signed [127:0] e0 = p2[0], e1 = p2[1], e2 = p2[2], e3 = p2[3];
    wire signed [127:0] sum_s = e0 + (e1 <<< 16) + (e2 <<< 16) + (e3 <<< 32);
    wire signed [127:0] sum_b = e0 + (e1 <<< 16) + (e2 <<< 32) + (e3 <<< 48);
    wire signed [127:0] sh_b  = sum_b <<< (16 * j2);
    wire signed [127:0] acc_n = ((j2 == 2'd0) ? 128'sd0 : acc) + sh_b;
    always @(posedge clk) begin
        if (rst) begin
            busy_big <= 0; jc <= 0; v1 <= 0; v2 <= 0; out_valid <= 0; acc <= 0; big1 <= 0; big2 <= 0; j1 <= 0; j2 <= 0;
        end else begin
            // issue
            if (issue && sz == 2'd3) begin busy_big <= 1; jc <= 2'd1; ra <= a; rb <= b; rsgn <= sgn; end
            else if (busy_big) begin
                jc <= jc + 1; if (jc == 2'd3) busy_big <= 0;
            end
            // S1
            v1 <= cv; big1 <= cbig; j1 <= cj;
            for (k = 0; k < 4; k = k + 1) begin x1[k] <= xn[k]; y1[k] <= yn[k]; end
            // S2
            v2 <= v1; big2 <= big1; j2 <= j1;
            for (k = 0; k < 4; k = k + 1) p2[k] <= x1[k] * y1[k];
            // S3
            out_valid <= 0;
            if (v2) begin
                if (big2) begin
                    acc <= acc_n;
                    if (j2 == 2'd3) begin prod <= acc_n; out_valid <= 1; end
                end else begin prod <= sum_s; out_valid <= 1; end
            end
        end
    end
endmodule
