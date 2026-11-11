// fpu_half.v - FPU aritmetica em dominio de clock proprio a EXATAMENTE metade do clock do pipeline (clk/2).
// O pipeline segue a 'clk' (100 MHz); o nucleo fpu_alu roda a clk2 = clk/2 (50 MHz), gerado por um flip-flop alternador
// ligado ao reset, portanto sempre em fase com 'clk' (cada borda de subida de clk2 coincide com uma de clk).
// Interface identica a do fpu_alu, em clocks do pipeline. Protocolo: 'start' (1 pulso, so com busy=0) trava os operandos;
// 'done' sai como 1 pulso em clk, com res/flags/up/cc estaveis ate o proximo start. Travessia de dominios por toggle (req_t/dt2).
module fpu_half(
    input  wire        clk, rst, start,
    input  wire [3:0]  op,
    input  wire [1:0]  rc, pc,
    input  wire [79:0] a, b,
    output wire        busy,
    output reg         done,
    output wire [79:0] res,
    output wire [5:0]  flags,
    output wire        up,
    output wire [2:0]  cc
);
    // ---- divisor por 2 (dominio clk)
    reg ph = 1'b0;
    always @(posedge clk) ph <= rst ? 1'b0 : ~ph;
    wire clk2 = ph;
    // ---- lado pipeline (clk): trava operandos e alterna req_t
    reg [3:0] op_q; reg [1:0] rc_q, pc_q; reg [79:0] a_q, b_q; reg req_t = 1'b0; reg d1 = 1'b0, dseen = 1'b0;
    wire dt2;
    assign busy = (req_t != dseen);
    always @(posedge clk) begin
        if (rst) begin req_t <= 1'b0; dseen <= 1'b0; d1 <= 1'b0; done <= 1'b0; end
        else begin
            done <= 1'b0;
            if (start && !busy) begin op_q <= op; rc_q <= rc; pc_q <= pc; a_q <= a; b_q <= b; req_t <= ~req_t; end
            d1 <= dt2;
            if (d1 != dseen) begin dseen <= d1; done <= 1'b1; end
        end
    end
    // ---- lado FPU (clk2)
    reg rst2 = 1'b1; reg s1 = 1'b0, seen = 1'b0, st2 = 1'b0, dq = 1'b0, dt = 1'b0;
    reg [79:0] res_r; reg [5:0] fl_r; reg up_r; reg [2:0] cc_r;
    wire alu_done; wire [79:0] alu_res; wire [5:0] alu_fl; wire alu_up; wire [2:0] alu_cc; wire alu_busy;
    always @(posedge clk2) begin
        rst2 <= rst;
        s1 <= req_t;
        st2 <= (s1 != seen);
        if (s1 != seen) seen <= s1;
        dq <= alu_done;
        if (alu_done && !dq) begin res_r <= alu_res; fl_r <= alu_fl; up_r <= alu_up; cc_r <= alu_cc; dt <= ~dt; end
        if (rst2) begin seen <= 1'b0; s1 <= 1'b0; st2 <= 1'b0; dq <= 1'b0; dt <= 1'b0; end
    end
    assign dt2 = dt;
    assign res = res_r; assign flags = fl_r; assign up = up_r; assign cc = cc_r;
    fpu_alu u_alu(.clk(clk2), .rst(rst2), .start(st2), .op(op_q), .rc(rc_q), .pc(pc_q), .a(a_q), .b(b_q),
                  .busy(alu_busy), .done(alu_done), .res(alu_res), .flags(alu_fl), .up(alu_up), .cc(alu_cc));
endmodule
