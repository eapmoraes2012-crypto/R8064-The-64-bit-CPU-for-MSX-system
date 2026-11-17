// cache8k.v - 8 KB cache, 2 ways, 32 B line (4 64-bit words), in BSRAM; write-through with write buffer, no write allocate.
//   WR=0: instruction cache (read only).  WR=1: data cache (writes by byte-enable).
// CPU interface: req/ready (accepted when req && ready); read: rvalid+rdata on the SAME clock after acceptance if it hits (hit latency = 1 clock; 1 access per clock);
//   write: posted into the buffer (WBD entries), 1 bubble after each write. Read miss: fills the line (4 64-bit reads) and repeats the access.
// Memory interface (via arbiter): m_req held until m_accept; then waits for m_done (rvalid or wdone).
// Address: 64-bit word index (19 bits = 4 MB): tag [18:9], set [8:2], word in line [1:0].
module cache8k #(parameter WR = 1, parameter WBD = 4)(
    input  wire        clk, rst, inv,
    input  wire        req, we,
    input  wire [18:0] addr,
    input  wire [63:0] wdata,
    input  wire [7:0]  be,
    output wire        ready,
    output wire        rvalid,
    output wire [63:0] rdata,
    output reg         m_req, m_we,
    output reg  [18:0] m_addr,
    output reg  [63:0] m_wdata,
    output reg  [7:0]  m_be,
    input  wire        m_accept, m_done,
    input  wire [63:0] m_rdata,
    output reg  [31:0] st_rd_hit, st_rd_miss, st_wr, st_wr_hit
);
    // ---------------- arrays
    reg [63:0] d0 [0:511]; reg [63:0] d1 [0:511]; reg [9:0] t0 [0:127]; reg [9:0] t1 [0:127];
    reg [127:0] v0, v1, lru;
    // stage 1
    reg        s1_valid, s1_ok, s1_we; reg [18:0] s1_addr; reg [63:0] s1_wd; reg [7:0] s1_be;
    wire [9:0] s1_tag = s1_addr[18:9]; wire [6:0] s1_set = s1_addr[8:2];
    wire       accept;
    wire [8:0] ra = accept ? addr[8:0] : s1_addr[8:0];
    wire [6:0] sa = addr[8:2], sb = s1_addr[8:2];
    wire [9:0] t0_a = t0[sa], t0_b = t0[sb], t1_a = t1[sa], t1_b = t1[sb]; wire v0_a = v0[sa], v0_b = v0[sb], v1_a = v1[sa], v1_b = v1[sb];
    reg [63:0] qd0, qd1; reg hit0, hit1;
    always @(posedge clk) begin
        qd0 <= d0[ra]; qd1 <= d1[ra];
        // tags and valids: read BOTH candidates (new address and that of stage 1) and choose afterwards, to take ready->accept off the 128:1 mux path
        // the tag compare is also done before the register: stage 1 only receives already-registered hit0/hit1 (ready stays shallow)
        hit0 <= accept ? (v0_a && t0_a == addr[18:9]) : (v0_b && t0_b == s1_tag);
        hit1 <= accept ? (v1_a && t1_a == addr[18:9]) : (v1_b && t1_b == s1_tag);
    end
    wire hit = hit0 | hit1;
    wire [63:0] hword = hit0 ? qd0 : qd1;
    // write buffer
    reg [18:0] wb_a [0:WBD-1]; reg [63:0] wb_d [0:WBD-1]; reg [7:0] wb_b [0:WBD-1]; reg [3:0] wb_cnt; reg [1:0] wb_rp, wb_wp;
    wire wb_space = (WR != 0) && (wb_cnt < WBD);
    // miss state
    localparam [2:0] F_NORMAL = 0, F_WAIT = 1, F_REQ = 2, F_RD = 3, F_TAG = 4;
    reg [2:0] fs; reg [1:0] fk; reg fvict;
    reg ds; // 0 = drain idle, 1 = write in progress (waiting for accept/completion)
    reg ds_acc;
    wire evalu = s1_valid && s1_ok && (fs == F_NORMAL);
    wire rd_hit  = evalu && !s1_we && hit;
    wire rd_miss = evalu && !s1_we && !hit;
    wire wr_done = evalu && s1_we && wb_space;
    assign ready  = !s1_valid || rd_hit;
    assign accept = req && ready;
    assign rvalid = rd_hit;
    assign rdata  = hword;
    // word merged for write with byte-enable
    wire [63:0] mrg = {be_m(s1_be[7], hword[63:56], s1_wd[63:56]), be_m(s1_be[6], hword[55:48], s1_wd[55:48]), be_m(s1_be[5], hword[47:40], s1_wd[47:40]), be_m(s1_be[4], hword[39:32], s1_wd[39:32]),
                       be_m(s1_be[3], hword[31:24], s1_wd[31:24]), be_m(s1_be[2], hword[23:16], s1_wd[23:16]), be_m(s1_be[1], hword[15:8],  s1_wd[15:8]),  be_m(s1_be[0], hword[7:0],   s1_wd[7:0])};
    function [7:0] be_m(input b, input [7:0] o, input [7:0] n); be_m = b ? n : o; endfunction
    // write into the arrays (single port per array)
    wire        wr_hit_upd = wr_done && hit;
    wire        fill_wr    = (fs == F_RD) && m_done;
    wire        d0_we = (wr_hit_upd && hit0) || (fill_wr && !fvict);
    wire        d1_we = (wr_hit_upd && !hit0 && hit1) || (fill_wr && fvict);
    wire [8:0]  d_wa = fill_wr ? {s1_set, fk} : s1_addr[8:0];
    wire [63:0] d_wd = fill_wr ? m_rdata : mrg;
    always @(posedge clk) begin
        if (d0_we) d0[d_wa] <= d_wd;
        if (d1_we) d1[d_wa] <= d_wd;
        if (fs == F_TAG) begin if (!fvict) t0[s1_set] <= s1_tag; else t1[s1_set] <= s1_tag; end
    end
    wire victim_sel = !v0[s1_set] ? 1'b0 : !v1[s1_set] ? 1'b1 : lru[s1_set];
    integer i;
    always @(posedge clk) begin
        m_req <= m_req & ~m_accept;
        if (rst) begin
            s1_valid <= 0; s1_ok <= 0; fs <= F_NORMAL; ds <= 0; ds_acc <= 0; wb_cnt <= 0; wb_rp <= 0; wb_wp <= 0; v0 <= 0; v1 <= 0; lru <= 0; m_req <= 0; m_we <= 0;
            st_rd_hit <= 0; st_rd_miss <= 0; st_wr <= 0; st_wr_hit <= 0; fk <= 0; fvict <= 0;
        end else begin
            if (inv) begin v0 <= 0; v1 <= 0; end
            // ---- stage 1
            if (accept) begin s1_valid <= 1; s1_ok <= 1; s1_we <= we; s1_addr <= addr; s1_wd <= wdata; s1_be <= be; end
            else if (rd_hit || wr_done) s1_valid <= 0;
            if (rd_hit) begin st_rd_hit <= st_rd_hit + 1; lru[s1_set] <= hit0; end
            if (wr_done) begin
                st_wr <= st_wr + 1; if (hit) begin st_wr_hit <= st_wr_hit + 1; lru[s1_set] <= hit0; end
                wb_a[wb_wp] <= s1_addr; wb_d[wb_wp] <= s1_wd; wb_b[wb_wp] <= s1_be; wb_wp <= wb_wp + 1;
            end
            // ---- read miss: fill
            case (fs)
                F_NORMAL: if (rd_miss) begin st_rd_miss <= st_rd_miss + 1; s1_ok <= 0; fs <= F_WAIT; fk <= 0; fvict <= victim_sel; end
                F_WAIT: if (wb_cnt == 0 && ds == 0 && !m_req) begin
                    m_req <= 1; m_we <= 0; m_addr <= {s1_addr[18:2], fk}; fs <= F_RD;
                end
                F_RD: if (m_done) begin
                    if (fk == 2'd3) fs <= F_TAG;
                    else begin fk <= fk + 1; m_req <= 1; m_we <= 0; m_addr <= {s1_addr[18:2], fk + 2'd1}; end
                end
                F_TAG: begin
                    if (!fvict) v0[s1_set] <= 1; else v1[s1_set] <= 1;
                    lru[s1_set] <= ~fvict; fs <= F_NORMAL; s1_ok <= 0;   // one wait clock: re-read s1_addr
                end
                default: fs <= F_NORMAL;
            endcase
            if (fs == F_NORMAL && s1_valid && !s1_ok && !rd_miss && !wr_done) s1_ok <= 1;   // data re-read
            // ---- write buffer drain (only when no fill is in progress)
            if (WR != 0) begin
                if (ds == 0 && wb_cnt != 0 && !m_req && (fs == F_NORMAL || fs == F_WAIT)) begin
                    m_req <= 1; m_we <= 1; m_addr <= wb_a[wb_rp]; m_wdata <= wb_d[wb_rp]; m_be <= wb_b[wb_rp]; ds <= 1;
                end else if (ds == 1 && m_done) begin
                    ds <= 0; wb_rp <= wb_rp + 1;
                end
                wb_cnt <= wb_cnt + (wr_done ? 1 : 0) - ((ds == 1 && m_done) ? 1 : 0);
            end
        end
    end
endmodule
