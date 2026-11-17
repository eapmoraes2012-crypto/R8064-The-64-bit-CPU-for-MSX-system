`timescale 1ns/1ps
// Teste da janela de troca MSX <-> R8064 (REV46): slot_dec (portas 0Bh/0Ch/0Dh) + fifo_if (WINDOW/ERROR) + xbuf (16 KB) + DMA (abertura de endereco bit 23) + arbitro + SDRAM.
module tb_dma_win;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg cr_we = 0; reg [3:0] cr_idx = 0; reg [63:0] cr_wd = 0;
    reg io_we = 0, io_re = 0; reg [7:0] io_a = 0, io_wd = 0; wire [7:0] io_rd; wire io_sel;
    wire m_req, m_we, m_acc, m_done; wire [19:0] m_addr; wire [63:0] m_wd, m_rd; wire [7:0] m_be;
    wire a_avail, b_space, d_pop, d_push; wire [7:0] a_q, d_wd; wire irq, inv;
    wire win, xb_re, xb_we; wire [10:0] xb_a; wire [63:0] xb_wd, xb_q;
    r8064_dma dma(.clk(clk), .rst(rst), .cr_we(cr_we), .cr_idx(cr_idx), .cr_wd(cr_wd), .io_we(io_we), .io_re(io_re), .io_a(io_a), .io_wd(io_wd), .io_rd(io_rd), .io_sel(io_sel),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wd(m_wd), .m_be(m_be), .m_acc(m_acc), .m_done(m_done), .m_rd(m_rd),
        .a_avail(a_avail), .a_q(a_q), .b_space(b_space), .d_pop(d_pop), .d_push(d_push), .d_wd(d_wd),
        .b_ok(!win), .b_re(xb_re), .b_we(xb_we), .b_a(xb_a), .b_wd(xb_wd), .b_q(xb_q), .irq(irq), .inv(inv));
    // lado MSX: slot_dec -> fifo_if
    reg sp_we = 0, sp_re = 0; reg [7:0] sp_a = 0, sp_wd = 0; wire [7:0] sp_rd; wire sp_hit;
    wire fm_we, fm_re; wire [1:0] fm_a; wire [7:0] fm_wd, fm_rd; wire fm_irq, fm_rst, r_hit; wire [7:0] r_rd;
    reg r_we = 0, r_re = 0; reg [7:0] r_a = 0, r_wd = 0;
    r8064_slot_dec sdec(.clk(clk), .rst(rst), .io_we(sp_we), .io_re(sp_re), .io_a(sp_a), .io_wd(sp_wd), .io_rd(sp_rd), .io_hit(sp_hit),
        .fm_we(fm_we), .fm_re(fm_re), .fm_a(fm_a), .fm_wd(fm_wd), .fm_rd(fm_rd));
    r8064_fifo_if fifo(.clk(clk), .rst(rst), .r_we(r_we), .r_re(r_re), .r_a(r_a), .r_wd(r_wd), .r_rd(r_rd), .r_hit(r_hit),
        .m_we(fm_we), .m_re(fm_re), .m_a(fm_a), .m_wd(fm_wd), .m_rd(fm_rd), .m_irq(fm_irq), .r8064_rst(fm_rst), .win(win),
        .d_pop(d_pop), .d_push(d_push), .d_wd(d_wd), .a_avail(a_avail), .a_q(a_q), .b_space(b_space));
    // buffer
    reg sb_we = 0, sb_re = 0; reg [13:0] sb_a = 0; reg [7:0] sb_wd = 0; wire [7:0] sb_rd;
    r8064_xbuf xbuf(.clk(clk), .win(win), .s_we(sb_we), .s_re(sb_re), .s_a(sb_a), .s_wd(sb_wd), .s_rd(sb_rd), .d_re(xb_re), .d_we(xb_we), .d_a(xb_a), .d_wd(xb_wd), .d_q(xb_q));
    // memoria
    wire [4:0] acc, done; wire [63:0] arb_rd; wire c_req, c_we, c_ready, c_rvalid, c_wdone; wire [19:0] c_addr; wire [63:0] c_wd, c_rd; wire [7:0] c_be;
    mem_arb5 arb(.clk(clk), .rst(rst), .req({m_req, 4'b0}), .we({m_we, 4'b0}), .addr({m_addr, 80'd0}), .wdata({m_wd, 256'd0}), .be({m_be, 32'd0}),
        .acc(acc), .done(done), .rdata(arb_rd), .c_req(c_req), .c_we(c_we), .c_addr(c_addr), .c_wdata(c_wd), .c_be(c_be), .c_ready(c_ready), .c_rvalid(c_rvalid), .c_rdata(c_rd), .c_wdone(c_wdone));
    assign m_acc = acc[4]; assign m_done = done[4]; assign m_rd = arb_rd;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe, init_done; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o, mdq;
    sdram_ctrl #(.INIT_CYC(2000)) sd(.clk(clk), .rst(rst), .req(c_req), .we(c_we), .addr(c_addr), .wdata(c_wd), .be(c_be), .ready(c_ready), .rvalid(c_rvalid), .rdata(c_rd), .wdone(c_wdone),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a), .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(mdq));
    sdram_model mdl(.clk(clk), .cke(s_cke), .cs_n(s_cs_n), .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm), .ba(s_ba), .a(s_a), .dq_i(s_dq_o), .dq_oe(s_dq_oe), .dq_o(mdq));
    // utilitarios
    integer errs = 0, i;
    task crw(input [3:0] idx, input [63:0] v); begin @(posedge clk); #1 cr_idx = idx; cr_wd = v; cr_we = 1; @(posedge clk); #1 cr_we = 0; end endtask
    task iow(input [7:0] a, input [7:0] d); begin @(posedge clk); #1 io_a = a; io_wd = d; io_we = 1; @(posedge clk); #1 io_we = 0; end endtask
    task ior(input [7:0] a, output [7:0] d); begin @(posedge clk); #1 io_a = a; #1 d = io_rd; end endtask
    task spw(input [7:0] a, input [7:0] d); begin @(posedge clk); #1 sp_a = a; sp_wd = d; sp_we = 1; @(posedge clk); #1 sp_we = 0; end endtask
    task spr(input [7:0] a, output [7:0] d); begin @(posedge clk); #1 sp_a = a; sp_re = 1; #1 d = sp_rd; @(posedge clk); #1 sp_re = 0; end endtask
    task sbw(input [13:0] a, input [7:0] d); begin @(posedge clk); #1 sb_a = a; sb_wd = d; sb_we = 1; @(posedge clk); #1 sb_we = 0; end endtask
    task sbr(input [13:0] a, output [7:0] d); begin @(posedge clk); #1 sb_a = a; @(posedge clk); #1 sb_re = 1; #1 d = sb_rd; @(posedge clk); #1 sb_re = 0; end endtask
    task rw(input [7:0] a, input [7:0] d); begin @(posedge clk); #1 r_a = a; r_wd = d; r_we = 1; @(posedge clk); #1 r_we = 0; end endtask
    task chk(input [255:0] nome, input [63:0] got, input [63:0] exp);
        if (got !== exp) begin errs = errs + 1; $display("ERRO %0s: obtido %h esperado %h", nome, got, exp); end
    endtask
    task wait_dma(input integer maxclk); integer c; reg [7:0] s; begin
        c = 0; s = 0; while (!(s[1]) && c < maxclk) begin ior(8'hEE, s); c = c + 1; end
        if (c >= maxclk) begin errs = errs + 1; $display("ERRO: timeout do DMA"); end
    end endtask
    function [63:0] mw(input integer w); mw = {mdl.mem[2*w+1], mdl.mem[2*w]}; endfunction
    function [7:0] bpat(input integer n, input integer salt); bpat = (n * 13 + salt + (n >> 8) * 7) & 255; endfunction
    function [63:0] wpat(input integer w, input integer salt); integer j; begin wpat = 0; for (j = 0; j < 8; j = j + 1) wpat = wpat | (bpat(w*8 + j, salt) << (8*j)); end endfunction
    reg [7:0] st, d8; reg [63:0] e64;
    localparam P_ST = 8'h0B, P_DT = 8'h0C, P_LN = 8'h0D;
    initial begin
        cr_idx = 4'd15; #2 cr_idx = 4'd0;   // força o always @* do decodificador do DMA a avaliar (artefato do simulador com cr_idx inicial = 0)
        repeat (4) @(posedge clk); rst = 0;
        wait (init_done); repeat (10) @(posedge clk);
        // ---- 1) estado apos o reset: WINDOW = 1, SPACE = 1 ----
        spr(P_ST, st); chk("STATUS apos reset (WINDOW|SPACE)", st, 8'h22);
        // ---- 2) assinatura no buffer ----
        sbr(14'd0, d8); chk("sig R", d8, "R"); sbr(14'd1, d8); chk("sig 8", d8, "8"); sbr(14'd2, d8); chk("sig 0", d8, "0");
        sbr(14'd3, d8); chk("sig 6", d8, "6"); sbr(14'd4, d8); chk("sig 4", d8, "4"); sbr(14'd5, d8); chk("versao", d8, 1);
        sbr(14'd6, d8); chk("zero 6", d8, 0); sbr(14'd7, d8); chk("zero 7", d8, 0);
        // ---- 3) MSX escreve os 16 KB; le de volta ----
        for (i = 0; i < 16384; i = i + 1) sbw(i, bpat(i, 1));
        for (i = 0; i < 16384; i = i + 97) begin sbr(i, d8); chk("rel. buffer", d8, bpat(i, 1)); end
        sbr(14'h3FFF, d8); chk("ultimo byte", d8, bpat(16383, 1));
        // ---- 4) START: janela passa ao R8064 ----
        spw(P_ST, 8'h01); spr(P_ST, st); chk("STATUS apos START (BUSY, sem WINDOW)", st & 8'h24, 8'h04);
        sbr(14'd5, d8); chk("leitura sem janela = FF", d8, 8'hFF); sbw(14'd5, 8'h77);
        // ---- 5) DMA buffer -> SDRAM: 2048 palavras para 0x40000 (palavra 0x8000) ----
        crw(0, 64'h80_0000); crw(1, 64'h4_0000); crw(2, 64'h8000_0000 | 2048); wait_dma(400000); ior(8'hEE, st); chk("DMA ch0 concluido sem erro", st & 8'h07, 8'h02); iow(8'hEE, 8'h01);
        for (i = 0; i < 2048; i = i + 13) chk("SDRAM recebeu o buffer", mw(32'h8000 + i), wpat(i, 1));
        // (o byte 5 foi escrito com 77h sem janela: deve ter sido ignorado; i == 0 acima compara palavra 0 com o padrao)
        chk("byte 5 ignorado", mw(32'h8000) >> 40 & 64'hFF, bpat(5, 1));
        // ---- 6) o R8064 marca DONE: janela volta ao MSX ----
        rw(8'hEC, 8'h04); spr(P_ST, st); chk("STATUS apos DONE (WINDOW|DONE|SPACE)", st & 8'h2E, 8'h2A);
        sbr(14'd0, d8); chk("MSX le o buffer de novo", d8, bpat(0, 1)); spw(P_ST, 8'h80);
        spr(P_ST, st); chk("DONE limpo", st & 8'h08, 0);
        // ---- 7) SDRAM -> buffer (WIN_GET): o MSX da START, o DMA preenche, o R8064 da DONE ----
        for (i = 0; i < 2048; i = i + 1) begin mdl.mem[2*(32'h9000+i)] = wpat(i, 5); mdl.mem[2*(32'h9000+i)+1] = wpat(i, 5) >> 32; end
        spw(P_ST, 8'h01);
        crw(0, 64'h4_8000); crw(1, 64'h80_0000); crw(2, 64'h8000_0000 | 2048); wait_dma(400000); iow(8'hEE, 8'h01);
        rw(8'hEC, 8'h04);
        for (i = 0; i < 16384; i = i + 31) begin sbr(i, d8); chk("MSX le o bloco do R8064", d8, bpat(i, 5)); end
        // ---- 8) deslocamento no buffer: 100 palavras de SDRAM 0x9000 para o offset 0x1000 do buffer ----
        spw(P_ST, 8'h01);
        crw(0, 64'h4_8000); crw(1, 64'h80_1000); crw(2, 64'h8000_0000 | 100); wait_dma(20000); ior(8'hEE, st); chk("ch0 offset ok", st & 8'h07, 8'h02); iow(8'hEE, 8'h01);
        rw(8'hEC, 8'h04);
        sbr(14'h1000 + 5, d8); chk("offset 0x1000", d8, bpat(5, 5)); sbr(14'h1000 + 799, d8); chk("ultimo do offset", d8, bpat(799, 5));
        // ---- 9) DMA espera a janela: sem START o DMA fica ativo e conclui depois ----
        crw(0, 64'h80_0000); crw(1, 64'h6_0000); crw(2, 64'h8000_0010);
        repeat (300) @(posedge clk); ior(8'hEE, st); chk("DMA parado (janela do MSX)", st & 8'h03, 8'h01);
        spw(P_ST, 8'h01); wait_dma(20000); ior(8'hEE, st); chk("DMA concluiu apos START", st & 8'h07, 8'h02); iow(8'hEE, 8'h01); rw(8'hEC, 8'h04);
        // ---- 10) erros de configuracao ----
        crw(0, 64'h80_0000); crw(1, 64'h1000); crw(2, 64'h8000_0000 | 2049); ior(8'hEE, st); chk("COUNT > 2048: erro", st & 8'h07, 8'h06); iow(8'hEE, 8'h01);
        crw(0, 64'h80_3F00); crw(1, 64'h1000); crw(2, 64'h8000_0000 | 33); ior(8'hEE, st); chk("offset+COUNT > 2048: erro", st & 8'h07, 8'h06); iow(8'hEE, 8'h01);
        crw(0, 64'h80_3F00); crw(1, 64'h1000); crw(2, 64'h8000_0000 | 32); ior(8'hEE, st); chk("offset+COUNT = 2048: ok (ativo)", st & 8'h04, 0); spw(P_ST, 8'h01); wait_dma(20000); iow(8'hEE, 8'h01); rw(8'hEC, 8'h04);
        crw(0, 64'h80_0000); crw(1, 64'h80_0000); crw(2, 64'h8000_0010); ior(8'hEE, st); chk("buffer -> buffer: erro", st & 8'h07, 8'h06); iow(8'hEE, 8'h01);
        crw(0, 64'h80_4000); crw(1, 64'h1000); crw(2, 64'h8000_0010); ior(8'hEE, st); chk("endereco acima de 16 KB: erro", st & 8'h07, 8'h06); iow(8'hEE, 8'h01);
        crw(0, 64'h80_0000); crw(1, 64'h1000); crw(2, 64'h8008_0010); ior(8'hEE, st); chk("buffer em modo FIFO: erro", st & 8'h07, 8'h06); iow(8'hEE, 8'h01);
        crw(0, 64'h80_0004); crw(1, 64'h1000); crw(2, 64'h8000_0010); ior(8'hEE, st); chk("buffer desalinhado: erro", st & 8'h07, 8'h06); iow(8'hEE, 8'h01);
        // ---- 11) ponteiro de LEN (porta 0Dh) ----
        spw(P_LN, 8'h34); spw(P_LN, 8'h12); r_a = 8'hEA; #1 chk("LEN_L", r_rd, 8'h34); r_a = 8'hEB; #1 chk("LEN_H", r_rd, 8'h12);
        spr(P_LN, d8); chk("le LEN_L", d8, 8'h34); spr(P_LN, d8); chk("le LEN_H", d8, 8'h12);
        spw(P_LN, 8'h55);                 // ponteiro em LEN_H
        spw(P_ST, 8'h02);                 // limpa: ponteiro volta a LEN_L
        spw(P_LN, 8'h66); r_a = 8'hEA; #1 chk("LEN_L apos limpar", r_rd, 8'h66);
        // ---- 12) ERROR: leitura com FIFO vazio; limpeza pelo COMANDO ----
        spr(P_ST, st); chk("sem ERROR", st & 8'h40, 0);
        spr(P_DT, d8); spr(P_ST, st); chk("ERROR apos underflow", st & 8'h40, 8'h40);
        spw(P_ST, 8'h02); spr(P_ST, st); chk("ERROR limpo", st & 8'h40, 0);
        // ---- 13) FIFO de dados pelas portas: MSX -> R8064 ----
        for (i = 0; i < 5; i = i + 1) spw(P_DT, 8'h20 + i);
        spr(P_ST, st); chk("DATA do R8064 sem dado ainda", st & 8'h01, 0);
        r_a = 8'hE8; for (i = 0; i < 5; i = i + 1) begin #1 chk("R8064 le FIFO", r_rd, 8'h20 + i); @(posedge clk); #1 r_re = 1; @(posedge clk); #1 r_re = 0; end
        // ---- 14) START/BUSY/DONE/FLAGS e reinicio ----
        spw(P_ST, 8'h01); r_a = 8'hEC; #1 chk("FLAGS: START, busy, sem WINDOW", r_rd, 8'h03);
        rw(8'hEC, 8'h01); rw(8'hEC, 8'h04); r_a = 8'hEC; #1 chk("FLAGS apos DONE", r_rd, 8'h0C);
        spw(P_ST, 8'h01); spw(P_ST, 8'h08); spr(P_ST, st); chk("reinicio devolve a janela", st & 8'h20, 8'h20);
        chk("violacoes SDRAM", mdl.viol, 0);
        if (errs == 0) $display("RESULTADO: JANELA OK"); else $display("RESULTADO: %0d ERROS", errs);
        $finish;
    end
    initial begin #400000000; $display("RESULTADO: TIMEOUT GLOBAL"); $finish; end
endmodule
