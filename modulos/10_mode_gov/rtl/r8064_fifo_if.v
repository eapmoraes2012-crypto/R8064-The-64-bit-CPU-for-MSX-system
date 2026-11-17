// r8064_fifo_if.v - interface de FIFOs MSX <-> R8064 por registradores de E/S (protocolo da aba "Pinagem MSX", secao 3).
//
// Lado R8064 (portas BASE..BASE+4, padrao BASE = E8h; as portas antigas F0h-F4h colidiam com F3h = modo de tela do MSX2+ e F4h = flag de inicializacao):
//   BASE+0 DATA     : IN = proximo byte do FIFO MSX->R8064 | OUT = empilha no FIFO R8064->MSX
//   BASE+1 STATUS   : IN: b0 ha dado para ler (FIFO MSX->R8064 nao vazio), b1 ha espaco para escrever (FIFO R8064->MSX nao cheio)
//   BASE+2 LEN_L    : comprimento do bloco, byte baixo (compartilhado com o MSX)
//   BASE+3 LEN_H    : byte alto
//   BASE+4 FLAGS    : IN: b0 INICIAR recebido, b1 ocupado, b2 CONCLUIDO, b3 JANELA (1 = o buffer de 16 KB e do MSX) | OUT: b0=1 limpa INICIAR; b1 = valor de "ocupado"; b2=1 marca CONCLUIDO (e devolve a janela ao MSX)
// Lado MSX (offset 0..3 = DATA, STATUS/CMD, LEN_L, LEN_H; a base no slot do MSX e escolhida fora, na decodificacao da porta):
//   DATA   : IN = proximo byte do FIFO R8064->MSX | OUT = empilha no FIFO MSX->R8064
//   STATUS : IN: b0 ha dado para ler, b1 ha espaco para escrever, b2 R8064 ocupado, b3 CONCLUIDO, b4 IRQ pendente, b5 JANELA (do MSX), b6 ERRO (estouro/esvaziamento de FIFO; limpo por CMD.b1), b7 = 0
//   CMD    : OUT: b0 INICIAR (no mesmo ciclo: ocupado = 1, CONCLUIDO = 0, JANELA = 0), b1 limpa os FIFOs e o ERRO, b2 habilita IRQ, b3 reinicia o R8064 (pulso; devolve a janela), b7 limpa CONCLUIDO/IRQ
// JANELA (REV46): registrador de posse do buffer de 16 KB (r8064_xbuf). Reset = 1 (MSX). INICIAR zera; CONCLUIDO do R8064 ou reinicio do R8064 devolvem 1.
// Porta de dispositivo do DMA (REV43): d_pop/d_push/d_wd/a_avail/a_q/b_space usam os mesmos FIFOs (modos 1 e 2 do r8064_dma).
// As portas de entrada devem ser lidas na MESMA fase do pulso *_re (dado combinacional); cada FIFO tem 2048 bytes (1 BSRAM cada).
module r8064_fifo_if #(parameter BASE = 8'hE8, parameter AW = 11)(
    input  wire       clk, rst,
    // lado R8064 (barramento de E/S do sistema)
    input  wire       r_we, r_re, input wire [7:0] r_a, r_wd, output reg [7:0] r_rd, output wire r_hit,
    // lado MSX (slot, ja sincronizado ao clk)
    input  wire       m_we, m_re, input wire [1:0] m_a, input wire [7:0] m_wd, output reg [7:0] m_rd,
    output wire       m_irq,        // linha INT do slot (coletor aberto fora)
    output reg        r8064_rst,    // pulso de reinicio do R8064 (CMD.b3)
    output wire       win,          // 1 = o buffer de 16 KB pertence ao MSX (JANELA)
    // porta de dispositivo do DMA (os mesmos FIFOs; o DMA so pede d_pop com a_avail e d_push com b_space)
    input  wire       d_pop, d_push, input wire [7:0] d_wd, output wire a_avail, output wire [7:0] a_q, output wire b_space
);
    localparam DEPTH = 1 << AW;
    // BASE deve ser multiplo de 8 (E8h, F0h...): decodificacao por comparacao de 5 bits + 3 bits (sem subtrator)
    wire [2:0] off3 = r_a[2:0];
    wire sel = (r_a[7:3] == BASE[7:3]);
    assign r_hit = sel && (off3 < 3'd5);
    wire off0 = sel && off3 == 3'd0, off1 = sel && off3 == 3'd1, off2 = sel && off3 == 3'd2, off3_ = sel && off3 == 3'd3, off4 = sel && off3 == 3'd4;
    // ---- FIFO A: MSX -> R8064 | FIFO B: R8064 -> MSX ----  (ocupacao mantida por ponteiros incrementais; flags cheio/nao-vazio registrados)
    reg [7:0] ma [0:DEPTH-1]; reg [7:0] mb [0:DEPTH-1];
    reg [AW:0] wa, ra, wb, rb;     // ponteiros com bit extra: vazio = iguais; cheio = iguais exceto o bit extra
    reg full_a, nz_a, nz_a_d, full_b, nz_b, nz_b_d;      // *_d: atrasado de 1 clock (a memoria le com 1 clock de latencia)
    reg [7:0] qa, qb;
    wire clr = m_we && m_a == 2'd1 && m_wd[1];
    wire avail_a = nz_a && nz_a_d;
    wire avail_b = nz_b && nz_b_d;
    wire pop_a  = (r_re && off0 && avail_a) || (d_pop && avail_a);
    wire push_a = m_we && m_a == 2'd0 && !full_a;
    wire push_b = (r_we && off0 && !full_b) || (d_push && !full_b);
    assign a_avail = avail_a; assign a_q = qa; assign b_space = !full_b;
    wire pop_b  = m_re && m_a == 2'd0 && avail_b;
    wire [AW:0] wa_n = push_a ? wa + 1'b1 : wa, ra_n = pop_a ? ra + 1'b1 : ra;
    wire [AW:0] wb_n = push_b ? wb + 1'b1 : wb, rb_n = pop_b ? rb + 1'b1 : rb;
    wire emp_a_n = (wa_n == ra_n), fl_a_n = (wa_n[AW-1:0] == ra_n[AW-1:0]) && (wa_n[AW] != ra_n[AW]);
    wire emp_b_n = (wb_n == rb_n), fl_b_n = (wb_n[AW-1:0] == rb_n[AW-1:0]) && (wb_n[AW] != rb_n[AW]);
    always @(posedge clk) begin
        if (push_a) ma[wa[AW-1:0]] <= m_wd;
        if (push_b) mb[wb[AW-1:0]] <= d_push ? d_wd : r_wd;
        qa <= ma[ra_n[AW-1:0]];
        qb <= mb[rb_n[AW-1:0]];
    end
    always @(posedge clk) begin
        if (rst || clr) begin
            wa <= 0; ra <= 0; wb <= 0; rb <= 0;
            full_a <= 0; nz_a <= 0; nz_a_d <= 0; full_b <= 0; nz_b <= 0; nz_b_d <= 0;
        end else begin
            wa <= wa_n; ra <= ra_n; wb <= wb_n; rb <= rb_n;
            full_a <= fl_a_n; nz_a <= !emp_a_n; nz_a_d <= nz_a;
            full_b <= fl_b_n; nz_b <= !emp_b_n; nz_b_d <= nz_b;
        end
    end
    // ---- registradores compartilhados ----
    reg [7:0] len_l, len_h; reg start_p, busy, done, irq_en, wnd, err;
    wire irq_pend = done && irq_en;
    always @(posedge clk) begin
        if (rst) begin len_l <= 0; len_h <= 0; start_p <= 0; busy <= 0; done <= 0; irq_en <= 0; r8064_rst <= 0; wnd <= 1; end
        else begin
            r8064_rst <= 1'b0;
            if (m_we && m_a == 2'd2) len_l <= m_wd;
            if (r_we && off2) len_l <= r_wd;
            if (m_we && m_a == 2'd3) len_h <= m_wd;
            if (r_we && off3_) len_h <= r_wd;
            if (m_we && m_a == 2'd1) begin
                if (m_wd[0]) begin start_p <= 1'b1; done <= 1'b0; busy <= 1'b1; wnd <= 1'b0; end
                irq_en <= m_wd[2];
                if (m_wd[3]) begin r8064_rst <= 1'b1; wnd <= 1'b1; end
                if (m_wd[7]) done <= 1'b0;
            end
            if (r_we && off4) begin
                if (r_wd[0]) start_p <= 1'b0;
                busy <= r_wd[1];
                if (r_wd[2]) begin done <= 1'b1; busy <= 1'b0; wnd <= 1'b1; end
            end
        end
    end
    // ERRO: estouro (escrita com FIFO cheio) ou esvaziamento (leitura com FIFO vazio); so o CMD.b1 (limpa FIFOs) o apaga
    wire ovf_a = m_we && m_a == 2'd0 && full_a, ovf_b = r_we && off0 && full_b;
    wire und_a = r_re && off0 && !avail_a, und_b = m_re && m_a == 2'd0 && !avail_b;
    always @(posedge clk) begin
        if (rst || clr) err <= 1'b0;
        else if (ovf_a || ovf_b || und_a || und_b) err <= 1'b1;
    end
    assign win = wnd;
    assign m_irq = irq_pend;
    // ---- leituras (combinacionais) ----
    always @* begin
        case (off3)
            3'd0: r_rd = avail_a ? qa : 8'h00;
            3'd1: r_rd = {6'd0, !full_b, avail_a};
            3'd2: r_rd = len_l;
            3'd3: r_rd = len_h;
            default: r_rd = {4'd0, wnd, done, busy, start_p};
        endcase
        case (m_a)
            2'd0: m_rd = avail_b ? qb : 8'h00;
            2'd1: m_rd = {1'b0, err, wnd, irq_pend, done, busy, !full_a, avail_b};
            2'd2: m_rd = len_l;
            default: m_rd = len_h;
        endcase
    end
endmodule
