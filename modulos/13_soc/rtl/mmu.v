// mmu.v - R8064 MMU (my assumptions; the spreadsheet only defines PGINV/PROT/JP USER/LDCR/STCR).
//  64-bit virtual addresses, translated to 39 bits (Sv39 style: bits 63:39 = copy of bit 38, otherwise page fault).
//  4 KB page, 2 MB megapage (leaf at level 1), 3 levels, 64-bit PTE:
//    [0]V [1]R [2]W [3]X [4]U [5]G [6]A [7]D [29:10]PPN.  Non-leaf: V=1 and R=W=X=0.  V=0 or (W&&!R) = invalid.
//  Software manages A/D (A=0 or write with D=0 -> fault cause 3). User only accesses U=1; supervisor does not execute U=1.
//  Physical address: 32 byte bits; the memory (cache/SDRAM) has 8 MB (20-bit word index): PPN[19:11]!=0 -> cause 4 (bus).
//  Causes: 1 page fault (invalid/non-canonical/leaf at level 2/misaligned), 2 permission, 3 A/D, 4 outside memory.
//  Fully associative TLB of NENT entries with 8-bit ASID and global bit; replacement: first invalid, otherwise circular.
//  Translation interface: v_req/ready (accepted when v_req&&ready); 2 stages (1: compare all entries -> vector mt2; 2: selection+permissions), 1 translation per clock; hit latency = 2 clocks;
//  p_valid is a 1-clock pulse (the consumer has to accept it). TLB miss: table walker through the same m_req/m_accept/m_done protocol as the cache.
//  With en=0 the address passes straight through (low 32 bits).
module mmu #(parameter NENT = 16, parameter STATS = 1)(
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
    output wire        fl_busy,           // flush sweep by VA/ASID in progress (NENT clocks); do not issue another flush or translation
    output wire        p_valid,
    output wire [31:0] p_addr,
    output wire        p_fault,
    output wire [2:0]  p_cause,
    output reg         m_req,
    output reg  [19:0] m_addr,
    input  wire        m_accept, m_done,
    input  wire [63:0] m_rdata,
    output reg  [31:0] st_hit, st_miss, st_walk, st_fault
);
    // ---------------- TLB
    reg [NENT-1:0] e_v, e_big, e_g, e_r, e_w, e_x, e_u, e_a, e_d;
    reg [7:0]  e_asid [0:NENT-1];
    reg [26:0] e_vpn  [0:NENT-1];
    reg [19:0] e_ppn  [0:NENT-1];
    // ---------------- stage 1 (registers the request) and stage 2 (registered hit vector)
    reg        s1_valid, s1_en; reg [63:0] s1_addr; reg [1:0] s1_acc; reg s1_user; reg [7:0] s1_asid; reg [19:0] s1_root;
    reg        s2_valid, s2_en, s2_canon, s2_stale; reg [63:0] s2_addr; reg [1:0] s2_acc; reg s2_user; reg [7:0] s2_asid; reg [19:0] s2_root; reg [NENT-1:0] mt2;
    wire [26:0] s1_vpn = s1_addr[38:12];
    wire [26:0] s2_vpn = s2_addr[38:12];
    wire canon1 = (s1_addr[63:39] == {25{s1_addr[38]}});
    reg  [NENT-1:0] mt1;
    integer i;
    always @* for (i = 0; i < NENT; i = i + 1)
        mt1[i] = e_v[i] && (e_g[i] || e_asid[i] == s1_asid) && (e_vpn[i][26:9] == s1_vpn[26:9]) && (e_big[i] || e_vpn[i][8:0] == s1_vpn[8:0]);
    reg [19:0] h_ppn; reg h_big, h_r, h_w, h_x, h_u, h_a, h_d;
    always @* begin
        h_ppn = 0; h_big = 0; h_r = 0; h_w = 0; h_x = 0; h_u = 0; h_a = 0; h_d = 0;
        for (i = 0; i < NENT; i = i + 1) if (mt2[i]) begin
            h_ppn = h_ppn | e_ppn[i]; h_big = h_big | e_big[i]; h_r = h_r | e_r[i]; h_w = h_w | e_w[i]; h_x = h_x | e_x[i]; h_u = h_u | e_u[i]; h_a = h_a | e_a[i]; h_d = h_d | e_d[i];
        end
    end
    wire hit = (|mt2) && !s2_stale;
    wire perm_f = (s2_acc == 2'd0 && !h_r) || (s2_acc == 2'd1 && !h_w) || (s2_acc == 2'd2 && !h_x) || (s2_user && !h_u) || (!s2_user && h_u && s2_acc == 2'd2);
    wire ad_f   = !h_a || (s2_acc == 2'd1 && !h_d);
    // ---------------- walker
    localparam [1:0] W_IDLE = 0, W_REQ = 1, W_WAIT = 2;
    reg [1:0] ws; reg [1:0] lvl; reg restart; reg wf_valid; reg [2:0] wf_cause;
    wire flush_any = fl_all | fl_va_en | fl_asid_en;
    // flush by VA/ASID: sequential sweep of 1 entry per clock (a single comparator instead of 2 per entry)
    reg fs_busy, fs_va, fs_asidf; reg [26:0] fs_vpn; reg [7:0] fs_asid; reg [$clog2(NENT):0] fs_i;
    assign fl_busy = fs_busy;
    wire [$clog2(NENT)-1:0] fs_ix = fs_i[$clog2(NENT)-1:0];
    wire [26:0] fs_evpn = e_vpn[fs_ix]; wire [7:0] fs_easid = e_asid[fs_ix];
    wire fs_hit_va   = fs_va && (fs_evpn[26:9] == fs_vpn[26:9]) && (e_big[fs_ix] || fs_evpn[8:0] == fs_vpn[8:0]);
    wire fs_hit_asid = fs_asidf && !e_g[fs_ix] && (fs_easid == fs_asid);
    wire resolved = !s2_en || !s2_canon || hit || wf_valid;
    assign p_valid = s2_valid && resolved;
    wire adv       = s1_valid && (!s2_valid || p_valid);          // stage 1 -> stage 2
    assign ready   = (!s1_valid || !s2_valid || p_valid) && !fs_busy;
    wire accept    = v_req && ready;
    wire tl_fault  = s2_en && s2_canon && hit && (perm_f || ad_f);
    assign p_fault = s2_valid && s2_en && (!s2_canon || wf_valid || tl_fault);
    assign p_cause = !s2_canon ? 3'd1 : wf_valid ? wf_cause : perm_f ? 3'd2 : 3'd3;
    assign p_addr  = !s2_en ? s2_addr[31:0] : h_big ? {h_ppn[19:9], s2_addr[20:0]} : {h_ppn, s2_addr[11:0]};
    wire need_walk = s2_valid && s2_en && s2_canon && !hit && !wf_valid;
    // PTE received
    wire [63:0] pte = m_rdata;
    wire pv = pte[0], pr = pte[1], pw = pte[2], px = pte[3];
    wire leaf = pr | pw | px;
    wire [19:0] pppn = pte[29:10];
    wire [8:0] vpn_n = (lvl == 2'd2) ? s2_addr[29:21] : s2_addr[20:12];   // index of the next level
    // victim
    reg [$clog2(NENT)-1:0] rr, vic; reg anyfree;
    always @* begin
        vic = rr; anyfree = 0;
        for (i = NENT - 1; i >= 0; i = i - 1) if (!e_v[i]) begin vic = i; anyfree = 1; end
    end
    reg walk_done_ok;
    always @(posedge clk) begin
        m_req <= m_req & ~m_accept;
        if (rst) begin
            s1_valid <= 0; s2_valid <= 0; s2_stale <= 0; e_v <= 0; fs_busy <= 0; fs_i <= 0; ws <= W_IDLE; restart <= 0; wf_valid <= 0; m_req <= 0; rr <= 0;
            st_hit <= 0; st_miss <= 0; st_walk <= 0; st_fault <= 0; lvl <= 0; wf_cause <= 0;
        end else begin
            // ---- stage 1
            if (accept) begin s1_valid <= 1; s1_en <= en; s1_addr <= v_addr; s1_acc <= v_acc; s1_user <= user; s1_asid <= asid; s1_root <= root_ppn; end
            else if (adv) s1_valid <= 0;
            if (adv) begin s2_valid <= 1; s2_en <= s1_en; s2_canon <= canon1; s2_addr <= s1_addr; s2_acc <= s1_acc; s2_user <= s1_user; s2_asid <= s1_asid; s2_root <= s1_root; mt2 <= mt1; s2_stale <= 0; wf_valid <= 0; end
            else if (p_valid) begin s2_valid <= 0; wf_valid <= 0; end
            if (flush_any && (s2_valid || adv)) s2_stale <= 1;
            if (p_valid) begin
                if (s2_en && s2_canon && hit) if (STATS) st_hit <= st_hit + 1;
                if (p_fault) if (STATS) st_fault <= st_fault + 1;
            end
            // ---- flush
            if (fl_all) e_v <= 0;
            if ((fl_va_en || fl_asid_en) && !fs_busy) begin fs_busy <= 1; fs_i <= 0; fs_va <= fl_va_en; fs_asidf <= fl_asid_en; fs_vpn <= fl_va[38:12]; fs_asid <= fl_asid; end
            else if (fs_busy) begin
                if (e_v[fs_ix] && (fs_hit_va || fs_hit_asid)) e_v[fs_ix] <= 0;
                fs_i <= fs_i + 1; if (fs_i == NENT - 1) fs_busy <= 0;
            end
            if (flush_any && ws != W_IDLE) restart <= 1;
            // ---- walker
            case (ws)
                W_IDLE: if (need_walk && !(accept)) begin
                    if (STATS) begin st_miss <= st_miss + 1; st_walk <= st_walk + 1; end lvl <= 2'd2; restart <= 0;
                    if (s2_root[19:11] != 0) begin wf_valid <= 1; wf_cause <= 3'd4; end
                    else begin ws <= W_REQ; m_req <= 1; m_addr <= {s2_root[10:0], s2_addr[38:30]}; end
                end
                W_REQ: if (m_accept) ws <= W_WAIT;
                W_WAIT: if (m_done) begin
                    if (restart || flush_any) begin   // the tables may have changed: restart
                        restart <= 0; lvl <= 2'd2;
                        if (s2_root[19:11] != 0) begin wf_valid <= 1; wf_cause <= 3'd4; ws <= W_IDLE; end
                        else begin ws <= W_REQ; m_req <= 1; m_addr <= {s2_root[10:0], s2_addr[38:30]}; end
                    end else if (!pv || (pw && !pr)) begin wf_valid <= 1; wf_cause <= 3'd1; ws <= W_IDLE; end
                    else if (leaf) begin
                        if (lvl == 2'd2 || (lvl == 2'd1 && pppn[8:0] != 0)) begin wf_valid <= 1; wf_cause <= 3'd1; ws <= W_IDLE; end
                        else if (pppn[19:11] != 0) begin wf_valid <= 1; wf_cause <= 3'd4; ws <= W_IDLE; end
                        else begin   // install
                            e_v[vic] <= 1; e_big[vic] <= (lvl == 2'd1); e_g[vic] <= pte[5]; e_r[vic] <= pr; e_w[vic] <= pw; e_x[vic] <= px; e_u[vic] <= pte[4]; e_a[vic] <= pte[6]; e_d[vic] <= pte[7];
                            e_asid[vic] <= s2_asid; e_vpn[vic] <= s2_vpn; mt2 <= ({{(NENT-1){1'b0}}, 1'b1} << vic); s2_stale <= 0; e_ppn[vic] <= pppn; if (!anyfree) rr <= rr + 1; ws <= W_IDLE;
                        end
                    end else begin
                        if (lvl == 2'd0) begin wf_valid <= 1; wf_cause <= 3'd1; ws <= W_IDLE; end
                        else if (pppn[19:11] != 0) begin wf_valid <= 1; wf_cause <= 3'd4; ws <= W_IDLE; end
                        else begin lvl <= lvl - 1; ws <= W_REQ; m_req <= 1; m_addr <= {pppn[10:0], vpn_n}; end
                    end
                end
                default: ws <= W_IDLE;
            endcase
        end
    end
endmodule
