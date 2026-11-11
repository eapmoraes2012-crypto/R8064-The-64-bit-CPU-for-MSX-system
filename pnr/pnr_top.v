// Invólucro SÓ para medir timing do decodificador na Tang Nano 20K (nao e o projeto final).
// Entradas serializadas (16 bits) e saidas reduzidas a 1 bit de paridade.
module pnr_top(input clk, input din, output dout);
    reg [15:0] sh = 16'd0;
    always @(posedge clk) sh <= {sh[14:0], din};
    wire [9:0] id; wire illegal; wire [3:0] len; wire [4:0] nr, nw; wire [1:0] nio; wire [7:0] ex; wire [1:0] pen_code; wire has_cond, is_z80;
    r8064_decode u(.clk(clk), .b2(sh[15:8]), .b3(sh[7:0]), .id(id), .illegal(illegal), .len(len), .nr(nr), .nw(nw),
                   .nio(nio), .ex(ex), .pen_code(pen_code), .has_cond(has_cond), .is_z80(is_z80));
    reg p = 1'b0;
    always @(posedge clk) p <= ^{id, illegal, len, nr, nw, nio, ex, pen_code, has_cond, is_z80};
    assign dout = p;
endmodule
