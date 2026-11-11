// cache8k.v - cache de 8 KB, 2 vias, linha de 32 B (4 palavras de 64 bits), em BSRAM; escrita direta (write-through) com buffer de escrita, sem alocar na escrita.
//   WR=0: cache de instrucoes (so leitura).  WR=1: cache de dados (escritas por byte-enable).
// Interface com a CPU: req/ready (aceito quando req && ready); leitura: rvalid+rdata na MESMA clock seguinte ao aceite se acertar (latencia de acerto = 1 clock; 1 acesso por clock);
//   escrita: postada no buffer (WBD entradas), 1 bolha apos cada escrita. Falha de leitura: preenche a linha (4 leituras de 64 bits) e repete o acesso.
// Interface com a memoria (via arbitro): m_req mantido ate m_accept; depois espera m_done (rvalid ou wdone).
// Endereco: indice de palavra de 64 bits (19 bits = 4 MB): tag [18:9], conjunto [8:2], palavra na linha [1:0].
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
    // ---------------- arranjos
    reg [63:0] d0 [0:511]; reg [63:0] d1 [0:511]; reg [9:0] t0 [0:127]; reg [9:0] t1 [0:127];
    reg [127:0] v0, v1, lru;
    // estagio 1
    reg        s1_valid, s1_ok, s1_we; reg [18:0] s1_addr; reg [63:0] s1_wd; reg [7:0] s1_be;
    wire [9:0] s1_tag = s1_addr[18:9]; wire [6:0] s1_set = s1_addr[8:2];
    wire       accept;
    wire [8:0] ra = accept ? addr[8:0] : s1_addr[8:0];
    wire [6:0] sa = addr[8:2], sb = s1_addr[8:2];
    wire [9:0] t0_a = t0[sa], t0_b = t0[sb], t1_a = t1[sa], t1_b = t1[sb]; wire v0_a = v0[sa], v0_b = v0[sb], v1_a = v1[sa], v1_b = v1[sb];
    reg [63:0] qd0, qd1; reg hit0, hit1;
    always @(posedge clk) begin
        qd0 <= d0[ra]; qd1 <= d1[ra];
        // tags e validos: leem os DOIS candidatos (endereco novo e o do estagio 1) e escolhem depois, para tirar ready->accept do caminho do mux 128:1
        // a comparacao de tag tambem e feita antes do registrador: o estagio 1 so recebe hit0/hit1 ja registrados (ready fica rasa)
        hit0 <= accept ? (v0_a && t0_a == addr[18:9]) : (v0_b && t0_b == s1_tag);
        hit1 <= accept ? (v1_a && t1_a == addr[18:9]) : (v1_b && t1_b == s1_tag);
    end
    wire hit = hit0 | hit1;
    wire [63:0] hword = hit0 ? qd0 : qd1;
    // buffer de escrita
    reg [18:0] wb_a [0:WBD-1]; reg [63:0] wb_d [0:WBD-1]; reg [7:0] wb_b [0:WBD-1]; reg [3:0] wb_cnt; reg [1:0] wb_rp, wb_wp;
    wire wb_space = (WR != 0) && (wb_cnt < WBD);
    // estado de falha
    localparam [2:0] F_NORMAL = 0, F_WAIT = 1, F_REQ = 2, F_RD = 3, F_TAG = 4;
    reg [2:0] fs; reg [1:0] fk; reg fvict;
    reg ds; // 0 = dreno ocioso, 1 = escrita em andamento (aguardando aceite/termino)
    reg ds_acc;
    wire evalu = s1_valid && s1_ok && (fs == F_NORMAL);
    wire rd_hit  = evalu && !s1_we && hit;
    wire rd_miss = evalu && !s1_we && !hit;
    wire wr_done = evalu && s1_we && wb_space;
    assign ready  = !s1_valid || rd_hit;
    assign accept = req && ready;
    assign rvalid = rd_hit;
    assign rdata  = hword;
    // palavra mesclada para escrita com byte-enable
    wire [63:0] mrg = {be_m(s1_be[7], hword[63:56], s1_wd[63:56]), be_m(s1_be[6], hword[55:48], s1_wd[55:48]), be_m(s1_be[5], hword[47:40], s1_wd[47:40]), be_m(s1_be[4], hword[39:32], s1_wd[39:32]),
                       be_m(s1_be[3], hword[31:24], s1_wd[31:24]), be_m(s1_be[2], hword[23:16], s1_wd[23:16]), be_m(s1_be[1], hword[15:8],  s1_wd[15:8]),  be_m(s1_be[0], hword[7:0],   s1_wd[7:0])};
    function [7:0] be_m(input b, input [7:0] o, input [7:0] n); be_m = b ? n : o; endfunction
    // escrita nos arranjos (porta unica por arranjo)
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
            // ---- estagio 1
            if (accept) begin s1_valid <= 1; s1_ok <= 1; s1_we <= we; s1_addr <= addr; s1_wd <= wdata; s1_be <= be; end
            else if (rd_hit || wr_done) s1_valid <= 0;
            if (rd_hit) begin st_rd_hit <= st_rd_hit + 1; lru[s1_set] <= hit0; end
            if (wr_done) begin
                st_wr <= st_wr + 1; if (hit) begin st_wr_hit <= st_wr_hit + 1; lru[s1_set] <= hit0; end
                wb_a[wb_wp] <= s1_addr; wb_d[wb_wp] <= s1_wd; wb_b[wb_wp] <= s1_be; wb_wp <= wb_wp + 1;
            end
            // ---- falha de leitura: preenchimento
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
                    lru[s1_set] <= ~fvict; fs <= F_NORMAL; s1_ok <= 0;   // um clock de espera: releitura de s1_addr
                end
                default: fs <= F_NORMAL;
            endcase
            if (fs == F_NORMAL && s1_valid && !s1_ok && !rd_miss && !wr_done) s1_ok <= 1;   // dados relidos
            // ---- dreno do buffer de escrita (so quando nao ha preenchimento em curso)
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
