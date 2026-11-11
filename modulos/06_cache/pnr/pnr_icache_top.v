// Wrapper de medida: cache de INSTRUCOES 4 KB (cache_dm WR=0, IDX=7, STATS=0), we=0, lado CPU/memoria por LFSR, saida = paridade. Nao e o projeto final.
module pnr_icache_top(input wire clk, input wire din, output wire dout);
    reg [3:0] rc = 0; wire rstw; reg [63:0] l = 64'h1; reg [63:0] m = 64'hACE1;
    always @(posedge clk) begin l <= {l[62:0], l[63]^l[62]^l[60]^l[59]^din}; m <= {m[62:0], m[63]^m[61]^m[60]^m[58]}; end
    wire rdy, rv; wire [63:0] rd; wire m_req, m_we, m_done; wire [18:0] m_addr; wire [63:0] m_wd; wire [7:0] m_be; wire [31:0] a,b,c,d;
    cache_dm #(.WR(0), .IDX(7), .STATS(0)) ic(.clk(clk), .rst(rstw), .inv(l[40]&l[41]&l[42]&l[43]&l[44]&l[45]), .req(l[0]), .we(1'b0), .addr(l[21:3]), .wdata(64'd0), .be(8'd0),
        .ready(rdy), .rvalid(rv), .rdata(rd), .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wd), .m_be(m_be),
        .m_accept(m[0]&m[1]), .m_done(m[2]&m_req), .m_rdata(m), .st_rd_hit(a), .st_rd_miss(b), .st_wr(c), .st_wr_hit(d));
    always @(posedge clk) if (rc != 15) rc <= rc + 1; assign rstw = (rc != 15) | (l[50]&l[51]&l[52]&l[53]&l[54]&l[55]&l[56]);
    reg p; always @(posedge clk) p <= ^{rdy, rv, rd, m_req, m_addr};
    assign dout = p;
endmodule
