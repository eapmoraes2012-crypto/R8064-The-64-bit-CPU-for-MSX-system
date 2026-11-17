module pnr_mem_top(input wire clk, input wire din, output wire dout);
    reg [255:0] l = 256'h1; reg [3:0] rc = 0; wire rstw = (rc != 15);
    always @(posedge clk) begin if (rc != 15) rc <= rc + 1; l <= {l[254:0], l[255]^l[253]^l[250]^l[245]^din}; end
    wire c_i_ack, c_d_ack, fbi, fbd, i_fault, d_fault, init_done; wire [63:0] c_i_rd, c_d_rd; wire [2:0] ic, dc;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o;
    // core requests: the request is only held until the ack (as the core does)
    reg ireq = 0, dreq = 0;
    always @(posedge clk) begin ireq <= c_i_ack ? 1'b0 : (ireq | l[3]); dreq <= c_d_ack ? 1'b0 : (dreq | l[5]); end
    r8064_memsys u(.clk(clk), .rst(rstw),
        .c_i_req(ireq), .c_i_ack(c_i_ack), .c_i_pa(l[63:0]), .c_i_rd(c_i_rd),
        .c_d_req(dreq), .c_d_we(l[6]), .c_d_ack(c_d_ack), .c_d_pa(l[127:64]), .c_d_wd(l[191:128] ^ l[63:0]), .c_d_be(l[199:192]), .c_d_rd(c_d_rd),
        .mmu_en(l[172]), .mmu_user(l[173]), .mmu_asid(l[181:174]), .mmu_root(l[201:182]), .fl_all(l[202]), .fl_va_en(l[203]), .fl_asid_en(l[204]), .fl_va(l[127:64] ^ l[255:192]), .fl_asid(l[212:205]), .fl_busy_i(fbi), .fl_busy_d(fbd),
        .cache_inv(l[213]), .i_fault(i_fault), .d_fault(d_fault), .i_cause(ic), .d_cause(dc),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a), .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(l[245:214]));
    reg [4:0] pp; reg p;
    always @(posedge clk) begin
        pp <= {^{c_i_ack, c_d_ack, fbi, fbd, i_fault, d_fault, ic, dc, init_done}, ^c_i_rd[63:32], ^c_i_rd[31:0], ^c_d_rd, ^{s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dqm, s_ba, s_dq_oe, s_a, s_dq_o}};
        p <= ^pp;
    end
    assign dout = p;
endmodule
