// mmu.v - R8064 MMU (my assumptions; the spreadsheet only defines PGINV/PROT/JP USER/LDCR/STCR).
//  64-bit virtual addresses, translated to 39 bits (Sv39 style: bits 63:39 = copy of bit 38, otherwise page fault).
//  4 KB page, 2 MB megapage (leaf at level 1), 3 levels, 64-bit PTE:
//    [0]V [1]R [2]W [3]X [4]U [5]G [6]A [7]D [29:10]PPN.  Non-leaf: V=1 and R=W=X=0.  V=0 or (W&&!R) = invalid.
//  Software manages A/D (A=0 or write with D=0 -> fault cause 3). User only accesses U=1; supervisor does not execute U=1.
//  Physical address: 32 byte bits; the memory (cache/SDRAM) is 4 MB (19-bit word index): PPN[19:10]!=0 -> cause 4 (bus).
//  Causes: 1 page fault (invalid/non-canonical/leaf at level 2/misaligned), 2 permission, 3 A/D, 4 outside memory.
//  Fully associative TLB of NENT entries with 8-bit ASID and global bit; replacement: first invalid, otherwise circular.
//  Translation interface: v_req/ready (accepted when v_req&&ready); result p_valid on the next clock if it hits (latency 1),
//  p_valid is a 1-clock pulse (the consumer has to accept it). TLB miss: table walker through the same m_req/m_accept/m_done protocol as the cache.
//  With en=0 the address passes straight through (low 32 bits).
module mmu #(parameter NENT = 16)(
    input  wire        clk, rst,
    input  wire        en, user,
    input  wire [7:0]  asid,
    input  wire [19:0] root_ppn,
    input  wire        fl_all, fl_va_en, fl_asid_en,
    input  wire [63:0] fl_va,
    input  wire [7:0]  fl_asid,
    input  wire        v_req,
    input  wire [63:0] v_addr,
    input  wire [1:0]  v_acc,          // 0 read, 1 write, 2 execute
    output wire        ready,
    output wire        p_valid,
    output wire [31:0] p_addr,
    output wire        p_fault,
    output wire [2:0]  p_cause,
    output reg         m_req,
    output reg  [18:0] m_addr,
    input  wire        m_accept, m_done,
    input  wire [63:0] m_rdata,
    output reg  [31:0] st_hit, st_miss, st_walk, st_fault
);
    // ---------------- TLB
    reg [NENT-1:0] e_v, e_big, e_g, e_r, e_w, e_x, e_u, e_a, e_d;
    reg [7:0]  e_asid [0:NENT-1];
    reg [26:0] e_vpn  [0:NENT-1];
    reg [19:0] e_ppn  [0:NENT-1];
    // ---------------- stage 1
    reg        s1_valid; reg [63:0] s1_addr; reg [1:0] s1_acc; reg s1_user; reg [7:0] s1_asid; reg [19:0] s1_root;
    wire [26:0] s1_vpn = s1_addr[38:12];
    wire canon = (s1_addr[63:39] == {25{s1_addr[38]}});
    reg  [NENT-1:0] mt;
    integer i;
    always @* for (i = 0; i < NENT; i = i + 1)
        mt[i] = e_v[i] && (e_g[i] || e_asid[i] == s1_asid) && (e_vpn[i][26:9] == s1_vpn[26:9]) && (e_big[i] || e_vpn[i][8:0] == s1_vpn[8:0]);
    reg [19:0] h_ppn; reg h_big, h_r, h_w, h_x, h_u, h_a, h_d;
    always @* begin
        h_ppn = 0; h_big = 0; h_r = 0; h_w = 0; h_x = 0; h_u = 0; h_a = 0; h_d = 0;
        for (i = 0; i < NENT; i = i + 1) if (mt[i]) begin
            h_ppn = h_ppn | e_ppn[i]; h_big = h_big | e_big[i]; h_r = h_r | e_r[i]; h_w = h_w | e_w[i]; h_x = h_x | e_x[i]; h_u = h_u | e_u[i]; h_a = h_a | e_a[i]; h_d = h_d | e_d[i];
        end
    end
    wire hit = |mt;
    wire perm_f = (s1_acc == 2'd0 && !h_r) || (s1_acc == 2'd1 && !h_w) || (s1_acc == 2'd2 && !h_x) || (s1_user && !h_u) || (!s1_user && h_u && s1_acc == 2'd2);
    wire ad_f   = !h_a || (s1_acc == 2'd1 && !h_d);
    // ---------------- walker
    localparam [1:0] W_IDLE = 0, W_REQ = 1, W_WAIT = 2;
    reg [1:0] ws; reg [1:0] lvl; reg restart; reg wf_valid; reg [2:0] wf_cause;
    wire flush_any = fl_all | fl_va_en | fl_asid_en;
    wire resolved = !en || !canon || hit || wf_valid;
    assign p_valid = s1_valid && resolved;
    assign ready   = !s1_valid || p_valid;
    wire accept    = v_req && ready;
    wire tl_fault  = en && canon && hit && (perm_f || ad_f);
    assign p_fault = s1_valid && en && (!canon || wf_valid || tl_fault);
    assign p_cause = !canon ? 3'd1 : wf_valid ? wf_cause : perm_f ? 3'd2 : 3'd3;
    assign p_addr  = !en ? s1_addr[31:0] : h_big ? {h_ppn[19:9], s1_addr[20:0]} : {h_ppn, s1_addr[11:0]};
    wire need_walk = s1_valid && en && canon && !hit && !wf_valid;
    // PTE recebido
    wire [63:0] pte = m_rdata;
    wire pv = pte[0], pr = pte[1], pw = pte[2], px = pte[3];
    wire leaf = pr | pw | px;
    wire [19:0] pppn = pte[29:10];
    wire [8:0] vpn_l = (lvl == 2'd2) ? s1_addr[38:30] : (lvl == 2'd1) ? s1_addr[29:21] : s1_addr[20:12];
    wire [8:0] vpn_n = (lvl == 2'd2) ? s1_addr[29:21] : s1_addr[20:12];   // index of the next level
    // vitima
    reg [$clog2(NENT)-1:0] rr, vic; reg anyfree;
    always @* begin
        vic = rr; anyfree = 0;
        for (i = NENT - 1; i >= 0; i = i - 1) if (!e_v[i]) begin vic = i; anyfree = 1; end
    end
    reg walk_done_ok;
    always @(posedge clk) begin
        m_req <= m_req & ~m_accept;
        if (rst) begin
            s1_valid <= 0; e_v <= 0; ws <= W_IDLE; restart <= 0; wf_valid <= 0; m_req <= 0; rr <= 0;
            st_hit <= 0; st_miss <= 0; st_walk <= 0; st_fault <= 0; lvl <= 0; wf_cause <= 0;
        end else begin
            // ---- stage 1
            if (accept) begin s1_valid <= 1; s1_addr <= v_addr; s1_acc <= v_acc; s1_user <= user; s1_asid <= asid; s1_root <= root_ppn; wf_valid <= 0; end
            else if (p_valid) begin s1_valid <= 0; wf_valid <= 0; end
            if (p_valid) begin
                if (en && canon && hit) st_hit <= st_hit + 1;
                if (p_fault) st_fault <= st_fault + 1;
            end
            // ---- flush
            if (fl_all) e_v <= 0;
            for (i = 0; i < NENT; i = i + 1) begin
                if (fl_va_en && e_vpn[i][26:9] == fl_va[38:21] && (e_big[i] || e_vpn[i][8:0] == fl_va[20:12])) e_v[i] <= 0;
                if (fl_asid_en && !e_g[i] && e_asid[i] == fl_asid) e_v[i] <= 0;
            end
            if (flush_any && ws != W_IDLE) restart <= 1;
            // ---- walker
            case (ws)
                W_IDLE: if (need_walk && !(accept)) begin
                    st_miss <= st_miss + 1; st_walk <= st_walk + 1; lvl <= 2'd2; restart <= 0;
                    if (s1_root[19:10] != 0) begin wf_valid <= 1; wf_cause <= 3'd4; end
                    else begin ws <= W_REQ; m_req <= 1; m_addr <= {s1_root[9:0], s1_addr[38:30]}; end
                end
                W_REQ: if (m_accept) ws <= W_WAIT;
                W_WAIT: if (m_done) begin
                    if (restart || flush_any) begin   // tabelas podem ter mudado: recomeca
                        restart <= 0; lvl <= 2'd2;
                        if (s1_root[19:10] != 0) begin wf_valid <= 1; wf_cause <= 3'd4; ws <= W_IDLE; end
                        else begin ws <= W_REQ; m_req <= 1; m_addr <= {s1_root[9:0], s1_addr[38:30]}; end
                    end else if (!pv || (pw && !pr)) begin wf_valid <= 1; wf_cause <= 3'd1; ws <= W_IDLE; end
                    else if (leaf) begin
                        if (lvl == 2'd2 || (lvl == 2'd1 && pppn[8:0] != 0)) begin wf_valid <= 1; wf_cause <= 3'd1; ws <= W_IDLE; end
                        else if (pppn[19:10] != 0) begin wf_valid <= 1; wf_cause <= 3'd4; ws <= W_IDLE; end
                        else begin   // instala
                            e_v[vic] <= 1; e_big[vic] <= (lvl == 2'd1); e_g[vic] <= pte[5]; e_r[vic] <= pr; e_w[vic] <= pw; e_x[vic] <= px; e_u[vic] <= pte[4]; e_a[vic] <= pte[6]; e_d[vic] <= pte[7];
                            e_asid[vic] <= s1_asid; e_vpn[vic] <= s1_vpn; e_ppn[vic] <= pppn; if (!anyfree) rr <= rr + 1; ws <= W_IDLE;
                        end
                    end else begin
                        if (lvl == 2'd0) begin wf_valid <= 1; wf_cause <= 3'd1; ws <= W_IDLE; end
                        else if (pppn[19:10] != 0) begin wf_valid <= 1; wf_cause <= 3'd4; ws <= W_IDLE; end
                        else begin lvl <= lvl - 1; ws <= W_REQ; m_req <= 1; m_addr <= {pppn[9:0], vpn_n}; end
                    end
                end
                default: ws <= W_IDLE;
            endcase
        end
    end
endmodule
