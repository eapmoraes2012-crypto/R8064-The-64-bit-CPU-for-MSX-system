// Topo de teste: clkgen (rPLL) + pnr_soc_top. SRC: 0 = 27 MHz da placa, 1 = 3,579545 MHz externo (x16), 2 = 57,27 MHz direto.
module pnr_soc_pll_top #(parameter SRC = 1)(input wire clk_in, input wire din, output wire dout);
    wire clk_g, lk, rst_g;
    r8064_clkgen #(.SRC(SRC)) u_clk(.clk_in(clk_in), .rst_in(1'b0), .clk(clk_g), .locked(lk), .rst(rst_g));
    pnr_soc_top u_top(.clk(clk_g), .din(din), .dout(dout));
endmodule
