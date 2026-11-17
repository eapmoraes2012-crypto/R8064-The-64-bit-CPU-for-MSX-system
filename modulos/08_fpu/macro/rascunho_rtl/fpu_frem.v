// fpu_frem.v - exact partial remainder FREM / FREM1 (bit-by-bit long division over the mantissas; up to ~32800 clocks).
// Finite and non-zero operands (special cases are handled by the macro program). res = x - y*N exact, N = trunc(x/y) (near = 0) or round-nearest-even (near = 1);
// q = 3 low bits of N (C0 = q[2], C3 = q[1], C1 = q[0]).
module fpu_frem(
    input  wire        clk, rst, start, near,
    input  wire [79:0] x, y,
    output reg         busy, done,
    output reg  [79:0] res,
    output reg  [2:0]  q
);
    localparam S_IDLE = 0, S_NX = 1, S_NY = 2, S_CHK = 3, S_LOOP = 4, S_ADJ = 5, S_N0 = 6, S_NORM = 7;
    reg [2:0] st; reg nr, sg; reg [63:0] mx, my; reg signed [17:0] ex, ey, ec, e0; reg [16:0] cnt; reg [64:0] a;
    wire signed [17:0] d = ex - ey;
    wire [65:0] t = {a, 1'b0};
    wire [65:0] t2 = {a, 1'b0};
    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin st <= S_IDLE; busy <= 1'b0; end
        else case (st)
            S_IDLE: if (start) begin
                busy <= 1'b1; nr <= near; sg <= x[79]; mx <= x[63:0]; my <= y[63:0];
                ex <= (x[78:64] == 15'd0 ? 18'sd1 : $signed({3'b000, x[78:64]})) - 18'sd16446;
                ey <= (y[78:64] == 15'd0 ? 18'sd1 : $signed({3'b000, y[78:64]})) - 18'sd16446;
                st <= S_NX;
            end
            S_NX: if (!mx[63]) begin mx <= {mx[62:0], 1'b0}; ex <= ex - 18'sd1; end else st <= S_NY;
            S_NY: if (!my[63]) begin my <= {my[62:0], 1'b0}; ey <= ey - 18'sd1; end else st <= S_CHK;
            S_CHK: begin
                if (d < -18'sd1) begin a <= {1'b0, mx}; e0 <= ex; q <= 3'd0; st <= S_N0; end
                else if (d == -18'sd1) begin
                    e0 <= ex;
                    if (nr && mx > my) begin a <= {1'b0, my, 1'b0} - {1'b0, 1'b0, mx}; sg <= ~sg; q <= 3'd1; end
                    else begin a <= {1'b0, mx}; q <= 3'd0; end
                    st <= S_N0;
                end else begin
                    e0 <= ey; cnt <= d[16:0];
                    if (mx >= my) begin a <= {1'b0, mx - my}; q <= 3'd1; end else begin a <= {1'b0, mx}; q <= 3'd0; end
                    st <= S_LOOP;
                end
            end
            S_LOOP: begin
                if (cnt == 17'd0) st <= nr ? S_ADJ : S_N0;
                else begin
                    if (t >= {2'b00, my}) begin a <= t[64:0] - {1'b0, my}; q <= {q[1:0], 1'b1}; end
                    else begin a <= t[64:0]; q <= {q[1:0], 1'b0}; end
                    cnt <= cnt - 17'd1;
                end
            end
            S_ADJ: begin
                if (t2 > {2'b00, my} || (t2 == {2'b00, my} && q[0])) begin a <= {1'b0, my} - a; sg <= ~sg; q <= q + 3'd1; end
                st <= S_N0;
            end
            S_N0: begin ec <= e0 + 18'sd16446; st <= S_NORM; end
            S_NORM: begin
                if (a == 65'd0) begin res <= {sg, 79'd0}; busy <= 1'b0; done <= 1'b1; st <= S_IDLE; end
                else if (!a[63] && ec > 18'sd1) begin a <= {1'b0, a[62:0], 1'b0}; ec <= ec - 18'sd1; end
                else if (ec < 18'sd1) begin a <= {1'b0, a[64:1]}; ec <= ec + 18'sd1; end
                else begin res <= {sg, (ec == 18'sd1 && !a[63]) ? 15'd0 : ec[14:0], a[63:0]}; busy <= 1'b0; done <= 1'b1; st <= S_IDLE; end
            end
            default: st <= S_IDLE;
        endcase
    end
endmodule
