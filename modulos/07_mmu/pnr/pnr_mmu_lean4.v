// Wrapper de P&R da MMU: entradas por LFSR, saida = paridade (nao e o projeto final).
module pnr_mmu_top(input wire clk, input wire din, output wire dout);
    reg [63:0] l = 64'h1, m = 64'hACE1; reg [3:0] rc = 0; wire rstw = (rc != 15);
    always @(posedge clk) begin if (rc != 15) rc <= rc + 1; l <= {l[62:0], l[63]^l[62]^l[60]^l[59]^din}; m <= {m[62:0], m[63]^m[61]^m[60]^m[58]}; end
    wire ready, pv, pf, fb; wire [31:0] pa; wire [2:0] pc; wire mreq; wire [18:0] ma; wire [31:0] a, b, c, d;
    mmu #(.NENT(4), .STATS(0)) u(.clk(clk), .rst(rstw), .en(1'b1), .user(l[3]), .asid(l[11:4]), .root_ppn(m[19:0]), .fl_all(&l[40:34]), .fl_va_en(&l[44:41]), .fl_asid_en(&l[48:45]), .fl_va(m), .fl_asid(l[20:13]),
        .v_req(l[0]), .v_addr(l ^ {m[31:0], m[63:32]}), .v_acc(l[2:1]), .ready(ready), .fl_busy(fb), .p_valid(pv), .p_addr(pa), .p_fault(pf), .p_cause(pc),
        .m_req(mreq), .m_addr(ma), .m_accept(m[40] & m[41]), .m_done(m[42] & m[43] & mreq), .m_rdata(m ^ l), .st_hit(a), .st_miss(b), .st_walk(c), .st_fault(d));
    reg [31:0] pa_r; reg pv_r, pf_r, rd_r; reg [2:0] pc_r; always @(posedge clk) begin pa_r <= pa; pv_r <= pv; pf_r <= pf; pc_r <= pc; rd_r <= ready; end
    reg p; always @(posedge clk) p <= ^{fb, rd_r, pv_r, pf_r, pa_r, pc_r, mreq, ma, a, b, c, d};
    assign dout = p;
endmodule
