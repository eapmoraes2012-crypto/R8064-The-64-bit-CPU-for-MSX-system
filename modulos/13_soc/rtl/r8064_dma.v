// r8064_dma.v - DMA de 4 canais do R8064. Um unico mestre de memoria fisica (palavras de 64 bits, 8 MB), atendendo os canais em rodizio (uma palavra por vez).
//
// Programacao (registradores de controle escritos por MTCR = ED 0C n, com AX; o nucleo repassa a escrita em CR19..CR30):
//   canal 0: CR19 SRC | CR20 DST | CR21 CTRL     canal 1: CR22 SRC | CR23 DST | CR24 CTRL
//   canal 2: CR25 SRC | CR26 DST | CR27 CTRL     canal 3: CR28 SRC | CR29 DST | CR30 CTRL
//   (cr_idx = n - 19 = 0..11; MFCR devolve o ultimo valor escrito, que fica no banco de registradores do nucleo)
//   SRC / DST : endereco FISICO em bytes (usa os bits [22:3]: alinhado a palavra de 64 bits, 8 MB); bit 23 = buffer da janela; bits [63:24] != 0 -> erro ao iniciar
//   CTRL      : [18:0] COUNT em palavras de 64 bits (0 = nada a fazer) | [20:19] MODO | [31] START (so inicia com o canal parado)
//   JANELA DE TROCA MSX (REV46): SRC ou DST com o bit 23 = 1 (endereco 800000h..803FFFh) aponta o buffer de 16 KB da janela 8000h-BFFFh (2048 palavras; so no MODO 0).
//     Um unico lado pode ser o buffer; offset + COUNT <= 2048 palavras; senao ERRO. O DMA espera (stall) enquanto a janela pertence ao MSX (b_ok = 0).
//     Buffer<->SDRAM transfere 1 palavra de 64 bits por transacao de memoria (sem serializar bytes como nos modos FIFO).
//   MODO 0 = memoria -> memoria | 1 = memoria -> FIFO R8064->MSX (SRC) | 2 = FIFO MSX->R8064 -> memoria (DST) | 3 = reservado (erro)
//   Nos modos 1 e 2 cada palavra e transferida como 8 bytes, byte menos significativo primeiro; o canal espera o FIFO ter dado/espaco.
//   A leitura de volta (MFCR) devolve o ultimo valor escrito, nao o ponteiro corrente.
// DESEMPENHO (REV43): o motor nao passa por estados ociosos entre palavras (o proximo canal do rodizio e escolhido no clock em que a palavra termina);
//   no MODO 0 com origem na janela a proxima palavra e lida do buffer enquanto a escrita na SDRAM esta em curso (quando so ha um canal ativo);
//   com destino na janela, a palavra lida da SDRAM e gravada no buffer no proprio clock do 'done'. O limite passa a ser a SDRAM (ver teste_dma_win.txt).
// Portas de E/S (parametros): PORT_STAT (EEh, canais 0 e 1), PORT_IE (EFh), PORT_STAT2 (EDh, canais 2 e 3)
//   STAT  leitura : b0 ATIVO0, b1 CONCLUIDO0, b2 ERRO0, b3 IRQ pendente (qualquer canal), b4 ATIVO1, b5 CONCLUIDO1, b6 ERRO1
//   STAT2 leitura : o mesmo para os canais 2 (b0..b2) e 3 (b4..b6)
//   STAT/STAT2 escrita : b0 limpa CONCLUIDO/ERRO do canal par | b1 aborta o canal par (CONCLUIDO + ERRO) | b4 e b5: o mesmo para o canal impar
//   IE leitura/escrita: b0..b3 habilitam a IRQ dos canais 0..3 (irq = CONCLUIDO & IE)
// Coerencia: a cache de dados e write-through sem alocar na escrita e nao enxerga escritas do DMA. Ao fim de uma transferencia que escreve em memoria
//   (modos 0 e 2) e ao abortar um canal ativo, o DMA emite o pulso 'inv' (invalida as caches). Antes de iniciar uma leitura de dados escritos pelo nucleo, use FENCE (ED A5).
module r8064_dma #(parameter PORT_STAT = 8'hEE, parameter PORT_IE = 8'hEF, parameter PORT_STAT2 = 8'hED)(
    input  wire        clk, rst,
    input  wire        cr_we, input wire [3:0] cr_idx, input wire [63:0] cr_wd,
    input  wire        io_we, io_re, input wire [7:0] io_a, io_wd, output wire [7:0] io_rd, output wire io_sel,
    // mestre de memoria fisica (indice de palavra de 64 bits; protocolo do arbitro: req ate acc, depois espera done)
    output wire        m_req, m_we, output wire [19:0] m_addr, output wire [63:0] m_wd, output wire [7:0] m_be,
    input  wire        m_acc, m_done, input wire [63:0] m_rd,
    // FIFOs (dispositivo)
    input  wire        a_avail, input wire [7:0] a_q, input wire b_space,
    output wire        d_pop, d_push, output wire [7:0] d_wd,
    // buffer da janela MSX (porta do lado do DMA; leitura com 1 clock de latencia)
    input  wire        b_ok, output wire b_re, b_we, output wire [10:0] b_a, output wire [63:0] b_wd, input wire [63:0] b_q,
    output wire        irq,
    output reg         inv,
    // boot: carrega o canal 0 (buffer offset 0 -> SDRAM 0, boot_cnt palavras, MODO 0) sem passar pelo nucleo
    input  wire        boot_go, input wire [18:0] boot_cnt, output wire boot_done, input wire boot_clr
);
    reg [20:0] s_r [0:3]; reg [20:0] d_r [0:3]; reg [3:0] s_bad, d_bad;
    reg [20:0] w_src [0:3]; reg [20:0] w_dst [0:3]; reg [18:0] cnt [0:3]; reg [1:0] md_r [0:3];
    reg [3:0] act, done, err, ie;
    reg [1:0] cur, last; reg lp; reg [3:0] st; reg [2:0] k; reg [63:0] dbuf;
    localparam E_IDLE = 4'd0, E_RRQ = 4'd1, E_RWT = 4'd2, E_WRQ = 4'd3, E_WWT = 4'd4, E_PUSH = 4'd5, E_POP = 4'd6, E_NEXT = 4'd7, E_RWB = 4'd8;
    wire [1:0]  md    = md_r[cur];
    wire [20:0] c_src = w_src[cur], c_dst = w_dst[cur];
    wire sbuf = c_src[20] && (md == 2'd0), dbuf_b = c_dst[20] && (md == 2'd0);
    wire [18:0] c_cnt = cnt[cur];   // sbuf/dbuf_b: acesso ao buffer da janela (so MODO 0)
    wire       last_w = (c_cnt == 19'd1);                       // a palavra corrente e a ultima do bloco
    // destino na janela com a palavra lida da SDRAM: grava no buffer no clock do 'done' (sem passar por dbuf/E_WRQ)
    wire       direct_bw = (st == E_RWT) && m_done && dbuf_b && b_ok && act[cur];
    // origem na janela: a escrita na SDRAM e requisitada ja no clock em que b_q chega (E_RWB), sem passar por E_WRQ
    wire       rwb_w  = (st == E_RWB) && act[cur] && !dbuf_b;
    assign m_req  = ((st == E_RRQ) && !sbuf) || ((st == E_WRQ) && !dbuf_b) || rwb_w;
    assign m_we   = (st == E_WRQ) || (st == E_RWB);
    assign m_addr = (st == E_WRQ || st == E_RWB) ? c_dst[19:0] : c_src[19:0];
    assign b_re   = (st == E_RRQ) && sbuf && b_ok;
    assign b_we   = direct_bw || ((st == E_WRQ) && dbuf_b && b_ok);
    assign b_a    = ((st == E_WRQ) || (st == E_RWT)) ? c_dst[10:0] : c_src[10:0];
    assign b_wd   = (st == E_RWT) ? m_rd : dbuf;
    assign m_wd   = (st == E_RWB) ? b_q : dbuf; assign m_be = 8'hFF;
    assign d_push = (st == E_PUSH) && b_space && act[cur];
    assign d_pop  = (st == E_POP) && a_avail && act[cur] && !lp;   // no maximo 1 byte a cada 2 clocks (o FIFO le o proximo byte com 1 clock de atraso)
    assign d_wd   = dbuf[7:0];
    assign boot_done = done[0];
    assign irq    = |(done & ie);
    assign io_sel = (io_a == PORT_STAT) || (io_a == PORT_IE) || (io_a == PORT_STAT2);
    wire irqp = |(done & ie);
    assign io_rd  = (io_a == PORT_IE)    ? {4'd0, ie} :
                    (io_a == PORT_STAT2) ? {1'b0, err[3], done[3], act[3], irqp, err[2], done[2], act[2]} :
                                           {1'b0, err[1], done[1], act[1], irqp, err[0], done[0], act[0]};
    function bad_f(input [1:0] m, input sb, input db, input sbf, input dbf);
        bad_f = (m == 2'd3) | ((m == 2'd0) & (sb | db)) | ((m == 2'd1) & sb) | ((m == 2'd2) & db)
              | ((m != 2'd0) & (sbf | dbf)) | (sbf & dbf);
    endfunction
    // decodificacao do indice de CR: canal = idx/3, campo = idx%3 (0 SRC, 1 DST, 2 CTRL)
    reg [1:0] cch; reg [1:0] cfd;
    always @* case (cr_idx)
        4'd0: begin cch = 0; cfd = 0; end 4'd1: begin cch = 0; cfd = 1; end 4'd2: begin cch = 0; cfd = 2; end
        4'd3: begin cch = 1; cfd = 0; end 4'd4: begin cch = 1; cfd = 1; end 4'd5: begin cch = 1; cfd = 2; end
        4'd6: begin cch = 2; cfd = 0; end 4'd7: begin cch = 2; cfd = 1; end 4'd8: begin cch = 2; cfd = 2; end
        4'd9: begin cch = 3; cfd = 0; end 4'd10: begin cch = 3; cfd = 1; end default: begin cch = 3; cfd = 2; end
    endcase
`ifdef R8064_DMA2
    // Build da Tang Nano 20K (nao cabe com 4 canais): so os canais 0 e 1 (CR19..CR24) existem; escritas em CR25..CR30 sao ignoradas e o yosys remove os canais 2 e 3.
    wire cr_ok = cr_we && cr_idx <= 4'd5;
`else
    wire cr_ok = cr_we && cr_idx <= 4'd11;
`endif
    wire go  = cr_ok && cfd == 2'd2 && cr_wd[31] && !act[cch];
    wire rsv = cr_wd[21] | (|cr_wd[62:32]);  // VIRT e COUNT alto: reservados para 64 bits
    // offset + COUNT > 2048 palavras (16 KB): verificado UM CLOCK DEPOIS do START, so com registradores (fora do caminho de cr_wd, que chega tarde do nucleo)
    reg        ovf_p; reg [1:0] ovf_c;
    wire [11:0] boff = w_src[ovf_c][20] ? {1'b0, w_src[ovf_c][10:0]} : {1'b0, w_dst[ovf_c][10:0]};
    wire        bovf = (w_src[ovf_c][20] | w_dst[ovf_c][20]) && (({1'b0, boff} + {1'b0, cnt[ovf_c]}) > 20'd2048);
    wire bad = rsv | bad_f(cr_wd[20:19], s_bad[cch], d_bad[cch], s_r[cch][20], d_r[cch][20]);
    wire z   = (cr_wd[18:0] == 19'd0);
    // proximo canal ativo em rodizio, a partir de last+1
    wire [1:0] c1 = last + 2'd1, c2 = last + 2'd2, c3 = last + 2'd3;
    wire [1:0] nxt = act[c1] ? c1 : act[c2] ? c2 : act[c3] ? c3 : last;
    wire [1:0] mdn = md_r[nxt];
    // palavra concluida neste clock: avanca ponteiros e ja escolhe o proximo canal (sem estados ociosos)
    wire       fin = ((st == E_WWT) && m_done) || ((st == E_WRQ) && dbuf_b && b_ok) || direct_bw || ((st == E_PUSH) && act[cur] && b_space && k == 3'd7);
    wire [3:0] actf = last_w ? (act & ~(4'b0001 << cur)) : act;
    wire [1:0] f1 = cur + 2'd1, f2 = cur + 2'd2, f3 = cur + 2'd3;
    wire [1:0] fn = actf[f1] ? f1 : actf[f2] ? f2 : actf[f3] ? f3 : cur;
    wire       fany = |actf;
    wire [1:0] fmd = md_r[fn];
    wire [1:0] ioch = {(io_a == PORT_STAT2), 1'b0};     // base do par de canais da porta de STAT
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            ovf_p <= 1'b0; ovf_c <= 2'd0; act <= 4'd0; done <= 4'd0; err <= 4'd0; ie <= 4'd0; st <= E_IDLE; cur <= 2'd0; last <= 2'd3; lp <= 1'b0; k <= 3'd0; inv <= 1'b0;
            s_bad <= 4'd0; d_bad <= 4'd0; dbuf <= 64'd0;
            for (i = 0; i < 4; i = i + 1) begin s_r[i] <= 21'd0; d_r[i] <= 21'd0; w_src[i] <= 21'd0; w_dst[i] <= 21'd0; cnt[i] <= 19'd0; md_r[i] <= 2'd0; end
        end else begin
            inv <= 1'b0; lp <= d_pop;
            ovf_p <= go && !bad && !z; ovf_c <= cch;
            if (ovf_p && bovf && act[ovf_c]) begin act[ovf_c] <= 1'b0; done[ovf_c] <= 1'b1; err[ovf_c] <= 1'b1; end
            // ---- escritas de registradores de controle ----
            if (cr_ok && cfd == 2'd0) begin s_r[cch] <= {cr_wd[23], cr_wd[22:3]}; s_bad[cch] <= (|cr_wd[63:24]) | (cr_wd[23] & (|cr_wd[22:14])) | (cr_wd[23] & (|cr_wd[2:0])); end
            if (cr_ok && cfd == 2'd1) begin d_r[cch] <= {cr_wd[23], cr_wd[22:3]}; d_bad[cch] <= (|cr_wd[63:24]) | (cr_wd[23] & (|cr_wd[22:14])) | (cr_wd[23] & (|cr_wd[2:0])); end
            if (go) begin
                w_src[cch] <= s_r[cch]; w_dst[cch] <= d_r[cch]; cnt[cch] <= cr_wd[18:0]; md_r[cch] <= cr_wd[20:19]; done[cch] <= 1'b0; err[cch] <= 1'b0;
                if (bad) begin err[cch] <= 1'b1; done[cch] <= 1'b1; end
                else if (z) done[cch] <= 1'b1;
                else act[cch] <= 1'b1;
            end
            if (boot_clr) begin done[0] <= 1'b0; err[0] <= 1'b0; end
            if (boot_go) begin w_src[0] <= 21'h100000; w_dst[0] <= 21'd0; cnt[0] <= boot_cnt; md_r[0] <= 2'd0; done[0] <= 1'b0; err[0] <= 1'b0; act[0] <= 1'b1; end
            // ---- portas de E/S ----
            if (io_we && io_a == PORT_IE) ie <= io_wd[3:0];
            if (io_we && (io_a == PORT_STAT || io_a == PORT_STAT2)) begin
                if (io_wd[0]) begin done[ioch] <= 1'b0; err[ioch] <= 1'b0; end
                if (io_wd[4]) begin done[ioch | 2'd1] <= 1'b0; err[ioch | 2'd1] <= 1'b0; end
                if (io_wd[1] && act[ioch]) begin act[ioch] <= 1'b0; done[ioch] <= 1'b1; err[ioch] <= 1'b1; inv <= 1'b1; end
                if (io_wd[5] && act[ioch | 2'd1]) begin act[ioch | 2'd1] <= 1'b0; done[ioch | 2'd1] <= 1'b1; err[ioch | 2'd1] <= 1'b1; inv <= 1'b1; end
            end
            // ---- motor de transferencia ----
            if (fin && act[cur]) begin
                if (md != 2'd2) w_src[cur] <= w_src[cur] + 21'd1;
                if (md != 2'd1) w_dst[cur] <= w_dst[cur] + 21'd1;
                cnt[cur] <= cnt[cur] - 19'd1;
                if (last_w) begin act[cur] <= 1'b0; done[cur] <= 1'b1; if (md != 2'd1) inv <= 1'b1; end
                last <= cur; k <= 3'd0;
                if (fany) begin cur <= fn; st <= (fmd == 2'd2) ? E_POP : E_RRQ; end else st <= E_IDLE;
            end else case (st)
                E_IDLE: if (act != 4'd0) begin cur <= nxt; k <= 3'd0; st <= (mdn == 2'd2) ? E_POP : E_RRQ; end
                E_RRQ: if (sbuf) begin if (b_ok) st <= E_RWB; end else if (m_acc) st <= E_RWT;
                E_RWB: begin dbuf <= b_q; k <= 3'd0; st <= !act[cur] ? E_NEXT : (rwb_w && m_acc) ? E_WWT : E_WRQ; end   // so MODO 0
                E_RWT: if (m_done) begin
                           dbuf <= m_rd; k <= 3'd0;
                           st <= !act[cur] ? E_NEXT : (md == 2'd0) ? E_WRQ : E_PUSH;
                       end
                E_WRQ: if (!dbuf_b && m_acc) st <= E_WWT;
                E_WWT: if (m_done) st <= E_NEXT;   // so chega aqui com o canal abortado (senao 'fin')
                E_PUSH: if (!act[cur]) st <= E_NEXT;
                        else if (b_space) begin dbuf <= {8'd0, dbuf[63:8]}; k <= k + 3'd1; end
                E_POP:  if (!act[cur]) st <= E_NEXT;
                        else if (a_avail && !lp) begin dbuf <= {a_q, dbuf[63:8]}; k <= k + 3'd1; if (k == 3'd7) st <= E_WRQ; end
                E_NEXT: begin last <= cur; st <= E_IDLE; end   // so abortos (canal ja inativo)
                default: st <= E_IDLE;
            endcase
        end
    end
endmodule
