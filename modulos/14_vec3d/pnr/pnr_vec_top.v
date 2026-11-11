module pnr_vec_top(input wire clk, input wire din, output wire dout);
    reg [255:0] l = 256'h1; always @(posedge clk) l <= {l[254:0], l[255]^l[253]^l[250]^l[245]^din};
    wire ov; wire [63:0] o; reg [63:0] oq; reg p;
    vec3d_unit u(.clk(clk), .in_valid(l[0]), .op(l[4:1]), .sh(l[9:5]), .imm(l[17:10]), .a(l[81:18]), .b(l[145:82]), .out_valid(ov), .out(o));
    always @(posedge clk) begin oq <= o; p <= ^oq ^ ov; end
    assign dout = p;
endmodule
