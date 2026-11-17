// Wrapper ONLY to measure area/timing of the SDRAM controller (LFSR inputs, outputs reduced to 1 bit). Not the final design.
module pnr_sdram_top(input clk, input din, output dout);
    reg [127:0] l = 128'h1357_9BDF_0246_8ACE_FEDC_BA98_7654_3211; always @(posedge clk) l <= {l[126:0], l[127] ^ l[126] ^ l[125] ^ l[120] ^ din};
    wire ready, rvalid, wdone, init_done, s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [63:0] rdata; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o;
    sdram_ctrl u(.clk(clk), .rst(1'b0), .req(l[0] & l[1]), .we(l[2]), .addr(l[40:22]), .wdata(l[127:64]), .be(l[60:53]), .ready(ready), .rvalid(rvalid), .rdata(rdata), .wdone(wdone), .init_done(init_done),
        .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a), .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(l[95:64]));
    reg pp = 0; always @(posedge clk) pp <= ^{ready, rvalid, wdone, init_done, s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe, rdata, s_dqm, s_ba, s_a, s_dq_o};
    assign dout = pp;
endmodule
