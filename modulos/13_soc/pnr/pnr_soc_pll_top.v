// Test top: clkgen (rPLL) + pnr_soc_top. SRC: 0 = board 27 MHz, 1 = external 3.579545 MHz (x16), 2 = 57.27 MHz direct.
module pnr_soc_pll_top #(parameter SRC = 1)(input wire clk_in, input wire din, output wire dout);
    wire clk_g, lk, rst_g;
    r8064_clkgen #(.SRC(SRC)) u_clk(.clk_in(clk_in), .rst_in(1'b0), .clk(clk_g), .locked(lk), .rst(rst_g));
    pnr_soc_top u_top(.clk(clk_g), .din(din), .dout(dout));
endmodule
