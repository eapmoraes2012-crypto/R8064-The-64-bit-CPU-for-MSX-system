`timescale 1ns/1ps
module tb_vec3d;
    parameter N = 30000;
    reg clk = 0; always #5 clk = ~clk;
    reg [63:0] ma [0:N-1], mb [0:N-1], me [0:N-1]; reg [19:0] mc [0:N-1];
    reg in_valid = 0; reg [3:0] op = 0; reg [3:0] sh = 0; reg [7:0] imm = 0; reg [63:0] a = 0, b = 0;
    wire out_valid; wire [63:0] out;
    vec3d_unit dut(.clk(clk), .in_valid(in_valid), .op(op), .sh(sh), .imm(imm), .a(a), .b(b), .out_valid(out_valid), .out(out));
    integer i = 0, k = 0, err = 0, gp = 0; parameter GAP = 2;
    initial begin $readmemh("v_a.mem", ma); $readmemh("v_b.mem", mb); $readmemh("v_c.mem", mc); $readmemh("v_e.mem", me); end
    always @(posedge clk) begin
        gp <= (gp + 1) % GAP; if (i < N && gp == 0) begin in_valid <= 1; a <= ma[i]; b <= mb[i]; op <= mc[i][3:0]; sh <= mc[i][7:4]; imm <= mc[i][19:12]; i <= i + 1; end
        else in_valid <= 0;
        if (out_valid) begin
            if (out !== me[k]) begin err = err + 1; if (err < 6) $display("ERRO vetor %0d op=%0d: obtido %h esperado %h", k, mc[k][3:0], out, me[k]); end
            k = k + 1;
        end
        if (k == N) begin
            if (err == 0) $display("RESULTADO: VEC3D OK (%0d vetores, 1 a cada %0d clocks)", N, GAP); else $display("RESULTADO: %0d ERROS", err);
            $finish;
        end
    end
    initial begin #40000000; $display("TIMEOUT k=%0d", k); $finish; end
endmodule
